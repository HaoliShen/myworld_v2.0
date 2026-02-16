## TileInfoPanel.gd
## 选中信息面板 - 显示选中实体或瓦片的详细信息
## 路径: res://Scripts/UI/TileInfoPanel.gd
## 挂载节点: World/UI/TileInfoPanel
## 继承: Control
##
## 职责:
## 当玩家选中实体或瓦片时，显示相关信息。
## 仅通过 SignalBus 获取选中事件。
class_name TileInfoPanel
extends Control

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

@onready var _panel: PanelContainer = $PanelContainer
@onready var _title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var _info_label: Label = $PanelContainer/MarginContainer/VBoxContainer/InfoLabel
@onready var _coords_label: Label = $PanelContainer/MarginContainer/VBoxContainer/CoordsLabel
@onready var _ground_id_label: Label = $PanelContainer/MarginContainer/VBoxContainer/GroundIdLabel

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

var _world_manager = null

## 当前选中类型
enum SelectionType { NONE, ENTITY, TILE }
var _selection_type: SelectionType = SelectionType.NONE

## 选中的实体名称
var _selected_entity_name: String = ""

## 选中的瓦片坐标
var _selected_tile_coord: Vector2i = Vector2i.ZERO

## 选中的层级
var _selected_layer: int = 0

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_world_manager = get_node_or_null("/root/World/Managers/WorldManager")
	#_selection_manager = get_node_or_null("/root/SelectionManager")
	_connect_signals()
	_hide_panel()


# =============================================================================
# 信号连接 (Signal Connections)
# =============================================================================

func _connect_signals() -> void:
	# 实体选中 (SelectionManager)
	if SelectionManager:
		SelectionManager.selection_changed.connect(_on_selection_changed)

	# 瓦片选中 (SignalBus)
	SignalBus.tile_selected.connect(_on_tile_selected)


# =============================================================================
# 信号处理 (Signal Handlers)
# =============================================================================

func _on_selection_changed(selected_units: Array[Node]) -> void:
	if selected_units.is_empty():
		# 如果之前是实体选中模式，则隐藏面板
		if _selection_type == SelectionType.ENTITY:
			_on_entity_deselected()
		return

	_selection_type = SelectionType.ENTITY
	
	if selected_units.size() == 1:
		_on_entity_selected(selected_units[0])
	else:
		_show_multiple_selection_info(selected_units)


func _on_entity_selected(entity: Node) -> void:
	_selection_type = SelectionType.ENTITY

	if entity:
		_selected_entity_name = entity.name
		# 尝试获取实体位置
		if entity is Node2D:
			var pos: Vector2 = entity.global_position
			_selected_tile_coord = _MapUtils.world_to_tile(pos)
	else:
		_selected_entity_name = "Unknown"
		_selected_tile_coord = Vector2i.ZERO

	_show_entity_info()


func _on_entity_deselected() -> void:
	_selection_type = SelectionType.NONE
	_hide_panel()


func _on_tile_selected(tile_coord: Vector2i, layer: int) -> void:
	_selection_type = SelectionType.TILE
	_selected_tile_coord = tile_coord
	_selected_layer = layer
	_show_tile_info()


# =============================================================================
# 显示控制 (Display Control)
# =============================================================================

func _show_entity_info() -> void:
	visible = true

	if _title_label:
		_title_label.text = "Entity"

	if _info_label:
		_info_label.text = _selected_entity_name

	if _coords_label:
		_coords_label.text = "Tile: (%d, %d)" % [
			_selected_tile_coord.x, _selected_tile_coord.y
		]

	if _ground_id_label:
		_ground_id_label.text = ""


func _show_multiple_selection_info(units: Array[Node]) -> void:
	visible = true

	if _title_label:
		_title_label.text = "Selection"

	if _info_label:
		_info_label.text = "%d Units" % units.size()

	if _coords_label:
		_coords_label.text = "Multiple"
	
	if _ground_id_label:
		_ground_id_label.text = ""


func _show_tile_info() -> void:
	visible = true

	if _title_label:
		_title_label.text = "Tile"

	if _info_label:
		_info_label.text = _get_layer_name(_selected_layer)

	if _coords_label:
		_coords_label.text = "(%d, %d)" % [
			_selected_tile_coord.x, _selected_tile_coord.y
		]

	if _ground_id_label:
		var ground_id = -1
		if _world_manager:
			var chunk_coord = _MapUtils.tile_to_chunk(_selected_tile_coord)
			var chunk_data = _world_manager.get_chunk_data(chunk_coord)
			if chunk_data:
				var local_coord = _MapUtils.tile_to_local(_selected_tile_coord)
				ground_id = chunk_data.get_terrain(local_coord.x, local_coord.y)
		
		_ground_id_label.text = "Ground ID: %d" % ground_id


func _hide_panel() -> void:
	visible = false


func _get_layer_name(layer: int) -> String:
	match layer:
		_C.Layer.GROUND:
			return "Ground Layer"
		_C.Layer.DECORATION:
			return "Decoration Layer"
		_C.Layer.OBSTACLE:
			return "Obstacle Layer"
		_:
			return "Unknown Layer"
