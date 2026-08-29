class_name Style
extends RefCounted
##
## 赛博国风占位配色 —— 美术素材换上来之前，先用颜色把气质立住。
## 墨底 + 青玉 + 鎏金。等 Codex 出图后这些色值应与素材对齐。
##

const INK      := Color("0b0f14")   # 墨底
const INK_2    := Color("141b24")   # 面板底
const INK_3    := Color("1e2833")   # 卡片底
const JADE     := Color("46c8a4")   # 青玉（主强调）
const JADE_DIM := Color("2b7d68")
const GOLD     := Color("d9b45b")   # 鎏金（次强调 / 灵石）
const TEXT     := Color("dbe4ef")
const TEXT_DIM := Color("8497ab")
const DANGER   := Color("c85a5a")
const LINE     := Color("2c3a49")

const POPUP_INSET := 64.0
const POPUP_CLOSE_SIZE := Vector2(40, 34)


## 弹窗底：实心墨色。边框素材的中心是透明的，不能直接当底用 ——
## 那样背后的场景会透过来（踩过）。所以底和框分成两层。
static func frame() -> StyleBoxFlat:
	var sb := panel(Color(0.045, 0.065, 0.085, 0.97), LINE, 10)
	# 内容安全区由 holder 内部显式控制。这里必须为 0，否则 PanelContainer
	# 会把 holder 往里推，边框贴图也就跟着缩进去，四周留下黑色空带。
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


## 叠在弹窗最上层的鎏金云雷纹边框。加到 holder 里，鼠标穿透。
static func frame_overlay() -> Control:
	var path := "res://assets/ui/ui_panel_frame_wide.png"
	if not ResourceLoader.exists(path):
		return null
	# 新素材本身就是横向 16:10。直接等比贴满统一比例的弹窗，避免再次
	# 九宫格拉坏顶部宝珠、角花和侧边山水。
	var tex := TextureRect.new()
	tex.texture = load(path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tex


## 所有弹窗共用的内容安全区。额外给右栏留位时传 right_extra。
static func apply_popup_safe_area(node: Control, right_extra: float = 0.0) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = POPUP_INSET
	node.offset_top = POPUP_INSET
	node.offset_right = -POPUP_INSET - right_extra
	node.offset_bottom = -POPUP_INSET


## 统一关闭按钮：完全收在纹样内缘，不再压住右上角花纹。
static func popup_close(on_close: Callable) -> Button:
	var close := make_button("✕", TEXT_DIM, 40)
	close.custom_minimum_size = POPUP_CLOSE_SIZE
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -112
	close.offset_top = 62
	close.offset_right = -72
	close.offset_bottom = 96
	close.pressed.connect(on_close)
	return close


## 从九尾狐四帧横向精灵表取一帧，供面板、工具栏和战斗复用。
static func spirit_frame(frame_index: int = 0) -> Texture2D:
	var path := "res://assets/sprites/spirit_fox_idle.png"
	if not ResourceLoader.exists(path):
		return null
	var at := AtlasTexture.new()
	at.atlas = load(path) as Texture2D
	at.region = Rect2(clampi(frame_index, 0, 3) * 64, 0, 64, 64)
	return at


static func panel(bg: Color = INK_2, border: Color = LINE, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## 信息卡、交易面板和导航栏共用的青玉鎏金底衬。
## 比普通 panel 多一层阴影和 2px 描边，在复杂全景图上也能保持轮廓。
static func ornate_panel(bg: Color = Color(0.035, 0.07, 0.085, 0.94),
		accent: Color = JADE_DIM, radius: int = 10) -> StyleBoxFlat:
	var sb := panel(bg, accent, radius)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


static func nav_panel() -> StyleBoxFlat:
	var sb := ornate_panel(Color(0.025, 0.055, 0.065, 0.96), JADE_DIM, 0)
	sb.border_width_top = 0
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


static func button(node: Button, accent: Color = JADE) -> Button:
	var normal := panel(INK_3, accent.darkened(0.45), 6)
	var hover := panel(accent.darkened(0.72), accent, 6)
	var pressed := panel(accent.darkened(0.6), accent, 6)
	var disabled := panel(INK_2, LINE, 6)
	for sb in [normal, hover, pressed]:
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("disabled", disabled)
	node.add_theme_stylebox_override("focus", normal)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_disabled_color", TEXT_DIM)
	node.focus_mode = Control.FOCUS_NONE
	# 注意：不要在这里往 pressed 上连 lambda。Style 是 RefCounted，
	# static func 里造出来的 lambda 没有属主对象，一旦报错会**中断整条信号派发**，
	# 表现就是按钮看着能点、但 pressed 的回调不执行。
	# 点击音效改由 Audio 自己在 _input 里统一处理。
	return node


static func make_button(text: String, accent: Color = JADE, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 40)
	return button(b, accent)


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = 26) -> Label:
	return label(text, size, JADE)


## 半透明遮罩，弹窗用
static func scrim() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, 0.62)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c
