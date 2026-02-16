extends Node

# 预加载依赖的类
const _C = preload("res://Scripts/data/Constants.gd")
const _MapUtils = preload("res://Scripts/data/MapUtils.gd")

# =============================================================================
# 信号 (Signals)
# =============================================================================

signal selection_changed(entity: Node)
signal interaction_started(target: Node, action: String)
signal interaction_completed(target: Node, action: String)
signal mode_changed(new_mode: int)

# =============================================================================
# 枚举 (Enums)
# =============================================================================

## 交互模式状态机
enum Mode {
	NORMAL,      ## 普通模式 - 选中、移动、交互
	BUILD,       ## 建造模式 - 放置建筑
}

# =============================================================================
# 节点引用 (Node References)
# =============================================================================

## 状态机节点引用 (如果使用 Godot State Charts 插件)
@onready var state_chart: Node = $StateChart

# =============================================================================
# 核心属性 (Core Properties)
# =============================================================================

## 当前准备建造的物品 ID (仅在 BuildMode 有效)
var current_blueprint_id: int = -1

## 当前交互模式
var _current_mode: Mode = Mode.NORMAL

## WorldManager 引用
var _world_manager: Node = null

## InputManager 引用
var _input_manager: Node = null

## SelectionManager 引用
var _selection_manager: Node = null

# =============================================================================
# 生命周期 (Lifecycle)
# =============================================================================

func _ready() -> void:
	# 延迟初始化，确保其他节点已就绪
	call_deferred("_initialize")


func _initialize() -> void:
	_connect_input_signals()
	_connect_signalbus_signals()
	_cache_references()
	_selection_manager = get_node_or_null("/root/SelectionManager")
	if _selection_manager == null:
		push_error("InteractionManager: SelectionManager not found at /root/SelectionManager")


# =============================================================================
# 初始化 (Initialization)
# =============================================================================

## 连接 InputManager 的信号
func _connect_input_signals() -> void:
	_input_manager = get_node_or_null("/root/InputManager")
	if _input_manager == null:
		push_warning("InteractionManager: InputManager not found")
		return

	# 连接输入信号
	if _input_manager.has_signal("on_primary_click"):
		_input_manager.on_primary_click.connect(_on_primary_click)
	if _input_manager.has_signal("on_secondary_click"):
		_input_manager.on_secondary_click.connect(_on_secondary_click)
	if _input_manager.has_signal("on_cancel_action"):
		_input_manager.on_cancel_action.connect(_on_cancel_action)
	if _input_manager.has_signal("on_toggle_inventory"):
		_input_manager.on_toggle_inventory.connect(_on_toggle_inventory)
	if _input_manager.has_signal("on_toggle_build_menu"):
		_input_manager.on_toggle_build_menu.connect(_on_toggle_build_menu)


## 连接 SignalBus 的信号
func _connect_signalbus_signals() -> void:
	# 建造物品选择信号 (从 UI 触发)
	SignalBus.build_item_selected.connect(_on_build_item_selected)


## 缓存常用节点引用
func _cache_references() -> void:
	_world_manager = get_node_or_null("/root/World/Managers/WorldManager")


## 设置玩家引用 (已弃用，保留兼容性但不再存储单一引用)
## @param player: Player 实例
func set_player(player) -> void:
	pass
	# 自动选中玩家作为默认单位
	# if _selection_manager: _selection_manager.select_unit(player)


# =============================================================================
# 输入信号处理 (Input Signal Handlers)
# =============================================================================

## 主要点击 (左键)
func _on_primary_click(global_pos: Vector2) -> void:
	match _current_mode:
		Mode.NORMAL:
			_handle_normal_primary_click(global_pos)
		Mode.BUILD:
			_handle_build_primary_click(global_pos)


## 次要点击 (右键)
func _on_secondary_click(global_pos: Vector2) -> void:
	match _current_mode:
		Mode.NORMAL:
			_handle_normal_secondary_click(global_pos)
		Mode.BUILD:
			_cancel_build_mode()


## 取消操作 (ESC)
func _on_cancel_action() -> void:
	match _current_mode:
		Mode.NORMAL:
			_deselect()
		Mode.BUILD:
			_cancel_build_mode()


## 切换背包
func _on_toggle_inventory() -> void:
	if has_selection():
		SignalBus.request_toggle_inventory.emit()


## 切换建造菜单
func _on_toggle_build_menu() -> void:
	if has_selection():
		SignalBus.request_toggle_build_menu.emit()


