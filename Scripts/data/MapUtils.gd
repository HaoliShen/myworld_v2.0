## MapUtils.gd
## 地图工具类 - 提供纯数学计算与坐标转换服务
## 路径: res://Scripts/Data/MapUtils.gd
## 继承: RefCounted (作为静态库使用)
##
## 职责: 连接 "屏幕像素"、"内存数据" 和 "硬盘文件" 三者的桥梁。
## 本脚本不存储任何状态，所有函数均为 static。
##
## 核心概念：四级坐标系
## 1. 世界像素坐标 (World Position): Vector2(float) - Godot 引擎底层坐标
## 2. 瓦片坐标 (Tile Coordinate): Vector2i - 网格坐标
## 3. 区块坐标 (Chunk Coordinate): Vector2i - 内存加载/渲染单位
## 4. 区域坐标 (Region Coordinate): Vector2i - 文件存储单位
class_name MapUtils
extends RefCounted

# 预加载依赖
const _C = preload("res://Scripts/data/Constants.gd")

# 常量别名 (便于访问)
static var TILE_SIZE: int:
	get: return _C.TILE_SIZE
static var CHUNK_SIZE: int:
	get: return _C.CHUNK_SIZE
static var CHUNK_SIZE_PIXELS: int:
	get: return _C.CHUNK_SIZE_PIXELS
static var REGION_SIZE: int:
	get: return _C.REGION_SIZE

# =============================================================================
# 坐标转换: 世界 <-> 瓦片 (World <-> Tile)
# =============================================================================

## 将世界像素坐标转换为全局瓦片坐标
## 算法: floor(pos / TILE_SIZE)
## 场景: InputManager 确定点击了哪个瓦片
static func world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(pos.x / _C.TILE_SIZE),
		floori(pos.y / _C.TILE_SIZE)
	)


## 瓦片坐标转世界坐标 (左上角)
static func tile_to_world(tile_coord: Vector2i) -> Vector2:
	return Vector2(
		tile_coord.x * _C.TILE_SIZE,
		tile_coord.y * _C.TILE_SIZE
	)


## 瓦片坐标转世界坐标 (中心点)
static func tile_to_world_center(tile_coord: Vector2i) -> Vector2:
	return Vector2(
		tile_coord.x * _C.TILE_SIZE + _C.TILE_SIZE * 0.5,
		tile_coord.y * _C.TILE_SIZE + _C.TILE_SIZE * 0.5
	)


# =============================================================================
# 坐标转换: 世界 <-> 区块 (World <-> Chunk)
# =============================================================================

## 将世界像素坐标转换为其所属的区块坐标
## 算法: floor(pos / (TILE_SIZE * CHUNK_SIZE))
## 场景: WorldManager 判断玩家跨越区块；InputManager 确定点击了哪个区块的数据
static func world_to_chunk(pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(pos.x / _C.CHUNK_SIZE_PIXELS),
		floori(pos.y / _C.CHUNK_SIZE_PIXELS)
	)


## 区块坐标转世界坐标 (左上角)
static func chunk_to_world(chunk_coord: Vector2i) -> Vector2:
	return Vector2(
		chunk_coord.x * _C.CHUNK_SIZE_PIXELS,
		chunk_coord.y * _C.CHUNK_SIZE_PIXELS
	)


## 区块坐标转世界坐标 (中心点)
static func chunk_to_world_center(chunk_coord: Vector2i) -> Vector2:
	return Vector2(
		chunk_coord.x * _C.CHUNK_SIZE_PIXELS + _C.CHUNK_SIZE_PIXELS * 0.5,
		chunk_coord.y * _C.CHUNK_SIZE_PIXELS + _C.CHUNK_SIZE_PIXELS * 0.5
	)


# =============================================================================
# 坐标转换: 瓦片 <-> 区块 (Tile <-> Chunk)
# =============================================================================

## 瓦片坐标转区块坐标
static func tile_to_chunk(tile_coord: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile_coord.x) / _C.CHUNK_SIZE),
		floori(float(tile_coord.y) / _C.CHUNK_SIZE)
	)


## 获取瓦片在区块内的局部坐标 (0 ~ CHUNK_SIZE-1)
static func tile_to_local(tile_coord: Vector2i) -> Vector2i:
	return Vector2i(
		posmod(tile_coord.x, _C.CHUNK_SIZE),
		posmod(tile_coord.y, _C.CHUNK_SIZE)
	)


## 区块坐标 + 局部坐标 转 全局瓦片坐标
static func local_to_tile(chunk_coord: Vector2i, local_coord: Vector2i) -> Vector2i:
	return Vector2i(
		chunk_coord.x * _C.CHUNK_SIZE + local_coord.x,
		chunk_coord.y * _C.CHUNK_SIZE + local_coord.y
	)


