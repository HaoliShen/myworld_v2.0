### 1. 问题分析 (Problem Analysis)
经过对代码和场景文件的深入排查，确认了问题的根源：

*   **现象**: 相机拖拽、缩放等操作无反应。
*   **原因**: 玩家场景 (`Player.tscn`) 在重构过程中丢失了相机相关的节点结构。
    *   **InputManager**: 正常工作。它能正确检测鼠标输入并发送 `camera_pan` (拖拽) 和 `camera_zoom` (缩放) 信号。
    *   **CameraRig.gd**: 逻辑完好。这个脚本负责监听上述信号并控制相机，但它目前**没有挂载到玩家场景中**，因此无法运行。
    *   **Player.tscn**: 目前只包含 `MovementComponent`, `HealthComponent` 等组件，**缺少 `CameraRig` 节点和 `PhantomCamera2D` 节点**。

简而言之，**“遥控器 (InputManager)”还在，“控制逻辑 (CameraRig)”也有，但是“接收器和相机实体”在场景里消失了。**

### 2. 改动方案 (Modification Plan)
为了修复此问题，我们需要在 `Player.tscn` 中重建相机结构。

#### **步骤 1: 恢复节点结构**
在 `Scenes/Entities/Player.tscn` 场景中添加以下节点：
1.  **添加 `CameraRig` 节点**:
    *   **类型**: `Node2D`
    *   **位置**: 作为 `root` (Player) 的子节点。
    *   **脚本**: 挂载 `res://Scripts/components/CameraRig.gd`。
    *   **作用**: 作为相机的挂载点，负责接收输入信号并处理“RTS式”的拖拽偏移逻辑。

2.  **添加 `PhantomCamera2D` 节点**:
    *   **类型**: `PhantomCamera2D` (来自插件)
    *   **位置**: 作为 `CameraRig` 的子节点。
    *   **作用**: 实际的相机对象，利用插件功能提供平滑的跟随和缩放效果。

#### **步骤 2: 配置参数**
*   **PhantomCamera2D**:
    *   `Priority`: 设置为 **10** (或更高)，确保它是当前激活的主相机。
    *   `Zoom`: 默认为 `Vector2(1, 1)`。
    *   `Follow Mode`: 由于它是 `CameraRig` 的子节点，且 `CameraRig` 会跟随玩家移动（并叠加拖拽偏移），因此这里通常**不需要**设置额外的 Follow Target，或者将其 Follow Target 设置为 `CameraRig` 自身（取决于插件的具体行为，通常作为子节点即可自然跟随）。

#### **预期修复效果**
1.  **恢复控制**: `InputManager` 发出的信号将被 `CameraRig` 捕获。
2.  **拖拽功能**: 右键/左键拖拽会更新 `CameraRig` 相对于 Player 的位置偏移 (`position`)，实现“不改变玩家位置的视野移动”。
3.  **缩放功能**: 滚轮操作会更新 `PhantomCamera2D` 的 `zoom` 属性。

请确认是否执行此修复方案？