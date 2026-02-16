class_name AttackBehavior
extends BaseInteractionBehavior

# 攻击行为

func can_handle(target: Node) -> bool:
	var interactable = target as InteractableComponent
	if interactable and interactable.interaction_type == InteractableComponent.Type.ATTACK:
		return true
	return false

func execute(target: Node) -> void:
	if not _is_in_range(target):
		print("Target too far to attack")
		return
		
	print("Attacking: ", target.name)
	if animation_logic and interaction_controller.owner_node.has_method("play_animation_logic"):
		interaction_controller.owner_node.play_animation_logic(animation_logic)
		
	if target.has_method("try_interact"):
		target.try_interact(interaction_controller.owner_node)
