extends Control
##
## 地图面板 —— 目前开放四张
## 【美术】每张地图一个缩略图 icon assets/ui/icon_<id>.png


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var world := get_parent().get_parent()

	var scrim := Style.scrim()
	scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			queue_free()
	)
	add_child(scrim)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.frame())
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)

	# PanelContainer 只认**一个**子节点 —— 内容和 ✕ 都得塞进同一个 holder 里，
	# 否则两个子节点会被容器同时拉满，整块布局直接塌掉（踩过：面板全空白）。
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(960, 600)
	card.add_child(holder)

	var fr := Style.frame_overlay()
	if fr != null:
		holder.add_child(fr)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	Style.apply_popup_safe_area(col)
	holder.add_child(col)
	col.add_child(Style.title("选择地图", 24))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	col.add_child(grid)

	for id in world.MAPS.keys():
		var info: Dictionary = world.MAPS[id]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.custom_minimum_size = Vector2(180, 0)
		grid.add_child(cell)

		# 缩略图（占位）
		var thumb := Panel.new()
		thumb.custom_minimum_size = Vector2(180, 110)
		var here: bool = (id == world.current_map)
		thumb.add_theme_stylebox_override("panel",
			Style.panel(Style.INK_3, Style.GOLD if here else Style.LINE, 8))
		cell.add_child(thumb)
		var ipath := "res://assets/ui/icon_%s.png" % id
		if ResourceLoader.exists(ipath):
			var it := TextureRect.new()
			it.texture = load(ipath)
			it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			it.set_anchors_preset(Control.PRESET_FULL_RECT)
			it.mouse_filter = Control.MOUSE_FILTER_IGNORE
			thumb.add_child(it)
		else:
			var tl := Style.label("icon_%s" % id, 12, Style.LINE)
			tl.set_anchors_preset(Control.PRESET_FULL_RECT)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			thumb.add_child(tl)

		cell.add_child(Style.label(str(info["name"]), 17,
			Style.GOLD if here else Style.JADE))

		var d := Style.label(str(info["desc"]), 12, Style.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(180, 52)
		cell.add_child(d)

		var mid := str(id)
		var b := Style.make_button("已在此处" if here else "前 往",
			Style.TEXT_DIM if here else Style.JADE, 180)
		b.disabled = here
		b.pressed.connect(func() -> void:
			world.goto_map(mid)
			queue_free()
		)
		cell.add_child(b)

	holder.add_child(Style.popup_close(queue_free))
