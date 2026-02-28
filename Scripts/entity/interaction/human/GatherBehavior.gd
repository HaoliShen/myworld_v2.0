class_name GatherBehavior
extends BaseInteractionBehavior

## 通用采集行为（结构与 ChopBehavior 保持一致）
## 设计目标：
## - 与砍树/采矿保持完全一致的“交互会话”结构，避免 busy 锁与回收竞态
## - 成功 receive_interaction(抢锁成功) 才播放动画并开始循环
## - 停止交互时解锁；若目标未死亡，发 interaction_finished 触发回收/恢复 tile 视觉
##
## 注意：采集具体结算（加背包/掉落等）暂不在此处理（后续可接入）

@export_group("Settings")
## 每次采集尝试的时间间隔（秒）。
@export var gather_interval: float = 1.0
## 基础伤害值（对“可被采集=可被清除”的目标，可用 1 直接触发死亡；后续可改为产出逻辑）。
@export var base_damage: int = 1

var _timer: Timer
var _current_target_interaction: InteractionComponent
var _current_target_node: Node # 实际实体节点（用于监听销毁）
var _has_started: bool = false

func can_handle(target: Node) -> bool:
	var comp = _get_interaction_component(target)
	if comp and comp.can_accept_interaction(&"gather"):
		return true
	return false

func execute(target: Node) -> void:
	var comp = _get_interaction_component(target)
	if not comp:
		cancel()
		return

	_current_target_interaction = comp
	_has_started = false
	print("[GatherBehavior] execute owner=%s target=%s" % [
		str(interaction_controller.owner_node.name) if interaction_controller and interaction_controller.owner_node else str(name),
		str(_current_target_interaction.owner_node.name) if _current_target_interaction and _current_target_interaction.owner_node else str(target.name)
	])
	_current_target_node = comp.owner_node
	if not _current_target_node:
		_current_target_node = comp.get_parent()

	if _current_target_node:
		if not _current_target_node.tree_exiting.is_connected(_on_target_lost):
			_current_target_node.tree_exiting.connect(_on_target_lost)
		if _current_target_node.has_signal("died"):
			if not _current_target_node.died.is_connected(_on_target_lost):
				_current_target_node.died.connect(_on_target_lost)

	# 关键点：必须先成功抢到锁（receive_interaction=true），才能播放采集动画并启动循环
	# 注意：采集目标可能在“首刀”就死亡（例如草 max_health=1），会触发 _on_target_lost 进而 stop_interaction。
	# 因此必须提前缓存 target_pos，并在开工前再次校验引用有效，避免空引用崩溃/Timer 空转。
	var target_pos = _current_target_interaction.get_interaction_position()
	var ok := _perform_gather()
	if not ok:
		return
	if not is_instance_valid(_current_target_interaction):
		return
	_has_started = true
	request_action_animation({ "target_pos": target_pos })
	_timer.start()
	
func setup(controller: Node) -> void:
	super.setup(controller)
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = gather_interval
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

func cancel() -> void:
	_stop_gathering()

func _stop_gathering() -> void:
	_timer.stop()

	if is_instance_valid(_current_target_interaction):
		if _has_started:
			_current_target_interaction.cancel_incoming_interaction(interaction_controller.owner_node)
			if is_instance_valid(_current_target_node) and _current_target_node.has_signal("interaction_finished"):
				var hp_ok := true
				if _current_target_interaction.health_component:
					hp_ok = _current_target_interaction.health_component.current_health > 0
				if hp_ok:
					_current_target_node.emit_signal("interaction_finished")

	if is_instance_valid(_current_target_node):
		if _current_target_node.tree_exiting.is_connected(_on_target_lost):
			_current_target_node.tree_exiting.disconnect(_on_target_lost)
		if _current_target_node.has_signal("died") and _current_target_node.died.is_connected(_on_target_lost):
			_current_target_node.died.disconnect(_on_target_lost)

	_current_target_interaction = null
	_current_target_node = null
	_has_started = false

func _perform_gather() -> bool:
	if not is_instance_valid(_current_target_interaction):
		interaction_controller.stop_interaction()
		return false

	var target_label := "Unknown"
	if _current_target_node:
		target_label = str(_current_target_node.name)
	print("Gathering: ", target_label)

	var context = {
		"action": &"gather",
		"instigator": interaction_controller.owner_node,
		"damage": base_damage
	}
	var ok := _current_target_interaction.receive_interaction(context)
	print("[GatherBehavior] hit ok=%s target=%s" % [str(ok), target_label])
	if not ok:
		interaction_controller.stop_interaction()
		return false
	return true

func _on_timer_timeout() -> void:
	_perform_gather()

func _on_target_lost() -> void:
	interaction_controller.stop_interaction()

func _get_interaction_component(target: Node) -> InteractionComponent:
	# 1. 检查是否是 InteractionComponent
	if target is InteractionComponent:
		return target
		
	# 2. 如果是 Area2D，尝试通过 owner 或 parent 获取
	if target is Area2D:
		# 尝试获取父级的 InteractionComponent
		var parent = target.get_parent()
		if parent:
			# 如果父级是实体，找子组件
			var candidate_from_parent = parent.get_node_or_null("InteractionComponent")
			if candidate_from_parent is InteractionComponent:
				return candidate_from_parent
			# 如果父级本身是 InteractionComponent (不太可能，Area 通常在 Entity 下)
			if parent is InteractionComponent:
				return parent
	
	# 3. 检查直接子节点 (标准结构)
	var candidate_from_self = target.get_node_or_null("InteractionComponent")
	if candidate_from_self is InteractionComponent:
		return candidate_from_self
		
	return null
