class_name ChopBehavior
extends BaseInteractionBehavior

# 砍树行为
# 负责控制单位进行砍树动作，包括播放动画、定时触发伤害等。

@export_group("Settings")
## 砍树动作的时间间隔（秒）。
@export var chop_interval: float = 1.0 
## 基础伤害值
@export var base_damage: int = 1

var _timer: Timer
var _current_target_interaction: InteractionComponent
var _current_target_node: Node # 实际的实体节点 (用于监听 tree_exiting)
var _has_started: bool = false

func setup(controller: Node) -> void:
	super.setup(controller)
	
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = chop_interval
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

func can_handle(target: Node) -> bool:
	var comp = _get_interaction_component(target)
	if comp and comp.can_accept_interaction(&"chop"):
		return true
	return false

func execute(target: Node) -> void:
	var comp = _get_interaction_component(target)
	if not comp:
		cancel()
		return
	_current_target_interaction = comp
	_has_started = false
	print("[ChopBehavior] execute owner=%s target=%s" % [
		str(interaction_controller.owner_node.name) if interaction_controller and interaction_controller.owner_node else str(name),
		str(_current_target_interaction.owner_node.name) if _current_target_interaction and _current_target_interaction.owner_node else str(target.name)
	])
	# 获取实际的实体节点用于监听销毁
	# InteractionComponent 的 owner 通常是实体
	_current_target_node = comp.owner_node
	if not _current_target_node:
		_current_target_node = comp.get_parent()
	
	# 监听目标销毁
	if _current_target_node:
		if not _current_target_node.tree_exiting.is_connected(_on_target_lost):
			_current_target_node.tree_exiting.connect(_on_target_lost)
		if _current_target_node.has_signal("died"):
			if not _current_target_node.died.is_connected(_on_target_lost):
				_current_target_node.died.connect(_on_target_lost)
			
	# 关键点：必须先成功抢到锁（receive_interaction=true），才能播放砍树动画并启动循环
	# 否则在“同时交互抢锁失败”的情况下，会出现：未抢到锁的一方也播放砍树动画，甚至影响树实体生命周期
	var ok := _perform_chop()
	if not ok:
		return
	_has_started = true
	var target_pos = _current_target_interaction.get_interaction_position()
	request_action_animation({ "target_pos": target_pos })
	_timer.start()

func cancel() -> void:
	_stop_chopping()

func _stop_chopping() -> void:
	_timer.stop()
	
	if is_instance_valid(_current_target_interaction):
		# 只有真正成功开始交互的一方才需要解锁并通知“交互结束”
		# 抢锁失败的一方不能影响目标实体，也不应触发回收
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

func _perform_chop() -> bool:
	if not is_instance_valid(_current_target_interaction):
		interaction_controller.stop_interaction()
		return false
		
	var target_label := "Unknown"
	if _current_target_node:
		target_label = str(_current_target_node.name)
	print("Chopping: ", target_label)
	
	# 执行交互
	var context = {
		"action": &"chop",
		"instigator": interaction_controller.owner_node,
		"damage": base_damage
	}
	var ok := _current_target_interaction.receive_interaction(context)
	print("[ChopBehavior] hit ok=%s target=%s" % [str(ok), target_label])
	if not ok:
		# 交互失败通常意味着目标不可用/距离不够/目标已被销毁等
		# 此时必须停止当前交互，确保：
		# 1) Timer 不再继续空转
		# 2) AnimationComponent 能收到 interaction_stopped 并回到 Idle
		interaction_controller.stop_interaction()
		return false
	return true

func _on_timer_timeout() -> void:
	_perform_chop()

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
