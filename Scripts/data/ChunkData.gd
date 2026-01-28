## ChunkData.gd
## 区块数据模型 - 内存中存储单个区块的所有状态
## 路径: res://Scripts/Data/ChunkData.gd
## 继承: RefCounted
##
## 职责:
## 内存中存储单个区块的所有状态，是数据流转的唯一真理 (Source of Truth)。
## 存储范围扩大了一圈 (Padding)，包含 34x34 的数据，以便进行本地地形连接计算。
class_name ChunkData
extends RefCounted

# 预加载依赖
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

# =============================================================================
# 属性 (Properties)
# =============================================================================

## 区块坐标 (Chunk Coordinate)
var coord: Vector2i = Vector2i.ZERO

## 脏标记。当数据发生修改时置为 true，用于决定卸载时是否需要回写磁盘。
var is_dirty: bool = false

## [Layer 0 - Data A] 地形类型数据 (Terrain Type ID)
## 大小: 34x34 (包含周围 1 格 padding)
## 索引: (y + 1) * 34 + (x + 1)
var terrain_map: PackedInt32Array

## [Layer 0 - Data B] 地形高度数据 (Elevation Level)
## 大小: 34x34
var elevation_map: PackedByteArray

## [Layer 1 & 2] 物体层数据 (稀疏存储)
## Key: int (Packed Local Coord) -> Value: int (Tile ID)
## 注意: Object 不需要 Padding，因为通常不需要连接计算。如果需要，也可以扩展。
## 目前保持仅存储 0..31 范围内的物体。
var object_map: Dictionary = {}

# =============================================================================
# 构造与初始化 (Construction & Initialization)
# =============================================================================

## 初始化函数
func _init(target_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = target_coord

	# 1. 初始化地形 ID 数组 (34x34)
	terrain_map = PackedInt32Array()
	terrain_map.resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
	terrain_map.fill(-1)  # 默认空

	# 2. 初始化高度数组 (34x34)
	elevation_map = PackedByteArray()
	elevation_map.resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
	elevation_map.fill(0)  # 默认高度 0

# =============================================================================
# 高度操作 (Elevation Operations)
# =============================================================================

## 获取高度 (支持 -1 到 32)
func get_elevation(x: int, y: int) -> int:
	# 边界检查放宽到 -1 ~ 32
	if x < -1 or x >= _C.CHUNK_SIZE + 1 or y < -1 or y >= _C.CHUNK_SIZE + 1:
		return 0
	
	# 映射到内部索引 (0~33)
	var internal_x := x + 1
	var internal_y := y + 1
	return elevation_map[internal_y * _C.CHUNK_DATA_SIZE + internal_x]


## 设置高度 (支持 -1 到 32)
func set_elevation(x: int, y: int, h: int) -> void:
	if x < -1 or x >= _C.CHUNK_SIZE + 1 or y < -1 or y >= _C.CHUNK_SIZE + 1:
		return
		
	var internal_x := x + 1
	var internal_y := y + 1
	var idx := internal_y * _C.CHUNK_DATA_SIZE + internal_x
	
	if elevation_map[idx] != h:
		elevation_map[idx] = h
		is_dirty = true

# =============================================================================
# 地形操作 (Terrain Operations)
# =============================================================================

## 获取地形 ID (支持 -1 到 32)
func get_terrain(x: int, y: int) -> int:
	if x < -1 or x >= _C.CHUNK_SIZE + 1 or y < -1 or y >= _C.CHUNK_SIZE + 1:
		return -1
		
	var internal_x := x + 1
	var internal_y := y + 1
	return terrain_map[internal_y * _C.CHUNK_DATA_SIZE + internal_x]


## 设置地形 ID (支持 -1 到 32)
func set_terrain(x: int, y: int, id: int) -> void:
	if x < -1 or x >= _C.CHUNK_SIZE + 1 or y < -1 or y >= _C.CHUNK_SIZE + 1:
		return
		
	var internal_x := x + 1
	var internal_y := y + 1
	var idx := internal_y * _C.CHUNK_DATA_SIZE + internal_x
	
	if terrain_map[idx] != id:
		terrain_map[idx] = id
		is_dirty = true

# =============================================================================
# 物体操作 (Object Operations)
# =============================================================================

## 获取物体 (Object 不需要 Padding，保持 0-31)
func get_object(x: int, y: int, layer: int) -> int:
	if x < 0 or x >= _C.CHUNK_SIZE or y < 0 or y >= _C.CHUNK_SIZE:
		return -1
	var key := _MapUtils.pack_coord(x, y, layer)
	return object_map.get(key, -1)


## 设置物体
func set_object(x: int, y: int, layer: int, tile_id: int) -> void:
	if x < 0 or x >= _C.CHUNK_SIZE or y < 0 or y >= _C.CHUNK_SIZE:
		return
		
	var key := _MapUtils.pack_coord(x, y, layer)

	if tile_id == -1:
		if object_map.has(key):
			object_map.erase(key)
			is_dirty = true
	else:
		if object_map.get(key) != tile_id:
			object_map[key] = tile_id
			is_dirty = true


## 检查物体是否存在
func has_object_at(x: int, y: int, layer: int) -> bool:
	return object_map.has(_MapUtils.pack_coord(x, y, layer))

# =============================================================================
# 序列化接口 (Serialization)
# =============================================================================

## 序列化 (保存完整的 34x34 数据)
func to_bytes() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()

	# 1. 地形 (34x34)
	var t_bytes := terrain_map.to_byte_array()
	buffer.put_32(t_bytes.size())
	buffer.put_data(t_bytes)

	# 2. 高度 (34x34)
	buffer.put_32(elevation_map.size())
	buffer.put_data(elevation_map)

	# 3. 物体
	var o_bytes := var_to_bytes(object_map)
	buffer.put_data(o_bytes)

	return buffer.data_array


## 反序列化
static func from_bytes(target_coord: Vector2i, data: PackedByteArray):
	var instance = (load("res://Scripts/data/ChunkData.gd") as GDScript).new(target_coord)
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data

	# 1. 地形
	var t_size := buffer.get_32()
	var t_result := buffer.get_data(t_size)
	if t_result[0] == OK:
		instance.terrain_map = t_result[1].to_int32_array()
		# 校验尺寸，如果旧存档是 32x32，需要迁移 (这里暂且假设都是新档)
		if instance.terrain_map.size() != _C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE:
			# 简单的迁移逻辑：重新 resize 并填充默认值
			instance.terrain_map = PackedInt32Array()
			instance.terrain_map.resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
			instance.terrain_map.fill(-1)
			# 这里如果需要迁移旧数据，逻辑会比较复杂，暂时忽略，假设重开档

	# 2. 高度
	var e_size := buffer.get_32()
	var e_result := buffer.get_data(e_size)
	if e_result[0] == OK:
		instance.elevation_map = e_result[1]

	# 3. 物体
	var o_bytes_size := buffer.get_available_bytes()
	if o_bytes_size > 0:
		var o_result := buffer.get_data(o_bytes_size)
		if o_result[0] == OK:
			var loaded_obj = bytes_to_var(o_result[1])
			if loaded_obj is Dictionary:
				instance.object_map = loaded_obj

	instance.is_dirty = false
	return instance

# =============================================================================
# 辅助方法
# =============================================================================

func clear_dirty() -> void:
	is_dirty = false

func get_object_count() -> int:
	return object_map.size()

func is_empty() -> bool:
	# 检查中心区域
	for y in range(_C.CHUNK_SIZE):
		for x in range(_C.CHUNK_SIZE):
			if get_terrain(x, y) != -1:
				return false
	return object_map.is_empty()
