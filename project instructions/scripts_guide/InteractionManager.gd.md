# **脚本设计: InteractionManager.gd**

路径: res://Scripts/Managers/InteractionManager.gd  
挂载节点: World/Managers/InteractionManager  
继承: Node  
依赖:

* Godot State Charts (状态机插件)  
* InputManager (输入信号源)  
* WorldManager (数据查询与修改)  
* SignalBus (事件广播)

## **职责**

操作模式管理器 (Game Mode Controller)。  
它是 Gameplay 逻辑的核心大脑。它不直接处理键盘按键，而是监听 InputManager 翻译后的意图信号，结合当前的操作模式（正常/建造），决定具体的游戏行为。

## **核心属性**

\# 当前选中的实体 (Player 或 NPC)  
var selected\_entity: Node2D \= null

\# 当前准备建造的物品 ID (仅在 BuildMode 有效)  
var current\_blueprint\_id: int \= \-1

\# 状态机节点引用  
@onready var state\_chart: StateChart \= $StateChart

## **状态机架构 (StateChart)**

Root (Compound)  
├── Normal (State)          \<-- \[默认状态\] 负责选中、移动、交互  
│   ├── event: build\_requested \-\> Transition to BuildMode  
│  
└── BuildMode (State)       \<-- \[建造状态\] 仅在从 UI 选择了物品后进入  
    ├── event: cancel \-\> Transition to Normal  
    ├── event: built \-\> (Optional) Stay or Transition to Normal

## **逻辑流程详解**

### **1\. 初始化 (\_ready)**

* 连接 InputManager 的所有信号 (on\_primary\_click, on\_secondary\_click, on\_cancel\_action 等)。  
* 连接 SignalBus 的 build\_item\_selected 信号 \-\> 触发状态机跳转到 BuildMode。

### **2\. Normal 状态逻辑**

在此状态下，鼠标左键用于选中或交互，右键用于移动。

* **左键点击 (\_on\_primary\_click)**:  
  1. **射线检测 (\_raycast\_at\_mouse)**: 获取鼠标点击位置的碰撞体。  
  2. **击中实体**:  
     * 若目标与 selected\_entity 不同，更新 selected\_entity \= target。  
     * 调用 target.set\_selected(true)。  
     * 发送 SignalBus.entity\_selected(target)。  
  3. **击中空地 (或 TileMap)**:  
     * **交互判定**: 如果 selected\_entity 是 Player，且点击位置距离 Player **\<= 1.5 Tile（玩家所在tile中心九宫格）**：  
       * 调用 Player.command\_interact(target\_pos)。  
     * **取消选中**: 如果距离过远或不是交互目标：  
       * 调用 selected\_entity.set\_selected(false)。  
       * 重置 selected\_entity \= null。  
       * 发送 SignalBus.entity\_deselected(null)。  
* **右键点击 (\_on\_secondary\_click)**:  
  * 若 selected\_entity 是 Player：  
    * 调用 selected\_entity.command\_move\_to(target\_pos)。  
    * 发送 SignalBus.command\_issued("move", target\_pos) (用于生成地面点击特效)。  
* **快捷键响应**:  
  * 收到 on\_toggle\_inventory \-\> 若选中 Player，发送 SignalBus.request\_toggle\_inventory。  
  * 收到 on\_toggle\_build\_menu \-\> 若选中 Player，发送 SignalBus.request\_toggle\_build\_menu。

### **3\. BuildMode 状态逻辑**

在此状态下，鼠标左键变为“放置”，右键/ESC 变为“取消”。

* **进入状态 (\_on\_build\_mode\_entered)**:  
  * 接收并记录 current\_blueprint\_id。  
  * (可选) 更改鼠标光标样式以提示玩家当前处于建造模式。  
* **左键点击 (\_on\_primary\_click)**:  
  * 获取点击位置的 Tile 坐标。  
  * **合法性检查 (\_check\_build\_validity)**: 调用 WorldManager.get\_chunk\_data\_at 检查目标位置是否已被占用、地形是否允许建造。  
  * 若合法：  
    * 调用 WorldManager.set\_block\_at(tile\_pos, layer, current\_blueprint\_id)。  
    * (可选) 播放建造音效。  
  * 若不合法：  
    * (可选) 播放错误音效。  
* **取消操作 (\_on\_cancel\_action / \_on\_secondary\_click)**:  
  * 触发状态机事件 cancel，返回 Normal 状态。  
* **退出状态 (\_on\_build\_mode\_exited)**:  
  * 重置 current\_blueprint\_id \= \-1。  
  * 恢复鼠标光标样式。

## **内部辅助函数 (Private Helpers)**

\# 执行物理射线检测  
func \_raycast\_at\_mouse() \-\> Dictionary:  
    \# ...

\# 检查某个位置是否可以建造特定建筑  
func \_check\_build\_validity(tile\_pos: Vector2i, blueprint\_id: int) \-\> bool:  
    \# ...  
