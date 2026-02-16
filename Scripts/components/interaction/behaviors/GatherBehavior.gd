class_name GatherBehavior
extends BaseInteractionBehavior

# 通用采集行为 (草、浆果等)

func can_handle(target: Node) -> bool:
	var interactable = target as InteractableComponent
	if interactable and interactable.interaction_type == InteractableComponent.Type.GATHER:
		# 如果不是树也不是矿，或者是通用的 Gather
		var owner = interactable.get_parent()
		if not owner.is_in_group("Tree") and not owner.is_in_group("Rock") and not owner.is_in_group("Ore"):
			return true
	return false

func execute(target: Node) -> void:
	if not _is_in_range(target):
		print("Target too far to gather")
		return
		
	print("Gathering: ", target.name)
	if animation_logic and interaction_controller.owner_node.has_method("play_animation_logic"):
		interaction_controller.owner_node.play_animation_logic(animation_logic)
		
	if target.has_method("try_interact"):
		target.try_interact(interaction_controller.owner_node)
