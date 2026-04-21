class_name ChopBehavior
extends LoopingActionBehavior

const _C = preload("res://Scripts/data/Constants.gd")

## 砍树行为。
## 统一框架由 LoopingActionBehavior 提供。此处声明 action 名称 + 实现掉落逻辑。
##
## 未来扩展方向（覆盖父类 hooks）：
## - _compute_damage()        读玩家装备斧头 tier 做加成
## - _compute_interval()      斧头越好砍得越快
## - _build_context(target)   追加 tool_id / swing_strength / skill_level
## - _on_hit_applied()        扣斧头耐久、加伐木技能经验、播命中粒子
## - _can_continue()          背包满则停

func _get_default_action_name() -> StringName:
	return &"chop"


## 树倒下时给玩家加木头（Phase 2a）。NPC 砍树暂不产出，以后做 NPC 库存时再扩展。
func _on_target_destroyed(_target: Node) -> void:
	if _is_instigated_by_player():
		PlayerInventory.add(_C.MATERIAL_WOOD, 2)


func _is_instigated_by_player() -> bool:
	return interaction_controller != null \
		and interaction_controller.owner_node != null \
		and interaction_controller.owner_node is Player
