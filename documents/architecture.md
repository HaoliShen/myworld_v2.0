# MyWorld v2.0 架构文档

版本: 当前代码（main 分支 `b82e9f0` 之后）
引擎: **Godot 4.6** Forward+ 渲染
语言: GDScript
主场景入口: `res://Scenes/Main/World.tscn`（根目录 `world.tscn` 为历史残留，勿使用）

---

## 1. 顶层结构

```
myworld_v2.0/
├── Assets/                  美术、音频、Tileset 资源
├── Scenes/
│   ├── Main/                World.tscn / Chunk.tscn / ChunkLogic.tscn
│   ├── Entities/            Player / HumanNPC / TreeEntity / GrassEntity / StoneEntity
│   └── UI/                  HUD / BuildMenu / DebugPanel / TileInfoPanel
├── Scripts/
│   ├── autoload/            SignalBus / InputManager / SaveSystem / RegionDatabase / SelectionManager
│   ├── data/                Constants / MapUtils / ChunkData
│   ├── world_scene/         WorldManager / MapGenerator / GlobalMapController / InteractionManager
│   │                        ChunkLogic / ChunkVisual / TerrainObjectManager
│   ├── entity/
│   │   ├── entity_root/     Player / HumanNPC / TreeEntity / GrassEntity / StoneEntity
│   │   ├── interaction/     InteractionComponent + human/*(Behaviors, HealthComponent,
│   │   │                    MovementController) + tree/BeHitComponent
│   │   ├── animation/       AnimationComponent / AnimationController / AnimationLogic
│   │   │                    + human/*（Idle/Run/Chop/Mine/Gather/Attack）
│   │   │                    + tree/* + common/（SimpleHit/SimpleDie）
│   │   └── ai/              NPCBrain
│   ├── player_scene/        CameraRig / ShadowGenerator
│   ├── UI/                  HUD / BuildMenu / DebugPanel / TileInfoPanel
│   └── dev_tools/           auto_tile / tileset_bit_copy（编辑器辅助）
├── addons/                  better-terrain / godot-console / godot-sqlite /
│                            godot_mcp / godot_state_charts / phantom_camera
├── documents/               当前文档
├── outdated/                过时文档归档（不入库）
├── skills_created/          Claude skill 源目录（参见第 9 节）
└── godot-entity-manager.skill   打包后的 Claude skill（参见第 9 节）
```

---

## 2. 自动加载单例

在 `project.godot` [autoload] 中注册，位于 `/root/` 下：

| 名称 | 脚本 | 职责 |
| :-- | :-- | :-- |
| `SignalBus` | `Scripts/autoload/SignalBus.gd` | 全局信号总线，所有跨系统事件在这里汇总 |
| `SaveSystem` | `Scripts/autoload/SaveSystem.gd` | 存档目录、世界元数据（`world.ini`）、增删查改存档 |
| `InputManager` | `Scripts/autoload/InputManager.gd` | 鼠键事件 → 语义信号；UI 过滤；相机缩放/拖拽；点击/拖拽判定 |
| `RegionDatabase` | `Scripts/autoload/RegionDatabase.gd` | SQLite 区域分片持久化（每 32×32 区块一个 `.rg` 文件，16 连接 LRU 池） |
| `SelectionManager` | `Scripts/autoload/SelectionManager.gd` | 单选/多选 RTS 管理（当前尚无框选拖拽） |
| `KeybindingManager` | `Scripts/autoload/KeybindingManager.gd` | 按键绑定持久化；启动时读 `user://keybindings.cfg` 覆写 InputMap |
| `PhantomCameraManager` | 插件提供 | Phantom Camera 插件单例 |
| `BetterTerrain` | 插件提供 | Better Terrain 运行时支持 |
| `Console` | 插件提供 | 调试控制台（\` 键切换） |

---

## 3. 启动流程 & 主菜单

**入口**：`project.godot` 的 `run/main_scene = Scenes/Main/MainMenu.tscn`。
游戏从主菜单进入，不再直接跑 `World.tscn`；若强行跑 `World.tscn`，`WorldManager`
检测到 `SaveSystem.current_world_name` 为空会 `push_error` 并跳回主菜单。

```
MainMenu.tscn                              ← run/main_scene
└── Control（根，script=MainMenu.gd）
    ├── 主按钮页：开始游戏 / 设置 / 退出   ← 程序化构建
    ├── SaveSlotPanel                     ← 存档选择 + 新建 + 详情 + 删除
    └── SettingsPanel                     ← 设置（目前只有按键重绑）
