class_name GlobalMapController
extends Node2D

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")
const _ChunkVisual = preload("res://Scripts/components/ChunkVisual.gd")
## Chunk 场景模板
const ChunkScene: PackedScene = preload("res://Scenes/Environment/Chunk.tscn")

# =============================================================================
# 属性
# =============================================================================

## 活跃的区块视觉节点
## Key: Vector2i (Chunk Coord) -> Value: ChunkVisual
var active_chunks: Dictionary = {}

## 共享 TileSet (从编辑器配置的 GroundLayer 获取，或者代码加载)
var _tile_set: TileSet

## 地形连接查找表
## Key: TerrainSet (int) -> Key: Terrain (int) -> Key: Bitmask (int) -> Value: Dictionary {source, atlas, alt}
var _terrain_lookup: Dictionary = {}

## 线程池任务 ID 映射 (防止重复计算)
var _calculating_tasks: Dictionary = {}


## 区块对象池 (ChunkVisual)
# var _chunk_pool: Array[ChunkVisual] = []

### 导航层引用 (仍然保留全局导航层，因为它通常是连续的)
#@onready var _navigation_layer: TileMapLayer = $NavigationLayer

## WorldManager 引用 (由 WorldManager 注入)
var world_manager = null

# =============================================================================
# 常量
# =============================================================================

# (已移至 Constants.gd)


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	# 1. 加载或获取 TileSet
	if _C.GROUND_TILESET and ResourceLoader.exists(_C.GROUND_TILESET):
		_tile_set = load(_C.GROUND_TILESET)
	
	
	if not _tile_set:
		push_error("GlobalMapController: Failed to load TileSet from %s" % _C.GROUND_TILESET)
		return

	# 2. 构建查找表
	_build_terrain_lookup()
	print("[GlobalMapController] Terrain lookup table built. Size: %s" % _terrain_lookup.size())
	if _terrain_lookup.is_empty():
		push_error("[GlobalMapController] Terrain lookup table is empty! Check TileSet configuration.")
	else:
		## 打印完整地形表供核对
		#print("========== TERRAIN LOOKUP TABLE DUMP ==========")
		#for t_set in _terrain_lookup:
		#	for t_id in _terrain_lookup[t_set]:
		#		print("TerrainSet: %s, TerrainID: %s" % [t_set, t_id])
		#		for mask in _terrain_lookup[t_set][t_id]:
		#			var info = _terrain_lookup[t_set][t_id][mask]
		#			print("  Mask: %s -> Source: %s, Atlas: %s, Alt: %s" % [mask, info.source, info.atlas, info.alt])
		#print("===============================================")
		pass

# =============================================================================
# 公共接口
# =============================================================================

## 渲染区块
## @param coord: 区块坐标
## @param data: ChunkData (包含 padding)
func render_chunk(coord: Vector2i, data) -> void:
	if active_chunks.has(coord):
		return
	
	if _calculating_tasks.has(coord):
		return
		
	# 启动后台任务计算视觉数据
	# 任务包括：计算数据 + 实例化场景 (但不 add_child)
	var task_id = WorkerThreadPool.add_task(
		_calculate_visuals_task.bind(coord, data),
		true, # High priority
		"RenderChunk:%s" % coord
	)
	_calculating_tasks[coord] = task_id


## 清除区块
func clear_chunk(coord: Vector2i) -> void:
	# var st=Time.get_ticks_usec()
	if active_chunks.has(coord):
		var visual = active_chunks[coord]
		active_chunks.erase(coord)
		visual.queue_free()
	# var end=Time.get_ticks_usec()
	# print(end-st)
	# 如果有正在进行的计算任务，无法直接取消，但在回调中会检查 active_chunks


## 修改单点 (运行时)
func set_cell_at(global_pos: Vector2, layer_enum: int, tile_id: int) -> void:
	var tile_coord := _MapUtils.world_to_tile(global_pos)
	var chunk_coord := _MapUtils.tile_to_chunk(tile_coord)
	var local_coord := _MapUtils.tile_to_local(tile_coord)
	
	if active_chunks.has(chunk_coord):
		var visual: ChunkVisual = active_chunks[chunk_coord]
		
		var source_id = -1
		var atlas_coord = Vector2i(-1, -1)
		
		if layer_enum == _C.Layer.GROUND:
			# 优化：仅更新局部区域 (3x3)，而不是重绘整个 Chunk
			if world_manager:
				_update_local_terrain_visuals(tile_coord)
			return
		
		# 如果是添加物体，需要查找资源
		if tile_id != -1:
			# 物体直接查表
			var res = _C.OBJECT_RESOURCE_TABLE.get(tile_id)
			if res:
				source_id = res.source_id
				var atlas_list = res.atlas
				if atlas_list is Array and atlas_list.size() > 0:
					var idx = _deterministic_index(atlas_list.size(), tile_coord.x, tile_coord.y, tile_id)
					atlas_coord = atlas_list[idx]
				elif atlas_list is Vector2i:
					atlas_coord = atlas_list
		
		visual.set_block(local_coord, layer_enum, source_id, atlas_coord)

