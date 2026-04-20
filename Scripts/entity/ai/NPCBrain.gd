class_name NPCBrain
extends Node

# NPC 大脑组件
# 职责：
# 1. 管理 NPC 的行为状态机 (FSM)。
# 2. 决策 NPC 的下一步行动 (游荡、工作、交互)。
# 3. 通过 HumanNPC 的 command_* 接口下达指令，模拟玩家操作。
#
# 依赖：
# - 必须作为 HumanNPC 的子节点。
# - 依赖 TerrainObjectManager 进行环境感知。

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

enum State { IDLE, WANDER, WORK, INTERACT }

# 配置参数
@export var wander_radius: float = 300.0 # 游荡半径
@export var detection_radius: float = 500.0 # 资源感知半径
@export var idle_time_min: float = 2.0 # 最小空闲时间
@export var idle_time_max: float = 5.0 # 最大空闲时间
@export var work_tags: Array[String] = ["tree", "stone", "grass"] # 工作目标类型（按优先级扫描）
@export var interaction_approach_distance: float = 10.0 # 接近到该距离后触发一次“脱困判定”（停止移动并重新评估下一步），不用于放宽交互距离（不能超过被交互物behit中定义的最大交互范围）

# 内部状态
var current_state: State = State.IDLE
var timer: Timer
var owner_npc: HumanNPC
var terrain_object_manager: Node

var _target_interaction_component: InteractionComponent = null # 当前交互目标组件
var _target_tile: Vector2i = Vector2i(-1, -1) # 当前交互目标地块 (需先实例化)
var _target_action: StringName = &"chop" # 当前目标所需动作（chop/mine/gather）
var _target_world_pos: Vector2 = Vector2.ZERO # 目标世界坐标（用于“接近即交互”）
var _has_target_world_pos: bool = false

func _get_action_for_tag(tag: String) -> StringName:
	# 资源类型 -> 动作映射（与 BeHit.actions 和单位侧 Behavior 一致）
	match tag:
		"tree":
			return &"chop"
		"stone":
			return &"mine"
		"grass":
			return &"gather"
		_:
			return &"chop"

func _ready() -> void:
	owner_npc = get_parent() as HumanNPC
	if not owner_npc:
		push_warning("NPCBrain must be child of HumanNPC")
		return
	
	# 获取环境管理器
	terrain_object_manager = get_node_or_null("/root/World/Managers/TerrainObjectManager")
	if not terrain_object_manager:
		# Fallback: 尝试在场景中查找
		terrain_object_manager = get_tree().current_scene.find_child("TerrainObjectManager", true, false)
	
	# 连接 HumanNPC 转发的反馈信号 (感知层)
	if not owner_npc.movement_reached.is_connected(_on_destination_reached):
		owner_npc.movement_reached.connect(_on_destination_reached)
	
	if not owner_npc.interaction_stopped.is_connected(_on_interaction_stopped):
		owner_npc.interaction_stopped.connect(_on_interaction_stopped)
	
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	
	# 延迟启动 AI 循环，防止初始化竞争
	await get_tree().create_timer(1.0).timeout
		
	_enter_state(State.IDLE)

func _physics_process(_delta: float) -> void:
	# 关键修复：
	# 多个 NPC 争抢同一个资源点时，失败者可能因为“目标位置被其他 NPC 占住”而导致导航永远无法判定到达，
	# 进而持续处于 WORK（移动）状态，动画表现为原地左右走动且不会恢复。
	# 这里改为：只要“接近到一定距离”，就停止移动并尝试交互/或者放弃目标。
	if current_state != State.WORK:
		return
	if not owner_npc:
		return
	if not _has_target_world_pos:
		return

	# 如果目标实体已经被销毁或变为不可交互（被占用），直接放弃，防止卡住
	if _target_interaction_component and is_instance_valid(_target_interaction_component):
		if not _target_interaction_component.can_accept_interaction(_target_action):
			owner_npc.command_stop_move()
			_enter_state(State.IDLE)
			return
	elif _target_interaction_component and not is_instance_valid(_target_interaction_component):
		_target_interaction_component = null

	var dist := owner_npc.global_position.distance_to(_target_world_pos)
	if dist <= interaction_approach_distance:
		owner_npc.command_stop_move()
		_try_begin_interaction_nearby()

