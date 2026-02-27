class_name MineBehavior
extends BaseInteractionBehavior

# 挖矿行为

func can_handle(target: Node) -> bool:
	var comp = _get_interaction_component(target)
	if comp and comp.can_accept_interaction(&"mine"):
		return true
	return false

func execute(target: Node) -> void:
	var comp = _get_interaction_component(target)
	if not comp:
		return

	print("Mining rock: ", comp.owner_node.name if comp.owner_node else comp.get_parent().name)
	
	request_action_animation({ "target_pos": comp.get_interaction_position() })
		
	var context = {
		"action": &"mine",
		"instigator": interaction_controller.owner_node,
		"damage": 1 # TODO: 从镐子获取
	}
	comp.receive_interaction(context)

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
