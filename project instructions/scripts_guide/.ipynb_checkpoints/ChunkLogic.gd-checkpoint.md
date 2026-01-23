# **脚本设计: ChunkLogic.gd**

路径: res://Scripts/Systems/ChunkLogic.gd  
挂载节点: World/Managers/WorldManager/ActiveChunks (动态生成)  
继承: Node

## **职责**

**生命周期锚点与视觉守卫 (Lifecycle Anchor & Visual Guard)**。

1. **存在即渲染 (Existence implies Rendering):**  
   * 这个节点的实例存在于场景树中，严格对应着 GlobalMapController 上已绘制的一块区域。  
   * 它是 WorldManager 追踪“当前显示了哪些区块”的句柄。  
2. **自动清理 (RAII Cleanup):**  
   * 利用 Godot 的 \_exit\_tree() 通知机制。当此节点被销毁（无论是被 WorldManager 主动卸载，还是场景切换导致销毁）时，它会自动调用 GlobalMapController.clear\_chunk()。  
   * 这种机制确保了逻辑状态与视觉状态的强一致性，防止“逻辑上卸载了，但地图上还留着残影”的 Bug。

## **属性**

\# 该逻辑块所代表的区块坐标  
var coord: Vector2i

\# 对全局地图控制器的引用 (用于卸载时调用擦除)  
var \_map\_controller: GlobalMapController

## **公共接口 (API)**

\# 初始化函数  
\# @param target\_coord: 区块坐标  
\# @param map\_controller: 全局地图控制器的引用 (依赖注入)  
func setup(target\_coord: Vector2i, map\_controller: Node) \-\> void:  
    coord \= target\_coord  
    \_map\_controller \= map\_controller  
    \# 注意：这里不需要调用 render，渲染由 WorldManager 在实例化此前完成，  
    \# 按照当前架构，WorldManager 先 render 再 add\_child 此节点。

## **生命周期回调 (Lifecycle)**

func \_exit\_tree() \-\> void:  
    \# 守卫逻辑：  
    \# 当节点离开场景树时，强制擦除对应的视觉内容。  
    if \_map\_controller and is\_instance\_valid(\_map\_controller):  
        \_map\_controller.clear\_chunk(coord)  
