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
# 挂起的交互目标：当点击触发但距离不足时，先移动到交互点，抵达后再自动交互
var _pending_interaction_target: Node = null
# 挂起目标的 InteractionComponent 引用，便于取交互点/权威距离与信号绑定
var _pending_interaction_component: InteractionComponent = null
# 玩家移动控制器引用（用于监听 destination_reached 以触发“抵达后交互”）
var _movement_controller: Node = null

func _ready() -> void:
	# 初始化区块坐标
	_current_chunk = MapUtils.world_to_chunk(global_position)
	_update_visuals()
	_connect_signals()

func _connect_signals() -> void:
	if not interaction_component:
		return
	_movement_controller = interaction_component.get_node_or_null("MovementComponent")
	if _movement_controller and _movement_controller.has_signal("destination_reached"):
		if not _movement_controller.destination_reached.is_connected(_on_destination_reached):
			_movement_controller.destination_reached.connect(_on_destination_reached)

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
	# 新的移动指令视为取消当前挂起交互，避免“改了目的地仍自动对旧目标交互”
	_clear_pending_interaction()
	if interaction_component:
		interaction_component.move_to(target_pos)

func command_interact(target: Node) -> void:
	# 交互指令：若不在 BeHit 交互范围内，则先移动到交互点并挂起此次交互
	# 仅当进入 BeHit 权威范围后，才实际调用 interact，避免范围外交互失败与无动画
	if not interaction_component:
		return
	if not target or not is_instance_valid(target):
		_clear_pending_interaction()
		return

	var target_ic := _get_interaction_component(target)
	if not target_ic:
		_clear_pending_interaction()
		interaction_component.interact(target)
		return

	if target_ic.is_instigator_in_interaction_range(self):
		_clear_pending_interaction()
		interaction_component.interact(target)
		return

	_pending_interaction_target = target
	_pending_interaction_component = target_ic
	_bind_pending_target_signals(target)
	interaction_component.move_to(target_ic.get_interaction_position())

func _on_destination_reached() -> void:
	# 抵达移动目标后：若仍有挂起交互且在权威范围内，则执行交互；否则继续靠交互点微调
	if not _pending_interaction_target or not is_instance_valid(_pending_interaction_target):
		_clear_pending_interaction()
		return
	if not _pending_interaction_component or not is_instance_valid(_pending_interaction_component):
		_clear_pending_interaction()
		return

	if not _pending_interaction_component.is_instigator_in_interaction_range(self):
		interaction_component.move_to(_pending_interaction_component.get_interaction_position())
		return

	var ok := interaction_component.interact(_pending_interaction_target)
	_clear_pending_interaction()
	if not ok:
		return

func _clear_pending_interaction() -> void:
	# 清理挂起交互及其信号绑定
	_unbind_pending_target_signals()
	_pending_interaction_target = null
	_pending_interaction_component = null

func _bind_pending_target_signals(target: Node) -> void:
	# 绑定目标的销毁/死亡信号，防止在移动途中目标消失导致悬挂引用
	if not target:
		return
	if target.tree_exiting.is_connected(_on_pending_target_gone) == false:
		target.tree_exiting.connect(_on_pending_target_gone)
	if target.has_signal("died"):
		if target.died.is_connected(_on_pending_target_gone) == false:
			target.died.connect(_on_pending_target_gone)

func _unbind_pending_target_signals() -> void:
	# 解除前面绑定的目标生命周期信号
	if not _pending_interaction_target or not is_instance_valid(_pending_interaction_target):
		return
	if _pending_interaction_target.tree_exiting.is_connected(_on_pending_target_gone):
		_pending_interaction_target.tree_exiting.disconnect(_on_pending_target_gone)
	if _pending_interaction_target.has_signal("died") and _pending_interaction_target.died.is_connected(_on_pending_target_gone):
		_pending_interaction_target.died.disconnect(_on_pending_target_gone)

func _on_pending_target_gone() -> void:
	# 目标离开场景或死亡时，取消挂起交互
	_clear_pending_interaction()

func _update_visuals() -> void:
	if selection_marker:
		selection_marker.visible = _is_selected

func _get_interaction_component(target: Node) -> InteractionComponent:
	# 从目标节点解析 InteractionComponent：支持直接组件、Area2D 的父级、或标准子节点
	if target is InteractionComponent:
		return target
	if target is Area2D:
		var parent = target.get_parent()
		if parent:
			var candidate_from_parent = parent.get_node_or_null("InteractionComponent")
			if candidate_from_parent is InteractionComponent:
				return candidate_from_parent
			if parent is InteractionComponent:
				return parent
	var candidate_from_self = target.get_node_or_null("InteractionComponent")
	if candidate_from_self is InteractionComponent:
		return candidate_from_self
	return null
