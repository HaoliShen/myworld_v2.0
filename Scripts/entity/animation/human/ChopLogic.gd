class_name ChopLogic
extends AnimationLogic

# 砍树动画逻辑
# 负责播放砍树动画，并根据目标位置调整朝向

@export var animation_name: String = "chop"

func enter() -> void:
	if not animated_sprite:
		print("[ChopLogic] enter animated_sprite=null")
		return
		
	print("[ChopLogic] enter sprite=%s anim=%s ctx=%s" % [animated_sprite.name, animation_name, str(context)])
	# 处理翻转
	if context.has("target_pos"):
		var target_pos = context["target_pos"]
		var owner_pos = animated_sprite.global_position
		# 假设 owner 是 animated_sprite 的父节点或其父节点的父节点
		# 或者直接用 animated_sprite.global_position
		
		if target_pos.x < owner_pos.x:
			animated_sprite.flip_h = true
		else:
			animated_sprite.flip_h = false
	
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)
	else:
		push_warning("Animation '%s' not found in SpriteFrames" % animation_name)

func exit() -> void:
	super.exit()

func process_logic(_delta: float) -> void:
	pass
