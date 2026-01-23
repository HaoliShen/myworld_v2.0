## DebugPanel.gd
## 调试面板 - 显示开发调试信息
## 路径: res://Scripts/UI/DebugPanel.gd
## 挂载节点: World/UI/DebugPanel
## 继承: Control
##
## 职责:
## 显示区块加载状态、内存使用等调试信息。
## 仅通过 SignalBus 获取数据，按 F3 切换显示。
class_name DebugPanel
extends Control

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

@onready var _content: VBoxContainer = $PanelContainer/VBoxContainer
@onready var _chunks_loaded_label: Label = $PanelContainer/VBoxContainer/ChunksLoadedLabel
@onready var _chunks_active_label: Label = $PanelContainer/VBoxContainer/ChunksActiveLabel
@onready var _memory_label: Label = $PanelContainer/VBoxContainer/MemoryLabel
@onready var _tile_info_label: Label = $PanelContainer/VBoxContainer/TileInfoLabel

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 已加载区块数量
var _chunks_loaded: int = 0

## 活跃区块数量
var _chunks_active: int = 0

## 选中的瓦片坐标
var _selected_tile: Vector2i = Vector2i(-1, -1)

## 选中瓦片的层级
var _selected_layer: int = 0

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_connect_signals()
	# 默认隐藏
	visible = false


func _input(event: InputEvent) -> void:
	# F3 切换调试面板
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible


func _process(_delta: float) -> void:
	if visible:
		_update_memory_display()


# =============================================================================
# 信号连接 (Signal Connections)
# =============================================================================

func _connect_signals() -> void:
	# 区块生命周期
	SignalBus.chunk_data_loaded.connect(_on_chunk_loaded)
	SignalBus.chunk_data_unloaded.connect(_on_chunk_unloaded)
	SignalBus.chunk_activated.connect(_on_chunk_activated)
	SignalBus.chunk_deactivated.connect(_on_chunk_deactivated)

	# 瓦片选择
	SignalBus.tile_selected.connect(_on_tile_selected)

	# 实体取消选中时清除瓦片信息
	SignalBus.entity_deselected.connect(_on_entity_deselected)


# =============================================================================
# 信号处理 (Signal Handlers)
# =============================================================================

func _on_chunk_loaded(_coord: Vector2i) -> void:
	_chunks_loaded += 1
	_update_chunks_display()


func _on_chunk_unloaded(_coord: Vector2i) -> void:
	_chunks_loaded = maxi(0, _chunks_loaded - 1)
	_update_chunks_display()


func _on_chunk_activated(_coord: Vector2i) -> void:
	_chunks_active += 1
	_update_chunks_display()


func _on_chunk_deactivated(_coord: Vector2i) -> void:
	_chunks_active = maxi(0, _chunks_active - 1)
	_update_chunks_display()


func _on_tile_selected(tile_coord: Vector2i, layer: int) -> void:
	_selected_tile = tile_coord
	_selected_layer = layer
	_update_tile_info_display()


func _on_entity_deselected() -> void:
	_selected_tile = Vector2i(-1, -1)
	_update_tile_info_display()


# =============================================================================
# 显示更新 (Display Updates)
# =============================================================================

func _update_chunks_display() -> void:
	if _chunks_loaded_label:
		_chunks_loaded_label.text = "Chunks Loaded: %d" % _chunks_loaded
	if _chunks_active_label:
		_chunks_active_label.text = "Chunks Active: %d" % _chunks_active


func _update_memory_display() -> void:
	if _memory_label:
		var memory_mb := OS.get_static_memory_usage() / 1048576.0
		_memory_label.text = "Memory: %.1f MB" % memory_mb


func _update_tile_info_display() -> void:
	if _tile_info_label:
		if _selected_tile != Vector2i(-1, -1):
			var layer_name := _get_layer_name(_selected_layer)
			_tile_info_label.text = "Tile: (%d, %d) [%s]" % [
				_selected_tile.x, _selected_tile.y, layer_name
			]
		else:
			_tile_info_label.text = "Tile: None"


func _get_layer_name(layer: int) -> String:
	match layer:
		_C.Layer.GROUND:
			return "Ground"
		_C.Layer.DECORATION:
			return "Decoration"
		_C.Layer.OBSTACLE:
			return "Obstacle"
		_:
			return "Unknown"
