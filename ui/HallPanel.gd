extends Control
##
## 宗门大殿 —— 领取筑基期第一个「历练任务」：初探青芜原
##
## 历练任务是策划案里的第三种任务类型：专门在秘境里发布、有利于探索秘境。
## 它不走法宝桥（不是让 Agent 干的活），是引导玩家进秘境的剧情任务。


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var world := get_parent().get_parent()
	var taken: bool = GameState.flags.get("quest_qingwu_taken", false)

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

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(896, 560)
	card.add_child(holder)

	var fr := Style.frame_overlay()
	if fr != null:
		holder.add_child(fr)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	Style.apply_popup_safe_area(col, 240)
	# 左侧云纹比普通弹窗更厚，正文再向右让出一段独立安全区。
	col.offset_left += 30
	holder.add_child(col)

	col.add_child(Style.title("万象宗 · 宗门大殿", 24))
	# 执事立绘放右侧，不挤正文
	var zs_path := "res://assets/ui/npc_zhishi.png"
	if ResourceLoader.exists(zs_path):
		var zs := TextureRect.new()
		zs.texture = load(zs_path)
		zs.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		zs.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		zs.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		zs.offset_left = -292
		zs.offset_top = 92
		zs.offset_right = -72
		zs.offset_bottom = -64
		zs.modulate.a = 0.9
		zs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(zs)

	var intro := Style.label(
		"执事抬眼看你：\n\n「筑基了，法器也认了主。宗门在青芜原有一处据点，那边荒得很，正缺人手。」\n\n「去吧。这是你这一境的第一个历练任务。」",
		15, Style.TEXT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)

	var quest := PanelContainer.new()
	quest.add_theme_stylebox_override("panel", Style.panel(Style.INK_3, Style.JADE_DIM, 8))
	col.add_child(quest)

	var qc := VBoxContainer.new()
	qc.add_theme_constant_override("separation", 6)
	quest.add_child(qc)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	qc.add_child(head)
	head.add_child(Style.label("[历练]", 13, Style.JADE))
	head.add_child(Style.label("初探青芜原", 18, Style.TEXT))
	qc.add_child(Style.label(
		"前往秘境青芜原，找到宗门据点的师兄，领取新手用度，开出第一片灵田。",
		14, Style.TEXT_DIM))

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	col.add_child(btns)

	if taken:
		btns.add_child(Style.label("已接取 —— 去地图选「秘境·青芜原」", 14, Style.JADE))
	else:
		var accept := Style.make_button("接 取 任 务", Style.GOLD, 160)
		accept.pressed.connect(func() -> void:
			GameState.flags["quest_qingwu_taken"] = true
			GameState.save_game()
			queue_free()
			# 接了任务直接进秘境的据点，师兄在那儿等着
			world.goto_map("outpost")
			world.toast("已接取「初探青芜原」，你被传送至秘境据点", Style.GOLD)
		)
		btns.add_child(accept)

	holder.add_child(Style.popup_close(queue_free))
