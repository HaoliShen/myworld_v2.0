# **脚本设计: WorldManager.gd**

路径: res://Scripts/Systems/WorldManager.gd  
挂载节点: World/Managers/WorldManager  
继承: Node  
依赖组件:

* Godot State Charts (用于管理整体加载状态，可选)  
* WorkerThreadPool (用于分发后台 IO/生成任务)  
* MapGenerator (子节点，地图生成组件)  
* ChunkLogic (动态实例化的逻辑节点)  
* GlobalMapController (环境渲染控制器)  
  依赖单例: SignalBus, RegionDatabase

## **职责**

资源流水线总管 (Pipeline Orchestrator)。  
它是整个开放世界的“心脏”，负责协调内存数据、磁盘存储和显存渲染之间的流动。它不直接处理具体的渲染或生成算法，而是调度各组件协同工作，确保玩家周围的世界始终处于正确的加载状态。

1. **数据持有 (Data Holder):** 维护全局唯一的内存数据字典 loaded\_data。  
2. **流水线调度 (Pipeline Scheduler):** 基于玩家位置，驱动区块在 Active/Ready/Data/Disk 四种状态间流转。  
3. **渲染指令 (Rendering Command):** 指挥 GlobalMapController 进行绘图和擦除。  
4. **持久化管理 (Persistence):** 收集脏数据并调度后台写入任务。

## **配置常量 (Configuration)**

定义四级加载流水线的半径范围（单位：区块 Chunk）。

* RADIUS\_ACTIVE \= 1: **活跃区** (3x3)。在此范围内，区块逻辑节点 (ChunkLogic) 存在，且视觉可见。  
* RADIUS\_READY \= 2: **就绪区** (5x5)。在此范围内，数据已加载，TileMap 已渲染，但逻辑节点不存在。用于缓冲渲染开销。  
* RADIUS\_DATA \= 8: **数据区** (17x17)。在此范围内，ChunkData 驻留内存，但没有任何视觉表现。用于缓冲 IO 开销。  
* RADIUS\_UNLOAD \= 10: **卸载区**。超出此范围的数据将被清理。与 RADIUS\_DATA 的差值构成**迟滞区间 (Hysteresis)**，防止边界抖动。

## **核心属性**

\# 全局内存数据字典  
\# Key: Vector2i (区块坐标) \-\> Value: ChunkData (纯数据对象)  
var loaded\_data: Dictionary \= {}

\# 当前活跃的逻辑节点字典  
\# Key: Vector2i (区块坐标) \-\> Value: ChunkLogic (场景节点)  
var active\_nodes: Dictionary \= {}

\# 正在加载中的区块集合 (防止重复请求)  
\# Key: Vector2i \-\> Value: bool  
var \_pending\_loads: Dictionary \= {}

\# 引用场景中的 ActiveChunks 容器节点  
@onready var active\_chunks\_container: Node \= $ActiveChunks

## **公共接口 (API)**

\# \-------------------------------------------------------------------------  
\# 核心调度逻辑  
\# \-------------------------------------------------------------------------

\# 更新区块状态 (Core Loop)  
\# 通常由 \_process 每隔几帧调用，或者响应 SignalBus.player\_entered\_new\_chunk 信号调用。  
\# 职责:  
\# 1\. 获取玩家当前的区块坐标 (center\_chunk)。  
\# 2\. 遍历以 center\_chunk 为中心，RADIUS\_UNLOAD 为半径的矩形区域。  
\# 3\. 对每个坐标点，计算其目标状态 (Active/Ready/Data/Disk)。  
\# 4\. 对比当前状态，执行状态迁移操作 (Load Data / Render / Spawn Logic / Unload)。  
\# @param player\_chunk\_coord: 玩家当前所在的区块坐标  
func update\_chunks(player\_chunk\_coord: Vector2i) \-\> void:  
    pass

\# 强制保存所有数据 (Blocking/High Priority)  
\# 用于: 游戏退出前、手动存档时。  
\# 职责:  
\# 1\. 遍历 loaded\_data 中所有标记为 is\_dirty 的 ChunkData。  
\# 2\. 将它们加入 RegionDatabase 的写入队列。  
\# 3\. (可选) 触发 RegionDatabase 的事务提交。  
\# 4\. 发送 SignalBus.game\_save\_completed 信号。  
func force\_save\_all() \-\> void:  
    pass

