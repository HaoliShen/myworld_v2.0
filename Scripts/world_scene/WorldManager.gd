## WorldManager.gd
## 世界管理器 - 资源流水线总管 (Pipeline Orchestrator)
## 路径: res://Scripts/Managers/WorldManager.gd
## 挂载节点: World/Managers/WorldManager
## 继承: Node
##
## 职责:
## 它是整个开放世界的"心脏"，负责协调内存数据、磁盘存储和显存渲染之间的流动。
## 它不直接处理具体的渲染或生成算法，而是调度各组件协同工作。
extends Node

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")
const _ChunkData = preload("res://Scripts/data/ChunkData.gd")
const _ChunkLogic = preload("res://Scripts/world_scene/ChunkLogic.gd")

# =============================================================================
# 信号 (Signals)
# =============================================================================

signal world_initialized(seed: int)
signal world_ready()
signal loading_progress(current: int, total: int)

# =============================================================================
# 配置常量 (Configuration)
# =============================================================================

const RADIUS_ACTIVE: int = _C.ACTIVE_LOAD_RADIUS
const RADIUS_READY: int = _C.READY_LOAD_RADIUS
const RADIUS_DATA: int = _C.DATA_LOAD_RADIUS

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

@onready var map_generator = $MapGenerator
@onready var active_chunks_container: Node = $ActiveChunks

## GlobalMapController 引用 (环境渲染控制器)
var _map_controller = null

## SelectionManager 引用
var _selection_manager = null

# =============================================================================
# 核心属性 (Core Properties)
# =============================================================================

## 全局内存数据字典
## Key: Vector2i (区块坐标) -> Value: ChunkData (纯数据对象)
var loaded_data: Dictionary = {}

## 当前活跃的逻辑节点字典
var active_nodes: Dictionary = {}

## 已渲染的区块字典 (不再手动维护，直接查询 GlobalMapController)
# var rendered_chunks: Dictionary = {}

## 正在加载中的区块集合
var _pending_loads: Dictionary = {}

## 当前玩家所在区块
var _player_chunk: Vector2i = Vector2i.ZERO

## 数据加载区域的中心区块 (实现滞后更新)
var _data_load_center: Vector2i = Vector2i.ZERO

## 是否已初始化
var _is_initialized: bool = false

## 世界种子
var _world_seed: int = 0

## 预加载资源
const ChunkLogicScene: PackedScene = preload("res://Scenes/Main/ChunkLogic.tscn")
const PlayerScene: PackedScene = preload("res://Scenes/Entities/Player.tscn")

## 玩家节点引用
var _player: Node2D = null

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_connect_signals()
	get_tree().set_auto_accept_quit(false)
	call_deferred("_startup_world")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		force_save_all()
		get_tree().quit()

func _process(_delta: float) -> void:
	if not _is_initialized:
		return
	# 可以在这里添加定期的状态检查或垃圾回收

# =============================================================================
# 初始化 (Initialization)
# =============================================================================

func initialize_world(seed: int) -> void:
	_world_seed = seed

	# 初始化地图生成器
	if map_generator:
		map_generator.initialize(seed)

	# 获取 GlobalMapController 引用
	_map_controller = get_node_or_null("/root/World/Environment")
	if _map_controller == null:
		push_error("WorldManager: Failed to get GlobalMapController reference")
		return
	
	# 注入自身引用
	if "world_manager" in _map_controller:
		_map_controller.world_manager = self

	# 获取 SelectionManager
	_selection_manager = get_node_or_null("/root/SelectionManager")

	_is_initialized = true
	world_initialized.emit(seed)
	SignalBus.world_initialized.emit(seed)


func _connect_signals() -> void:
	SignalBus.player_chunk_changed.connect(_on_player_chunk_changed)
	SignalBus.chunk_modified.connect(_on_chunk_modified)


