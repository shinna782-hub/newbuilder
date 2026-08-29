extends Control
##
## 非玩法地图（芥子空间 / 万象宗 / 问仙镇）
##   一张全景图 + 若干可点击分区。点分区弹出对应内容。
##
## 【美术】每张地图需要：缩略图 icon + 一张全景图 assets/ui/map_<id>.png

var _id: String
var _info: Dictionary


func _init(id: String = "", info: Dictionary = {}) -> void:
	_id = id
	_info = info
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	var bg_path := "res://assets/ui/map_%s.png" % _id
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
		bg.color = Color("16202b")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	# 只在文字附近铺局部墨底，不再牺牲整张全景图的亮度。
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel",
		Style.ornate_panel(Color(0.025, 0.06, 0.075, 0.86), Style.GOLD.darkened(0.25), 12))
	info_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	info_panel.offset_top = -292
	info_panel.offset_bottom = -76
	add_child(info_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(860, 0)
	info_panel.add_child(box)

	var t := Style.title(str(_info.get("name", _id)), 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 5)
	t.add_theme_color_override("font_outline_color", Color(0.01, 0.04, 0.05, 0.9))
	box.add_child(t)

	var d := Style.label(str(_info.get("desc", "")), 15, Style.TEXT)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(d)

	var grid := HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 12)
	box.add_child(grid)

	for z in _info.get("zones", []):
		var zone := str(z)
		var available := zone == "宗门大殿"
		var b := Style.make_button(zone if available else "%s\n本期未开放" % zone,
			Style.GOLD if available else Style.TEXT_DIM, 116)
		b.custom_minimum_size = Vector2(116, 52)
		b.disabled = not available
		b.tooltip_text = "进入%s" % zone if available else "%s将在后续版本开放" % zone
		if available:
			b.pressed.connect(func() -> void: _enter_zone(zone))
		grid.add_child(b)


func _enter_zone(zone: String) -> void:
	var world := get_parent().get_parent()
	match zone:
		"宗门大殿":
			world.open_panel(preload("res://ui/HallPanel.gd").new())
		_:
			pass
