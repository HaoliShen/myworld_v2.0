class_name MineLogic
extends AnimationLogic

# 挖矿动画逻辑

func enter() -> void:
	if animated_sprite:
		animated_sprite.play("attack") # 暂时复用 attack 动画
	
func exit() -> void:
	pass

func process_logic(_delta: float) -> void:
	pass
