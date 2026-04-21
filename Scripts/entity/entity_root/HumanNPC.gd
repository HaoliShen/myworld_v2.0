class_name HumanNPC
extends CharacterBody2D

# 信号
signal selection_changed(is_selected: bool)
signal movement_reached
signal interaction_stopped
signal interaction_started(target: Node)

# 组件引用 (只引用主节点)
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var animation_component: AnimationComponent = $AnimationComponent
@onready var visuals: Node2D = $Visuals
@onready var brain: NPCBrain = $NPCBrain

var _is_selected: bool = false
var _current_chunk: Vector2i = Vector2i.ZERO

## 跨会话唯一标识（Phase 1b 持久化）。由 EntityManager 在 spawn 时赋值。
var entity_uuid: String = ""

## 实体种类名（对应 EntityManager.ENTITY_SCENES 的 key）。与 to_record 的 kind 字段一致。
const ENTITY_KIND: String = "HumanNPC"

func _ready() -> void:
	_connect_signals()
	_current_chunk = MapUtils.world_to_chunk(global_position)
	_update_visuals()

func _connect_signals() -> void:
	if interaction_component:
		interaction_component.interaction_stopped.connect(func(): interaction_stopped.emit())
		interaction_component.interaction_started.connect(func(t): interaction_started.emit(t))
		
		# MovementController 通常挂载在 InteractionComponent 下，尝试获取并连接信号
		var movement = interaction_component.get_node_or_null("MovementComponent")
		if movement and movement.has_signal("destination_reached"):
			movement.destination_reached.connect(func(): movement_reached.emit())

func _physics_process(_delta: float) -> void:
	_check_chunk_update()

func _check_chunk_update() -> void:
	var new_chunk := MapUtils.world_to_chunk(global_position)
	if new_chunk != _current_chunk:
		var old_chunk = _current_chunk
		_current_chunk = new_chunk
		# Optional: Emit signal if needed

func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	selection_changed.emit(selected)

func _update_visuals() -> void:
	pass

# 供 NPCBrain 调用的接口 (模拟玩家指令)
func command_move_to(target_pos: Vector2) -> void:
	if interaction_component:
		interaction_component.move_to(target_pos)

func command_stop_move() -> void:
	if interaction_component:
		interaction_component.stop_move()

func command_interact(target: Node) -> bool:
	if interaction_component:
		return interaction_component.interact(target)
	return false


# =============================================================================
# 持久化：序列化到 Dictionary / 从 Dictionary 恢复
# =============================================================================

## 生成当前状态快照，用于 EntityManager 写入 world.db。
## state_blob 里放子类独有的状态（future: 工作目标、日程进度 等）。
func to_record() -> Dictionary:
	var hp := 0
	var max_hp := 0
	var hc = interaction_component.health_component if interaction_component else null
	if hc:
		hp = int(hc.current_health)
		max_hp = int(hc.max_health)
	return {
		"uuid": entity_uuid,
		"kind": ENTITY_KIND,
		"x": global_position.x,
		"y": global_position.y,
		"hp": hp,
		"max_hp": max_hp,
		"state_blob": "", # Phase 1b 先留空；Phase 3 起放 work_structure_id 等
	}


## 从 world.db 读出的 record 恢复状态。spawn 时调用一次（在 add_child 之后）。
func apply_record(record: Dictionary) -> void:
	entity_uuid = String(record.get("uuid", ""))
	global_position = Vector2(
		float(record.get("x", 0.0)),
		float(record.get("y", 0.0))
	)
	# 血量延迟到 _ready 里各组件初始化后再恢复；先缓存。
	# 约定：max_hp <= 0 表示记录无有效血量（新 seed 的实体走这条路），
	# 此时不覆盖组件的默认值。
	var rec_max: int = int(record.get("max_hp", 0))
	var rec_hp: int = int(record.get("hp", 0))
	if rec_max > 0:
		_pending_hp = rec_hp
		_pending_max_hp = rec_max
	else:
		_pending_hp = -1
		_pending_max_hp = -1


var _pending_hp: int = -1
var _pending_max_hp: int = -1


## 由外部（EntityManager）在节点 _ready 完成后调用，把缓存的血量写入 HealthComponent。
## 单独开一个方法是因为组件的 @onready 在节点进入树之后才生效，
## apply_record 可能在 @onready 之前调。
func restore_components_from_record() -> void:
	if _pending_max_hp <= 0:
		return
	var hc = interaction_component.health_component if interaction_component else null
	if hc:
		hc.max_health = _pending_max_hp
		hc.current_health = clampi(_pending_hp, 0, _pending_max_hp)
	_pending_hp = -1
	_pending_max_hp = -1
