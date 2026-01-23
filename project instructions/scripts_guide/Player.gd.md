# **脚本设计: Player.gd**

路径: res://Scripts/Entities/Player.gd  
挂载节点: World/Environment/EntityContainer/Player  
继承: CharacterBody2D  
依赖组件:

* Godot State Charts (状态机插件)  
* NavigationAgent2D (寻路代理)  
* CameraRig (子节点控制器)

## **职责**

玩家实体的核心控制器。它不直接处理输入（由 InteractionManager 或 InputManager 处理），而是接收指令并执行。它负责物理运动计算、寻路逻辑执行以及状态机的状态流转。

## **节点结构 (Scene Tree)**

Player 是一个独立的场景文件 (Player.tscn)，其内部结构如下：

Player (CharacterBody2D)                    \<-- 挂载 Player.gd  
│  
├── StateChart (Node)                       \<-- \[插件\] 状态机根节点  
│   └── Root (CompoundState)  
│       ├── Idle (State)  
│       ├── Moving (State)  
│       └── Interacting (State)  
│  
├── NavigationAgent2D (Node)                \<-- \[组件\] 寻路与避障代理  
│  
├── CameraRig (Node2D)                      \<-- \[组件\] 摄像机挂载点  
│   └── script: CameraRig.gd                \<-- (已配置 Phantom Camera 逻辑)  
│  
├── Visuals (Node2D)                        \<-- \[视觉\] 视觉元素容器  
│   ├── Sprite2D                            \<-- 角色贴图 (Offset.y 适配 Y-Sort)  
│   ├── AnimationPlayer                     \<-- 动画控制器  
│   └── SelectionMarker (Sprite2D)          \<-- 选中光圈 (默认隐藏)  
│  
└── CollisionShape2D                        \<-- \[物理\] 碰撞胶囊体

## **公共接口 (API)**

class\_name Player

\# \--- 状态查询 \---

\# 返回玩家当前是否被 InteractionManager 选中。  
\# 用于 UI 判断是否显示属性面板或允许下达指令。  
func is\_selected() \-\> bool:  
    pass

\# \--- 外部指令 (Command Interface) \---  
\# 这些方法通常由 InteractionManager 调用

\# 设置玩家的选中状态。  
\# 职责:  
\# 1\. 更新内部状态变量。  
\# 2\. 控制 Visuals/SelectionMarker 的显示与隐藏。  
\# @param selected: true 为选中，false 为取消选中。  
func set\_selected(selected: bool) \-\> void:  
    pass

\# 瞬间传送玩家到指定位置。  
\# 职责:  
\# 1\. 直接修改 global\_position。  
\# 2\. 重置 NavigationAgent2D 的路径，取消当前移动指令。  
\# 3\. 强制更新 CameraRig 位置 (避免平滑过渡导致的镜头拉扯)。  
\# 场景: 调试指令、进出室内、跨地图传送。  
func teleport\_to(global\_pos: Vector2) \-\> void:  
    pass

\# 命令玩家移动到指定位置。  
\# 职责:  
\# 1\. 设置 NavigationAgent2D.target\_position。  
\# 2\. 向 StateChart 发送 "move\_requested" 事件，切换至 Moving 状态。  
\# 3\. (可选) 在目标位置生成一个临时的移动标记特效。  
\# @param target\_pos: 目标世界坐标。  
func command\_move\_to(target\_pos: Vector2) \-\> void:  
    pass

\# 命令玩家与指定位置的物体交互。  
\# 职责:  
\# 1\. 判断目标是否在交互范围内 (Interaction Range)。  
\# 2\. 若在范围内: 停止移动，向 StateChart 发送 "interact" 事件。  
\# 3\. 若不在范围内: 设置移动目标为交互对象的边缘，先移动再交互 (Move-To-Interact)。  
\# @param target\_pos: 交互目标的世界坐标。  
func command\_interact(target\_pos: Vector2) \-\> void:  
    pass

\# \--- 内部逻辑钩子 (仅说明功能) \---

\# 物理帧处理 (\_physics\_process)  
\# 职责:  
\# 1\. 检查 StateChart，仅在 Moving 状态下执行。  
\# 2\. 获取 NavigationAgent2D 的下一个路径点。  
\# 3\. 计算速度向量 (Velocity)，应用加速度和摩擦力。  
\# 4\. 调用 move\_and\_slide() 执行物理移动。  
\# 5\. 根据移动方向更新 Sprite 朝向。  
func \_physics\_process(delta: float) \-\> void:  
    pass  
