class_name DemolishBehavior
extends LoopingActionBehavior

## Demolishes buildable blocks. This keeps building teardown semantically
## separate from resource gathering while reusing the shared looping action flow.

func _get_default_action_name() -> StringName:
	return &"demolish"


func _on_target_destroyed(_target: Node) -> void:
	_grant_target_drops_to_player(_target, _get_default_action_name())
