## MapGenerator.gd
## 地图生成器 - 纯计算组件
## 路径: res://Scripts/Components/MapGenerator.gd
## 继承: Node
##
## 职责:
## 当磁盘中不存在请求的区块数据时，负责根据种子生成新的 ChunkData。
## 使用 FastNoiseLite 进行程序化地形生成，保证相同种子生成相同结果。
class_name MapGenerator
extends Node

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _ChunkData = preload("res://Scripts/data/ChunkData.gd")

# =============================================================================
# 导出变量 (Exported Variables)
# =============================================================================

@export_group("Noise Settings")
@export var noise_frequency: float = 0.02
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5

@export_group("Generation Settings")
## 树木生成密度 (0.0 ~ 1.0)
@export var tree_density: float = 0.08
## 石头生成密度 (0.0 ~ 1.0)
@export var stone_density: float = 0.03
## 草丛生成密度 (0.0 ~ 1.0)
@export var grass_density: float = 0.15

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 世界种子
var _seed: int = 0

## 地形噪声生成器
var _terrain_noise: FastNoiseLite

## 物体分布噪声生成器
var _scatter_noise: FastNoiseLite

## 是否已初始化
var _is_initialized: bool = false

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	pass

# =============================================================================
# 公共接口 (API)
# =============================================================================

## 使用种子初始化生成器
## @param seed: 世界种子，相同种子保证生成相同地形
func initialize(world_seed: int) -> void:
	_seed = world_seed
	_setup_noise()
	_is_initialized = true


## 生成指定坐标的区块数据
## @param chunk_coord: 区块坐标
## @return: 生成的 ChunkData，如果未初始化返回 null
func generate_chunk(chunk_coord: Vector2i):
	if not _is_initialized:
		push_error("MapGenerator: Not initialized. Call initialize() first.")
		return null

	var chunk = _ChunkData.new(chunk_coord)

	# 生成地面层 (Layer 0)
	_generate_terrain(chunk)

	# 生成物体层 (Layer 1 & 2)
	_generate_objects(chunk)

	# 新生成的数据标记为脏，需要保存
	chunk.is_dirty = true

	return chunk


## 检查是否已初始化
func is_initialized() -> bool:
	return _is_initialized


## 获取当前种子
func get_seed() -> int:
	return _seed

# =============================================================================
# 内部方法 - 噪声设置 (Noise Setup)
# =============================================================================

## 设置噪声生成器
func _setup_noise() -> void:
	# 地形噪声 - 用于生成基础地形
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = _seed
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = noise_frequency
	_terrain_noise.fractal_octaves = noise_octaves
	_terrain_noise.fractal_lacunarity = noise_lacunarity
	_terrain_noise.fractal_gain = noise_gain

	# 物体分布噪声 - 用于决定物体放置
	_scatter_noise = FastNoiseLite.new()
	_scatter_noise.seed = _seed + 12345  # 偏移种子避免与地形相关
	_scatter_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_scatter_noise.frequency = 0.5

# =============================================================================
# 内部方法 - 地形生成 (Terrain Generation)
# =============================================================================

## 生成地面层数据 (地形 + 高度)
func _generate_terrain(chunk) -> void:
	var base_x = chunk.coord.x * _C.CHUNK_SIZE
	var base_y = chunk.coord.y * _C.CHUNK_SIZE

	for local_y in range(_C.CHUNK_SIZE):
		for local_x in range(_C.CHUNK_SIZE):
			var world_x = base_x + local_x
			var world_y = base_y + local_y

			# 获取噪声值并映射到地形 ID 和高度
			var result := _sample_terrain(world_x, world_y)
			chunk.set_terrain(local_x, local_y, result.terrain_id)
			chunk.set_elevation(local_x, local_y, result.elevation)


## 采样地形噪声，返回地形 ID 和高度
## @return: Dictionary { terrain_id: int, elevation: int }
func _sample_terrain(world_x: int, world_y: int) -> Dictionary:
	var noise_value := _terrain_noise.get_noise_2d(world_x, world_y)
	# 噪声值范围 -1 ~ 1，映射到 0 ~ 1
	var normalized := (noise_value + 1.0) * 0.5

	# 根据噪声值返回不同地形 ID 和高度
	# 高度与地形类型对应，便于查询
	if normalized < 0.3:
		return { "terrain_id": 1, "elevation": 0 }   # 水/深色地面 - 高度 0
	elif normalized < 0.5:
		return { "terrain_id": 2, "elevation": 1 }   # 草地/普通地面 - 高度 1
	elif normalized < 0.7:
		return { "terrain_id": 3, "elevation": 2 }   # 泥土/浅色地面 - 高度 2
	elif normalized < 0.85:
		return { "terrain_id": 4, "elevation": 3 }   # 石头/高地 - 高度 3
	else:
		return { "terrain_id": 5, "elevation": 4 }   # 山峰 - 高度 4

# =============================================================================
# 内部方法 - 物体生成 (Object Generation)
# =============================================================================

## 生成装饰层和障碍层物体
func _generate_objects(chunk) -> void:
	var base_x = chunk.coord.x * _C.CHUNK_SIZE
	var base_y = chunk.coord.y * _C.CHUNK_SIZE

	for local_y in range(_C.CHUNK_SIZE):
		for local_x in range(_C.CHUNK_SIZE):
			var world_x = base_x + local_x
			var world_y = base_y + local_y

			# 获取该位置的高度
			var elevation = chunk.get_elevation(local_x, local_y)

			# 根据高度决定可以生成什么物体
			_try_place_object(chunk, local_x, local_y, world_x, world_y, elevation)


## 尝试在指定位置放置物体
## @param elevation: 该位置的高度值
func _try_place_object(chunk, local_x: int, local_y: int,
		world_x: int, world_y: int, elevation: int) -> void:
	# 水面 (高度 0) 不放置物体
	if elevation <= 0:
		return

	# 使用确定性随机值
	var scatter_value := _scatter_noise.get_noise_2d(world_x, world_y)
	var normalized := (scatter_value + 1.0) * 0.5

	# 使用另一个偏移的噪声值来增加变化
	var secondary_value := _scatter_noise.get_noise_2d(world_x + 1000, world_y + 1000)
	var secondary_normalized := (secondary_value + 1.0) * 0.5

	# 低地 (高度 1-2) - 可以生成草丛和树木
	if elevation <= 2:
		if normalized < grass_density:
			# 放置草丛到装饰层
			chunk.set_object(local_x, local_y, _C.Layer.DECORATION, _C.ID_GRASS)
		elif secondary_normalized < tree_density:
			# 放置树木到装饰层 (按设计文档，树是装饰层)
			chunk.set_object(local_x, local_y, _C.Layer.DECORATION, _C.ID_TREE)

	# 高地 (高度 3+) - 可以生成石头
	elif elevation >= 3:
		if normalized < stone_density:
			# 放置石头到障碍层
			chunk.set_object(local_x, local_y, _C.Layer.OBSTACLE, _C.ID_STONE)
		elif secondary_normalized < tree_density * 0.3:
			# 高地也有少量树木
			chunk.set_object(local_x, local_y, _C.Layer.DECORATION, _C.ID_TREE)
