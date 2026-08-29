extends Control
##
## 任务列表
##
##   【去修炼】 → 把任务要求一键发给本命法器（法宝桥），ZCode 桌面端会开一个原生会话
##   【创建任务】→ 生成一条新的演示任务（路演用）
##   完成后任务出小红点，回来领灵石 + 经验
##
## 奖励 = 完成奖励 + 吐纳所得（消耗的灵气按 1000:1 折算成灵石）

var _list: VBoxContainer
var _world: Node


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_world = get_parent().get_parent()

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
	col.add_theme_constant_override("separation", 12)
	Style.apply_popup_safe_area(col)
	holder.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER      # 同一行里垂直居中对齐
	col.add_child(head)
	head.add_child(Style.title("任务列表", 24))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)

	var create := Style.make_button("＋ 创建任务", Style.GOLD, 130)
	create.custom_minimum_size = Vector2(130, 34)      # 跟 ✕ 等高才对得齐
	create.tooltip_text = "生成一条新的演示任务"
	create.pressed.connect(func() -> void:
		GameState.new_drill_task()
		_rebuild()
	)
	head.add_child(create)

	# 右上角留出 ✕ 的位置（✕ 是绝对定位的，这里空出等宽的位置免得挨着）
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(58, 0)
	head.add_child(pad)

	holder.add_child(Style.popup_close(queue_free))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 400)
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	GameState.tasks_changed.connect(_rebuild)
	Bridge.task_phase_changed.connect(func(_a: String, _b: String) -> void: _rebuild())
	_rebuild()


func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	for c in _list.get_children():
		c.queue_free()

	for t in GameState.tasks:
		_list.add_child(_make_row(t))
		# 主任务下面缩进挂它的 KR
		for st in t.get("subtasks", []):
			var wrap := MarginContainer.new()
			wrap.add_theme_constant_override("margin_left", 26)
			wrap.add_child(_make_row(st, true))
			_list.add_child(wrap)

	# ScrollContainer 的最后一项也要完整离开下边框山水纹样。
	var bottom_safe := Control.new()
	bottom_safe.custom_minimum_size = Vector2(0, 52)
	bottom_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(bottom_safe)


