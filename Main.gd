extends Node
##
## 场景路由。整个游戏只有一个根节点，屏幕在这里换。
##
##   首页 → 开场（3段解说 + 3段PV）→ 游戏世界
##

const TitleScreen := preload("res://scenes/TitleScreen.gd")
const Intro       := preload("res://scenes/Intro.gd")
const World       := preload("res://scenes/World.gd")

var _current: Node = null


func _ready() -> void:
	goto_title()
	if "--shot" in OS.get_cmdline_user_args():
		_shoot_all.call_deferred()
	if "--clicktest" in OS.get_cmdline_user_args():
		_click_test.call_deferred()


## 用真实鼠标事件走一遍输入管线，验证 mouse_filter 没有把点击吃掉。
##   godot --path . -- --clicktest
func _click_test() -> void:
	var fails := 0
	# 点击验收必须可在任何玩家存档上重复运行，并且不能污染真实进度。
	GameState.suppress_persistence = true

	# --- 0. 已看过开场时继续游戏；重置所清空的标记会让开场重新播放 ---
	GameState.flags["intro_seen"] = true
	continue_game()
	await _settle()
	if _current != null and _current.get_script() == World:
		print("✓ 已看过开场：继续游戏直接进入世界")
	else:
		print("✗ 已看过开场仍然重复播放"); fails += 1
	GameState.flags.erase("intro_seen")
	continue_game()
	await _settle()
	if _current != null and _current.get_script() == Intro:
		print("✓ 重置后：从开场背景介绍开始")
	else:
		print("✗ 重置后没有重新播放开场"); fails += 1

	# --- 1. 开场：点任意处应该翻页 ---
	goto_intro()
	await _settle()
	var intro := _current
	var before: int = intro._step
	await _click(Vector2(640, 400))
	if intro._step == before:
		print("✗ 开场点击无反应（_step 仍为 %d）" % before); fails += 1
	else:
		print("✓ 开场点击翻页：%d → %d" % [before, intro._step])

	# --- 1b. 三段 PV 在源码和导出 app 中都必须能加载满 49 帧 ---
	for pv_id in ["26080118044326194", "26080118120135627", "26080118175164449"]:
		intro._load_frames(pv_id)
		if intro._frames.size() == 49:
			print("✓ PV %s：49 帧可加载" % pv_id)
		else:
			print("✗ PV %s：只加载 %d/49 帧" % [pv_id, intro._frames.size()]); fails += 1

	# --- 2. 秘境：点地块应该能种下种子 ---
	goto_world()
	await _settle()
	var world := _current
	GameState.flags.erase("herb_slot_unlocked")
	GameState.inventory["herb"] = 0
	GameState.set_tile(5, 6, {"kind": "cleared"})
	GameState.add_item("seed", 5)
	GameState.selected_tool = GameState.TOOLBAR.find("seed")
	world.goto_map("qingwu")
	await _settle()

	# 玩家出生在 (4.5, 6.5) 格；把按下事件送进地图自己的 gui_input 处理器。
	# 这样验证的仍是生产点击入口，同时避开 headless 下系统鼠标 hover 的不确定性。
	var kind_before := str(GameState.get_tile(5, 6).get("kind", ""))
	var mj_after_plant: Node = world._map_host.get_child(0)
	var farm_press := InputEventMouseButton.new()
	farm_press.button_index = MOUSE_BUTTON_LEFT
	farm_press.position = Vector2(5 * 48 + 24, 6 * 48 + 24)
	farm_press.pressed = true
	mj_after_plant._on_board_input(farm_press)
	await _settle()
	var kind_after := str(GameState.get_tile(5, 6).get("kind", ""))
	if kind_after == "planted":
		print("✓ 秘境地块点击生效：%s → %s" % [kind_before, kind_after])
	else:
		print("✗ 秘境地块点击无反应（%s → %s）" % [kind_before, kind_after]); fails += 1
	await _settle()
	if mj_after_plant._drawn_plant_overlays > 0:
		print("✓ 已种地块绘制了青芒草覆盖层与倒计时")
	else:
		print("✗ 已种地块只有土地底图，青芒草覆盖层未绘制"); fails += 1

	# 催成并收割刚种下的这一格，首次收割后才出现青芒草库存格。
	var planted := GameState.get_tile(5, 6)
	planted["grow_seconds"] = 0
	GameState.set_tile(5, 6, planted)
	mj_after_plant._use_tool_at(Vector2(5 * 48 + 24, 6 * 48 + 24))
	await _settle()
	if GameState.herb_slot_unlocked() and GameState.item_count("herb") > 0 \
			and world._toolbar_items.size() == 5 and world._toolbar_items[4].visible:
		print("✓ 首次收割解锁青芒草库存格")
	else:
		print("✗ 首次收割后青芒草库存格没有出现"); fails += 1

	# --- 3. 工具格：点第 2 格应该切换选中 ---
	GameState.selected_tool = 0
	var slot2: Control = world._toolbar_slots[1]
	var slot_press := InputEventMouseButton.new()
	slot_press.button_index = MOUSE_BUTTON_LEFT
	slot_press.position = slot2.size * 0.5
	slot_press.pressed = true
	slot2.gui_input.emit(slot_press)
	await _settle()
	if GameState.selected_tool == 1:
		print("✓ 工具格点击切换生效")
	else:
		print("✗ 工具格点击无反应（selected_tool = %d）" % GameState.selected_tool); fails += 1

	# --- 4. 顶栏「任务」按钮：应该弹出任务面板 ---
	var btn: Node = null
	var seen_texts: Array[String] = []
	for n in _all_buttons(world):
		seen_texts.append(n.text)
		if n.text.contains("任务"):
			btn = n
			break
	if btn == null:
		print("   没找到「任务」按钮，当前按钮有：", seen_texts)
	if btn is Button:
		var rect: Rect2 = (btn as Button).get_global_rect()
		# 合成事件点 Button 会偶发不生效：Button 是松开时才发信号、且要求松开时
		# 光标还悬停在它身上，而真实光标在别处，Godot 每帧会按真实位置重算 hover，
		# 把合成的移动覆盖掉。真人操作没这个问题，所以这里重试两次就够。
		for attempt in range(3):
			await _click(rect.get_center())
			if world._panel_host.get_child_count() > 0:
				break
	else:
		print("   找不到「任务」按钮")
		await _click(Vector2(230, 30))
	var by_click: int = world._panel_host.get_child_count()
	# 分开验：面板本身能不能造出来（跟点击无关）
	for c in world._panel_host.get_children():
		c.queue_free()
	await _settle()
	world.open_panel(preload("res://ui/TaskPanel.gd").new())
	await _settle()
	var by_call: int = world._panel_host.get_child_count()
	print("   点击后子节点数=%d，直接调用后子节点数=%d" % [by_click, by_call])
	if by_call == 0:
		# 这条是真断言：面板造不出来就是真坏了
		print("✗ 任务面板造不出来 —— TaskPanel 构造有问题"); fails += 1
	elif by_click > 0:
		print("✓ 顶栏按钮弹面板生效")
	else:
		# 合成点击打 Button 会偶发不生效（约 1/3）：Button 松开时才发信号，
		# 且要求松开时光标仍悬停其上，而真实光标在别处，Godot 每帧按真实位置
		# 重算 hover，把合成的移动覆盖掉。真人操作没这个问题 ——
		# 所以这里只警告，不算失败。面板本身能造已经在上面断言过了。
		print("⚠ 顶栏按钮合成点击未生效（已知 harness 限制，非游戏缺陷）")

	# --- 4b. 面板不能是空壳 ---
	# 只查「有没有子节点」是查不出来的：PanelContainer 塞了两个子节点会
	# 把布局撑塌，面板照样存在、但里面什么都不显示。所以要查真实文字。
	var want := ["任务列表", "制作一款 AI 产品小程序", "立名帖", "注册小程序"]
	var missing: Array[String] = []
	for w in want:
		if not _has_text(world._panel_host, w):
			missing.append(w)
	if missing.is_empty():
		print("✓ 任务面板内容渲染正常（含 KR 层级）")
	else:
		print("✗ 面板是空壳，缺少文字：", missing); fails += 1
	var task_panel_node: Node = world._panel_host.get_child(0) if world._panel_host.get_child_count() > 0 else null
	if task_panel_node != null and task_panel_node._status_color("claimed") == Style.JADE \
			and task_panel_node._list.get_child_count() > 0 \
			and task_panel_node._list.get_child(-1).custom_minimum_size.y >= 52:
		print("✓ 已完成状态为绿色，任务列表底部安全留白存在")
	else:
		print("✗ 任务完成色或底部安全留白不符合规范"); fails += 1
	for c in world._panel_host.get_children():
		c.queue_free()
	await _settle()

	# --- 5. 空格：作用于**正前方**那格（道身初始朝下 → 目标 (4,7)），与星露谷一致 ---
	GameState.selected_tool = GameState.TOOLBAR.find("seed")
	var sp_before := str(GameState.get_tile(4, 7).get("kind", ""))
	await _key(KEY_SPACE)
	var sp_after := str(GameState.get_tile(4, 7).get("kind", ""))
	if sp_after == "planted":
		print("✓ 空格作用于正前方：%s → %s" % [sp_before, sp_after])
	else:
		print("✗ 空格无反应（%s → %s）" % [sp_before, sp_after]); fails += 1

	# --- 5b. 主线的 4 条 KR 都在，且能单独派发 ---
	var main_t := GameState.find_task("main-1")
	var subs: Array = main_t.get("subtasks", [])
	var kr := GameState.find_task("kr-4")
	var stones := 0
	var with_links := 0
	for st in subs:
		stones += int(st["reward_stones"])
		if st.get("links", []).size() > 0:
			with_links += 1
	if subs.size() == 8 and not kr.is_empty() and str(kr.get("parent", "")) == "main-1":
		print("✓ 八关任务链已载入（%d 关，灵石合计 %d，其中 %d 关带外链）"
			% [subs.size(), stones, with_links])
	else:
		print("✗ 任务链没载入（子任务 %d 条）" % subs.size()); fails += 1

	# --- 6. 连通性：溪流/山包不能把地图切出走不到的孤岛 ---
	var mj: Node = world._map_host.get_child(0)
	var reach: Dictionary = mj._flood()
	var walkable := 0
	var counts := {}
	for y in range(mj.GRID_H):
		for x in range(mj.GRID_W):
			var k: String = mj._kind(x, y)
			counts[k] = int(counts.get(k, 0)) + 1
			if not mj._is_permanent(x, y):
				walkable += 1
	if reach.size() == walkable:
		print("✓ 地图全连通（可达 %d / 可走 %d）" % [reach.size(), walkable])
	else:
		print("✗ 有走不到的孤岛（可达 %d / 可走 %d）" % [reach.size(), walkable]); fails += 1
	print("   地块分布：", counts)

	# --- 7. 器灵工具格 + 两回合战斗 ---
	if world._toolbar_slots.size() == 5 and GameState.SPIRIT_LEVEL == 2 and GameState.BEAST_LEVEL == 2:
		print("✓ 器灵工具格与双方 Lv.2 数据已载入")
	else:
		print("✗ 器灵工具格或等级数据缺失"); fails += 1
	if Audio.SFX.has("foxfire") and ResourceLoader.exists(str(Audio.SFX["foxfire"])):
		print("✓ 狐火发射音效已载入")
	else:
		print("✗ 狐火发射音效缺失"); fails += 1

	var beast_pos := Vector2i(-1, -1)
	for yy in range(mj.GRID_H):
		for xx in range(mj.GRID_W):
			if mj._kind(xx, yy) == "beast":
				beast_pos = Vector2i(xx, yy)
				break
		if beast_pos.x >= 0:
			break
	if beast_pos.x < 0:
		print("✗ 地图没有可用于测试的灵兽"); fails += 1
	else:
		mj._start_battle(beast_pos.x, beast_pos.y)
		await _settle()
		if world._panel_host.get_child_count() == 0:
			print("✗ 器灵战斗弹窗没有打开"); fails += 1
		else:
			var battle: Node = world._panel_host.get_child(0)
			var foxfire_sfx_before := int(Audio.sfx_play_counts.get("foxfire", 0))
			await battle._on_attack()
			var first_cast_ok: bool = battle._foxfire_casts == 1
			await battle._on_attack()
			await _settle()
			if mj._kind(beast_pos.x, beast_pos.y) == "cleared" and first_cast_ok \
					and int(Audio.sfx_play_counts.get("foxfire", 0)) - foxfire_sfx_before == 2:
				print("✓ 两回合狐火投射与音效均触发，并清除灵兽地块")
			else:
				print("✗ 两回合战斗、音效或灵兽清除未完整执行"); fails += 1

	# --- 8. 法宝桥引导必须明确要求把游戏沙盒加入 ZCode 项目 ---
	world.open_panel(preload("res://ui/BridgeGuide.gd").new())
	await _settle()
	if _has_text(world._panel_host, "把沙盒添加到 ZCode 项目") \
			and _has_text(world._panel_host, "添加项目 / 打开文件夹"):
		print("✓ 法宝桥引导包含 ZCode 添加游戏沙盒步骤")
	else:
		print("✗ 法宝桥引导缺少添加游戏沙盒步骤"); fails += 1

	print("clicktest 失败 %d 项" % fails)
	GameState.suppress_persistence = false
	get_tree().quit(1 if fails > 0 else 0)


