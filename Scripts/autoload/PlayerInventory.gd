## PlayerInventory.gd
## 玩家材料库存 - Phase 2a
## 路径: res://Scripts/autoload/PlayerInventory.gd
## 类型: Autoload (Global Singleton)
##
## 设计目标（当前阶段）：
## - 最小可用：只是一个 Dictionary[String, int]，记材料种类 → 数量
## - 无 slot / 无堆叠上限 / 无重量——为将来可能的富库存 UI 预留
## - 持久化：SaveSystem 负责读写 world.ini [inventory] 段
## - 广播：任何改动都发 inventory_changed 信号（HUD、BuildMenu 监听）
##
## 当前只服务于 Player。NPC 有了产出/消耗需求时再复制一份或扩展成"entity 级库存"。
extends Node

signal inventory_changed(inventory: Dictionary)

## 当前库存：material_key(String) -> count(int)
## 约定 count 恒 >= 0；为 0 不删 key，保持语义"这个材料见过但为空"
var _inv: Dictionary = {}


# =============================================================================
# 读取
# =============================================================================

func count(key: String) -> int:
	return int(_inv.get(key, 0))


## 是否满足一组材料消耗
func has_at_least(costs: Dictionary) -> bool:
	for key in costs:
		if count(key) < int(costs[key]):
			return false
	return true


## 返回深拷贝快照（给 SaveSystem 写回时用；避免外部误改内部状态）
func snapshot() -> Dictionary:
	return _inv.duplicate(true)


# =============================================================================
# 修改
# =============================================================================

func add(key: String, n: int) -> void:
	if n <= 0:
		return
	_inv[key] = count(key) + n
	inventory_changed.emit(_inv)


## 尝试扣除；不够则不扣且返回 false
func remove(key: String, n: int) -> bool:
	if n <= 0:
		return true
	var cur := count(key)
	if cur < n:
		return false
	_inv[key] = cur - n
	inventory_changed.emit(_inv)
	return true


## 批量扣除；任一项不够则全部不扣
func remove_batch(costs: Dictionary) -> bool:
	if not has_at_least(costs):
		return false
	for key in costs:
		_inv[key] = count(key) - int(costs[key])
	inventory_changed.emit(_inv)
	return true


# =============================================================================
# 生命周期（SaveSystem 调用）
# =============================================================================

## 从存档恢复。data 是 SaveSystem.load_player_inventory 返回的 Dictionary
func restore(data: Dictionary) -> void:
	_inv.clear()
	for key in data:
		var v := int(data[key])
		if v > 0:
			_inv[String(key)] = v
	inventory_changed.emit(_inv)


## 切存档或退出世界时清空
func clear() -> void:
	_inv.clear()
	inventory_changed.emit(_inv)
