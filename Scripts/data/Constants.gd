## Constants.gd
## 全局常量定义 - 定义游戏核心度量衡、枚举、配置表
## 路径: res://Scripts/Core/Constants.gd
## 继承: RefCounted
##
## 职责: 定义全局常量、枚举、配置表。它是全项目的"字典"，所有魔术数字都应在此统一定义。
class_name Constants
extends RefCounted

# =============================================================================
# 基础度量衡 (Basic Metrics)
# =============================================================================

## 单个瓦片的像素大小 (16x16)
## 用于: MapUtils 坐标转换, InputManager 鼠标定位
const TILE_SIZE: int = 16

## 一个区块包含的瓦片数量 (32x32 tiles = 1024x1024 pixels)
## 用于: ChunkData 数据结构大小, RegionDatabase 文件索引计算
const CHUNK_SIZE: int = 32

## 区块数据尺寸 (包含 1 圈 padding)
## 用于: ChunkData 内部存储
const CHUNK_DATA_SIZE: int = CHUNK_SIZE + 2

## 区块像素尺寸 (派生常量)
const CHUNK_SIZE_PIXELS: int = CHUNK_SIZE * TILE_SIZE  # 1024

## 一个区域包含的区块数量 (32x32 chunks)
## 用于: RegionDatabase 文件组织
const REGION_SIZE: int = 32

# =============================================================================
# 渲染与逻辑层级 (Render & Logic Layers)
# =============================================================================

## 用于: 区分物体在 TileMap 中的层级，以及是否具有碰撞属性
enum Layer {
	## 地面层 (Z-Index: -10, 无 Y-Sort, 无碰撞)
	## 存放: 泥土, 水, 悬崖, 地板
	GROUND = 0,

	## 装饰层 (Y-Sort Enabled, 无碰撞)
	## 存放: 花, 草, 地毯, 农作物
	DECORATION = 1,

	## 障碍层 (Y-Sort Enabled, 有碰撞)
	## 存放: 树木, 墙壁, 家具, 机器
	OBSTACLE = 2
}

# =============================================================================
# 地面配置 (Ground Configuration)
# =============================================================================
##地面层tileset资源路径
const GROUND_TILESET:String = "res://Assets/Tilesets/test_tileset.tres"

## 地面 Terrain Set 索引
const GROUND_TERRAIN_SET: int = 0
const TERRAIN_SET_GROUND: int = 0 # Alias for consistency

## 地形连接位掩码 (Autotiling Bitmask)
const BIT_LEFT: int = 1
const BIT_BOTTOM_LEFT: int = 2
const BIT_BOTTOM: int = 4
const BIT_BOTTOM_RIGHT: int = 8
const BIT_RIGHT: int = 16
const BIT_TOP_RIGHT: int = 32
const BIT_TOP: int = 64
const BIT_TOP_LEFT: int = 128

## 地形层级定义 (用于渲染顺序和逻辑分层)
enum TerrainLayer {
	BASE = 0, # 基础层 (泥土、草地、沙地)
	EXH_1 = 1, # 高度层 1
	EXH_2 = 2, # 高度层 2
	EXH_3 = 3, # 高度层 3
	EXH_4 = 4  # 高度层 4
}

## 地形层级配置
## Key: Layer Index (int) -> Value: { "terrain_set": int, "terrain_id": int }
## 注意：Base Layer 的 terrain_id 可能根据生物群落变化，这里只配置 set
##      ExH 层目前使用固定的 default_terrain，未来也可扩展
const TERRAIN_LAYER_CONFIG: Dictionary = {
	TerrainLayer.BASE:  { "terrain_set": 0 }, # Base Layer 使用 set 0
	TerrainLayer.EXH_1: { "terrain_set": 0, "default_terrain": 4 }, # ExH1 使用 set 0, terrain 3
	TerrainLayer.EXH_2: { "terrain_set": 0, "default_terrain": 5 }, # ExH2 使用 set 0, terrain 3
	TerrainLayer.EXH_3: { "terrain_set": 0, "default_terrain": 6 }, # ExH3 使用 set 0, terrain 3
	TerrainLayer.EXH_4: { "terrain_set": 0, "default_terrain": 7 }, # ExH4 使用 set 0, terrain 3
}

## 基础地形类型定义 (仅用于 Base Layer)
## Key: 类型枚举或字符串 -> Value: 地形 ID (在 TileSet 编辑器中设定的 ID)
## 注意：这些 ID 必须属于 TERRAIN_LAYER_CONFIG[TerrainLayer.BASE].terrain_set
const BASE_TERRAINS: Dictionary = {
	"DIRT":  1, # 对应 TileSet Set 0 中的 Dirt 地形
	"GRASS": 2, # 对应 TileSet Set 0 中的 Grass 地形
	"SAND":  3, # 对应 TileSet Set 0 中的 Sand 地形
	"WATER": 0  # 对应 TileSet Set 0 中的 Water 地形 (假设 ID 为 4)
}

## 空地形标记 (用于表示该层该位置无数据)
const TERRAIN_EMPTY: int = -1

# =============================================================================
# 导航配置 (Navigation Configuration)
# =============================================================================

## 导航 TileSource ID
const NAV_SOURCE_ID: int = 2

## 可通行地块 Atlas 坐标
const NAV_TILE_WALKABLE: Vector2i = Vector2i(56, 25)

## 不可通行地块 Atlas 坐标
const NAV_TILE_UNWALKABLE: Vector2i = Vector2i(56, 26)

