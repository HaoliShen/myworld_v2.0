class_name TreeDieLogic
extends AnimationLogic

@export var visuals_node: Node2D # 用于 Tween 旋转等

signal die_finished

func enter() -> void:
	if animated_sprite and animated_sprite.sprite_frames.has_animation("die"):
		animated_sprite.play("die")
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
	else:
		# 简单的倒下效果
		if visuals_node:
			var tween = create_tween()
			tween.tween_property(visuals_node, "rotation_degrees", 90.0, 0.5).set_ease(Tween.EASE_IN)
			tween.tween_property(visuals_node, "modulate:a", 0.0, 0.5)
			tween.finished.connect(_on_animation_finished)
		else:
			call_deferred("_on_animation_finished")

func exit() -> void:
	if animated_sprite and animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.disconnect(_on_animation_finished)
	super.exit()

func _on_animation_finished() -> void:
	die_finished.emit()
