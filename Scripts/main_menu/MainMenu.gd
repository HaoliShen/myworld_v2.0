## MainMenu.gd
## 主菜单根控制器 - 管理三个页面的切换（主按钮 / 存档 / 设置）
## 挂载: Scenes/Main/MainMenu.tscn 根节点 (Control)
##
## 所有子 UI 程序化构建。这么做可以把布局细节与逻辑放在一起，
## 且便于文本编辑（无需打开 Godot 编辑器拖拽）。
extends Control

const _C = preload("res://Scripts/data/Constants.gd")
const SaveSlotPanelScript = preload("res://Scripts/main_menu/SaveSlotPanel.gd")
const SettingsPanelScript = preload("res://Scripts/main_menu/SettingsPanel.gd")

enum Page { MAIN, SAVES, SETTINGS }

var _current_page: Page = Page.MAIN

var _main_page: Control
var _saves_page: Control
var _settings_page: Control


func _ready() -> void:
	_build_background()
	_build_title()
	_build_pages()
	_show_page(Page.MAIN)


# =============================================================================
# UI 构建
# =============================================================================

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_title() -> void:
	var title := Label.new()
	title.text = "MyWorld"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.05
	title.anchor_bottom = 0.20
	add_child(title)


func _build_pages() -> void:
	_main_page = _build_main_buttons_page()
	add_child(_main_page)

	_saves_page = SaveSlotPanelScript.new()
	_saves_page.back_requested.connect(func(): _show_page(Page.MAIN))
	add_child(_saves_page)

	_settings_page = SettingsPanelScript.new()
	_settings_page.back_requested.connect(func(): _show_page(Page.MAIN))
	add_child(_settings_page)


func _build_main_buttons_page() -> Control:
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	vbox.add_child(_make_button("开始游戏", func(): _show_page(Page.SAVES)))
	vbox.add_child(_make_button("设置", func(): _show_page(Page.SETTINGS)))
	vbox.add_child(_make_button("退出", func(): get_tree().quit()))

	return root


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_pressed)
	return b


# =============================================================================
# 页面切换
# =============================================================================

func _show_page(p: Page) -> void:
	_current_page = p
	_main_page.visible = (p == Page.MAIN)
	_saves_page.visible = (p == Page.SAVES)
	_settings_page.visible = (p == Page.SETTINGS)
	if p == Page.SAVES:
		_saves_page.refresh()
	elif p == Page.SETTINGS:
		_settings_page.refresh()