# =============================================================================
# 坐标转换: 区块 <-> 区域 (Chunk <-> Region)
# =============================================================================

## 将区块坐标转换为其所属的区域文件坐标
## 算法: floor(coord / REGION_SIZE)
## 注意: 必须使用向下取整除法 (floori)，确保负数坐标处理的连续性
##       例如 -1 属于 Region -1 而非 0
## 场景: RegionDatabase 决定读写哪个 .rg 文件
static func chunk_to_region(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(chunk_coord.x) / _C.REGION_SIZE),
		floori(float(chunk_coord.y) / _C.REGION_SIZE)
	)


## 获取区块在区域内的局部坐标 (0 ~ REGION_SIZE-1)
static func chunk_to_region_local(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(
		posmod(chunk_coord.x, _C.REGION_SIZE),
		posmod(chunk_coord.y, _C.REGION_SIZE)
	)


## 计算区块在区域文件中的局部索引 (0 ~ 1023)
## 算法: local_y * REGION_SIZE + local_x
## 场景: RegionDatabase 在 Header 中查找偏移量
static func get_chunk_index_in_region(chunk_coord: Vector2i) -> int:
	var local := chunk_to_region_local(chunk_coord)
	return local.y * _C.REGION_SIZE + local.x


## 区域坐标 + 局部坐标 转 全局区块坐标
static func region_local_to_chunk(region_coord: Vector2i, local_coord: Vector2i) -> Vector2i:
	return Vector2i(
		region_coord.x * _C.REGION_SIZE + local_coord.x,
		region_coord.y * _C.REGION_SIZE + local_coord.y
	)


# =============================================================================
# 数据压缩函数 (Data Packing)
# =============================================================================

## 将区块内的局部坐标 (x, y) 和层级 (layer) 压缩为一个整数
## 目的: 作为 ChunkData 中稀疏字典 (object_map) 的 Key，减少内存占用并提升查找速度
## 原理 (位运算):
##   x (0-31) 占 5 bit
##   y (0-31) 占 5 bit
##   layer (0-15) 占 4 bit
##   Result = (x << 9) | (y << 4) | layer
static func pack_coord(x: int, y: int, layer: int) -> int:
	return (x << 9) | (y << 4) | layer


## 解压整数，还原出 x, y 和 layer
## 返回: Vector3i(x, y, layer)
## 场景: GlobalMapController 遍历数据进行渲染时
static func unpack_coord(packed: int) -> Vector3i:
	var x := (packed >> 9) & 0x1F  # 5 bits
	var y := (packed >> 4) & 0x1F  # 5 bits
	var layer := packed & 0x0F     # 4 bits
	return Vector3i(x, y, layer)


# =============================================================================
# 范围与距离 (Bounds & Distance)
# =============================================================================

## 计算两个坐标之间的切比雪夫距离
## 切比雪夫距离 = max(|Δx|, |Δy|)，即"国王走法"的最短步数
## 适用于: 瓦片坐标、区块坐标等任意 Vector2i
## 场景: WorldManager 判断区块属于哪个加载层级
static func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## 获取指定中心和半径的瓦片范围 (切比雪夫距离，即方形范围)
## 返回: 所有在半径内的瓦片坐标数组
## 场景: 范围攻击、区域效果、AOE 技能等
static func get_tiles_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dy)
			tiles.append(coord)

	return tiles


## 获取指定中心和半径的区块范围 (切比雪夫距离，即方形范围)
## 返回: 所有在半径内的区块坐标数组
## 场景: WorldManager 批量加载/卸载区块
static func get_chunks_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dy)
			chunks.append(coord)

	return chunks


# =============================================================================
# 区块遍历 (Chunk Iteration)
# =============================================================================

## 获取区块内所有瓦片的全局坐标
## 注意: 返回 CHUNK_SIZE * CHUNK_SIZE 个坐标，大量使用时注意性能
static func get_tiles_in_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var base_x := chunk_coord.x * _C.CHUNK_SIZE
	var base_y := chunk_coord.y * _C.CHUNK_SIZE

	for y in range(_C.CHUNK_SIZE):
		for x in range(_C.CHUNK_SIZE):
			tiles.append(Vector2i(base_x + x, base_y + y))

	return tiles


## 获取区块的边界矩形 (世界坐标)
static func get_chunk_rect(chunk_coord: Vector2i) -> Rect2:
	var top_left := chunk_to_world(chunk_coord)
	return Rect2(top_left, Vector2(_C.CHUNK_SIZE_PIXELS, _C.CHUNK_SIZE_PIXELS))


## 检查世界坐标是否在指定区块内
static func is_pos_in_chunk(pos: Vector2, chunk_coord: Vector2i) -> bool:
	return get_chunk_rect(chunk_coord).has_point(pos)
