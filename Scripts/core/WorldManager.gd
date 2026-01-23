## WorldManager.gd
## 世界管理器 - 资源流水线总管 (Pipeline Orchestrator)
## 路径: res://Scripts/Managers/WorldManager.gd
## 挂载节点: World/Managers/WorldManager
## 继承: Node
## 依赖组件:
##   - WorkerThreadPool (用于分发后台 IO/生成任务)
##   - MapGenerator (子节点，地图生成组件)
##   - ChunkLogic (动态实例化的逻辑节点)
##   - GlobalMapController (环境渲染控制器)
##   - 依赖单例: SignalBus, RegionDatabase
##
## 职责:
## 它是整个开放世界的"心脏"，负责协调内存数据、磁盘存储和显存渲染之间的流动。
## 它不直接处理具体的渲染或生成算法，而是调度各组件协同工作，
## 确保玩家周围的世界始终处于正确的加载状态。
##
## 1. 数据持有 (Data Holder): 维护全局唯一的内存数据字典 loaded_data
## 2. 流水线调度 (Pipeline Scheduler): 基于玩家位置，驱动区块在 Active/Ready/Data/Disk 四种状态间流转
## 3. 渲染指令 (Rendering Command): 指挥 GlobalMapController 进行绘图和擦除
## 4. 持久化管理 (Persistence): 收集脏数据并调度后台写入任务
extends Node

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")
const _ChunkData = preload("res://Scripts/data/ChunkData.gd")
const _ChunkLogic = preload("res://Scripts/components/ChunkLogic.gd")

# =============================================================================
# 信号 (Signals)
# =============================================================================

signal world_initialized(seed: int)
signal world_ready()
signal loading_progress(current: int, total: int)

# =============================================================================
# 配置常量 (Configuration)
# =============================================================================
# 定义四级加载流水线的半径范围（单位：区块 Chunk）
# 使用迟滞区间 (Hysteresis) 防止边界抖动

## 活跃区半径 (3x3): 逻辑节点存在，视觉可见
const RADIUS_ACTIVE: int = _C.ACTIVE_LOAD_RADIUS  # 1

## 就绪区半径 (5x5): 数据已加载，TileMap 已渲染，但逻辑节点不存在
const RADIUS_READY: int = _C.READY_LOAD_RADIUS  # 2

## 数据区半径 (17x17): ChunkData 驻留内存，但没有任何视觉表现
const RADIUS_DATA: int = _C.DATA_LOAD_RADIUS  # 8

## 卸载区半径: 超出此范围的数据将被清理
const RADIUS_UNLOAD: int = _C.DATA_UNLOAD_RADIUS  # 10

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

@onready var map_generator = $MapGenerator
@onready var active_chunks_container: Node = $ActiveChunks

## GlobalMapController 引用 (环境渲染控制器)
var _map_controller = null

# =============================================================================
# 核心属性 (Core Properties)
# =============================================================================

## 全局内存数据字典
## Key: Vector2i (区块坐标) -> Value: ChunkData (纯数据对象)
var loaded_data: Dictionary = {}

## 当前活跃的逻辑节点字典
## Key: Vector2i (区块坐标) -> Value: ChunkLogic (场景节点)
var active_nodes: Dictionary = {}

## 正在加载中的区块集合 (防止重复请求)
## Key: Vector2i -> Value: bool
var _pending_loads: Dictionary = {}

## 当前玩家所在区块
var _player_chunk: Vector2i = Vector2i.ZERO

## 是否已初始化
var _is_initialized: bool = false

## 世界种子
var _world_seed: int = 0

# =============================================================================
# 预加载资源 (Preloaded Resources)
# =============================================================================

const ChunkLogicScene: PackedScene = preload("res://Scenes/Entities/ChunkLogic.tscn")
const PlayerScene: PackedScene = preload("res://Scenes/Entities/Player.tscn")

# =============================================================================
# 玩家引用 (Player Reference)
# =============================================================================

## 玩家节点引用
var _player: Node2D = null

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_connect_signals()
	_startup_world()


func _process(_delta: float) -> void:
	if not _is_initialized:
		return

	# 定期检查区块加载状态 (可以考虑降低频率或响应信号触发)
	# 当前设计: 每帧检查，实际项目中可能需要优化
	pass


# =============================================================================
# 初始化 (Initialization)
# =============================================================================

