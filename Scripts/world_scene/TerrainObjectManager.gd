class_name TerrainObjectManager
extends Node

# 管理器，负责处理地形物体（树木、石头）的动态实例化和销毁
# 挂载位置: World/Managers/TerrainObjectManager

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

# 实体场景预制体
# TODO: 实际路径可能需要根据项目调整
const TreeEntityScene = preload("res://Scenes/Entities/TreeEntity.tscn")
# const RockEntityScene = preload("res://Scenes/Entities/RockEntity.tscn")

# 活跃的实体字典
# Key: Vector2i (Tile Coordinate) -> Value: Node2D (Entity Instance)
var active_entities: Dictionary = {}

# 依赖引用
var world_manager: Node
var map_controller: GlobalMapController

func _ready() -> void:
	# 获取依赖
	world_manager = get_node_or_null("../WorldManager")
	var env = get_node_or_null("/root/World/Environment")
	if env and env is GlobalMapController:
		map_controller = env
	
	if not world_manager:
		push_error("TerrainObjectManager: WorldManager not found!")
	if not map_controller:
		push_error("TerrainObjectManager: GlobalMapController not found!")

# 请求与指定位置的瓦片交互
# 如果实体已存在，直接返回；否则创建新实体
func request_interaction(tile_pos: Vector2i, layer: int = -1) -> Node2D:
	if active_entities.has(tile_pos):
		return active_entities[tile_pos]
	
	# 检查该位置是否有对应的物体数据
	var chunk_data = _get_chunk_data(tile_pos)
	if not chunk_data:
		print("[TerrainObjectManager] request_interaction tile=%s no_chunk_data" % [str(tile_pos)])
		return null
		
	var local_pos = _MapUtils.tile_to_local(tile_pos)
	
	var target_layer = layer
	var object_id = -1
	
	if target_layer == -1:
		# 自动扫描所有层级 (从上到下)，找到第一个可交互物体
		# 假设最大层级为 4 (ExH_4) 或更高，根据 Constants 里的定义覆盖
		for l in range(4, -1, -1):
			var id = chunk_data.get_object(local_pos.x, local_pos.y, l)
			if id > 0:
				object_id = id
				target_layer = l
				break
	else:
		object_id = chunk_data.get_object(local_pos.x, local_pos.y, target_layer)
	
	if object_id <= 0:
		print("[TerrainObjectManager] request_interaction tile=%s no_object layer=%s" % [str(tile_pos), str(target_layer)])
		return null
		
	# 根据 ID 创建实体
	var entity = _create_entity(object_id, tile_pos, target_layer)
	if entity:
		print("[TerrainObjectManager] created entity=%s tile=%s object_id=%s layer=%s" % [
			str(entity.name),
			str(tile_pos),
			str(object_id),
			str(target_layer)
		])
		active_entities[tile_pos] = entity
		# 隐藏底层的 Tile (使用 GlobalMapController.set_cell_at)
		_hide_tile_visual(tile_pos, object_id)
		
		# 监听实体信号
		if entity.has_signal("interaction_finished"):
			entity.interaction_finished.connect(_on_interaction_finished.bind(tile_pos, target_layer, object_id))
		if entity.has_signal("died"):
			entity.died.connect(_on_entity_died.bind(tile_pos, target_layer))
			
	return entity

## 扫描指定区域内的物体
## @param center_pos: 搜索中心世界坐标
## @param radius: 搜索半径
## @param tag: 物体标签 (如 "tree", "stone")
## @return: Array[Dictionary] - { "type": "entity"|"tile", "position": Vector2, "target": Node|Vector2i }
func scan_for_objects(center_pos: Vector2, radius: float, tag: String) -> Array:
	var results = []
	var radius_sq = radius * radius
	
	# 1. 获取标签对应的 ID 列表
	var target_ids = _C.OBJECT_TAG_TABLE.get(tag, [])
	if target_ids.is_empty():
		return results
		
	# 2. 扫描活跃实体 (优先)
	# 注意：active_entities 是以 tile_pos 为 key 的
	for tile_pos in active_entities:
		var entity = active_entities[tile_pos]
		if not is_instance_valid(entity): continue
		
		# 检查距离
		var dist_sq = entity.global_position.distance_squared_to(center_pos)
		if dist_sq > radius_sq: continue
		
		# 检查是否匹配标签 (假设 Entity 都在对应 Group 中，或者通过 metadata)
		# 简单起见，我们检查 Entity 是否在 tag 对应的 group 中 (首字母大写)
		# 或者检查 entity 的原始 ID (目前 entity 没有存 ID，除了在闭包里)
		# 更好的方法是 Entity 自身有 "tags" 属性或方法
		var match_tag = false
		if entity.is_in_group(tag.capitalize()): # "tree" -> "Tree"
			match_tag = true
		
		if match_tag:
			results.append({
				"type": "entity",
				"position": entity.global_position,
				"target": entity,
				"dist_sq": dist_sq
			})
	
	# 3. 扫描静态 Tile
	if world_manager:
		var center_tile = _MapUtils.world_to_tile(center_pos)
		var tile_radius = int(radius / _C.TILE_SIZE) + 1
		
		for y in range(center_tile.y - tile_radius, center_tile.y + tile_radius + 1):
			for x in range(center_tile.x - tile_radius, center_tile.x + tile_radius + 1):
				var tile = Vector2i(x, y)
				
				# 如果该位置已有活跃实体，跳过 (已在上面处理)
				if active_entities.has(tile): continue
				
				var world_pos = _MapUtils.tile_to_world_center(tile)
				var dist_sq = world_pos.distance_squared_to(center_pos)
				if dist_sq > radius_sq: continue
				
				var chunk_data = _get_chunk_data(tile)
				if not chunk_data: continue
				
				var local = _MapUtils.tile_to_local(tile)
				
				# 检查每一层
				for id in target_ids:
					# 查找该 ID 所在的层
					var layer = _C.OBJECT_RENDER_LAYER_TABLE.get(id, -1)
					if layer != -1:
						if chunk_data.get_object(local.x, local.y, layer) == id:
							results.append({
								"type": "tile",
								"position": world_pos,
								"target": tile, # Vector2i
								"dist_sq": dist_sq
							})
							break # 找到一个就够了
	
	# 按距离排序
	results.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	return results

