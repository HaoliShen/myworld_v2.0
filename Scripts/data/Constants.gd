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

## 单个瓦片的像素大小 (32x32)
## 用于: MapUtils 坐标转换, InputManager 鼠标定位
const TILE_SIZE: int = 32

## 一个区块包含的瓦片数量 (32x32 tiles = 1024x1024 pixels)
## 用于: ChunkData 数据结构大小, RegionDatabase 文件索引计算
const CHUNK_SIZE: int = 32

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
# 数据 ID 定义 (Data ID Definitions)
# =============================================================================

## 建议在实际开发中建立专门的 ItemID 表，这里仅作演示
const ID_GRASS: int = 200
const ID_TREE: int = 300
const ID_STONE: int = 400

# =============================================================================
# 渲染映射表 (Render Layer Mapping)
# =============================================================================

## 核心作用: 定义一个 ID 应该被渲染到哪一层。
## 用于: GlobalMapController 在渲染 ChunkData 时进行分发。
## Key: Tile ID (int) -> Value: Layer Enum (int)
const OBJECT_LAYER_MAPPING: Dictionary = {
	ID_GRASS: Layer.DECORATION,
	ID_TREE: Layer.DECORATION,
	ID_STONE:  Layer.OBSTACLE
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

## Level 1: 活跃层 - 加载/卸载半径 (区块)
const ACTIVE_LOAD_RADIUS: int = 1
const ACTIVE_UNLOAD_RADIUS: int = 2

## Level 2: 就绪层 - 加载/卸载半径 (区块)
const READY_LOAD_RADIUS: int = 2
const READY_UNLOAD_RADIUS: int = 3

## Level 3: 数据层 - 加载/卸载半径 (区块)
const DATA_LOAD_RADIUS: int = 8
const DATA_UNLOAD_RADIUS: int = 10

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
const DEFAULT_SAVE_PATH: String = "user://saves/"

## 配置文件名
const CONFIG_FILE_NAME: String = "config.ini"

## Region 文件扩展名
const REGION_FILE_EXTENSION: String = ".rg"

## Region 文件夹名
const REGIONS_FOLDER_NAME: String = "regions"
