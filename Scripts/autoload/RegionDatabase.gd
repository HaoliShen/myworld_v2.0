## RegionDatabase.gd
## 区域数据库 - 数据持久化核心 (Persistence Core)
## 路径: res://Scripts/Components/RegionDatabase.gd
## 类型: Autoload (Global Singleton)
## 继承: Node
## 依赖: Godot-SQLite
##
## 职责:
## 负责管理海量区块数据的磁盘读写。为了解决单文件过大和文件系统碎片化的问题，
## 采用基于 SQLite 的区域分片存储 (Sharded SQLite Storage) 策略。
##
## 核心架构：区域分片 (Region Sharding)
## - 文件格式: SQLite 数据库文件
## - 扩展名: .rg (例如 r.0.0.rg, r.-1.5.rg)
## - 存储粒度: 每个 .rg 文件对应一个 Region (包含 32 x 32 = 1024 个 Chunk)
## - 路径: {SaveRoot}/{WorldName}/regions/r.{RegionX}.{RegionY}.rg
extends Node

# 预加载依赖的类 (解决 Autoload 加载顺序问题)
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")
const _ChunkData = preload("res://Scripts/data/ChunkData.gd")

# =============================================================================
# 常量 (Constants)
# =============================================================================

## 最大缓存连接数 (防止文件句柄耗尽)
const MAX_OPEN_DBS: int = 16

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 数据库连接池 (Connection Pool)
## Key: Vector2i (Region 坐标) -> Value: SQLite 实例
## 目的: 缓存最近访问的 Region 数据库连接，避免频繁 IO 开销
var _db_connections: Dictionary = {}

## 连接访问时间戳 (用于 LRU 淘汰)
## Key: Vector2i (Region 坐标) -> Value: int (ticks_msec)
var _connection_timestamps: Dictionary = {}

## 数据库互斥锁 (Mutex)
## 确保多线程访问数据库连接池时的线程安全
var _mutex: Mutex = Mutex.new()

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	# 检查 SQLite GDExtension 是否可用
	if not ClassDB.class_exists("SQLite"):
		push_warning("RegionDatabase: SQLite GDExtension not available, database features disabled")


func _exit_tree() -> void:
	close_all_connections()

# =============================================================================
# 公共接口 (API)
# =============================================================================

## [线程安全] 读取指定坐标的区块数据
func load_chunk_blob(chunk_coord: Vector2i) -> PackedByteArray:
	var region_coord := _MapUtils.chunk_to_region(chunk_coord)
	var local_coord := _MapUtils.chunk_to_region_local(chunk_coord)

	_mutex.lock()
	var db = _get_db_connection(region_coord)
	if db == null:
		print("[RegionDatabase] load_chunk_blob: DB connection failed for region %s" % region_coord)
		_mutex.unlock()
		return PackedByteArray()

	print("[RegionDatabase] load_chunk_blob: Querying chunk %s in region %s" % [local_coord, region_coord])
	db.query_with_bindings(
		"SELECT data FROM chunks WHERE pos_x = ? AND pos_y = ?",
		[local_coord.x, local_coord.y]
	)
	
	# 深拷贝结果，避免在解锁后结果被其他线程修改
	var result = db.query_result.duplicate(true)
	_mutex.unlock()

	if result.size() == 0:
		print("[RegionDatabase] load_chunk_blob: Chunk not found in DB")
		return PackedByteArray()
	
	print("[RegionDatabase] load_chunk_blob: Chunk found, returning data")
	var data = result[0]["data"]
	if data is PackedByteArray:
		return data

	return PackedByteArray()


## [线程安全] 将区块数据写入数据库
## 逻辑:
## 1. 计算 Region 和局部坐标
## 2. 获取/打开 .rg 连接
## 3. 执行 INSERT OR REPLACE INTO chunks ...
func save_chunk_blob(chunk_coord: Vector2i, data: PackedByteArray) -> void:
	var region_coord := _MapUtils.chunk_to_region(chunk_coord)
	var local_coord := _MapUtils.chunk_to_region_local(chunk_coord)

	_mutex.lock()
	var db = _get_db_connection(region_coord)
	if db == null:
		push_error("RegionDatabase: Failed to get db connection for region %s" % region_coord)
		_mutex.unlock()
		return

	print("[RegionDatabase] save_chunk_blob: Saving chunk %s to region %s" % [local_coord, region_coord])
	db.query_with_bindings(
		"INSERT OR REPLACE INTO chunks (pos_x, pos_y, data, timestamp) VALUES (?, ?, ?, ?)",
		[local_coord.x, local_coord.y, data, Time.get_ticks_msec()]
	)
	_mutex.unlock()


