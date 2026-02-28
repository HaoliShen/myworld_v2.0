class_name SimpleDieLogic
extends AnimationLogic

## 通用“死亡/消失”动画逻辑（可用于树/石头/草等同构资源点）
## 设计意图：
## - 如果 AnimatedSprite2D 中存在 "die" 动画：优先播放，结束后发 die_finished
## - 否则退化为对 visuals_node 旋转 + 渐隐
##
## 注意：真正 queue_free 由实体脚本负责（便于先播完动画再销毁）

@export var visuals_node: Node2D # 用于 Tween 旋转/渐隐等

signal die_finished

func enter() -> void:
	if animated_sprite and animated_sprite.sprite_frames.has_animation("die"):
		animated_sprite.play("die")
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
	else:
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
