class_name ShadowGenerator
extends Sprite2D

# 阴影半径：控制阴影的大小
@export var radius: float = 10.0
# 阴影透明度：0.0 为完全透明，1.0 为完全不透明
@export var opacity: float = 0.75
# 垂直压缩比例：用于模拟 2D 视角下的透视效果，值越小越扁
@export var flatten_y: float = 0.35

func _ready():
	_setup_shadow()

func _setup_shadow():
	# 创建渐变
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, opacity)) # 中心颜色（黑色带透明度）
	gradient.set_color(1, Color(0, 0, 0, 0))       # 边缘颜色（完全透明）
	
	# 创建程序化纹理
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	
	self.texture = tex
	
	# 调整变换以呈现透视阴影效果
	# 通过缩放来匹配所需的半径和扁平度
	self.scale = Vector2(1.0, flatten_y) * (radius / 32.0)
	self.z_index = -1 # 确保阴影渲染在角色精灵下方
