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

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================
#读取出来的配置文件
var _config: ConfigFile = null

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

	if not ensure_directory_exists(get_regions_path()):
		push_error("SaveSystem: Failed to create world directory")
		return false

	_save_world_metadata()
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
	return true


## 切换/重建世界前的上下文重置。
## 职责：
## 1. 关闭 RegionDatabase 所有打开的 SQLite 连接（它们属于旧世界）
## 2. 清零 world_seed（避免继承旧世界种子）
## 注意：current_world_name 不在这里清——由调用方随即赋上新值，保证始终非空或受控
func _reset_world_context() -> void:
	if Engine.has_singleton("RegionDatabase") or get_node_or_null("/root/RegionDatabase"):
		# autoload 加载期可能还没就绪；兜底 null 检查
		var rdb := get_node_or_null("/root/RegionDatabase")
		if rdb and rdb.has_method("close_all_connections"):
			rdb.close_all_connections()
	world_seed = 0


## 保存世界元数据（首次创建时写入完整字段）
func _save_world_metadata() -> void:
	var metadata := ConfigFile.new()
	metadata.set_value("world", "name", current_world_name)
	metadata.set_value("world", "seed", world_seed)
	metadata.set_value("world", "version", "1.0")
	metadata.set_value("world", "created_at", Time.get_datetime_string_from_system())
	metadata.set_value("world", "last_played_at", "")
	metadata.set_value("world", "play_count", 0)

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


## 加载世界元数据（只读 seed 到 SaveSystem 的状态）
func _load_world_metadata() -> bool:
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")

	if metadata.load(path) != OK:
		push_error("SaveSystem: Failed to load world metadata")
		return false

	world_seed = metadata.get_value("world", "seed", 0)
	return true


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


