class_name AnimationComponent
extends Node2D

# 动画组件 (动画主节点)
# 职责：
# 1. 管理动画状态机 (AnimationLogic)
# 2. 监听 InteractionComponent 信号并切换状态

@export var initial_state: AnimationLogic
@export var animated_sprite: AnimatedSprite2D
@export var interaction_component: InteractionComponent

var _current_state: AnimationLogic
var _root_label: String = ""

func _ready() -> void:
	# 如果没有手动赋值 animated_sprite，尝试在根节点查找
	if not animated_sprite:
		var root = get_owner() if get_owner() else get_parent()
		if root:
			var visuals = root.get_node_or_null("Visuals")
			if visuals:
				animated_sprite = visuals.get_node_or_null("AnimatedSprite2D")
	
	if not interaction_component:
		var root = get_owner() if get_owner() else get_parent()
		if root:
			interaction_component = root.get_node_or_null("InteractionComponent")

	_root_label = str(get_owner().name) if get_owner() else (str(get_parent().name) if get_parent() else str(name))
	var owner_node = get_owner() if get_owner() else get_parent()
	if owner_node is CharacterBody2D or (owner_node and str(owner_node.name) == "TreeEntity"):
		print("[AnimationComponent] %s sprite=%s interaction_component=%s" % [
			_root_label,
			str(animated_sprite.name) if animated_sprite else "null",
			str(interaction_component.name) if interaction_component else "null"
		])
	_setup_signals()
	
	if initial_state:
		change_state(initial_state)

func _is_action_state(state: AnimationLogic) -> bool:
	if not state:
		return false
	return state.name in ["ChopLogic", "MineLogic", "GatherLogic", "AttackLogic"]

func _setup_signals() -> void:
	if interaction_component:
		interaction_component.movement_started.connect(func(_dir):
			if not _is_action_state(_current_state):
				transition_to("walk")
		)
		interaction_component.movement_stopped.connect(func():
			if _current_state and _current_state.name == "walk":
				transition_to("Idle")
		)
		interaction_component.died.connect(func(): transition_to("Die"))
		interaction_component.damaged.connect(func(_amt): transition_to("Hit"))
		interaction_component.animation_requested.connect(func(logic, ctx):
			print("[AnimationComponent] %s animation_requested logic=%s ctx=%s" % [
				_root_label,
				str(logic),
				str(ctx)
			])
			if logic is String:
				transition_to(logic, ctx)
			elif logic is AnimationLogic:
				change_state(logic, ctx)
		)
		interaction_component.interaction_stopped.connect(func():
			if _current_state and _current_state.name == "Die":
				return
			print("[AnimationComponent] %s interaction_stopped -> Idle" % [
				_root_label
			])
			transition_to("Idle")
		)
		# interaction_component.damaged.connect(func(_amt): transition_to("Hit")) # 可选

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
		_current_state.context = context.duplicate()
		if not _current_state.animated_sprite and animated_sprite:
			_current_state.animated_sprite = animated_sprite
		_current_state.enter()

func transition_to(state_name: String, context: Dictionary = {}) -> void:
	var node = get_node_or_null(state_name)
	if node and node is AnimationLogic:
		change_state(node, context)
	else:
		# 仅警告，防止某些实体没有特定状态
		# push_warning("AnimationComponent: State not found " + state_name)
		pass
