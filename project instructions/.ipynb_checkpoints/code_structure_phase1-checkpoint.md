# **代码架构拆分 \- 00\. 项目结构总览**

版本: 1.0 (Ref: v24.0)  
引擎: Godot 4.3 (Stable)

## **1\. 全局自动加载 (Global Autoloads)**

这些脚本需要在 **Project Settings \-\> Autoload** 中配置。它们在游戏启动时自动实例化，驻留在 /root/ 下，独立于当前场景，全局可访问。详细接口见 arch\_01\_managers.md。

| 节点名 (单例名) | 脚本路径 | 简述职责 |
| :---- | :---- | :---- |
| **SignalBus** | res://Scripts/Core/SignalBus.gd | **\[通信\]** 全局信号总线，解耦各系统。 |
| **SaveSystem** | res://Scripts/Core/SaveSystem.gd | **\[配置\]** 管理存档路径、配置文件读写。 |
| **InputManager** | res://Scripts/Core/InputManager.gd | **\[输入\]** 逻辑翻译官。处理坐标转换、UI过滤、手势识别。 |
| **RegionDatabase** | res://Scripts/Components/RegionDatabase.gd | **\[存储\]** 数据库连接保持，提供全局 I/O 接口 (SQLite)。 |

## **2\. 主场景树架构 (Main Scene Architecture)**

这是游戏主关卡的运行时结构。

场景文件: res://Scenes/World/World.tscn  
根节点: World (Node)  
World (Node)                                        \<-- 游戏入口  
│  
├── Managers (Node)                                 \<-- \[逻辑容器\] 关卡级管理器  
│   │  
│   ├── WorldManager (Node)                         \<-- \[核心\] 关卡调度器  
│   │   ├── StateChart (Node)                       \<-- \[插件\] Godot State Charts  
│   │   ├── MapGenerator (Node)                     \<-- \[组件\] 地形生成器  
│   │   └── ActiveChunks (Node)                     \<-- \[容器\] 动态生成的 ChunkLogic 挂载点  
│   │       ├── ChunkLogic\_0\_0 (Node)               \<-- \[动态\] (详见 arch\_03\_entities.md)  
│   │       └── ...  
│   │  
│   ├── InteractionManager (Node)                   \<-- \[交互\] 逻辑控制器  
│   │   \# 职责: 监听 InputManager 信号，维护 "SelectedEntity"，  
│   │   \# 执行射线检测，分发 Move/Interact 指令给实体。  
│   │  
│   └── (RegionDatabase 等已移至 Autoload)  
│  
├── Environment (Node2D)                            \<-- \[渲染容器\] Y-Sort Enabled \= True  
│   │   \# 核心设计: 所有的地块层和实体都置于同一个 Y-Sort 空间下  
│   │   \# 详见 arch\_02\_environment.md  
│   │  
│   ├── GroundLayer (TileMapLayer)                  \<-- \[Layer 1: 地面\] Z=-10  
│   ├── DecorationLayer (TileMapLayer)              \<-- \[Layer 2: 装饰\] Y-Sort=True  
│   ├── ObstacleLayer (TileMapLayer)                \<-- \[Layer 3: 障碍\] Y-Sort=True  
│   │  
│   └── EntityContainer (Node2D)                    \<-- \[实体层\] Y-Sort=True  
│       ├── (Dynamic Player)                        \<-- \[动态\] 玩家实例 (详见 arch\_03\_entities.md)  
│       └── (Dynamic NPCs...)                       \<-- \[动态\] NPC 实例  
│  
└── UI (CanvasLayer)                                \<-- \[界面层\]  
    ├── DebugConsole (Control)                      \<-- \[插件\] Godot Console  
    └── HUD (Control)  
