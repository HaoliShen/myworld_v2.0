## ChunkLogic.gd
## 区块逻辑节点 - 生命周期锚点与视觉守卫
## 路径: res://Scripts/Entities/ChunkLogic.gd
## 挂载节点: World/Managers/WorldManager/ActiveChunks (动态生成)
## 继承: Node
##
## 职责:
## 1. 存在即渲染 (Existence implies Rendering):
##    这个节点的实例存在于场景树中，严格对应着 GlobalMapController 上已绘制的一块区域。
##    它是 WorldManager 追踪"当前显示了哪些区块"的句柄。
## 2. 自动清理 (RAII Cleanup):
##    利用 Godot 的 _exit_tree() 通知机制。当此节点被销毁时，
##    它会自动调用 GlobalMapController.clear_chunk()，
##    确保逻辑状态与视觉状态的强一致性。
class_name ChunkLogic
extends Node

# =============================================================================
# 属性 (Properties)
# =============================================================================

## 该逻辑块所代表的区块坐标
var coord: Vector2i = Vector2i.ZERO

## 对全局地图控制器的引用 (用于卸载时调用擦除)
var _map_controller = null

# =============================================================================
# 公共接口 (API)
# =============================================================================

## 初始化函数
## @param target_coord: 区块坐标
## @param map_controller: 全局地图控制器的引用 (依赖注入)
## 注意: 这里不需要调用 render，渲染由 WorldManager 在实例化此节点前完成。
##       按照当前架构，WorldManager 先 render 再 add_child 此节点。
func setup(target_coord: Vector2i, map_controller) -> void:
	coord = target_coord
	_map_controller = map_controller
	name = "Chunk_%d_%d" % [coord.x, coord.y]

# =============================================================================
# 生命周期回调 (Lifecycle)
# =============================================================================

## 守卫逻辑：当节点离开场景树时，强制擦除对应的视觉内容
func _exit_tree() -> void:
	if _map_controller and is_instance_valid(_map_controller):
		_map_controller.clear_chunk(coord)
