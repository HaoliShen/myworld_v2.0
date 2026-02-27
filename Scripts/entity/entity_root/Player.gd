class_name Player
extends CharacterBody2D

# 信号
signal selection_changed(is_selected: bool)

# 组件引用 (只引用主节点)
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var animation_component: AnimationComponent = $AnimationComponent
@onready var visuals: AnimatedSprite2D = $Visuals/AnimatedSprite2D
@onready var selection_marker: Sprite2D = $Visuals/SelectionMarker

var _is_selected: bool = false
var _current_chunk: Vector2i = Vector2i.ZERO

func _ready() -> void:
	# 初始化区块坐标
	_current_chunk = MapUtils.world_to_chunk(global_position)
	_update_visuals()

func _physics_process(_delta: float) -> void:
	_check_chunk_update()

func _check_chunk_update() -> void:
	var new_chunk := MapUtils.world_to_chunk(global_position)
	if new_chunk != _current_chunk:
		var old_chunk = _current_chunk
		_current_chunk = new_chunk
		SignalBus.player_chunk_changed.emit(old_chunk, new_chunk)
		SignalBus.player_position_updated.emit(global_position)

func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	if selection_marker:
		selection_marker.visible = selected
	selection_changed.emit(selected)

# 命令接口 (供管理器调用)
func command_move_to(target_pos: Vector2) -> void:
	if interaction_component:
		interaction_component.move_to(target_pos)

func command_interact(target: Node) -> void:
	# 交互逻辑：先移动到范围，再执行交互 (通常由 Behavior 处理移动，这里只负责传递意图)
	# 目前的 InteractionComponent.interact 会尝试寻找 behavior 并执行
	if interaction_component:
		interaction_component.interact(target)

func _update_visuals() -> void:
	if selection_marker:
		selection_marker.visible = _is_selected