## 初始化世界
## @param seed: 世界种子
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

	_is_initialized = true
	world_initialized.emit(seed)
	SignalBus.world_initialized.emit(seed)


## 连接信号
func _connect_signals() -> void:
	SignalBus.player_chunk_changed.connect(_on_player_chunk_changed)
	SignalBus.chunk_modified.connect(_on_chunk_modified)


## 世界启动入口 (Startup Entry Point)
## 由 _ready() 调用，执行完整的游戏关卡启动流程
## 流程:
## 1. 存档上下文检查 (Debug Fallback)
## 2. 数据库初始化
## 3. 玩家生成
## 4. 启动流式加载
func _startup_world() -> void:
	# =========================================================================
	# 1. 存档上下文检查 (Debug Fallback)
	# =========================================================================
	# 检查 SaveSystem.current_world_name 是否为空
	# 如果为空（说明是直接运行场景，非主菜单进入），加载/创建调试世界
	if SaveSystem.current_world_name.is_empty():
		SaveSystem.load_or_create_debug_world()

	# =========================================================================
	# 2. 初始化世界
	# =========================================================================
	# 使用 SaveSystem 中的种子初始化世界
	initialize_world(SaveSystem.world_seed)

	if not _is_initialized:
		push_error("WorldManager: Failed to initialize world")
		return

	# =========================================================================
	# 3. 玩家生成 (Spawn Player)
	# =========================================================================
	# 简化逻辑：暂不读取数据库中的玩家旧位置，直接使用默认坐标
	var spawn_pos := Vector2(0, 0)

	# 加载并实例化 Player
	_player = PlayerScene.instantiate()
	_player.global_position = spawn_pos

	# 获取 EntityContainer 并添加玩家
	var entity_container := get_node_or_null("/root/World/Environment/EntityContainer")
	if entity_container == null:
		# 尝试使用 Unique Name 访问
		entity_container = get_tree().current_scene.get_node_or_null("%EntityContainer")

	if entity_container:
		entity_container.add_child(_player)
	else:
		push_error("WorldManager: EntityContainer not found, adding player to Environment")
		_map_controller.add_child(_player)

	# 将玩家引用传给 InteractionManager
	var interaction_manager = get_node_or_null("/root/World/Managers/InteractionManager")
	if interaction_manager:
		interaction_manager.set_player(_player)

	# =========================================================================
	# 4. 启动流式加载 (Kickoff)
	# =========================================================================
	# 计算玩家所在的区块坐标
	var start_chunk := _MapUtils.world_to_chunk(spawn_pos)

	# 强制刷新一次周围环境
	update_chunks(start_chunk)

	# 发送世界就绪信号
	world_ready.emit()


# =============================================================================
# 核心调度逻辑 (Core Loop)
# =============================================================================