```

**进入游戏的两条路径**：
1. 选中已有存档 → Start → `SaveSystem.load_world(name)` → `change_scene_to_file(World.tscn)`
2. 新建世界 → 填写 world_name + seed（可空=随机） → `SaveSystem.create_world` → 进入 World.tscn

**退回主菜单**：World 场景里按 ESC（无选中、无建造时）→ `InteractionManager` 发
`SignalBus.pause_menu_requested` → `PauseMenu` 弹出（`get_tree().paused=true`）→
"回主菜单" 按钮先 `WorldManager.force_save_all()` 再切场景。

---

## 3.5 主场景 World.tscn 结构

```
World (Node)
├── Managers (Node)
│   ├── WorldManager (Node)                         ← Scripts/world_scene/WorldManager.gd
│   │   ├── MapGenerator (Node)                     ← MapGenerator.gd
│   │   └── ActiveChunks (Node)                     ← ChunkLogic 挂载点（动态）
│   ├── InteractionManager (Node)                   ← world_scene/InteractionManager.gd
│   │   └── StateChart (godot_state_charts)
│   │       └── Root  initial_state = "Normal"
│   │           ├── Normal  → "build_requested" → BuildMode
│   │           └── BuildMode  → "cancel" → Normal
│   └── TerrainObjectManager (Node)                 ← TerrainObjectManager.gd
├── Environment (Node2D, y_sort=true)               ← GlobalMapController.gd
│   ├── Camera2D
│   │   └── PhantomCameraHost
│   └── EntityContainer (Node2D, y_sort=true)       ← 动态实体（Player/NPC/物化资源）挂这里
└── UI (CanvasLayer)
    ├── HUD / DebugPanel / BuildMenu / TileInfoPanel
    ├── DebugConsole / DebugOutput
    └── PauseMenu (script=PauseMenu.gd)           ← 默认隐藏，ESC 触发
