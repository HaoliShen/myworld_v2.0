## ChunkData.gd
## 区块数据模型 - 内存中存储单个区块的所有状态
## 路径: res://Scripts/Data/ChunkData.gd
## 继承: RefCounted
##
## 职责:
## 内存中存储单个区块的所有状态，是数据流转的唯一真理 (Source of Truth)。
## 它不包含任何节点引用，不处理渲染，仅负责数据的存储、查询、修改和序列化。
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
## 存储: 地面材质 ID (如 _C.ID_TREE = 300)
## 类型: PackedInt32Array
## 理由: 使用 Int32 而非 Byte，因为物体 ID 可能超过 255 (例如 300, 400)
## 访问: 直接通过索引访问，无需解压
var terrain_map: PackedInt32Array

## [Layer 0 - Data B] 地形高度数据 (Elevation Level)
## 存储: 绝对高度值 (0, 1, 2...)
## 类型: PackedByteArray
## 理由: 高度层级通常不会超过 255 层，使用 Byte 最省内存
## 访问: elevation_map[index] 直接返回整数，无需位运算
var elevation_map: PackedByteArray

## [Layer 1 & 2] 物体层数据 (稀疏存储)
## Key: int (Packed Local Coord) -> Value: int (Tile ID)
## 存储: 树木、墙壁等稀疏物体
## 使用 _MapUtils.pack_coord(x, y, layer) 生成 Key
var object_map: Dictionary = {}

# =============================================================================
# 构造与初始化 (Construction & Initialization)
# =============================================================================

