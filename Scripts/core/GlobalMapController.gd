## GlobalMapController.gd
## 全局地图控制器 - 全局渲染画布 (Global Rendering Canvas)
## 路径: res://Scripts/Components/GlobalMapController.gd
## 挂载节点: World/Environment
## 继承: Node2D
## 依赖: Better Terrain (插件)
##
## 职责:
## 它是连接数据 (ChunkData) 与视觉 (TileMapLayer) 的唯一桥梁。
## 它不存储任何游戏逻辑状态，只负责调用 Better Terrain 的 API 进行高效的"画"和"擦"。
class_name GlobalMapController
extends Node2D

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")
const _ShadowChunkRenderer = preload("res://Scripts/components/ShadowChunkRenderer.gd")

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

## 基础地形层 (Z-Index: -10) - 用于绘制地面、水体和悬崖
@onready var _ground_layer: TileMapLayer = $GroundLayer

## 装饰层 (Y-Sort Enabled) - 用于绘制草丛、花朵、地毯
@onready var _decoration_layer: TileMapLayer = $DecorationLayer

## 障碍层 (Y-Sort Enabled) - 用于绘制树木、墙壁、建筑
@onready var _obstacle_layer: TileMapLayer = $ObstacleLayer

## 导航层 (不可见) - 用于寻路系统
@onready var _navigation_layer: TileMapLayer = $NavigationLayer

# =============================================================================
# 导航常量 (Navigation Constants)
# =============================================================================

## 导航 TileSet 中的 Source ID
const NAV_SOURCE_ID: int = 3

## 可通行 Tile 的 Atlas 坐标
const NAV_TILE_PASSABLE: Vector2i = Vector2i(56, 25)

## 不可通行 Tile 的 Atlas 坐标 (或使用 -1 表示无 tile)
const NAV_TILE_BLOCKED: Vector2i = Vector2i(56, 26)

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## TileSet 引用
var _tileset: TileSet

## 导航 TileSet 引用
var _nav_tileset: TileSet

## 是否已初始化
var _is_initialized: bool = false

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	print("[GlobalMapController] _ready called - DEBUG CHECK")
	_initialize()


func _initialize() -> void:
	if _ground_layer and _ground_layer.tile_set:
		_tileset = _ground_layer.tile_set
		_is_initialized = true

# =============================================================================
# 批量操作 (Batch Operations) - 用于流式加载
# =============================================================================

