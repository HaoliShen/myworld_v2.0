# **脚本设计: RegionDatabase.gd**

路径: res://Scripts/Components/RegionDatabase.gd  
类型: Autoload (Global Singleton)  
继承: Node  
依赖: Godot-SQLite

## **职责**

数据持久化核心 (Persistence Core)。  
负责管理海量区块数据的磁盘读写。为了解决单文件过大和文件系统碎片化的问题，采用 基于 SQLite 的区域分片存储 (Sharded SQLite Storage) 策略。

## **核心架构：区域分片 (Region Sharding)**

* **文件格式:** SQLite 数据库文件。  
* **扩展名:** **.rg** (例如 r.0.0.rg, r.-1.5.rg)。  
* **存储粒度:** 每个 .rg 文件对应一个 **Region** (包含 32 x 32 \= 1024 个 Chunk)。  
* **路径:** {SaveRoot}/{WorldName}/regions/r.{RegionX}.{RegionY}.rg。

## **内部状态**

\# 数据库连接池 (Connection Pool)  
\# Key: Vector2i (Region 坐标) \-\> Value: SQLite 实例  
\# 目的: 缓存最近访问的 Region 数据库连接，避免频繁 IO 开销。  
var \_db\_connections: Dictionary \= {}

\# 最大缓存连接数 (防止文件句柄耗尽)  
const MAX\_OPEN\_DBS: int \= 16

## **表结构设计 (Schema)**

每个 .rg 数据库包含一张核心表 chunks:

CREATE TABLE IF NOT EXISTS chunks (  
    pos\_x INTEGER,          \-- 区块在 Region 内的局部 X 坐标 (0-31)  
    pos\_y INTEGER,          \-- 区块在 Region 内的局部 Y 坐标 (0-31)  
    data BLOB,              \-- 序列化后的二进制 ChunkData  
    timestamp INTEGER,      \-- 最后修改时间 (用于版本控制或调试)  
    PRIMARY KEY (pos\_x, pos\_y)  
);

## **公共接口 (API)**

\# 初始化 (设置全局路径等，但不立即打开具体文件)  
func \_ready() \-\> void

\# \[线程安全\] 读取指定坐标的区块数据  
\# 逻辑:  
\# 1\. 计算所属 Region 坐标和局部 Chunk 坐标。  
\# 2\. 获取或打开对应的 .rg 数据库连接。  
\# 3\. 执行 SELECT data FROM chunks WHERE pos\_x=? AND pos\_y=?  
\# 4\. 如果查询结果为空，返回空 ByteArray (表示未生成)。  
\# 5\. 返回 BLOB 数据。  
func load\_chunk\_blob(coord: Vector2i) \-\> PackedByteArray 

\# \[线程安全\] 将区块数据写入数据库  
\# 逻辑:  
\# 1\. 计算 Region 和局部坐标。  
\# 2\. 获取/打开 .rg 连接。  
\# 3\. 执行 INSERT OR REPLACE INTO chunks ...  
func save\_chunk\_blob(coord: Vector2i, data: PackedByteArray) \-\> void 

\# \[维护\] 关闭所有打开的数据库连接 (用于退出游戏或切换存档)  
func close\_all\_connections() \-\> void

\# \[维护\] 垃圾回收 (定期调用)  
\# 检查连接池，关闭长时间未访问的 .rg 文件句柄，保持 open\_dbs \<= MAX\_OPEN\_DBS  
func prune\_connections() \-\> void

## **内部私有方法 (Private)**

\# 获取指定 Region 的数据库连接实例  
\# 如果池中有，直接返回；如果没有，加载文件并初始化表结构。  
func \_get\_db\_connection(region\_coord: Vector2i) \-\> SQLite

\# 计算文件路径  
func \_get\_region\_file\_path(region\_coord: Vector2i) \-\> String  