## 局部更新地形视觉 (3x3 区域)
## @param center_tile: 修改的中心世界瓦片坐标
func _update_local_terrain_visuals(center_tile: Vector2i) -> void:
	if not world_manager: return
	
	# 遍历 3x3 区域 (包含中心点和8邻居)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var target_tile = center_tile + Vector2i(dx, dy)
			
			# 获取目标点的区块和局部坐标
			var target_chunk = _MapUtils.tile_to_chunk(target_tile)
			var target_local = _MapUtils.tile_to_local(target_tile)
			
			# 如果该区块未渲染，跳过
			if not active_chunks.has(target_chunk):
				continue
				
			var visual = active_chunks[target_chunk]
			
			# 1. 获取目标点的地形 ID
			var chunk_data = world_manager.get_chunk_data(target_chunk)
			if not chunk_data: continue
			
			var t_id = chunk_data.get_terrain(target_local.x, target_local.y)
			if t_id == -1:
				# 如果是空地形，清除
				visual.set_block(target_local, _C.Layer.GROUND, -1, Vector2i(-1, -1))
				continue
				
			# 2. 重新计算 Bitmask
			# 注意：_get_terrain_bitmask_at 需要访问 chunk_data
			# 但因为 WorldManager 已经处理了 Padding 同步，所以可以直接从当前 ChunkData 读取邻居
			# 除非目标点在 Chunk 边缘，此时需要访问跨 Chunk 的数据。
			# 现在的 _get_terrain_bitmask_at 是基于单个 ChunkData 的，且假设 Padding 已同步。
			var bitmask = _get_terrain_bitmask_at(chunk_data, target_local.x, target_local.y, t_id)
			
			# 3. 查表获取图块信息
			var tile_info = _lookup_terrain_tile(_C.TERRAIN_SET_GROUND, t_id, bitmask)
			
			if tile_info:
				visual.set_block(
					target_local, 
					_C.Layer.GROUND, 
					tile_info.source, 
					tile_info.atlas, 
					tile_info.alt
				)
			else:
				# 找不到匹配图块，可能回退到默认
				pass

# =============================================================================
# 查找表构建 (Initialization)
# =============================================================================

func _build_terrain_lookup() -> void:
	if not _tile_set: return
	
	for i in _tile_set.get_source_count():
		var source_id = _tile_set.get_source_id(i)
		var source = _tile_set.get_source(source_id)
		if not source is TileSetAtlasSource: continue
		
		for j in source.get_tiles_count():
			var atlas_coords = source.get_tile_id(j)
			for n in source.get_alternative_tiles_count(atlas_coords):
				var alt_id = source.get_alternative_tile_id(atlas_coords, n)
				var tile_data = source.get_tile_data(atlas_coords, alt_id)
				
				# 检查是否有地形数据
				if tile_data.terrain_set == -1 or tile_data.terrain == -1:
					continue
					
				# 计算该 Tile 对应的 Bitmask ID
				var bitmask = _calculate_tile_bitmask(tile_data)
				if bitmask == -1: continue
				
				# 存入查找表
				var t_set = tile_data.terrain_set
				var t_id = tile_data.terrain
				
				if not _terrain_lookup.has(t_set): _terrain_lookup[t_set] = {}
				if not _terrain_lookup[t_set].has(t_id): _terrain_lookup[t_set][t_id] = {}
				
				_terrain_lookup[t_set][t_id][bitmask] = {
					"source": source_id,
					"atlas": atlas_coords,
					"alt": alt_id
				}
	
	# print("[GlobalMapController] Terrain lookup built. Dump for set 0, terrain 0:")
	# if _terrain_lookup.has(0) and _terrain_lookup[0].has(0):
	# 	print(_terrain_lookup[0][0])

