class_name LoopingActionBehavior
extends BaseInteractionBehavior

## 循环型交互行为（砍/采/挖/钓/...）的通用骨架。
## 子类通过重写 hooks 定制差异（动作名、伤害/速度/产出、工具系统、背包限额等），
## 共享的交互会话语义（抢锁→首击→动画→定时循环→停止）由本类保证。
##
## 统一流程：
##   execute(target)
##     └─ 解析 InteractionComponent → 绑定 tree_exiting/died 信号 → 执行首击
##         ├─ 成功：_has_started=true → 请求动画 → 启定时器
##         └─ 失败：stop_interaction（上层会触发 interaction_stopped，动画回 Idle）
##   timer tick → _perform_action()
##     └─ _can_continue() → _build_context() → receive_interaction()
##         └─ 成功：_on_hit_applied()
##   目标销毁/死亡 → _on_target_lost → _on_target_destroyed() → stop_interaction

@export_group("Settings")
## 每次动作的时间间隔（秒）。子类可通过 _compute_interval() 做动态加成。
@export var interval: float = 1.0
## 基础伤害值。子类可通过 _compute_damage() 读工具/技能做加成。
@export var base_damage: int = 1

var _timer: Timer
var _current_target_interaction: InteractionComponent
var _current_target_node: Node
var _has_started: bool = false


# =============================================================================
# 子类扩展点 (Hooks) —— 默认实现已给出，子类按需覆盖
# =============================================================================

## 子类必须返回动作标识（如 &"chop"），用于 can_handle / context。
func _get_default_action_name() -> StringName:
	return &""

## 实际伤害计算。默认返回 base_damage。
## 典型扩展：读玩家装备的工具等级做加成；受 buff/debuff 影响。
func _compute_damage() -> int:
	return base_damage

## 实际间隔计算。默认返回 interval。
## 典型扩展：高级斧头缩短砍树间隔；疲劳度降低动作速度。
func _compute_interval() -> float:
	return interval

## 构造发往对方 BeHitComponent 的 context 字典。
## 默认只含 {action, instigator, damage}；子类可追加自定义字段。
## 典型扩展：tool_id、swing_strength、loot_multiplier、skill_level 等。
func _build_context(_target: Node) -> Dictionary:
	return {
		"action": _get_default_action_name(),
		"instigator": interaction_controller.owner_node,
		"damage": _compute_damage()
	}

## 成功命中（receive_interaction 返回 true）后的钩子。
## 典型扩展：扣工具耐久、加技能经验、触发命中音效/特效。
func _on_hit_applied(_target: Node, _context: Dictionary) -> void:
	pass

## 每次循环前校验。返回 false 可提前终止循环。
## 典型扩展：背包满了（采集类）、饥饿度耗尽、工具损坏。
func _can_continue() -> bool:
	return true

## 目标销毁时的钩子（在 stop_interaction 之前调用）。
## 典型扩展：生成掉落物（原木/矿石/草束）、记录统计、触发事件。
func _on_target_destroyed(_target: Node) -> void:
	pass


# =============================================================================
# 统一框架（子类一般无需重写下方逻辑）
# =============================================================================

func setup(controller: InteractionComponent) -> void:
	super.setup(controller)
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = _compute_interval()
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


func can_handle(target: Node) -> bool:
	var comp = _get_interaction_component(target)
	return comp != null and comp.can_accept_interaction(_get_default_action_name())


func execute(target: Node) -> void:
	var comp = _get_interaction_component(target)
	if not comp:
		cancel()
		return

	_current_target_interaction = comp
	_has_started = false
	_current_target_node = comp.owner_node if comp.owner_node else comp.get_parent()

	if _current_target_node:
		if not _current_target_node.tree_exiting.is_connected(_on_target_lost):
			_current_target_node.tree_exiting.connect(_on_target_lost)
		if _current_target_node.has_signal("died"):
			if not _current_target_node.died.is_connected(_on_target_lost):
				_current_target_node.died.connect(_on_target_lost)

	# 必须先成功首击（抢锁成功）才播动画/启 timer。
	# 首击可能同步导致目标死亡，引用被 stop_interaction 清空；所以提前缓存交互点。
	var target_pos = _current_target_interaction.get_interaction_position()
	if not _perform_action():
		return
	if not is_instance_valid(_current_target_interaction):
		return
	_has_started = true
	request_action_animation({ "target_pos": target_pos })
	_timer.wait_time = _compute_interval() # 每次 execute 同步一次（子类可能动态变化）
	_timer.start()


func cancel() -> void:
	_stop_loop()


func _stop_loop() -> void:
	if _timer:
		_timer.stop()

	if is_instance_valid(_current_target_interaction):
		# 只有"真正成功开工"的一方才需要解锁并通知"交互结束"，
		# 抢锁失败的一方不能影响目标实体的生命周期
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


func _perform_action() -> bool:
	if not is_instance_valid(_current_target_interaction):
		interaction_controller.stop_interaction()
		return false
	if not _can_continue():
		interaction_controller.stop_interaction()
		return false

	var context := _build_context(_current_target_node)
	var ok := _current_target_interaction.receive_interaction(context)
	if not ok:
		# 交互失败（距离不够/锁被抢/动作不支持/目标失效）→ 停止循环并通知动画回 Idle
		interaction_controller.stop_interaction()
		return false
	_on_hit_applied(_current_target_node, context)
	return true


func _on_timer_timeout() -> void:
	_perform_action()


func _on_target_lost() -> void:
	# 目标销毁时给子类一次最后处理机会（掉落、统计）
	if is_instance_valid(_current_target_node):
		_on_target_destroyed(_current_target_node)
	interaction_controller.stop_interaction()


func _get_interaction_component(target: Node) -> InteractionComponent:
	if target is InteractionComponent:
		return target
	if target is Area2D:
		var parent = target.get_parent()
		if parent:
			var candidate_from_parent = parent.get_node_or_null("InteractionComponent")
			if candidate_from_parent is InteractionComponent:
				return candidate_from_parent
			if parent is InteractionComponent:
				return parent
	var candidate_from_self = target.get_node_or_null("InteractionComponent")
	if candidate_from_self is InteractionComponent:
		return candidate_from_self
	return null