## 渲染指定区块的数据到全局地图
## 职责:
## 1. 计算该区块在全局 TileMap 中的坐标偏移
## 2. 读取 ChunkData 中的地形、高度和物体数据
## 3. 将逻辑 ID (ChunkData) 映射为视觉 ID (TileSet)
## 4. 调用 BetterTerrain 的批量设置接口将数据填充到对应的 TileMapLayer
## 5. 触发 BetterTerrain 的地形连接更新以处理边缘自动拼接
## @param coord: 区块坐标
## @param data: 包含该区块所有信息的纯数据对象
func render_chunk(coord: Vector2i, data) -> void:
	var t_start = Time.get_ticks_usec()
	print("[DEBUG] render_chunk START for chunk %s at %d us" % [coord, t_start])
	
	if not _is_initialized:
		push_error("GlobalMapController: Not initialized")
		return

	# 计算区块在全局 TileMap 中的基础坐标
	var base_tile := Vector2i(
		coord.x * _C.CHUNK_SIZE,
		coord.y * _C.CHUNK_SIZE
	)

	# 收集需要更新的瓦片坐标 (用于 BetterTerrain 批量更新)
	var ground_cells: Array[Vector2i] = []

	# 1. 渲染地面层 (Layer 0) - 使用 Autotile 批量设置
	var terrain_cells = {} # Key: terrain_id -> Value: Array[Vector2i]
	
	for local_y in range(_C.CHUNK_SIZE):
		for local_x in range(_C.CHUNK_SIZE):
			var tile_coord := base_tile + Vector2i(local_x, local_y)
			var terrain_id = data.get_terrain(local_x, local_y)
			# var elevation = data.get_elevation(local_x, local_y) # 地形 ID 已包含高度信息

			# 收集相同地形的瓦片
			if not terrain_cells.has(terrain_id):
				terrain_cells[terrain_id] = []
			terrain_cells[terrain_id].append(tile_coord)
			
			ground_cells.append(tile_coord)
	
	var t_ground_prep = Time.get_ticks_usec()
	print("[DEBUG] render_chunk - Ground prep completed: %d us, terrain types: %d, total cells: %d" % [
		t_ground_prep - t_start, terrain_cells.size(), ground_cells.size()
	])

	# 批量应用地形连接
	# 使用 BetterTerrain 插件 API
	var time=[]
	var terrain_id_list = []
	
	for t_id in terrain_cells:
		if not terrain_cells[t_id].is_empty():
			var t_before = Time.get_ticks_usec()
			print("[DEBUG] render_chunk - Calling BetterTerrain.set_cells for terrain_id %d with %d cells" % [t_id, terrain_cells[t_id].size()])
			# _ground_layer.set_cells_terrain_connect(terrain_cells[t_id], _C.GROUND_TERRAIN_SET, t_id, false)
			# 替换为 BetterTerrain.set_cells
			_ShadowChunkRenderer.shared_mutex.lock()
			BetterTerrain.set_cells(_ground_layer, terrain_cells[t_id], t_id)
			_ShadowChunkRenderer.shared_mutex.unlock()
			var t_after = Time.get_ticks_usec()
			time.append(t_after)
			terrain_id_list.append(t_id)
			print("[DEBUG] render_chunk - BetterTerrain.set_cells for terrain_id %d took %d us" % [t_id, t_after - t_before])

	var t_bt_done = Time.get_ticks_usec()
	print("[DEBUG] render_chunk - All BetterTerrain.set_cells completed: %d us" % [t_bt_done - t_ground_prep])

	# 2. 渲染物体层 (Layer 1 & 2)
	var object_count = data.object_map.size()
	print("[DEBUG] render_chunk - Starting object rendering, count: %d" % object_count)
	for packed_key in data.object_map:
		var unpacked := _MapUtils.unpack_coord(packed_key)
		var local_x := unpacked.x
		var local_y := unpacked.y
		var layer := unpacked.z
		var object_id: int = data.object_map[packed_key]

		var tile_coord := base_tile + Vector2i(local_x, local_y)
		_set_object_cell(tile_coord, layer, object_id)

	var t_obj = Time.get_ticks_usec()
	print("[DEBUG] render_chunk - Object rendering completed: %d us" % [t_obj - t_bt_done])

	# 3. 触发 BetterTerrain 更新地形连接
	print("[DEBUG] render_chunk - Calling _update_terrain_connections with %d cells" % ground_cells.size())
	_update_terrain_connections(ground_cells)
	
	var t_conn = Time.get_ticks_usec()
	print("[DEBUG] render_chunk - Terrain connections update completed: %d us" % [t_conn - t_obj])
	
	# 4. 更新导航层
	print("[DEBUG] render_chunk - Starting navigation update")
	_update_chunk_navigation(coord, data)
	
	var t_nav = Time.get_ticks_usec()
	print("[DEBUG] render_chunk - Navigation update completed: %d us" % [t_nav - t_conn])

	var total_time = t_nav - t_start
	print("[Profile] render_chunk %s Total: %d us (%.2f ms) | Prep: %d | BetterTerrain: %d | Objects: %d | Connections: %d | Nav: %d" % [
		coord, total_time, total_time / 1000.0,
		t_ground_prep - t_start,
		t_bt_done - t_ground_prep,
		t_obj - t_bt_done,
		t_conn - t_obj,
		t_nav - t_conn
	])
	print("[DEBUG] render_chunk END for chunk %s\n" % coord)


