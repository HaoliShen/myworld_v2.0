# MyWorld v2.0

**MyWorld v2.0** 是一个基于 Godot 4.6 开发的 2D 开放世界游戏框架。具有地形系统、分层区块加载机制以及基于组件的实体交互架构，旨在构建一个高性能、可扩展的沙盒世界。

## 🛠️ 技术栈与环境 (Tech Stack)

- **引擎版本**: Godot 4.6 (Forward Plus 渲染器)
- **编程语言**: GDScript
- **核心插件**:
  - [Better Terrain](https://github.com/Portponky/better-terrain): 处理复杂的自动瓦片连接与地形编辑。
  - [Godot SQLite](https://github.com/2shady4u/godot-sqlite): 用于大规模世界数据的持久化存储。
  - [Godot State Charts](https://github.com/derkork/godot-state-charts): 基于状态机的复杂逻辑管理。
  - [Phantom Camera](https://github.com/ramokz/phantom-camera): 实现平滑的相机跟随与 RTS 风格控制。
  - [Godot Console](https://github.com/QuentinCaffeino/godot-console): 内置调试控制台。

## ✨ 核心功能 (Features)

### 1. 开放世界系统 (Open World System)
- **三层区块加载机制 (3-Layer Chunking)**:
  - **Active Layer**: 包含完整逻辑节点（实体、碰撞、AI），玩家当前所在的活跃区域。
  - **Ready Layer**: 仅渲染视觉内容（TileMapLayer），作为缓冲区平滑过渡。
  - **Data Layer**: 仅保留内存数据，用于快速检索。
- **持久化存储**: 采用 SQLite 数据库存储每个区块的地形、植被和物体状态，支持超大地图的动态读写。

### 2. 地形与渲染 (Terrain & Rendering)
- **伪高度视觉**: 通过 Y-Sort 和多层 TileMap（Ground, Decoration, Obstacle）模拟 2D 顶视角下的高度感。
- **动态阴影**: 结合 `ShadowGenerator` 为物体和地形投射实时阴影，增强立体感。
- **自动地形生成**: 基于噪声算法生成的自然地貌（草地、沙漠、水域等）。

### 3. 实体交互架构 (Entity Architecture)
- **组件化设计**: 实体（Player, NPC, Tree）由功能组件组装而成，而非深层继承。
  - `InteractionComponent`: 处理交互逻辑的核心枢纽。
  - `AnimationComponent`: 统一管理状态动画。
  - `HealthComponent`: 处理生命值与伤害。
- **多样化行为 (Behaviors)**: 支持 Attack, Chop, Gather, Mine 等多种交互行为，逻辑高度复用。

### 4. 操作与控制 (Controls & RTS Style)
- **RTS 风格控制**: 支持鼠标左键选中、右键移动/交互。
- **寻路系统**: 集成 NavigationServer2D，支持复杂地形的自动寻路。
- **双模式切换**:
  - **普通模式**: 探索、战斗、采集。
  - **建筑模式**: 放置方块、建造设施。

## 🏗️ 架构概览 (Architecture)

项目采用 **单例驱动 + 信号解耦 + 组件化** 的架构设计：

### 核心单例 (Autoloads)
- **SignalBus**: 全局信号总线，负责模块间的解耦通信。
- **InputManager**: 统一处理输入事件，将硬件输入映射为游戏指令。
- **SaveSystem / RegionDatabase**: 负责存档管理与数据库 I/O。
- **SelectionManager**: 管理 RTS 风格的单位选中逻辑。

### 核心管理器 (Managers)
- **WorldManager**: 世界系统的总指挥，负责区块的生成、加载与卸载。
- **InteractionManager**: 处理玩家与环境的交互请求，仲裁交互状态。

### 数据驱动 (Data Driven)
- **ChunkData**: 轻量级数据容器，用于在内存与数据库间传输区块信息。
- **Constants**: 集中管理游戏配置（如区块大小、渲染层级、物理层掩码）。

## 🎮 操作说明 (Controls)

| 动作 | 按键/操作 |
| --- | --- |
| **主操作 (选择)** | 鼠标左键 |
| **次操作 (移动/交互)** | 鼠标右键 |
| **缩放视角** | 鼠标滚轮 |
| **交互（目前仅砍树）** | 鼠标左键 |


## 📂 项目结构 (Project Structure)

```
d:\mygames_all_ver\myworld_v2.0
├── addons/             # 第三方插件 (BetterTerrain, SQLite, etc.)
├── Assets/             # 美术资源 (Sprites, Tilesets)
├── Scenes/             # 场景文件 (.tscn)
│   ├── Entities/       # 实体场景 (Player, HumanNPC, TreeEntity)
│   ├── Main/           # 核心场景 (World, Chunk, ChunkLogic)
│   └── UI/             
├── Scripts/            # GDScript 脚本代码
│   ├── autoload/       # 全局单例 (SignalBus, InputManager, SaveSystem, etc.)
│   ├── data/           # 数据结构与常量 (ChunkData, Constants, MapUtils)
│   ├── dev_tools/      # 开发辅助工具 (AutoTile, TilesetBitCopy)
│   ├── entity/         # 组件化实体
│   │   ├── ai/         # NPC AI 逻辑 (NPCBrain)
│   │   ├── animation/  # 动画系统组件 (AnimationController, AnimationComponent)
│   │   ├── entity_root/# 实体根节点脚本 (Player, HumanNPC, TreeEntity)
│   │   └── interaction/# 交互系统组件 (InteractionComponent, Behaviors, HealthComponent)
│   ├── player_scene/   # 玩家场景特有 (CameraRig, ShadowGenerator)
│   ├── world_scene/    # 世界场景 (WorldManager, ChunkLogic, MapGenerator)
│   └── UI/             
└── project.godot       # 引擎配置文件
```