```

注意：**TileMapLayer 不再挂在 Environment 下**（老文档的写法）。每个区块是一个独立的
`ChunkVisual` 场景（`Scenes/Main/Chunk.tscn`）实例，由 `GlobalMapController` 动态加挂。

---

## 4. 世界/区块系统（三层流式加载）

### 4.1 关键常量（`Scripts/data/Constants.gd`）

| 常量 | 值 | 说明 |
| :-- | :-- | :-- |
| `TILE_SIZE` | 16 | 每 tile 像素 |
| `CHUNK_SIZE` | 32 | 每区块 tile 数（32×32 = 1024×1024 px） |
| `CHUNK_DATA_SIZE` | 34 | 带 1 圈邻居 padding 的存储大小 |
| `REGION_SIZE` | 32 | 每 region 文件包含的区块数 |
| `ACTIVE_LOAD_RADIUS` | 1 | 需要 ChunkLogic 节点的 Chebyshev 距离 |
| `READY_LOAD_RADIUS` | 2 | 需要渲染 ChunkVisual 的距离 |
| `DATA_LOAD_RADIUS` | 8 | 需要把 ChunkData 装进内存的距离 |

物理层（`PhysicsLayer` 枚举）：GROUND=1 / INTERACTABLES=2 / OBSTACLES=4 / ENTITIES=8。
渲染层（`Layer` 枚举）：GROUND=0 / DECORATION=1 / OBSTACLE=2。
资源 ID：`ID_GRASS=200`、`ID_TREE=300`、`ID_STONE=400`。

### 4.2 三层语义

| 层 | 存什么 | 由谁管 |
| :-- | :-- | :-- |
| **Data** | `ChunkData`（纯数据，RefCounted），可序列化为 `PackedByteArray` | `WorldManager.loaded_data` dict |
| **Ready** | `ChunkVisual` 节点（`Chunk.tscn`），含 7 个 TileMapLayer 子节点 | `GlobalMapController.active_chunks` dict |
| **Active** | `ChunkLogic` 节点（锚点，目前业务为空壳） | `WorldManager.active_nodes` dict |

`ChunkVisual` 的 7 层 TileMapLayer：
`GroundLayer` → `ExH1Layer..ExH4Layer`（四层伪高度）→ `DecorationLayer` → `ObstacleLayer` → `NavigationLayer`（隐藏）。

### 4.3 加载/卸载主循环

触发：`Player._physics_process` 移动后调用 `WorldManager.set_player_position()`，
或直接发 `SignalBus.player_chunk_changed`，进入
`WorldManager.update_chunks()`：

1. 数据层：`data_range` 内未加载的 → 入 `_pending_loads`，`WorkerThreadPool` 后台跑
   `_load_chunk_task`（先查 `RegionDatabase`，未命中回落 `MapGenerator.generate_chunk`）。
2. 完成回主线程 `_on_chunk_data_ready` → 存入 `loaded_data` → 发 `chunk_data_loaded`。
3. 渲染层：`ready_range` 内的 → `GlobalMapController.render_chunk()`（后台计算 bitmask，
   主线程每帧 4 ms 预算 apply 到 `ChunkVisual`）。
4. 逻辑层：`active_range` 内的 → 实例化 `ChunkLogic` 挂到 `ActiveChunks`。
5. 离开各自半径时：销毁 ChunkLogic、调用 `clear_chunk()` 卸视觉、
   `is_dirty` 的写回 SQLite 后从 `loaded_data` 抹掉。

数据层有一个 `_data_load_center` 迟滞机制（偏移 `DATA_UPDATE_THRESHOLD_OFFSET`），
只有当玩家离中心足够远时才重算 data_range，减少抖动。

### 4.4 `ChunkData` 格式（`Scripts/data/ChunkData.gd`）

```
coord:          Vector2i
base_layer:     PackedByteArray  (34×34，含 padding)
height_layers:  Array[PackedByteArray]  (4 层，对应 ExH1..ExH4)
object_map:     Dictionary  { packed_coord(int) → tile_id(int) }  —— 稀疏
is_dirty:       bool
```

`to_bytes()` / `from_bytes()` 对应 `RegionDatabase` 里 `chunks(pos_x, pos_y, data BLOB, timestamp)`
表的 BLOB 字段。

### 4.5 地形生成（`MapGenerator.gd`）

4 组 FastNoiseLite，由 `world_seed` 派生：

| 噪声 | 频率 | 用途 |
| :-- | :-- | :-- |
| `_terrain_noise` | 0.01 SIMPLEX | 基础地形（水/沙/草/土） |
| `_elevation_noise` | 0.01 SIMPLEX RIDGED | 4 层伪高度阈值 |
| `_moisture_noise` | 0.008 SIMPLEX | 森林/草原判定 |
| `_scatter_noise` | 0.5 SIMPLEX | 树/草/石散布 |

散布规则按 `elevation_layer`（最高高度层）和 `base_id` 分支：高处多石、低处多植被，
沙地几乎不长东西；森林（moisture 高）提升 tree 概率；同一格最多一个物件。

### 4.6 `GlobalMapController`

- 启动时构建**地形查找表**（terrain_set × terrain × bitmask → atlas 坐标），来自
  `res://Assets/Tilesets/test_tileset.tres`。
- `render_chunk()` 派发后台任务算每格 8 邻接 bitmask、查表得 atlas，生成
  `ChunkVisual` 实例放入 `_render_queue`。
- `_process()` 按帧预算（`MAX_RENDER_TIME_PER_FRAME_US` = 4 ms）从队列取一个挂到
  Environment 下并 `apply_visual_data()`。
- `set_cell_at()` 提供单格编辑，只重算 3×3 邻居的 bitmask。

### 4.7 `TerrainObjectManager`

把 `ChunkData.object_map` 里的 tile 按需物化成实体（`TreeEntity/StoneEntity/GrassEntity`）：

- `request_interaction(tile_pos, layer)`：命中则复用缓存；否则实例化场景、放到 world 坐标、
  **隐藏原 tile** (`set_cell_at(..., -1)`)，并连 `interaction_finished` / `died`。
- `scan_for_objects(center, radius, tag)`：同时扫描已物化的实体和静态 tile，按距离排序返回——
  `NPCBrain` 用它找活干。
- `_on_entity_died()`：写回 `object_map` 为 -1、实体 `queue_free`。

