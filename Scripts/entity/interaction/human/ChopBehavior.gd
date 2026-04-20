class_name ChopBehavior
extends LoopingActionBehavior

## 砍树行为。
## 统一框架由 LoopingActionBehavior 提供。此处仅声明 action 名称。
##
## 未来扩展方向（覆盖父类 hooks）：
## - _compute_damage()        读玩家装备斧头 tier 做加成
## - _compute_interval()      斧头越好砍得越快
## - _build_context(target)   追加 tool_id / swing_strength / skill_level
## - _on_hit_applied()        扣斧头耐久、加伐木技能经验、播命中粒子
## - _on_target_destroyed()   生成原木掉落物
## - _can_continue()          背包满则停

func _get_default_action_name() -> StringName:
	return &"chop"
