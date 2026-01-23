# **脚本设计: GlobalMapController.gd**

路径: res://Scripts/Systems/GlobalMapController.gd  
挂载节点: World/Environment  
继承: Node2D  
依赖: Better Terrain (插件)

## **职责**

全局渲染画布 (Global Rendering Canvas)。  
它是连接数据 (ChunkData) 与视觉 (TileMapLayer) 的唯一桥梁。它不存储任何游戏逻辑状态，只负责调用 Better Terrain 的 API 进行高效的“画”和“擦”。

## **节点引用**

必须获取以下子节点的引用，以便将不同的数据分发到正确的层级：

* **$GroundLayer**: 基础地形层 (Z-Index: \-10)。用于绘制地面、水体和悬崖。  
* **$DecorationLayer**: 装饰层 (Y-Sort Enabled)。用于绘制草丛、花朵、地毯。  
* **$ObstacleLayer**: 障碍层 (Y-Sort Enabled)。用于绘制树木、墙壁、建筑。

## **公共接口 (API)**

class\_name GlobalMapController

\# \-------------------------------------------------------------------------  
\# 批量操作 (Batch Operations) \- 用于流式加载  
\# \-------------------------------------------------------------------------

\# 渲染指定区块的数据到全局地图。  
\# 职责:  
\# 1\. 计算该区块在全局 TileMap 中的坐标偏移。  
\# 2\. 读取 ChunkData 中的地形、高度和物体数据。  
\# 3\. 将逻辑 ID (ChunkData) 映射为 视觉 ID (TileSet)。  
\# 4\. 调用 BetterTerrain 的批量设置接口 (set\_cells) 将数据填充到对应的 TileMapLayer。  
\# 5\. 触发 BetterTerrain 的地形连接更新 (update\_terrain\_cells) 以处理边缘自动拼接。  
\# @param coord: 区块坐标  
\# @param data: 包含该区块所有信息的纯数据对象  
func render\_chunk(coord: Vector2i, data: ChunkData) \-\> void:  
    pass

\# 清除指定区块的渲染内容。  
\# 职责:  
\# 1\. 计算该区块在全局 TileMap 中的矩形范围。  
\# 2\. 将该范围内的三层 TileMapLayer 数据全部置空 (Set to \-1/Empty)。  
\# 3\. 触发 BetterTerrain 更新，确保移除后邻接区块的边缘纹理正确闭合。  
\# @param coord: 区块坐标  
func clear\_chunk(coord: Vector2i) \-\> void:  
    pass

\# \-------------------------------------------------------------------------  
\# 单点操作 (Single Operations) \- 用于玩家交互  
\# \-------------------------------------------------------------------------

\# 单点更新视觉，用于玩家实时交互 (建造/破坏)。  
\# 职责:  
\# 1\. 将世界像素坐标转换为 TileMap 网格坐标。  
\# 2\. 根据 layer\_enum 选择对应的 TileMapLayer。  
\# 3\. 调用 BetterTerrain 设置单个单元格并更新周边连接。  
\# @param global\_pos: 发生改变的世界坐标  
\# @param layer\_enum: 目标层级 (Constants.Layer)  
\# @param tile\_id: 新的图块 ID (-1 表示移除)  
func set\_cell\_at(global\_pos: Vector2, layer\_enum: int, tile\_id: int) \-\> void:  
    pass

\# \-------------------------------------------------------------------------  
\# 内部辅助逻辑 (Internal Helpers)  
\# \-------------------------------------------------------------------------

\# 这是一个私有辅助函数的建议，具体实现由开发者决定。（先实现）  
\# 职责: 将 ChunkData 中存储的“基础地形类型”和“高度值”组合映射为 TileSet 中实际定义的 Terrain ID。  
\# 例如: 类型=草(1), 高度=2 \-\> 映射为 TileSet ID 102。（这里数值仅展示，实际从constants中提取）  
func \_get\_mapped\_terrain\_id(base\_type: int, elevation: int) \-\> int:  
    return \-1  