## 更新区块状态 (Core Loop)
## 通常由 _process 每隔几帧调用，或者响应 SignalBus.player_entered_new_chunk 信号调用。
## 职责:
## 1. 获取玩家当前的区块坐标 (center_chunk)
## 2. 遍历以 center_chunk 为中心，RADIUS_UNLOAD 为半径的矩形区域
## 3. 对每个坐标点，计算其目标状态 (Active/Ready/Data/Disk)
## 4. 对比当前状态，执行状态迁移操作 (Load Data / Render / Spawn Logic / Unload)
## @param player_chunk_coord: 玩家当前所在的区块坐标
func update_chunks(player_chunk_coord: Vector2i) -> void:
	_player_chunk = player_chunk_coord

	# 收集需要进行状态迁移的区块
	var chunks_to_load_data: Array[Vector2i] = []
	var chunks_to_render: Array[Vector2i] = []
	var chunks_to_spawn_logic: Array[Vector2i] = []
	var chunks_to_despawn_logic: Array[Vector2i] = []
	var chunks_to_unrender: Array[Vector2i] = []
	var chunks_to_unload_data: Array[Vector2i] = []

	# 计算各层级需要的区块
	var active_range := _MapUtils.get_chunks_in_radius(player_chunk_coord, RADIUS_ACTIVE)
	var ready_range := _MapUtils.get_chunks_in_radius(player_chunk_coord, RADIUS_READY)
	var data_range := _MapUtils.get_chunks_in_radius(player_chunk_coord, RADIUS_DATA)

	# 1. 确定需要加载数据的区块 (进入 DATA 层)
	for coord in data_range:
		if not loaded_data.has(coord) and not _pending_loads.has(coord):
			chunks_to_load_data.append(coord)

	# 2. 确定需要渲染的区块 (进入 READY 层)
	for coord in ready_range:
		if loaded_data.has(coord) and not _is_chunk_rendered(coord):
			chunks_to_render.append(coord)

	# 3. 确定需要生成逻辑节点的区块 (进入 ACTIVE 层)
	for coord in active_range:
		if loaded_data.has(coord) and not active_nodes.has(coord):
			# 确保已渲染
			if not _is_chunk_rendered(coord):
				chunks_to_render.append(coord)
			chunks_to_spawn_logic.append(coord)

	# 4. 确定需要销毁逻辑节点的区块 (离开 ACTIVE 层)
	for coord in active_nodes.keys():
		var distance := _MapUtils.chebyshev_distance(coord, player_chunk_coord)
		if distance > _C.ACTIVE_UNLOAD_RADIUS:
			chunks_to_despawn_logic.append(coord)

	# 5. 确定需要卸载渲染的区块 (离开 READY 层)
	# 注意: 由于 ChunkLogic._exit_tree 会自动 clear_chunk，
	# 这里只处理没有逻辑节点但有渲染的区块
	for coord in loaded_data.keys():
		if not active_nodes.has(coord):
			var distance := _MapUtils.chebyshev_distance(coord, player_chunk_coord)
			if distance > _C.READY_UNLOAD_RADIUS:
				if _is_chunk_rendered(coord):
					chunks_to_unrender.append(coord)

	# 6. 确定需要完全卸载的区块 (离开 DATA 层)
	for coord in loaded_data.keys():
		var distance := _MapUtils.chebyshev_distance(coord, player_chunk_coord)
		if distance > RADIUS_UNLOAD:
			chunks_to_unload_data.append(coord)

	# 执行状态迁移 (按顺序)
	# 先卸载，再加载，避免内存峰值

	# 卸载逻辑节点
	for coord in chunks_to_despawn_logic:
		_despawn_chunk_logic(coord)

	# 卸载渲染
	for coord in chunks_to_unrender:
		_unload_chunk_visuals(coord)

	# 卸载数据
	for coord in chunks_to_unload_data:
		_unload_chunk_data(coord)

	# 请求加载数据 (异步)
	for coord in chunks_to_load_data:
		_request_chunk_data(coord)

	# 渲染 (需要数据已加载)
	for coord in chunks_to_render:
		if loaded_data.has(coord):
			_render_chunk_visuals(coord, loaded_data[coord])

	# 生成逻辑节点 (需要已渲染)
	for coord in chunks_to_spawn_logic:
		if loaded_data.has(coord):
			_spawn_chunk_logic(coord)


## 强制保存所有数据 (Blocking/High Priority)
## 用于: 游戏退出前、手动存档时
## 职责:
## 1. 遍历 loaded_data 中所有标记为 is_dirty 的 ChunkData
## 2. 将它们加入 RegionDatabase 的写入队列
## 3. (可选) 触发 RegionDatabase 的事务提交
## 4. 发送 SignalBus.game_save_completed 信号
func force_save_all() -> void:
	for coord in loaded_data.keys():
		var chunk = loaded_data[coord]
		if chunk and chunk.is_dirty:
			RegionDatabase.save_chunk(chunk)

	SignalBus.save_completed.emit()


# =============================================================================
# 数据查询与交互 (Data Query & Interaction)
# =============================================================================

## 获取指定世界像素坐标处的区块数据对象
## 用于: InteractionManager 查询地块属性、寻路系统获取权重等
## @param global_pos: 世界坐标
## @return: ChunkData 对象。如果该位置未加载 (处于 Data 层以外)，返回 null
func get_chunk_data_at(global_pos: Vector2):
	var chunk_coord := _MapUtils.world_to_chunk(global_pos)
	return loaded_data.get(chunk_coord)


## 获取指定区块坐标的区块数据对象
## @param coord: 区块坐标
## @return: ChunkData 对象，如果未加载返回 null
func get_chunk_data(coord: Vector2i):
	return loaded_data.get(coord)


