class_name ObjectCatalog
extends RefCounted

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

const BLOCK_ENTITY_SCENE := "res://Scenes/Entities/BlockEntity.tscn"

const DEFINITIONS: Dictionary = {
	_C.ID_GRASS: {
		"key": "grass",
		"display_name": "Grass",
		"scene": BLOCK_ENTITY_SCENE,
		"layer": _C.Layer.DECORATION,
		"max_health": 1,
		"actions": [&"gather"],
		"destroy_action": &"gather",
		"preferred_tool": "hand",
		"drop_policy": "inventory",
		"drops": { _C.MATERIAL_FIBER: 1 },
		"tags": ["grass"],
		"collision_size": Vector2(14, 14),
	},
	_C.ID_TREE: {
		"key": "tree",
		"display_name": "Tree",
		"scene": BLOCK_ENTITY_SCENE,
		"layer": _C.Layer.DECORATION,
		"max_health": 5,
		"actions": [&"chop"],
		"destroy_action": &"chop",
		"preferred_tool": "axe",
		"drop_policy": "inventory",
		"drops": { _C.MATERIAL_WOOD: 2 },
		"tags": ["tree"],
		"collision_size": Vector2(16, 16),
	},
	_C.ID_STONE: {
		"key": "stone",
		"display_name": "Stone",
		"scene": BLOCK_ENTITY_SCENE,
		"layer": _C.Layer.OBSTACLE,
		"max_health": 8,
		"actions": [&"mine"],
		"destroy_action": &"mine",
		"preferred_tool": "pickaxe",
		"drop_policy": "inventory",
		"drops": { _C.MATERIAL_STONE: 1 },
		"tags": ["stone"],
		"collision_size": Vector2(16, 16),
	},
	_C.ID_WOOD_WALL: {
		"key": "wood_wall",
		"display_name": "Wood Wall",
		"scene": BLOCK_ENTITY_SCENE,
		"layer": _C.Layer.OBSTACLE,
		"buildable": true,
		"build_cost": { _C.MATERIAL_WOOD: 2 },
		"place_rules": ["not_water", "empty_layer"],
		"max_health": 4,
		"actions": [&"demolish", &"chop"],
		"destroy_action": &"demolish",
		"preferred_tool": "axe",
		"drop_policy": "inventory",
		"drops": { _C.MATERIAL_WOOD: 1 },
		"tags": ["building", "wall", "wood"],
		"structure_tags": ["wall"],
		"collision_size": Vector2(16, 16),
	},
	_C.ID_STONE_WALL: {
		"key": "stone_wall",
		"display_name": "Stone Wall",
		"scene": BLOCK_ENTITY_SCENE,
		"layer": _C.Layer.OBSTACLE,
		"buildable": true,
		"build_cost": { _C.MATERIAL_STONE: 2 },
		"place_rules": ["not_water", "empty_layer"],
		"max_health": 8,
		"actions": [&"demolish", &"mine"],
		"destroy_action": &"demolish",
		"preferred_tool": "pickaxe",
		"drop_policy": "inventory",
		"drops": { _C.MATERIAL_STONE: 1 },
		"tags": ["building", "wall", "stone"],
		"structure_tags": ["wall"],
		"collision_size": Vector2(16, 16),
	},
	_C.ID_WOOD_FLOOR: {
		"key": "wood_floor",
		"display_name": "Wood Floor",
		"scene": BLOCK_ENTITY_SCENE,
		"layer": _C.Layer.DECORATION,
		"buildable": true,
		"build_cost": { _C.MATERIAL_WOOD: 1 },
		"place_rules": ["not_water", "empty_layer"],
		"max_health": 3,
		"actions": [&"demolish", &"chop"],
		"destroy_action": &"demolish",
		"preferred_tool": "axe",
		"drop_policy": "inventory",
		"drops": { _C.MATERIAL_WOOD: 1 },
		"tags": ["building", "floor", "wood"],
		"structure_tags": ["floor"],
		"collision_size": Vector2(16, 16),
	},
}