## 建造物品被选中 (从 UI)
func _on_build_item_selected(item_id: int) -> void:
	_enter_build_mode(item_id)


# =============================================================================
# Normal 状态逻辑 (Normal Mode Logic)
# =============================================================================

## 处理普通模式下的左键点击
func _handle_normal_primary_click(global_pos: Vector2) -> void:
	# 1. 射线检测
	var hit_entity := _raycast_at_position(global_pos)

	if hit_entity:
		# 2. 击中实体 - 选中它
		if _selection_manager: _selection_manager.select_unit(hit_entity)
		
	else:
		# 3. 击中空地或 TileMap
		var selected_unit = _selection_manager.get_single_selected_unit() if _selection_manager else null
		if selected_unit:
			# 检查是否在交互范围内 (玩家所在瓦片九宫格)
			
			if _is_within_interaction_range(selected_unit, global_pos):
				# 在范围内：执行交互
				if selected_unit.has_method("command_interact"):
					# 这里需要传入一个虚拟的目标节点或者位置，目前假设 command_interact 只接受位置或者需要重构
					# 暂时为了兼容性，我们假设点击空地不触发交互，除非该位置有特定逻辑
					pass 
				
			else:
				# 超出范围：取消选中
				_deselect()
				
		else:
			# 选择瓦片
			var tile_coord := _MapUtils.world_to_tile(global_pos)
			_select_tile(tile_coord)


## 处理普通模式下的右键点击
func _handle_normal_secondary_click(global_pos: Vector2) -> void:
	var selected_units = _selection_manager.get_selected_units() if _selection_manager else []
	if not selected_units.is_empty():
		for unit in selected_units:
			# 命令单位移动到目标位置
			if unit.has_method("command_move_to"):
				unit.command_move_to(global_pos)
		
		# 发送命令信号 (用于生成地面点击特效)
		SignalBus.command_issued.emit("move", global_pos)


## 检查点击位置是否在单位交互范围内
func _is_within_interaction_range(unit: Node2D, global_pos: Vector2) -> bool:
	if unit == null:
		return false

	var unit_tile := _MapUtils.world_to_tile(unit.global_position)
	var target_tile := _MapUtils.world_to_tile(global_pos)

	# 计算瓦片距离 (切比雪夫距离)
	var tile_distance := _MapUtils.chebyshev_distance(unit_tile, target_tile)

	return tile_distance <= _C.INTERACTION_TILE_RANGE


# =============================================================================
# BuildMode 状态逻辑 (Build Mode Logic)
# =============================================================================

## 进入建造模式
func _enter_build_mode(blueprint_id: int) -> void:
	current_blueprint_id = blueprint_id
	_current_mode = Mode.BUILD
	mode_changed.emit(Mode.BUILD)

	# 发送状态机事件 (如果使用 StateChart)
	_send_state_event("build_requested")


## 处理建造模式下的左键点击
func _handle_build_primary_click(global_pos: Vector2) -> void:
	if current_blueprint_id < 0:
		return

	var tile_coord := _MapUtils.world_to_tile(global_pos)

	# 检查建造合法性
	if _check_build_validity(tile_coord, current_blueprint_id):
		# 合法：执行建造
		_execute_build(tile_coord, current_blueprint_id)
	else:
		# 不合法：可以播放错误音效
		pass


## 取消建造模式
func _cancel_build_mode() -> void:
	current_blueprint_id = -1
	_current_mode = Mode.NORMAL
	mode_changed.emit(Mode.NORMAL)

	# 发送状态机事件
	_send_state_event("cancel")


## 检查某个位置是否可以建造特定建筑
## @param tile_pos: 瓦片坐标
## @param blueprint_id: 建筑 ID
## @return: 是否可以建造
func _check_build_validity(tile_pos: Vector2i, blueprint_id: int) -> bool:
	if _world_manager == null:
		return false

	# 获取目标位置的区块数据
	var world_pos := _MapUtils.tile_to_world_center(tile_pos)
	var chunk_data = _world_manager.get_chunk_data_at(world_pos)

	if chunk_data == null:
		return false

	# 计算局部坐标
	var local_coord := _MapUtils.tile_to_local(tile_pos)

	# 检查目标位置是否已被占用
	# 根据建筑类型确定目标层
	var target_layer := _get_blueprint_layer(blueprint_id)

	# 检查该层是否已有物体
	var existing_object = chunk_data.get_object(local_coord.x, local_coord.y, target_layer)
	if existing_object > 0:
		return false

	# 检查地形是否允许建造 (例如：不能在水上建造)
	var elevation = chunk_data.get_elevation(local_coord.x, local_coord.y)
	if elevation <= 0:
		return false

	return true