\# \-------------------------------------------------------------------------  
\# 数据查询与交互  
\# \-------------------------------------------------------------------------

\# 获取指定世界像素坐标处的区块数据对象。  
\# 用于: InteractionManager 查询地块属性、寻路系统获取权重等。  
\# @param global\_pos: 世界坐标  
\# @return: ChunkData 对象。如果该位置未加载 (处于 Data 层以外)，返回 null。  
func get\_chunk\_data\_at(global\_pos: Vector2) \-\> ChunkData:  
    pass

\# \[核心交互\] 修改世界中的一个方块。  
\# 用于: 玩家建造、破坏、耕地等 Gameplay 逻辑。  
\# 职责:  
\# 1\. 将 global\_pos 转换为 Chunk 坐标和内部 Tile 坐标。  
\# 2\. 获取对应的 ChunkData (需确保已加载)。  
\# 3\. 修改 ChunkData 中的数据 (set\_terrain 或 set\_object)，并自动标记 is\_dirty \= true。  
\# 4\. 调用 GlobalMapController.set\_cell\_at 同步更新视觉表现。  
\# 5\. 发送 SignalBus.block\_changed 信号，供特效/音效系统响应。  
\# @param global\_pos: 目标位置  
\# @param layer: 目标层级 (Constants.Layer)  
\# @param tile\_id: 新的图块 ID  
func set\_block\_at(global\_pos: Vector2, layer: int, tile\_id: int) \-\> void:  
    pass

\# \-------------------------------------------------------------------------  
\# 内部流程控制 (Internal / Callbacks)  
\# \-------------------------------------------------------------------------

\# \[异步回调\] 请求加载区块数据  
\# 逻辑:  
\# 1\. 检查 loaded\_data 中是否已存在。  
\# 2\. 若不存在，向 WorkerThreadPool 提交任务：  
\#    \- 先尝试调用 RegionDatabase.load\_chunk\_blob 读取存档。  
\#    \- 若存档不存在，调用 MapGenerator.generate\_chunk\_data 生成新数据。  
\# 3\. 标记 \_pending\_loads 防止重复提交。  
func \_request\_chunk\_data(coord: Vector2i) \-\> void:  
    pass

\# \[异步回调\] 区块数据加载/生成完成时调用  
\# 注意: 此函数需通过 call\_deferred 在主线程执行。  
\# @param coord: 区块坐标  
\# @param data: 准备好的 ChunkData 对象  
\# 职责:  
\# 1\. 清除 \_pending\_loads 标记。  
\# 2\. 将 data 存入 loaded\_data。  
\# 3\. 立即重新评估该区块的目标状态 (因为加载期间玩家可能已经移动)。  
\# 4\. 如果目标状态 \>= Ready，调用 \_render\_chunk\_visuals。  
\# 5\. 如果目标状态 \== Active，调用 \_spawn\_chunk\_logic。  
func \_on\_chunk\_data\_ready(coord: Vector2i, data: ChunkData) \-\> void:  
    pass

\# \[状态迁移\] 渲染区块视觉  
\# 职责: 调用 GlobalMapController.render\_chunk。  
func \_render\_chunk\_visuals(coord: Vector2i, data: ChunkData) \-\> void:  
    pass

\# \[状态迁移\] 卸载区块视觉  
\# 职责: 调用 GlobalMapController.clear\_chunk。  
func \_unload\_chunk\_visuals(coord: Vector2i) \-\> void:  
    pass

\# \[状态迁移\] 生成逻辑节点  
\# 职责: 实例化 ChunkLogic.tscn，设置坐标，并添加到 active\_chunks\_container。  
func \_spawn\_chunk\_logic(coord: Vector2i) \-\> void:  
    pass

\# \[状态迁移\] 销毁逻辑节点  
\# 职责: 在 active\_nodes 中找到对应节点，调用 queue\_free()。  
func \_despawn\_chunk\_logic(coord: Vector2i) \-\> void:  
    pass

\# \[状态迁移\] 完全卸载数据  
\# 职责:  
\# 1\. 检查 ChunkData.is\_dirty。  
\# 2\. 若为脏数据，调用 RegionDatabase.save\_chunk\_blob 发起后台写入。  
\# 3\. 从 loaded\_data 中移除对象，允许引用计数归零回收。  
func \_unload\_chunk\_data(coord: Vector2i) \-\> void:  
    pass  