func _make_row(t: Dictionary, is_sub: bool = false) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.panel(
		Style.INK_2 if is_sub else Style.INK_3,
		Style.LINE, 8))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)

	var kind: String = {"main": "主线", "kr": "子任务", "drill": "演示"}.get(str(t["kind"]), "任务")
	var badge := Style.label("[%s]" % kind, 13,
		Style.GOLD if t["kind"] == "main" else Style.TEXT_DIM)
	top.add_child(badge)

	var title := Style.label(str(t["title"]), 15 if is_sub else 17, Style.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	# 状态
	var status_text: String = {
		"open": "未开始", "running": "法器运转中…",
		"done": "● 待领取", "claimed": "已完成",
	}.get(str(t["status"]), "")
	var status_color := _status_color(str(t["status"]))
	top.add_child(Style.label(status_text, 14, status_color))

	# 奖励行
	var reward := Style.label("完成奖励 %d 灵石 · %d 经验　｜　另计%s（消耗灵气 1000:1 折算）"
		% [t["reward_stones"], t.get("reward_exp", 0), GameState.TOKEN_BONUS_NAME],
		12, Style.TEXT_DIM)
	col.add_child(reward)

	# 按钮行
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)

	if t["kind"] == "main" and t.get("subtasks", []).size() > 0:
		var done := 0
		for st in t["subtasks"]:
			if st["status"] == "claimed":
				done += 1
		col.add_child(Style.label(
			"子任务 %d/%d 已完成　·　可以整条派发，也可以按子任务分别派发"
				% [done, t["subtasks"].size()], 12, Style.TEXT_DIM))

	var detail := Style.make_button("查看任务详情", Style.TEXT_DIM, 130)
	detail.pressed.connect(func() -> void: _show_detail(t))
	btns.add_child(detail)

	# 有些环节法器代劳不了 —— 注册、备案、提审、开流量主都得人自己
	# 去微信后台点。这类关卡除了「去修炼」（法器备料）之外，
	# 再给一个直接跳浏览器的入口。
	for link in t.get("links", []):
		var url := str(link.get("url", ""))
		if url == "":
			continue
		var lb := Style.make_button("↗ " + str(link.get("label", "打开外链")), Style.GOLD, 0)
		lb.custom_minimum_size = Vector2(0, 40)
		lb.tooltip_text = url
		lb.pressed.connect(func() -> void:
			OS.shell_open(url)
			_world.toast("已在浏览器打开：%s" % link.get("label", url), Style.GOLD)
		)
		btns.add_child(lb)

	match str(t["status"]):
		"open":
			# 没连桥时不要把按钮灰掉 —— 那样玩家不知道该干嘛。
			# 让它可点，点了给绑定引导。
			var go := Style.make_button("去 修 炼", Style.JADE, 120)
			go.tooltip_text = "把任务一键发给本命法器" if Bridge.connected \
				else "本命法器尚未连通，点一下查看连接步骤"
			go.pressed.connect(func() -> void:
				if not Bridge.connected:
					_world.open_panel(preload("res://ui/BridgeGuide.gd").new())
					return
				Bridge.dispatch(t)
				_world.toast("任务令已发往本命法器 —— 切到 ZCode 窗口看它开工", Style.JADE)
			)
			btns.add_child(go)
		"running":
			var elapsed := int(Time.get_unix_time_from_system() - float(t.get("started_at", 0)))
			var msg := "法器已在 ZCode 开了会话，去那边看它干活"
			if t.get("started_at", 0) != 0:
				msg += "（已跑 %d 分 %d 秒）" % [elapsed / 60, elapsed % 60]
			btns.add_child(Style.label(msg, 13, Style.JADE))

			# 主线那种大任务能跑很久，没有退路的话界面就等于卡死了
			# 说明：ZCode 没有提供可靠的「中断已开始的会话」接口，
			# 盲杀子进程会误伤别的会话。所以这个按钮只解除游戏侧的关联，
			# 名字也如实写成「解除关联」，不叫「取消」骗人。
			var cancel := Style.make_button("解除关联", Style.DANGER, 100)
			cancel.tooltip_text = "把游戏里的任务放回「未开始」，好重新派发。\n法器那边的会话不会停 —— 要停请去 ZCode 里停。"
			cancel.pressed.connect(func() -> void:
				Bridge.cancel(t)
				_world.toast("已解除关联，可重新派发。法器那边的会话仍在跑，要停请去 ZCode", Style.DANGER)
			)
			btns.add_child(cancel)
		"done":
			var claim := Style.make_button("领取奖励", Style.GOLD, 120)
			claim.pressed.connect(func() -> void: _claim(t))
			btns.add_child(claim)

	return card


func _status_color(status: String) -> Color:
	return {
		"open": Style.TEXT_DIM, "running": Style.JADE,
		"done": Style.DANGER, "claimed": Style.JADE,
	}.get(status, Style.TEXT_DIM)


func _claim(t: Dictionary) -> void:
	var r := GameState.claim_task(str(t["id"]))
	Audio.sfx("levelup")
	if r.is_empty():
		return
	_world.toast("领取：%d 灵石（完成 %d ＋%s %d）" % [
		r["total"], r["base"], GameState.TOKEN_BONUS_NAME, r["bonus"]], Style.GOLD)
	_rebuild()


func _show_detail(t: Dictionary) -> void:
	var dlg := Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dlg)

	var s := Style.scrim()
	s.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			dlg.queue_free()
	)
	dlg.add_child(s)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.frame())
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	dlg.add_child(card)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(720, 450)
	card.add_child(holder)
	var fr := Style.frame_overlay()
	if fr != null:
		holder.add_child(fr)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	Style.apply_popup_safe_area(col)
	holder.add_child(col)

	col.add_child(Style.title(str(t["title"]), 20))

	var body := Style.label(str(t.get("desc", "")), 15, Style.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	if str(t.get("automation_id", "")) != "":
		col.add_child(Style.label("法器会话：%s" % t["automation_id"], 12, Style.TEXT_DIM))

	holder.add_child(Style.popup_close(dlg.queue_free))
