# 重构 Constants.gd 与地图系统对齐计划

## 1. 重构 Constants.gd
将所有魔术数字和逻辑映射整合为配置表。
### 地面配置 (Ground)
- 统一定义 `GROUND_SOURCE_ID = 2` 和 `GROUND_TERRAIN_SET = 0`。
- 建立 `HEIGHT_TO_TERRAIN` 字典，实现 `高度 -> 地形ID` 的直接查表。

### 物体配置 (Objects)
- **ID表**: `OBJECT_ID_TABLE` (名称 -> ID)。
- **资源表**: `OBJECT_RESOURCE_TABLE` (ID -> {source_id, atlas_coords})。
- **层级表**: `OBJECT_RENDER_LAYER_TABLE` (ID -> Layer)。

## 2. 简化 MapGenerator.gd
- `_sample_terrain`: 仅计算高度值，通过 `Constants.HEIGHT_TO_TERRAIN` 获取地形 ID。
- `_try_place_object`: 使用 `OBJECT_ID_TABLE` 中的 ID 进行生成逻辑。

## 3. 简化 GlobalMapController.gd
- `render_chunk`: 使用新的地面常量。
- `_set_object_cell`: 移除所有 `match` 和辅助函数，改为从 `OBJECT_RESOURCE_TABLE` 和 `OBJECT_RENDER_LAYER_TABLE` 进行单次查表。

## 4. 验证与对齐
- 确保地面层显示正常。
- 确认物体层由于 `source_id = -1` 而正确跳过渲染，但保留逻辑 ID 以供后续导航检测。
- 检查导航网格生成情况。
