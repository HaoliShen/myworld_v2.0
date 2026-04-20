class_name GatherBehavior
extends LoopingActionBehavior

## 采集行为（草/花/作物）。
## 统一框架由 LoopingActionBehavior 提供。此处仅声明 action 名称。
##
## 未来扩展方向（覆盖父类 hooks）：
## - _compute_damage()        一般为固定 1；若引入"镰刀"类工具可加成
## - _compute_interval()      更好的采集工具 / 熟练度降低间隔
## - _build_context(target)   追加 tool_id / harvest_yield_multiplier
## - _on_hit_applied()        加采集技能经验、触发自动拾取
## - _on_target_destroyed()   生成产出（草束、种子、药草）
## - _can_continue()          背包满则停

func _get_default_action_name() -> StringName:
	return &"gather"
