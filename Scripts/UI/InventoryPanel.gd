## InventoryPanel.gd
## 玩家物品栏页面
## 挂载: Scenes/Main/World.tscn 的 UI CanvasLayer 下
##
## 触发：
## - 打开/关闭：I 键（InputManager.on_toggle_inventory）
## - 关闭：ESC（当面板可见时，优先消费 ESC）
##
## 设计：
## - 与 HUD.materials_label 数据同源（PlayerInventory.inventory_changed），
##   面板只是把它画成更友好的网格样式
## - 不暂停游戏（仅叠加式 overlay），与暂停菜单区分开
## - 程序化构建 UI，和 MainMenu 风格保持一致
extends Control

const _C = preload("res://Scripts/data/Constants.gd")

var _slots_grid: GridContainer
var _dim: ColorRect

## 当前绘制的插槽 label，按 material_key 索引，便于局部刷新
var _slot_labels: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE # 隐藏时不拦截
	_build_ui()
	# 通过 InputManager 的语义信号切换（I 键）
	InputManager.on_toggle_inventory.connect(_on_toggle)
	PlayerInventory.inventory_changed.connect(_refresh)
	# 开发模式切换时整块重建，以显示/隐藏 +/- 按钮
	DevMode.dev_mode_changed.connect(_on_dev_mode_changed)


# =============================================================================
# UI 构建
# =============================================================================

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.35)
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 360)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# 顶部：标题 + 关闭按钮
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "背包"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	# 材料分区标题
	var section_label := Label.new()
	section_label.text = "材料"
	section_label.modulate = Color(0.75, 0.75, 0.75)
	section_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(section_label)

	# 材料网格
	_slots_grid = GridContainer.new()
	_slots_grid.columns = 4
	_slots_grid.add_theme_constant_override("h_separation", 12)
	_slots_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(_slots_grid)

	# 底部提示
	var hint := Label.new()
	hint.text = "I / ESC 关闭背包"
	hint.modulate = Color(0.65, 0.65, 0.65)
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	_populate_slots()


## 每种已知材料都给一个格子（即使数量为 0，让玩家对可收集材料有整体认知）
## 后续加更多材料类别（矿石、食物、工具等）时按同样思路扩展
func _populate_slots() -> void:
	for c in _slots_grid.get_children():
		c.queue_free()
	_slot_labels.clear()
	for key in _C.MATERIAL_DISPLAY_NAMES.keys():
		var slot := _make_slot(String(key), _C.MATERIAL_DISPLAY_NAMES[key])
		_slots_grid.add_child(slot)


func _make_slot(key: String, display_name: String) -> Control:
	# 单个格子：PanelContainer 包 VBox（名字 + 数量 + 可选 dev 按钮）
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(96, 128 if DevMode.is_enabled else 96)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	slot.add_child(vbox)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "×0"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 22)
	count_label.modulate = Color(0.75, 0.75, 0.75)
	vbox.add_child(count_label)

	_slot_labels[key] = count_label

	# 开发模式下露出一排 +/- 按钮
	if DevMode.is_enabled:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(32, 28)
		minus.pressed.connect(_dev_remove.bind(key))
		row.add_child(minus)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(32, 28)
		plus.pressed.connect(_dev_add.bind(key))
		row.add_child(plus)

	return slot


# =============================================================================
# 开发模式编辑
# =============================================================================

func _dev_add(key: String) -> void:
	PlayerInventory.add(key, 1)


func _dev_remove(key: String) -> void:
	PlayerInventory.remove(key, 1)


func _on_dev_mode_changed(_enabled: bool) -> void:
	# 整块重建以加上/移除 +/- 按钮
	_populate_slots()
	_refresh(PlayerInventory.snapshot())


# =============================================================================
# 刷新
# =============================================================================

func _refresh(inventory: Dictionary) -> void:
	for key in _slot_labels.keys():
		var label: Label = _slot_labels[key]
		var n: int = int(inventory.get(key, 0))
		label.text = "×%d" % n
		# 有存量时亮色，空时暗色
		label.modulate = Color(1.0, 1.0, 1.0) if n > 0 else Color(0.5, 0.5, 0.5)


# =============================================================================
# 显隐控制
# =============================================================================

func _on_toggle() -> void:
	if visible:
		_close()
	else:
		_open()


func _open() -> void:
	if visible:
		return
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 打开时主动刷一次（进入场景前可能已有材料）
	_refresh(PlayerInventory.snapshot())


func _close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 打开时消费 ESC 自己关闭，不让事件传到 InteractionManager / PauseMenu
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
