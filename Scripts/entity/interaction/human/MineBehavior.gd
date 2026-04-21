class_name MineBehavior
extends LoopingActionBehavior

const _C = preload("res://Scripts/data/Constants.gd")

## 挖矿行为（石头/矿石）。
## 统一框架由 LoopingActionBehavior 提供。此处声明 action 名称 + 实现掉落逻辑。
##
## 未来扩展方向（覆盖父类 hooks）：
## - _compute_damage()        读玩家装备镐头 tier / 矿石硬度做加成
## - _compute_interval()      更好的镐头缩短开采间隔
## - _build_context(target)   追加 tool_id / pickaxe_tier / ore_type_filter
## - _on_hit_applied()        扣镐头耐久、加采矿技能经验、播击石粒子
## - _can_continue()          背包满则停；装备了不支持该矿种的镐头则停

func _get_default_action_name() -> StringName:
	return &"mine"


func _on_target_destroyed(_target: Node) -> void:
	if _is_instigated_by_player():
		PlayerInventory.add(_C.MATERIAL_STONE, 1)


func _is_instigated_by_player() -> bool:
	return interaction_controller != null \
		and interaction_controller.owner_node != null \
		and interaction_controller.owner_node is Player
