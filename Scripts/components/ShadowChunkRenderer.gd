## ShadowChunkRenderer.gd
## 影子区块渲染器 - 多线程预计算地形连接
## 路径: res://Scripts/components/ShadowChunkRenderer.gd
## 继承: RefCounted
##
## 职责:
## 1. 在后台线程中创建影子TileMapLayer并使用BetterTerrain预计算地形连接
## 2. 管理影子图层池，复用TileMapLayer实例减少内存分配
## 3. 使用Mutex保证BetterTerrain调用的线程安全
## 4. 提供优先级任务队列，优先处理玩家视野中心的区块
class_name ShadowChunkRenderer
extends RefCounted

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

signal shadow_chunk_ready(shadow_data: Dictionary)

var _ground_tileset: TileSet
var _shadow_pool: Array[TileMapLayer] = []
var _max_pool_size: int = 10
# 使用静态互斥锁，确保所有实例和主线程共享同一个锁
# BetterTerrain 内部使用了非线程安全的 RNG 和缓存，必须全局串行化访问
static var shared_mutex: Mutex = Mutex.new()
var _active_tasks: int = 0
var _max_concurrent_tasks: int = 4
var _task_queue: Array[Dictionary] = []

func _init(ground_tileset: TileSet) -> void:
	_ground_tileset = ground_tileset
	# _betterterrain_mutex = Mutex.new() # Removed instance mutex
	print("[ShadowChunkRenderer] Initialized with max pool size: %d, max concurrent tasks: %d" % [_max_pool_size, _max_concurrent_tasks])
	
	# 预热 BetterTerrain 缓存 (必须在主线程执行)
	# 通过创建一个临时的 TileMapLayer 并调用 set_cell 来强制 BetterTerrain 构建缓存
	# 防止在子线程中首次调用时触发 add_child 等非线程安全操作
	if ground_tileset:
		var warmup_layer = TileMapLayer.new()
		warmup_layer.tile_set = ground_tileset
		# 使用一个不存在的 terrain_id 进行空调用，仅为了触发 _get_cache
		BetterTerrain.set_cell(warmup_layer, Vector2i(0,0), -1) 
		warmup_layer.free()
		print("[ShadowChunkRenderer] BetterTerrain cache warmed up")

func request_render(coord: Vector2i, chunk_data, player_chunk: Vector2i) -> void:
	var priority := _calculate_priority(coord, player_chunk)
	
	# 将任务加入队列
	_task_queue.append({
		"coord": coord,
		"data": chunk_data,
		"priority": priority
	})
	
	# 按优先级排序（距离越小优先级越高，即 priority 值越大越好？
	# _calculate_priority 返回 -distance。距离越小，-distance 越大（越接近0）。
	# sort_custom 默认升序。我们需要降序（优先级高的在前）或者 pop_back。
	# 让优先级高的排在后面，这样 pop_back 取出的就是优先级最高的。
	# 优先级 (-distance): -1 (近) > -10 (远). -1 > -10.
	# 升序: [-10, -5, -1]. pop_back() -> -1. 正确。
	_task_queue.sort_custom(func(a, b): return a.priority < b.priority)
	
	_process_queue()

func _process_queue() -> void:
	while _active_tasks < _max_concurrent_tasks and not _task_queue.is_empty():
		var task = _task_queue.pop_back()
		_active_tasks += 1
		# print("[ShadowChunkRenderer] Starting task for %s (Priority: %d)" % [task.coord, task.priority])
		WorkerThreadPool.add_task(_render_shadow_chunk.bind(task.coord, task.data, task.priority))

func _calculate_priority(coord: Vector2i, player_chunk: Vector2i) -> int:
	var distance := _MapUtils.chebyshev_distance(coord, player_chunk)
	return -distance

