class_name Player
extends CharacterBody2D

# 信号
signal selection_changed(is_selected: bool)

# 组件引用
@onready var movement_controller: MovementController = $MovementComponent
@onready var animation_controller: AnimationController = $AnimationComponent
@onready var health_component: HealthComponent = $HealthComponent
# @onready var interactable_component: InteractableComponent = $InteractionShape # 已移除脚本
@onready var interaction_controller: InteractionController = $InteractionController
@onready var visuals: AnimatedSprite2D = $Visuals/AnimatedSprite2D
@onready var selection_marker: Sprite2D = $Visuals/SelectionMarker

var _is_selected: bool = false
var _current_chunk: Vector2i = Vector2i.ZERO

func _ready() -> void:
	# 初始化组件连接
	_setup_components()
	_update_visuals()
	
	# 初始化区块坐标
	_current_chunk = MapUtils.world_to_chunk(global_position)

func _physics_process(_delta: float) -> void:
	_check_chunk_update()

func _check_chunk_update() -> void:
	var new_chunk := MapUtils.world_to_chunk(global_position)
	if new_chunk != _current_chunk:
		var old_chunk = _current_chunk
		_current_chunk = new_chunk
		SignalBus.player_chunk_changed.emit(old_chunk, new_chunk)
		SignalBus.player_position_updated.emit(global_position)

func _setup_components() -> void:
	# 连接移动控制器信号到动画控制器
	if movement_controller and animation_controller:
		movement_controller.movement_started.connect(func(_dir): animation_controller.transition_to("walk"))
		movement_controller.movement_stopped.connect(func(): animation_controller.transition_to("Idle"))

func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	if selection_marker:
		selection_marker.visible = selected
	selection_changed.emit(selected)

# 命令接口 (供管理器调用)
func command_move_to(target_pos: Vector2) -> void:
	if movement_controller:
		movement_controller.move_to(target_pos)

func command_interact(target: Node) -> void:
	# 交互逻辑：先移动到范围，再执行交互
	# 使用 InteractionController 进行交互
	if interaction_controller:
		interaction_controller.interact(target)
	else:
		# 后备逻辑 (兼容旧代码)
		if target.has_method("try_interact"):
			target.try_interact(self)

func _update_visuals() -> void:
	if selection_marker:
		selection_marker.visible = _is_selected
	
	# 播放动画逻辑的辅助方法 (供 InteractionBehavior 调用)
func play_animation_logic(logic_node: AnimationLogic) -> void:
	if animation_controller:
		animation_controller.change_state(logic_node)
