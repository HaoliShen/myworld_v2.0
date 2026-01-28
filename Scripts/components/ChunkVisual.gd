class_name ChunkVisual
extends Node2D

# 预加载依赖
const _C = preload("res://Scripts/data/Constants.gd")

# 子节点引用
var ground_layer: TileMapLayer
var decoration_layer: TileMapLayer
var obstacle_layer: TileMapLayer

# 初始化
func _init(tile_set: TileSet) -> void:
	# 开启 Y-Sort 以支持正确的遮挡关系
	y_sort_enabled = true
	
	# 1. 地面层 (Z = -10)
	ground_layer = TileMapLayer.new()
	ground_layer.name = "GroundLayer"
	ground_layer.tile_set = tile_set
	ground_layer.z_index = -10
	add_child(ground_layer)
	
	# 2. 装饰层 (Y-Sort)
	decoration_layer = TileMapLayer.new()
	decoration_layer.name = "DecorationLayer"
	decoration_layer.tile_set = tile_set
	decoration_layer.y_sort_enabled = true
	add_child(decoration_layer)
	
	# 3. 障碍层 (Y-Sort)
	obstacle_layer = TileMapLayer.new()
	obstacle_layer.name = "ObstacleLayer"
	obstacle_layer.tile_set = tile_set
	obstacle_layer.y_sort_enabled = true
	add_child(obstacle_layer)

## 应用预计算的视觉数据
## @param visual_data: 包含各层 cell 数据的字典
func apply_visual_data(visual_data: Dictionary) -> void:
	# 1. 应用地面层
	if visual_data.has("ground"):
		var g_data = visual_data["ground"]
		for i in range(g_data["cells"].size()):
			ground_layer.set_cell(
				g_data["cells"][i],
				g_data["sources"][i],
				g_data["coords"][i],
				g_data["alts"][i]
			)
			
	# 2. 应用物体层
	if visual_data.has("objects"):
		var o_data = visual_data["objects"]
		# Objects 格式: { layer_enum: [ {cell, source, coord, alt}, ... ] }
		
		for layer_id in o_data:
			var layer_node = _get_layer_by_enum(layer_id)
			if layer_node:
				for item in o_data[layer_id]:
					layer_node.set_cell(item.cell, item.source, item.coord)

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