### 4.8 `SaveSystem` + `RegionDatabase`

- `SaveSystem` 目前**硬编码** `save_path = "D:/mygames_all_ver/mwv2.0_save"`（覆盖配置文件），
  世界根目录下写 `world.ini`（名字、种子、版本、时间）和 `regions/r.{X}.{Y}.rg`。
- `RegionDatabase` 维护最多 16 个 SQLite 连接的 LRU 池，互斥锁包裹，表结构：
  `chunks(pos_x INTEGER, pos_y INTEGER, data BLOB, timestamp INTEGER, PRIMARY KEY(pos_x,pos_y))`。
- `load_chunk_blob` / `save_chunk_blob` 是底层；`load_chunk` / `save_chunk` 在其上做
  `ChunkData` 序列化。

---

## 5. 交互 / 实体架构（组件化，已脱离旧 StateChart 方案）

### 5.1 实体根节点

| 实体 | 基类 | 主要子节点 |
| :-- | :-- | :-- |
| `Player` | `CharacterBody2D` | `InteractionComponent` + `AnimationComponent` + `Visuals` + `NavigationAgent2D` + `CameraRig` |
| `HumanNPC` | `CharacterBody2D` | 同上 + `NPCBrain`（无 `CameraRig`） |
| `TreeEntity` / `GrassEntity` / `StoneEntity` | `Node2D` | `InteractionComponent`（挂 `BeHitComponent`）+ `AnimationComponent`（统一挂 `SimpleHit/SimpleDieLogic`）+ `HealthComponent`；action 分别为 `chop` / `gather` / `mine` |

重要：`InteractionComponent` 是**分发器 + 门面**，不是状态机；真正的动画状态机是
`AnimationComponent`。

### 5.2 交互分发（主动方）

`Scripts/entity/interaction/InteractionComponent.gd`

- `interact(target)`：停当前 behavior → 遍历子 `BaseInteractionBehavior`，找第一个
  `can_handle(target)` 为 true 的执行。
- `move_to(pos)`：先停交互再派发给 `MovementController`。
- `receive_interaction(ctx)`：被动入口，转给 `BeHitComponent` 处理。
- 对外信号：`interaction_started` / `interaction_stopped` / `interaction_finished`
  / `damaged` / `died` / `movement_started` / `movement_stopped` / `animation_requested`。

#### Behaviors（`Scripts/entity/interaction/human/`）

`BaseInteractionBehavior` 是所有行为的根。**循环型行为** Chop/Gather/Mine 共享
`LoopingActionBehavior` 基类（提供 timer + 抢锁 + 动画请求 + 信号收尾的完整骨架），
子类只声明 `_get_default_action_name()`；未来按工具/技能分化差异化逻辑时，
覆盖基类的扩展点即可：

| 行为 | 继承 | action | 说明 |
| :-- | :-- | :-- | :-- |
| `AttackBehavior` | `BaseInteractionBehavior` | `&"attack"` | 单次：发伤害上下文一次即结束 |
| `ChopBehavior` | `LoopingActionBehavior` | `&"chop"` | 砍树 |
| `MineBehavior` | `LoopingActionBehavior` | `&"mine"` | 采石 |
| `GatherBehavior` | `LoopingActionBehavior` | `&"gather"` | 采草 |
| `NPCInteractionBehavior` | `BaseInteractionBehavior` | `&"talk"` | 对话，调对方 `on_interact_start` 钩子 |

`LoopingActionBehavior` 提供的覆盖点（子类按需重写，默认实现与旧 Chop/Gather/Mine 等价）：

| Hook | 默认 | 典型扩展 |
| :-- | :-- | :-- |
| `_get_default_action_name()` | `&""` | 子类必写，返回 `&"chop"` 等 |
| `_compute_damage()` | `base_damage` | 读工具 tier/技能加成 |
| `_compute_interval()` | `interval` | 工具速度加成、疲劳度惩罚 |
| `_build_context(target)` | `{action, instigator, damage}` | 追加 `tool_id` / `swing_strength` 等 |
| `_on_hit_applied(target, ctx)` | 无 | 扣工具耐久、加技能经验、播粒子 |
| `_can_continue()` | `true` | 背包满 / 饥饿耗尽时返回 false 结束循环 |
| `_on_target_destroyed(target)` | 无 | 生成掉落物（原木 / 矿石 / 草束） |

