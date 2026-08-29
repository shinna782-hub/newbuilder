extends Control
##
## 开场：3 段解说 + 3 段 PV 交替播放
##
##   解说1 → PV1 → 解说2 → PV2 → 解说3 → PV3 → 【开始修炼】
##
## 右上角常驻【跳过开场】，测试时直接进游戏。
##
## PV 用帧序列播放（assets/video/<id>/f%03d.jpg）——
## Godot 4 原生只认 Ogg Theora，而这台机器的 ffmpeg 没有 theora 编码器；
## 4 秒的过场用帧序列反而更稳，也不引入额外依赖。

const FPS := 12.0

# 按剧本顺序排的步骤表
const STEPS := [
	{"type": "text", "body": "灵能复苏之后，人类进入「赛博修仙」纪元。\n\n科学与玄学共存，天地间弥漫的不再是灵气，是算力。\n人人皆有本命法器，人机共同修炼进化。\n\n每年，问仙镇都会汇集求仙问道的有志之士，参与宗门考核。"},
	{"type": "video", "id": "26080118044326194"},
	{"type": "text", "body": "你经过问道石测灵根，明确了自己的道统，\n获得十境六脉的《本命功法》，\n\n顺利加入了宗门——万象宗。"},
	{"type": "video", "id": "26080118175164449"},
	{"type": "text", "body": "你在洗精伐髓、塑造道身之后，刻苦修炼半年，\n终于突破筑基期，绑定了本命法器，\n\n即将被宗门派往秘境「青芜原」历练。"},
	{"type": "video", "id": "26080118120135627"},
]

var _step := 0
var _frames: Array[Texture2D] = []
var _frame_idx := 0
var _accum := 0.0
var _playing := false

var _bg: ColorRect
var _text: Label
var _film: TextureRect
var _hint: Label
var _start_btn: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	Audio.bgm("title")          # 开场沿用首页那首，不打断

	_bg = ColorRect.new()
	_bg.color = Style.INK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_film = TextureRect.new()
	_film.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_film.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_film.set_anchors_preset(Control.PRESET_FULL_RECT)
	_film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film.visible = false
	add_child(_film)

	_text = Style.label("", 22, Style.TEXT)
	_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text.offset_left = 180
	_text.offset_right = -180
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 不再放横贯屏幕的黑条；用深色描边和柔和阴影贴着字保证可读。
	_text.add_theme_constant_override("outline_size", 9)
	_text.add_theme_color_override("font_outline_color", Color(0.02, 0.07, 0.08, 0.92))
	_text.add_theme_constant_override("shadow_offset_x", 0)
	_text.add_theme_constant_override("shadow_offset_y", 3)
	_text.add_theme_constant_override("shadow_outline_size", 5)
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)

	_hint = Style.label("点击任意处继续", 14, Style.TEXT_DIM)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -200
	_hint.offset_right = 200
	_hint.offset_top = -56
	_hint.offset_bottom = -30
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	var skip := Style.make_button("跳过开场", Style.TEXT_DIM, 110)
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -130
	skip.offset_top = 16
	skip.offset_right = -20
	skip.offset_bottom = 52
	skip.pressed.connect(_finish)
	add_child(skip)

	_start_btn = Style.make_button("开 始 修 炼", Style.JADE, 220)
	_start_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_btn.offset_left = -110
	_start_btn.offset_right = 110
	_start_btn.offset_top = -110
	_start_btn.offset_bottom = -62
	_start_btn.visible = false
	_start_btn.pressed.connect(_finish)
	add_child(_start_btn)

	_show_step()


func _gui_input(event: InputEvent) -> void:
	if _clicked(event):
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _clicked(event):
		_advance()
	# 键盘也能翻页：空格 / 回车。鼠标万一被别的控件吃掉还有条退路。
	elif event is InputEventKey and event.pressed and not event.echo \
			and not _start_btn.visible:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER:
			_advance()


func _clicked(event: InputEvent) -> bool:
	return event is InputEventMouseButton \
		and event.pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and not _start_btn.visible


func _advance() -> void:
	Audio.stop_narration()          # 翻页就掐掉当前旁白，别叠到下一段
	_step += 1
	if _step >= STEPS.size():
		_show_start()
	else:
		_show_step()


func _show_step() -> void:
	var s: Dictionary = STEPS[_step]
	_playing = false
	_frames.clear()
	_frame_idx = 0
	_accum = 0.0

	if s["type"] == "text":
		# 解说页也有背景图了（第 1/2/3 页各一张）
		var bgp := "res://assets/ui/intro_bg_%d.png" % (_step / 2 + 1)
		if ResourceLoader.exists(bgp):
			_film.texture = load(bgp)
			_film.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			_film.visible = true
			_film.modulate = Color(1, 1, 1, 0.92)
		else:
			_film.visible = false
		_text.visible = true
		_text.text = str(s["body"])
		_text.modulate.a = 0.0
		create_tween().tween_property(_text, "modulate:a", 1.0, 0.6)
		_hint.text = "点击任意处继续"
	else:
		_text.visible = false
		_film.visible = true
		_film.modulate = Color(1, 1, 1, 1)
		_film.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		_load_frames(str(s["id"]))
		# 原视频里的旁白，跟帧序列一起放（两者都是 4.06 秒，天然对得上）
		Audio.play_narration("res://assets/video/%s.mp3" % s["id"])
		_hint.text = "点击任意处跳过本段"


func _load_frames(id: String) -> void:
	_frames.clear()
	var dir_path := "res://assets/video/%s" % id
	# PCK 会保存导入纹理的 remap，但不会可靠保留可枚举的原始 JPG 目录项。
	# 三段 PV 的制作契约固定为 f001..f049，直接构造资源路径才能同时适用于
	# 编辑器与导出应用；运行时扫描目录会在导出包里得到空序列。
	for i in range(1, 50):
		var frame_path := "%s/f%03d.jpg" % [dir_path, i]
		var tex := _load_frame_texture(frame_path)
		if tex != null:
			_frames.append(tex)
	if _frames.is_empty():
		_film.visible = false
		_text.visible = true
		_text.text = "【PV %s】\n（帧序列为空，点击继续）" % id
		return
	_film.texture = _frames[0]
	_playing = true


## 路径由固定帧契约生成；打包前 --import 会保证这些路径都有导入纹理 remap。
func _load_frame_texture(frame_path: String) -> Texture2D:
	var imported: Resource = load(frame_path)
	if imported is Texture2D:
		return imported as Texture2D
	return null


func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return
	_accum += delta
	var step_time := 1.0 / FPS
	while _accum >= step_time:
		_accum -= step_time
		_frame_idx += 1
		if _frame_idx >= _frames.size():
			# 播完自动往下走
			_playing = false
			_advance()
			return
		_film.texture = _frames[_frame_idx]


func _show_start() -> void:
	_playing = false
	# 最后一页复用第三张解说背景，别突然变纯黑
	var bgp := "res://assets/ui/intro_bg_3.png"
	if ResourceLoader.exists(bgp):
		_film.texture = load(bgp)
		_film.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_film.modulate = Color(1, 1, 1, 0.92)
		_film.visible = true
	else:
		_film.visible = false
	_text.visible = true
	_text.text = "青芜原就在山门之外。\n\n去吧。"
	_hint.visible = false
	_start_btn.visible = true


func _finish() -> void:
	Audio.stop_narration()
	GameState.mark_intro_seen()
	get_parent().goto_world()


func _exit_tree() -> void:
	Audio.stop_narration()