func _calculate_tile_bitmask(tile_data: TileData) -> int:
	var mode = _tile_set.get_terrain_set_mode(tile_data.terrain_set)
	var t_id = tile_data.terrain
	
	# 检查各方向是否连接
	# 注意：Godot 的 bit 定义与 auto_tile.gd 中的顺序可能一致，我们需要标准化
	# 这里的顺序参考 auto_tile.gd: Left, BL, B, BR, R, TR, T, TL
	
	var left = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_LEFT_SIDE) == t_id
	var right = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_RIGHT_SIDE) == t_id
	var top = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE) == t_id
	var bottom = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE) == t_id
	
	var top_left = false
	var top_right = false
	var bottom_left = false
	var bottom_right = false
	
	if mode == TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES:
		top_left = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER) == t_id
		top_right = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER) == t_id
		bottom_left = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER) == t_id
		bottom_right = tile_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER) == t_id
	
	# 标准化：角连接必须依赖边连接
	if top_left: top_left = top and left
	if top_right: top_right = top and right
	if bottom_left: bottom_left = bottom and left
	if bottom_right: bottom_right = bottom and right
	
	# 构建整数 ID
	var id = 0
	if left: id |= _C.BIT_LEFT
	if bottom_left: id |= _C.BIT_BOTTOM_LEFT
	if bottom: id |= _C.BIT_BOTTOM
	if bottom_right: id |= _C.BIT_BOTTOM_RIGHT
	if right: id |= _C.BIT_RIGHT
	if top_right: id |= _C.BIT_TOP_RIGHT
	if top: id |= _C.BIT_TOP
	if top_left: id |= _C.BIT_TOP_LEFT
	return id

# =============================================================================
# 线程任务
# =============================================================================