### 5.3 被击/协议（被动方）

- `HealthComponent`（`entity/interaction/human/HealthComponent.gd`）——纯血量状态，
  信号 `health_changed` / `damaged(amount, source)` / `died` / `healed`。
- `BeHitComponent`（`entity/interaction/tree/BeHitComponent.gd`）——**交互协议**：
  - `actions: Array[StringName]` 声明可接受动作白名单（如 `[&"chop"]`）。
  - 用 `current_interactor` 做**互斥锁**，`try_lock/unlock`。
  - `interact(ctx)`：加锁 → 校验 action ∈ actions → 校验距离
    ≤ `interaction_range` → 发 `action_received(ctx)`。
- `InteractionComponent` 收到 `action_received` 后从 context 取 `damage` 调用
  `HealthComponent.take_damage(damage, instigator)`。

### 5.4 动画（`Scripts/entity/animation/`）

- `AnimationComponent`：状态机宿主；监听 `InteractionComponent` 的信号，按规则切换
  当前 `AnimationLogic` 子节点。
  - `damaged` → 切 "Hit"；`died` → 切 "Die"；
  - `movement_started/stopped` → "walk"/"Idle"（在动作状态中不被打断）；
  - `animation_requested(logic_name, ctx)` → 行为手动请求切状态。
- `AnimationLogic`（基类）：持 `animated_sprite` 和 `context`，子类实现
  `enter/exit/process_logic`，负责播 AnimatedSprite 帧、按 `context["target_pos"]` 翻朝向，
  结束时发 `animation_finished` / `die_finished`。
- 人形动画：`IdleLogic` / `RunLogic` / `ChopLogic` / `MineLogic` / `GatherLogic` / `AttackLogic`。
- 树专用：`TreeHitLogic`（无 hit 动画则 5° 摇晃 tween）/ `TreeDieLogic`（无 die 动画则 90°
  倾倒 + 淡出）。
- 通用兜底：`common/SimpleHitLogic` / `SimpleDieLogic`（草、石用）。

动画驱动全部由 `AnimationComponent` 负责（旧的 `AnimationController.gd` 已清理）。

### 5.5 移动（`MovementController.gd`）

- 依赖同级 `NavigationAgent2D`。`move_to(target_pos)` 设置
  `navigation_agent.target_position`，发 `movement_started`。
- `_physics_process` 按路径点加速/滑行，`is_navigation_finished()` 时发
  `destination_reached`。
- `Player` 的 **pending interaction** 机制：远点击时记 `_pending_interaction_target`，
  到达后在 `destination_reached` 回调里自动触发 `interact()`。

### 5.6 NPC AI（`NPCBrain.gd`）

状态 `IDLE / WANDER / WORK / INTERACT`。
- IDLE：计时→ `_decide_next_action`（60% 漫游，40% 干活）。
- WORK：按 `work_tags`（当前默认 `["stone","grass","tree"]`）调
  `TerrainObjectManager.scan_for_objects` 找最近目标 → 走到 `interaction_approach_distance`
  → `_try_begin_interaction_nearby` 校验对方仍可交互 + 在 `BeHitComponent.interaction_range`
  内 → 调 `command_interact`。
- 卡死兜底：10s 超时强制回 IDLE。

---

## 6. 主场景 InteractionManager（世界交互控制）

`Scripts/world_scene/InteractionManager.gd`——**世界级输入仲裁**，和组件里的
`InteractionComponent` 是两个东西。

两种模式：
- **NORMAL**
  - 左键：射线命中 ENTITIES|INTERACTABLES 层 → 选中；若已有选中且目标在
    `INTERACTION_TILE_RANGE`(1.5 tile) 内 → `command_interact`；否则发 `tile_selected`。
  - 右键：对所有选中单位 `command_move_to`，发 `command_issued("move", pos)` 做反馈效果。
  - ESC：取消选择 / 退出建造模式。
- **BUILD**
  - 从 `BuildMenu` 点选蓝图 → 进入；左键做
    `_check_build_validity`（区块已加载、目标层为空、高度>0 非水）→
    `WorldManager.set_block_at`。