func _render_shadow_chunk(coord: Vector2i, chunk_data, _priority: int) -> void:
	var t_start = Time.get_ticks_usec()
	# print("[ShadowChunkRenderer] Thread %d: Starting shadow render for chunk %s" % [OS.get_thread_caller_id(), coord])
	
	var shadow_ground := _get_shadow_layer()
	if shadow_ground == null:
		push_error("[ShadowChunkRenderer] Failed to get shadow layer")
		call_deferred("_on_task_completed")
		return
	
	var base_tile := Vector2i(
		coord.x * _C.CHUNK_SIZE,
		coord.y * _C.CHUNK_SIZE
	)
	
	var terrain_cells := {}
	var all_cells: Array[Vector2i] = []
	
	for local_y in range(_C.CHUNK_SIZE):
		for local_x in range(_C.CHUNK_SIZE):
			var tile_coord := base_tile + Vector2i(local_x, local_y)
			var terrain_id: int = chunk_data.get_terrain(local_x, local_y)
			
			if not terrain_cells.has(terrain_id):
				terrain_cells[terrain_id] = []
			terrain_cells[terrain_id].append(tile_coord)
			all_cells.append(tile_coord)
	
	var t_prep = Time.get_ticks_usec()
	# print("[ShadowChunkRenderer] Thread %d: Data prep completed in %d us" % [OS.get_thread_caller_id(), t_prep - t_start])
	
	shared_mutex.lock()
	var t_lock = Time.get_ticks_usec()
	
	for t_id in terrain_cells:
		if not terrain_cells[t_id].is_empty():
			var t_before = Time.get_ticks_usec()
			BetterTerrain.set_cells(shadow_ground, terrain_cells[t_id], t_id)
			var t_after = Time.get_ticks_usec()
			# print("[ShadowChunkRenderer] Thread %d: BetterTerrain.set_cells for terrain %d (%d cells) took %d us" % [
			# 	OS.get_thread_caller_id(), t_id, terrain_cells[t_id].size(), t_after - t_before
			# ])
	
	var t_set_cells = Time.get_ticks_usec()
	
	BetterTerrain.update_terrain_cells(shadow_ground, all_cells)
	
	var t_update = Time.get_ticks_usec()
	# print("[ShadowChunkRenderer] Thread %d: BetterTerrain.update_terrain_cells (%d cells) took %d us" % [
	# 	OS.get_thread_caller_id(), all_cells.size(), t_update - t_set_cells
	# ])
	
	shared_mutex.unlock()
	var t_unlock = Time.get_ticks_usec()
	
	var shadow_data := {
		"coord": coord,
		"shadow_ground": shadow_ground,
		"object_data": chunk_data.object_map,
		"base_tile": base_tile,
		"timestamp": Time.get_ticks_msec()
	}
	
	var total_time = t_unlock - t_start
	print("[ShadowChunkRenderer] Thread %d: Shadow render completed for %s in %d us (%.2f ms)" % [
		OS.get_thread_caller_id(), coord, total_time, total_time / 1000.0
	])
	
	call_deferred("_emit_shadow_ready", shadow_data)
	call_deferred("_on_task_completed")

func _on_task_completed() -> void:
	_active_tasks -= 1
	_process_queue()

func _emit_shadow_ready(shadow_data: Dictionary) -> void:
	shadow_chunk_ready.emit(shadow_data)

func _get_shadow_layer() -> TileMapLayer:
	if not _shadow_pool.is_empty():
		var layer: TileMapLayer = _shadow_pool.pop_back()
		print("[ShadowChunkRenderer] Reusing shadow layer from pool (pool size: %d)" % _shadow_pool.size())
		return layer
	
	var layer: TileMapLayer = TileMapLayer.new()
	layer.tile_set = _ground_tileset
	layer.name = "ShadowLayer_%d" % Time.get_ticks_msec()
	print("[ShadowChunkRenderer] Created new shadow layer: %s" % layer.name)
	return layer

func return_shadow_layer(layer: TileMapLayer) -> void:
	if _shadow_pool.size() < _max_pool_size:
		layer.clear()
		_shadow_pool.append(layer)
		print("[ShadowChunkRenderer] Returned shadow layer to pool (pool size: %d)" % _shadow_pool.size())
	else:
		layer.queue_free()
		print("[ShadowChunkRenderer] Pool full, freeing shadow layer")

func get_active_task_count() -> int:
	return _active_tasks

func cleanup() -> void:
	for layer in _shadow_pool:
		layer.queue_free()
	_shadow_pool.clear()
	print("[ShadowChunkRenderer] Cleanup completed")
