class_name ChunkVisual
extends Node2D

# 预加载依赖
const _C = preload("res://Scripts/data/Constants.gd")

# 子节点引用
var ground_layer: TileMapLayer
var exh1_layer: TileMapLayer
var exh2_layer: TileMapLayer
var exh3_layer: TileMapLayer
var exh4_layer: TileMapLayer
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
	exh1_layer = get_node_or_null("ExH1Layer")
	exh2_layer = get_node_or_null("ExH2Layer")
	exh3_layer = get_node_or_null("ExH3Layer")
	exh4_layer = get_node_or_null("ExH4Layer")
	decoration_layer = get_node_or_null("DecorationLayer")
	obstacle_layer = get_node_or_null("ObstacleLayer")
	navigation_layer = get_node_or_null("NavigationLayer")


## 应用预计算的视觉数据
## @param visual_data: 包含各层 cell 数据的字典
func apply_visual_data(visual_data: Dictionary) -> void:
	# 确保引用已设置
	if not ground_layer:
		_setup_references()
	
	# 1. 应用地形层 (Ground + ExH1-4)
	if visual_data.has("terrain"):
		var t_data = visual_data["terrain"]
		
		# Ground
		if t_data.has(0) and ground_layer:
			_apply_layer_data(ground_layer, t_data[0])
			
		# ExH1
		if t_data.has(1) and exh1_layer:
			_apply_layer_data(exh1_layer, t_data[1])
			
		# ExH2
		if t_data.has(2) and exh2_layer:
			_apply_layer_data(exh2_layer, t_data[2])
			
		# ExH3
		if t_data.has(3) and exh3_layer:
			_apply_layer_data(exh3_layer, t_data[3])
			
		# ExH4
		if t_data.has(4) and exh4_layer:
			_apply_layer_data(exh4_layer, t_data[4])

	# 2. 应用物体层
	if visual_data.has("objects"):
		var o_data = visual_data["objects"]
		# Objects 格式: { layer_enum: [ {cell, source, coord, alt}, ... ] }
		
		for layer_id in o_data:
			var layer_node = _get_layer_by_enum(layer_id)
			if layer_node:
				for item in o_data[layer_id]:
					layer_node.set_cell(item.cell, item.source, item.coord)

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

func _apply_layer_data(layer: TileMapLayer, data: Dictionary) -> void:
	# 批量设置
	if data.has("cells") and data["cells"].size() > 0:
		for i in range(data["cells"].size()):
			layer.set_cell(
				data["cells"][i],
				data["sources"][i],
				data["coords"][i],
				data["alts"][i]
			)

## 单点设置 (用于运行时修改)
func set_block(local_pos: Vector2i, layer_enum: int, source_id: int, atlas_coord: Vector2i, alt_id: int = 0) -> void:
	var layer = _get_layer_by_enum(layer_enum)
	
	# 如果是地形层 (目前 set_block 主要用于物体，如果用于地形需扩展)
	# 这里的 layer_enum 主要是 Constants.Layer (GROUND, DECORATION, OBSTACLE)
	# 如果需要动态修改 ExH 层，需要定义新的枚举或逻辑
	
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
		# 这里没有 ExH 层，因为 ExH 层通常不通过通用的 set_block 修改，而是通过地形工具
	return null

func get_height_layer(index: int) -> TileMapLayer:
	match index:
		1: return exh1_layer
		2: return exh2_layer
		3: return exh3_layer
		4: return exh4_layer
	return null