StateChart 初始状态为 `Normal`。

---

## 7. UI / 输入 / 相机

### 7.1 输入映射（`project.godot`）

| action | 默认绑定 |
| :-- | :-- |
| `move_up/down/left/right` | W/S/A/D |
| `primary_action` | 鼠标左键 |
| `secondary_action` | 鼠标右键 |
| `zoom_in/out` | 滚轮 上/下 |
| `interact` | E |
| `toggle_console` | ` |
| `toggle_inventory` | I |
| `toggle_build_menu` | B |

### 7.2 `InputManager` 发射的语义信号

`camera_pan(relative)` / `camera_zoom(factor, mouse_global_pos)` /
`on_primary_click(global_pos)` / `on_secondary_click(global_pos)` /
`on_cancel_action()` / `on_toggle_inventory()` / `on_toggle_build_menu()`。
所有点击经过 `viewport.gui_get_hovered_control() != null` 过滤，悬停 UI 时不派发。

### 7.3 UI 面板

- **HUD**（左上，passive）：玩家坐标、区块、模式、FPS。
- **BuildMenu**（中心弹出，B 切换）：3 种建造物（grass/tree/stone），选中时发
  `build_item_selected(item_id)` + `ui_mode_changed("Build")`。
- **DebugPanel**（右上，F3 切换）：区块计数、内存、选中 tile 信息。
- **TileInfoPanel**（左下）：展示当前选中实体或 tile 的详细信息。

### 7.4 相机 / 视觉

- `CameraRig`：包一层 `PhantomCamera2D`（可用时）或 `Camera2D`（回落）；
  订阅 `InputManager.camera_pan/zoom` 做平滑 lerp，支持缩放/平移限位。
- `ShadowGenerator`：程序化径向渐变贴图（64×64），按 `flatten_y` 做 2.5D 压扁，
  `z_index=-1`。不是 Light2D。

---

## 8. SignalBus 信号清单

区块生命周期
`chunk_data_loaded(coord)` / `chunk_data_unloaded(coord)` /
`chunk_activated(coord)` / `chunk_deactivated(coord)` / `chunk_modified(coord)` /
`object_placed(tile_coord, tile_id)` / `object_removed(tile_coord, tile_id)`

玩家
`player_chunk_changed(old, new)` / `player_position_updated(world_position)`

交互
`entity_deselected()` / `tile_selected(tile_coord, layer)` /
`interaction_executed(target, action)` / `command_issued(command, target_pos)` /
`build_item_selected(item_id)` / `request_toggle_build_menu()`

其他
`ui_mode_changed(mode_name)` / `pause_menu_requested()` / `save_completed()` /
`world_initialized(seed)` / `loading_progress(current, total)` / `world_ready()`

---

## 9. 插件

| 插件 | 用途 | 依赖深度 |
| :-- | :-- | :-- |
| Better Terrain | TileSet 地形连接（查找表从 Tileset 构建） | 深度依赖（`GlobalMapController`） |
| Godot SQLite | `RegionDatabase` 持久化 | 深度依赖 |
| Phantom Camera | `CameraRig` 平滑相机 | 有回落（`Camera2D`） |
| Godot State Charts | `InteractionManager` Normal/Build 状态切换 | 浅依赖 |
| Godot Console | 调试控制台 | 浅依赖 |
| godot_mcp | 开发期 MCP 服务 | 非运行依赖 |

---

## 10. 当前遗留点 / TODO

1. `ChunkLogic._exit_tree()` 是空壳（历史上负责清理视觉，现由 WorldManager 显式接管）。
2. `SelectionManager` 暂无框选拖拽实现。
3. `MapGenerator` 的 `noise_frequency/octaves/lacunarity/gain` 等导出参数目前只作用于
   elevation 噪声，terrain 噪声频率硬编码在 0.01。
4. `_sync_neighbor_padding` 仅同步 GROUND 层——高度层目前只在生成期写入、runtime 不编辑，
   当前用法是正确的；若未来加入 runtime 高度编辑，需扩展。
5. 设置菜单目前只有按键重绑定；语言、分辨率、音量、图形质量等均未实现。
6. `SignalBus` 里的 `object_placed / object_removed / interaction_executed` 还没有监听者，
   等 UI 反馈或成就/日志系统接入时再用。