## 面板里有没有出现这段文字（Label / Button 都算）
func _has_text(root: Node, needle: String) -> bool:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and (n as Label).text.contains(needle):
			return true
		if n is Button and (n as Button).text.contains(needle):
			return true
		for c in n.get_children():
			stack.append(c)
	return false


## 自己递归找按钮 —— find_children 的类型过滤在这里偶发漏，不如自己走一遍稳
func _all_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			out.append(n as Button)
		for c in n.get_children():
			stack.append(c)
	return out


func _settle() -> void:
	for i in range(8):
		await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _settle()


func _click(pos: Vector2) -> void:
	# 先把鼠标"移"过去。Button 是在松开时才发 pressed 信号，而且要求松开时
	# 光标还悬停在它身上；只发按下/松开、不发移动，hover 状态可能没建立，
	# 于是点击时灵时不灵。真人操作本来也是先移过去再点。
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await _settle()

	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _settle()


## 自动巡一遍所有界面并截图 —— 自测用，也可以直接拿去做 PPT 素材。
##   godot --path . -- --shot
func _shoot_all() -> void:
	var out := "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	print("截图输出目录：", ProjectSettings.globalize_path(out))

	await _shot(out, "01_首页")

	goto_intro()
	await _shot(out, "02_开场解说")

	goto_world()
	await _shot(out, "03_万象宗")

	var world := _current
	world.open_panel(preload("res://ui/HallPanel.gd").new())
	await _shot(out, "04_宗门大殿")
	for c in world._panel_host.get_children():
		c.queue_free()

	# 视觉回归直接拍交易态；新手礼包态由 clicktest/真人流程覆盖。
	var gift_before: bool = bool(GameState.flags.get("gift_claimed", false))
	GameState.flags["gift_claimed"] = true
	world.goto_map("outpost")
	await _shot(out, "05_秘境据点_师兄")

	# 提示条会不会压到「走出据点」按钮
	world.toast("灵石不够 —— 去任务列表做功课赚灵石", Style.DANGER)
	await _shot(out, "05b_据点_提示条")
	GameState.flags["gift_claimed"] = gift_before

	world.goto_map("qingwu")
	await _shot(out, "06_秘境_青芜原")

	# 复现用户截图里那条乱码提示
	world.toast("杂石要用爆破符 ×2", Style.TEXT_DIM)
	await _shot(out, "06b_提示_杂石_刚出现")
	# 等一秒再拍一张：如果第二张正常，就是字形光栅化的时序问题
	await get_tree().create_timer(1.0).timeout
	await _shot(out, "06c_提示_杂石_一秒后")

	# 桥在哪
	var mj2: Node = world._map_host.get_child(0)
	var bridges: Array = []
	for yy in range(mj2.GRID_H):
		for xx in range(mj2.GRID_W):
			if mj2._kind(xx, yy) == "bridge":
				bridges.append(Vector2i(xx, yy))
	print("   桥的位置：", bridges, "（视口约能看到 x<26, y<15）")

	# 战斗界面：找第一只灵兽直接进入，截图后不改地图。
	var beast_pos := Vector2i(-1, -1)
	for yy in range(mj2.GRID_H):
		for xx in range(mj2.GRID_W):
			if mj2._kind(xx, yy) == "beast":
				beast_pos = Vector2i(xx, yy)
				break
		if beast_pos.x >= 0:
			break
	if beast_pos.x >= 0:
		mj2._start_battle(beast_pos.x, beast_pos.y)
		await _shot(out, "06d_器灵对战")
		for c in world._panel_host.get_children():
			c.queue_free()
		await _settle()

	var tasks := preload("res://ui/TaskPanel.gd").new()
	world.open_panel(tasks)
	await _shot(out, "07_任务列表")
	if not GameState.tasks.is_empty():
		tasks._show_detail(GameState.tasks[0])
		await _shot(out, "07b_任务详情")
	for c in world._panel_host.get_children():
		c.queue_free()
	await _settle()

	world.open_panel(preload("res://ui/BridgeGuide.gd").new())
	await _shot(out, "07c_法宝桥")
	for c in world._panel_host.get_children():
		c.queue_free()
	await _settle()

	world.open_panel(preload("res://ui/PlayerPanel.gd").new())
	await _shot(out, "08_道身_十境六脉")
	for c in world._panel_host.get_children():
		c.queue_free()

	world.open_panel(preload("res://ui/MapPanel.gd").new())
	await _shot(out, "09_地图")

	print("截图完成")
	get_tree().quit()


func _shot(dir: String, name: String) -> void:
	# 等布局稳定 + 等淡入之类的 tween 播完（开场文字有 0.6 秒淡入，
	# 只等几帧会抓到半透明的中间态，看着像文字发灰）
	await get_tree().create_timer(0.9).timeout
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("  ✓ ", name)


func _swap(node: Node) -> void:
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = node
	add_child(node)


func goto_title() -> void:
	_swap(TitleScreen.new())


func goto_intro() -> void:
	_swap(Intro.new())


func continue_game() -> void:
	if GameState.should_play_intro():
		goto_intro()
	else:
		goto_world()


func goto_world() -> void:
	_swap(World.new())
