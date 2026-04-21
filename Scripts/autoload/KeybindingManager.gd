## KeybindingManager.gd
## 按键绑定管理器 - 持久化 InputMap 覆写
## 路径: res://Scripts/autoload/KeybindingManager.gd
## 类型: Autoload (Global Singleton)
##
## 职责:
## 1. 游戏启动时读 user://keybindings.cfg，把用户保存的绑定覆写到 InputMap
## 2. 提供 set_binding / reset / save API 给设置面板调用
## 3. 维护"默认绑定"快照（启动时从 project.godot 现状取），用于 reset_all
##
## 对外接口设计为"一次绑定一个事件"（不支持同一 action 多事件）。当前项目够用。
extends Node

# =============================================================================
# 信号
# =============================================================================

signal binding_changed(action: StringName, event: InputEvent)
signal bindings_reset()

# =============================================================================
# 配置
# =============================================================================

## 存储路径
const CONFIG_PATH: String = "user://keybindings.cfg"

## 白名单：哪些 action 允许重绑定（排除 ui_* 以避免 Godot 内置行为被破坏）
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"primary_action", &"secondary_action",
	&"zoom_in", &"zoom_out",
	&"interact",
	&"toggle_console", &"toggle_inventory", &"toggle_build_menu",
	&"toggle_dev_mode",
]

# =============================================================================
# 内部状态
# =============================================================================

## 项目默认绑定快照（启动时抓一次，用于 reset）
## Key: StringName -> Value: InputEvent (第一个事件；项目里每 action 只绑了一个)
var _default_bindings: Dictionary = {}


func _ready() -> void:
	_snapshot_defaults()
	_load_and_apply()


# =============================================================================
# 公共 API
# =============================================================================

## 返回所有可重绑定的 action 及其当前 InputEvent。
## [{ action: StringName, event: InputEvent, label: String }]
func list_bindings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in REBINDABLE_ACTIONS:
		var event := _get_primary_event(action)
		result.append({
			"action": action,
			"event": event,
			"label": event_to_string(event)
		})
	return result


## 为 action 设置新的唯一绑定（会清除该 action 的所有旧事件）。
## event 必须是 InputEventKey 或 InputEventMouseButton。
func set_binding(action: StringName, event: InputEvent) -> void:
	if not REBINDABLE_ACTIONS.has(action):
		push_warning("KeybindingManager: action not rebindable: %s" % action)
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		push_warning("KeybindingManager: unsupported event type for %s" % action)
		return

	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)
	_save()
	binding_changed.emit(action, event)


## 恢复所有可重绑定 action 到项目默认值。
func reset_all() -> void:
	for action in REBINDABLE_ACTIONS:
		var default_evt: InputEvent = _default_bindings.get(action)
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		if default_evt:
			InputMap.action_add_event(action, default_evt)
	_save()
	bindings_reset.emit()


## 把 InputEvent 转成人类可读的文本（按钮显示用）。
static func event_to_string(event: InputEvent) -> String:
	if event == null:
		return "—"
	if event is InputEventKey:
		var key := event as InputEventKey
		# 优先 physical_keycode（与键盘布局无关），否则用 keycode
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			return "—"
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT: return "Mouse Left"
			MOUSE_BUTTON_RIGHT: return "Mouse Right"
			MOUSE_BUTTON_MIDDLE: return "Mouse Middle"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse X1"
			MOUSE_BUTTON_XBUTTON2: return "Mouse X2"
			_: return "Mouse %d" % mb.button_index
	return str(event)


# =============================================================================
# 内部：启动时快照默认绑定
# =============================================================================

func _snapshot_defaults() -> void:
	for action in REBINDABLE_ACTIONS:
		_default_bindings[action] = _get_primary_event(action)


func _get_primary_event(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return null
	return events[0]


# =============================================================================
# 内部：持久化
# =============================================================================

func _load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return # 第一次跑/文件不存在，什么都不做，保持项目默认

	for action in REBINDABLE_ACTIONS:
		# 用 has_section_key 守护：Godot 4 的 get_value 传 null 默认值时仍会打 ERROR 日志
		# 新增的 action（如 toggle_dev_mode）在旧 cfg 里还没保存，直接跳过用项目默认
		if not cfg.has_section_key("bindings", String(action)):
			continue
		var packed = cfg.get_value("bindings", String(action))
		if packed == null:
			continue
		var event := _unpack_event(packed)
		if event == null:
			continue
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)


func _save() -> void:
	var cfg := ConfigFile.new()
	for action in REBINDABLE_ACTIONS:
		var event := _get_primary_event(action)
		if event == null:
			continue
		cfg.set_value("bindings", String(action), _pack_event(event))
	cfg.save(CONFIG_PATH)


## 把 InputEvent 打包成可写入 cfg 的 Dictionary
func _pack_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": k.physical_keycode,
			"keycode": k.keycode,
			"shift": k.shift_pressed,
			"ctrl": k.ctrl_pressed,
			"alt": k.alt_pressed,
			"meta": k.meta_pressed,
		}
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		return {
			"type": "mouse",
			"button_index": m.button_index,
		}
	return {}


func _unpack_event(packed: Variant) -> InputEvent:
	if not packed is Dictionary:
		return null
	var d := packed as Dictionary
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = d.get("physical_keycode", 0)
			k.keycode = d.get("keycode", 0)
			k.shift_pressed = d.get("shift", false)
			k.ctrl_pressed = d.get("ctrl", false)
			k.alt_pressed = d.get("alt", false)
			k.meta_pressed = d.get("meta", false)
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = d.get("button_index", 0)
			return m
	return null
