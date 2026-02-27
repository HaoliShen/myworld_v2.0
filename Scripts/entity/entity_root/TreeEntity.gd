class_name TreeEntity
extends Node2D

# 树木实体逻辑
# 新结构下，大部分交互逻辑已由 InteractionComponent 自动处理

# 信号
signal interaction_finished # 如果外部系统还在监听这个
signal died

# 组件引用 (只引用主节点)
@onready var interaction_component: InteractionComponent = $InteractionComponent
@onready var animation_component: AnimationComponent = $AnimationComponent

## 配置参数说明
@export_group("Stats")
## 树木的最大生命值。
@export var max_health: int = 3

# 初始数据 (可选)
var tile_pos: Vector2i

func _ready() -> void:
	# 初始化血量 (如果 InteractionComponent 已经初始化了子组件，这里可以通过它访问)
	# 但 HealthComponent 在 ready 时通常使用默认值，我们需要覆盖它
	
	if interaction_component and interaction_component.health_component:
		interaction_component.health_component.max_health = max_health
		interaction_component.health_component.current_health = max_health
		
		# 监听死亡，处理自身销毁逻辑 (也可以交给 DeathHandlerComponent，但目前保留在这里)
		interaction_component.died.connect(_on_died)
	
	# 监听交互结束 (用于通知 chop behavior)
	# interaction_component.incoming_interaction 发生后，如果没死，可能需要发出 interaction_finished
	# 但目前的 ChopBehavior 是靠 Timer 循环的，或者靠 HealthComponent 的 died
	# 原有逻辑：如果没死，发出 interaction_finished
	# 注意：这里不能在每次受击/受交互时直接 emit interaction_finished
	# 否则会导致 TerrainObjectManager 反复安排销毁计时，造成“交互进行中被回收”的异常
	# interaction_finished 应当由“交互真正结束”的发起方触发（例如行为取消/停止时）
		
	# 确保在 Tree 组中
	add_to_group("Tree")

func _on_died() -> void:
	print("TreeEntity: Died!")
	died.emit()
	
	# 等待死亡动画播放完毕再销毁
	# AnimationComponent 会自动播放 Die
	# 我们需要监听 AnimationComponent 的状态变化或者 Die 状态的结束信号
	
	# 获取 Die 状态节点
	var die_state = animation_component.get_node_or_null("Die")
	if die_state and die_state.has_signal("die_finished"):
		if not die_state.die_finished.is_connected(_on_die_anim_finished):
			die_state.die_finished.connect(_on_die_anim_finished)
	else:
		# 如果没有 Die 状态或者没信号，直接销毁
		_on_die_anim_finished()

func _on_die_anim_finished() -> void:
	queue_free()
