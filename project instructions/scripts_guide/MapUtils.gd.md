# **脚本设计: MapUtils.gd**

路径: res://Scripts/Utils/MapUtils.gd  
继承: RefCounted (作为静态库使用)

## **职责**

提供纯数学计算与坐标转换服务。它是连接\*\*“屏幕像素”**、**“内存数据”**和**“硬盘文件”\*\*三者的桥梁。本脚本不存储任何状态，所有函数均为 static。

## **核心概念：四级坐标系**

为了管理超大规模地图，系统采用了分层坐标系。MapUtils 负责在这些层级间进行换算。

1. **世界像素坐标 (World Position):** Vector2(float)  
   * Godot 引擎最底层的坐标，用于 position、物理碰撞和鼠标点击。  
   * 例如: (12345.5, \-9876.0)  
2. **瓦片坐标 (Tile Coordinate):** Vector2i  
   * 网格坐标。公式: floor(WorldPos / TILE\_SIZE)。  
   * 例如: (771, \-617)  
3. **区块坐标 (Chunk Coordinate):** Vector2i  
   * 内存加载/渲染单位。公式: floor(TileCoord / CHUNK\_SIZE)。  
   * 例如: (24, \-19)  
4. **区域坐标 (Region Coordinate):** Vector2i  
   * 文件存储单位。公式: floor(ChunkCoord / REGION\_SIZE)。  
   * 例如: (0, 0\)

## **公共接口 (API)**

class\_name MapUtils

\# \--- 坐标转换函数 \---

\# 将世界像素坐标转换为其所属的区块坐标。  
\# 算法: floor(pos / (TILE\_SIZE \* CHUNK\_SIZE))  
\# 输入: Vector2(1000, 1000\) \-\> 输出: Vector2i(1, 1\) (假设 Chunk宽512px)  
\# 场景: WorldManager 判断玩家跨越区块；InputManager 确定点击了哪个区块的数据。  
static func world\_to\_chunk(pos: Vector2) \-\> Vector2i

\# 将世界像素坐标转换为全局瓦片坐标。  
\# 算法: floor(pos / TILE\_SIZE)  
static func world\_to\_tile(pos: Vector2) \-\> Vector2i

\# 将区块坐标转换为其所属的区域文件坐标。  
\# 算法: floor(coord / REGION\_SIZE)  
\# 注意: 必须使用向下取整除法 (floori)，确保负数坐标处理的连续性 (例如 \-1 属于 Region \-1 而非 0)。  
\# 场景: RegionDatabase 决定读写哪个 .data 文件。  
static func chunk\_to\_region(coord: Vector2i) \-\> Vector2i

\# 计算区块在区域文件中的局部索引 (0 \~ 1023)。  
\# 算法: local\_x \= posmod(chunk\_x, REGION\_SIZE) ... return y \* width \+ x  
\# 场景: RegionDatabase 在 Header 中查找偏移量。  
static func get\_chunk\_index\_in\_region(chunk\_coord: Vector2i) \-\> int

\# \--- 数据压缩函数 \---

\# 将区块内的局部坐标 (x, y) 和层级 (layer) 压缩为一个整数。  
\# 目的: 作为 ChunkData 中稀疏字典 (object\_map) 的 Key，减少内存占用并提升查找速度。  
\# 原理 (位运算):   
\#   x (0-31) 占 5 bit  
\#   y (0-31) 占 5 bit  
\#   layer (0-15) 占 4 bit  
\#   Result \= (x \<\< 9\) | (y \<\< 4\) | layer  
static func pack\_coord(x: int, y: int, layer: int) \-\> int

\# 解压整数，还原出 x, y 和 layer。  
\# 返回: Vector3i(x, y, layer)  
\# 场景: GlobalMapController 遍历数据进行渲染时。  
static func unpack\_coord(packed: int) \-\> Vector3i  