## [新增] 从影子图层快速复制数据到主图层
## 职责:
## 1. 从预计算好的影子TileMapLayer批量复制瓦片数据
## 2. 渲染物体层（装饰和障碍）
## 3. 更新导航层
## @param shadow_data: 影子渲染器返回的数据字典
func apply_shadow_chunk(shadow_data: Dictionary) -> void:
	var t_start = Time.get_ticks_usec()
	var coord: Vector2i = shadow_data["coord"]
	var shadow_ground: TileMapLayer = shadow_data["shadow_ground"]
	var base_tile: Vector2i = shadow_data["base_tile"]
	
	print("[DEBUG] apply_shadow_chunk START for chunk %s" % coord)
	
	var used_cells := shadow_ground.get_used_cells()
	print("[DEBUG] apply_shadow_chunk - Copying %d cells from shadow layer" % used_cells.size())
	
	var t_copy_start = Time.get_ticks_usec()
	for cell in used_cells:
		var source_id := shadow_ground.get_cell_source_id(cell)
		var atlas_coords := shadow_ground.get_cell_atlas_coords(cell)
		var alternative := shadow_ground.get_cell_alternative_tile(cell)
		_ground_layer.set_cell(cell, source_id, atlas_coords, alternative)
	
	var t_copy_end = Time.get_ticks_usec()
	print("[DEBUG] apply_shadow_chunk - Cell copy completed in %d us (%.2f ms)" % [t_copy_end - t_copy_start, (t_copy_end - t_copy_start) / 1000.0])
	
	var object_count = shadow_data["object_data"].size()
	print("[DEBUG] apply_shadow_chunk - Rendering %d objects" % object_count)
	for packed_key in shadow_data["object_data"]:
		var unpacked := _MapUtils.unpack_coord(packed_key)
		var local_x := unpacked.x
		var local_y := unpacked.y
		var layer := unpacked.z
		var object_id: int = shadow_data["object_data"][packed_key]
		
		var tile_coord := base_tile + Vector2i(local_x, local_y)
		_set_object_cell(tile_coord, layer, object_id)
	
	var t_obj_end = Time.get_ticks_usec()
	print("[DEBUG] apply_shadow_chunk - Object rendering completed in %d us" % [t_obj_end - t_copy_end])
	
	var chunk_data = shadow_data.get("chunk_data")
	if chunk_data:
		_update_chunk_navigation(coord, chunk_data)
	
	var t_nav_end = Time.get_ticks_usec()
	
	var total_time = t_nav_end - t_start
	print("[Profile] apply_shadow_chunk %s Total: %d us (%.2f ms) | Copy: %d | Objects: %d | Nav: %d" % [
		coord, total_time, total_time / 1000.0,
		t_copy_end - t_copy_start,
		t_obj_end - t_copy_end,
		t_nav_end - t_obj_end
	])
	print("[DEBUG] apply_shadow_chunk END for chunk %s\n" % coord)


## [新增] 批量更新区块边界的地形连接
## 职责:
## 只更新指定区块的边界瓦片，而不是整个区块，大幅减少计算量
## @param chunk_coords: 需要更新边界的区块坐标数组
func update_chunk_boundaries(chunk_coords: Array[Vector2i]) -> void:
	if chunk_coords.is_empty():
		return
	
	var t_start = Time.get_ticks_usec()
	var boundary_cells: Array[Vector2i] = []
	
	print("[DEBUG] update_chunk_boundaries - Processing %d chunks" % chunk_coords.size())
	
	for coord in chunk_coords:
		var base_tile := Vector2i(
			coord.x * _C.CHUNK_SIZE,
			coord.y * _C.CHUNK_SIZE
		)
		
		for x in range(_C.CHUNK_SIZE):
			boundary_cells.append(base_tile + Vector2i(x, 0))
			boundary_cells.append(base_tile + Vector2i(x, _C.CHUNK_SIZE - 1))
		
		for y in range(1, _C.CHUNK_SIZE - 1):
			boundary_cells.append(base_tile + Vector2i(0, y))
			boundary_cells.append(base_tile + Vector2i(_C.CHUNK_SIZE - 1, y))
	
	var t_prep = Time.get_ticks_usec()
	print("[DEBUG] update_chunk_boundaries - Collected %d boundary cells in %d us" % [boundary_cells.size(), t_prep - t_start])
	
	if not boundary_cells.is_empty():
		_ShadowChunkRenderer.shared_mutex.lock()
		BetterTerrain.update_terrain_cells(_ground_layer, boundary_cells)
		_ShadowChunkRenderer.shared_mutex.unlock()
	
	var t_end = Time.get_ticks_usec()
	print("[Profile] update_chunk_boundaries - %d chunks, %d cells in %d us (%.2f ms)" % [
		chunk_coords.size(), boundary_cells.size(), t_end - t_start, (t_end - t_start) / 1000.0
	])


