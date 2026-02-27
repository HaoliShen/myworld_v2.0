class_name RunLogic
extends AnimationLogic

@export var movement_controller: MovementController

func enter() -> void:
	if animated_sprite:
		animated_sprite.play("walk")

func process_logic(_delta: float) -> void:
	# 可以在这里处理翻转逻辑，或者监听 movement_controller 的信号
	if movement_controller and animated_sprite:
		var vel = movement_controller.current_velocity
		if vel.x != 0:
			animated_sprite.flip_h = vel.x < 0
