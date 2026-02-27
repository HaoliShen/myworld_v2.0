class_name TreeHitLogic
extends AnimationLogic

@export var visuals_node: Node2D # 用于 Tween 旋转等

func enter() -> void:
	if animated_sprite and animated_sprite.sprite_frames.has_animation("hit"):
		animated_sprite.play("hit")
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
	else:
		# 简单的抖动效果
		if visuals_node:
			var tween = create_tween()
			tween.tween_property(visuals_node, "rotation_degrees", 5.0, 0.05)
			tween.tween_property(visuals_node, "rotation_degrees", -5.0, 0.05)
			tween.tween_property(visuals_node, "rotation_degrees", 0.0, 0.05)
			tween.finished.connect(_on_animation_finished)
		else:
			# 如果没有 visuals_node 也没有动画，直接结束
			call_deferred("_on_animation_finished")

func exit() -> void:
	if animated_sprite and animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.disconnect(_on_animation_finished)
	super.exit()

func _on_animation_finished() -> void:
	# 播放完 hit 动画后，不需要切回 Idle，保持在 Hit 状态（或自动停止播放）
	# 如果有默认动画，可以在这里播放
	if animated_sprite and animated_sprite.sprite_frames.has_animation("default"):
		animated_sprite.play("default")
	elif animated_sprite and animated_sprite.sprite_frames.has_animation("idle"):
		# 如果确实有 idle 动画资源，也可以播放，但不作为状态切换
		animated_sprite.play("idle")
