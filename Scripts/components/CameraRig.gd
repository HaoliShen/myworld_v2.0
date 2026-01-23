## CameraRig.gd
## 摄像机控制中枢 (Camera Control Hub)
## 路径: res://Scripts/Components/CameraRig.gd
## 挂载节点: Player/CameraRig (作为玩家场景的子节点)
## 继承: Node2D
## 依赖: Phantom Camera (插件)
##
## 职责:
## 它不直接是摄像机，而是 PhantomCamera2D (PCam) 的挂载点和控制器。
## 它负责监听 InputManager 的信号，动态调整 PCam 的参数（缩放、偏移），
## 从而实现 RPG 跟随视角与 RTS 拖拽视角的平滑融合。
##
## 节点结构:
## CameraRig (Node2D)              <-- 挂载此脚本
## └── PhantomCamera2D             <-- [插件节点] PhantomCamera2D
class_name CameraRig
extends Node2D

# =============================================================================
# 导出变量 (Exported Variables)
# =============================================================================

@export_group("Zoom Settings")
## 最远视角 (宏观) - 设置为 0 表示无限制
@export var min_zoom: float = 0.1
## 最近视角 (微观) - 设置为 0 表示无限制
@export var max_zoom: float = 10.0
## 缩放平滑速度
@export var zoom_speed: float = 5.0

@export_group("Pan Settings")
## 允许拖拽偏离玩家的最大距离 - 设置为 Vector2.ZERO 表示无限制
@export var max_pan_offset: Vector2 = Vector2.ZERO
## 拖拽平滑速度
@export var pan_speed: float = 10.0

@export_group("Debug")
## 是否启用缩放限制
@export var enable_zoom_limits: bool = false
## 是否启用拖拽限制
@export var enable_pan_limits: bool = false

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 当前的目标缩放值 (用于平滑插值)
var _target_zoom: float = 1.0

## 当前的拖拽偏移量 (相对于 Player 中心的偏移)
var _current_pan_offset: Vector2 = Vector2.ZERO

## 引用 PhantomCamera2D 节点
@onready var pcam = $PhantomCamera2D

## 是否使用 Phantom Camera (如果插件不可用则回退)
var _use_phantom_camera: bool = false

## 回退用的 Camera2D 引用
var _fallback_camera: Camera2D = null

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	_setup_camera()
	_connect_signals()


func _process(delta: float) -> void:
	# 1. 处理平滑缩放
	_update_zoom(delta)

	# 2. 处理位置偏移
	# CameraRig 是 Player 的子节点，修改其 position 就相当于修改了 PCam 的 Follow Offset
	_update_position(delta)

# =============================================================================
# 初始化 (Initialization)
# =============================================================================

func _setup_camera() -> void:
	# 检查 PhantomCamera2D 是否可用 (检查是否有 zoom 属性)
	if pcam != null and "zoom" in pcam:
		_use_phantom_camera = true
		_target_zoom = pcam.zoom.x if pcam.zoom else 1.0
		print("CameraRig: Using PhantomCamera2D")
	else:
		# 回退: 使用普通 Camera2D
		_use_phantom_camera = false
		_setup_fallback_camera()
		print("CameraRig: PhantomCamera2D not available, using fallback Camera2D")


func _setup_fallback_camera() -> void:
	_fallback_camera = get_node_or_null("Camera2D")
	if _fallback_camera == null:
		_fallback_camera = Camera2D.new()
		_fallback_camera.name = "Camera2D"
		add_child(_fallback_camera)

	_fallback_camera.make_current()
	_target_zoom = _fallback_camera.zoom.x


func _connect_signals() -> void:
	# 连接 InputManager 信号
	InputManager.camera_zoom.connect(_on_camera_zoom)
	InputManager.camera_pan.connect(_on_camera_pan)

# =============================================================================
# 缩放控制 (Zoom Control)
# =============================================================================

