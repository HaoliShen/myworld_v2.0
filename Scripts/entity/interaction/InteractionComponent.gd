class_name InteractionComponent
extends Node2D

# 交互组件 (逻辑主节点)
# 职责：
# 1. 管理所有逻辑子组件 (Health, Movement, BeHit等)
# 2. 管理所有主动交互行为 (Behaviors)
# 3. 作为实体逻辑的外观 (Facade)，转发外部请求到对应子组件

signal interaction_started(target: Node)
signal interaction_finished
signal interaction_stopped
signal damaged(amount: int)
signal died
signal movement_started(direction: Vector2)
signal movement_stopped
signal animation_requested(logic: Variant, context: Dictionary)
signal incoming_interaction(context: Dictionary)

# 依赖引用 (自动查找子节点)
var health_component: HealthComponent
var movement_component: MovementController
var be_hit_component: BeHitComponent # 原 interactable_component

# 内部状态
var behaviors: Array[BaseInteractionBehavior] = []
var current_behavior: BaseInteractionBehavior
var owner_node: Node

func _ready() -> void:
	owner_node = get_owner() if get_owner() else get_parent()
	
	_find_components()
	_setup_behaviors()
	_connect_signals()
	if be_hit_component == null and owner_node and str(owner_node.name).find("Tree") != -1 and not has_meta("_dbg_dumped"):
		set_meta("_dbg_dumped", true)
		print("[InteractionComponent] %s children_dump" % [str(owner_node.name)])
		for c in get_children():
			var s = c.get_script()
			print("[InteractionComponent] child name=%s class=%s script=%s" % [
				str(c.name),
				str(c.get_class()),
				str(s.resource_path) if s else "null"
			])

func _find_components() -> void:
	# 查找直接挂载的组件
	for child in get_children():
		if child is HealthComponent:
			health_component = child
		elif child is MovementController:
			movement_component = child
		elif child is BeHitComponent:
			be_hit_component = child

func _setup_behaviors() -> void:
	behaviors.clear()
	for child in get_children():
		if child is BaseInteractionBehavior:
			behaviors.append(child)
			child.setup(self) # 行为需要引用此控制器

func _connect_signals() -> void:
	if health_component:
		health_component.died.connect(func():
			print("[InteractionComponent] %s died" % [str(owner_node.name) if owner_node else str(name)])
			died.emit()
		)
		health_component.damaged.connect(func(amount, _source):
			damaged.emit(amount)
			print("[InteractionComponent] %s damaged=%s hp=%s/%s" % [
				str(owner_node.name) if owner_node else str(name),
				str(amount),
				str(health_component.current_health),
				str(health_component.max_health)
			])
		)
	
	if movement_component:
		movement_component.movement_started.connect(func(dir): movement_started.emit(dir))
		movement_component.movement_stopped.connect(func(): movement_stopped.emit())

	if be_hit_component:
		be_hit_component.action_received.connect(_on_incoming_interaction)
		be_hit_component.action_failed.connect(func(reason):
			print("[BeHit] %s action_failed=%s" % [str(owner_node.name) if owner_node else str(name), reason])
		)

func _on_incoming_interaction(context: Dictionary) -> void:
	incoming_interaction.emit(context)
	print("[InteractionComponent] %s incoming=%s" % [str(owner_node.name) if owner_node else str(name), str(context)])
	
	# 自动处理伤害
	if context.has("damage") and health_component:
		var amount := int(context.get("damage", 0))
		var instigator := context.get("instigator") as Node
		print("[InteractionComponent] %s take_damage=%s instigator=%s" % [
			str(owner_node.name) if owner_node else str(name),
			str(amount),
			str(instigator.name) if instigator else "null"
		])
		health_component.take_damage(amount, instigator)

# --- Facade Methods (供根节点调用) ---

func move_to(target_pos: Vector2) -> void:
	# 对外公开接口：发起移动
	# 关键点：
	# - 任何移动命令都视为“主动中断当前交互”，必须先停止当前行为并触发 interaction_stopped
	# - 避免砍树/采集等行为在移动后仍继续运行，导致动画与逻辑不同步
	stop_interaction()
	if movement_component:
		movement_component.move_to(target_pos)
	else:
		push_warning("InteractionComponent: No MovementComponent found on " + owner.name)

func stop_move() -> void:
	if movement_component:
		movement_component.stop()

func take_damage(amount: int) -> void:
	if health_component:
		health_component.take_damage(amount)

func interact(target: Node) -> bool:
	# 停止当前交互
	stop_interaction()
	print("[InteractionComponent] %s interact target=%s" % [str(owner_node.name) if owner_node else str(name), str(target.name) if target else "null"])
	# 寻找合适的行为
	for behavior in behaviors:
		if behavior.can_handle(target):
			current_behavior = behavior
			interaction_started.emit(target)
			print("[InteractionComponent] %s using_behavior=%s" % [str(owner_node.name) if owner_node else str(name), str(behavior.name)])
			behavior.execute(target)
			return true
	
	print("[InteractionComponent] %s no_behavior" % [str(owner_node.name) if owner_node else str(name)])
	return false

func stop_interaction() -> void:
	if current_behavior:
		print("[InteractionComponent] %s stop_behavior=%s" % [str(owner_node.name) if owner_node else str(name), str(current_behavior.name)])
		current_behavior.cancel()
		current_behavior = null
	interaction_stopped.emit()

# 供 Behavior 调用的辅助方法
func notify_interaction_finished() -> void:
	interaction_finished.emit()
	stop_interaction()

func request_animation(logic: Variant, context: Dictionary = {}) -> void:
	print("[InteractionComponent] %s request_animation logic=%s ctx=%s" % [
		str(owner_node.name) if owner_node else str(name),
		str(logic),
		str(context)
	])
	animation_requested.emit(logic, context)

# --- Incoming Interaction Facade (作为交互接收方) ---

## 接收外部交互请求
func receive_interaction(context: Dictionary) -> bool:
	if be_hit_component:
		var ok := be_hit_component.interact(context)
		print("[InteractionComponent] %s receive_interaction ok=%s ctx=%s" % [
			str(owner_node.name) if owner_node else str(name),
			str(ok),
			str(context)
		])
		return ok
	return false

## 检查是否接受某种交互
func can_accept_interaction(action: StringName = &"") -> bool:
	if not be_hit_component:
		if action == &"chop":
			print("[InteractionComponent] %s can_accept_interaction=false no_be_hit" % [str(owner_node.name) if owner_node else str(name)])
		return false
	
	if action != &"" and not be_hit_component.actions.has(action):
		if action == &"chop":
			print("[InteractionComponent] %s can_accept_interaction=false action=%s actions=%s" % [
				str(owner_node.name) if owner_node else str(name),
				str(action),
				str(be_hit_component.actions)
			])
		return false
		
	var ok := not be_hit_component.is_busy()
	if action == &"chop" and not ok:
		print("[InteractionComponent] %s can_accept_interaction=false busy" % [str(owner_node.name) if owner_node else str(name)])
	return ok

## 获取交互位置 (通常是 InteractionArea 的位置)
func get_interaction_position() -> Vector2:
	if be_hit_component and be_hit_component.interaction_area:
		return be_hit_component.interaction_area.global_position
	return global_position

## 取消/结束接收的交互 (释放锁)
func cancel_incoming_interaction(instigator: Node) -> void:
	if be_hit_component:
		be_hit_component.unlock(instigator)
