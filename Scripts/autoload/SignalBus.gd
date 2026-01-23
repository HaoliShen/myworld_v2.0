## SignalBus.gd
## 全局信号总线 - 解耦各系统间的通信
## 对应文档: arch_01_managers.md
extends Node

# =============================================================================
# 区块生命周期信号 (Chunk Lifecycle Signals)
# =============================================================================

## 区块数据已加载到内存
signal chunk_data_loaded(chunk_coord: Vector2i)

## 区块数据已从内存卸载
signal chunk_data_unloaded(chunk_coord: Vector2i)

## 区块节点已激活 (可见)
signal chunk_activated(chunk_coord: Vector2i)

## 区块节点已停用 (隐藏)
signal chunk_deactivated(chunk_coord: Vector2i)

## 区块数据已修改 (标记为脏)
signal chunk_modified(chunk_coord: Vector2i)

# =============================================================================
# 玩家相关信号 (Player Signals)
# =============================================================================

## 玩家进入新区块
signal player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i)

## 玩家位置更新
signal player_position_updated(world_position: Vector2)

## 玩家开始移动
signal player_move_started(direction: Vector2)

## 玩家停止移动
signal player_move_stopped()

# =============================================================================
# 输入相关信号 (Input Signals)
# =============================================================================

## 世界点击事件 (已转换为世界坐标)
signal world_clicked(world_position: Vector2, button: int)

## 世界拖拽事件
signal world_drag(delta: Vector2)

## 缩放请求
signal zoom_requested(direction: int)

## 交互请求
signal interact_requested(world_position: Vector2)

# =============================================================================
# 交互系统信号 (Interaction Signals)
# =============================================================================

## 实体被选中
signal entity_selected(entity: Node)

## 实体取消选中
signal entity_deselected()

## 地块被选中
signal tile_selected(tile_coord: Vector2i, layer: int)

## 交互执行
signal interaction_executed(target: Node, action: String)

## 命令发出 (用于生成地面点击特效等)
signal command_issued(command: String, target_pos: Vector2)

## 建造物品被选中 (从 UI 选择了建造物品)
signal build_item_selected(item_id: int)

## 请求切换背包
signal request_toggle_inventory()

## 请求切换建造菜单
signal request_toggle_build_menu()

# =============================================================================
# UI 系统信号 (UI System Signals)
# =============================================================================

## UI 模式变化 (Normal, Build 等)
signal ui_mode_changed(mode_name: String)

## 通知显示消息 (用于临时提示)
signal show_notification(message: String, duration: float)

## 请求打开面板
signal request_open_panel(panel_name: String)

## 请求关闭面板
signal request_close_panel(panel_name: String)

# =============================================================================
# 存档系统信号 (Save System Signals)
# =============================================================================

## 开始保存
signal save_started()

## 保存完成
signal save_completed()

## 开始加载
signal load_started()

## 加载完成
signal load_completed()

## 自动保存触发
signal auto_save_triggered()

# =============================================================================
# 世界管理信号 (World Management Signals)
# =============================================================================

## 世界初始化完成
signal world_initialized(seed: int)

## 世界准备就绪 (可以开始游戏)
signal world_ready()

## 请求生成区块
signal chunk_generation_requested(chunk_coord: Vector2i)

## 区块生成完成
signal chunk_generation_completed(chunk_coord: Vector2i)

# =============================================================================
# 地形修改信号 (Terrain Modification Signals)
# =============================================================================

## 地形高度修改
signal terrain_elevation_changed(tile_coord: Vector2i, old_elevation: int, new_elevation: int)

## 地形类型修改
signal terrain_type_changed(tile_coord: Vector2i, old_type: int, new_type: int)

## 物体放置
signal object_placed(tile_coord: Vector2i, object_id: int)

## 物体移除
signal object_removed(tile_coord: Vector2i, object_id: int)
