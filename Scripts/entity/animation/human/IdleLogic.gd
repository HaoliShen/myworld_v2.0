class_name IdleLogic
extends AnimationLogic

func enter() -> void:
	if animated_sprite:
		animated_sprite.play("idle")

func exit() -> void:
	pass
