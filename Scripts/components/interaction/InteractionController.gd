class_name InteractionController
extends Node

# 交互控制器，作为胶水组件管理具体的交互行为

@export var interaction_shape: Area2D
@export var behaviors: Array[BaseInteractionBehavior]

var owner_node: Node2D

func _ready() -> void:
	owner_node = get_parent() as Node2D
	
	# 初始化子行为节点
	for child in get_children():
		if child is BaseInteractionBehavior:
			if not behaviors.has(child):
				behaviors.append(child)
	
	for behavior in behaviors:
		behavior.setup(self)

func interact(target: Node) -> bool:
	# 寻找能处理该目标的行为
	for behavior in behaviors:
		if behavior.can_handle(target):
			behavior.execute(target)
			return true
	
	print("No behavior found to handle interaction with: ", target.name)
	return false

func get_overlapping_interactables() -> Array:
	if interaction_shape:
		return interaction_shape.get_overlapping_areas()
	return []
