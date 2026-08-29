extends Control
##
## 秘境里的宗门据点 —— 师兄在这里
##
##   首次进来：领新手礼包（10 粒青芒草种子 + 20 张爆破符）
##   之后：找师兄交易，买种子 / 爆破符 / 灵液
##
## 【美术】据点内景、师兄立绘、交易界面边框

const ITEM_ICON := {
	"bomb": "res://assets/sprites/item_talisman.png",
	"seed": "res://assets/sprites/item_seed.png",
	"elixir": "res://assets/sprites/item_elixir.png",
}

var _world: Node
var _dialog: Label
var _shop_box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_world = get_parent().get_parent()

	var bg_path := "res://assets/ui/outpost_interior.png"
	if ResourceLoader.exists(bg_path):
		var tex := TextureRect.new()
		tex.texture = load(bg_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
		# 内景是亮的，压一层墨色让上面的文字读得清
		var dim := ColorRect.new()
		dim.color = Color(0.04, 0.05, 0.09, 0.50)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	else:
		var bg := ColorRect.new()
		bg.color = Color("1b1726")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 80
	row.offset_right = -80
	row.offset_top = 80
	row.offset_bottom = -110
	row.add_theme_constant_override("separation", 28)
	add_child(row)

	# ---- 左：师兄 ----
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)

	# 立绘本身带透明背景，不要再套框 —— 会把人裁掉
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(0, 340)
	left.add_child(portrait)

	var sx_path := "res://assets/ui/npc_shixiong.png"
	if ResourceLoader.exists(sx_path):
		var av := TextureRect.new()
		av.texture = load(sx_path)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		av.set_anchors_preset(Control.PRESET_FULL_RECT)
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(av)
	else:
		var pl := Style.label("【美术占位】\n师兄立绘", 15, Style.TEXT_DIM)
		pl.set_anchors_preset(Control.PRESET_FULL_RECT)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		portrait.add_child(pl)

	left.add_child(Style.title("师兄 · 陆行舟", 22))

	_dialog = Style.label("", 16, Style.TEXT)
	_dialog.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog.custom_minimum_size = Vector2(0, 96)
	left.add_child(_dialog)

	# ---- 右：交易 ----
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)

	# 交易区压在亮内景上，加个底衬才读得清
	var right_bg := PanelContainer.new()
	right_bg.add_theme_stylebox_override("panel",
		Style.ornate_panel(Color(0.035, 0.065, 0.085, 0.92), Style.GOLD.darkened(0.25), 10))
	right.add_child(right_bg)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 10)
	right_bg.add_child(right_col)
	right_col.add_child(Style.title("交易", 20))
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", Style.GOLD.darkened(0.35))
	right_col.add_child(divider)
	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 8)
	right_col.add_child(_shop_box)

	# ---- 底：出门 ----
	var back := Style.make_button("进入青芜原", Style.JADE, 220)
	back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	back.grow_horizontal = Control.GROW_DIRECTION_BOTH
	back.offset_top = -104
	back.offset_bottom = -60
	back.pressed.connect(func() -> void: _world.goto_map("qingwu"))
	add_child(back)

	GameState.stones_changed.connect(func(_v: int) -> void: _build_shop())
	GameState.inventory_changed.connect(_build_shop)

	_refresh_dialog()
	_build_shop()


func _refresh_dialog() -> void:
	if not GameState.flags.get("gift_claimed", false):
		_dialog.text = "师妹来啦。刚筑基就被派来青芜原，宗门是看得起你。\n\n这地方灵气是厚，就是荒得很——先拿套家伙什。"
	else:
		_dialog.text = "符箓和种子用完了就来找我。\n\n没灵石？那就去做功课。你那本命法器可不是摆着好看的。"


func _build_shop() -> void:
	for c in _shop_box.get_children():
		c.queue_free()

	if not GameState.flags.get("gift_claimed", false):
		var gift := Style.make_button("领取新手礼包", Style.GOLD, 240)
		gift.pressed.connect(_claim_gift)
		_shop_box.add_child(gift)
		_shop_box.add_child(Style.label(
			"10 粒%s种子 · 20 张爆破符" % GameState.HERB_NAME, 14, Style.TEXT_DIM))
		return

	for key in ["seed", "bomb", "elixir"]:
		var price: int = GameState.PRICE[key]

		# 每样商品一张卡：图标 + 名称/持有 + 价格 + 买
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel",
			Style.ornate_panel(Color(0.055, 0.085, 0.105, 0.96),
				Style.GOLD.darkened(0.25) if key == "elixir" else Style.JADE_DIM, 8))
		_shop_box.add_child(row)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(line)

		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(40, 40)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ip: String = ITEM_ICON.get(key, "")
		if ip != "" and ResourceLoader.exists(ip):
			ic.texture = load(ip)
		line.add_child(ic)

		var meta := VBoxContainer.new()
		meta.add_theme_constant_override("separation", 2)
		meta.custom_minimum_size = Vector2(150, 0)
		line.add_child(meta)
		meta.add_child(Style.label(GameState.ITEM_NAME[key], 15, Style.TEXT))
		meta.add_child(Style.label("持有 %d" % GameState.item_count(key), 12, Style.TEXT_DIM))
		if key == "elixir":
			var note := Style.label("立刻催熟一株%s，可直接收割" % GameState.HERB_NAME,
				10, Style.JADE)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			meta.add_child(note)

		var price_box := HBoxContainer.new()
		price_box.add_theme_constant_override("separation", 4)
		price_box.custom_minimum_size = Vector2(78, 0)
		line.add_child(price_box)
		var si := TextureRect.new()
		si.custom_minimum_size = Vector2(18, 18)
		si.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		si.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists("res://assets/ui/icon_stone.png"):
			si.texture = load("res://assets/ui/icon_stone.png")
		price_box.add_child(si)
		price_box.add_child(Style.label("%d" % price, 15, Style.GOLD))

		var k: String = key
		var b1 := Style.make_button("买 1", Style.JADE, 66)
		b1.pressed.connect(func() -> void: _buy(k, 1))
		line.add_child(b1)

		var b5 := Style.make_button("买 5", Style.JADE, 66)
		b5.pressed.connect(func() -> void: _buy(k, 5))
		line.add_child(b5)



func _claim_gift() -> void:
	GameState.add_item("seed", 10)
	GameState.add_item("bomb", 20)
	GameState.flags["gift_claimed"] = true
	GameState.save_game()
	_refresh_dialog()
	_build_shop()
	_world.toast("领到 10 粒%s种子、20 张爆破符" % GameState.HERB_NAME, Style.GOLD)


func _buy(key: String, n: int) -> void:
	var cost: int = GameState.PRICE[key] * n
	if not GameState.spend_stones(cost):
		_world.toast("灵石不够 —— 去任务列表做功课赚灵石", Style.DANGER)
		return
	GameState.add_item(key, n)
	_world.toast("购得 %s ×%d，花去 %d 灵石" % [GameState.ITEM_NAME[key], n, cost], Style.GOLD)
