extends Control
##
## 游戏世界外壳
##
##   左上：玩家信息 / 地图 / 任务列表 三个入口（任务列表带小红点）
##   右上：灵石、等级
##   底部：工具格（数字键 1/2/3 切换，鼠标左键使用）
##   中间：当前地图
##
## 地图分两类：
##   · 秘境-青芜原 → 直接是核心玩法界面（Mijing.gd）
##   · 其余三张   → 全景图 + 可点击分区（HotspotMap.gd）
##

const Mijing      := preload("res://scenes/Mijing.gd")
const Outpost     := preload("res://scenes/Outpost.gd")
const HotspotMap  := preload("res://scenes/HotspotMap.gd")
const PlayerPanel := preload("res://ui/PlayerPanel.gd")
const MapPanel    := preload("res://ui/MapPanel.gd")
const TaskPanel   := preload("res://ui/TaskPanel.gd")
const BridgeGuide := preload("res://ui/BridgeGuide.gd")

# 目前开放的四张地图
const MAPS := {
	"jiezi":   {"name": "芥子空间", "desc": "入宗门即得的私人洞府，兼作背包与展柜。",
				"zones": ["丹房", "藏经阁", "器室", "灵田", "展柜"]},
	"zongmen": {"name": "万象宗",   "desc": "你的宗门。道统：AI 产品经理 · 主脉产品脉。",
				"zones": ["宗门大殿", "讲坛", "宗门商店", "执事堂", "演武场"]},
	"wenxian": {"name": "问仙镇",   "desc": "求仙问道之人汇集之地，宗门考核在此举行。",
				"zones": ["问道石", "坊市", "客栈", "传送阵"]},
	"qingwu":  {"name": "秘境·青芜原", "desc": "筑基期历练秘境。开荒、种植、与灵兽周旋。",
				"zones": []},
}

# 工具格图标
const ITEM_ICON := {
	"bomb": "res://assets/sprites/item_talisman.png",
	"seed": "res://assets/sprites/item_seed.png",
	"elixir": "res://assets/sprites/item_elixir.png",
	"spirit": "res://assets/sprites/spirit_fox_idle.png",
	"herb": "res://assets/sprites/item_herb.png",
}
const TOOLBAR_DISPLAY := ["bomb", "seed", "elixir", "spirit", "herb"]

var current_map := "zongmen"

var _map_host: Control
var _panel_host: Control
var _stone_label: Label
var _level_label: Label
var _task_dot: Panel
var _toolbar: Control
var _toolbar_slots: Array[Panel] = []
var _toolbar_items: Array[Control] = []
var _toolbar_labels: Array[Label] = []
var _bridge_label: Button
var _toast: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 自己不吃鼠标事件，否则会截住要传给秘境的点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Style.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_map_host = Control.new()
	_map_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_host.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_map_host)

	_build_topbar()
	_build_toolbar()

	_panel_host = Control.new()
	_panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_host)

	GameState.stones_changed.connect(func(_v: int) -> void: _refresh_topbar())
	GameState.exp_changed.connect(func(_a: int, _b: int) -> void: _refresh_topbar())
	GameState.inventory_changed.connect(_refresh_toolbar)
	GameState.tasks_changed.connect(_refresh_topbar)
	Bridge.bridge_ok.connect(_on_bridge_ok)

	goto_map(current_map)
	_refresh_topbar()
	_refresh_toolbar()


# ---------------------------------------------------------------- 顶栏

