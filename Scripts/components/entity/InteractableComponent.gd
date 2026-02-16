class_name InteractableComponent
extends Area2D

# 交互类型
enum Type { 
	GATHER,  # 采集
	TALK,    # 对话
	ATTACK,  # 攻击
	OPEN,    # 打开
	CUSTOM   # 自定义
}

signal interacted(interactor: Node)
signal interaction_failed(reason: String)

@export var interaction_type: Type = Type.GATHER
@export var interaction_range: float = 50.0
@export var interaction_time: float = 0.0 # 0 表示瞬间完成
@export var interaction_label: String = "Interact"

var owner_node: Node

func _ready() -> void:
	owner_node = get_parent()
	# 确保 Area2D 配置正确
	# collision_layer = 2 # 使用 Layer 2 (Interactables)
	collision_mask = 0  # 不需要检测其他

func try_interact(interactor: Node) -> bool:
	if not _can_interact(interactor):
		return false
		
	interacted.emit(interactor)
	return true

func _can_interact(interactor: Node) -> bool:
	if interactor is Node2D:
		var distance = global_position.distance_to(interactor.global_position)
		if distance > interaction_range:
			interaction_failed.emit("Too far")
			return false
	return true
