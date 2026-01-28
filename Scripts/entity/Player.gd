## Player.gd
## 玩家实体 - 核心控制器
## 路径: res://Scripts/Entities/Player.gd
## 挂载节点: World/Environment/EntityContainer/Player
## 继承: CharacterBody2D
## 依赖:
##   - Godot State Charts (状态机插件)
##   - NavigationAgent2D (寻路代理)
##   - CameraRig (子节点控制器)
##
## 职责:
## 玩家实体的核心控制器。它不直接处理输入（由 InteractionManager 处理），
## 而是接收指令并执行。它负责物理运动计算、寻路逻辑执行以及状态机的状态流转。
class_name Player
extends CharacterBody2D

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

# =============================================================================
# 信号 (Signals)
# =============================================================================

## 玩家位置变化
signal moved(new_position: Vector2)

## 玩家进入新区块
signal chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i)

## 玩家与目标交互
signal interacted(target_pos: Vector2)

## 玩家选中状态变化
signal selection_changed(is_selected: bool)

# =============================================================================
# 导出变量 (Exported Variables)
# =============================================================================

@export_group("Movement")
## 基础移动速度
@export var base_speed: float = 600.0
## 加速度
@export var acceleration: float = 3000.0
## 摩擦力 (减速度)
@export var friction: float = 1500.0
## 上坡速度倍率
@export var uphill_multiplier: float = 0.7
## 下坡速度倍率
@export var downhill_multiplier: float = 1.2

@export_group("Interaction")
## 交互范围 (像素)
@export var interaction_range: float = 48.0

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

## 状态机 (通过事件发送状态转换请求)
@onready var _state_chart: Node = $StateChart

## 导航代理
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D

## 摄像机控制器
@onready var _camera_rig = $CameraRig

## 视觉容器
# @onready var _visuals: Node2D = $Visuals

## 精灵
@onready var _sprite: Sprite2D = $Visuals/Sprite2D

## 动画播放器
# @onready var _anim_player: AnimationPlayer = $Visuals/AnimationPlayer

## 选中标记
@onready var _selection_marker: Sprite2D = $Visuals/SelectionMarker

# =============================================================================
# 内部变量 (Internal Variables)
# =============================================================================

## 当前所在区块
var _current_chunk: Vector2i = Vector2i.ZERO

## 当前高度 (暂时未使用)
# var _current_elevation: int = 0

## 是否被选中
var _is_selected: bool = false

## 当前状态 (Idle, Moving, Interacting)
var _current_state: String = "Idle"

## 待交互的目标位置 (Move-To-Interact)
var _pending_interact_pos: Vector2 = Vector2.ZERO

## 是否有待执行的交互
var _has_pending_interact: bool = false

## 目标速度
var _target_velocity: Vector2 = Vector2.ZERO

## 面朝方向
var _facing_direction: Vector2 = Vector2.DOWN

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	print("[Player] _ready() called")
	_setup_navigation()
	_setup_visuals()
	_update_current_chunk()
	print("[Player] Initial chunk: %s at position: %s" % [_current_chunk, global_position])
	add_to_group("player")

	if _selection_marker:
		_selection_marker.visible = false
	print("[Player] Initialization complete")


func _physics_process(delta: float) -> void:
	match _current_state:
		"Moving":
			_process_movement(delta)
		"Interacting":
			_process_interaction(delta)
		_:  # Idle
			_apply_friction(delta)

	# 应用速度
	move_and_slide()

	# 检查区块变化
	_check_chunk_change()


# =============================================================================
# 初始化 (Initialization)
# =============================================================================

func _setup_navigation() -> void:
	if _nav_agent:
		# 配置导航代理
		_nav_agent.path_desired_distance = 4.0
		_nav_agent.target_desired_distance = 4.0
		_nav_agent.avoidance_enabled = true

		# 连接信号
		_nav_agent.navigation_finished.connect(_on_navigation_finished)
		_nav_agent.velocity_computed.connect(_on_velocity_computed)


func _setup_visuals() -> void:
	# 设置精灵偏移以适配 Y-Sort
	if _sprite:
		_sprite.offset.y = -8  # 假设角色高度 16px，脚底在中心


# =============================================================================
# 状态查询 (State Query)
# =============================================================================

## 返回玩家当前是否被选中
func is_selected() -> bool:
	return _is_selected