## 清除指定区块的渲染内容
## 职责:
## 1. 计算该区块在全局 TileMap 中的矩形范围
## 2. 将该范围内的三层 TileMapLayer 数据全部置空
## 3. 触发 BetterTerrain 更新，确保移除后邻接区块的边缘纹理正确闭合
## @param coord: 区块坐标
func clear_chunk(coord: Vector2i) -> void:
	var t_start = Time.get_ticks_usec()
	if not _is_initialized:
		return

	var base_tile := Vector2i(
		coord.x * _C.CHUNK_SIZE,
		coord.y * _C.CHUNK_SIZE
	)

	var cleared_cells: Array[Vector2i] = []

	# 清除所有层的瓦片
	# 优化：不要逐个 erase，尝试批量操作或者只收集坐标最后一起更新
	# 目前 Godot 没有 erase_cells，只能循环
	for local_y in range(_C.CHUNK_SIZE):
		for local_x in range(_C.CHUNK_SIZE):
			var tile_coord := base_tile + Vector2i(local_x, local_y)

			if _ground_layer:
				_ground_layer.erase_cell(tile_coord)
			if _decoration_layer:
				_decoration_layer.erase_cell(tile_coord)
			if _obstacle_layer:
				_obstacle_layer.erase_cell(tile_coord)
			if _navigation_layer:
				_navigation_layer.erase_cell(tile_coord)

			cleared_cells.append(tile_coord)
	
	var t_erase = Time.get_ticks_usec()
	# 更新邻接区块的边缘连接
	#_update_terrain_connections(cleared_cells)
	var t_conn = Time.get_ticks_usec()
	
	print("[DEBUG] clear_chunk %s Total: %d us | Erase: %d | Connect: %d" % [coord, t_conn - t_start, t_erase - t_start, t_conn - t_erase])

# =============================================================================
# 单点操作 (Single Operations) - 用于玩家交互
# =============================================================================

## 单点更新视觉，用于玩家实时交互 (建造/破坏)
## 职责:
## 1. 将世界像素坐标转换为 TileMap 网格坐标
## 2. 根据 layer_enum 选择对应的 TileMapLayer
## 3. 设置单元格并更新周边连接
## @param global_pos: 发生改变的世界坐标
## @param layer_enum: 目标层级 (_C.Layer)
## @param tile_id: 新的图块 ID (-1 表示移除)
func set_cell_at(global_pos: Vector2, layer_enum: int, tile_id: int) -> void:
	if not _is_initialized:
		return

	var tile_coord := _MapUtils.world_to_tile(global_pos)

	match layer_enum:
		_C.Layer.GROUND:
			if tile_id == -1:
				_ground_layer.erase_cell(tile_coord)
			else:
				_set_ground_cell(tile_coord, tile_id)
			# 更新周边连接
			_update_terrain_connections([tile_coord])

		_C.Layer.DECORATION:
			if tile_id == -1:
				_decoration_layer.erase_cell(tile_coord)
			else:
				_set_object_cell(tile_coord, _C.Layer.DECORATION, tile_id)

		_C.Layer.OBSTACLE:
			if tile_id == -1:
				_obstacle_layer.erase_cell(tile_coord)
			else:
				_set_object_cell(tile_coord, _C.Layer.OBSTACLE, tile_id)
			# 障碍物变化时更新导航
			_update_navigation_cell(tile_coord, tile_id != -1)

# =============================================================================
# 内部辅助方法 (Internal Helpers)
# =============================================================================



## 设置地面层单元格
func _set_ground_cell(tile_coord: Vector2i, visual_id: int) -> void:
	if _ground_layer == null or visual_id < 0:
		return

	# 使用 Godot 内置地形系统
	_ground_layer.set_cells_terrain_connect([tile_coord], 0, visual_id)


## 设置物体层单元格
func _set_object_cell(tile_coord: Vector2i, layer: int, object_id: int) -> void:
	if object_id < 0:
		return

	var target_layer: TileMapLayer = get_layer(layer)
	if target_layer == null:
		return

	# 从配置表获取资源信息
	var resource_config = _C.OBJECT_RESOURCE_TABLE.get(object_id)
	if resource_config == null:
		return

	var source_id: int = resource_config.get("source_id", -1)
	var atlas_coord: Vector2i = resource_config.get("atlas", Vector2i(-1, -1))

	# 如果 source_id 为 -1 (未配置资源)，则跳过渲染
	if source_id < 0:
		return

	target_layer.set_cell(tile_coord, source_id, atlas_coord)



