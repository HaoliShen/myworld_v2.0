class_name NPCInteractionBehavior
extends BaseInteractionBehavior

# NPC交互行为（对话等）

func can_handle(target: Node) -> bool:
	var comp = _get_interaction_component(target)
	if comp and comp.can_accept_interaction(&"talk"):
		return true
	return false

func execute(target: Node) -> void:
	var comp = _get_interaction_component(target)
	if not comp:
		return

	print("Talking to NPC: ", comp.owner_node.name if comp.owner_node else comp.get_parent().name)
	
	request_action_animation({ "target_pos": comp.get_interaction_position() })
		
	var context = {
		"action": &"talk",
		"instigator": interaction_controller.owner_node
	}
	comp.receive_interaction(context)
	
	# 触发对话逻辑
	# InteractionComponent 的 owner 通常是 NPC
	var target_owner = comp.owner_node
	if not target_owner:
		target_owner = comp.get_parent()
		
	if target_owner and target_owner.has_method("on_interact_start"):
		target_owner.on_interact_start(interaction_controller.owner_node)

func _get_interaction_component(target: Node) -> InteractionComponent:
	# 1. 检查是否是 InteractionComponent
	if target is InteractionComponent:
		return target
		
	# 2. 如果是 Area2D，尝试通过 owner 或 parent 获取
	if target is Area2D:
		var parent = target.get_parent()
		if parent:
			var candidate_from_parent = parent.get_node_or_null("InteractionComponent")
			if candidate_from_parent is InteractionComponent:
				return candidate_from_parent
			if parent is InteractionComponent:
				return parent
	
	# 3. 检查直接子节点 (标准结构)
	var candidate_from_self = target.get_node_or_null("InteractionComponent")
	if candidate_from_self is InteractionComponent:
		return candidate_from_self
		
	return null
