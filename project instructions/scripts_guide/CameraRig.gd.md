# **脚本设计: CameraRig.gd**

路径: res://Scripts/Components/CameraRig.gd  
挂载节点: Player/CameraRig (作为玩家场景的子节点)  
继承: Node2D  
依赖: Phantom Camera (插件)

## **职责**

摄像机控制中枢 (Camera Control Hub)。  
它不直接是摄像机，而是 PhantomCamera2D (PCam) 的挂载点和控制器。它负责监听 InputManager 的信号，动态调整 PCam 的参数（缩放、偏移、跟随目标），从而实现 RPG 跟随视角与 RTS 拖拽视角的平滑融合。

## **节点结构**

CameraRig (Node2D)                  \<-- 挂载此脚本  
└── PhantomCamera2D (Node2D)        \<-- \[插件节点\] 实际的摄像机控制体  
    ├── follow\_mode: Glued (粘滞跟随)  
    ├── follow\_target: .. (指向 Player)  
    ├── zoom: (1, 1\)  
    └── tween\_resource: (配置平滑过渡参数)

## **属性配置**

@export\_group("Zoom Settings")  
@export var min\_zoom: float \= 0.5   \# 最远视角 (宏观)  
@export var max\_zoom: float \= 2.0   \# 最近视角 (微观)  
@export var zoom\_speed: float \= 5.0 \# 缩放平滑速度

@export\_group("Pan Settings")  
@export var max\_pan\_offset: Vector2 \= Vector2(500, 300\) \# 允许拖拽偏离玩家的最大距离

## **内部状态**

\# 当前的目标缩放值 (用于平滑插值)  
var \_target\_zoom: float \= 1.0

\# 当前的拖拽偏移量 (相对于 Player 中心的偏移)  
var \_current\_pan\_offset: Vector2 \= Vector2.ZERO

\# 引用 PhantomCamera2D 节点  
@onready var pcam: PhantomCamera2D \= $PhantomCamera2D

## **公共接口 (API)**

func \_ready():  
    \# 连接 InputManager 信号  
    InputManager.camera\_zoom.connect(\_on\_camera\_zoom)  
    InputManager.camera\_pan.connect(\_on\_camera\_pan)  
      
    \# 初始化  
    \_target\_zoom \= pcam.zoom.x

func \_process(delta: float):  
    \# 1\. 处理平滑缩放  
    \# 使用 lerp 让当前 zoom 逐渐接近 \_target\_zoom  
    var new\_zoom \= lerp(pcam.zoom.x, \_target\_zoom, zoom\_speed \* delta)  
    pcam.set\_zoom(Vector2(new\_zoom, new\_zoom))  
      
    \# 2\. 处理位置偏移  
    \# Phantom Camera 的 Glued 模式通常跟随 Target。  
    \# 如果要实现拖拽地图（但不脱离玩家太远），我们可以修改 CameraRig 自身的 position。  
    \# 因为 CameraRig 是 Player 的子节点，修改其 position 就相当于修改了 PCam 的 Follow Offset。  
    position \= position.lerp(\_current\_pan\_offset, 10.0 \* delta)

\# \--- 信号响应 \---

\# 响应滚轮缩放  
\# @param zoom\_factor: \+0.1 或 \-0.1  
func \_on\_camera\_zoom(zoom\_factor: float, \_mouse\_pos: Vector2) \-\> void:  
    \_target\_zoom \= clamp(\_target\_zoom \+ zoom\_factor, min\_zoom, max\_zoom)

\# 响应鼠标拖拽地图  
\# @param relative: 鼠标相对位移 (注意：为了符合直觉，地图移动方向应与鼠标相反，或者视具体设计而定)  
\# 这里假设 relative 是“摄像机应该移动的量”  
func \_on\_camera\_pan(relative: Vector2) \-\> void:  
    \# 累加偏移量  
    \_current\_pan\_offset \-= relative \# 鼠标向左拖，摄像机向右看（即位置向左移）  
      
    \# 限制拖拽范围，防止玩家把摄像机拖得离角色太远看不到自己  
    \_current\_pan\_offset.x \= clamp(\_current\_pan\_offset.x, \-max\_pan\_offset.x, max\_pan\_offset.x)  
    \_current\_pan\_offset.y \= clamp(\_current\_pan\_offset.y, \-max\_pan\_offset.y, max\_pan\_offset.y)

\# 外部调用：重置视角（例如按下空格键回到玩家中心）  
func recenter\_camera() \-\> void:  
    \_current\_pan\_offset \= Vector2.ZERO  
    \_target\_zoom \= 1.0  
