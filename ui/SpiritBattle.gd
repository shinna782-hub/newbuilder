extends Control
##
## 器灵对战：为黑客松演示收敛成稳定的两回合流程。
## 双方固定 Lv.2，不做随机命中、失败分支或持久化血量。

var _target := Vector2i(-1, -1)
var _won: Callable
var _round := 0
var _fox_hp: ProgressBar
var _beast_hp: ProgressBar
var _story: Label
var _attack: Button
var _fox: TextureRect
var _beast: TextureRect
var _anim_t := 0.0
var _anim_frame := 0
var _foxfire_casts := 0
var _foxfire_sfx_casts := 0


func _init(target: Vector2i = Vector2i(-1, -1), won: Callable = Callable()) -> void:
	_target = target
	_won = won
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var scrim := Style.scrim()
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

	var frame := Style.frame_overlay()
	if frame != null:
		holder.add_child(frame)

	var arena := Control.new()
	Style.apply_popup_safe_area(arena)
	holder.add_child(arena)

	var title := Style.title("器灵试炼 · 青芜原", 22)
	title.position = Vector2(0, 0)
	title.size = Vector2(420, 34)
	arena.add_child(title)

	var enemy_info := _status_card("赤焰灵兽", GameState.BEAST_LEVEL, false)
	enemy_info.position = Vector2(0, 42)
	enemy_info.size = Vector2(320, 88)
	arena.add_child(enemy_info)
	_beast_hp = enemy_info.get_node("Box/HP") as ProgressBar

	_beast = TextureRect.new()
	var beast_path := "res://assets/ui/battle_beast_lingshou_v2.png"
	if not ResourceLoader.exists(beast_path):
		beast_path = "res://assets/sprites/beast_lingshou.png"
	_beast.texture = load(beast_path) if ResourceLoader.exists(beast_path) else null
	_beast.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_beast.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_beast.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_beast.position = Vector2(510, 48)
	_beast.size = Vector2(238, 178)
	_beast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(_beast)

	_fox = TextureRect.new()
	var fox_path := "res://assets/ui/battle_spirit_fox_v2.png"
	_fox.texture = load(fox_path) if ResourceLoader.exists(fox_path) else Style.spirit_frame(0)
	_fox.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fox.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fox.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fox.position = Vector2(20, 136)
	_fox.size = Vector2(300, 204)
	_fox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(_fox)

	var fox_info := _status_card(GameState.SPIRIT_NAME, GameState.SPIRIT_LEVEL, true)
	fox_info.position = Vector2(420, 230)
	fox_info.size = Vector2(330, 88)
	arena.add_child(fox_info)
	_fox_hp = fox_info.get_node("Box/HP") as ProgressBar

	var command := PanelContainer.new()
	command.position = Vector2(0, 330)
	command.size = Vector2(768, 102)
	command.add_theme_stylebox_override("panel",
		Style.panel(Color(0.055, 0.085, 0.11, 0.98), Style.GOLD.darkened(0.35), 10))
	arena.add_child(command)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	command.add_child(line)
	_story = Style.label("野生赤焰灵兽拦住去路。\n青璃九尾舒展，等待你的号令。", 15, Style.TEXT)
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_story)
	_attack = Style.make_button("狐 火", Style.JADE, 150)
	var fire_path := "res://assets/ui/icon_foxfire_v1.png"
	if ResourceLoader.exists(fire_path):
		_attack.icon = load(fire_path)
		_attack.expand_icon = true
		_attack.add_theme_constant_override("icon_max_width", 34)
	_attack.pressed.connect(_on_attack)
	line.add_child(_attack)

	set_process(true)


func _status_card(display_name: String, level: int, ally: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel(
		Color(0.04, 0.07, 0.09, 0.95), Style.JADE_DIM if ally else Style.DANGER.darkened(0.25), 8))
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(Style.label(display_name, 17, Style.JADE if ally else Style.GOLD))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(Style.label("Lv.%d" % level, 15, Style.TEXT))
	var hp := ProgressBar.new()
	hp.name = "HP"
	hp.max_value = 100
	hp.value = 100
	hp.show_percentage = true
	hp.custom_minimum_size = Vector2(0, 22)
	box.add_child(hp)
	return panel


func _on_attack() -> void:
	if _attack.disabled:
		return
	_round += 1
	_attack.disabled = true
	_story.text = "青璃凝聚九尾灵息，狐火破空而出——"
	await _cast_foxfire()
	if _round == 1:
		_beast_hp.value = 45
		_story.text = "青璃使出「狐火」！赤焰灵兽受到重创。"
		await get_tree().create_timer(0.32).timeout
		_fox_hp.value = 60
		_story.text = "赤焰灵兽反扑，青璃稳住身形。\n再使一次狐火结束战斗。"
		_attack.text = "狐 火 · 终式"
		_attack.disabled = false
	else:
		_beast_hp.value = 0
		_story.text = "狐火贯穿赤焰！\n青璃赢得器灵试炼，前路已经清开。"
		_attack.text = "胜 利"
		if _won.is_valid():
			_won.call()
		await get_tree().create_timer(0.75).timeout
		queue_free()


func _cast_foxfire() -> void:
	_foxfire_casts += 1
	if Audio.sfx("foxfire", 0.0):
		_foxfire_sfx_casts += 1
	var fx := TextureRect.new()
	fx.texture = load("res://assets/ui/icon_foxfire_v1.png") \
		if ResourceLoader.exists("res://assets/ui/icon_foxfire_v1.png") else null
	fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fx.position = _fox.position + Vector2(206, 74)
	fx.size = Vector2(68, 68)
	fx.scale = Vector2(0.45, 0.45)
	fx.pivot_offset = fx.size * 0.5
	fx.modulate.a = 0.25
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fox.get_parent().add_child(fx)

	var target := _beast.position + Vector2(34, 86)
	var fly := create_tween().set_parallel(true)
	fly.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	fly.tween_property(fx, "position", target, 0.46)
	fly.tween_property(fx, "scale", Vector2(1.15, 1.15), 0.30)
	fly.tween_property(fx, "modulate:a", 1.0, 0.18)
	fly.tween_property(fx, "rotation", 0.8, 0.46)
	await fly.finished

	fx.queue_free()
	var base_pos := _beast.position
	var hit := create_tween()
	hit.tween_property(_beast, "modulate", Color(1.8, 1.8, 1.8, 1), 0.07)
	hit.parallel().tween_property(_beast, "position", base_pos + Vector2(12, -3), 0.07)
	hit.tween_property(_beast, "modulate", Color.WHITE, 0.11)
	hit.parallel().tween_property(_beast, "position", base_pos, 0.11)
	await hit.finished


func _process(delta: float) -> void:
	if not is_instance_valid(_fox):
		return
	_anim_t += delta
	if _anim_t >= 0.22:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % 4
		# 只有低清兜底精灵才需要切四帧；高清战斗立绘保持清晰稳定。
		if not ResourceLoader.exists("res://assets/ui/battle_spirit_fox_v2.png"):
			_fox.texture = Style.spirit_frame(_anim_frame)
