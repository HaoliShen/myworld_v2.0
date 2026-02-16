class_name AnimationLogic
extends Node

# 基类主要为了提供统一的接口，方便 AnimationController 管理。
# 虽然不同动画逻辑不同，但它们都需要“进入”和“退出”的状态管理。

@export var animated_sprite: AnimatedSprite2D

func enter() -> void:
	pass

func exit() -> void:
	pass

func process_logic(_delta: float) -> void:
	pass