func _build_topbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Style.nav_panel())
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 64
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	var b_player := _icon_button("道身", "icon_daoshen")
	b_player.pressed.connect(func() -> void: open_panel(PlayerPanel.new()))
	row.add_child(b_player)

	var b_map := _icon_button("地图", "icon_map")
	b_map.pressed.connect(func() -> void: open_panel(MapPanel.new()))
	row.add_child(b_map)

	# 任务列表按钮 + 小红点
	var task_wrap := Control.new()
	task_wrap.custom_minimum_size = Vector2(92, 40)
	row.add_child(task_wrap)

	var b_task := _icon_button("任务", "icon_task")
	b_task.set_anchors_preset(Control.PRESET_FULL_RECT)
	b_task.offset_right = -12
	b_task.pressed.connect(func() -> void: open_panel(TaskPanel.new()))
	task_wrap.add_child(b_task)

	_task_dot = Panel.new()
	_task_dot.add_theme_stylebox_override("panel", Style.panel(Style.DANGER, Style.DANGER, 7))
	_task_dot.custom_minimum_size = Vector2(14, 14)
	_task_dot.position = Vector2(70, 2)
	_task_dot.size = Vector2(14, 14)
	_task_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_task_dot.visible = false
	task_wrap.add_child(_task_dot)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# 桥的状态做成可点的，点开就是绑定引导
	var bridge_btn := Style.make_button("", Style.TEXT_DIM, 0)
	bridge_btn.custom_minimum_size = Vector2(96, 34)
	bridge_btn.pressed.connect(func() -> void: open_panel(BridgeGuide.new()))
	bridge_btn.tooltip_text = "点开看怎么绑定本命法器"
	row.add_child(bridge_btn)
	_bridge_label = bridge_btn

	_level_label = Style.label("", 15, Style.TEXT)
	row.add_child(_level_label)

	var stone_icon := TextureRect.new()
	stone_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stone_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stone_icon.custom_minimum_size = Vector2(22, 22)
	stone_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/ui/icon_stone.png"):
		stone_icon.texture = load("res://assets/ui/icon_stone.png")
	row.add_child(stone_icon)

	_stone_label = Style.label("", 16, Style.GOLD)
	row.add_child(_stone_label)


func _on_bridge_ok(_ok: bool) -> void:
	_refresh_topbar()


## 带图标的入口按钮。没图就退回纯文字。
func _icon_button(text: String, icon_name: String) -> Button:
	var b := Style.make_button(text, Style.JADE, 92)
	var path := "res://assets/ui/%s.png" % icon_name
	if ResourceLoader.exists(path):
		b.icon = load(path)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 22)
		b.add_theme_constant_override("h_separation", 6)
	return b


func _refresh_topbar() -> void:
	if _stone_label == null:
		return
	_stone_label.text = "%d" % GameState.stones
	_level_label.text = "%s · Lv%d  (%d/%d)" % [
		GameState.realm, GameState.level, GameState.exp_value, GameState.exp_to_next]
	_bridge_label.text = "法宝桥 ●" if Bridge.connected else "法宝桥 ○"
	_bridge_label.add_theme_color_override(
		"font_color", Style.JADE if Bridge.connected else Style.DANGER)
	_task_dot.visible = GameState.unclaimed_count() > 0


# ---------------------------------------------------------------- 工具格

