# **代码架构拆分 - 00. 项目结构总览**

版本: 2.0 (Updated: 2026-01)
引擎: Godot 4.3 (Stable)

## **1. 全局自动加载 (Global Autoloads)**

这些脚本需要在 **Project Settings -> Autoload** 中配置。它们在游戏启动时自动实例化，驻留在 /root/ 下，独立于当前场景，全局可访问。

| 节点名 (单例名) | 脚本路径 | 简述职责 |
| :---- | :---- | :---- |
| **SignalBus** | res://Scripts/autoload/SignalBus.gd | **[通信]** 全局信号总线，解耦各系统。 |
| **SaveSystem** | res://Scripts/autoload/SaveSystem.gd | **[配置]** 管理存档路径、配置文件读写。 |
| **InputManager** | res://Scripts/autoload/InputManager.gd | **[输入]** 逻辑翻译官。处理坐标转换、UI过滤、手势识别。 |
| **RegionDatabase** | res://Scripts/autoload/RegionDatabase.gd | **[存储]** 数据库连接保持，提供全局 I/O 接口 (SQLite)。 |

## **2. Scripts 文件夹结构**

```
Scripts/
├── autoload/           # 自动加载单例
│   ├── SignalBus.gd
│   ├── SaveSystem.gd
│   ├── InputManager.gd
│   └── RegionDatabase.gd
│
├── core/               # 核心管理器
│   ├── WorldManager.gd
│   ├── InteractionManager.gd
│   └── GlobalMapController.gd
│
├── data/               # 数据类与工具
│   ├── Constants.gd
│   ├── MapUtils.gd
│   └── ChunkData.gd
│
├── entity/             # 实体脚本
│   └── Player.gd
│
├── components/         # 可复用组件
│   ├── ChunkLogic.gd
│   ├── MapGenerator.gd
│   └── CameraRig.gd
│
└── UI/                 # 界面脚本
    ├── HUD.gd
    ├── DebugPanel.gd
    ├── BuildMenu.gd
    └── TileInfoPanel.gd
```

## **3. 主场景树架构 (Main Scene Architecture)**

这是游戏主关卡的运行时结构。

场景文件: `res://Scenes/World/World.tscn`
根节点: World (Node)

```
World (Node)                                         <-- 游戏入口
│
├── Managers (Node)                                  <-- [逻辑容器] 关卡级管理器
│   │
│   ├── WorldManager (Node)                          <-- [核心] 关卡调度器
│   │   │   script: res://Scripts/core/WorldManager.gd
│   │   │
│   │   ├── MapGenerator (Node)                      <-- [组件] 地形生成器
│   │   │   script: res://Scripts/components/MapGenerator.gd
│   │   │
│   │   └── ActiveChunks (Node)                      <-- [容器] 动态生成的 ChunkLogic 挂载点
│   │       ├── ChunkLogic_0_0 (Node)                <-- [动态]
│   │       └── ...
│   │
│   └── InteractionManager (Node)                    <-- [交互] 逻辑控制器
│       │   script: res://Scripts/core/InteractionManager.gd
│       │
│       └── StateChart (Node)                        <-- [插件] Godot State Charts
│           │   script: godot_state_charts/state_chart.gd
│           └── Root (CompoundState)
│               │   initial_state = "Normal"
│               ├── Normal (AtomicState)
│               │   └── ToBuildMode (Transition)     <-- event: "build_requested"
│               └── BuildMode (AtomicState)
│                   └── ToNormal (Transition)        <-- event: "cancel"
│
├── Environment (Node2D)                             <-- [渲染容器] Y-Sort Enabled = True
│   │   script: res://Scripts/core/GlobalMapController.gd
│   │
│   ├── Camera2D (Camera2D)                          <-- [相机] 主相机
│   │   │   process_callback = IDLE
│   │   └── PhantomCameraHost (Node)                 <-- [插件] Phantom Camera Host
│   │       script: phantom_camera/phantom_camera_host.gd
│   │
│   ├── GroundLayer (TileMapLayer)                   <-- [Layer 0: 地面] Z=-10
│   ├── DecorationLayer (TileMapLayer)               <-- [Layer 1: 装饰] Y-Sort=True
│   ├── ObstacleLayer (TileMapLayer)                 <-- [Layer 2: 障碍] Y-Sort=True
│   ├── NavigationLayer (TileMapLayer)               <-- [导航层] visible=false
│   │
│   └── EntityContainer (Node2D)                     <-- [实体层] Y-Sort=True, unique_name
│       ├── Player (CharacterBody2D)                 <-- [动态] 玩家实例 (见下方)
│       └── (Dynamic NPCs...)                        <-- [动态] NPC 实例
│
└── UI (CanvasLayer)                                 <-- [界面层]
    ├── HUD (Control)
    ├── DebugPanel (Control)
    ├── BuildMenu (Control)
    ├── TileInfoPanel (Control)
    └── DebugConsole (Control)                       <-- mouse_filter = IGNORE
```

