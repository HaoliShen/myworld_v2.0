## StructureRegistry.gd
## 涌现结构（shelter / blacksmith / workshop 等）的运行时注册表
## 路径: res://Scripts/autoload/StructureRegistry.gd
## 类型: Autoload (Global Singleton)
##
## 设计思路（见架构文档 §3.1）：
## - 结构是"跨 chunk 的聚合实体"。tile 数据仍在各 chunk 的 object_map，
##   但"这几块 tile 构成一个 shelter"的元信息挂在 world.db.structures，全局索引。
## - 玩家放/拆一个建筑方块时，StructureRecognizer 会根据 pattern 判定，
##   调本类的 add / remove，这里负责：
##     1. 维护内存中的 uuid → record 映射
##     2. 同步写入 world.db（实时，非 force_save_all 时才写）
##     3. 通过信号广播 structure_added / structure_removed 给 UI / AI
##
## Record 字段：
##   id         : int            结构自增 id（本注册表分配）
##   kind       : String         种类名（"shelter"、将来 "blacksmith" 等）
##   tiles      : Array[Vector2i] 构成此结构的全部 tile 世界坐标
##   bbox       : Rect2i         包围盒（由 tiles 派生，快速空间查询用）
##   village_id : int            所属村庄 id（-1 = 未分配；Phase 4 起真正启用）
##   created_at : int            unix 时间戳
extends Node

signal structure_added(record: Dictionary)
signal structure_removed(id: int, record: Dictionary)

## 运行时镜像：id → record
var _by_id: Dictionary = {}
## 下一个待分配 id
var _next_id: int = 1


func _ready() -> void:
	# 切世界时由 SaveSystem 调 reload_from_current_world；这里不自己 load，
	# 避免和 world.db 打开顺序冲突
	pass


# =============================================================================
# 生命周期（SaveSystem / WorldManager 调）
# =============================================================================

## 切换/加载世界后调用：清空缓存 + 从 world.db 读回所有 structure
func reload_from_current_world() -> void:
	_by_id.clear()
	_next_id = 1
	var records: Array = SaveSystem.load_structures()
	for rec in records:
		var id := int(rec.get("id", 0))
		_by_id[id] = rec
		if id >= _next_id:
			_next_id = id + 1


## 主动清空（退出世界 / 切存档时；与 PlayerInventory.clear 类似位置调）
func clear() -> void:
	_by_id.clear()
	_next_id = 1


# =============================================================================
# 查询 API
# =============================================================================

func get_all() -> Array:
	return _by_id.values()


func get_by_id(structure_id: int) -> Dictionary:
	return _by_id.get(structure_id, {})


## 给定一个 tile 世界坐标，返回含该 tile 的第一个 structure（{} 表示没有）
func find_containing_tile(tile: Vector2i) -> Dictionary:
	for rec in _by_id.values():
		var tiles: Array = rec.get("tiles", [])
		for t in tiles:
			if t == tile:
				return rec
	return {}


## 给定一组 tile，返回所有"至少有一个 tile 落在其中"的 structure
## 用于 StructureRecognizer 在 object_removed 时找到受影响的结构
func find_structures_with_any_tile(tiles: Array) -> Array:
	var hits: Array = []
	var tile_set: Dictionary = {}
	for t in tiles:
		tile_set[t] = true
	for rec in _by_id.values():
		for t in rec.get("tiles", []):
			if tile_set.has(t):
				hits.append(rec)
				break
	return hits


# =============================================================================
# 增删
# =============================================================================

## 新建一个 structure；tiles 需至少 1 个；返回分配的 id
func add(kind: String, tiles: Array) -> int:
	if tiles.is_empty():
		push_warning("StructureRegistry.add: empty tiles, ignored")
		return -1
	var bbox := _compute_bbox(tiles)
	var record := {
		"id": _next_id,
		"kind": kind,
		"tiles": tiles.duplicate(),
		"bbox": bbox,
		"village_id": -1,
		"created_at": int(Time.get_unix_time_from_system()),
	}
	_by_id[_next_id] = record
	_next_id += 1
	# 立即写盘——结构事件比较稀疏，每次 INSERT 性能不是问题，换来崩溃保护
	SaveSystem.insert_structure(record)
	structure_added.emit(record)
	return record.id


func remove(structure_id: int) -> void:
	if not _by_id.has(structure_id):
		return
	var record: Dictionary = _by_id[structure_id]
	_by_id.erase(structure_id)
	SaveSystem.delete_structure(structure_id)
	structure_removed.emit(structure_id, record)


# =============================================================================
# 工具
# =============================================================================

func _compute_bbox(tiles: Array) -> Rect2i:
	if tiles.is_empty():
		return Rect2i()
	var first: Vector2i = tiles[0]
	var min_x := first.x
	var min_y := first.y
	var max_x := first.x
	var max_y := first.y
	for t in tiles:
		if t is Vector2i:
			min_x = min(min_x, t.x)
			min_y = min(min_y, t.y)
			max_x = max(max_x, t.x)
			max_y = max(max_y, t.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