func _try_begin_interaction_nearby() -> void:
	# 在接近目标时触发（不依赖 destination_reached），让 NPC 能在拥挤情况下仍然退出“走路循环”
	if current_state != State.WORK:
		return

	# Tile 目标：先实体化或复用活跃实体
	if not _target_interaction_component and _target_tile != Vector2i(-1, -1) and terrain_object_manager:
		var entity = terrain_object_manager.request_interaction(_target_tile, -1)
		if entity:
			_target_interaction_component = _get_interaction_component(entity)

	# 如果仍然没有目标，放弃
	if not _target_interaction_component or not is_instance_valid(_target_interaction_component):
		_enter_state(State.IDLE)
		return

	# 检查是否可交互（包含 busy 锁，不包含距离）
	if not _target_interaction_component.can_accept_interaction(_target_action):
		_enter_state(State.IDLE)
		return

	# 结构性修复（方案 A）：
	# - 交互距离的权威规则必须来自目标侧 BeHitComponent.interaction_range
	# - 接近阈值 interaction_approach_distance 只用于“脱困判定”，不能放宽交互距离
	# 结论：只有当 NPC 已经处在允许交互范围内，才进入 INTERACT；否则继续靠近交互点。
	if not _target_interaction_component.is_instigator_in_interaction_range(owner_npc):
		_target_world_pos = _target_interaction_component.get_interaction_position()
		_has_target_world_pos = true
		owner_npc.command_move_to(_target_world_pos)
		return

	_enter_state(State.INTERACT)

# 状态切换入口
func _enter_state(new_state: State) -> void:
	current_state = new_state
	print("[NPCBrain] %s state=%s" % [str(owner_npc.name), str(State.keys()[current_state])])
	
	match current_state:
		State.IDLE:
			# 空闲状态：随机停留一段时间
			var time = randf_range(idle_time_min, idle_time_max)
			timer.start(time)
			owner_npc.command_stop_move()
				
		State.WANDER:
			# 游荡状态：随机移动
			_start_wandering()
			
		State.WORK:
			# 工作状态：寻找资源
			_start_working()
			
		State.INTERACT:
			# 交互状态：执行具体动作
			_perform_interaction()

func _on_timer_timeout() -> void:
	# 计时器结束通常意味着 IDLE 结束
	if current_state == State.IDLE:
		_decide_next_action()
	elif current_state == State.INTERACT:
		# 交互超时保护 (模拟交互完成)
		_enter_state(State.IDLE)

# 决策核心：决定下一步做什么
func _decide_next_action() -> void:
	# 简单逻辑：40% 概率工作，60% 概率游荡
	if randf() < 0.6:
		_enter_state(State.WORK)
	else:
		_enter_state(State.WANDER)

# 行为：开始游荡
func _start_wandering() -> void:
	var random_angle = randf() * TAU
	var distance = randf_range(50, wander_radius)
	var offset = Vector2.RIGHT.rotated(random_angle) * distance
	var target_pos = owner_npc.global_position + offset
	
	# TODO: Check if target_pos is valid (navigable)
	owner_npc.command_move_to(target_pos)

# 行为：开始工作 (寻找资源)
func _start_working() -> void:
	_target_interaction_component = null
	_target_tile = Vector2i(-1, -1)
	_target_action = &"chop"
	_has_target_world_pos = false
	
	# 使用 TerrainObjectManager 扫描环境
	if terrain_object_manager and terrain_object_manager.has_method("scan_for_objects_multi"):
		# 一次合并多 tag 扫描，避免按 tag 重复遍历 grid（O(tags * radius^2) -> O(radius^2)）。
		# scan_for_objects_multi 已按距离排序，且每项附带 "tag" 字段。
		var results: Array = terrain_object_manager.scan_for_objects_multi(
			owner_npc.global_position, detection_radius, work_tags
		)
		if results.is_empty():
			_enter_state(State.WANDER)
			return

		var best_result: Dictionary = results[0]
		var best_tag: String = String(best_result.get("tag", ""))
		_target_action = _get_action_for_tag(best_tag)

		if best_result.type == "entity":
			var entity = best_result.target
			var comp = _get_interaction_component(entity)
			# 检查是否可用（未被其他 NPC 占用）
			if comp and comp.can_accept_interaction(_target_action):
				print("[NPCBrain] %s found_target tag=%s entity=%s action=%s" % [
					str(owner_npc.name),
					str(best_tag),
					str(entity.name),
					str(_target_action)
				])
				_target_interaction_component = comp
				_target_world_pos = comp.get_interaction_position()
				_has_target_world_pos = true
				owner_npc.command_move_to(_target_world_pos)
				return
			_enter_state(State.WANDER)
			return

		elif best_result.type == "tile":
			# 找到地块资源（尚未实体化）
			_target_tile = best_result.target
			var world_pos = best_result.position
			print("[NPCBrain] %s found_tile tag=%s tile=%s pos=%s action=%s" % [
				str(owner_npc.name),
				str(best_tag),
				str(_target_tile),
				str(world_pos),
				str(_target_action)
			])
			_target_world_pos = world_pos
			_has_target_world_pos = true
			owner_npc.command_move_to(world_pos)
			return
	else:
		print("[NPCBrain] %s no_terrain_object_manager" % [str(owner_npc.name)])
	
	# 没找到工作，转为游荡
	_enter_state(State.WANDER)

