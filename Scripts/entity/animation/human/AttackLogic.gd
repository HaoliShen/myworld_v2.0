class_name AttackLogic
extends AnimationLogic

# 攻击动画逻辑

func enter() -> void:
	if animated_sprite:
		animated_sprite.play("attack")
	
func exit() -> void:
	pass

func process_logic(_delta: float) -> void:
	pass