func _startup_world() -> void:
	# 正常流程：SaveSystem.current_world_name 由主菜单设置。
	# 直接跑 World.tscn 不再支持——应从 MainMenu.tscn 进入。
	if SaveSystem.current_world_name.is_empty():
		push_error("WorldManager: current_world_name is empty; return to main menu")
		get_tree().change_scene_to_file("res://Scenes/Main/MainMenu.tscn")
		return

	initialize_world(SaveSystem.world_seed)

	if not _is_initialized:
		push_error("WorldManager: Failed to initialize world")
		return

	# 玩家位置：从 world.ini 读（新世界为 (0,0)）
	var spawn_pos: Vector2 = SaveSystem.player_spawn_pos
	_player = PlayerScene.instantiate()
	_player.global_position = spawn_pos

	# 玩家库存：从 world.ini [inventory] 恢复
	PlayerInventory.restore(SaveSystem.load_player_inventory())

	# 结构注册表：从 world.db.structures 恢复
	StructureRegistry.reload_from_current_world()

	var entity_container := get_node_or_null("/root/World/Environment/EntityContainer")
	if entity_container == null:
		entity_container = get_tree().current_scene.get_node_or_null("%EntityContainer")

	if entity_container:
		entity_container.add_child(_player)
	else:
		_map_controller.add_child(_player)

	# -------------------------------------------------------------------------
	# 实体装载：从 world.db 恢复所有 NPC；如果是全新世界，seed 默认几个
	# -------------------------------------------------------------------------
	var entity_mgr := get_node_or_null("/root/World/Managers/EntityManager")
	if entity_mgr:
		var loaded_count: int = entity_mgr.boot_from_db()
		if loaded_count == 0:
			_seed_default_entities(entity_mgr, spawn_pos)
	else:
		push_warning("WorldManager: EntityManager not found, NPC persistence disabled")
	# -------------------------------------------------------------------------

	var interaction_manager = get_node_or_null("/root/World/Managers/InteractionManager")
	if interaction_manager:
		if _selection_manager: _selection_manager.select_unit(_player)

	var start_chunk := _MapUtils.world_to_chunk(spawn_pos)
	update_chunks(start_chunk)
	world_ready.emit()


