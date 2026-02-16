class_name MovementComponent
extends NavigationAgent2D

signal movement_started(direction: Vector2)
signal movement_stopped
signal destination_reached
# velocity_computed signal is already defined in NavigationAgent2D

@export var speed: float = 200.0
@export var acceleration: float = 1000.0
@export var friction: float = 1000.0

var current_velocity: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO
var _is_moving: bool = false
var _parent: CharacterBody2D

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D
	if not _parent:
		push_error("MovementComponent must be child of CharacterBody2D")
		set_physics_process(false)
		return
		
	_connect_nav_signals()

# initialize function removed as we are the agent now

func _connect_nav_signals() -> void:
	if not velocity_computed.is_connected(_on_velocity_computed):
		velocity_computed.connect(_on_velocity_computed)
	if not navigation_finished.is_connected(_on_navigation_finished):
		navigation_finished.connect(_on_navigation_finished)

func _physics_process(delta: float) -> void:
	if not _is_moving:
		_apply_friction(delta)
	else:
		_process_navigation(delta)
	
	_parent.velocity = current_velocity
	_parent.move_and_slide()
	current_velocity = _parent.velocity

func move_to(target_pos: Vector2) -> void:
	_target_position = target_pos
	_is_moving = true
	
	target_position = target_pos
	movement_started.emit((target_pos - _parent.global_position).normalized())

func stop() -> void:
	_is_moving = false
	set_velocity(Vector2.ZERO)
	movement_stopped.emit()

func _process_navigation(delta: float) -> void:
	if is_navigation_finished():
		stop()
		destination_reached.emit()
		return
		
	var next_path_pos = get_next_path_position()
	var current_pos = _parent.global_position
	var new_velocity = (next_path_pos - current_pos).normalized() * speed
	
	if avoidance_enabled:
		set_velocity(new_velocity)
	else:
		_apply_velocity(new_velocity, delta)

func _apply_velocity(target_velocity: Vector2, delta: float) -> void:
	current_velocity = current_velocity.move_toward(target_velocity, acceleration * delta)

func _apply_friction(delta: float) -> void:
	current_velocity = current_velocity.move_toward(Vector2.ZERO, friction * delta)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if _is_moving:
		current_velocity = safe_velocity
		# We don't need to emit a custom velocity_computed since the agent already has one,
		# but if other components listen to MovementComponent's signal specifically, we might want to keep it.
		# However, NavigationAgent2D has velocity_computed.
		# But wait, the original code had `signal velocity_computed(safe_velocity: Vector2)`
		# which shadowed the built-in signal of NavigationAgent2D (if it had one, but it does).
		# NavigationAgent2D signal: velocity_computed(safe_velocity: Vector2)
		# So we can just use the inherited signal.
		# But we are connecting to it ourselves.
		pass

func _on_navigation_finished() -> void:
	stop()
	destination_reached.emit()
