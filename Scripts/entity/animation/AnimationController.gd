class_name AnimationController
extends Node

@export var initial_state: AnimationLogic
@export var animated_sprite: AnimatedSprite2D

var _current_state: AnimationLogic

func _ready() -> void:
	if initial_state:
		change_state(initial_state)

func _process(delta: float) -> void:
	if _current_state:
		_current_state.process_logic(delta)

func change_state(new_state: AnimationLogic, context: Dictionary = {}) -> void:
	if _current_state == new_state and context.is_empty():
		return
		
	if _current_state:
		_current_state.exit()
		
	_current_state = new_state
	
	if _current_state:
		# 传递上下文
		_current_state.context = context.duplicate()
		
		# 确保注入依赖（如果子节点没有手动配置）
		if not _current_state.animated_sprite and animated_sprite:
			_current_state.animated_sprite = animated_sprite
		_current_state.enter()

# 供外部组件调用的辅助方法
func transition_to(state_name: String, context: Dictionary = {}) -> void:
	var node = get_node_or_null(state_name)
	if node and node is AnimationLogic:
		change_state(node, context)
	else:
		push_warning("AnimationController: State not found " + state_name)