## **4. 玩家实体结构 (Player Entity)**

场景文件: `res://Scenes/Entities/Player.tscn`

```
Player (CharacterBody2D)                             <-- collision_layer=8 (ENTITIES, Layer 4)
│   script: res://Scripts/entity/Player.gd
│   groups: ["player"]
│
├── StateChart (Node)                                <-- [插件] Godot State Charts
│   │   script: godot_state_charts/state_chart.gd
│   └── Root (CompoundState)
│       │   initial_state = "Idle"
│       │
│       ├── Idle (AtomicState)
│       │   ├── ToMoving (Transition)                <-- event: "move_requested"
│       │   └── ToInteracting (Transition)           <-- event: "interact"
│       │
│       ├── Moving (AtomicState)
│       │   ├── ToIdle (Transition)                  <-- event: "arrived"
│       │   └── ToIdleStop (Transition)              <-- event: "stop"
│       │
│       └── Interacting (AtomicState)
│           └── ToIdle (Transition)                  <-- event: "interact_done"
│
├── NavigationAgent2D                                <-- [寻路]
│
├── CameraRig (Node2D)                               <-- [相机控制]
│   │   script: res://Scripts/components/CameraRig.gd
│   └── PhantomCamera2D (Node2D)                     <-- [插件] Phantom Camera 2D
│       script: phantom_camera/phantom_camera_2d.gd
│       priority = 10
│       follow_mode = SIMPLE (2)
│       follow_target = Player
│       follow_damping = true
│
├── Visuals (Node2D)                                 <-- [视觉容器]
│   ├── Sprite2D
│   ├── AnimationPlayer
│   └── SelectionMarker (Sprite2D)                   <-- visible=false
│
└── CollisionShape2D (RectangleShape2D: 24x24)
```

## **5. 插件依赖 (Plugin Dependencies)**

| 插件名 | 版本 | 用途 |
| :---- | :---- | :---- |
| **Godot State Charts** | v0.22.2 | 状态机管理 (StateChart, CompoundState, AtomicState, Transition) |
| **Phantom Camera** | v0.10 | 相机控制 (PhantomCameraHost, PhantomCamera2D) |
| **Better Terrain** | - | 地形编辑增强 |
| **Godot Console** | - | 调试控制台 |

## **6. 物理层配置 (Physics Layers)**

| 层名 | Layer 编号 | 掩码值 | 用途 |
| :---- | :---- | :---- | :---- |
| GROUND | 1 | 1 | 地形碰撞 |
| INTERACTABLES | 2 | 2 | 可交互物体 |
| OBSTACLES | 3 | 4 | 静态障碍物 |
| ENTITIES | 4 | 8 | 玩家、NPC |

## **7. 数据层定义 (Data Layers)**

| 层级 | 枚举值 | TileMapLayer | 用途 |
| :---- | :---- | :---- | :---- |
| GROUND | 0 | GroundLayer | 地面材质 (泥土、水、悬崖) |
| DECORATION | 1 | DecorationLayer | 装饰物 (花草、地毯) |
| OBSTACLE | 2 | ObstacleLayer | 障碍物 (树木、墙壁) |
