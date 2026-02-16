class_name ChopBehavior
extends BaseInteractionBehavior

# 砍树行为

func can_handle(target: Node) -> bool:
	# 检查目标是否是树
	# 这里假设树木有 "Tree" 的 group 或者特定的组件，暂时用 InteractableComponent 的类型判断
	# 注意：InteractableComponent 是挂在 Area2D 上的，通常 Area2D 是目标的子节点
	var interactable = target as InteractableComponent
	if interactable and interactable.interaction_type == InteractableComponent.Type.GATHER:
		# 进一步检查父节点是否在 "Tree" 组中，或者是否有特定的 metadata
		var owner = interactable.get_parent()
		if owner.is_in_group("Tree"):
			return true
	return false

func execute(target: Node) -> void:
	if not _is_in_range(target):
		print("Target too far to chop")
		return
	
	print("Chopping tree: ", target.name)
	# 播放动画
	if animation_logic and interaction_controller.owner_node.has_method("play_animation_logic"):
		interaction_controller.owner_node.play_animation_logic(animation_logic)
	
	# 实际的交互逻辑，比如造成伤害或掉落
	if target.has_method("try_interact"):
		target.try_interact(interaction_controller.owner_node)
