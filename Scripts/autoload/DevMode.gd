## DevMode.gd
## 开发者模式总开关
## 路径: res://Scripts/autoload/DevMode.gd
## 类型: Autoload (Global Singleton)
##
## 用途：
## 提供一个全局布尔状态 + 切换信号，让各 UI / 游戏系统在开发期绕过正常限制。
## 当前支持：
##   1. 物品栏 +/- 编辑按钮（无视材料来源直接改数量）
##
## 未来可能加的 dev 功能（都挂在这个开关下）：
##   - "无限采集"：砍/挖一刀到死不扣玩家耐力
##   - "秒建造"：无视材料消耗建造任何方块
##   - "显形"：画出结构/村庄的边界框
##   - "传送"：右键点击直接把玩家瞬移过去
##   - "强制保存/加载"、"清空存档" 快捷键
##
## 开关方式：F10（可在设置里重绑 toggle_dev_mode）
## 视觉反馈：HUD 右上角显示 "开发模式" 徽标
extends Node

signal dev_mode_changed(enabled: bool)

## 当前是否处于开发模式
var is_enabled: bool = false


func _ready() -> void:
	# 听 InputManager 转发的切换信号
	if InputManager.has_signal("on_toggle_dev_mode"):
		InputManager.on_toggle_dev_mode.connect(toggle)


## 切换开发模式
func toggle() -> void:
	set_enabled(not is_enabled)


## 显式设置
func set_enabled(v: bool) -> void:
	if is_enabled == v:
		return
	is_enabled = v
	dev_mode_changed.emit(is_enabled)
	print("[DevMode] %s" % ("ON" if is_enabled else "OFF"))
