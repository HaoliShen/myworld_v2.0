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

## 从config path加载配置文件到_config（目前强制使用了debugpath）
func _load_config() -> void:
	_config = ConfigFile.new()
	var config_path := _get_config_path()

	if FileAccess.file_exists(config_path):
		var err := _config.load(config_path)
		if err == OK:
			# 优先使用硬编码路径进行调试
			var debug_path = "D:/mygames_all_ver/mwv2.0_save"
			save_path = _config.get_value("paths", "save_path", debug_path)
			
			# 如果配置中的路径与调试路径不一致，强制更新为debugpath
			if save_path != debug_path:
				save_path = debug_path
				save_config()
				
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
	current_world_name = world_name
	world_seed = seed if seed != 0 else randi()

	if not ensure_directory_exists(get_regions_path()):
		push_error("SaveSystem: Failed to create world directory")
		return false

	# 保存世界元数据
	_save_world_metadata()
	return true


## 加载世界
func load_world(world_name: String) -> bool:
	var world_path := save_path.path_join(world_name)

	if not DirAccess.dir_exists_absolute(world_path):
		push_error("SaveSystem: World does not exist: " + world_name)
		return false

	current_world_name = world_name
	return _load_world_metadata()


## 保存世界元数据
func _save_world_metadata() -> void:
	var metadata := ConfigFile.new()
	metadata.set_value("world", "name", current_world_name)
	metadata.set_value("world", "seed", world_seed)
	metadata.set_value("world", "version", "1.0")
	metadata.set_value("world", "created_at", Time.get_datetime_string_from_system())

	var path := get_world_path().path_join("world.ini")
	metadata.save(path)


## 加载世界元数据
func _load_world_metadata() -> bool:
	var metadata := ConfigFile.new()
	var path := get_world_path().path_join("world.ini")

	if metadata.load(path) != OK:
		push_error("SaveSystem: Failed to load world metadata")
		return false

	world_seed = metadata.get_value("world", "seed", 0)
	return true


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


## 加载或创建调试世界 (Debug Fallback)
## 用于: 直接运行场景时，没有通过主菜单选择世界的情况
## 职责:
## 1. 检查是否存在名为 "DebugWorld" 的存档
## 2. 如果存在则加载；不存在则创建
## 3. 设置 current_world_name 为 "DebugWorld"
## @return: 世界名称 ("DebugWorld")
func load_or_create_debug_world() -> String:
	const DEBUG_WORLD_NAME := "DebugWorld"

	if world_exists(DEBUG_WORLD_NAME):
		# 存档存在，加载它
		if not load_world(DEBUG_WORLD_NAME):
			push_error("SaveSystem: Failed to load debug world")
	else:
		# 存档不存在，创建新的调试世界
		if not create_world(DEBUG_WORLD_NAME, 0):
			push_error("SaveSystem: Failed to create debug world")

	current_world_name = DEBUG_WORLD_NAME
	return DEBUG_WORLD_NAME