# =============================================================================
# 物体配置 (Object Configuration)
# =============================================================================

## 物体 ID 常量 (便于代码引用)
const ID_GRASS: int = 200
const ID_TREE: int = 300
const ID_STONE: int = 400

## 物体 ID 表 (Name -> ID)
const OBJECT_ID_TABLE: Dictionary = {
	"GRASS": ID_GRASS,
	"TREE": ID_TREE,
	"STONE": ID_STONE
}

## 物体资源配置表 (ID -> Resource Config)
## source_id: -1 表示暂时不渲染 (用于开发阶段或无资源物体)
const OBJECT_RESOURCE_TABLE: Dictionary = {
	ID_GRASS: { "source_id": 1, "atlas": [Vector2i(6, 19),Vector2i(7,19),Vector2i(8,19),Vector2i(9,19),Vector2i(10,19),Vector2i(11,19)] },
	ID_STONE:  { "source_id": 1, "atlas": [Vector2i(12, 18),Vector2i(12,19),Vector2i(12,20)] },
	ID_TREE: { "source_id": 1, "atlas": [
	Vector2i(14, 0),Vector2i(20,0),Vector2i(26,0),
	Vector2i(14,6),Vector2i(20,6),Vector2i(26,6),
	Vector2i(14,12),Vector2i(20,12),Vector2i(26,12)] },
}

## 物体渲染层级表 (ID -> Layer Enum)
const OBJECT_RENDER_LAYER_TABLE: Dictionary = {
	ID_GRASS: Layer.DECORATION,
	ID_TREE:  Layer.DECORATION,
	ID_STONE: Layer.OBSTACLE
}

# =============================================================================
# 输入配置 (Input Configuration)
# =============================================================================

## 判断鼠标操作是"点击"还是"拖拽"的像素阈值。
## 用于: InputManager 手势消歧
const DRAG_THRESHOLD: float = 10.0

# =============================================================================
# 流水线半径配置 (Pipeline Radius - Hysteresis)
# 用于: WorldManager 区块加载/卸载判定
# =============================================================================

## Level 1: 活跃层 - 加载半径 (区块)
const ACTIVE_LOAD_RADIUS: int = 1

## Level 2: 就绪层 - 加载半径 (区块)
const READY_LOAD_RADIUS: int = 2

## Level 3: 数据层 - 加载半径 (区块)
const DATA_LOAD_RADIUS: int = 8

## 数据层更新阈值
## 当玩家距离当前数据中心超过 (DATA_LOAD_RADIUS - DATA_UPDATE_THRESHOLD_OFFSET) 时触发数据层更新
## 也就是离load区域边界切比雪夫距离为ready距离的时候进行一次load区域更新
const DATA_UPDATE_THRESHOLD_OFFSET: int = READY_LOAD_RADIUS

# =============================================================================
# 高度系统 (Elevation System)
# 用于: MapGenerator 地形生成, ChunkData 高度存储
# =============================================================================

## 最小高度层级
const MIN_ELEVATION: int = 0

## 最大高度层级
const MAX_ELEVATION: int = 7

## 默认高度层级
const DEFAULT_ELEVATION: int = 0

# =============================================================================
# 区块状态枚举 (Chunk State)
# 用于: WorldManager 流水线状态管理
# =============================================================================

enum ChunkState {
	UNLOADED = 0,  ## 未加载 (磁盘)
	DATA = 1,      ## 数据层 (内存)
	READY = 2,     ## 就绪层 (隐藏节点)
	ACTIVE = 3,    ## 活跃层 (可见节点)
}

## 渲染配置 (Rendering Configuration)
# =============================================================================

## 每帧允许用于区块渲染的最大时间 (微秒)
## 8ms = 8000us (目标 60FPS 约 16ms/帧，留一半时间给逻辑和其他渲染)
const MAX_RENDER_TIME_PER_FRAME_US: int = 2000

# =============================================================================
# 物理层级 (Physics Layers)
# 用于: 物理射线检测、碰撞分组
# =============================================================================

## 物理碰撞层位掩码
## 用于: InteractionManager 射线检测, CharacterBody2D 碰撞配置
## 层号与掩码值对应: Layer N -> 2^(N-1)
class PhysicsLayer:
	## 地面层 (Layer 1) - 地形碰撞
	const GROUND: int = 1
	## 可交互物体层 (Layer 2) - 可拾取物品、可操作物体
	const INTERACTABLES: int = 2
	## 障碍物层 (Layer 3) - 静态障碍物 (树木、墙壁)
	const OBSTACLES: int = 4
	## 实体层 (Layer 4) - 玩家、NPC
	const ENTITIES: int = 8

# =============================================================================
# 交互配置 (Interaction Configuration)
# 用于: InteractionManager 交互判定
# =============================================================================

## 交互判定距离 (瓦片数)
## 玩家所在瓦片中心九宫格范围内视为可直接交互
const INTERACTION_TILE_RANGE: float = 1.5

# =============================================================================
# 路径常量 (Path Constants)
# 用于: SaveSystem 存档管理
# =============================================================================

## 默认存档路径
# const DEFAULT_SAVE_PATH: String = "user://saves/"
const DEFAULT_SAVE_PATH: String = "D:/mygames_all_ver/mwv2.0_save/"

## 配置文件名
const CONFIG_FILE_NAME: String = "config.ini"

## Region 文件扩展名
const REGION_FILE_EXTENSION: String = ".rg"

## Region 文件夹名
const REGIONS_FOLDER_NAME: String = "regions"
