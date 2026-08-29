extends Control
##
## 法宝桥未连接时的引导。
##
## 之前只在顶栏显示一个「○」，玩家不知道该干什么。这里把「怎么绑定本命法器」
## 一步步说清楚，并给一个「重新检测」按钮。

var _path_label: Label
var _status: Label


func _steps() -> Array:
	var ws := Bridge.workspace_path if Bridge.workspace_path != "" else "（启动法宝桥后显示实际路径）"
	return [
		["① 安装并登录 ZCode", "在这台电脑上安装 ZCode 桌面端，并登录自己的账号。"],
		["② 启动法宝桥", "双击演示包里的「启动.command」，保持弹出的终端窗口不要关闭。"],
		["③ 找到游戏沙盒", "当前桥实际使用的本地目录：\n%s" % ws],
		["④ 把沙盒添加到 ZCode 项目", "在 ZCode 里选择「添加项目 / 打开文件夹」，选中上面的游戏沙盒。\n这一步不能省略，否则任务会运行，但会话不会出现在 ZCode 界面。"],
		["⑤ 回到游戏重新检测", "确认 ZCode 项目列表中已经出现并选中游戏沙盒，再点下面的「重新检测」。"],
	]


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

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(1024, 640)
	card.add_child(holder)

	var fr := Style.frame_overlay()
	if fr != null:
		holder.add_child(fr)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	Style.apply_popup_safe_area(col)
	holder.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(head)
	head.add_child(Style.title("本命法器尚在休眠", 24))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_pad := Control.new()
	close_pad.custom_minimum_size = Vector2(54, 0)
	head.add_child(close_pad)
	holder.add_child(Style.popup_close(queue_free))

	var lead := Style.label(
		"「去修炼」要把任务发给本命法器执行。当前尚未连通，按下面五步完成连接：",
		14, Style.TEXT)
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(lead)

	for st in _steps():
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", Style.panel(Style.INK_3, Style.JADE_DIM, 8))
		col.add_child(row)
		var rc := VBoxContainer.new()
		rc.add_theme_constant_override("separation", 2)
		row.add_child(rc)
		rc.add_child(Style.label(str(st[0]), 14, Style.JADE))
		var d := Style.label(str(st[1]), 11, Style.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rc.add_child(d)
		if str(st[0]).begins_with("③"):
			_path_label = d

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btns)

	var recheck := Style.make_button("重新检测", Style.JADE, 140)
	recheck.pressed.connect(func() -> void:
		_status.text = "正在检测法宝桥…"
		_status.add_theme_color_override("font_color", Style.TEXT_DIM)
		Bridge.check_health()
	)
	btns.add_child(recheck)

	var reveal := Style.make_button("在访达中显示沙盒", Style.GOLD, 174)
	reveal.pressed.connect(func() -> void:
		if Bridge.workspace_path != "":
			OS.shell_show_in_file_manager(Bridge.workspace_path, true)
	)
	btns.add_child(reveal)

	_status = Style.label("", 13, Style.TEXT_DIM)
	btns.add_child(_status)
	var paint := func(ok: bool) -> void:
		if not is_instance_valid(_status):
			return
		_status.text = "桥已连接 ✓ · 请确认 ZCode 已添加沙盒项目" if ok else "仍未连接"
		_status.add_theme_color_override("font_color", Style.JADE if ok else Style.DANGER)
		if is_instance_valid(_path_label) and Bridge.workspace_path != "":
			_path_label.text = "当前桥实际使用的本地目录：\n%s" % Bridge.workspace_path
	paint.call(Bridge.connected)
	Bridge.bridge_ok.connect(paint)
	Bridge.bridge_info_changed.connect(func() -> void: paint.call(Bridge.connected))