## 初始化函数
func _init(target_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = target_coord

	# 1. 初始化地形 ID 数组 (32位整数)
	terrain_map = PackedInt32Array()
	terrain_map.resize(_C.CHUNK_SIZE * _C.CHUNK_SIZE)
	terrain_map.fill(-1)  # 默认空

	# 2. 初始化高度数组 (8位字节)
	elevation_map = PackedByteArray()
	elevation_map.resize(_C.CHUNK_SIZE * _C.CHUNK_SIZE)
	elevation_map.fill(0)  # 默认高度 0

# =============================================================================
# 高度操作 (Elevation Operations) - 最频繁调用的逻辑
# =============================================================================

## 获取高度
## 复杂度: O(1) 直接内存访问
## @param x: 区块内局部 X 坐标 (0 ~ CHUNK_SIZE-1)
## @param y: 区块内局部 Y 坐标 (0 ~ CHUNK_SIZE-1)
## @return: 高度值
func get_elevation(x: int, y: int) -> int:
	if x < 0 or x >= _C.CHUNK_SIZE or y < 0 or y >= _C.CHUNK_SIZE:
		return 0
	return elevation_map[y * _C.CHUNK_SIZE + x]


## 设置高度
## @param x: 区块内局部 X 坐标 (0 ~ CHUNK_SIZE-1)
## @param y: 区块内局部 Y 坐标 (0 ~ CHUNK_SIZE-1)
## @param h: 高度值
func set_elevation(x: int, y: int, h: int) -> void:
	if x < 0 or x >= _C.CHUNK_SIZE or y < 0 or y >= _C.CHUNK_SIZE:
		return
	var idx := y * _C.CHUNK_SIZE + x
	if elevation_map[idx] != h:
		elevation_map[idx] = h
		is_dirty = true

# =============================================================================
# 地形操作 (Terrain Operations) - Layer 0
# =============================================================================

## 获取指定位置的地形 ID
## @param x: 区块内局部 X 坐标 (0 ~ CHUNK_SIZE-1)
## @param y: 区块内局部 Y 坐标 (0 ~ CHUNK_SIZE-1)
## @return: 地形 ID，越界返回 -1
func get_terrain(x: int, y: int) -> int:
	if x < 0 or x >= _C.CHUNK_SIZE or y < 0 or y >= _C.CHUNK_SIZE:
		return -1
	return terrain_map[y * _C.CHUNK_SIZE + x]


## 设置指定位置的地形 ID
## @param x: 区块内局部 X 坐标 (0 ~ CHUNK_SIZE-1)
## @param y: 区块内局部 Y 坐标 (0 ~ CHUNK_SIZE-1)
## @param id: 地形 ID
func set_terrain(x: int, y: int, id: int) -> void:
	if x < 0 or x >= _C.CHUNK_SIZE or y < 0 or y >= _C.CHUNK_SIZE:
		return
	var idx := y * _C.CHUNK_SIZE + x
	if terrain_map[idx] != id:
		terrain_map[idx] = id
		is_dirty = true

# =============================================================================
# 物体操作 (Object Operations) - Layer 1 & 2
# =============================================================================

## 获取指定位置和层级的物体 ID
## @param x: 区块内局部 X 坐标 (0 ~ CHUNK_SIZE-1)
## @param y: 区块内局部 Y 坐标 (0 ~ CHUNK_SIZE-1)
## @param layer: 层级 (_C.Layer.DECORATION 或 _C.Layer.OBSTACLE)
## @return: 物体 ID，不存在返回 -1
func get_object(x: int, y: int, layer: int) -> int:
	var key := _MapUtils.pack_coord(x, y, layer)
	return object_map.get(key, -1)


## 设置物体 (如果 tile_id 为 -1，则移除)
## @param x: 区块内局部 X 坐标 (0 ~ CHUNK_SIZE-1)
## @param y: 区块内局部 Y 坐标 (0 ~ CHUNK_SIZE-1)
## @param layer: 层级 (_C.Layer.DECORATION 或 _C.Layer.OBSTACLE)
## @param tile_id: 物体 ID，-1 表示移除
func set_object(x: int, y: int, layer: int, tile_id: int) -> void:
	var key := _MapUtils.pack_coord(x, y, layer)

	if tile_id == -1:
		if object_map.has(key):
			object_map.erase(key)
			is_dirty = true
	else:
		# 只有当 ID 真正改变时才标记 dirty
		if object_map.get(key) != tile_id:
			object_map[key] = tile_id
			is_dirty = true


## 检查某位置是否有任何物体 (用于碰撞检测预判)
## @param x: 区块内局部 X 坐标
## @param y: 区块内局部 Y 坐标
## @param layer: 层级
## @return: 是否存在物体
func has_object_at(x: int, y: int, layer: int) -> bool:
	return object_map.has(_MapUtils.pack_coord(x, y, layer))

# =============================================================================
# 序列化接口 (Serialization)
# =============================================================================
# 用于与 RegionDatabase (SQLite) 交互。
# 结构: [Terrain(Int32) Bytes] + [Elevation(Byte) Bytes] + [Object Dictionary]

## 将对象序列化为二进制流
func to_bytes() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()

	# 1. 写入地形 (Int32 Array -> Bytes)
	var t_bytes := terrain_map.to_byte_array()
	buffer.put_32(t_bytes.size())
	buffer.put_data(t_bytes)

	# 2. 写入高度 (Byte Array -> Bytes)
	# PackedByteArray 本身就是 Bytes，无需转换，直接写入内容
	buffer.put_32(elevation_map.size())
	buffer.put_data(elevation_map)

	# 3. 写入物体 (Dictionary)
	var o_bytes := var_to_bytes(object_map)
	buffer.put_data(o_bytes)

	return buffer.data_array


## 从二进制流还原对象 (静态工厂方法)
## @param target_coord: 区块坐标
## @param data: 二进制数据
## @return: 还原的 ChunkData 实例
static func from_bytes(target_coord: Vector2i, data: PackedByteArray):
	var instance = (load("res://Scripts/data/ChunkData.gd") as GDScript).new(target_coord)
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data

	# 1. 读取地形
	var t_size := buffer.get_32()
	var t_result := buffer.get_data(t_size)
	if t_result[0] == OK:
		instance.terrain_map = t_result[1].to_int32_array()

	# 2. 读取高度
	var e_size := buffer.get_32()
	var e_result := buffer.get_data(e_size)
	if e_result[0] == OK:
		instance.elevation_map = e_result[1]  # 直接赋值，无需转换

	# 3. 读取物体
	var o_bytes_size := buffer.get_available_bytes()
	if o_bytes_size > 0:
		var o_result := buffer.get_data(o_bytes_size)
		if o_result[0] == OK:
			var loaded_obj = bytes_to_var(o_result[1])
			if loaded_obj is Dictionary:
				instance.object_map = loaded_obj

	# 新加载的数据默认是干净的
	instance.is_dirty = false

	return instance

# =============================================================================
# 辅助方法 (Helper Methods)
# =============================================================================

## 清除脏标记 (保存后调用)
func clear_dirty() -> void:
	is_dirty = false


## 获取物体数量 (用于调试/统计)
func get_object_count() -> int:
	return object_map.size()


## 检查区块是否为空 (全部默认值)
func is_empty() -> bool:
	# 检查地形是否全为 -1
	for i in range(terrain_map.size()):
		if terrain_map[i] != -1:
			return false
	# 检查物体是否为空
	return object_map.is_empty()
