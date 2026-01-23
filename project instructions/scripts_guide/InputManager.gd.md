# **脚本设计: InputManager.gd**

路径: res://Scripts/Core/InputManager.gd  
类型: Autoload (Global Singleton)  
继承: Node

## **职责**

**第一道防线 (Input Translation)**。负责将原始硬件输入转化为游戏意图，并负责**UI 遮挡过滤**。

1. **坐标转换:** 屏幕坐标 \-\> 世界坐标 / 网格坐标。  
2. **UI 过滤:** 检测鼠标是否在 UI 上 (is\_mouse\_over\_ui)，若是则拦截信号。  
3. **手势识别:** 区分点击 (Click) 和 拖拽 (Drag)。

## **输入处理流程 (Processing Logic)**

当检测到鼠标输入（按下/移动/松开）时，执行以下判断：

1. **UI 阻断检查 (UI Blocking):**  
   * 调用 is\_mouse\_over\_ui()。  
   * **如果为 True (点在 UI 上):**  
     * **立即返回 (Return Early)。**  
     * **不发射** 任何 click 或 pan 信号。  
     * *注：具体的 UI 交互由 UI 控件自身的 \_gui\_input 或 pressed 信号处理，InputManager 不参与。*  
   * **如果为 False (点在空地上):**  
     * 继续执行后续步骤。  
2. **手势消歧 (Gesture Disambiguation):**  
   * **按下 (Press):** 记录起始位置。  
   * **移动 (Move):** 若按住且移动距离 \> drag\_threshold，判定为 **拖拽**，发射 camera\_pan。  
   * **松开 (Release):** 若未触发拖拽，判定为 **点击**，发射 on\_primary\_click。  
3. **坐标转换 (Coordinate Conversion):**  
   * 将屏幕坐标转换为世界坐标 (Global Pos) 和 网格坐标 (Tile Pos) 随信号发出。

## **配置参数**

* drag\_threshold: float (e.g. 10.0 px)  
* zoom\_speed: float (e.g. 0.1)

## **公共接口 (API)**

\# \--- 信号 (仅当 is\_mouse\_over\_ui() \== false 时触发) \---

\# 意图：移动摄像机 / 拖拽地图 (左键按住移动)  
signal camera\_pan(relative: Vector2)

\# 意图：缩放视野 (滚轮)  
signal camera\_zoom(zoom\_factor: float, mouse\_global\_pos: Vector2)

\# 意图：主要点击 (左键单击)  
signal on\_primary\_click(global\_pos: Vector2)

\# 意图：次要点击 (右键单击)  
signal on\_secondary\_click(global\_pos: Vector2)

\# 意图：取消/返回 (ESC)  
signal on\_cancel\_action()

\# \--- 界面快捷键信号 \---  
signal on\_toggle\_inventory()  
signal on\_toggle\_build\_menu()

\# \--- 状态查询 \---

\# 获取当前鼠标指向的世界坐标 (即时计算)  
\# 逻辑:   
\# 1\. get\_viewport().get\_mouse\_position()  
\# 2\. 结合 CameraRig 的位置和缩放进行转换 (get\_global\_mouse\_position)  
func get\_mouse\_world\_pos() \-\> Vector2

\# 获取当前鼠标指向的网格坐标  
\# 逻辑:   
\# 1\. 调用 get\_mouse\_world\_pos()  
\# 2\. 直接调用 MapUtils的工具函数实现转换  
func get\_mouse\_tile\_pos() \-\> Vector2i

\# 检查鼠标是否在 UI 上  
func is\_mouse\_over\_ui() \-\> bool  
