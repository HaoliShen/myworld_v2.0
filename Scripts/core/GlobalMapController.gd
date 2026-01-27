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

	# 批量应用地形连接
	# 使用 BetterTerrain 插件 API
	var time=[]
	
	for t_id in terrain_cells:
		if not terrain_cells[t_id].is_empty():
			# _ground_layer.set_cells_terrain_connect(terrain_cells[t_id], _C.GROUND_TERRAIN_SET, t_id, false)
			# 替换为 BetterTerrain.set_cells
			BetterTerrain.set_cells(_ground_layer, terrain_cells[t_id], t_id)
			time.append(Time.get_ticks_usec())

	# 2. 渲染物体层 (Layer 1 & 2)
	for packed_key in data.object_map:
		var unpacked := _MapUtils.unpack_coord(packed_key)
		var local_x := unpacked.x
		var local_y := unpacked.y
		var layer := unpacked.z
		var object_id: int = data.object_map[packed_key]

		var tile_coord := base_tile + Vector2i(local_x, local_y)
		_set_object_cell(tile_coord, layer, object_id)

	var t_obj = Time.get_ticks_usec()

	# 3. 触发 BetterTerrain 更新地形连接
	_update_terrain_connections(ground_cells)
	
	var t_conn = Time.get_ticks_usec()
	
	# 4. 更新导航层
	_update_chunk_navigation(coord, data)
	
	var t_nav = Time.get_ticks_usec()

	print("[Profile] render_chunk %s Total: %d us | Prep: %d | Ground0: %d | ground1: %d | zero: %d | Nav: %d" % [
		coord, t_nav - t_start, 
		t_ground_prep - t_start,
		time[0] - t_ground_prep,
		time[1]-time[0],
		t_conn-t_obj,
		t_nav - t_conn
	])


## 清除指定区块的渲染内容
## 职责:
## 1. 计算该区块在全局 TileMap 中的矩形范围
## 2. 将该范围内的三层 TileMapLayer 数据全部置空
## 3. 触发 BetterTerrain 更新，确保移除后邻接区块的边缘纹理正确闭合
## @param coord: 区块坐标
func clear_chunk(coord: Vector2i) -> void:
	if not _is_initialized:
		return

	var base_tile := Vector2i(
		coord.x * _C.CHUNK_SIZE,
		coord.y * _C.CHUNK_SIZE
	)

	var cleared_cells: Array[Vector2i] = []

	# 清除所有层的瓦片
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

	# 更新邻接区块的边缘连接
	_update_terrain_connections(cleared_cells)

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
		BetterTerrain.update_terrain_cells(_ground_layer, _cells)
	pass


## 将视觉 ID 转换为 Atlas 坐标 (回退方案)
func _visual_id_to_atlas(visual_id: int) -> Vector2i:
	# 测试模式: 所有地形都使用同一个 tile (0, 0)
	# TODO: 实际项目中应根据 visual_id 映射到正确的 Atlas 坐标
	# 简单映射: visual_id = base_type * 10 + elevation
	# Atlas 坐标: x = elevation, y = base_type
	# var base_type := visual_id / 10
	# var elevation := visual_id % 10
	# return Vector2i(elevation, base_type)
	return Vector2i(0, 0)  # 测试 tile

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

			# 判断是否可通行
			var is_blocked := _is_tile_blocked(local_x, local_y, data)
			_set_navigation_cell(tile_coord, is_blocked)


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
