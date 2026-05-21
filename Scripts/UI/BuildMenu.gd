class_name BuildMenu
extends Control

const _C = preload("res://Scripts/data/Constants.gd")
const _ObjectCatalog = preload("res://Scripts/data/ObjectCatalog.gd")

signal menu_opened()
signal menu_closed()

@onready var _item_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ItemList
@onready var _close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/CloseButton

var _build_items: Array[Dictionary] = []


func _ready() -> void:
	_connect_signals()
	_setup_build_items()
	_create_item_buttons()
	visible = false


func _connect_signals() -> void:
	SignalBus.request_toggle_build_menu.connect(_on_toggle_requested)
	if _close_button:
		_close_button.pressed.connect(_close_menu)


func _setup_build_items() -> void:
	_build_items.clear()
	for build_id in _ObjectCatalog.get_buildable_ids():
		_build_items.append({
			"id": int(build_id),
			"name": _ObjectCatalog.get_display_name(build_id),
			"layer": _ObjectCatalog.get_render_layer(build_id, _C.Layer.OBSTACLE),
		})


func _create_item_buttons() -> void:
	if _item_list == null:
		return

	for child in _item_list.get_children():
		child.queue_free()

	for item in _build_items:
		var button := Button.new()
		button.text = _format_button_text(int(item.id), String(item.name))
		button.custom_minimum_size = Vector2(160, 36)
		var item_id: int = item.id
		button.pressed.connect(func(): _on_item_selected(item_id))
		_item_list.add_child(button)


func _format_button_text(build_id: int, display_name: String) -> String:
	var cost: Dictionary = _ObjectCatalog.get_build_cost(build_id)
	if cost.is_empty():
		return display_name

	var parts: Array[String] = []
	for mat_key in cost:
		var mat_name: String = _C.MATERIAL_DISPLAY_NAMES.get(mat_key, String(mat_key))
		parts.append("%s x%d" % [mat_name, int(cost[mat_key])])
	return "%s  (%s)" % [display_name, ", ".join(parts)]


func _on_toggle_requested() -> void:
	if visible:
		_close_menu()
	else:
		_open_menu()


func _on_item_selected(item_id: int) -> void:
	SignalBus.build_item_selected.emit(item_id)
	SignalBus.ui_mode_changed.emit("Build")
	_close_menu()


func _open_menu() -> void:
	visible = true
	menu_opened.emit()


func _close_menu() -> void:
	visible = false
	menu_closed.emit()
	SignalBus.ui_mode_changed.emit("Normal")


func is_open() -> bool:
	return visible


func add_build_item(item_id: int, item_name: String, layer: int) -> void:
	_build_items.append({"id": item_id, "name": item_name, "layer": layer})
	_create_item_buttons()