## 执行建造操作
func _execute_build(tile_pos: Vector2i, blueprint_id: int) -> void:
	if _world_manager == null:
		return

	var world_pos := _MapUtils.tile_to_world_center(tile_pos)
	var target_layer := _get_blueprint_layer(blueprint_id)

	# 调用 WorldManager 放置方块
	_world_manager.set_block_at(world_pos, target_layer, blueprint_id)


## 根据建筑 ID 获取目标层
func _get_blueprint_layer(blueprint_id: int) -> int:
	# 从 Constants 的映射表获取层级
	if _C.OBJECT_RENDER_LAYER_TABLE.has(blueprint_id):
		return _C.OBJECT_RENDER_LAYER_TABLE[blueprint_id]
	# 默认放置到装饰层
	return _C.Layer.DECORATION


# =============================================================================
# 选择逻辑 (Selection Logic)
# =============================================================================

## 选择实体 (已委托给 SelectionManager)
func _select_entity(entity: Node2D) -> void:
	if _selection_manager: _selection_manager.select_unit(entity)


## 选择瓦片
func _select_tile(tile_coord: Vector2i) -> void:
	_deselect()
	SignalBus.tile_selected.emit(tile_coord, _C.Layer.GROUND)


## 取消选择
func _deselect() -> void:
	if _selection_manager: _selection_manager.clear_selection()
	SignalBus.entity_deselected.emit()
	selection_changed.emit(null)


## 检查是否有单位被选中
func has_selection() -> bool:
	return _selection_manager.has_selection() if _selection_manager else false


# =============================================================================
# 物理射线检测 (Physics Raycast)
# =============================================================================

## 在指定位置执行物理射线检测
## @param global_pos: 世界坐标
## @return: 检测到的实体，如果没有则返回 null
func _raycast_at_position(global_pos: Vector2) -> Node2D:
	var viewport := get_viewport()
	if viewport == null:
		return null

	var space_state := viewport.get_world_2d().direct_space_state
	if space_state == null:
		return null

	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_pos
	query.collision_mask = _C.PhysicsLayer.ENTITIES | _C.PhysicsLayer.INTERACTABLES  # 8 | 2 = 10

	var results := space_state.intersect_point(query, 1)

	if not results.is_empty():
		var collider = results[0].collider
		if collider is Node2D:
			return collider

	return null


# =============================================================================
# 交互逻辑 (Interaction Logic)
# =============================================================================

## 与实体交互
func _interact_with(entity: Node2D) -> void:
	if entity == null:
		return

	var action := _determine_action(entity)
	interaction_started.emit(entity, action)
	
	# 获取当前选中的单位去执行交互
	var unit = _selection_manager.get_single_selected_unit() if _selection_manager else null
	if unit and unit.has_method("command_interact"):
		unit.command_interact(entity)

	interaction_completed.emit(entity, action)
	SignalBus.interaction_executed.emit(entity, action)


## 确定交互动作
func _determine_action(entity: Node2D) -> String:
	if entity.has_method("get_available_actions"):
		var actions: Array = entity.get_available_actions()
		if not actions.is_empty():
			return actions[0]
	return "interact"


# =============================================================================
# 状态机辅助 (State Machine Helpers)
# =============================================================================

## 发送状态机事件
func _send_state_event(event_name: String) -> void:
	if state_chart and state_chart.has_method("send_event"):
		state_chart.send_event(event_name)


# =============================================================================
# 公共接口 (Public API)
# =============================================================================

## 获取当前选中的实体
func get_selected_entity() -> Node2D:
	return _selection_manager.get_single_selected_unit() if _selection_manager else null


## 获取当前交互模式
func get_current_mode() -> Mode:
	return _current_mode


## 设置交互模式
func set_mode(mode: Mode) -> void:
	if mode == Mode.BUILD and current_blueprint_id < 0:
		push_warning("InteractionManager: Cannot enter BUILD mode without blueprint")
		return

	_current_mode = mode
	mode_changed.emit(mode)


## 获取玩家引用 (保留兼容性，实际上返回当前选中的单位)
func get_player():
	return _selection_manager.get_single_selected_unit() if _selection_manager else null