## 获取当前所在区块
func get_current_chunk() -> Vector2i:
	return _current_chunk


## 获取面朝方向
func get_facing_direction() -> Vector2:
	return _facing_direction


## 获取面前的瓦片坐标
func get_facing_tile() -> Vector2i:
	var facing_pos := global_position + _facing_direction * _C.TILE_SIZE
	return _MapUtils.world_to_tile(facing_pos)


## 获取当前状态
func get_current_state() -> String:
	return _current_state


# =============================================================================
# 外部指令 (Command Interface)
# =============================================================================

## 设置玩家的选中状态
## @param selected: true 为选中，false 为取消选中
func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return

	_is_selected = selected

	# 控制选中标记显示
	if _selection_marker:
		_selection_marker.visible = selected

	selection_changed.emit(selected)


## 瞬间传送玩家到指定位置
## @param target_pos: 目标世界坐标
func teleport_to(target_pos: Vector2) -> void:
	# 1. 直接修改位置
	global_position = target_pos

	# 2. 重置导航代理路径
	if _nav_agent:
		_nav_agent.target_position = target_pos

	# 3. 重置速度
	velocity = Vector2.ZERO
	_target_velocity = Vector2.ZERO

	# 4. 强制更新 CameraRig 位置
	if _camera_rig:
		_camera_rig.snap_to_center()

	# 5. 切换到 Idle 状态
	_change_state("Idle")

	# 6. 更新区块
	_update_current_chunk()

	# 7. 发送信号
	moved.emit(global_position)
	SignalBus.player_position_updated.emit(global_position)


## 传送到指定瓦片
func teleport_to_tile(tile_coord: Vector2i) -> void:
	var world_pos := _MapUtils.tile_to_world_center(tile_coord)
	teleport_to(world_pos)


## 命令玩家移动到指定位置
## @param target_pos: 目标世界坐标
func command_move_to(target_pos: Vector2) -> void:
	# 清除待交互状态
	_has_pending_interact = false

	# 设置导航目标
	if _nav_agent:
		_nav_agent.target_position = target_pos
	print("move start")
	# 切换到 Moving 状态
	_change_state("Moving")

	# 发送状态机事件 (如果使用 StateChart 插件)
	_send_state_event("move_requested")

	# 发送移动开始信号
	SignalBus.player_move_started.emit(_facing_direction)


## 命令玩家与指定位置的物体交互
## @param target_pos: 交互目标的世界坐标
func command_interact(target_pos: Vector2) -> void:
	var distance := global_position.distance_to(target_pos)

	if distance <= interaction_range:
		# 在交互范围内：直接交互
		_execute_interaction(target_pos)
	else:
		# 不在范围内：先移动再交互 (Move-To-Interact)
		_pending_interact_pos = target_pos
		_has_pending_interact = true

		# 计算移动目标 (交互对象边缘)
		var direction := (target_pos - global_position).normalized()
		var move_target := target_pos - direction * (interaction_range * 0.8)

		command_move_to(move_target)


## 停止当前移动
func stop_movement() -> void:
	_target_velocity = Vector2.ZERO
	_change_state("Idle")
	_send_state_event("stop")
	SignalBus.player_move_stopped.emit()


# =============================================================================
# 移动处理 (Movement Processing)
# =============================================================================

func _process_movement(delta: float) -> void:
	if _nav_agent == null:
		return

	if _nav_agent.is_navigation_finished():
		_on_navigation_finished()
		return

	# 获取下一个路径点
	var next_position := _nav_agent.get_next_path_position()
	var direction := (next_position - global_position).normalized()

	# 更新面朝方向
	if direction.length() > 0.1:
		_facing_direction = direction
		_update_sprite_direction()

	# 计算目标速度
	var speed := _calculate_speed()
	_target_velocity = direction * speed

	# 应用加速度
	velocity = velocity.move_toward(_target_velocity, acceleration * delta)

	# 使用导航代理的避障功能
	if _nav_agent.avoidance_enabled:
		_nav_agent.velocity = velocity
	
	# [修复] 确保每帧更新动画状态，防止因速度过小或方向未改变导致动画停滞
	_play_movement_animation()


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	# 应用避障后的安全速度
	velocity = safe_velocity


