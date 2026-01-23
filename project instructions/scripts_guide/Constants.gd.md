# **脚本设计: Constants.gd**

路径: res://Scripts/Core/Constants.gd  
继承: RefCounted

## **职责**

定义全局常量、枚举、配置表。它是全项目的“字典”，所有魔术数字都应在此统一定义。

## **内容定义**

class\_name Constants

\# \--- 基础度量衡 \---  
\# 单个瓦片的像素大小 (16x16)  
\# 用于: MapUtils 坐标转换, InputManager 鼠标定位  
const TILE\_SIZE: int \= 16

\# 一个区块包含的瓦片数量 (32x32 tiles \= 512x512 pixels)  
\# 用于: ChunkData 数据结构大小, RegionDatabase 文件索引计算  
const CHUNK\_SIZE: int \= 32

\# \--- 渲染与逻辑层级 \---  
\# 用于: 区分物体在 TileMap 中的层级，以及是否具有碰撞属性  
enum Layer {  
    \# 地面层 (Z-Index: \-10, 无 Y-Sort, 无碰撞)  
    \# 存放: 泥土, 水, 悬崖, 地板  
    GROUND \= 0,  
      
    \# 装饰层 (Y-Sort Enabled, 无碰撞)  
    \# 存放: 花, 草, 地毯, 农作物  
    DECORATION \= 1,   
      
    \# 障碍层 (Y-Sort Enabled, 有碰撞)  
    \# 存放: 树木, 墙壁, 家具, 机器  
    OBSTACLE \= 2      
}

\# \--- 数据 ID 定义 (示例) \---  
\# 建议在实际开发中建立专门的 ItemID 表，这里仅作演示  
const ID\_GRASS\_PLANT \= 200  
const ID\_TREE\_OAK \= 300  
const ID\_WALL\_STONE \= 400

\# \--- 渲染映射表 \---  
\# 核心作用: 定义一个 ID 应该被渲染到哪一层。  
\# 用于: GlobalMapController 在渲染 ChunkData 时进行分发。  
\# Key: Tile ID (int) \-\> Value: Layer Enum (int)  
const OBJECT\_LAYER\_MAPPING \= {  
    ID\_GRASS\_PLANT: Layer.DECORATION,  
    ID\_TREE\_OAK:    Layer.OBSTACLE,  
    ID\_WALL\_STONE:  Layer.OBSTACLE  
}

\# \--- 输入配置 \---  
\# 判断鼠标操作是“点击”还是“拖拽”的像素阈值。  
\# 用于: InputManager 手势消歧  
const DRAG\_THRESHOLD: float \= 10.0  
