class_name BeHitComponent
extends Node

# BeHit 组件 (原 InteractableComponent)
# 职责：作为实体对外的交互接口，声明该实体能接受哪些动作 (如 "chop", "attack")。
# 必须引用一个 Area2D (InteractionArea) 用于检测交互范围。

signal action_received(context: Dictionary) # 原 interacted
signal action_failed(reason: String) # 原 interaction_failed

## 配置
@export var interaction_area: Area2D
@export var actions: Array[StringName] = [] # e.g. ["chop", "mine", "talk"]
@export var interaction_label: String = "Interact" # UI 显示文本
@export var interaction_range: float = 50.0 # 最大交互距离
@export var data: Dictionary = {} # 自定义数据

var current_interactor: Node = null

func _ready() -> void:
	if interaction_area:
		# 将自身注册到 Area2D 的元数据中，方便 Controller 查找
		# 更新 meta key 为 behit_component
		interaction_area.set_meta("behit_component", self)
		
		# 兼容旧逻辑，暂时保留 interactable_component meta，以防有漏改
		interaction_area.set_meta("interactable_component", self)
	else:
		push_warning("BeHitComponent: No InteractionArea assigned!")

func is_busy() -> bool:
	return is_instance_valid(current_interactor)

func try_lock(interactor: Node) -> bool:
	if is_busy() and current_interactor != interactor:
		return false
	current_interactor = interactor
	return true

func unlock(interactor: Node) -> void:
	if current_interactor == interactor:
		current_interactor = null

# 原 interact 方法，保留名称以减少改动，但语义上是 "receive_action"
func interact(context: Dictionary) -> bool:
	var instigator = context.get("instigator")
	if not instigator:
		push_error("BeHitComponent: No instigator in context")
		return false
		
	if not try_lock(instigator):
		print("[BeHitComponent] %s busy interactor=%s new=%s" % [
			str(get_parent().name) if get_parent() else str(name),
			str(current_interactor.name) if current_interactor else "null",
			str(instigator.name) if instigator else "null"
		])
		action_failed.emit("Object is busy")
		return false
	
	# 如果 context 中有 action，检查是否支持该 action
	if context.has("action"):
		var action = context.get("action")
		if not actions.has(action):
			print("[BeHitComponent] %s action_not_supported action=%s actions=%s" % [
				str(get_parent().name) if get_parent() else str(name),
				str(action),
				str(actions)
			])
			action_failed.emit("Action not supported")
			return false

	# 检查距离 (如果 interaction_area 存在)
	if interaction_area and instigator is Node2D:
		var target_pos = interaction_area.global_position
		var distance = target_pos.distance_to(instigator.global_position)
		if distance > interaction_range:
			print("[BeHitComponent] %s too_far dist=%s range=%s action=%s" % [
				str(get_parent().name) if get_parent() else str(name),
				str(distance),
				str(interaction_range),
				str(context.get("action"))
			])
			action_failed.emit("Too far")
			return false
	
	print("[BeHitComponent] %s action_received ctx=%s" % [str(get_parent().name) if get_parent() else str(name), str(context)])
	action_received.emit(context)
	return true
