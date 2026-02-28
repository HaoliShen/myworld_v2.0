class_name SimpleHitLogic
extends AnimationLogic

## 通用“受击”动画逻辑（可用于树/石头/草等同构资源点）
## 设计意图：
## - 如果 AnimatedSprite2D 中存在 "hit" 动画：优先播放
## - 否则退化为对 visuals_node 的轻微抖动效果
## - 播放结束后若存在 "idle"/"default" 则切回（仅播放，不负责状态切换）

@export var visuals_node: Node2D # 用于 Tween 旋转/抖动等

func enter() -> void:
	if animated_sprite and animated_sprite.sprite_frames.has_animation("hit"):
		animated_sprite.play("hit")
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
	else:
		# 无 hit 动画：使用轻微抖动作为通用反馈
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
	# hit 结束后尝试恢复默认动画（如果存在）
	if animated_sprite and animated_sprite.sprite_frames.has_animation("default"):
		animated_sprite.play("default")
	elif animated_sprite and animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")
