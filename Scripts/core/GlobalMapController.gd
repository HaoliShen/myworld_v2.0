## GlobalMapController.gd
## 全局地图控制器 - 负责管理和渲染所有区块节点
## 路径: res://Scripts/Core/GlobalMapController.gd
## 挂载节点: World/Environment
##
## 职责:
## 1. 维护活跃的 ChunkVisual 节点集合
## 2. 负责 TileSet 的地形连接查找表构建
## 3. 在后台线程计算区块的瓦片数据 (地形连接 + 物体)
## 4. 实例化和更新 ChunkVisual
class_name GlobalMapController
extends Node2D

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")
const _ChunkVisual = preload("res://Scripts/components/ChunkVisual.gd")

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
		# 打印完整地形表供核对
		print("========== TERRAIN LOOKUP TABLE DUMP ==========")
		for t_set in _terrain_lookup:
			for t_id in _terrain_lookup[t_set]:
				print("TerrainSet: %s, TerrainID: %s" % [t_set, t_id])
				for mask in _terrain_lookup[t_set][t_id]:
					var info = _terrain_lookup[t_set][t_id][mask]
					print("  Mask: %s -> Source: %s, Atlas: %s, Alt: %s" % [mask, info.source, info.atlas, info.alt])
		print("===============================================")


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
	# 注意：传递 data.terrain_map (PackedInt32Array) 是值传递(COW)，但在线程中读取是安全的
	# data 对象本身是 RefCounted，传递引用也是安全的，只要主线程不修改它
	var task_id = WorkerThreadPool.add_task(
		_calculate_visuals_task.bind(coord, data),
		true, # High priority
		"RenderChunk:%s" % coord
	)
	_calculating_tasks[coord] = task_id


## 清除区块
func clear_chunk(coord: Vector2i) -> void:
	if active_chunks.has(coord):
		var visual = active_chunks[coord]
		active_chunks.erase(coord)
		visual.queue_free()
	
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
		
		# 如果是添加物体/地形，需要查找资源
		if tile_id != -1:
			if layer_enum == _C.Layer.GROUND:
				# 运行时修改地形比较复杂，需要重新计算连接
				# 简单起见，这里只设置中心块，不更新连接 (或者请求重新完整渲染该 Chunk)
				# 为了正确性，最好是重新渲染整个 Chunk (及其邻居)
				# 暂时实现为：重新请求渲染该 Chunk
				if world_manager:
					var chunk_data = world_manager.get_chunk_data(chunk_coord)
					if chunk_data:
						clear_chunk(chunk_coord)
						render_chunk(chunk_coord, chunk_data)
						# TODO: 邻居也需要更新边缘
				return
			else:
				# 物体直接查表
				var res = _C.OBJECT_RESOURCE_TABLE.get(tile_id)
				if res:
					source_id = res.source_id
					atlas_coord = res.atlas
		
		visual.set_block(local_coord, layer_enum, source_id, atlas_coord)


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
	# print("[GlobalMapController] Starting visual calculation for chunk %s" % coord)
	var result = {
		"coord": coord,
		"ground": {
			"cells": [] as Array[Vector2i],
			"sources": [] as Array[int],
			"coords": [] as Array[Vector2i],
			"alts": [] as Array[int]
		},
		"objects": {}
	}
	
	# 1. 计算地形 (0..31)
	for y in range(_C.CHUNK_SIZE):
		for x in range(_C.CHUNK_SIZE):
			var t_id = data.get_terrain(x, y)
			if t_id == -1: continue
			
			# 获取周围信息 (从 padding 读取)
			var bitmask = _get_terrain_bitmask_at(data, x, y, t_id)
			
			# 查表
			var tile_info = _lookup_terrain_tile(_C.TERRAIN_SET_GROUND, t_id, bitmask)
			if tile_info:
				# 检查坐标是否有效 (简单的范围检查，假设 atlas 不会超过 100x100)
				if tile_info.atlas.x > 100 or tile_info.atlas.y > 100:
					print("[GlobalMapController] Suspicious atlas coord found: %s for t_id=%s, mask=%s" % [tile_info.atlas, t_id, bitmask])
				
				result.ground.cells.append(Vector2i(x, y))
				result.ground.sources.append(tile_info.source)
				result.ground.coords.append(tile_info.atlas)
				result.ground.alts.append(tile_info.alt)
			else:
				# print("[GlobalMapController] No tile found for t_set=%s, t_id=%s, bitmask=%s at %s" % [_C.TERRAIN_SET_GROUND, t_id, bitmask, Vector2i(x, y)])
				pass
	
	# 2. 计算物体
	for packed_key in data.object_map:
		var obj_id = data.object_map[packed_key]
		var unpacked = _MapUtils.unpack_coord(packed_key) # {x, y, z}
		
		var res = _C.OBJECT_RESOURCE_TABLE.get(obj_id)
		if res and res.source_id != -1:
			var layer_id = unpacked.z
			if not result.objects.has(layer_id):
				result.objects[layer_id] = []
			
			result.objects[layer_id].append({
				"cell": Vector2i(unpacked.x, unpacked.y),
				"source": res.source_id,
				"coord": res.atlas
			})
	
	# 回调主线程
	# print("[GlobalMapController] Visuals calculated for %s. Ground cells: %s" % [coord, result.ground.cells.size()])
	call_deferred("_on_visuals_calculated", result)


func _get_terrain_bitmask_at(data: ChunkData, x: int, y: int, center_id: int) -> int:
	# 检查 8 邻居
	var left = data.get_terrain(x - 1, y) == center_id
	var right = data.get_terrain(x + 1, y) == center_id
	var top = data.get_terrain(x, y - 1) == center_id
	var bottom = data.get_terrain(x, y + 1) == center_id
	
	var top_left = data.get_terrain(x - 1, y - 1) == center_id
	var top_right = data.get_terrain(x + 1, y - 1) == center_id
	var bottom_left = data.get_terrain(x - 1, y + 1) == center_id
	var bottom_right = data.get_terrain(x + 1, y + 1) == center_id
	
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


# =============================================================================
# 回调
# =============================================================================

func _on_visuals_calculated(result: Dictionary) -> void:
	var coord = result.coord
	_calculating_tasks.erase(coord)
	
	# 如果在计算期间区块被清除了（例如玩家快速移动），则丢弃结果
	# 但这里我们没有 active_chunks 标记"pending"，所以主要检查是否需要
	# 简单的策略：直接创建。WorldManager 会负责管理它的生命周期（如果不需要了会调 clear_chunk）
	# 不过如果 active_chunks 已经有了（理论上不应该），则覆盖
	
	if active_chunks.has(coord):
		active_chunks[coord].queue_free()
	
	# 实例化 ChunkVisual
	var visual = _ChunkVisual.new(_tile_set)
	visual.position = Vector2(coord.x * _C.CHUNK_SIZE_PIXELS, coord.y * _C.CHUNK_SIZE_PIXELS)
	add_child(visual)
	
	# 应用数据
	visual.apply_visual_data(result)
	
	active_chunks[coord] = visual
	print("[GlobalMapController] Chunk %s rendered. Visual node: %s" % [coord, visual])
