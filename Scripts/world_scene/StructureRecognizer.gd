## StructureRecognizer.gd
## 涌现建筑识别器 - Phase 3
## 挂载: /root/World/Managers/StructureRecognizer
##
## 设计目标：
## 玩家放置 / 拆除建筑 tile 时，扫描受影响的局部区域，按 pattern 规则判断
## 是否形成/失效一个结构。识别出的结构登记到 StructureRegistry 并写回 world.db。
##
## 当前实现的 pattern：
##   shelter —— 任意形状的地板连通块 + 外围 4 邻居必须全部是墙
##              （木墙或石墙皆可；不要求矩形，允许凹多边形）
##
## 工作流程：
## - object_placed：若是墙或地板，尝试从该 tile 及其 4 邻居出发做 flood-fill 找 shelter
## - object_removed：回扫所有已知 structure，重新验证，破坏则从注册表移除
##
## 性能：
## shelter flood-fill 目前硬限最大 MAX_FLOOD 个 tile 防止逃逸；后续扩更多 pattern
## 时可以复用同一 BFS 工具函数。
extends Node

const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

## 单个 shelter 的最大 tile 数（防止巨型开放区域被误判成 shelter）
const MAX_FLOOD: int = 256

## 合法的墙 ID 集合
const WALL_IDS: Array[int] = [_C.ID_WOOD_WALL, _C.ID_STONE_WALL]

## 合法的地板 ID（当前只有一种）
const FLOOR_IDS: Array[int] = [_C.ID_WOOD_FLOOR]


var _world_manager: Node = null


func _ready() -> void:
	# 延后一帧，让 WorldManager 先就位
	call_deferred("_post_ready")


func _post_ready() -> void:
	_world_manager = get_node_or_null("/root/World/Managers/WorldManager")
	if _world_manager == null:
		push_error("StructureRecognizer: WorldManager not found")
		return
	SignalBus.object_placed.connect(_on_object_placed)
	SignalBus.object_removed.connect(_on_object_removed)


# =============================================================================
# 事件入口
# =============================================================================

func _on_object_placed(tile: Vector2i, tile_id: int) -> void:
	if _is_wall(tile_id) or _is_floor(tile_id):
		_try_recognize_around(tile)


func _on_object_removed(tile: Vector2i, _tile_id: int) -> void:
	# 已有结构里包含该 tile 或其邻居的，重新验证
	var affected: Array = StructureRegistry.find_structures_with_any_tile(
		_neighborhood_tiles(tile)
	)
	for rec in affected:
		if not _revalidate(rec):
			StructureRegistry.remove(int(rec.id))
	# 拆除也可能"敞开"一个之前没被识别的区域——不考虑这种情况
	# （拆墙只会让结构消失，不会凭空产生新结构）


# =============================================================================
# 识别：在 seed tile 周围找 shelter
# =============================================================================

## 以 seed 及其 4 邻居为起点，尝试找出包含任一地板的连通块，判定 shelter。
## 如果找到且之前未登记，add 到 StructureRegistry。
func _try_recognize_around(seed: Vector2i) -> void:
	var candidates: Array[Vector2i] = [seed]
	candidates.append_array(_four_neighbors(seed))

	for start in candidates:
		if not _is_floor(_get_object_at(start)):
			continue
		# 已登记的 structure 跳过——免得重复识别
		if not StructureRegistry.find_containing_tile(start).is_empty():
			continue
		var floors: Array[Vector2i] = _flood_floors(start)
		if floors.is_empty():
			continue
		if _perimeter_all_walls(floors):
			StructureRegistry.add("shelter", floors)
			return  # 一次事件只识别一个新结构


## 从 start 开始 BFS，收集所有 4-连通的地板 tile。
## 超过 MAX_FLOOD 返回空（防止逃逸）。
func _flood_floors(start: Vector2i) -> Array[Vector2i]:
	var visited: Dictionary = { start: true }
	var queue: Array[Vector2i] = [start]
	var out: Array[Vector2i] = []
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		if not _is_floor(_get_object_at(t)):
			continue
		out.append(t)
		if out.size() > MAX_FLOOD:
			return []
		for n in _four_neighbors(t):
			if visited.has(n):
				continue
			visited[n] = true
			queue.append(n)
	return out


## 地板连通块 floors 的外围 4 邻居（不在 floors 中）必须全部是 wall
func _perimeter_all_walls(floors: Array[Vector2i]) -> bool:
	var floor_set: Dictionary = {}
	for t in floors:
		floor_set[t] = true
	for t in floors:
		for n in _four_neighbors(t):
			if floor_set.has(n):
				continue
			if not _is_wall(_get_object_at(n)):
				return false
	return true


## 重新验证一个已登记 structure 是否仍满足其 pattern
func _revalidate(record: Dictionary) -> bool:
	var kind := String(record.get("kind", ""))
	var tiles: Array = record.get("tiles", [])
	if tiles.is_empty():
		return false
	match kind:
		"shelter":
			# 所有原 tile 必须仍是地板
			for t in tiles:
				if not _is_floor(_get_object_at(t)):
					return false
			# 且外围仍全是墙
			return _perimeter_all_walls(tiles)
	return false


# =============================================================================
# 工具：tile 读取
# =============================================================================

## 读 tile 上的物体 id（障碍层优先，其次装饰层）；无则 -1
func _get_object_at(tile: Vector2i) -> int:
	if _world_manager == null:
		return -1
	var world_pos := _MapUtils.tile_to_world_center(tile)
	var chunk_data = _world_manager.get_chunk_data_at(world_pos)
	if chunk_data == null:
		return -1
	var local := _MapUtils.tile_to_local(tile)
	var obstacle: int = chunk_data.get_object(local.x, local.y, _C.Layer.OBSTACLE)
	if obstacle > 0:
		return obstacle
	var decoration: int = chunk_data.get_object(local.x, local.y, _C.Layer.DECORATION)
	if decoration > 0:
		return decoration
	return -1


func _is_wall(id: int) -> bool:
	return WALL_IDS.has(id)


func _is_floor(id: int) -> bool:
	return FLOOR_IDS.has(id)


func _four_neighbors(t: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(t.x + 1, t.y),
		Vector2i(t.x - 1, t.y),
		Vector2i(t.x, t.y + 1),
		Vector2i(t.x, t.y - 1),
	]


## 返回 tile 周围 3×3 的所有 tile（含自己）——给 object_removed 找受影响 structure 用
func _neighborhood_tiles(t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			out.append(Vector2i(t.x + dx, t.y + dy))
	return out
