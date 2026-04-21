## SaveSystem.gd
## 存档系统 - 管理存档路径、配置文件读写
## 对应文档: arch_01_managers.md
extends Node

# 预加载依赖的类 (解决 Autoload 加载顺序问题)
const _C = preload("res://Scripts/data/Constants.gd")

# =============================================================================
# 信号 (Signals)
# =============================================================================

signal config_loaded()
signal config_saved()
signal save_path_changed(new_path: String)

# =============================================================================
# 导出变量 (Exported Variables)
# =============================================================================

## 当前存档根路径
var save_path: String = _C.DEFAULT_SAVE_PATH:
	set(value):
		if save_path != value:
			save_path = value
			save_path_changed.emit(value)
	get:
		return save_path

## 当前世界名称
var current_world_name: String = ""

## 世界种子
var world_seed: int = 0

## 玩家在当前世界的出生/上次登出位置（每次 load_world 从 world.ini 读出；WorldManager 启动时用）
var player_spawn_pos: Vector2 = Vector2.ZERO

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================
#读取出来的配置文件
var _config: ConfigFile = null

## 当前世界的 SQLite 句柄（world.db），存实体/structure/village 等世界级数据
## 生命周期：load_world/create_world 打开；_reset_world_context 关闭
var _world_db = null

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_load_config()


# =============================================================================
# 配置文件操作 (Config File Operations)
# =============================================================================

## 从config path加载配置文件到_config
func _load_config() -> void:
	_config = ConfigFile.new()
	var config_path := _get_config_path()

	if FileAccess.file_exists(config_path):
		var err := _config.load(config_path)
		if err == OK:
			save_path = _config.get_value("paths", "save_path", _C.DEFAULT_SAVE_PATH)
			config_loaded.emit()
		else:
			push_warning("SaveSystem: Failed to load config file, using defaults")
			_create_default_config()
	else:
		_create_default_config()


## 创建默认配置
func _create_default_config() -> void:
	_config = ConfigFile.new()
	_config.set_value("paths", "save_path", _C.DEFAULT_SAVE_PATH)
	save_config()
	save_path = _C.DEFAULT_SAVE_PATH


## 保存配置文件
func save_config() -> void:
	if _config == null:
		_config = ConfigFile.new()

	_config.set_value("paths", "save_path", save_path)

	var err := _config.save(_get_config_path())
	if err == OK:
		config_saved.emit()
	else:
		push_error("SaveSystem: Failed to save config file")


## 获取配置文件路径
func _get_config_path() -> String:
	return "user://" + _C.CONFIG_FILE_NAME


# =============================================================================
# 路径工具 (Path Utilities)
# =============================================================================

## 获取当前世界的完整路径
func get_world_path() -> String:
	return save_path.path_join(current_world_name)


## 获取 Region 文件夹路径
func get_regions_path() -> String:
	return get_world_path().path_join(_C.REGIONS_FOLDER_NAME)


## 获取特定 Region 文件路径
func get_region_file_path(region_coord: Vector2i) -> String:
	var filename := "r.%d.%d%s" % [region_coord.x, region_coord.y, _C.REGION_FILE_EXTENSION]
	return get_regions_path().path_join(filename)


