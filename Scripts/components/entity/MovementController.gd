class_name MovementController
extends Node

signal movement_started(direction: Vector2)
signal movement_stopped
signal destination_reached

@export_group("Dependencies")
@export var character_body: CharacterBody2D
@export var navigation_agent: NavigationAgent2D

@export_group("Settings")
@export var speed: float = 100.0
@export var acceleration: float = 1000.0
@export var friction: float = 1000.0

var current_velocity: Vector2 = Vector2.ZERO
var _is_moving: bool = false

func _ready() -> void:
	if not character_body:
		push_warning("MovementController: CharacterBody2D not assigned!")
	if not navigation_agent:
		push_warning("MovementController: NavigationAgent2D not assigned!")
	else:
		_connect_nav_signals()

func _connect_nav_signals() -> void:
	if not navigation_agent.velocity_computed.is_connected(_on_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_velocity_computed)
	if not navigation_agent.navigation_finished.is_connected(_on_navigation_finished):
		navigation_agent.navigation_finished.connect(_on_navigation_finished)

func _physics_process(delta: float) -> void:
	if not character_body: return
	
	if not _is_moving:
		_apply_friction(delta)
	else:
		_process_navigation(delta)
	
	character_body.velocity = current_velocity
	character_body.move_and_slide()
	current_velocity = character_body.velocity

func move_to(target_pos: Vector2) -> void:
	if not navigation_agent: return
	
	_is_moving = true
	navigation_agent.target_position = target_pos
	movement_started.emit((target_pos - character_body.global_position).normalized())

func stop() -> void:
	_is_moving = false
	if navigation_agent:
		navigation_agent.set_velocity(Vector2.ZERO)
	movement_stopped.emit()

func _process_navigation(delta: float) -> void:
	if not navigation_agent: return
	
	if navigation_agent.is_navigation_finished():
		stop()
		destination_reached.emit()
		return
		
	var next_path_pos = navigation_agent.get_next_path_position()
	var current_pos = character_body.global_position
	var new_velocity = (next_path_pos - current_pos).normalized() * speed
	
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		_apply_velocity(new_velocity, delta)

func _apply_velocity(target_velocity: Vector2, delta: float) -> void:
	current_velocity = current_velocity.move_toward(target_velocity, acceleration * delta)

func _apply_friction(delta: float) -> void:
	current_velocity = current_velocity.move_toward(Vector2.ZERO, friction * delta)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if _is_moving:
		current_velocity = safe_velocity

func _on_navigation_finished() -> void:
	stop()
	destination_reached.emit()
