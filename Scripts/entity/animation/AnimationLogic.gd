class_name AnimationLogic
extends Node

# 基类主要为了提供统一的接口，方便 AnimationComponent 管理。
# 虽然不同动画逻辑不同，但它们都需要“进入”和“退出”的状态管理。

@export var animated_sprite: AnimatedSprite2D

# 动画上下文，用于传递额外参数 (如目标位置)
var context: Dictionary = {}

func enter() -> void:
	pass

func exit() -> void:
	context.clear()

func process_logic(_delta: float) -> void:
	pass
