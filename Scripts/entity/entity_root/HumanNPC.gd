class_name HumanNPC
extends CharacterBody2D

# 信号
signal selection_changed(is_selected: bool)
signal movement_reached
signal interaction_stopped
signal interaction_started(target: Node)

# 组件引用 (只引用主节点)
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var animation_component: AnimationComponent = $AnimationComponent
@onready var visuals: Node2D = $Visuals
@onready var brain: NPCBrain = $NPCBrain

var _is_selected: bool = false
var _current_chunk: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_connect_signals()
	_current_chunk = MapUtils.world_to_chunk(global_position)
	_update_visuals()

func _connect_signals() -> void:
	if interaction_component:
		interaction_component.interaction_stopped.connect(func(): interaction_stopped.emit())
		interaction_component.interaction_started.connect(func(t): interaction_started.emit(t))
		
		# MovementController 通常挂载在 InteractionComponent 下，尝试获取并连接信号
		var movement = interaction_component.get_node_or_null("MovementComponent")
		if movement and movement.has_signal("destination_reached"):
			movement.destination_reached.connect(func(): movement_reached.emit())

func _physics_process(_delta: float) -> void:
	_check_chunk_update()

func _check_chunk_update() -> void:
	var new_chunk := MapUtils.world_to_chunk(global_position)
	if new_chunk != _current_chunk:
		var old_chunk = _current_chunk
		_current_chunk = new_chunk
		# Optional: Emit signal if needed

func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	selection_changed.emit(selected)

func _update_visuals() -> void:
	pass

# 供 NPCBrain 调用的接口 (模拟玩家指令)
func command_move_to(target_pos: Vector2) -> void:
	if interaction_component:
		interaction_component.move_to(target_pos)

func command_stop_move() -> void:
	if interaction_component:
		interaction_component.stop_move()

func command_interact(target: Node) -> bool:
	if interaction_component:
		return interaction_component.interact(target)
	return false