## 更新地形连接 (预留接口，BetterTerrain 插件可选)
func _update_terrain_connections(_cells: Array[Vector2i]) -> void:
	# BetterTerrain 插件未启用时，此函数为空操作
	# 如需启用 BetterTerrain 自动连接功能，请安装插件并取消注释以下代码:
	if not _cells.is_empty():
		var t_before = Time.get_ticks_usec()
		print("[DEBUG] _update_terrain_connections - Calling BetterTerrain.update_terrain_cells with %d cells" % _cells.size())
		_ShadowChunkRenderer.shared_mutex.lock()
		BetterTerrain.update_terrain_cells(_ground_layer, _cells)
		_ShadowChunkRenderer.shared_mutex.unlock()
		var t_after = Time.get_ticks_usec()
		print("[DEBUG] _update_terrain_connections - BetterTerrain.update_terrain_cells took %d us (%.2f ms)" % [t_after - t_before, (t_after - t_before) / 1000.0])
	pass



# =============================================================================
# 导航层方法 (Navigation Layer Methods)
# =============================================================================

## 批量更新区块的导航数据
## @param coord: 区块坐标
## @param data: 区块数据
func _update_chunk_navigation(coord: Vector2i, data) -> void:
	if _navigation_layer == null:
		return
	
	var base_tile := Vector2i(
		coord.x * _C.CHUNK_SIZE,
		coord.y * _C.CHUNK_SIZE
	)

	for local_y in range(_C.CHUNK_SIZE):
		for local_x in range(_C.CHUNK_SIZE):
			var tile_coord := base_tile + Vector2i(local_x, local_y)

			# 判断是否可通行，这里仅设置了可通行地块
			if not _is_tile_blocked(local_x, local_y, data):
				_navigation_layer.set_cell(tile_coord, NAV_SOURCE_ID, NAV_TILE_PASSABLE)
	
	
	

## 更新单个导航格 (用于实时交互)
## @param tile_coord: 瓦片坐标
## @param is_blocked: 是否阻挡
func _update_navigation_cell(tile_coord: Vector2i, is_blocked: bool) -> void:
	if _navigation_layer == null:
		return
	_set_navigation_cell(tile_coord, is_blocked)


## 设置导航层单元格
## @param tile_coord: 瓦片坐标
## @param is_blocked: 是否阻挡
func _set_navigation_cell(tile_coord: Vector2i, is_blocked: bool) -> void:
	if _navigation_layer == null:
		return

	if is_blocked:
		# 设置为不可通行瓦片
		_navigation_layer.set_cell(tile_coord, NAV_SOURCE_ID, NAV_TILE_BLOCKED)
	else:
		# 设置为可通行瓦片
		_navigation_layer.set_cell(tile_coord, NAV_SOURCE_ID, NAV_TILE_PASSABLE)


## 判断瓦片是否被阻挡
## 阻挡条件:
## 1. 高度为 0 (水体/悬崖)
## 2. 障碍层有物体 (树木、建筑等)
## @param local_x: 区块内局部 X 坐标
## @param local_y: 区块内局部 Y 坐标
## @param data: 区块数据
## @return: true 表示阻挡, false 表示可通行
func _is_tile_blocked(local_x: int, local_y: int, data) -> bool:
	# 检查高度: 高度为 0 表示水体或悬崖，不可通行
	# 注意: MapGenerator 生成的 watertile 是 terrain_id=0, elevation=0
	var elevation = data.get_elevation(local_x, local_y)
	if elevation == 0:
		return true

	# 检查障碍层是否有物体
	# 注意: 即使物体层不渲染 (OBJECT_SOURCE_ID = -1)，逻辑阻挡仍然有效
	var obstacle_id = data.get_object(local_x, local_y, _C.Layer.OBSTACLE)
	if obstacle_id > 0:
		return true

	return false

# =============================================================================
# 工具方法 (Utility Methods)
# =============================================================================

## 获取指定瓦片坐标的层引用
func get_layer(layer_enum: int) -> TileMapLayer:
	match layer_enum:
		_C.Layer.GROUND:
			return _ground_layer
		_C.Layer.DECORATION:
			return _decoration_layer
		_C.Layer.OBSTACLE:
			return _obstacle_layer
		_:
			return null


## 检查瓦片是否可通行
func is_tile_walkable(tile_coord: Vector2i) -> bool:
	# 检查障碍层是否有阻挡物
	if _obstacle_layer:
		var source_id := _obstacle_layer.get_cell_source_id(tile_coord)
		if source_id != -1:
			return false
	return true


## 手动初始化 (用于动态创建场景)
func manual_initialize(ground: TileMapLayer, decoration: TileMapLayer, obstacle: TileMapLayer, navigation: TileMapLayer = null) -> void:
	_ground_layer = ground
	_decoration_layer = decoration
	_obstacle_layer = obstacle
	_navigation_layer = navigation
	_initialize()
