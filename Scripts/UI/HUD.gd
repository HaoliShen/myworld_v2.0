## HUD.gd
## 抬头显示 - 显示玩家基本信息
## 路径: res://Scripts/UI/HUD.gd
## 挂载节点: World/UI/HUD
## 继承: Control
##
## 职责:
## 显示玩家坐标、当前区块、交互模式等基本信息。
## 仅通过 SignalBus 获取数据，不直接引用游戏逻辑节点。
class_name HUD
extends Control

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

const _C = preload("res://Scripts/data/Constants.gd")

@onready var _position_label: Label = $MarginContainer/VBoxContainer/PositionLabel
@onready var _chunk_label: Label = $MarginContainer/VBoxContainer/ChunkLabel
@onready var _mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var _fps_label: Label = $MarginContainer/VBoxContainer/FPSLabel
@onready var _materials_label: Label = $MarginContainer/VBoxContainer/MaterialsLabel
@onready var _build_hint_label: Label = $BuildHintLabel
@onready var _dev_badge: Label = $DevModeBadge

## 当前 hint 的 Tween，新消息进来先把旧的 kill 掉避免叠加
var _hint_tween: Tween = null

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 当前玩家位置
var _player_position: Vector2 = Vector2.ZERO

## 当前玩家区块
var _player_chunk: Vector2i = Vector2i.ZERO

## 当前交互模式
var _current_mode: String = "Normal"

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_connect_signals()
	_update_display()


func _process(_delta: float) -> void:
	# 更新 FPS 显示
	if _fps_label:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


# =============================================================================
# 信号连接 (Signal Connections)
# =============================================================================

func _connect_signals() -> void:
	# 玩家位置更新
	SignalBus.player_position_updated.connect(_on_player_position_updated)

	# 玩家区块变化
	SignalBus.player_chunk_changed.connect(_on_player_chunk_changed)

	# 监听模式变化 (通过 UI 信号)
	SignalBus.ui_mode_changed.connect(_on_mode_changed)

	# 材料库存变化（Phase 2a）
	PlayerInventory.inventory_changed.connect(_on_inventory_changed)
	# 进入场景时先画一次当前库存
	_on_inventory_changed(PlayerInventory.snapshot())

	# 建造失败浮动提示
	SignalBus.build_failed.connect(_on_build_failed)

	# 开发模式徽标
	DevMode.dev_mode_changed.connect(_on_dev_mode_changed)
	_on_dev_mode_changed(DevMode.is_enabled)

	# 结构识别事件
	StructureRegistry.structure_added.connect(_on_structure_added)
	StructureRegistry.structure_removed.connect(_on_structure_removed)


# =============================================================================
# 信号处理 (Signal Handlers)
# =============================================================================

func _on_player_position_updated(world_position: Vector2) -> void:
	_player_position = world_position
	_update_position_display()


func _on_player_chunk_changed(_old_chunk: Vector2i, new_chunk: Vector2i) -> void:
	_player_chunk = new_chunk
	_update_chunk_display()


func _on_mode_changed(mode_name: String) -> void:
	_current_mode = mode_name
	_update_mode_display()


# =============================================================================
# 显示更新 (Display Updates)
# =============================================================================

func _update_display() -> void:
	_update_position_display()
	_update_chunk_display()
	_update_mode_display()


func _update_position_display() -> void:
	if _position_label:
		_position_label.text = "Pos: (%.0f, %.0f)" % [_player_position.x, _player_position.y]


func _update_chunk_display() -> void:
	if _chunk_label:
		_chunk_label.text = "Chunk: (%d, %d)" % [_player_chunk.x, _player_chunk.y]


func _update_mode_display() -> void:
	if _mode_label:
		_mode_label.text = "Mode: %s" % _current_mode


func _on_inventory_changed(inventory: Dictionary) -> void:
	if _materials_label == null:
		return
	if inventory.is_empty():
		_materials_label.text = "材料: —"
		return
	# 按 MATERIAL_DISPLAY_NAMES 的顺序显示，未命名的 key 直接原样
	var parts: Array[String] = []
	for key in _C.MATERIAL_DISPLAY_NAMES.keys():
		if inventory.has(key):
			var disp: String = _C.MATERIAL_DISPLAY_NAMES[key]
			parts.append("%s %d" % [disp, int(inventory[key])])
	# 兜底：出现未预定义的材料键也列出来
	for key in inventory.keys():
		if not _C.MATERIAL_DISPLAY_NAMES.has(key):
			parts.append("%s %d" % [String(key), int(inventory[key])])
	# 注意括号：三元优先级让 "材料: " + X if ... else Y 会被解释为 "材料: " + (X if ... else Y)
	# 后者在 parts 为空时产生 "材料: 材料: —"。改写清楚：
	if parts.is_empty():
		_materials_label.text = "材料: —"
	else:
		_materials_label.text = "材料: " + "  ".join(parts)


func _on_dev_mode_changed(enabled: bool) -> void:
	if _dev_badge:
		_dev_badge.visible = enabled


## 建造失败提示：屏幕下方浮出一条红色文字，0.3s 淡入 → 停 1.5s → 0.5s 淡出
func _on_build_failed(reason: String) -> void:
	_show_hint(reason, Color(1.0, 0.5, 0.5))


## 结构识别/解散使用同一条浮动提示通道，颜色区分
func _on_structure_added(record: Dictionary) -> void:
	var kind := String(record.get("kind", "structure"))
	_show_hint("形成了一个 %s" % _kind_display_name(kind), Color(0.5, 1.0, 0.6))


func _on_structure_removed(_id: int, record: Dictionary) -> void:
	var kind := String(record.get("kind", "structure"))
	_show_hint("一个 %s 被破坏了" % _kind_display_name(kind), Color(1.0, 0.8, 0.4))


## 结构 kind 的中文显示名
func _kind_display_name(kind: String) -> String:
	const NAMES := {
		"shelter": "庇护所",
	}
	return NAMES.get(kind, kind)


## 屏幕下方浮出一条提示文字，供 build_failed / structure_added / structure_removed 复用
func _show_hint(text: String, color: Color) -> void:
	if _build_hint_label == null:
		return
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_build_hint_label.text = text
	_build_hint_label.modulate = Color(color.r, color.g, color.b, 0.0)
	_hint_tween = create_tween()
	_hint_tween.tween_property(_build_hint_label, "modulate:a", 1.0, 0.15)
	_hint_tween.tween_interval(1.5)
	_hint_tween.tween_property(_build_hint_label, "modulate:a", 0.0, 0.4)
