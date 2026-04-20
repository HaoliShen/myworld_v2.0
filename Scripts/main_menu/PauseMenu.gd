## PauseMenu.gd
## 游戏内暂停菜单
## 挂载: Scenes/Main/World.tscn 的 UI CanvasLayer 下
##
## 触发：
## - 打开：SignalBus.pause_menu_requested（由 InteractionManager 在 NORMAL 模式+无选中时发出）
## - 关闭：Continue 按钮 / ESC / 点击外部（无）
##
## 选项：
## - 继续        → 关闭菜单，恢复运行
## - 回主菜单    → force_save_all → change_scene_to_file(MainMenu.tscn)
## - 退出游戏    → force_save_all → get_tree().quit()
##
## 注意 process_mode = PROCESS_MODE_ALWAYS，使得菜单在 get_tree().paused=true 时仍可响应。
extends Control

const _C = preload("res://Scripts/data/Constants.gd")


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	SignalBus.pause_menu_requested.connect(_open)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(260, 0)
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	vbox.add_child(_make_button("继续", _close))
	vbox.add_child(_make_button("回主菜单", _back_to_main_menu))
	vbox.add_child(_make_button("退出游戏", _quit_game))


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_pressed)
	return b


func _input(event: InputEvent) -> void:
	# 只在菜单打开时处理 ESC 关闭，避免跟 InteractionManager 争抢 on_cancel_action
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true


func _close() -> void:
	visible = false
	get_tree().paused = false


func _back_to_main_menu() -> void:
	# 先保存再切场景。切场景会销毁 WorldManager，它的 _notification 也会兜底，
	# 但这里显式调用一次，确保时序明确。
	var wm := get_node_or_null("/root/World/Managers/WorldManager")
	if wm and wm.has_method("force_save_all"):
		wm.force_save_all()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/Main/MainMenu.tscn")


func _quit_game() -> void:
	var wm := get_node_or_null("/root/World/Managers/WorldManager")
	if wm and wm.has_method("force_save_all"):
		wm.force_save_all()
	get_tree().quit()