func _calculate_visuals_task(coord: Vector2i, data: ChunkData) -> void:
	#OS.delay_msec(1000)
	# print("[GlobalMapController] Starting visual calculation for chunk %s" % coord)
	
	if data == null:
		_queue_visual_update(coord, {})
		return
		
	# 检查数据完整性 (防止旧存档或损坏数据导致数组越界崩溃)
	# 崩溃会导致任务标记泄露，从而永久阻塞该区块渲染
	var expected_size = _C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE
	if data.base_layer.size() != expected_size:
		push_error("[GlobalMapController] Chunk data size mismatch for %s. Expected %d, got %d. Discarding." % [coord, expected_size, data.base_layer.size()])
		_queue_visual_update(coord, {})
		return
		
	var result = {
		"coord": coord,
		"terrain": {
			# Key: layer_index (0=Base, 1-4=ExH) -> Value: {cells, sources, coords, alts}
		},
		"objects": {}
	}
	
	# 1. 计算地形 (遍历 5 层)
	for layer_idx in range(5):
		# 获取该层的地形配置 (TerrainSet)
		var layer_config = _C.TERRAIN_LAYER_CONFIG.get(layer_idx)
		if not layer_config:
			continue
			
		var terrain_set_id = layer_config.get("terrain_set", 0)
		
		var layer_data = {
			"cells": [] as Array[Vector2i],
			"sources": [] as Array[int],
			"coords": [] as Array[Vector2i],
			"alts": [] as Array[int]
		}
		
		for y in range(_C.CHUNK_SIZE):
			for x in range(_C.CHUNK_SIZE):
				var t_id = data.get_terrain(x, y, layer_idx)
				if t_id == -1: continue
				
				# 获取周围信息 (从 padding 读取)
				# 传入 layer_idx 以获取正确层级的邻居
				var bitmask = _get_terrain_bitmask_at(data, x, y, t_id, layer_idx)
				
				# 查表 (使用配置的 TerrainSet ID)
				var tile_info = _lookup_terrain_tile(terrain_set_id, t_id, bitmask)
				if tile_info:
					layer_data.cells.append(Vector2i(x, y))
					layer_data.sources.append(tile_info.source)
					layer_data.coords.append(tile_info.atlas)
					layer_data.alts.append(tile_info.alt)
		
		if layer_data.cells.size() > 0:
			result.terrain[layer_idx] = layer_data
	
	# 2. 计算物体
	for packed_key in data.object_map:
		var obj_id = data.object_map[packed_key]
		var unpacked = _MapUtils.unpack_coord(packed_key) # {x, y, z}
		
		var res = _C.OBJECT_RESOURCE_TABLE.get(obj_id)
		if res and res.source_id != -1:
			var layer_id = unpacked.z
			if not result.objects.has(layer_id):
				result.objects[layer_id] = []
			
			var atlas_list = res.atlas
			var chosen_coord: Vector2i = Vector2i(-1, -1)
			if atlas_list is Array and atlas_list.size() > 0:
				var idx = _deterministic_index(atlas_list.size(), unpacked.x, unpacked.y, obj_id)
				chosen_coord = atlas_list[idx]
			elif atlas_list is Vector2i:
				chosen_coord = atlas_list
			
			result.objects[layer_id].append({
				"cell": Vector2i(unpacked.x, unpacked.y),
				"source": res.source_id,
				"coord": chosen_coord
			})
	
	# 3. 计算导航层
	result.navigation = {
		"cells": [] as Array[Vector2i],
		"source": _C.NAV_SOURCE_ID,
		"coords": [] as Array[Vector2i]
	}
	
	# 简单逻辑：有地面且无障碍物 -> 可通行；有障碍物 -> 不可通行
	for y in range(_C.CHUNK_SIZE):
		for x in range(_C.CHUNK_SIZE):
			# 只要基础层有地形，就可能有导航点
			var t_id = data.get_terrain(x, y, 0)
			
			# 如果没有地形（虚空），不设置导航点
			if t_id == -1: continue
			
			# 检查是否有障碍物
			var is_blocked = false
			# 检查该位置是否有 OBSTACLE 层的物体
			var packed_key = _MapUtils.pack_coord(x, y, _C.Layer.OBSTACLE)
			if data.object_map.has(packed_key):
				is_blocked = true
				
			# 检查高度层级 (高度0为水域，不可通行)
			# 如果是 BaseLayer 的 Sand/Dirt/Grass，通常可通行
			# 如果是 ExH 层级作为山脉，可能不可通行? 暂时保留原有逻辑，即 ID 0 (水) 不可通行
			# 这里的 t_id 是 BaseLayer 的 ID。
			# 假设所有 Base Terrain 都可通行，除非被物体阻挡或类型为 Water。
			
			if t_id == _C.BASE_TERRAINS.WATER:
				is_blocked = true
			
			var nav_coord = _C.NAV_TILE_WALKABLE
			if is_blocked:
				nav_coord = _C.NAV_TILE_UNWALKABLE
				
			result.navigation.cells.append(Vector2i(x, y))
			result.navigation.coords.append(nav_coord)
	
	# 4. 实例化 ChunkVisual (在后台线程进行)
	# 注意：实例化节点通常是线程安全的，只要不将其添加到 SceneTree
	var visual_node = ChunkScene.instantiate()
	if not visual_node is ChunkVisual:
		push_error("GlobalMapController: Instantiated scene is not a ChunkVisual!")
		visual_node.queue_free()
		# 即使失败也要发送空结果，以清除 _calculating_tasks 标记
		_queue_visual_update(coord, {})
		return
		
	var visual: ChunkVisual = visual_node as ChunkVisual
	visual.position = Vector2(coord.x * _C.CHUNK_SIZE_PIXELS, coord.y * _C.CHUNK_SIZE_PIXELS)
	
	# 将实例化好的节点传递给主线程
	result.visual_node = visual
	
	# 直接推入渲染队列 (线程安全)
	_queue_visual_update(coord, result)


func _get_terrain_bitmask_at(data: ChunkData, x: int, y: int, center_id: int, layer_index: int = 0) -> int:
	# 检查 8 邻居
	var left = data.get_terrain(x - 1, y, layer_index) == center_id
	var right = data.get_terrain(x + 1, y, layer_index) == center_id
	var top = data.get_terrain(x, y - 1, layer_index) == center_id
	var bottom = data.get_terrain(x, y + 1, layer_index) == center_id
	
	var top_left = data.get_terrain(x - 1, y - 1, layer_index) == center_id
	var top_right = data.get_terrain(x + 1, y - 1, layer_index) == center_id
	var bottom_left = data.get_terrain(x - 1, y + 1, layer_index) == center_id
	var bottom_right = data.get_terrain(x + 1, y + 1, layer_index) == center_id
	
	# 标准化
	if top_left: top_left = top and left
	if top_right: top_right = top and right
	if bottom_left: bottom_left = bottom and left
	if bottom_right: bottom_right = bottom and right
	
	var id = 0
	if left: id |= _C.BIT_LEFT
	if bottom_left: id |= _C.BIT_BOTTOM_LEFT
	if bottom: id |= _C.BIT_BOTTOM
	if bottom_right: id |= _C.BIT_BOTTOM_RIGHT
	if right: id |= _C.BIT_RIGHT
	if top_right: id |= _C.BIT_TOP_RIGHT
	if top: id |= _C.BIT_TOP
	if top_left: id |= _C.BIT_TOP_LEFT
	
	return id