func _build_toolbar() -> void:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		Style.ornate_panel(Color(0.03, 0.055, 0.07, 0.95), Style.GOLD.darkened(0.28), 10))
	wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wrap.offset_top = -116
	wrap.offset_bottom = -10
	add_child(wrap)
	_toolbar = wrap

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(row)

	for i in range(TOOLBAR_DISPLAY.size()):
		var key: String = TOOLBAR_DISPLAY[i]
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		item.alignment = BoxContainer.ALIGNMENT_CENTER
		item.visible = key != "herb" or GameState.herb_slot_unlocked()
		row.add_child(item)
		_toolbar_items.append(item)

		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(82, 62)
		item.add_child(slot)
		_toolbar_slots.append(slot)

		# 边框内部只放图标；名称和数量独立放在纹样下方，永不互相覆盖。
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 10
		icon.offset_right = -10
		icon.offset_top = 6
		icon.offset_bottom = -6
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ipath: String = ITEM_ICON.get(key, "")
		if key == "spirit":
			icon.texture = Style.spirit_frame(0)
		elif ipath != "" and ResourceLoader.exists(ipath):
			icon.texture = load(ipath)
		slot.add_child(icon)

		var lab := Style.label("", 12, Style.TEXT)
		lab.name = "Label"
		lab.custom_minimum_size = Vector2(82, 20)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(lab)
		_toolbar_labels.append(lab)

		if i < GameState.TOOLBAR.size():
			var idx := i
			slot.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed:
					GameState.selected_tool = idx
					_refresh_toolbar()
			)
		else:
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_toolbar() -> void:
	for i in range(_toolbar_slots.size()):
		var key: String = TOOLBAR_DISPLAY[i]
		var slot := _toolbar_slots[i]
		var on := (i < GameState.TOOLBAR.size() and i == GameState.selected_tool)
		_toolbar_items[i].visible = key != "herb" or GameState.herb_slot_unlocked()
		# 有槽位贴图就用贴图，没有退回描边色块
		var sp := "res://assets/ui/ui_slot%s.png" % ("_active" if on else "")
		if ResourceLoader.exists(sp):
			var sb := StyleBoxTexture.new()
			sb.texture = load(sp)
			sb.set_texture_margin_all(14)      # 九宫格拉伸，四角不变形
			slot.add_theme_stylebox_override("panel", sb)
		else:
			slot.add_theme_stylebox_override("panel",
				Style.panel(Style.INK_3 if on else Style.INK_2,
							Style.GOLD if on else Style.LINE, 6))
		var lab: Label = _toolbar_labels[i]
		if key == "spirit":
			lab.text = "4 器灵 · Lv.%d" % GameState.SPIRIT_LEVEL
		elif key == "herb":
			lab.text = "%s · ×%d" % [GameState.HERB_NAME, GameState.item_count("herb")]
		else:
			lab.text = "%d %s · ×%d" % [i + 1, GameState.ITEM_NAME[key], GameState.item_count(key)]
		slot.tooltip_text = GameState.ITEM_NAME[key]
		lab.add_theme_color_override("font_color", Style.TEXT if on else Style.TEXT_DIM)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k >= KEY_1 and k < KEY_1 + GameState.TOOLBAR.size():
			GameState.selected_tool = k - KEY_1
			_refresh_toolbar()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 地图 / 面板

func goto_map(id: String) -> void:
	current_map = id
	for c in _map_host.get_children():
		c.queue_free()

	var node: Node
	match id:
		"qingwu":  node = Mijing.new()
		"outpost": node = Outpost.new()
		_:         node = HotspotMap.new(id, MAPS[id])
	_map_host.add_child(node)

	# 工具格是秘境开荒用的，别的地图不显示
	if _toolbar:
		_toolbar.visible = (id == "qingwu")

	# 每张地图一首背景音乐。据点在秘境里，沿用青芜原那首。
	Audio.bgm("qingwu" if id == "outpost" else id)


func open_panel(panel: Control) -> void:
	_panel_host.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tree_exited.connect(func() -> void:
		if is_instance_valid(_panel_host) and _panel_host.get_child_count() <= 1:
			_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)
	_panel_host.add_child(panel)


func toast(msg: String, color: Color = Style.TEXT) -> void:
	# 位置要同时避开两样东西：秘境的工具格（底部 -84..-14）
	# 和据点的「走出据点」按钮（-104..-60）。所以统一放在它们上方。
	# 连续操作时旧提示还没淡完，新的会叠上去糊成一团 —— 所以先把旧的清掉
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel",
		Style.panel(Color(0.04, 0.06, 0.09, 0.94), Style.LINE, 8))
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = -168
	box.offset_bottom = -126
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_toast = box

	var l := Style.label(msg, 16, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)

	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(box, "modulate:a", 0.0, 0.5)
	tw.tween_callback(box.queue_free)
