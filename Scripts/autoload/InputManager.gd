## InputManager.gd
## 输入管理器 - 第一道防线 (Input Translation)
## 路径: res://Scripts/Core/InputManager.gd
## 类型: Autoload (Global Singleton)
## 继承: Node
##
## 职责:
## 1. 坐标转换: 屏幕坐标 -> 世界坐标 / 网格坐标
## 2. UI 过滤: 检测鼠标是否在 UI 上，若是则拦截信号
## 3. 手势识别: 区分点击 (Click) 和 拖拽 (Drag)
extends Node2D

# 预加载依赖的类 (解决 Autoload 加载顺序问题)
const _C = preload("res://Scripts/data/Constants.gd")
const _MU = preload("res://Scripts/data/MapUtils.gd")

# =============================================================================
# 信号 (Signals) - 仅当 is_mouse_over_ui() == false 时触发
# =============================================================================

## 意图：移动摄像机 / 拖拽地图 (左键按住移动)
signal camera_pan(relative: Vector2)

## 意图：缩放视野 (滚轮)
## @param zoom_factor: 正值放大，负值缩小
## @param mouse_global_pos: 鼠标世界坐标，用于以鼠标为中心缩放
signal camera_zoom(zoom_factor: float, mouse_global_pos: Vector2)

## 意图：主要点击 (左键单击)
signal on_primary_click(global_pos: Vector2)

## 意图：次要点击 (右键单击)
signal on_secondary_click(global_pos: Vector2)

## 意图：取消/返回 (ESC)
signal on_cancel_action()

## 界面快捷键信号
signal on_toggle_inventory()
signal on_toggle_build_menu()

## 开发者模式切换（F10 默认）
signal on_toggle_dev_mode()

# =============================================================================
# 配置参数 (Configuration)
# =============================================================================

## 拖拽检测阈值 (像素) - 超过此距离判定为拖拽而非点击
var drag_threshold: float = _C.DRAG_THRESHOLD

## 缩放速度系数
var zoom_speed: float = 0.1

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 是否正在拖拽
var _is_dragging: bool = false

## 拖拽起始位置 (屏幕坐标)
var _drag_start_position: Vector2 = Vector2.ZERO

## 左键是否按下
var _is_left_pressed: bool = false


# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	# 鼠标移动单独处理（不走 InputMap action，因为 action 是"瞬时触发"语义，
	# 而 drag 需要基于位置变化持续计算）
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
		return

	_handle_actions(event)


# =============================================================================
# 输入派发 (走 InputMap action，保证可重绑)
# =============================================================================

func _handle_actions(event: InputEvent) -> void:
	# 主操作：按下+松开需要配对，因此分别检测 pressed / released
	if event.is_action_pressed("primary_action"):
		if is_mouse_over_ui():
			return
		_drag_start_position = _get_event_position(event)
		_is_left_pressed = true
		_is_dragging = false
		return
	if event.is_action_released("primary_action"):
		if _is_left_pressed:
			if not _is_dragging:
				on_primary_click.emit(get_mouse_world_pos())
			_is_left_pressed = false
			_is_dragging = false
		return

	# 次操作：在松开时触发（保持与原来语义一致）
	if event.is_action_released("secondary_action"):
		if is_mouse_over_ui():
			return
		on_secondary_click.emit(get_mouse_world_pos())
		return

	# 缩放
	if event.is_action_pressed("zoom_in"):
		if is_mouse_over_ui():
			return
		camera_zoom.emit(zoom_speed, get_mouse_world_pos())
		return
	if event.is_action_pressed("zoom_out"):
		if is_mouse_over_ui():
			return
		camera_zoom.emit(-zoom_speed, get_mouse_world_pos())
		return

	# UI/菜单键
	_handle_keyboard_input(event)


func _get_event_position(event: InputEvent) -> Vector2:
	# primary_action 可能是鼠标按钮也可能是键盘键（用户重绑后）。
	# 鼠标拖拽阈值需要屏幕坐标；键盘触发时用当前鼠标位置做起点即可。
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return get_viewport().get_mouse_position()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# UI 阻断检查
	if is_mouse_over_ui():
		return

	# 左键按住时的拖拽检测
	if _is_left_pressed:
		var drag_distance := event.position.distance_to(_drag_start_position)
		if drag_distance > drag_threshold:
			_is_dragging = true

		# 如果已经在拖拽，发射 camera_pan 信号
		if _is_dragging:
			camera_pan.emit(event.relative)

# =============================================================================
# 键盘输入处理 (Keyboard Input Handling)
# =============================================================================

func _handle_keyboard_input(event: InputEvent) -> void:
	# ESC - 取消操作
	if event.is_action_pressed("ui_cancel"):
		on_cancel_action.emit()

	# I - 切换背包 (可根据需要配置 Input Map)
	if event.is_action_pressed("toggle_inventory"):
		on_toggle_inventory.emit()

	# B - 切换建造菜单 (可根据需要配置 Input Map)
	if event.is_action_pressed("toggle_build_menu"):
		on_toggle_build_menu.emit()

	# F10 - 切换开发者模式
	if event.is_action_pressed("toggle_dev_mode"):
		on_toggle_dev_mode.emit()

# =============================================================================
# 状态查询 (State Queries)
# =============================================================================

## 获取当前鼠标指向的世界坐标
## 使用 Godot 内置方法，自动考虑相机位置和缩放
func get_mouse_world_pos() -> Vector2:
	return get_global_mouse_position()


## 获取当前鼠标指向的网格坐标
## 逻辑:
## 1. 调用 get_mouse_world_pos()
## 2. 直接调用 MapUtils 的工具函数实现转换
func get_mouse_tile_pos() -> Vector2i:
	return _MU.world_to_tile(get_mouse_world_pos())


## 检查鼠标是否在 UI 上
## 使用 Viewport 的 gui_get_focus_owner 和 Control.get_global_rect 判断
func is_mouse_over_ui() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false

	# 方法1: 检查是否有 GUI 控件获得焦点且正在处理输入
	# 方法2: 使用 Viewport.gui_is_dragging() 检查拖拽
	# 方法3: 检查鼠标位置下是否有 Control 节点

	# 最可靠的方法: 检查 viewport 是否将输入传递给了 GUI
	return viewport.gui_get_hovered_control() != null

# =============================================================================
# 辅助方法 (Helper Methods)
# =============================================================================

## 获取当前鼠标指向的区块坐标
func get_mouse_chunk_pos() -> Vector2i:
	return _MU.world_to_chunk(get_mouse_world_pos())
