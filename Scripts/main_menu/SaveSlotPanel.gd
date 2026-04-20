## SaveSlotPanel.gd
## 存档选择面板
## 用法: 由 MainMenu 程序化 new() 并 add_child()
##
## 布局:
##   [返回]  存档槽
##   [新建世界]
##   ┌─ ItemList: 世界列表 ─┐
##   │  world1 (上次: ...)  │
##   │  world2 (上次: ...)  │
##   └──────────────────────┘
##   选中后弹出操作条: [开始] [详情] [删除]
class_name SaveSlotPanel
extends Control

signal back_requested

const _C = preload("res://Scripts/data/Constants.gd")

var _list: ItemList
var _actions_row: HBoxContainer
var _empty_label: Label

var _world_names: Array[String] = []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_left = 0.5
	margin.anchor_right = 0.5
	margin.anchor_top = 0.25
	margin.anchor_bottom = 0.95
	margin.offset_left = -360
	margin.offset_right = 360
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# 顶部：返回 + 标题 + 新建
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vbox.add_child(top)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.pressed.connect(func(): back_requested.emit())
	top.add_child(back_btn)

	var title := Label.new()
	title.text = "选择存档"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)

	var new_btn := Button.new()
	new_btn.text = "+ 新建世界"
	new_btn.pressed.connect(_open_new_world_dialog)
	top.add_child(new_btn)

	# 列表
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 320)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_idx): _on_item_selected())
	_list.item_activated.connect(func(_idx): _on_start_pressed()) # 双击直接进游戏
	vbox.add_child(_list)

	# 空列表提示
	_empty_label = Label.new()
	_empty_label.text = "暂无存档，点击右上角新建世界"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(_empty_label)

	# 操作条（选中后显示）
	_actions_row = HBoxContainer.new()
	_actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions_row.add_theme_constant_override("separation", 12)
	_actions_row.visible = false
	vbox.add_child(_actions_row)

	var start_btn := Button.new()
	start_btn.text = "开始游戏"
	start_btn.pressed.connect(_on_start_pressed)
	_actions_row.add_child(start_btn)

	var details_btn := Button.new()
	details_btn.text = "查看详情"
	details_btn.pressed.connect(_on_details_pressed)
	_actions_row.add_child(details_btn)

	var delete_btn := Button.new()
	delete_btn.text = "删除"
	delete_btn.modulate = Color(1.0, 0.6, 0.6)
	delete_btn.pressed.connect(_on_delete_pressed)
	_actions_row.add_child(delete_btn)


# =============================================================================
# 刷新列表
# =============================================================================

func refresh() -> void:
	_list.clear()
	_actions_row.visible = false
	_world_names = SaveSystem.get_world_list()
	for world_name in _world_names:
		var meta: Dictionary = SaveSystem.get_world_metadata(world_name)
		var display: String = world_name
		if meta.get("exists", false):
			var last: String = str(meta.get("last_played_at", ""))
			if not last.is_empty():
				display += "    上次游玩: %s" % last
			else:
				display += "    （未进入过）"
		_list.add_item(display)
	_empty_label.visible = _world_names.is_empty()


func _get_selected_world() -> String:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return ""
	return _world_names[sel[0]]


func _on_item_selected() -> void:
	_actions_row.visible = true


# =============================================================================
# 按钮处理
# =============================================================================

func _on_start_pressed() -> void:
	var world_name := _get_selected_world()
	if world_name.is_empty():
		return
	if not SaveSystem.load_world(world_name):
		push_error("SaveSlotPanel: load_world failed: %s" % world_name)
		return
	get_tree().change_scene_to_file("res://Scenes/Main/World.tscn")


func _on_details_pressed() -> void:
	var world_name := _get_selected_world()
	if world_name.is_empty():
		return
	var meta: Dictionary = SaveSystem.get_world_metadata(world_name)
	if not meta.get("exists", false):
		push_error("SaveSlotPanel: cannot read metadata for %s" % world_name)
		return
	_show_details(meta)


func _on_delete_pressed() -> void:
	var world_name := _get_selected_world()
	if world_name.is_empty():
		return
	_confirm_delete(world_name)


# =============================================================================
# 新建世界对话框
# =============================================================================

func _open_new_world_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "新建世界"
	dialog.min_size = Vector2(420, 200)
	dialog.ok_button_text = "创建"
	dialog.add_cancel_button("取消")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	vbox.add_child(_label_for_input("世界名称："))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "例如 MyFirstWorld"
	name_edit.max_length = 40
	vbox.add_child(name_edit)

	vbox.add_child(_label_for_input("种子（留空随机）："))
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "整数，可留空"
	vbox.add_child(seed_edit)

	var hint := Label.new()
	hint.text = "世界名仅允许字母、数字、下划线、减号"
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)

	dialog.confirmed.connect(func():
		_try_create_world(name_edit.text.strip_edges(), seed_edit.text.strip_edges())
	)
	add_child(dialog)
	dialog.popup_centered()


func _try_create_world(world_name: String, seed_text: String) -> void:
	if world_name.is_empty():
		_show_alert("世界名不能为空")
		return
	if not _is_valid_world_name(world_name):
		_show_alert("世界名含非法字符（只允许字母数字下划线减号）")
		return
	if SaveSystem.world_exists(world_name):
		_show_alert("同名存档已存在")
		return

	var seed_int := 0
	if not seed_text.is_empty():
		if not seed_text.is_valid_int():
			_show_alert("种子必须是整数或留空")
			return
		seed_int = seed_text.to_int()

	if not SaveSystem.create_world(world_name, seed_int):
		_show_alert("创建失败（路径权限？）")
		return
	# 创建后直接进入游戏
	get_tree().change_scene_to_file("res://Scenes/Main/World.tscn")


func _is_valid_world_name(s: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]+$")
	return regex.search(s) != null


# =============================================================================
# 详情对话框
# =============================================================================

func _show_details(meta: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "存档详情"
	dialog.min_size = Vector2(480, 280)
	dialog.ok_button_text = "关闭"

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	dialog.add_child(grid)

	var last: String = str(meta.get("last_played_at", ""))
	if last.is_empty():
		last = "（未进入过）"

	_grid_row(grid, "世界名", str(meta.get("name", "")))
	_grid_row(grid, "种子", str(meta.get("seed", 0)))
	_grid_row(grid, "版本", str(meta.get("version", "")))
	_grid_row(grid, "创建时间", str(meta.get("created_at", "")))
	_grid_row(grid, "上次游玩", str(last))
	_grid_row(grid, "游玩次数", str(meta.get("play_count", 0)))

	add_child(dialog)
	dialog.popup_centered()


func _grid_row(grid: GridContainer, key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.modulate = Color(0.75, 0.75, 0.75)
	grid.add_child(k)
	var v := Label.new()
	v.text = value
	grid.add_child(v)


# =============================================================================
# 删除确认
# =============================================================================

func _confirm_delete(world_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "删除存档"
	dialog.dialog_text = "确定删除存档「%s」？此操作不可撤销。" % world_name
	dialog.ok_button_text = "删除"
	dialog.get_ok_button().modulate = Color(1.0, 0.4, 0.4)
	dialog.confirmed.connect(func():
		if SaveSystem.delete_world(world_name):
			refresh()
		else:
			_show_alert("删除失败")
	)
	add_child(dialog)
	dialog.popup_centered()


# =============================================================================
# 通用提示
# =============================================================================

func _show_alert(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = msg
	add_child(dialog)
	dialog.popup_centered()


func _label_for_input(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