func _on_navigation_finished() -> void:
	# 移动完成
	_target_velocity = Vector2.ZERO

	# 检查是否有待执行的交互
	if _has_pending_interact:
		_execute_interaction(_pending_interact_pos)
		_has_pending_interact = false
	else:
		_change_state("Idle")
		_send_state_event("arrived")
		SignalBus.player_move_stopped.emit()

	# 发送信号
	moved.emit(global_position)
	SignalBus.player_position_updated.emit(global_position)


func _apply_friction(delta: float) -> void:
	# 应用摩擦力减速
	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _calculate_speed() -> float:
	var speed := base_speed

	# 根据目标位置的高度调整速度 (需要外部提供高度查询)
	# 这里暂时不实现高度相关逻辑，因为需要依赖未审阅的 WorldManager

	return speed


# =============================================================================
# 交互处理 (Interaction Processing)
# =============================================================================

func _process_interaction(_delta: float) -> void:
	# 交互状态的处理逻辑
	# 可以在这里添加交互动画等
	pass


func _execute_interaction(target_pos: Vector2) -> void:
	# 停止移动
	velocity = Vector2.ZERO
	_target_velocity = Vector2.ZERO

	# 面向交互目标
	var direction := (target_pos - global_position).normalized()
	if direction.length() > 0.1:
		_facing_direction = direction
		_update_sprite_direction()

	# 切换到交互状态
	_change_state("Interacting")
	_send_state_event("interact")

	# 发送交互信号
	interacted.emit(target_pos)

	# 交互完成后返回 Idle (可以添加延迟)
	_change_state("Idle")


# =============================================================================
# 区块追踪 (Chunk Tracking)
# =============================================================================

func _update_current_chunk() -> void:
	_current_chunk = _MapUtils.world_to_chunk(global_position)


func _check_chunk_change() -> void:
	var new_chunk := _MapUtils.world_to_chunk(global_position)

	if new_chunk != _current_chunk:
		var old_chunk := _current_chunk
		_current_chunk = new_chunk

		print("\n========== PLAYER CHUNK CHANGE ==========")
		print("[Player] Chunk changed: %s -> %s (pos: %s)" % [old_chunk, new_chunk, global_position])
		print("[Player] Emitting chunk_changed signal...")
		chunk_changed.emit(old_chunk, new_chunk)
		print("[Player] Emitting SignalBus.player_chunk_changed signal...")
		SignalBus.player_chunk_changed.emit(old_chunk, new_chunk)
		print("[Player] Signals emitted successfully")
		print("=========================================\n")


# =============================================================================
# 状态机辅助 (State Machine Helpers)
# =============================================================================

func _change_state(new_state: String) -> void:
	_current_state = new_state
	_play_movement_animation()


func _send_state_event(event_name: String) -> void:
	# 如果使用 StateChart 插件，发送事件
	if _state_chart and _state_chart.has_method("send_event"):
		_state_chart.send_event(event_name)


# =============================================================================
# 视觉更新 (Visual Updates)
# =============================================================================

func _update_sprite_direction() -> void:
	if _sprite == null:
		return

	# 根据水平速度方向翻转精灵
	if velocity.x < -0.1:
		_sprite.flip_h = true
	elif velocity.x > 0.1:
		_sprite.flip_h = false

	# 播放对应动画
	_play_movement_animation()


func _play_movement_animation() -> void:
	if _sprite == null:
		return

	var anim_name := "idle"
	# [修复] 改进移动状态判断
	# 优先使用状态机状态判断
	if _current_state == "Moving":
		anim_name = "walk"
	else:
		# 兜底：只要有移动意图 (导航未完成且目标未到达) 或 实际速度大于阈值，都视为移动中
		var is_moving := velocity.length() > 0.1
		if _nav_agent:
			if not _nav_agent.is_navigation_finished() and not _nav_agent.is_target_reached():
				is_moving = true

		if is_moving:
			anim_name = "walk"
		else:
			anim_name = "idle"

	if _sprite.animation != anim_name or not _sprite.is_playing():
		_sprite.play(anim_name)


# =============================================================================
# 工具方法 (Utility Methods)
# =============================================================================

## 获取摄像机控制器
func get_camera_rig():
	return _camera_rig


## 重置摄像机到玩家中心
func recenter_camera() -> void:
	if _camera_rig:
		_camera_rig.recenter_camera()
