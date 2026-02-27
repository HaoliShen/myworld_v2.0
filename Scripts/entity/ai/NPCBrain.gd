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

# 内部状态
var current_state: State = State.IDLE
var timer: Timer
var owner_npc: HumanNPC
var terrain_object_manager: Node

var _target_interaction_component: InteractionComponent = null # 当前交互目标组件
var _target_tile: Vector2i = Vector2i(-1, -1) # 当前交互目标地块 (需先实例化)

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
	
	# 使用 TerrainObjectManager 扫描环境
	if terrain_object_manager and terrain_object_manager.has_method("scan_for_objects"):
		var results = terrain_object_manager.scan_for_objects(owner_npc.global_position, detection_radius, "tree")
		print("[NPCBrain] %s scan_for_objects size=%s" % [str(owner_npc.name), str(results.size())])
		if results.size() > 0:
			var first = results[0]
			print("[NPCBrain] %s first_result type=%s dist_sq=%s" % [
				str(owner_npc.name),
				str(first.get("type")),
				str(first.get("dist_sq"))
			])
		
		for result in results:
			if result.type == "entity":
				# 找到实体资源
				var entity = result.target
				var comp = _get_interaction_component(entity)
				
				# 检查是否可用 (未被其他 NPC 占用)
				if comp and comp.can_accept_interaction(&"chop"):
					print("[NPCBrain] %s found_tree entity=%s" % [str(owner_npc.name), str(entity.name)])
					_target_interaction_component = comp
					owner_npc.command_move_to(comp.get_interaction_position())
					return
					
			elif result.type == "tile":
				# 找到地块资源 (尚未实体化)
				_target_tile = result.target
				var world_pos = result.position
				print("[NPCBrain] %s found_tree_tile tile=%s pos=%s" % [str(owner_npc.name), str(_target_tile), str(world_pos)])
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
				# 使用 -1 让 Manager 自动扫描，或者使用正确的层级
				var tree_layer = _C.OBJECT_RENDER_LAYER_TABLE.get(_C.ID_TREE, _C.Layer.DECORATION)
				var entity = terrain_object_manager.request_interaction(_target_tile, tree_layer)
				print("[NPCBrain] %s request_interaction entity=%s" % [
					str(owner_npc.name),
					str(entity.name) if entity else "null"
				])
				if entity:
					_target_interaction_component = _get_interaction_component(entity)
				# 如果刚生成就被占用了 (不太可能，但为了安全)
				if _target_interaction_component and not _target_interaction_component.can_accept_interaction(&"chop"):
					print("[NPCBrain] %s entity_not_accept_chop" % [str(owner_npc.name)])
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