## 响应滚轮缩放
## @param zoom_factor: +0.1 或 -0.1
## @param mouse_pos: 鼠标世界坐标 (可用于以鼠标为中心缩放)
func _on_camera_zoom(zoom_factor: float, _mouse_pos: Vector2) -> void:
	_target_zoom += zoom_factor

	# 仅在启用限制时应用 clamp
	if enable_zoom_limits and min_zoom > 0 and max_zoom > 0:
		_target_zoom = clampf(_target_zoom, min_zoom, max_zoom)
	else:
		# 至少保证缩放值为正
		_target_zoom = maxf(_target_zoom, 0.01)


func _update_zoom(delta: float) -> void:
	var current_zoom := _get_current_zoom()

	if absf(current_zoom - _target_zoom) > 0.001:
		var new_zoom := lerpf(current_zoom, _target_zoom, zoom_speed * delta)
		_set_zoom(new_zoom)

# =============================================================================
# 位置/拖拽控制 (Pan Control)
# =============================================================================

## 响应鼠标拖拽地图
## @param relative: 鼠标相对位移
## 为了符合直觉，地图移动方向与鼠标相反（拖拽地图的感觉）
func _on_camera_pan(relative: Vector2) -> void:
	# 累加偏移量 (考虑缩放影响)
	var current_zoom := _get_current_zoom()
	_current_pan_offset -= relative / current_zoom

	# 仅在启用限制时应用 clamp
	if enable_pan_limits and max_pan_offset != Vector2.ZERO:
		_current_pan_offset.x = clampf(_current_pan_offset.x, -max_pan_offset.x, max_pan_offset.x)
		_current_pan_offset.y = clampf(_current_pan_offset.y, -max_pan_offset.y, max_pan_offset.y)


func _update_position(delta: float) -> void:
	# 平滑移动到目标偏移位置
	position = position.lerp(_current_pan_offset, pan_speed * delta)

# =============================================================================
# 公共接口 (API)
# =============================================================================

## 重置视角（回到玩家中心，恢复默认缩放）
func recenter_camera() -> void:
	_current_pan_offset = Vector2.ZERO
	_target_zoom = 1.0


## 设置缩放级别
func set_zoom(zoom_level: float) -> void:
	if enable_zoom_limits and min_zoom > 0 and max_zoom > 0:
		_target_zoom = clampf(zoom_level, min_zoom, max_zoom)
	else:
		_target_zoom = maxf(zoom_level, 0.01)


## 获取当前缩放级别
func get_zoom() -> float:
	return _get_current_zoom()


## 立即重置位置（无平滑）
func snap_to_center() -> void:
	_current_pan_offset = Vector2.ZERO
	position = Vector2.ZERO

# =============================================================================
# 内部辅助方法 (Internal Helpers)
# =============================================================================

func _get_current_zoom() -> float:
	if _use_phantom_camera and pcam:
		return pcam.zoom.x if pcam.zoom else 1.0
	elif _fallback_camera:
		return _fallback_camera.zoom.x
	return 1.0


func _set_zoom(new_zoom: float) -> void:
	var zoom_vec := Vector2(new_zoom, new_zoom)

	if _use_phantom_camera and pcam:
		pcam.zoom = zoom_vec
	elif _fallback_camera:
		_fallback_camera.zoom = zoom_vec

# =============================================================================
# 工具方法 (Utility Methods)
# =============================================================================

## 获取相机可见区域 (世界坐标)
func get_visible_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()

	var viewport_size := viewport.get_visible_rect().size
	var current_zoom := _get_current_zoom()
	var camera_size := viewport_size / current_zoom
	var top_left := global_position - camera_size * 0.5

	return Rect2(top_left, camera_size)


## 检查世界坐标是否在相机视野内
func is_position_visible(world_pos: Vector2) -> bool:
	return get_visible_rect().has_point(world_pos)


## 获取实际的摄像机节点
func get_camera_node() -> Node2D:
	if _use_phantom_camera and pcam:
		return pcam
	return _fallback_camera