func _lookup_terrain_tile(t_set: int, t_id: int, bitmask: int):
	if _terrain_lookup.has(t_set) and _terrain_lookup[t_set].has(t_id):
		var tiles = _terrain_lookup[t_set][t_id]
		if tiles.has(bitmask):
			return tiles[bitmask]
		# 如果找不到精确匹配，可以尝试 fallback (例如只有中心块)
		# Bitmask 0 (无连接) 通常代表单块
		if tiles.has(0): return tiles[0]
	return null

func _deterministic_index(count: int, x: int, y: int, id: int) -> int:
	var h = int(((x * 73856093) ^ (y * 19349663) ^ (id * 83492791)) & 0x7fffffff)
	return h % max(1, count)


# =============================================================================
# 分帧渲染队列 (Frame-Budgeted Rendering Queue)
# =============================================================================

## 待处理的视觉更新队列
## 元素: { "coord": Vector2i, "data": Dictionary }
var _render_queue: Array[Dictionary] = []
var _queue_mutex := Mutex.new()

func _queue_visual_update(coord: Vector2i, data: Dictionary) -> void:
	_queue_mutex.lock()
	_render_queue.append({ "coord": coord, "data": data })
	_queue_mutex.unlock()
	# 确保每帧处理开启
	call_deferred("set_process", true)

func _process(_delta: float) -> void:
	var start_time = Time.get_ticks_usec()
	
	while true:
		# 1. 安全获取任务
		_queue_mutex.lock()
		if _render_queue.is_empty():
			_queue_mutex.unlock()
			set_process(false)
			break
			
		var task = _render_queue.pop_front()
		_queue_mutex.unlock()
		
		var coord: Vector2i = task["coord"]
		var data: Dictionary = task["data"]
		
		# 清除计算任务标记 (原 _on_visuals_calculated 逻辑)
		_calculating_tasks.erase(coord)
		
		# 2. 检查是否还需要渲染
		# 如果在排队期间区块已经通过 clear_chunk 移除了 active_chunks，理论上应该跳过？
		# 但 clear_chunk 逻辑是：如果 active_chunks 有，就删除。
		# 这里的场景是：后台任务完成了，准备创建。
		# 我们需要再次检查这个区块是否仍然应该被渲染（例如是否还在 active 半径内）
		# 不过简单起见，且遵循 WorldManager 的指令，只要任务完成了就尝试渲染。
		# WorldManager 稍后如果判定不需要，会调用 clear_chunk。
		
		# 检查数据有效性（防止任务失败导致的问题）
		if not data.has("terrain"):
			# print("[GlobalMapController] Task failed or returned invalid data for chunk %s" % coord)
			continue
		
		if not world_manager:
			print("[GlobalMapController] ERROR: world_manager is null! Discarding chunk %s" % coord)
			if data.has("visual_node") and is_instance_valid(data.visual_node):
				data.visual_node.queue_free()
			continue
		
		#print("[GlobalMapController] Processing chunk %s from queue." % coord)
		
		# 3. 如果 active_chunks 里已经有了（极罕见情况），先清理旧的
		if active_chunks.has(coord):
			var old_visual = active_chunks[coord]
			active_chunks.erase(coord)
			old_visual.queue_free()
		
		# 4. 获取预实例化的节点 (耗时操作1 已转移至线程)
		var visual: ChunkVisual
		if data.has("visual_node") and is_instance_valid(data.visual_node):
			visual = data.visual_node
		else:
			# 后备方案：如果数据里没有，或者失效了
			var visual_node = ChunkScene.instantiate()
			if not visual_node is ChunkVisual:
				visual_node.queue_free()
				continue
			visual = visual_node as ChunkVisual
			visual.position = Vector2(coord.x * _C.CHUNK_SIZE_PIXELS, coord.y * _C.CHUNK_SIZE_PIXELS)
		
		# 5. 挂载 (耗时操作2)
		add_child(visual)
		active_chunks[coord] = visual
		
		# 6. 应用数据 (耗时操作3)
		visual.apply_visual_data(data)
		
		# 检查时间预算
		var current_time = Time.get_ticks_usec()
		#print("frame_time",current_time - start_time)
		if (current_time - start_time) > _C.MAX_RENDER_TIME_PER_FRAME_US:
			# print("[GlobalMapController] Render budget exceeded (%sus). Yielding..." % (current_time - start_time))
			break
