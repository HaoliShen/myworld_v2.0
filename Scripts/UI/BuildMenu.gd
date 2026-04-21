## BuildMenu.gd
## 建造菜单 - 选择建造物品
## 路径: res://Scripts/UI/BuildMenu.gd
## 挂载节点: World/UI/BuildMenu
## 继承: Control
##
## 职责:
## 显示可建造物品列表，选择后通过 SignalBus 发送 build_item_selected 信号。
## 响应 request_toggle_build_menu 信号切换显示。
class_name BuildMenu
extends Control

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")

# =============================================================================
# 信号 (Signals)
# =============================================================================

signal menu_opened()
signal menu_closed()

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

@onready var _panel: PanelContainer = $PanelContainer
@onready var _item_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ItemList
@onready var _title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var _close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/CloseButton

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 建造物品列表 (从 Constants 获取)
var _build_items: Array[Dictionary] = []

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_connect_signals()
	_setup_build_items()
	_create_item_buttons()
	# 默认隐藏
	visible = false


# =============================================================================
# 信号连接 (Signal Connections)
# =============================================================================

func _connect_signals() -> void:
	# 响应切换建造菜单请求
	SignalBus.request_toggle_build_menu.connect(_on_toggle_requested)

	# 关闭按钮
	if _close_button:
		_close_button.pressed.connect(_close_menu)


# =============================================================================
# 初始化 (Initialization)
# =============================================================================

func _setup_build_items() -> void:
	# 建造菜单只放"建筑方块"——自然资源（草/树/石）是采集物，不应出现在这里。
	# palette 从 Constants.BUILD_COSTS 的 key 派生，新增建筑方块只需在那里加一行。
	_build_items.clear()
	for build_id in _C.BUILD_COSTS.keys():
		_build_items.append({
			"id": int(build_id),
			"name": _C.BUILD_DISPLAY_NAMES.get(build_id, str(build_id)),
			"layer": _C.OBJECT_RENDER_LAYER_TABLE.get(build_id, _C.Layer.OBSTACLE),
		})


func _create_item_buttons() -> void:
	if _item_list == null:
		return

	# 清空现有按钮
	for child in _item_list.get_children():
		child.queue_free()

	# 创建物品按钮
	for item in _build_items:
		var button := Button.new()
		button.text = _format_button_text(int(item.id), String(item.name))
		button.custom_minimum_size = Vector2(160, 36)
		# 绑定点击事件
		var item_id: int = item.id
		button.pressed.connect(func(): _on_item_selected(item_id))
		_item_list.add_child(button)


## 按钮文字格式："木墙  (木 x2)"
func _format_button_text(build_id: int, display_name: String) -> String:
	var cost: Dictionary = _C.BUILD_COSTS.get(build_id, {})
	if cost.is_empty():
		return display_name
	var parts: Array[String] = []
	for mat_key in cost:
		var mat_name: String = _C.MATERIAL_DISPLAY_NAMES.get(mat_key, String(mat_key))
		parts.append("%s x%d" % [mat_name, int(cost[mat_key])])
	return "%s  (%s)" % [display_name, ", ".join(parts)]


# =============================================================================
# 信号处理 (Signal Handlers)
# =============================================================================

func _on_toggle_requested() -> void:
	if visible:
		_close_menu()
	else:
		_open_menu()


func _on_item_selected(item_id: int) -> void:
	# 发送建造物品选择信号
	SignalBus.build_item_selected.emit(item_id)

	# 通知 UI 模式变化
	SignalBus.ui_mode_changed.emit("Build")

	# 关闭菜单
	_close_menu()


# =============================================================================
# 菜单控制 (Menu Control)
# =============================================================================

func _open_menu() -> void:
	visible = true
	menu_opened.emit()


func _close_menu() -> void:
	visible = false
	menu_closed.emit()

	# 如果没有选择物品，恢复普通模式
	SignalBus.ui_mode_changed.emit("Normal")


# =============================================================================
# 公共接口 (Public API)
# =============================================================================

## 检查菜单是否打开
func is_open() -> bool:
	return visible


## 添加建造物品
func add_build_item(item_id: int, item_name: String, layer: int) -> void:
	_build_items.append({"id": item_id, "name": item_name, "layer": layer})
	_create_item_buttons()