## [核心交互] 修改世界中的一个方块
## 用于: 玩家建造、破坏、耕地等 Gameplay 逻辑
## 职责:
## 1. 将 global_pos 转换为 Chunk 坐标和内部 Tile 坐标
## 2. 获取对应的 ChunkData (需确保已加载)
## 3. 修改 ChunkData 中的数据 (set_terrain 或 set_object)，并自动标记 is_dirty = true
## 4. 调用 GlobalMapController.set_cell_at 同步更新视觉表现
## 5. 发送 SignalBus.block_changed 信号，供特效/音效系统响应
## @param global_pos: 目标位置
## @param layer: 目标层级 (Constants.Layer)
## @param tile_id: 新的图块 ID
func set_block_at(global_pos: Vector2, layer: int, tile_id: int) -> void:
	# 1. 坐标转换
	var tile_coord := _MapUtils.world_to_tile(global_pos)
	var chunk_coord := _MapUtils.tile_to_chunk(tile_coord)
	var local_coord := _MapUtils.tile_to_local(tile_coord)

	# 2. 获取 ChunkData
	var chunk = loaded_data.get(chunk_coord)
	if chunk == null:
		push_warning("WorldManager: Cannot set block at unloaded chunk %s" % chunk_coord)
		return

	# 3. 修改数据 (自动标记 is_dirty)
	match layer:
		_C.Layer.GROUND:
			chunk.set_terrain(local_coord.x, local_coord.y, tile_id)
		_C.Layer.DECORATION, _C.Layer.OBSTACLE:
			chunk.set_object(local_coord.x, local_coord.y, layer, tile_id)

	# 4. 同步更新视觉
	if _map_controller:
		_map_controller.set_cell_at(global_pos, layer, tile_id)

	# 5. 发送信号
	SignalBus.chunk_modified.emit(chunk_coord)
	if tile_id == -1:
		SignalBus.object_removed.emit(tile_coord, tile_id)
	else:
		SignalBus.object_placed.emit(tile_coord, tile_id)


## 获取指定瓦片的高度
## @param tile_coord: 全局瓦片坐标
## @return: 高度值，如果未加载返回默认高度
func get_elevation_at(tile_coord: Vector2i) -> int:
	var chunk_coord := _MapUtils.tile_to_chunk(tile_coord)
	var chunk = get_chunk_data(chunk_coord)

	if chunk:
		var local := _MapUtils.tile_to_local(tile_coord)
		return chunk.get_elevation(local.x, local.y)

	return _C.DEFAULT_ELEVATION


## 设置玩家位置 (用于初始化)
## @param world_pos: 玩家世界坐标
func set_player_position(world_pos: Vector2) -> void:
	_player_chunk = _MapUtils.world_to_chunk(world_pos)
	update_chunks(_player_chunk)


## 获取世界种子
func get_world_seed() -> int:
	return _world_seed


# =============================================================================
# 内部流程控制 (Internal / Callbacks)
# =============================================================================

## [异步回调] 请求加载区块数据
## 逻辑:
## 1. 检查 loaded_data 中是否已存在
## 2. 若不存在，向 WorkerThreadPool 提交任务：
##    - 先尝试调用 RegionDatabase.load_chunk_blob 读取存档
##    - 若存档不存在，调用 MapGenerator.generate_chunk_data 生成新数据
## 3. 标记 _pending_loads 防止重复提交
func _request_chunk_data(coord: Vector2i) -> void:
	# 防止重复请求
	if loaded_data.has(coord) or _pending_loads.has(coord):
		return

	_pending_loads[coord] = true

	# 注意: 当前使用同步加载，实际项目可使用 WorkerThreadPool 实现异步
	# 同步加载实现:
	var chunk = RegionDatabase.load_chunk(coord)

	if chunk == null:
		# 数据库中不存在，生成新数据
		chunk = map_generator.generate_chunk(coord)

	# 通过 call_deferred 确保在主线程处理
	call_deferred("_on_chunk_data_ready", coord, chunk)


## [异步回调] 区块数据加载/生成完成时调用
## 注意: 此函数需通过 call_deferred 在主线程执行
## @param coord: 区块坐标
## @param data: 准备好的 ChunkData 对象
## 职责:
## 1. 清除 _pending_loads 标记
## 2. 将 data 存入 loaded_data
## 3. 立即重新评估该区块的目标状态 (因为加载期间玩家可能已经移动)
## 4. 如果目标状态 >= Ready，调用 _render_chunk_visuals
## 5. 如果目标状态 == Active，调用 _spawn_chunk_logic
func _on_chunk_data_ready(coord: Vector2i, data) -> void:
	# 1. 清除 pending 标记
	_pending_loads.erase(coord)

	if data == null:
		push_error("WorldManager: Failed to load/generate chunk at %s" % coord)
		return

	# 2. 存入 loaded_data
	loaded_data[coord] = data

	# 3. 发送信号
	SignalBus.chunk_data_loaded.emit(coord)

	# 4. 重新评估目标状态
	var distance := _MapUtils.chebyshev_distance(coord, _player_chunk)

	if distance <= RADIUS_ACTIVE:
		# Active 状态: 渲染 + 生成逻辑
		_render_chunk_visuals(coord, data)
		_spawn_chunk_logic(coord)
	elif distance <= RADIUS_READY:
		# Ready 状态: 仅渲染
		_render_chunk_visuals(coord, data)
	# else: Data 状态，数据已在内存中，无需额外操作


