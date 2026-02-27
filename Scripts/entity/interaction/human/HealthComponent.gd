class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int)
signal died

@export var max_health: int = 100
@export var invincibility_time: float = 0.0

var current_health: int:
	set(value):
		var old := current_health
		current_health = clampi(value, 0, max_health)
		if current_health != old:
			health_changed.emit(current_health, max_health)

var _invincible: bool = false

func _ready() -> void:
	current_health = max_health

func take_damage(amount: int, source: Node = null) -> int:
	if _invincible or current_health <= 0:
		return 0

	var actual := mini(amount, current_health)
	current_health -= actual
	damaged.emit(actual, source)

	if current_health <= 0:
		died.emit()
	elif invincibility_time > 0:
		_start_invincibility()

	return actual

func heal(amount: int) -> int:
	var actual := mini(amount, max_health - current_health)
	current_health += actual
	if actual > 0:
		healed.emit(actual)
	return actual

func _start_invincibility() -> void:
	_invincible = true
	await get_tree().create_timer(invincibility_time).timeout
	_invincible = false
