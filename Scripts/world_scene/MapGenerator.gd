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

@export_group("Noise Settings (噪声设置)")
@export var noise_frequency: float = 0.02
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5

@export_group("Generation Settings (生成设置)")
## 树木生成密度 (0.0 ~ 1.0)
## 控制树木的总体生成概率，值越大树木越多
@export var tree_density: float = 0.20
## 石头生成密度 (0.0 ~ 1.0)
## 控制石头的总体生成概率，值越大石头越多
@export var stone_density: float = 0.20
## 草丛生成密度 (0.0 ~ 1.0)
## 控制草丛的总体生成概率，值越大草丛越多
@export var grass_density: float = 0.30

@export_group("Forest Settings (森林设置)")
## 森林中树木的密度 (0.0 ~ 1.0)
## 控制森林区域内树木的密集程度。
## 建议值: 0.3 ~ 0.6。如果过高(如 1.0)，森林会密不透风；
## 较低的值(如 0.3)会让森林中有更多空隙，便于行走和视觉留白。
@export var forest_tree_density: float = 0.40

## 森林生成的湿度阈值 (0.0 ~ 1.0)
## 决定了多少比例的地图会被判定为"森林区"。
## 值越小(如 0.3)，森林面积越大；值越大(如 0.7)，森林越稀少。
@export var forest_threshold: float = 0.55

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 世界种子
var _seed: int = 0

## 地形噪声生成器 (用于基础地形)
var _terrain_noise: FastNoiseLite

## 高度噪声生成器 (用于高度层)
var _elevation_noise: FastNoiseLite

## 湿度/植被噪声生成器
var _moisture_noise: FastNoiseLite

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

	# 生成地形层 (Base + 4 Height Layers)
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
	# 地形噪声 - 用于生成基础地形类型 (Dirt/Grass/Sand)
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = _seed
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_terrain_noise.frequency = 0.01

	# 高度噪声 - 用于生成高度层级
	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.seed = _seed + 999
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_elevation_noise.frequency = noise_frequency * 0.5 # 降低频率，使山脉更宽阔
	_elevation_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED # 使用 Ridged 模式生成山脊线
	_elevation_noise.fractal_octaves = noise_octaves
	_elevation_noise.fractal_lacunarity = noise_lacunarity
	_elevation_noise.fractal_gain = noise_gain

	# 湿度噪声 - 用于决定植被密度 (森林/草原)
	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = _seed + 555
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture_noise.frequency = 0.008 # 低频，形成大片区域

	# 物体分布噪声 - 用于决定物体放置
	_scatter_noise = FastNoiseLite.new()
	_scatter_noise.seed = _seed + 12345
	_scatter_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_scatter_noise.frequency = 0.5

# =============================================================================
# 内部方法 - 地形生成 (Terrain Generation)
# =============================================================================

## 生成地形数据 (Base Layer + 4 Height Layers)
func _generate_terrain(chunk) -> void:
	var base_x = chunk.coord.x * _C.CHUNK_SIZE
	var base_y = chunk.coord.y * _C.CHUNK_SIZE

	# 生成范围扩大一圈 (-1 到 CHUNK_SIZE)，用于地形连接计算
	for local_y in range(-1, _C.CHUNK_SIZE + 1):
		for local_x in range(-1, _C.CHUNK_SIZE + 1):
			var world_x = base_x + local_x
			var world_y = base_y + local_y

			# 1. 生成基础地形 (Base Layer)
			# 这里简单使用噪声生成 Dirt/Grass/Sand 分布
			var terrain_val = _terrain_noise.get_noise_2d(world_x, world_y)
			var base_id = _C.BASE_TERRAINS.GRASS # 默认草地
			
			# 注意：这些阈值决定了基础地形的分布
			if terrain_val < -0.4:
				base_id = _C.BASE_TERRAINS.WATER
			elif terrain_val < -0.1:
				base_id = _C.BASE_TERRAINS.SAND
			elif terrain_val > 0.4:
				base_id = _C.BASE_TERRAINS.DIRT
			
			chunk.set_terrain(local_x, local_y, base_id, 0) # Layer 0 is Base

			# 2. 生成高度层 (ExH1 - ExH4)
			# 如果基础地形是水，则不生成山脉 (保持水面平坦)
			if base_id == _C.BASE_TERRAINS.WATER:
				continue
				
			var elev_val = _elevation_noise.get_noise_2d(world_x, world_y)
			# Ridged 噪声在 FastNoiseLite 中返回值范围可能在 -1 到 1，但通常偏高
			# 我们需要将其归一化并反转（Ridged 通常是沟壑，取反成山脊）
			# 注意：FastNoiseLite 的 Ridged 模式输出是 1 - |noise|，所以已经是“脊”状了 (0~1)
			# 但为了保险，我们先归一化到 0~1
			var normalized_elev = (elev_val + 1.0) * 0.5 
			
			# 使用指数函数让高山更稀有，使平原更开阔
			normalized_elev = pow(normalized_elev, 2.5) # 增加指数，让山脉更集中
			
			# 限制山脉生成区域：只有在基础地形比较"内陆"的地方才允许生成高山
			# 我们可以复用 terrain_val (它决定了海/沙/土/草)
			# terrain_val > 0.4 是 DIRT/GRASS。值越大越接近大陆中心。
			# 简单的遮罩：如果 terrain_val 不够高，强制压低高度
			if terrain_val < 0.3:
				normalized_elev *= 0.5 # 靠近海边/沙地的地方山脉变矮
			if terrain_val < 0.1:
				normalized_elev = 0.0 # 极靠近海边不生成山
			
			# 调整后的阈值 (配合 Ridged + Pow)
			# ExH1: > 0.30
			# ExH2: > 0.45
			# ExH3: > 0.60
			# ExH4: > 0.75
			
			# 获取每层的默认地形ID
			var t1 = _C.TERRAIN_LAYER_CONFIG[_C.TerrainLayer.EXH_1].default_terrain
			var t2 = _C.TERRAIN_LAYER_CONFIG[_C.TerrainLayer.EXH_2].default_terrain
			var t3 = _C.TERRAIN_LAYER_CONFIG[_C.TerrainLayer.EXH_3].default_terrain
			var t4 = _C.TERRAIN_LAYER_CONFIG[_C.TerrainLayer.EXH_4].default_terrain
			
			if normalized_elev > 0.30:
				chunk.set_terrain(local_x, local_y, t1, 1)
			
			if normalized_elev > 0.45:
				chunk.set_terrain(local_x, local_y, t2, 2)
				
			if normalized_elev > 0.60:
				chunk.set_terrain(local_x, local_y, t3, 3)
				
			if normalized_elev > 0.75:
				chunk.set_terrain(local_x, local_y, t4, 4)

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

			# 获取该位置的最高高度层级
			var max_layer = 0
			if chunk.get_terrain(local_x, local_y, 4) != -1: max_layer = 4
			elif chunk.get_terrain(local_x, local_y, 3) != -1: max_layer = 3
			elif chunk.get_terrain(local_x, local_y, 2) != -1: max_layer = 2
			elif chunk.get_terrain(local_x, local_y, 1) != -1: max_layer = 1
			
			# 根据高度决定可以生成什么物体
			_try_place_object(chunk, local_x, local_y, world_x, world_y, max_layer)