## 确保目录存在
func ensure_directory_exists(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true

	var err := DirAccess.make_dir_recursive_absolute(path)
	return err == OK


# =============================================================================
# 世界管理 (World Management)
# =============================================================================

## 创建新世界
func create_world(world_name: String, seed: int = 0) -> bool:
	# 切换世界前必须清掉 RegionDatabase 的连接池。
	# 否则新世界会继承旧世界的 SQLite 句柄（region 坐标复用），导致串档。
	_reset_world_context()

	current_world_name = world_name
	world_seed = seed if seed != 0 else randi()
	player_spawn_pos = Vector2.ZERO

	if not ensure_directory_exists(get_regions_path()):
		push_error("SaveSystem: Failed to create world directory")
		return false

	_save_world_metadata()
	_open_world_db()
	return true


## 加载世界
func load_world(world_name: String) -> bool:
	var world_path := save_path.path_join(world_name)

	if not DirAccess.dir_exists_absolute(world_path):
		push_error("SaveSystem: World does not exist: " + world_name)
		return false

	# 清旧世界上下文，避免跨存档串档（见 create_world 注释）
	_reset_world_context()

	current_world_name = world_name
	if not _load_world_metadata():
		return false
	_touch_world_metadata()
	_open_world_db()
	return true


## 切换/重建世界前的上下文重置。
## 职责：
## 1. 关闭 RegionDatabase 所有打开的 SQLite 连接（它们属于旧世界）
## 2. 关闭 world.db 句柄
## 3. 清零 world_seed / player_spawn_pos（避免继承旧世界的状态）
## 4. 清空 PlayerInventory（避免材料跨存档泄漏）
## 注意：current_world_name 不在这里清——由调用方随即赋上新值，保证始终非空或受控
func _reset_world_context() -> void:
	var rdb := get_node_or_null("/root/RegionDatabase")
	if rdb and rdb.has_method("close_all_connections"):
		rdb.close_all_connections()
	_close_world_db()
	world_seed = 0
	player_spawn_pos = Vector2.ZERO
	var inv := get_node_or_null("/root/PlayerInventory")
	if inv and inv.has_method("clear"):
		inv.clear()


# =============================================================================
# world.db (SQLite) 管理
# =============================================================================
# 存世界级涌现实体：NPC、future structures、future villages
# 和 RegionDatabase 的 .rg 是平行的——那边存 tile/terrain，这里存 "aggregated" 实体

## 打开当前世界的 world.db，初始化 schema（首次创建时）
func _open_world_db() -> void:
	if current_world_name.is_empty():
		return
	if not ClassDB.class_exists("SQLite"):
		push_error("SaveSystem: SQLite GDExtension not loaded, world.db disabled")
		return
	var db_path := get_world_path().path_join("world.db")
	ensure_directory_exists(get_world_path())
	_world_db = ClassDB.instantiate("SQLite")
	_world_db.path = db_path
	_world_db.open_db()
	_init_world_db_schema()


## 关闭 world.db 句柄（切世界 / 退出游戏时调）
func _close_world_db() -> void:
	if _world_db != null:
		_world_db.close_db()
		_world_db = null


func _init_world_db_schema() -> void:
	if _world_db == null:
		return
	# entities：Phase 1b 的核心——NPC、怪物、动物等"活体"实体
	_world_db.query("""
		CREATE TABLE IF NOT EXISTS entities (
			uuid TEXT PRIMARY KEY,
			kind TEXT NOT NULL,
			x REAL NOT NULL,
			y REAL NOT NULL,
			hp INTEGER DEFAULT 0,
			max_hp INTEGER DEFAULT 0,
			state_blob TEXT,
			updated_at INTEGER
		)
	""")
	# structures：Phase 3 预留——pattern 识别出的建筑（铁匠铺/伐木场/...）
	_world_db.query("""
		CREATE TABLE IF NOT EXISTS structures (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			kind TEXT NOT NULL,
			tiles_json TEXT NOT NULL,
			bbox_x1 INTEGER, bbox_y1 INTEGER, bbox_x2 INTEGER, bbox_y2 INTEGER,
			village_id INTEGER,
			created_at INTEGER
		)
	""")
	# villages：Phase 4 预留——structure 聚类形成的聚落
	_world_db.query("""
		CREATE TABLE IF NOT EXISTS villages (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT,
			center_x INTEGER, center_y INTEGER,
			bbox_x1 INTEGER, bbox_y1 INTEGER, bbox_x2 INTEGER, bbox_y2 INTEGER,
			created_at INTEGER
		)
	""")
	# meta：放 schema_version 等杂项
	_world_db.query("""
		CREATE TABLE IF NOT EXISTS meta (
			key TEXT PRIMARY KEY,
			value TEXT
		)
	""")
	_world_db.query_with_bindings(
		"INSERT OR IGNORE INTO meta (key, value) VALUES (?, ?)",
		["schema_version", "1"]
	)


# =============================================================================
# 实体读写 API
# =============================================================================

## 读取当前世界的所有实体记录
## 返回 Array[Dictionary]，字段见 entities 表
func load_entities() -> Array:
	var result: Array = []
	if _world_db == null:
		return result
	_world_db.query("SELECT uuid, kind, x, y, hp, max_hp, state_blob FROM entities")
	for row in _world_db.query_result:
		result.append({
			"uuid": row.uuid,
			"kind": row.kind,
			"x": row.x,
			"y": row.y,
			"hp": row.hp,
			"max_hp": row.max_hp,
			"state_blob": row.state_blob if row.state_blob else "",
		})
	return result


## 批量写入实体（INSERT OR REPLACE）。调用方负责先组装好 records。
func save_entities(records: Array) -> void:
	if _world_db == null:
		return
	var ts := Time.get_unix_time_from_system()
	for rec in records:
		_world_db.query_with_bindings(
			"INSERT OR REPLACE INTO entities (uuid, kind, x, y, hp, max_hp, state_blob, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
			[
				rec.get("uuid", ""),
				rec.get("kind", ""),
				float(rec.get("x", 0.0)),
				float(rec.get("y", 0.0)),
				int(rec.get("hp", 0)),
				int(rec.get("max_hp", 0)),
				str(rec.get("state_blob", "")),
				int(ts),
			]
		)


## 删除指定 uuid 的实体（用于实体被销毁时从存档里抹掉）
func delete_entity(uuid: String) -> void:
	if _world_db == null or uuid.is_empty():
		return
	_world_db.query_with_bindings("DELETE FROM entities WHERE uuid = ?", [uuid])


## 当前世界的实体总数（主要给"无存档时 seed 默认实体"判定用）
func entity_count() -> int:
	if _world_db == null:
		return 0
	_world_db.query("SELECT COUNT(*) AS n FROM entities")
	if _world_db.query_result.size() == 0:
		return 0
	return int(_world_db.query_result[0].n)


## 保存世界元数据（首次创建时写入完整字段）
func _save_world_metadata() -> void:
	var metadata := ConfigFile.new()
	metadata.set_value("world", "name", current_world_name)
	metadata.set_value("world", "seed", world_seed)
	metadata.set_value("world", "version", "1.0")
	metadata.set_value("world", "created_at", Time.get_datetime_string_from_system())
	metadata.set_value("world", "last_played_at", "")
	metadata.set_value("world", "play_count", 0)
	metadata.set_value("player", "x", player_spawn_pos.x)
	metadata.set_value("player", "y", player_spawn_pos.y)

	var path := get_world_path().path_join("world.ini")
	metadata.save(path)


## 更新"上次游玩"元数据（每次 load_world 成功后调用）
func _touch_world_metadata() -> void:
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")
	if metadata.load(path) != OK:
		return
	metadata.set_value("world", "last_played_at", Time.get_datetime_string_from_system())
	var count: int = metadata.get_value("world", "play_count", 0)
	metadata.set_value("world", "play_count", count + 1)
	metadata.save(path)


## 加载世界元数据（读 seed + 玩家位置到 SaveSystem 的状态）
func _load_world_metadata() -> bool:
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")

	if metadata.load(path) != OK:
		push_error("SaveSystem: Failed to load world metadata")
		return false

	world_seed = metadata.get_value("world", "seed", 0)
	var px: float = metadata.get_value("player", "x", 0.0)
	var py: float = metadata.get_value("player", "y", 0.0)
	player_spawn_pos = Vector2(px, py)
	return true


## 保存玩家位置到 world.ini（WorldManager.force_save_all 会调用这个）
func save_player_position(pos: Vector2) -> void:
	if current_world_name.is_empty():
		return
	player_spawn_pos = pos
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")
	# 保留已有字段，只覆盖玩家位置
	metadata.load(path)
	metadata.set_value("player", "x", pos.x)
	metadata.set_value("player", "y", pos.y)
	metadata.save(path)


## 保存玩家材料库存到 world.ini [inventory]
## dict: { material_key: count }
func save_player_inventory(inventory: Dictionary) -> void:
	if current_world_name.is_empty():
		return
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")
	metadata.load(path)
	# 先清掉旧的 [inventory] 段，再按当前快照重写（避免残留已归零的 key）
	if metadata.has_section("inventory"):
		metadata.erase_section("inventory")
	for key in inventory:
		var n := int(inventory[key])
		if n > 0:
			metadata.set_value("inventory", String(key), n)
	metadata.save(path)


## 从 world.ini [inventory] 读回玩家材料（WorldManager 启动时调）
## 返回 Dictionary[String, int]；空世界返回空 dict
func load_player_inventory() -> Dictionary:
	var out: Dictionary = {}
	if current_world_name.is_empty():
		return out
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")
	if metadata.load(path) != OK:
		return out
	if not metadata.has_section("inventory"):
		return out
	for key in metadata.get_section_keys("inventory"):
		out[String(key)] = int(metadata.get_value("inventory", key, 0))
	return out


## 获取指定世界的完整元数据字典（主菜单详情面板使用）
## 返回: { name, seed, version, created_at, last_played_at, play_count, exists }
## 如果 world.ini 读取失败，返回 { exists: false }
func get_world_metadata(world_name: String) -> Dictionary:
	var metadata := ConfigFile.new()
	var path := save_path.path_join(world_name).path_join("world.ini")
	if metadata.load(path) != OK:
		return { "exists": false }
	return {
		"exists": true,
		"name": metadata.get_value("world", "name", world_name),
		"seed": metadata.get_value("world", "seed", 0),
		"version": metadata.get_value("world", "version", "unknown"),
		"created_at": metadata.get_value("world", "created_at", ""),
		"last_played_at": metadata.get_value("world", "last_played_at", ""),
		"play_count": metadata.get_value("world", "play_count", 0),
	}


## 删除整个世界目录（含所有 region 文件）
func delete_world(world_name: String) -> bool:
	var world_path := save_path.path_join(world_name)
	if not DirAccess.dir_exists_absolute(world_path):
		return false

	# 如果正在删除当前活跃世界（理论上不会发生在正常流程里——暂停菜单里没"删档"），
	# 需要先释放 RegionDatabase 对这些文件的句柄，否则 Windows 下文件删不掉。
	if current_world_name == world_name:
		_reset_world_context()
		current_world_name = ""

	var err := _rm_recursive(world_path)
	if err != OK:
		push_error("SaveSystem: Failed to delete world %s (err %d)" % [world_name, err])
		return false
	return true


## 递归删除目录（Godot 的 DirAccess.remove 不能删非空目录）
func _rm_recursive(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return ERR_CANT_OPEN
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var child := path.path_join(entry)
		if dir.current_is_dir():
			var sub_err := _rm_recursive(child)
			if sub_err != OK:
				dir.list_dir_end()
				return sub_err
		else:
			var rm_err := DirAccess.remove_absolute(child)
			if rm_err != OK:
				dir.list_dir_end()
				return rm_err
		entry = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path)


## 获取所有世界列表
func get_world_list() -> Array[String]:
	var worlds: Array[String] = []

	if not DirAccess.dir_exists_absolute(save_path):
		return worlds

	var dir := DirAccess.open(save_path)
	if dir == null:
		return worlds

	dir.list_dir_begin()
	var dir_name := dir.get_next()

	while dir_name != "":
		if dir.current_is_dir() and not dir_name.begins_with("."):
			var world_ini := save_path.path_join(dir_name).path_join("world.ini")
			if FileAccess.file_exists(world_ini):
				worlds.append(dir_name)
		dir_name = dir.get_next()

	dir.list_dir_end()
	return worlds


## 检查指定世界是否存在
func world_exists(world_name: String) -> bool:
	var world_ini := save_path.path_join(world_name).path_join("world.ini")
	return FileAccess.file_exists(world_ini)


