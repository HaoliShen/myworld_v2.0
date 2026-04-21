## SettingsPanel.gd
## 设置面板 - 目前只有按键重绑定
## 用法: 由 MainMenu 程序化 new() 并 add_child()
class_name SettingsPanel
extends Control

signal back_requested

var _rows_vbox: VBoxContainer

## 当前等待捕获按键的 action；为空表示未处于捕获状态
var _capturing_action: StringName = &""
## 捕获中的按钮（用于显示 "按下任意键..."）
var _capturing_button: Button = null


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_left = 0.5
	margin.anchor_right = 0.5
	margin.anchor_top = 0.22
	margin.anchor_bottom = 0.95
	margin.offset_left = -320
	margin.offset_right = 320
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# 顶部：返回 + 标题 + 重置
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vbox.add_child(top)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.pressed.connect(func(): back_requested.emit())
	top.add_child(back_btn)

	var title := Label.new()
	title.text = "设置 · 按键"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)

	var reset_btn := Button.new()
	reset_btn.text = "恢复默认"
	reset_btn.pressed.connect(_on_reset_pressed)
	top.add_child(reset_btn)

	# 滚动的按键列表
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_vbox)

	var hint := Label.new()
	hint.text = "点击右侧按键框 → 按下新按键完成绑定（ESC 取消捕获）"
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


# =============================================================================
# 构建/刷新行
# =============================================================================

func refresh() -> void:
	# 清空旧行
	for c in _rows_vbox.get_children():
		c.queue_free()

	var bindings: Array = KeybindingManager.list_bindings()
	for binding in bindings:
		_rows_vbox.add_child(_build_row(binding))


func _build_row(binding: Dictionary) -> Control:
	var action: StringName = binding.action
	var label_text: String = binding.label
	var unavailable: String = UNAVAILABLE_ACTIONS.get(action, "")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	var display := _action_display_name(action)
	if not unavailable.is_empty():
		display += "  " + unavailable
		name_label.modulate = Color(0.6, 0.6, 0.6)
	name_label.text = display
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(name_label)

	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(180, 32)
	btn.toggle_mode = true
	if unavailable.is_empty():
		btn.pressed.connect(func(): _start_capture(action, btn))
	else:
		# 灰掉：禁止修改功能尚未实现的按键
		btn.disabled = true
		btn.modulate = Color(0.6, 0.6, 0.6)
	row.add_child(btn)

	return row


## Action 显示名（让菜单更友好一些）。
func _action_display_name(action: StringName) -> String:
	const NAMES := {
		&"move_up": "向上",
		&"move_down": "向下",
		&"move_left": "向左",
		&"move_right": "向右",
		&"primary_action": "主操作（选中/交互）",
		&"secondary_action": "次操作（移动/取消）",
		&"zoom_in": "放大视角",
		&"zoom_out": "缩小视角",
		&"interact": "交互",
		&"toggle_console": "调试控制台",
		&"toggle_inventory": "背包",
		&"toggle_build_menu": "建造菜单",
		&"toggle_dev_mode": "开发者模式",
	}
	return NAMES.get(action, String(action))


## 未实现 / 不可重绑的 action 列表（UI 会把它们灰掉）。
## Key: StringName -> Value: 说明文字
const UNAVAILABLE_ACTIONS := {
	&"move_up": "（WASD 移动未实现）",
	&"move_down": "（WASD 移动未实现）",
	&"move_left": "（WASD 移动未实现）",
	&"move_right": "（WASD 移动未实现）",
	&"interact": "（功能未实现）",
	&"toggle_console": "（由 Console 插件处理）",
}


# =============================================================================
# 按键捕获
# =============================================================================

func _start_capture(action: StringName, btn: Button) -> void:
	# 如果已经在捕获另一个，先取消
	if _capturing_button and _capturing_button != btn:
		_cancel_capture()
	_capturing_action = action
	_capturing_button = btn
	btn.button_pressed = true
	btn.text = "按下任意键..."


func _cancel_capture() -> void:
	if _capturing_button:
		_capturing_button.button_pressed = false
	_capturing_action = &""
	_capturing_button = null
	# 刷新一次，恢复按键文本
	refresh()


func _gui_input(_event: InputEvent) -> void:
	# 占位：按键捕获走 _input()，这里不处理
	pass


func _input(event: InputEvent) -> void:
	if _capturing_action == &"":
		return
	if not visible:
		return

	# ESC 取消捕获
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return

	var capture_event: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		capture_event = event
	elif event is InputEventMouseButton and event.pressed:
		# 过滤：滚轮也允许，但左键点击可能是点按钮本身触发的；
		# 由于 _start_capture 是在按钮的 pressed 信号里触发，按钮按下时已 handled，
		# 这里收到的鼠标事件是"下一个"，所以安全
		capture_event = event

	if capture_event:
		KeybindingManager.set_binding(_capturing_action, capture_event)
		_capturing_action = &""
		_capturing_button.button_pressed = false
		_capturing_button = null
		refresh()
		get_viewport().set_input_as_handled()


# =============================================================================
# 按钮
# =============================================================================

func _on_reset_pressed() -> void:
	KeybindingManager.reset_all()
	refresh()
