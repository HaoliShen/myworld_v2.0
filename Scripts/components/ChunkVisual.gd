class_name ChunkVisual
extends Node2D

# 预加载依赖
const _C = preload("res://Scripts/data/Constants.gd")

# 子节点引用
var ground_layer: TileMapLayer
var decoration_layer: TileMapLayer
var obstacle_layer: TileMapLayer
var navigation_layer: TileMapLayer

# 初始化
func _init(tile_set: TileSet = null) -> void:
	# 如果是从 PackedScene 实例化，节点已经存在，不需要 new
	# 但如果是纯代码 new，则需要创建 (兼容旧逻辑，或后续重构掉)
	if get_child_count() > 0:
		_setup_references()
		return
	

func _ready() -> void:
	if not ground_layer:
		_setup_references()

func _setup_references() -> void:
	ground_layer = get_node_or_null("GroundLayer")
	decoration_layer = get_node_or_null("DecorationLayer")
	obstacle_layer = get_node_or_null("ObstacleLayer")
	navigation_layer = get_node_or_null("NavigationLayer")


## 应用预计算的视觉数据
## @param visual_data: 包含各层 cell 数据的字典
func apply_visual_data(visual_data: Dictionary) -> void:
	# 确保引用已设置
	if not ground_layer:
		_setup_references()
	
	var groundst=Time.get_ticks_usec()
	# 1. 应用地面层
	if visual_data.has("ground"):
		var g_data = visual_data["ground"]
		# print("ChunkVisual: Applying %s ground cells to %s" % [g_data["cells"].size(), ground_layer])
		for i in range(g_data["cells"].size()):
			ground_layer.set_cell(
				g_data["cells"][i],
				g_data["sources"][i],
				g_data["coords"][i],
				g_data["alts"][i]
			)
			
	var groundend=Time.get_ticks_usec()
	#print("ground:", groundend-groundst)
			
	# 2. 应用物体层
	if visual_data.has("objects"):
		var o_data = visual_data["objects"]
		# Objects 格式: { layer_enum: [ {cell, source, coord, alt}, ... ] }
		
		for layer_id in o_data:
			var layer_node = _get_layer_by_enum(layer_id)
			if layer_node:
				for item in o_data[layer_id]:
					layer_node.set_cell(item.cell, item.source, item.coord)

	var navst=Time.get_ticks_usec()
	# 3. 应用导航层
	if visual_data.has("navigation") and navigation_layer:
		var n_data = visual_data["navigation"]
		var source_id = n_data["source"]
		for i in range(n_data["cells"].size()):
			navigation_layer.set_cell(
				n_data["cells"][i],
				source_id,
				n_data["coords"][i]
			)
	var navend=Time.get_ticks_usec()
	#print("navi:",navend-navst)

## 单点设置 (用于运行时修改)
func set_block(local_pos: Vector2i, layer_enum: int, source_id: int, atlas_coord: Vector2i, alt_id: int = 0) -> void:
	var layer = _get_layer_by_enum(layer_enum)
	if layer:
		if source_id == -1:
			layer.erase_cell(local_pos)
		else:
			layer.set_cell(local_pos, source_id, atlas_coord, alt_id)

func _get_layer_by_enum(layer_enum: int) -> TileMapLayer:
	match layer_enum:
		_C.Layer.GROUND: return ground_layer
		_C.Layer.DECORATION: return decoration_layer
		_C.Layer.OBSTACLE: return obstacle_layer
	return null

### 清除所有内容 (用于对象池复用)
#func clear() -> void:
	#if not ground_layer: _setup_references()
	#if ground_layer: ground_layer.clear()
	#if decoration_layer: decoration_layer.clear()
	#if obstacle_layer: obstacle_layer.clear()
	#if navigation_layer: navigation_layer.clear()