## [维护] 关闭所有打开的数据库连接 (用于退出游戏或切换存档)
func close_all_connections() -> void:
	for region_coord in _db_connections.keys():
		var db = _db_connections[region_coord]
		if db != null:
			db.close_db()

	_db_connections.clear()
	_connection_timestamps.clear()


## [维护] 垃圾回收 (定期调用)
## 检查连接池，关闭长时间未访问的 .rg 文件句柄，保持 open_dbs <= MAX_OPEN_DBS
func prune_connections() -> void:
	if _db_connections.size() <= MAX_OPEN_DBS:
		return

	# 按访问时间排序，关闭最老的连接
	var sorted_regions: Array = _connection_timestamps.keys()
	sorted_regions.sort_custom(func(a, b):
		return _connection_timestamps[a] < _connection_timestamps[b]
	)

	# 关闭超出限制的连接
	var to_close_count := _db_connections.size() - MAX_OPEN_DBS
	for i in range(to_close_count):
		var region_coord: Vector2i = sorted_regions[i]
		_close_connection(region_coord)


## 检查区块是否存在于数据库中
func chunk_exists(chunk_coord: Vector2i) -> bool:
	var region_coord := _MapUtils.chunk_to_region(chunk_coord)
	var local_coord := _MapUtils.chunk_to_region_local(chunk_coord)

	var db = _get_db_connection(region_coord)
	if db == null:
		return false

	db.query_with_bindings(
		"SELECT 1 FROM chunks WHERE pos_x = ? AND pos_y = ? LIMIT 1",
		[local_coord.x, local_coord.y]
	)

	return db.query_result.size() > 0


## 删除指定区块的数据
func delete_chunk(chunk_coord: Vector2i) -> void:
	var region_coord := _MapUtils.chunk_to_region(chunk_coord)
	var local_coord := _MapUtils.chunk_to_region_local(chunk_coord)

	var db = _get_db_connection(region_coord)
	if db == null:
		return

	db.query_with_bindings(
		"DELETE FROM chunks WHERE pos_x = ? AND pos_y = ?",
		[local_coord.x, local_coord.y]
	)

# =============================================================================
# 内部私有方法 (Private)
# =============================================================================

## 获取指定 Region 的数据库连接实例
## 如果池中有，直接返回；如果没有，加载文件并初始化表结构
func _get_db_connection(region_coord: Vector2i):
	# 检查连接池
	if _db_connections.has(region_coord):
		_connection_timestamps[region_coord] = Time.get_ticks_msec()
		return _db_connections[region_coord]

	# 连接池满时进行清理
	if _db_connections.size() >= MAX_OPEN_DBS:
		prune_connections()

	# 打开新连接
	var db_path := _get_region_file_path(region_coord)
	print("[RegionDatabase] _get_db_connection: Opening DB at %s" % db_path)

	# 确保目录存在
	SaveSystem.ensure_directory_exists(db_path.get_base_dir())

	# 使用 ClassDB 运行时创建 SQLite 实例 (避免解析时报错)
	if not ClassDB.class_exists("SQLite"):
		push_error("RegionDatabase: SQLite GDExtension not loaded")
		return null
	var db = ClassDB.instantiate("SQLite")
	db.path = db_path
	db.open_db()

	# 初始化表结构
	_init_schema(db)

	# 加入连接池
	_db_connections[region_coord] = db
	_connection_timestamps[region_coord] = Time.get_ticks_msec()

	return db


## 计算 Region 文件路径
func _get_region_file_path(region_coord: Vector2i) -> String:
	return SaveSystem.get_region_file_path(region_coord)


## 初始化数据库表结构
func _init_schema(db) -> void:
	db.query("""
		CREATE TABLE IF NOT EXISTS chunks (
			pos_x INTEGER,
			pos_y INTEGER,
			data BLOB,
			timestamp INTEGER,
			PRIMARY KEY (pos_x, pos_y)
		)
	""")


## 关闭单个连接
func _close_connection(region_coord: Vector2i) -> void:
	if _db_connections.has(region_coord):
		var db = _db_connections[region_coord]
		if db != null:
			db.close_db()
		_db_connections.erase(region_coord)
		_connection_timestamps.erase(region_coord)

# =============================================================================
# 便捷方法 (Convenience Methods)
# =============================================================================

## 加载区块数据并反序列化为 ChunkData 对象
## 如果数据不存在，返回 null
func load_chunk(chunk_coord: Vector2i):
	var blob := load_chunk_blob(chunk_coord)
	if blob.is_empty():
		return null
	return _ChunkData.from_bytes(chunk_coord, blob)


## 将 ChunkData 对象序列化并保存
func save_chunk(chunk) -> void:
	var blob = chunk.to_bytes()
	save_chunk_blob(chunk.coord, blob)
	chunk.clear_dirty()


## 获取当前打开的连接数量
func get_open_connection_count() -> int:
	return _db_connections.size()
