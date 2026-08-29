extends Control
##
## 游戏首页
##   正中「赛博修仙系统」 + 【开始游戏】【重置游戏】【退出】
##   开始游戏 = 读档继续；重置游戏 = 清档从头（路演/测试用）
##
## 【美术】需要一张首页主视觉背景图 → assets/ui/title_bg.png


var _status: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	Audio.bgm("title")

	# 背景：有图用图，没图用墨底渐变占位
	var bg_path := "res://assets/ui/title_bg.png"
	if ResourceLoader.exists(bg_path):
		var tex := TextureRect.new()
		tex.texture = load(bg_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
	else:
		var bg := ColorRect.new()
		bg.color = Style.INK
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		_add_placeholder_note()

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	# 水墨花字是一张透明标题组合图；若素材缺失，再退回可读的代码文字。
	var logo_path := "res://assets/ui/title_logo_ink.png"
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.custom_minimum_size = Vector2(650, 285)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(logo)
	else:
		var t := Style.label("赛博修仙系统", 72, Color("0c332b"))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_constant_override("outline_size", 12)
		t.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.92))
		box.add_child(t)
		var sub := Style.label("赛博修仙 · 迭代进化", 20, Color("7d5a1c"))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)

	var start := Style.make_button("开 始 游 戏", Style.JADE, 240)
	start.pressed.connect(func() -> void: get_parent().continue_game())
	box.add_child(start)

	var reset := Style.make_button("重 置 游 戏", Style.GOLD, 240)
	reset.tooltip_text = "清空存档，从头开始（路演 / 测试用）"
	reset.pressed.connect(_on_reset)
	box.add_child(reset)

	var quit := Style.make_button("退 出", Style.DANGER, 240)
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	# 桥状态，小字放右下角
	var status := Style.label("", 13, Style.TEXT_DIM)
	status.add_theme_constant_override("outline_size", 6)
	status.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
	status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	status.offset_left = -320
	status.offset_top = -34
	status.offset_right = -16
	status.offset_bottom = -12
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(status)

	_status = status
	_paint_bridge(Bridge.connected)
	Bridge.bridge_ok.connect(_paint_bridge)
	Bridge.check_health()


func _paint_bridge(ok: bool) -> void:
	if _status == null or not is_instance_valid(_status):
		return
	_status.text = "法宝桥：已通" if ok else "法宝桥：未连接（先跑 bridge.js）"
	_status.add_theme_color_override("font_color", Color("156b52") if ok else Color("9c2f2f"))


func _add_placeholder_note() -> void:
	var n := Style.label("【美术占位】首页主视觉 assets/ui/title_bg.png", 12, Style.TEXT_DIM)
	n.set_anchors_preset(Control.PRESET_TOP_LEFT)
	n.offset_left = 14
	n.offset_top = 10
	add_child(n)


func _on_reset() -> void:
	GameState.reset_game()
	var toast := Style.label("存档已清空", 16, Style.GOLD)
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_top = -90
	toast.offset_bottom = -60
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast)
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5)
	tw.tween_callback(toast.queue_free)
