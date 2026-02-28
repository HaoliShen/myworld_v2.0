class_name GatherLogic
extends AnimationLogic

# 采集动画逻辑

@export var animation_name: String = "gather"

func enter() -> void:
	if not animated_sprite:
		return

	# 根据目标位置调整朝向（与 ChopLogic 保持一致）
	if context.has("target_pos"):
		var target_pos = context["target_pos"]
		var owner_pos = animated_sprite.global_position
		animated_sprite.flip_h = target_pos.x < owner_pos.x

	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)
	else:
		animated_sprite.play()
	
func exit() -> void:
	pass

func process_logic(_delta: float) -> void:
	pass
