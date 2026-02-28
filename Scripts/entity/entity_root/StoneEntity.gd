class_name StoneEntity
extends Node2D

## 石头实体逻辑（与 TreeEntity 同构）
## 职责：
## - 作为“地形物体(tile)临时实体化”的承载体，接入 InteractionComponent/BeHit/Health/Animation
## - 死亡时发出 died 信号，交给 TerrainObjectManager 回写数据
## - 等待死亡动画结束后再 queue_free（避免“数据已清除但视觉瞬间消失”的割裂）

signal interaction_finished
signal died

@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var animation_component: AnimationComponent = $AnimationComponent

@export_group("Stats")
## 石头最大生命值（可配置）
@export var max_health: int = 8

## 可选：记录该实体来自的 tile 坐标（当前流程由 TerrainObjectManager 闭包保存，不强依赖这里）
var tile_pos: Vector2i

func _ready() -> void:
	if interaction_component and interaction_component.health_component:
		interaction_component.health_component.max_health = max_health
		interaction_component.health_component.current_health = max_health
		interaction_component.died.connect(_on_died)

	# 供 NPCBrain.scan_for_objects 使用（tag="stone" -> group="Stone"）
	add_to_group("Stone")

func _on_died() -> void:
	print("StoneEntity: Died!")
	died.emit()

	# 等待死亡动画播放完毕再销毁
	var die_state = animation_component.get_node_or_null("Die")
	if die_state and die_state.has_signal("die_finished"):
		if not die_state.die_finished.is_connected(_on_die_anim_finished):
			die_state.die_finished.connect(_on_die_anim_finished)
	else:
		_on_die_anim_finished()

func _on_die_anim_finished() -> void:
	queue_free()