## [状态迁移] 渲染区块视觉
## 职责: 调用 GlobalMapController.render_chunk
func _render_chunk_visuals(coord: Vector2i, data) -> void:
	if _map_controller == null:
		push_error("WorldManager: GlobalMapController is null")
		return

	_map_controller.render_chunk(coord, data)


## [状态迁移] 卸载区块视觉
## 职责: 调用 GlobalMapController.clear_chunk
func _unload_chunk_visuals(coord: Vector2i) -> void:
	if _map_controller == null:
		return

	_map_controller.clear_chunk(coord)


## [状态迁移] 生成逻辑节点
## 职责: 实例化 ChunkLogic，设置坐标，并添加到 active_chunks_container
func _spawn_chunk_logic(coord: Vector2i) -> void:
	if active_nodes.has(coord):
		return

	# 实例化 ChunkLogic 节点
	var chunk_node
	if ChunkLogicScene:
		chunk_node = ChunkLogicScene.instantiate()
	else:
		chunk_node = _ChunkLogic.new()

	# 设置坐标和控制器引用
	chunk_node.setup(coord, _map_controller)

	# 添加到容器
	active_chunks_container.add_child(chunk_node)
	active_nodes[coord] = chunk_node

	# 发送信号
	SignalBus.chunk_activated.emit(coord)


## [状态迁移] 销毁逻辑节点
## 职责: 在 active_nodes 中找到对应节点，调用 queue_free()
func _despawn_chunk_logic(coord: Vector2i) -> void:
	if not active_nodes.has(coord):
		return

	var node = active_nodes[coord]
	active_nodes.erase(coord)

	if node and is_instance_valid(node):
		# 注意: ChunkLogic._exit_tree 会自动调用 clear_chunk
		node.queue_free()

	# 发送信号
	SignalBus.chunk_deactivated.emit(coord)


## [状态迁移] 完全卸载数据
## 职责:
## 1. 检查 ChunkData.is_dirty
## 2. 若为脏数据，调用 RegionDatabase.save_chunk 发起后台写入
## 3. 从 loaded_data 中移除对象，允许引用计数归零回收
func _unload_chunk_data(coord: Vector2i) -> void:
	var chunk = loaded_data.get(coord)

	if chunk == null:
		loaded_data.erase(coord)
		return

	# 如果有逻辑节点，先销毁
	if active_nodes.has(coord):
		_despawn_chunk_logic(coord)

	# 如果有渲染，先清除
	if _is_chunk_rendered(coord):
		_unload_chunk_visuals(coord)

	# 保存脏数据
	if chunk.is_dirty:
		RegionDatabase.save_chunk(chunk)

	# 从缓存移除
	loaded_data.erase(coord)

	# 发送信号
	SignalBus.chunk_data_unloaded.emit(coord)


## 检查区块是否已渲染
## 简单实现: 如果有活跃节点或数据在 READY 范围内，认为已渲染
## 实际项目可能需要更精确的跟踪
func _is_chunk_rendered(coord: Vector2i) -> bool:
	# 如果有活跃节点，一定已渲染
	if active_nodes.has(coord):
		return true

	# 检查距离是否在渲染范围内
	var distance := _MapUtils.chebyshev_distance(coord, _player_chunk)
	return distance <= RADIUS_READY and loaded_data.has(coord)


# =============================================================================
# 信号处理 (Signal Handlers)
# =============================================================================

func _on_player_chunk_changed(_old_chunk: Vector2i, new_chunk: Vector2i) -> void:
	update_chunks(new_chunk)


func _on_chunk_modified(chunk_coord: Vector2i) -> void:
	# 区块被修改时，数据已经通过 set_block_at 标记为 dirty
	# 这里可以做额外处理，如触发自动保存等
	pass