func _get_interaction_component(target: Node) -> InteractionComponent:
	# 1. 检查是否是 InteractionComponent
	if target is InteractionComponent:
		return target
		
	# 2. 如果是 Area2D，尝试通过 owner 或 parent 获取
	if target is Area2D:
		var parent = target.get_parent()
		if parent:
			var candidate_from_parent = parent.get_node_or_null("InteractionComponent")
			if candidate_from_parent is InteractionComponent:
				return candidate_from_parent
			if parent is InteractionComponent:
				return parent
	
	# 3. 检查直接子节点 (标准结构)
	var candidate_from_self = target.get_node_or_null("InteractionComponent")
	if candidate_from_self is InteractionComponent:
		return candidate_from_self
		
	return null

# 信号回调：到达目的地
func _on_destination_reached() -> void:
	if current_state == State.WANDER:
		_enter_state(State.IDLE)
	elif current_state == State.WORK:
		# 到达工作地点
		if _target_interaction_component:
			print("[NPCBrain] %s reached_entity_target=%s" % [
				str(owner_npc.name),
				str(_target_interaction_component.owner_node.name) if _target_interaction_component.owner_node else str(_target_interaction_component.name)
			])
			_enter_state(State.INTERACT)
		elif _target_tile != Vector2i(-1, -1):
			print("[NPCBrain] %s reached_tile_target=%s" % [str(owner_npc.name), str(_target_tile)])
			# 到达 Tile，请求实体化
			if terrain_object_manager:
				# 使用 -1 让 Manager 自动扫描对应层级（支持 tree/stone/grass 等同构资源点）
				var entity = terrain_object_manager.request_interaction(_target_tile, -1)
				print("[NPCBrain] %s request_interaction entity=%s" % [
					str(owner_npc.name),
					str(entity.name) if entity else "null"
				])
				if entity:
					_target_interaction_component = _get_interaction_component(entity)
				# 如果刚生成就被占用了 (不太可能，但为了安全)
				if _target_interaction_component and not _target_interaction_component.can_accept_interaction(_target_action):
					print("[NPCBrain] %s entity_not_accept action=%s" % [str(owner_npc.name), str(_target_action)])
					_enter_state(State.IDLE)
					return
					
				if _target_interaction_component:
					_enter_state(State.INTERACT)
					return
			
			# 如果实例化失败
			_enter_state(State.IDLE)
		else:
			_enter_state(State.IDLE)

# 行为：执行交互
func _perform_interaction() -> void:
	if not _target_interaction_component:
		_enter_state(State.IDLE)
		return
	print("[NPCBrain] %s interact_with=%s" % [str(owner_npc.name), str(_target_interaction_component.owner_node.name) if _target_interaction_component.owner_node else str(_target_interaction_component.name)])
		
	# Execute interaction via Root Command
	# 传递 InteractionComponent 作为目标
	var success = owner_npc.command_interact(_target_interaction_component)
	print("[NPCBrain] %s interact_success=%s" % [str(owner_npc.name), str(success)])
	if success:
		# 设置一个最长超时，防止交互卡死
		timer.start(10.0)
	else:
		# Failed
		_enter_state(State.IDLE)

# 信号回调：交互结束
func _on_interaction_stopped() -> void:
	# 交互真正结束了 (由 Controller 通知)
	if current_state == State.INTERACT:
		_enter_state(State.IDLE)
