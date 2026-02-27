class_name BaseInteractionBehavior
extends Node

# 基础交互行为类，定义接口

@export var animation_logic: AnimationLogic
@export var interaction_range: float = 50.0

var interaction_controller: InteractionComponent

func setup(controller: InteractionComponent) -> void:
	interaction_controller = controller

func request_action_animation(context: Dictionary = {}) -> void:
	if not interaction_controller:
		return
	if animation_logic:
		interaction_controller.request_animation(animation_logic, context)

func can_handle(_target: Node) -> bool:
	return false

func execute(_target: Node) -> void:
	pass

func cancel() -> void:
	pass

func _is_in_range(target: Node) -> bool:
	if not interaction_controller or not interaction_controller.owner_node:
		return false
	if not target is Node2D:
		return true # 非空间节点默认可交互
	var owner_pos = interaction_controller.owner_node.global_position
	return owner_pos.distance_to(target.global_position) <= interaction_range