static func has_definition(object_id: int) -> bool:
	return DEFINITIONS.has(object_id)


static func get_definition(object_id: int) -> Dictionary:
	return DEFINITIONS.get(object_id, {})


static func get_scene_path(object_id: int) -> String:
	return String(get_definition(object_id).get("scene", ""))


static func get_display_name(object_id: int) -> String:
	var def := get_definition(object_id)
	if def.has("display_name"):
		return String(def.display_name)
	return String(_C.BUILD_DISPLAY_NAMES.get(object_id, object_id))


static func get_render_layer(object_id: int, fallback: int = _C.Layer.DECORATION) -> int:
	return int(get_definition(object_id).get(
		"layer",
		_C.OBJECT_RENDER_LAYER_TABLE.get(object_id, fallback)
	))


static func is_buildable(object_id: int) -> bool:
	return bool(get_definition(object_id).get("buildable", false))


static func get_buildable_ids() -> Array[int]:
	var ids: Array[int] = []
	for object_id in DEFINITIONS.keys():
		if is_buildable(int(object_id)):
			ids.append(int(object_id))
	ids.sort()
	return ids


static func get_build_cost(object_id: int) -> Dictionary:
	if get_definition(object_id).has("build_cost"):
		return get_definition(object_id).get("build_cost", {}).duplicate(true)
	return _C.BUILD_COSTS.get(object_id, {}).duplicate(true)


static func get_max_health(object_id: int, fallback: int = 1) -> int:
	return int(get_definition(object_id).get("max_health", fallback))


static func get_actions(object_id: int) -> Array[StringName]:
	var raw: Array = get_definition(object_id).get("actions", [])
	var out: Array[StringName] = []
	for action in raw:
		out.append(StringName(action))
	return out


static func get_destroy_action(object_id: int) -> StringName:
	return StringName(get_definition(object_id).get("destroy_action", &""))


static func get_preferred_tool(object_id: int) -> String:
	return String(get_definition(object_id).get("preferred_tool", ""))


static func get_drop_policy(object_id: int) -> String:
	return String(get_definition(object_id).get("drop_policy", "inventory"))


static func get_drops(object_id: int) -> Dictionary:
	return get_definition(object_id).get("drops", {}).duplicate(true)


static func get_tags(object_id: int) -> Array:
	return get_definition(object_id).get("tags", []).duplicate()


static func has_structure_tag(object_id: int, tag: String) -> bool:
	var tags: Array = get_definition(object_id).get("structure_tags", [])
	return tags.has(tag)


static func get_resource_config(object_id: int) -> Dictionary:
	return _C.OBJECT_RESOURCE_TABLE.get(object_id, {})


static func can_place(object_id: int, tile_pos: Vector2i, world_manager: Node) -> Dictionary:
	if not is_buildable(object_id):
		return { "ok": false, "reason": "Object is not buildable" }
	if world_manager == null:
		return { "ok": false, "reason": "World is not ready" }

	var world_pos := _MapUtils.tile_to_world_center(tile_pos)
	var chunk_data = world_manager.get_chunk_data_at(world_pos)
	if chunk_data == null:
		return { "ok": false, "reason": "Chunk is not loaded" }

	var local_coord := _MapUtils.tile_to_local(tile_pos)
	var rules: Array = get_definition(object_id).get("place_rules", [])
	if rules.has("not_water") and chunk_data.is_water(local_coord.x, local_coord.y):
		return { "ok": false, "reason": "Cannot build on water" }
	if rules.has("empty_layer"):
		var layer := get_render_layer(object_id)
		var existing_object = chunk_data.get_object(local_coord.x, local_coord.y, layer)
		if existing_object > 0:
			return { "ok": false, "reason": "This position is occupied" }

	return { "ok": true, "reason": "" }
