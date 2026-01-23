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

@onready var _position_label: Label = $MarginContainer/VBoxContainer/PositionLabel
@onready var _chunk_label: Label = $MarginContainer/VBoxContainer/ChunkLabel
@onready var _mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var _fps_label: Label = $MarginContainer/VBoxContainer/FPSLabel

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