## 尝试在指定位置放置物体
## @param elevation_layer: 该位置的最高高度层级 (0-4)
func _try_place_object(chunk, local_x: int, local_y: int,
		world_x: int, world_y: int, elevation_layer: int) -> void:
	
	# 如果是高度层级 4 (最高峰)，不生成植物
	if elevation_layer >= 4:
		return
		
	# 检查基础地形是否为水面
	# 如果基础层是水，且没有覆盖高度层（即 max_layer == 0），则不生成陆地植物
	# 注意：如果 ExH 层覆盖在水面上（虽然逻辑上不应该发生，除非是悬空岛），也需要考虑
	if elevation_layer == 0:
		var base_id = chunk.get_terrain(local_x, local_y, 0)
		if base_id == _C.BASE_TERRAINS.WATER:
			return

	# 使用确定性随机值
	var scatter_value := _scatter_noise.get_noise_2d(world_x, world_y)
	var normalized := (scatter_value + 1.0) * 0.5

	# 获取湿度值 (决定植被)
	var moisture_val = _moisture_noise.get_noise_2d(world_x, world_y)
	var normalized_moisture = (moisture_val + 1.0) * 0.5
	
	# 判定是否为森林区
	# 使用可配置的阈值 forest_threshold
	var is_forest = normalized_moisture > forest_threshold
	
	# 基础概率配置
	var tree_chance = 0.0
	var grass_chance = 0.0
	var stone_chance = 0.0
	
	# 1. 高山环境 (ExH3+)
	if elevation_layer >= 3:
		stone_chance = stone_density * 1.5 # 很多石头
		tree_chance = 0.0   # 无树
		grass_chance = 0.0  # 无草
		
	# 2. 中山环境 (ExH2)
	elif elevation_layer == 2:
		stone_chance = stone_density * 0.75
		tree_chance = tree_density * 0.25 # 零星树木
		grass_chance = grass_density * 0.3
		
	# 3. 低地环境 (Base ~ ExH1)
	else:
		stone_chance = 0.01 # 极少石头
		
		# 根据基础地形微调
		var base_id = chunk.get_terrain(local_x, local_y, 0)
		
		if base_id == _C.BASE_TERRAINS.GRASS:
			grass_chance = grass_density
			tree_chance = tree_density * 0.4 # 基础草原有少量树
			if is_forest: 
				# 森林区树木密度由 forest_tree_density 控制
				tree_chance = forest_tree_density 
				grass_chance = grass_density * 0.5 # 草稍微变少因为被树占了
				
		elif base_id == _C.BASE_TERRAINS.DIRT:
			grass_chance = grass_density * 0.5
			tree_chance = tree_density * 0.1
			if is_forest:
				# 泥土上的稀疏森林，密度打折
				tree_chance = forest_tree_density * 0.5 
				
		elif base_id == _C.BASE_TERRAINS.SAND:
			# 沙地几乎不长东西 (未来可以加仙人掌)
			grass_chance = 0.05
			tree_chance = 0.0
	
	# 执行生成 (优先级: 石头 > 树木 > 草)
	# 使用同一个随机值 normalized 进行区间判定
	
	var current_threshold = 0.0
	
	# 判定石头
	current_threshold += stone_chance
	if normalized < current_threshold:
		var layer = _C.OBJECT_RENDER_LAYER_TABLE.get(_C.ID_STONE, _C.Layer.OBSTACLE)
		chunk.set_object(local_x, local_y, layer, _C.ID_STONE)
		return
		
	# 判定树木
	current_threshold += tree_chance
	if normalized < current_threshold:
		var layer = _C.OBJECT_RENDER_LAYER_TABLE.get(_C.ID_TREE, _C.Layer.DECORATION)
		chunk.set_object(local_x, local_y, layer, _C.ID_TREE)
		return
		
	# 判定草
	current_threshold += grass_chance
	if normalized < current_threshold:
		var layer = _C.OBJECT_RENDER_LAYER_TABLE.get(_C.ID_GRASS, _C.Layer.DECORATION)
		chunk.set_object(local_x, local_y, layer, _C.ID_GRASS)
		return
