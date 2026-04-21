## EntityManager.gd
## 世界级实体管理器 - Phase 1b
## 挂载: World.tscn 的 /root/World/Managers/EntityManager（与 WorldManager 平级）
##
## 职责:
## - 启动时从 SaveSystem.load_entities() 读取所有实体记录，按 kind 查表实例化
## - 运行时新实体通过 register_new 登记（生成 uuid + spawn 节点）
## - 保存时 snapshot_all 把所有活动实体的当前状态写回 world.db
##
## 当前阶段（Phase 1b）所有实体启动时一次性全部激活，不做按距离 spawn/despawn。
## 未来若实体数量变大，可在此加 "dormant/active" 分层（参见架构文档 §存档数据分层）。
extends Node

# =============================================================================
# 实体 kind → 场景映射
# =============================================================================
## 新增实体种类时在此注册
const ENTITY_SCENES: Dictionary = {
	"HumanNPC": preload("res://Scenes/Entities/HumanNPC.tscn"),
}

# =============================================================================
# 状态
# =============================================================================

## 活动中的实体：uuid → Node
var _active: Dictionary = {}

## EntityContainer 引用（实体挂载位置）
var _container: Node = null


## WorldManager 在 _startup_world 里显式调这两个方法。
## 不用 _ready/call_deferred 自启动——避免和 WorldManager 的时序竞争。

## 由 WorldManager 在 spawn Player 后调用，完成 EntityContainer 绑定 + 从 DB 装载所有实体。
## 返回值：装载出来的实体数量（用于决定是否需要 seed 默认实体）。
func boot_from_db() -> int:
	_container = get_node_or_null("/root/World/Environment/EntityContainer")
	if _container == null:
		push_error("EntityManager: EntityContainer not found")
		return 0
	var records: Array = SaveSystem.load_entities()
	for rec in records:
		_spawn_from_record(rec)
	return records.size()


## 把所有活动实体的当前状态写回 DB（调用方：WorldManager.force_save_all）
func snapshot_all_to_db() -> void:
	var records: Array = []
	for uuid in _active.keys():
		var node = _active[uuid]
		if not is_instance_valid(node):
			continue
		if node.has_method("to_record"):
			records.append(node.to_record())
	SaveSystem.save_entities(records)


# =============================================================================
# 新实体注册
# =============================================================================

## 在指定世界坐标 spawn 一个新实体；生成 uuid，写入 DB，返回节点
func register_new(kind: String, world_pos: Vector2) -> Node:
	if not ENTITY_SCENES.has(kind):
		push_error("EntityManager: unknown kind '%s'" % kind)
		return null
	var record := {
		"uuid": _generate_uuid(kind),
		"kind": kind,
		"x": world_pos.x,
		"y": world_pos.y,
		"hp": 0,
		"max_hp": 0,
		"state_blob": "",
	}
	var node := _spawn_from_record(record)
	# 立即落盘，避免进程崩溃丢实体
	SaveSystem.save_entities([record])
	return node


## 从存档记录实例化节点并加入场景
func _spawn_from_record(record: Dictionary) -> Node:
	var kind: String = String(record.get("kind", ""))
	var scene: PackedScene = ENTITY_SCENES.get(kind)
	if scene == null:
		push_warning("EntityManager: no scene for kind '%s', skipping" % kind)
		return null

	var node = scene.instantiate()
	_container.add_child(node)
	if node.has_method("apply_record"):
		node.apply_record(record)
	else:
		# 兜底：老实体没有 apply_record，只设位置
		if node is Node2D:
			node.global_position = Vector2(record.get("x", 0.0), record.get("y", 0.0))

	# 节点进入树后，组件的 @onready 才触发；这里再恢复组件状态
	if node.has_method("restore_components_from_record"):
		# 延一帧——给 HumanNPC._ready 里 _connect_signals 跑完
		node.call_deferred("restore_components_from_record")

	var uuid: String = String(record.get("uuid", ""))
	if uuid.is_empty():
		uuid = _generate_uuid(kind)
		if "entity_uuid" in node:
			node.entity_uuid = uuid
	_active[uuid] = node
	return node


# =============================================================================
# 销毁
# =============================================================================

## 彻底移除一个实体（节点销毁 + 存档中删除）
func remove(uuid: String) -> void:
	if _active.has(uuid):
		var node = _active[uuid]
		_active.erase(uuid)
		if is_instance_valid(node):
			node.queue_free()
	SaveSystem.delete_entity(uuid)


# =============================================================================
# 工具
# =============================================================================

## uuid 格式：kind_unix_rand，避免跨实体冲突
func _generate_uuid(kind: String) -> String:
	return "%s_%d_%d" % [kind, Time.get_unix_time_from_system(), randi()]
