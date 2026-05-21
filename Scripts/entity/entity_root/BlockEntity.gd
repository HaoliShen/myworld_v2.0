class_name BlockEntity
extends Node2D

const _C = preload("res://Scripts/data/Constants.gd")
const _ObjectCatalog = preload("res://Scripts/data/ObjectCatalog.gd")

signal interaction_finished
signal died

@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var interaction_area: Area2D = $InteractionArea
@onready var collision_shape: CollisionShape2D = $InteractionArea/CollisionShape
@onready var be_hit_component: BeHitComponent = $InteractionComponent/BeHit
@onready var health_component: HealthComponent = $InteractionComponent/HealthComponent
@onready var visuals: Node2D = $Visuals
@onready var sprite: Sprite2D = $Visuals/Sprite2D

var object_id: int = -1
var tile_pos: Vector2i = Vector2i.ZERO
var object_layer: int = -1
var definition: Dictionary = {}


func setup_from_definition(id: int, source_tile: Vector2i, layer: int, def: Dictionary) -> void:
	object_id = id
	tile_pos = source_tile
	object_layer = layer
	definition = def.duplicate(true)
	if is_node_ready():
		_apply_definition()


func _ready() -> void:
	if definition.is_empty() and object_id > 0:
		definition = _ObjectCatalog.get_definition(object_id)
	_apply_definition()


func get_drops(_action: StringName = &"") -> Dictionary:
	if definition.has("drops"):
		return definition.get("drops", {}).duplicate(true)
	return _ObjectCatalog.get_drops(object_id)


func _apply_definition() -> void:
	if object_id <= 0:
		return

	name = String(definition.get("key", "block_%d" % object_id)).to_pascal_case()
	add_to_group("Block")
	for tag in definition.get("tags", []):
		add_to_group(String(tag).capitalize())

	if health_component:
		var max_health := int(definition.get("max_health", 1))
		health_component.max_health = max_health
		health_component.current_health = max_health
	if be_hit_component:
		be_hit_component.actions = _ObjectCatalog.get_actions(object_id)
		be_hit_component.interaction_label = String(definition.get("display_name", "Block"))
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rect := collision_shape.shape as RectangleShape2D
		rect.size = definition.get("collision_size", Vector2(16, 16))
	if interaction_component and not interaction_component.died.is_connected(_on_died):
		interaction_component.died.connect(_on_died)
	if interaction_component and not interaction_component.damaged.is_connected(_on_damaged):
		interaction_component.damaged.connect(_on_damaged)

	_apply_visual()


func _apply_visual() -> void:
	var cfg := _ObjectCatalog.get_resource_config(object_id)
	if cfg.is_empty() or sprite == null:
		return
	var tileset: TileSet = load(_C.OBJECT_TILESET)
	if tileset == null:
		return
	var source_id := int(cfg.get("source_id", -1))
	if source_id < 0 or not tileset.has_source(source_id):
		return
	var source := tileset.get_source(source_id)
	if not source is TileSetAtlasSource:
		return
	var atlas_values = cfg.get("atlas", [])
	var atlas_coord := Vector2i.ZERO
	if atlas_values is Array and not atlas_values.is_empty():
		atlas_coord = atlas_values[0]
	elif atlas_values is Vector2i:
		atlas_coord = atlas_values
	var atlas_source := source as TileSetAtlasSource
	var region_size := atlas_source.texture_region_size
	if region_size == Vector2i.ZERO:
		region_size = Vector2i(_C.TILE_SIZE, _C.TILE_SIZE)
	var texture := AtlasTexture.new()
	texture.atlas = atlas_source.texture
	texture.region = Rect2(atlas_coord * region_size, region_size)
	sprite.texture = texture
	sprite.position = definition.get("sprite_offset", Vector2.ZERO)
	sprite.scale = definition.get("sprite_scale", Vector2.ONE)


func _on_damaged(_amount: int) -> void:
	if visuals == null:
		return
	var tween := create_tween()
	tween.tween_property(visuals, "rotation_degrees", 5.0, 0.04)
	tween.tween_property(visuals, "rotation_degrees", -5.0, 0.04)
	tween.tween_property(visuals, "rotation_degrees", 0.0, 0.04)


func _on_died() -> void:
	died.emit()
	if visuals:
		var tween := create_tween()
		tween.tween_property(visuals, "rotation_degrees", 90.0, 0.2)
		tween.tween_property(visuals, "modulate:a", 0.0, 0.25)
		tween.finished.connect(queue_free)
	else:
		queue_free()
