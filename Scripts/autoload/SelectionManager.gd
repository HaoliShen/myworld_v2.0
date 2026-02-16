extends Node

# 信号
signal selection_changed(selected_units: Array[Node])
signal unit_selected(unit: Node)
signal unit_deselected(unit: Node)

# 当前选中的单位列表
var _selected_units: Array[Node] = []

# 配置
@export var max_selection_count: int = 0 # 0 表示无限

func _ready() -> void:
	# 确保在 Autoload 中运行
	process_mode = Node.PROCESS_MODE_ALWAYS

func select_unit(unit: Node, clear_previous: bool = true) -> void:
	if clear_previous:
		clear_selection()
	
	if unit in _selected_units:
		return
		
	if max_selection_count > 0 and _selected_units.size() >= max_selection_count:
		return
		
	_selected_units.append(unit)
	if unit.has_method("set_selected"):
		unit.set_selected(true)
		
	unit_selected.emit(unit)
	selection_changed.emit(_selected_units)

func deselect_unit(unit: Node) -> void:
	if unit in _selected_units:
		_selected_units.erase(unit)
		
		if unit.has_method("set_selected"):
			unit.set_selected(false)
			
		unit_deselected.emit(unit)
		selection_changed.emit(_selected_units)

func clear_selection() -> void:
	for unit in _selected_units:
		if is_instance_valid(unit) and unit.has_method("set_selected"):
			unit.set_selected(false)
			
	_selected_units.clear()
	selection_changed.emit(_selected_units)

func get_selected_units() -> Array[Node]:
	# 返回副本以防外部修改
	return _selected_units.duplicate()

func has_selection() -> bool:
	return not _selected_units.is_empty()

func get_single_selected_unit() -> Node:
	if _selected_units.size() == 1:
		return _selected_units[0]
	return null
