extends Control
##
## 道身面板
##   道身立绘 · 昵称 · 十境图 · 六脉技能树 · 本命法器
##
## 【美术】道身立绘（女性道长）、十境图腾（万象宗版）、六脉窍位图标

const REALMS := ["凡人", "练气", "筑基", "金丹", "元婴", "化神", "合体", "大乘", "渡劫", "飞升"]

var _spirit_icon: TextureRect
var _spirit_anim := 0.0
var _spirit_frame := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
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
	holder.custom_minimum_size = Vector2(1024, 640)
	card.add_child(holder)

	var fr := Style.frame_overlay()
	if fr != null:
		holder.add_child(fr)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	Style.apply_popup_safe_area(row)
	holder.add_child(row)

	# ---- 左：道身 ----
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(220, 0)
	row.add_child(left)

	var portrait := Panel.new()
	portrait.add_theme_stylebox_override("panel", Style.panel(Style.INK_3, Style.JADE_DIM, 10))
	portrait.custom_minimum_size = Vector2(200, 210)
	left.add_child(portrait)

	var avatar_path := "res://assets/ui/avatar_daoshen.png"
	if ResourceLoader.exists(avatar_path):
		var av := TextureRect.new()
		av.texture = load(avatar_path)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.set_anchors_preset(Control.PRESET_FULL_RECT)
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(av)
	else:
		var ph := Style.label("【美术占位】\n道身立绘\n（女性道长）", 14, Style.TEXT_DIM)
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		portrait.add_child(ph)

	left.add_child(Style.title(GameState.player_name, 24))
	left.add_child(Style.label("%s · Lv%d" % [GameState.realm, GameState.level], 15, Style.TEXT))

	var bar := ProgressBar.new()
	bar.max_value = GameState.exp_to_next
	bar.value = GameState.exp_value
	bar.custom_minimum_size = Vector2(0, 18)
	bar.show_percentage = false
	left.add_child(bar)
	left.add_child(Style.label("经验 %d / %d" % [GameState.exp_value, GameState.exp_to_next],
		13, Style.TEXT_DIM))

	left.add_child(Style.label("本命法器 · 器灵", 14, Style.TEXT_DIM))
	var art_row := HBoxContainer.new()
	art_row.add_theme_constant_override("separation", 8)
	left.add_child(art_row)

	var artifact_card := PanelContainer.new()
	artifact_card.custom_minimum_size = Vector2(102, 86)
	artifact_card.add_theme_stylebox_override("panel", Style.panel(Style.INK_3, Style.GOLD.darkened(0.35), 8))
	art_row.add_child(artifact_card)
	var ac := VBoxContainer.new()
	ac.alignment = BoxContainer.ALIGNMENT_CENTER
	artifact_card.add_child(ac)
	var an := Style.label(GameState.artifact, 18, Style.GOLD)
	an.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ac.add_child(an)
	var rebind := Style.make_button("本命法器", Style.TEXT_DIM, 82)
	rebind.disabled = true
	rebind.tooltip_text = "已认主"
	ac.add_child(rebind)

	var spirit_card := PanelContainer.new()
	spirit_card.custom_minimum_size = Vector2(102, 86)
	spirit_card.add_theme_stylebox_override("panel", Style.panel(Style.INK_3, Style.JADE_DIM, 8))
	art_row.add_child(spirit_card)
	var sc := VBoxContainer.new()
	sc.alignment = BoxContainer.ALIGNMENT_CENTER
	spirit_card.add_child(sc)
	_spirit_icon = TextureRect.new()
	_spirit_icon.custom_minimum_size = Vector2(64, 54)
	_spirit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spirit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spirit_icon.texture = Style.spirit_frame(0)
	_spirit_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(_spirit_icon)
	var sn := Style.label("%s · Lv.%d" % [GameState.SPIRIT_NAME, GameState.SPIRIT_LEVEL], 12, Style.JADE)
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc.add_child(sn)

	# ---- 右：十境 + 六脉 ----
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)

	right.add_child(Style.title("十境", 20))
	right.add_child(_build_realms())
	right.add_child(Style.label(
		"整体境界 = 六脉中最短的那一条（木桶模型）", 12, Style.TEXT_DIM))

	var gap2 := Control.new(); gap2.custom_minimum_size = Vector2(0, 6)
	right.add_child(gap2)

	right.add_child(Style.title("六脉 · 一脉十窍", 20))
	right.add_child(_build_meridians())

	holder.add_child(Style.popup_close(queue_free))
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_spirit_icon):
		return
	_spirit_anim += delta
	if _spirit_anim >= 0.24:
		_spirit_anim = 0.0
		_spirit_frame = (_spirit_frame + 1) % 4
		_spirit_icon.texture = Style.spirit_frame(_spirit_frame)