func _create_entity(object_id: int, tile_pos: Vector2i, layer: int) -> Node2D:
	var scene: PackedScene = null
	
	match object_id:
		_C.ID_TREE:
			scene = TreeEntityScene
		# _C.ID_STONE:
		# 	scene = RockEntityScene
			
	if not scene:
		print("[TerrainObjectManager] _create_entity no_scene object_id=%s" % [str(object_id)])
		return null
		
	var instance = scene.instantiate()
	# 设置位置
	instance.global_position = _MapUtils.tile_to_world_center(tile_pos)
	
	# 添加到场景 (添加到 EntityContainer 以便正确 Y-Sort)
	var container = map_controller.get_node_or_null("EntityContainer")
	if not container:
		container = map_controller # Fallback
	container.add_child(instance)
	
	return instance

func _get_chunk_data(tile_pos: Vector2i):
	if not world_manager: return null
	var world_pos = _MapUtils.tile_to_world_center(tile_pos)
	return world_manager.get_chunk_data_at(world_pos)

func _hide_tile_visual(tile_pos: Vector2i, object_id: int) -> void:
	if not map_controller: return
	var world_pos = _MapUtils.tile_to_world_center(tile_pos)
	
	# Determine render layer from object ID
	var render_layer = _C.OBJECT_RENDER_LAYER_TABLE.get(object_id, _C.Layer.DECORATION)
	
	# Hide by setting tile_id to -1 (set_cell_at handles this)
	map_controller.set_cell_at(world_pos, render_layer, -1)

func _restore_tile_visual(tile_pos: Vector2i, layer: int, object_id: int) -> void:
	if not map_controller: return
	var world_pos = _MapUtils.tile_to_world_center(tile_pos)
	
	# Determine render layer from object ID
	var render_layer = _C.OBJECT_RENDER_LAYER_TABLE.get(object_id, _C.Layer.DECORATION)
	
	# Restore by setting tile_id back to object_id (set_cell_at handles atlas lookup)
	map_controller.set_cell_at(world_pos, render_layer, object_id)

func _on_interaction_finished(tile_pos: Vector2i, layer: int, object_id: int) -> void:
	# 交互结束（但没死），立即回收实体并恢复 Tile 视觉
	# 设计意图：
	# - 只要不在砍树/交互中，就不保留临时实体，降低竞态与生命周期复杂度
	# - 回收前必须确认当前没有交互者持有锁，避免“未抢到锁的一方”误触发回收影响正在交互的一方
	if not active_entities.has(tile_pos):
		return
	var entity = active_entities[tile_pos]
	if not is_instance_valid(entity):
		active_entities.erase(tile_pos)
		return
	var comp := entity.get_node_or_null("InteractionComponent") as InteractionComponent
	if comp and comp.be_hit_component and comp.be_hit_component.is_busy():
		return
	_destroy_entity(tile_pos, layer, object_id)

func _destroy_entity(tile_pos: Vector2i, layer: int, object_id: int) -> void:
	if not active_entities.has(tile_pos): return
		
	var entity = active_entities[tile_pos]
	active_entities.erase(tile_pos)
	
	if is_instance_valid(entity):
		entity.queue_free()
		
	# 恢复 Tile 视觉
	_restore_tile_visual(tile_pos, layer, object_id)
	# print("TerrainObjectManager: Entity destroyed and tile restored at ", tile_pos)

func _on_entity_died(tile_pos: Vector2i, layer: int) -> void:
	# 实体死亡（被砍倒）
	# print("TerrainObjectManager: Entity died at ", tile_pos)
	
	# 1. 清除 Entity 记录
	if active_entities.has(tile_pos):
		active_entities.erase(tile_pos)
		
	# 2. 修改真实数据 (WorldManager) - 将该位置设为空
	if world_manager:
		var world_pos = _MapUtils.tile_to_world_center(tile_pos)
		world_manager.set_block_at(world_pos, layer, -1) # -1 = Remove
		
	# 注意：Entity 自身的销毁 (queue_free) 由 Entity 自己在播放完死亡动画后处理
	# 这里不需要手动 queue_free，也不需要恢复 Tile (因为数据已经变成空了)
