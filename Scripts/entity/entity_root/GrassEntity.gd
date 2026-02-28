class_name GrassEntity
extends Node2D

## 草丛实体逻辑（与 TreeEntity 同构）
## 说明：
## - 当前阶段只关心“交互闭环”是否打通：可抢锁、可受击/结算、可回写、可回收
## - 具体“采集产出/掉落/背包”等可以后续在 died 或 action_received 处接入

signal interaction_finished
signal died

@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var animation_component: AnimationComponent = $AnimationComponent

@export_group("Stats")
## 草的最大生命值（默认 1：采集一次即可清除）
@export var max_health: int = 1

var tile_pos: Vector2i

func _ready() -> void:
	if interaction_component and interaction_component.health_component:
		interaction_component.health_component.max_health = max_health
		interaction_component.health_component.current_health = max_health
		interaction_component.died.connect(_on_died)

	# 供 NPCBrain.scan_for_objects 使用（tag="grass" -> group="Grass"）
	add_to_group("Grass")

func _on_died() -> void:
	print("GrassEntity: Died!")
	died.emit()

	var die_state = animation_component.get_node_or_null("Die")
	if die_state and die_state.has_signal("die_finished"):
		if not die_state.die_finished.is_connected(_on_die_anim_finished):
			die_state.die_finished.connect(_on_die_anim_finished)
	else:
		_on_die_anim_finished()

func _on_die_anim_finished() -> void:
	queue_free()
