@tool
extends EditorScript
##用于讲一个tileset中几个相同的图块源全部画上形状一样的掩码
# ================= 配置区域 (请修改这里) =================

# 1. TileSet 资源路径
const TILESET_PATH = "res://Assets/Tilesets/test_tileset.tres"

# 2. 【模板源】已经画好遮罩的 Source ID
const TEMPLATE_SOURCE_ID = 2

# 3. 【模板地形 ID】模板源里使用的是哪个地形 ID？
# (例如：你在 ID=1 的图里画的是“草地”，草地在地形列表排第0，这里就填0)
const TEMPLATE_TERRAIN_ID = 0

# 4. 【目标配置】格式：{ 目标SourceID : 目标TerrainID }
# 意思：把模板复制给 Source ID 2，设为地形 1；复制给 Source ID 3，设为地形 2
const TARGETS = {
	7: 1,  # 比如：Source 2 是“雪地”，对应地形列表 ID 1
	5: 2   # 比如：Source 3 是“沙漠”，对应地形列表 ID 2
}

# 5. 地形集合 Set ID (默认通常是 0)
const TERRAIN_SET = 0

# =======================================================

func _run():
	# 1. 加载资源
	var tileset = load(TILESET_PATH) as TileSet
	if not tileset:
		push_error("错误：找不到 TileSet 文件，请检查路径。")
		return

	# 2. 获取模板源
	var source_template = tileset.get_source(TEMPLATE_SOURCE_ID) as TileSetAtlasSource
	if not source_template:
		push_error("错误：找不到模板 Source ID: %d" % TEMPLATE_SOURCE_ID)
		return

	print("--- 开始批量复制地形遮罩 ---")
	print("模板源: ID %d (地形 ID %d)" % [TEMPLATE_SOURCE_ID, TEMPLATE_TERRAIN_ID])

	# 3. 遍历每一个目标配置
	for target_source_id in TARGETS:
		var target_terrain_id = TARGETS[target_source_id]
		
		var source_target = tileset.get_source(target_source_id) as TileSetAtlasSource
		if not source_target:
			push_warning("跳过：找不到目标 Source ID %d" % target_source_id)
			continue
			
		print("正在处理 -> 目标源 ID: %d (应用地形 ID: %d)..." % [target_source_id, target_terrain_id])
		
		# 4. 执行复制逻辑
		_copy_bits(source_template, source_target, target_terrain_id)

	print("--- 全部完成！请保存资源并可能需要重启项目以刷新编辑器显示 ---")


func _copy_bits(src: TileSetAtlasSource, dst: TileSetAtlasSource, target_terrain_id: int):
	# 遍历模板源中的所有图块
	for tile_idx in src.get_tiles_count():
		var coord = src.get_tile_id(tile_idx)
		
		# 如果目标源在这个坐标没有图块，就跳过（防止报错）
		if not dst.has_tile(coord):
			continue
			
		var data_src = src.get_tile_data(coord, 0)
		var data_dst = dst.get_tile_data(coord, 0)
		
		# 设置目标图块的地形归属
		data_dst.terrain_set = TERRAIN_SET
		data_dst.terrain = target_terrain_id
		
		# 定义所有需要检查的方向
		var neighbors = [
			TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
			TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_TOP_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
		]
		
		# 逐个方向检查位掩码
		for side in neighbors:
			var src_bit = data_src.get_terrain_peering_bit(side)
			
			# 核心逻辑：只有当模板的这个方向设置了“模板地形ID”时，我们才在目标里设置“目标地形ID”
			if src_bit == TEMPLATE_TERRAIN_ID:
				data_dst.set_terrain_peering_bit(side, target_terrain_id)
			else:
				# 保持为空，或者在这里强制设为 -1 (看你需求，通常不设就行)
				# data_dst.set_terrain_peering_bit(side, -1) 
				pass