## 全新世界的默认实体种子（只在 world.db.entities 为空时跑）
func _seed_default_entities(entity_mgr: Node, spawn_pos: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(3):
		var offset := Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		entity_mgr.register_new("HumanNPC", spawn_pos + offset)


# =============================================================================
# 核心调度逻辑 (Core Loop)
# =============================================================================

func update_chunks(player_chunk_coord: Vector2i) -> void:
	# print("[WorldManager] update_chunks: %s" % player_chunk_coord)
	_player_chunk = player_chunk_coord

	# 检查是否需要更新数据中心
	var dist_to_data_center := _MapUtils.chebyshev_distance(player_chunk_coord, _data_load_center)
	var update_threshold := _C.DATA_LOAD_RADIUS - _C.DATA_UPDATE_THRESHOLD_OFFSET
	
	if dist_to_data_center >= update_threshold:
		print("[WorldManager] Updating data center: %s -> %s" % [_data_load_center, player_chunk_coord])
		_data_load_center = player_chunk_coord

	var chunks_to_load_data: Array[Vector2i] = []
	var chunks_to_render: Array[Vector2i] = []
	var chunks_to_spawn_logic: Array[Vector2i] = []
	var chunks_to_despawn_logic: Array[Vector2i] = []
	var chunks_to_unrender: Array[Vector2i] = []
	var chunks_to_unload_data: Array[Vector2i] = []

	var active_range := _MapUtils.get_chunks_in_radius(player_chunk_coord, _C.ACTIVE_LOAD_RADIUS)
	var ready_range := _MapUtils.get_chunks_in_radius(player_chunk_coord, _C.READY_LOAD_RADIUS)
	# 数据层使用滞后的中心点 _data_load_center
	var data_range := _MapUtils.get_chunks_in_radius(_data_load_center, _C.DATA_LOAD_RADIUS)
	
	# 1. DATA (基于 _data_load_center)
	for coord in data_range:
		if not loaded_data.has(coord) and not _pending_loads.has(coord):
			chunks_to_load_data.append(coord)

	# 2. READY (基于 player_chunk_coord)
	for coord in ready_range:
		if loaded_data.has(coord):
			# 只要数据加载了，就尝试渲染。
			chunks_to_render.append(coord)

	# 3. ACTIVE (基于 player_chunk_coord)
	for coord in active_range:
		if loaded_data.has(coord) and not active_nodes.has(coord):
			chunks_to_render.append(coord)
			chunks_to_spawn_logic.append(coord)

	# 4. LEAVE ACTIVE (基于 player_chunk_coord)
	for coord in active_nodes.keys():
		var distance := _MapUtils.chebyshev_distance(coord, player_chunk_coord)
		if distance > _C.ACTIVE_LOAD_RADIUS:
			chunks_to_despawn_logic.append(coord)

	# 5. LEAVE READY (基于 player_chunk_coord)
	for coord in loaded_data.keys():
		if not active_nodes.has(coord) or chunks_to_despawn_logic.has(coord):
			var distance := _MapUtils.chebyshev_distance(coord, player_chunk_coord)
			if distance > _C.READY_LOAD_RADIUS:
				if _is_chunk_rendered(coord):
					chunks_to_unrender.append(coord)

	# 6. LEAVE DATA (基于 _data_load_center)
	for coord in loaded_data.keys():
		var distance := _MapUtils.chebyshev_distance(coord, _data_load_center)
		if distance > _C.DATA_LOAD_RADIUS:
			chunks_to_unload_data.append(coord)

	# 执行状态迁移
	for coord in chunks_to_despawn_logic: _despawn_chunk_logic(coord)#ok
	for coord in chunks_to_unrender: _unload_chunk_visuals(coord)#ok
	for coord in chunks_to_unload_data: _unload_chunk_data(coord)#ok
	for coord in chunks_to_load_data: _request_chunk_data(coord)#seems ok,no clear improvement
	
	# 渲染 (直接调用 MapController)
	for coord in chunks_to_render:
		if loaded_data.has(coord):
			_map_controller.render_chunk(coord, loaded_data[coord])
			# rendered_chunks[coord] = true # 不再需要手动维护状态
	
	for coord in chunks_to_spawn_logic:
		if loaded_data.has(coord):
			_spawn_chunk_logic(coord)
	

func force_save_all() -> void:
	# 1. Chunk 脏数据写回 .rg
	for coord in loaded_data.keys():
		var chunk = loaded_data[coord]
		if chunk and chunk.is_dirty:
			RegionDatabase.save_chunk(chunk)
	# 2. 玩家位置写回 world.ini
	if _player and is_instance_valid(_player):
		SaveSystem.save_player_position(_player.global_position)
	# 3. 玩家库存写回 world.ini [inventory]
	SaveSystem.save_player_inventory(PlayerInventory.snapshot())
	# 4. 所有活动实体快照写回 world.db.entities
	var entity_mgr := get_node_or_null("/root/World/Managers/EntityManager")
	if entity_mgr and entity_mgr.has_method("snapshot_all_to_db"):
		entity_mgr.snapshot_all_to_db()
	SignalBus.save_completed.emit()


# =============================================================================
# 数据查询与交互 (Data Query & Interaction)
# =============================================================================

func get_chunk_data_at(global_pos: Vector2):
	var chunk_coord := _MapUtils.world_to_chunk(global_pos)
	return loaded_data.get(chunk_coord)

func get_chunk_data(coord: Vector2i):
	return loaded_data.get(coord)

func set_block_at(global_pos: Vector2, layer: int, tile_id: int) -> void:
	var tile_coord := _MapUtils.world_to_tile(global_pos)
	var chunk_coord := _MapUtils.tile_to_chunk(tile_coord)
	var local_coord := _MapUtils.tile_to_local(tile_coord)

	var chunk = loaded_data.get(chunk_coord)
	if chunk == null: return

	# 修改本区块
	match layer:
		_C.Layer.GROUND:
			chunk.set_terrain(local_coord.x, local_coord.y, tile_id)
		_C.Layer.DECORATION, _C.Layer.OBSTACLE:
			chunk.set_object(local_coord.x, local_coord.y, layer, tile_id)

	# 同步视觉
	if _map_controller:
		_map_controller.set_cell_at(global_pos, layer, tile_id)

	# 信号
	SignalBus.chunk_modified.emit(chunk_coord)
	if tile_id == -1: SignalBus.object_removed.emit(tile_coord, tile_id)
	else: SignalBus.object_placed.emit(tile_coord, tile_id)
	
	# 同步邻居 Padding (仅地形层)
	if layer == _C.Layer.GROUND:
		_sync_neighbor_padding(chunk_coord, local_coord, tile_id)


func _sync_neighbor_padding(chunk_coord: Vector2i, local: Vector2i, tile_id: int) -> void:
	var x = local.x
	var y = local.y
	
	# 检查4个方向的边界
	if x == 0: _update_neighbor(chunk_coord + Vector2i.LEFT, 32, y, tile_id)
	if x == 31: _update_neighbor(chunk_coord + Vector2i.RIGHT, -1, y, tile_id)
	if y == 0: _update_neighbor(chunk_coord + Vector2i.UP, x, 32, tile_id)
	if y == 31: _update_neighbor(chunk_coord + Vector2i.DOWN, x, -1, tile_id)
	
	# 检查4个角的边界
	if x == 0 and y == 0: _update_neighbor(chunk_coord + Vector2i(-1, -1), 32, 32, tile_id)
	if x == 31 and y == 0: _update_neighbor(chunk_coord + Vector2i(1, -1), -1, 32, tile_id)
	if x == 0 and y == 31: _update_neighbor(chunk_coord + Vector2i(-1, 1), 32, -1, tile_id)
	if x == 31 and y == 31: _update_neighbor(chunk_coord + Vector2i(1, 1), -1, -1, tile_id)

func _update_neighbor(coord: Vector2i, x: int, y: int, val: int) -> void:
	var chunk = loaded_data.get(coord)
	if chunk:
		chunk.set_terrain(x, y, val)
		# 邻居数据改变，如果邻居已渲染，需要刷新以更新连接
		if _is_chunk_rendered(coord):
			_map_controller.render_chunk(coord, chunk)

func get_elevation_at(tile_coord: Vector2i) -> int:
	var chunk_coord := _MapUtils.tile_to_chunk(tile_coord)
	var chunk = get_chunk_data(chunk_coord)
	if chunk:
		var local := _MapUtils.tile_to_local(tile_coord)
		return chunk.get_elevation(local.x, local.y)
	return _C.DEFAULT_ELEVATION

func set_player_position(world_pos: Vector2) -> void:
	_player_chunk = _MapUtils.world_to_chunk(world_pos)
	update_chunks(_player_chunk)

func get_world_seed() -> int:
	return _world_seed


# =============================================================================
# 内部流程控制
# =============================================================================

func _request_chunk_data(coord: Vector2i) -> void:
	if loaded_data.has(coord) or _pending_loads.has(coord): return
	_pending_loads[coord] = true
	WorkerThreadPool.add_task(_load_chunk_task.bind(coord))


func _load_chunk_task(coord: Vector2i) -> void:
	var chunk = RegionDatabase.load_chunk(coord)
	if chunk == null:
		chunk = map_generator.generate_chunk(coord)
	call_deferred("_on_chunk_data_ready", coord, chunk)


func _on_chunk_data_ready(coord: Vector2i, data) -> void:
	_pending_loads.erase(coord)
	if data == null: return
	loaded_data[coord] = data
	SignalBus.chunk_data_loaded.emit(coord)

	var distance := _MapUtils.chebyshev_distance(coord, _player_chunk)
	if distance <= RADIUS_READY:
		# if not _is_chunk_rendered(coord):
		_map_controller.render_chunk(coord, data)
		# rendered_chunks[coord] = true


func _unload_chunk_visuals(coord: Vector2i) -> void:
	if _map_controller: _map_controller.clear_chunk(coord)
	# rendered_chunks.erase(coord)


func _spawn_chunk_logic(coord: Vector2i) -> void:
	if active_nodes.has(coord): return
	var chunk_node = ChunkLogicScene.instantiate() if ChunkLogicScene else _ChunkLogic.new()
	chunk_node.setup(coord, _map_controller)
	active_chunks_container.add_child(chunk_node)
	active_nodes[coord] = chunk_node
	SignalBus.chunk_activated.emit(coord)


func _despawn_chunk_logic(coord: Vector2i) -> void:
	if not active_nodes.has(coord): return
	var node = active_nodes[coord]
	active_nodes.erase(coord)
	if node and is_instance_valid(node): node.queue_free()
	SignalBus.chunk_deactivated.emit(coord)


func _unload_chunk_data(coord: Vector2i) -> void:
	var chunk = loaded_data.get(coord)
	if chunk == null:
		loaded_data.erase(coord)
		return
	if active_nodes.has(coord): _despawn_chunk_logic(coord)
	if _is_chunk_rendered(coord): _unload_chunk_visuals(coord)
	if chunk.is_dirty: RegionDatabase.save_chunk(chunk)
	loaded_data.erase(coord)
	SignalBus.chunk_data_unloaded.emit(coord)

func _is_chunk_rendered(coord: Vector2i) -> bool:
	if _map_controller:
		return _map_controller.active_chunks.has(coord)
	return false

# =============================================================================
# 信号处理
# =============================================================================

func _on_player_chunk_changed(_old: Vector2i, new_chunk: Vector2i) -> void:
	update_chunks(new_chunk)


func _on_chunk_modified(_coord: Vector2i) -> void:
	pass
