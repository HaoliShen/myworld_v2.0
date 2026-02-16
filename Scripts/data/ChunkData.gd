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

## [Layer 0] 基础地形层 (Terrain Type ID)
## 存储: BASE_TERRAINS 的 ID (0, 1, 2...)
## 大小: 34x34 (包含周围 1 格 padding)
## 索引: (y + 1) * 34 + (x + 1)
var base_layer: PackedByteArray

## [Layer 1-4] 扩展高度层 (稀疏，可能为空)
## 存储: CLIFF_TERRAIN_ID 或 255 (代表 TERRAIN_EMPTY)
## 这是一个数组，包含 4 个 PackedByteArray，分别对应 ExH1, ExH2, ExH3, ExH4
var height_layers: Array[PackedByteArray] = []

## [Object Layer] 物体层数据 (稀疏存储)
## Key: int (Packed Local Coord) -> Value: int (Tile ID)
## 注意: Object 不需要 Padding，因为通常不需要连接计算。
## 目前保持仅存储 0..31 范围内的物体。
var object_map: Dictionary = {}

# =============================================================================
# 构造与初始化 (Construction & Initialization)
# =============================================================================

## 初始化函数
func _init(target_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = target_coord

	# 1. 初始化基础地形层 (34x34)
	base_layer = PackedByteArray()
	base_layer.resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
	# 默认填充泥土
	base_layer.fill(_C.BASE_TERRAINS.DIRT) 

	# 2. 初始化高度层 (34x34 * 4)
	height_layers.resize(4)
	for i in range(4):
		var layer = PackedByteArray()
		layer.resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
		layer.fill(255) # 255 代表 -1 (Empty)
		height_layers[i] = layer

# =============================================================================
# 地形操作 (Terrain Operations)
# =============================================================================

## 获取指定层的地形 ID
## @param layer_index: 0=Base, 1=ExH1, 2=ExH2, 3=ExH3, 4=ExH4
## @return: Terrain ID (0-254) 或 -1 (Empty)
func get_terrain(x: int, y: int, layer_index: int = 0) -> int:
	if x < -1 or x >= _C.CHUNK_SIZE + 1 or y < -1 or y >= _C.CHUNK_SIZE + 1:
		return -1
		
	var internal_x := x + 1
	var internal_y := y + 1
	var idx := internal_y * _C.CHUNK_DATA_SIZE + internal_x
	
	if layer_index == 0:
		return base_layer[idx]
	elif layer_index >= 1 and layer_index <= 4:
		var val = height_layers[layer_index - 1][idx]
		if val == 255:
			return -1
		return val
	
	return -1


## 设置指定层的地形 ID
## @param layer_index: 0=Base, 1=ExH1, 2=ExH2, 3=ExH3, 4=ExH4
func set_terrain(x: int, y: int, id: int, layer_index: int = 0) -> void:
	if x < -1 or x >= _C.CHUNK_SIZE + 1 or y < -1 or y >= _C.CHUNK_SIZE + 1:
		return
		
	var internal_x := x + 1
	var internal_y := y + 1
	var idx := internal_y * _C.CHUNK_DATA_SIZE + internal_x
	
	if layer_index == 0:
		if base_layer[idx] != id:
			base_layer[idx] = id
			is_dirty = true
	elif layer_index >= 1 and layer_index <= 4:
		var stored_val = id
		if id == -1: stored_val = 255
		
		if height_layers[layer_index - 1][idx] != stored_val:
			height_layers[layer_index - 1][idx] = stored_val
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

	# 1. 基础地形层 (34x34)
	var b_bytes := base_layer
	buffer.put_32(b_bytes.size())
	buffer.put_data(b_bytes)

	# 2. 高度层 (4 x 34x34)
	for i in range(4):
		var h_bytes = height_layers[i]
		buffer.put_32(h_bytes.size())
		buffer.put_data(h_bytes)

	# 3. 物体
	var o_bytes := var_to_bytes(object_map)
	buffer.put_data(o_bytes)

	return buffer.data_array


## 反序列化
static func from_bytes(target_coord: Vector2i, data: PackedByteArray):
	var instance = (load("res://Scripts/data/ChunkData.gd") as GDScript).new(target_coord)
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data

	# 1. 基础地形层
	var b_size := buffer.get_32()
	var b_result := buffer.get_data(b_size)
	if b_result[0] == OK:
		instance.base_layer = b_result[1]
		# 校验尺寸 (兼容性处理)
		if instance.base_layer.size() != _C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE:
			instance.base_layer.resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
			instance.base_layer.fill(_C.BASE_TERRAINS.DIRT)

	# 2. 高度层
	for i in range(4):
		if buffer.get_available_bytes() > 0:
			var h_size := buffer.get_32()
			var h_result := buffer.get_data(h_size)
			if h_result[0] == OK:
				instance.height_layers[i] = h_result[1]
				if instance.height_layers[i].size() != _C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE:
					instance.height_layers[i].resize(_C.CHUNK_DATA_SIZE * _C.CHUNK_DATA_SIZE)
					instance.height_layers[i].fill(255)

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
			# 如果基础层不是空的(比如不是 -1, 但基础层默认是 dirt, 所以这里可能需要改逻辑)
			# 这里假设只要有数据就算非空。
			# 实际上，只要生成过，肯定非空。
			pass
	return object_map.is_empty()
