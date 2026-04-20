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

## 物体已放置 (Decoration/Obstacle 等对象层)
signal object_placed(tile_coord: Vector2i, tile_id: int)

## 物体已移除 (Decoration/Obstacle 等对象层)
signal object_removed(tile_coord: Vector2i, tile_id: int)

# =============================================================================
# 玩家相关信号 (Player Signals)
# =============================================================================

## 玩家进入新区块
signal player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i)

## 玩家位置更新
signal player_position_updated(world_position: Vector2)

# =============================================================================
# 交互系统信号 (Interaction Signals)
# =============================================================================

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

## 请求切换建造菜单
signal request_toggle_build_menu()

# =============================================================================
# UI 系统信号 (UI System Signals)
# =============================================================================

## UI 模式变化 (Normal, Build 等)
signal ui_mode_changed(mode_name: String)

## 请求打开暂停菜单（InteractionManager 在 NORMAL 模式且无选中时从 ESC 转发）
signal pause_menu_requested()

# =============================================================================
# 存档系统信号 (Save System Signals)
# =============================================================================

## 保存完成
signal save_completed()

# =============================================================================
# 世界管理信号 (World Management Signals)
# =============================================================================

## 世界初始化完成
signal world_initialized(seed: int)