func _build_realms() -> Control:
	# 有图腾条就把窍位点画在图腾上
	var totem := "res://assets/ui/realm_totem.png"
	if ResourceLoader.exists(totem):
		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(640, 84)
		var t := TextureRect.new()
		t.texture = load(totem)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(t)

		# 没到的境界压暗，一眼看出走到哪了
		var mask := Control.new()
		mask.set_anchors_preset(Control.PRESET_FULL_RECT)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.draw.connect(func() -> void:
			var w := mask.size.x / float(REALMS.size())
			for i in range(REALMS.size()):
				if i > GameState.realm_index - 1:
					mask.draw_rect(Rect2(i * w, 0, w, mask.size.y),
						Color(0.03, 0.05, 0.08, 0.62), true)
		)
		wrap.add_child(mask)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		row.offset_top = -22
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(row)
		for i in range(REALMS.size()):
			var cur := i == GameState.realm_index - 1
			var lit := i <= GameState.realm_index - 1
			var l := Style.label(REALMS[i], 11,
				Style.GOLD if cur else (Style.TEXT if lit else Style.TEXT_DIM))
			l.custom_minimum_size = Vector2(56, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(l)
		return wrap

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for i in range(REALMS.size()):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		box.add_child(cell)

		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(20, 20)
		var lit := i <= GameState.realm_index - 1
		var cur := i == GameState.realm_index - 1
		dot.add_theme_stylebox_override("panel", Style.panel(
			Style.GOLD if cur else (Style.JADE if lit else Style.INK_3),
			Style.GOLD if cur else Style.LINE, 10))
		cell.add_child(dot)

		var l := Style.label(REALMS[i], 11,
			Style.GOLD if cur else (Style.TEXT if lit else Style.TEXT_DIM))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(l)
	return box


## 六脉：直接用那张六芒放射图（太极为心，六条脉各十窍），
## 沿每条脉画一段发光表示已通几窍。之前拿它当 30% 透明的背景垫在圆点后面，
## 等于把最好的一张素材浪费了。
const ARM_DEG := {          # 每条脉对应放射图上的一条臂
	"产品脉": 90.0, "技术脉": 30.0, "商业脉": 330.0,
	"内容脉": 270.0, "表达脉": 210.0, "思维脉": 150.0,
}
const ARM_R0 := 46.0        # 第一窍离中心的距离
const ARM_R1 := 176.0       # 第十窍


func _build_meridians() -> Control:
	var tree := "res://assets/ui/meridian_tree.png"
	if not ResourceLoader.exists(tree):
		return _build_meridians_fallback()

	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(540, 220)

	var bg := TextureRect.new()
	bg.texture = load(tree)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bg)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(func() -> void:
		var c := overlay.size * 0.5
		var scale: float = minf(overlay.size.x / 720.0, overlay.size.y / 420.0)
		var f := ThemeDB.fallback_font
		for key in GameState.MERIDIAN_ORDER:
			var n: int = GameState.meridians.get(key, 0)
			var deg: float = ARM_DEG[key]
			var dir := Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))
			var is_main: bool = (key == "产品脉")
			var col := Style.GOLD if is_main else Style.JADE

			# 已通的那一段：从内往外描一条渐亮的光
			for i in range(n):
				var t := float(i) / 9.0
				var r: float = (ARM_R0 + (ARM_R1 - ARM_R0) * t) * scale
				var pos := c + dir * r
				overlay.draw_circle(pos, 9.0 * scale, Color(col.r, col.g, col.b, 0.22))
				overlay.draw_circle(pos, 5.0 * scale, col)

			# 脉名 + 窍数写在臂的外端
			var lp := c + dir * (ARM_R1 + 34.0) * scale
			var label := "%s %d/10" % [key, n]
			var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			overlay.draw_rect(Rect2(lp.x - w * 0.5 - 6, lp.y - 11, w + 12, 20),
				Color(0.03, 0.05, 0.08, 0.72), true)
			overlay.draw_string(f, Vector2(lp.x - w * 0.5, lp.y + 4), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	)
	wrap.add_child(overlay)
	return wrap


## 没有放射图时的退路：还是原来那几行圆点
func _build_meridians_fallback() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	for key in GameState.MERIDIAN_ORDER:
		var n: int = GameState.meridians.get(key, 0)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)

		var is_main: bool = (key == "产品脉")
		var name_l := Style.label(key + ("（主脉）" if is_main else ""), 14,
			Style.GOLD if is_main else Style.TEXT)
		name_l.custom_minimum_size = Vector2(110, 0)
		line.add_child(name_l)

		# 十窍
		for i in range(10):
			var d := Panel.new()
			d.custom_minimum_size = Vector2(15, 15)
			d.add_theme_stylebox_override("panel", Style.panel(
				(Style.GOLD if is_main else Style.JADE) if i < n else Style.INK_3,
				Style.LINE, 7))
			line.add_child(d)

		line.add_child(Style.label("%d/10" % n, 13, Style.TEXT_DIM))
	return box
