extends Control
##
## 秘境 · 青芜原 —— 核心玩法
##
##   键盘 WASD / 方向键控制道身移动
##   工具格选中某个工具后，鼠标左键点身边的地块使用它
##
## 地块分两类：
##
##   【可清理】
##     野草 → 徒手拔掉，不耗东西（教玩家点第一下）
##     荒地 → 爆破符 ×1
##     杂石 → 爆破符 ×2，挡路
##     古木 → 爆破符 ×2，挡路
##     灵兽 → 召唤 Lv.2 器灵进入两回合战斗
##
##   【永久障碍 · 清不掉，只能绕】
##     小山包 → 成片隆起
##     溪流   → 成条流过
##
##   空地 → 种子 ×1 种下青芒草，1 小时成熟
##   已种 → 灵液 ×1 立刻催熟；成熟后左键收割
##
## 成熟倒计时会被 Agent 工作时长抵扣：做半小时功课回来，灵草就多长了半小时。
##
## 【美术】地块贴图、道身行走图、灵草四阶段、灵兽、山包、溪流、爆破符特效

const TILE := 48
const GRID_W := 28
const GRID_H := 17
const REACH := 1.9          # 能够到的格数
const SPEED := 190.0
const GROW_SECONDS := 3600  # 一株青芒草 1 小时
const SpiritBattle := preload("res://ui/SpiritBattle.gd")

# 出生点所在格（据点门口那片空地）
const SPAWN := Vector2i(4, 6)

const BLOCKING := ["tree", "beast", "rock", "hill", "stream"]   # 挡路（桥不在内，可以走）
const PERMANENT := ["hill", "stream"]                            # 清不掉

# 四邻方向。必须显式标类型，否则数组字面量里取出来是 Variant，
# 后面 `var nx := x + d.x` 推不出类型会编译失败。
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _player_pos := Vector2(SPAWN.x * TILE + TILE * 0.5, SPAWN.y * TILE + TILE * 0.5)
var _facing := Vector2.DOWN
var _cam_offset := Vector2.ZERO
var _board: Control
var _hint: Label
var _world: Node

# 美术素材：有图就用图，没图退回代码画的占位形状。
# Codex 还没出的（野草/杂石/山包/溪流）目前仍是占位。
var _tex := {}
var _set_tex := {}    # 九宫格套图：hill / stream / bridge
var _door_tex: Texture2D = null    # 据点建筑（96×96，正好盖住 2×2 格的门口）
var _herb_tex: Array[Texture2D] = []
var _walk: Texture2D = null
var _fx := {}                      # 特效图集：blast / harvest
var _fx_playing: Array = []        # [{tex, pos, t}]
var _anim_t := 0.0
var _moving := false
var _battle_active := false
var _drawn_plant_overlays := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_world = get_parent().get_parent()
	if not GameState.mijing_entered:
		_generate()
		GameState.mijing_entered = true
		GameState.save_game()

	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	add_child(_board)

	# 操作提示：地图很花，不加底衬读不清
	var hint_box := PanelContainer.new()
	hint_box.add_theme_stylebox_override("panel",
		Style.panel(Color(0.04, 0.06, 0.09, 0.86), Style.LINE, 6))
	hint_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_box.offset_top = 72
	hint_box.offset_bottom = 106
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_box)

	_hint = Style.label("", 13, Style.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.add_child(_hint)
	_hint.text = "WASD 移动 · 数字键切工具 · 左键点地块 或 空格对正前方使用 · 据点门口按 E 进门"

	_load_art()
	Audio.ambience(true)          # 秘境里开户外环境音
	set_process(true)


## 载入 Codex 出的素材。缺哪张就让哪张继续用占位画法。
func _load_art() -> void:
	for kind in ["cleared", "wild", "planted", "tree", "grass", "rock"]:
		var path := "res://assets/sprites/tile_%s.png" % kind
		if ResourceLoader.exists(path):
			_tex[kind] = load(path)
	if ResourceLoader.exists("res://assets/sprites/beast_lingshou.png"):
		_tex["beast"] = load("res://assets/sprites/beast_lingshou.png")
	# 山包 / 溪流 / 木桥都是 3×3 九宫格套图（144×144），按邻居挑格子拼
	for k in ["hill", "stream", "bridge"]:
		var sp := "res://assets/sprites/tile_bridge_arch_set.png" if k == "bridge" \
			else "res://assets/sprites/tile_%s_set.png" % k
		if k == "bridge" and not ResourceLoader.exists(sp):
			sp = "res://assets/sprites/tile_bridge_set.png"
		if ResourceLoader.exists(sp):
			_set_tex[k] = load(sp)
	for i in range(1, 5):
		var hp := "res://assets/sprites/herb_qingmang_%d.png" % i
		if ResourceLoader.exists(hp):
			_herb_tex.append(load(hp))
	for k in ["blast", "harvest"]:
		var fp := "res://assets/sprites/fx_%s.png" % k
		if ResourceLoader.exists(fp):
			_fx[k] = load(fp)
	if ResourceLoader.exists("res://assets/sprites/player_walk.png"):
		_walk = load("res://assets/sprites/player_walk.png")
	if ResourceLoader.exists("res://assets/sprites/building_outpost.png"):
		_door_tex = load("res://assets/sprites/building_outpost.png")


# ---------------------------------------------------------------- 地图生成

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260830
	GameState.tiles.clear()

	# 1) 铺底：野草 / 荒地 / 杂石 / 古木 / 灵兽
	for y in range(GRID_H):
		for x in range(GRID_W):
			var r := rng.randf()
			var kind := "wild"
			if r < 0.20:    kind = "grass"
			elif r < 0.74:  kind = "wild"
			elif r < 0.85:  kind = "rock"
			elif r < 0.95:  kind = "tree"
			else:           kind = "beast"
			GameState.tiles[GameState.tile_key(x, y)] = {"kind": kind}

	# 2) 撒几片小山包（每片连成 4–9 格）
	for i in range(4):
		var cx := rng.randi_range(9, GRID_W - 4)
		var cy := rng.randi_range(1, GRID_H - 4)
		for dy in range(rng.randi_range(2, 3)):
			for dx in range(rng.randi_range(2, 3)):
				if rng.randf() < 0.85:
					_put(cx + dx, cy + dy, "hill")

	# 3) 一条自上而下蜿蜒的溪流。
	#    固定 2 格宽，且拐弯的那一行把新旧两列都填上 —— 否则河道会在斜move 处断开，
	#    九宫格就会在河中间挑出「端盖」那格，看着像河里长了块岸石。
	var sx := rng.randi_range(12, GRID_W - 8)
	for y in range(GRID_H):
		var prev := sx
		if y > 0:
			sx = clampi(sx + rng.randi_range(-1, 1), 9, GRID_W - 4)
		var lo: int = mini(prev, sx)
		var hi: int = maxi(prev, sx)
		for x in range(lo, hi + 2):          # +2 = 保证至少 2 格宽
			_put(x, y, "stream")

	# 4) 据点门口那片留成空地
	for y in range(2, 8):
		for x in range(0, 6):
			_put(x, y, "cleared")

	# 5) 在两个显眼的高度各架一座桥。
	#    早先只靠连通性算法兜底，它求的是最短路径，结果把桥架在第 0 行 ——
	#    正好被顶栏挡住，玩家根本看不见。
	for frac in [0.35, 0.72]:
		var by := int(GRID_H * frac)
		for x in range(GRID_W):
			if _kind(x, by) == "stream":
				_put(x, by, "bridge")

	# 6) 兜底：万一还有走不到的地方，再铺路
	_ensure_connected()
	GameState.save_game()


func _put(x: int, y: int, kind: String) -> void:
	if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H:
		return
	GameState.tiles[GameState.tile_key(x, y)] = {"kind": kind}


## 从出生点洪水填充；若有区域被永久障碍围死，就在墙上凿一个浅滩/山口。
## 不做这步，随机溪流很容易把半张图变成永远去不了的地方。
func _ensure_connected() -> void:
	for attempt in range(30):
		var seen := _flood()

		# 找一个「走不到、但本身能走」的格子
		var orphan := Vector2i(-1, -1)
		for y in range(GRID_H):
			for x in range(GRID_W):
				if not seen.has(GameState.tile_key(x, y)) and not _is_permanent(x, y):
					orphan = Vector2i(x, y)
					break
			if orphan.x >= 0:
				break
		if orphan.x < 0:
			return                                   # 全连通

		if not _carve_to(orphan, seen):
			return                                   # 实在铺不过去就算了，别死循环


## 从孤岛铺一条最短的路回到已连通区，沿途把永久障碍改成桥/山口。
##
## 早先的做法是「找一格同时挨着两岸的障碍」，那只能跨 1 格宽的东西 ——
## 溪流改成 2 格宽之后就再也找不到这种格子，于是一座桥都架不出来，
## 地图被劈成两半。改成铺路就跟宽度无关了。
func _carve_to(from: Vector2i, seen: Dictionary) -> bool:
	var prev := {}
	var visited := {GameState.tile_key(from.x, from.y): true}
	var q: Array[Vector2i] = [from]
	var hit := Vector2i(-1, -1)

	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		if seen.has(GameState.tile_key(p.x, p.y)):
			hit = p
			break
		for d in DIRS:
			var nx := p.x + d.x
			var ny := p.y + d.y
			if nx < 0 or ny < 0 or nx >= GRID_W or ny >= GRID_H:
				continue
			var k := GameState.tile_key(nx, ny)
			if visited.has(k):
				continue
			visited[k] = true
			prev[k] = p                              # 障碍也走，等下把沿途铺开
			q.append(Vector2i(nx, ny))

	if hit.x < 0:
		return false

	# 回溯，把路径上的永久障碍改掉：水上架桥，山上开口
	var cur := hit
	while true:
		if _is_permanent(cur.x, cur.y):
			_put(cur.x, cur.y, "bridge" if _kind(cur.x, cur.y) == "stream" else "cleared")
		var ck := GameState.tile_key(cur.x, cur.y)
		if not prev.has(ck):
			break
		cur = prev[ck]
	return true


func _flood() -> Dictionary:
	var seen := {}
	var stack: Array[Vector2i] = [SPAWN]
	seen[GameState.tile_key(SPAWN.x, SPAWN.y)] = true
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in DIRS:
			var nx := p.x + d.x
			var ny := p.y + d.y
			if nx < 0 or ny < 0 or nx >= GRID_W or ny >= GRID_H:
				continue
			var k := GameState.tile_key(nx, ny)
			if seen.has(k) or _is_permanent(nx, ny):
				continue
			seen[k] = true
			stack.append(Vector2i(nx, ny))
	return seen


func _is_permanent(x: int, y: int) -> bool:
	return _kind(x, y) in PERMANENT


func _kind(x: int, y: int) -> String:
	return str(GameState.get_tile(x, y).get("kind", "cleared"))


# ---------------------------------------------------------------- 循环

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if not _battle_active:
		dir = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down")
		)
	_moving = dir.length() > 0.1
	if _moving:
		_anim_t += delta
		Audio.step_on("wood" if _kind_at(_player_pos) == "bridge" else "grass")
		dir = dir.normalized()
		_facing = dir
		var next := _player_pos + dir * SPEED * delta
		if _kind_at(next) == "beast":
			_start_battle(int(next.x / TILE), int(next.y / TILE))
		elif not _blocked(next):
			_player_pos = next
		elif not _blocked(Vector2(next.x, _player_pos.y)):
			_player_pos.x = next.x
		elif not _blocked(Vector2(_player_pos.x, next.y)):
			_player_pos.y = next.y

	_player_pos.x = clamp(_player_pos.x, TILE * 0.4, GRID_W * TILE - TILE * 0.4)
	_player_pos.y = clamp(_player_pos.y, TILE * 0.4, GRID_H * TILE - TILE * 0.4)

	var vp := size
	_cam_offset = vp * 0.5 - _player_pos
	_cam_offset.x = clamp(_cam_offset.x, min(0.0, vp.x - GRID_W * TILE), 0.0)
	_cam_offset.y = clamp(_cam_offset.y, min(0.0, vp.y - GRID_H * TILE), 0.0)

	# 推进特效，播完就丢
	for i in range(_fx_playing.size() - 1, -1, -1):
		_fx_playing[i]["t"] += delta
		if _fx_playing[i]["t"] > 0.42:          # 6 帧 @ ~14fps
			_fx_playing.remove_at(i)

	_board.queue_redraw()


func _exit_tree() -> void:
	Audio.ambience(false)


## 在某格放一个 6 帧特效
func _play_fx(kind: String, gx: int, gy: int) -> void:
	if not _fx.has(kind):
		return
	_fx_playing.append({"tex": _fx[kind],
		"pos": Vector2(gx * TILE, gy * TILE), "t": 0.0})


## 是否站在宗门据点门口
func _near_door() -> bool:
	return _player_pos.x < TILE * 3.6 and _player_pos.y > TILE * 2.4 and _player_pos.y < TILE * 5.6


func _blocked(p: Vector2) -> bool:
	return str(_tile_at(p).get("kind", "cleared")) in BLOCKING


func _kind_at(p: Vector2) -> String:
	return str(_tile_at(p).get("kind", "cleared"))


func _tile_at(p: Vector2) -> Dictionary:
	return GameState.get_tile(int(p.x / TILE), int(p.y / TILE))


## 地块点击。挂在 _board 上，不走 _unhandled_input ——
## 上层任何一个 STOP 的控件都会截断那条链，太脆。
func _on_board_input(event: InputEvent) -> void:
	if _battle_active:
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_use_tool_at((event as InputEventMouseButton).position - _cam_offset)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _battle_active:
		return
	if event.is_action_pressed("interact") and _near_door():
		_world.goto_map("outpost")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_tool"):
		# 空格 = 对**正前方**那一格用当前工具。跟《星露谷物语》一致。
		_use_tool_at(_facing_tile_pos())
		get_viewport().set_input_as_handled()


## 正前方那一格的中心。朝向吸附到四方向，斜着走时也不会指到奇怪的格子。
func _facing_tile_pos() -> Vector2:
	var d := Vector2.DOWN
	if absf(_facing.x) > absf(_facing.y):
		d = Vector2(signf(_facing.x), 0.0)
	elif absf(_facing.y) > 0.0:
		d = Vector2(0.0, signf(_facing.y))
	return _player_pos + d * TILE


# ---------------------------------------------------------------- 用工具

func _use_tool_at(world_pos: Vector2) -> void:
	var gx := int(world_pos.x / TILE)
	var gy := int(world_pos.y / TILE)
	if gx < 0 or gy < 0 or gx >= GRID_W or gy >= GRID_H:
		return

	var center := Vector2(gx * TILE + TILE * 0.5, gy * TILE + TILE * 0.5)
	if _player_pos.distance_to(center) > REACH * TILE:
		_world.toast("够不着，走近一点", Style.TEXT_DIM)
		return

	var t := GameState.get_tile(gx, gy)
	var kind := str(t.get("kind", "cleared"))
	var tool := GameState.current_tool()

	match kind:
		"hill":
			_world.toast("山石嶙峋，开凿不动 —— 绕过去", Style.TEXT_DIM)

		"stream":
			_world.toast("溪水湍急，趟不过 —— 沿岸找桥", Style.TEXT_DIM)

		"bridge":
			_world.toast("木桥上没法开垦，过去再说", Style.TEXT_DIM)

		"grass":
			GameState.set_tile(gx, gy, {"kind": "cleared"})   # 徒手拔草，不耗东西
			Audio.sfx("grass")
			_world.toast("拔掉一丛野草")

		"wild":
			if tool != "bomb":
				_world.toast("荒地要用爆破符清理", Style.TEXT_DIM); return
			if not GameState.use_item("bomb", 1):
				_world.toast("爆破符不够了 —— 去做功课赚灵石吧", Style.DANGER); return
			GameState.set_tile(gx, gy, {"kind": "cleared"})
			Audio.sfx("blast"); _play_fx("blast", gx, gy)
			_world.toast("符箓炸开，露出一片空地")

		"rock":
			if tool != "bomb":
				_world.toast("杂石要用爆破符 ×2", Style.TEXT_DIM); return
			if GameState.item_count("bomb") < 2:
				_world.toast("爆破符不足 2 张", Style.DANGER); return
			GameState.use_item("bomb", 2)
			GameState.set_tile(gx, gy, {"kind": "cleared"})
			Audio.sfx("blast"); _play_fx("blast", gx, gy)
			_world.toast("乱石崩碎")

		"tree":
			if tool != "bomb":
				_world.toast("砍树要用爆破符 ×2", Style.TEXT_DIM); return
			if GameState.item_count("bomb") < 2:
				_world.toast("爆破符不足 2 张", Style.DANGER); return
			GameState.use_item("bomb", 2)
			GameState.set_tile(gx, gy, {"kind": "cleared"})
			Audio.sfx("tree"); _play_fx("blast", gx, gy)
			_world.toast("古木倒下")

		"beast":
			if tool != "spirit":
				_world.toast("灵兽只能由器灵迎战 —— 选择第 4 格「器灵」", Style.GOLD); return
			_start_battle(gx, gy)

		"cleared":
			if tool != "seed":
				_world.toast("空地可以种下%s种子" % GameState.HERB_NAME, Style.TEXT_DIM); return
			if not GameState.use_item("seed", 1):
				_world.toast("没有种子了", Style.DANGER); return
			GameState.set_tile(gx, gy, {
				"kind": "planted",
				"planted_at": int(Time.get_unix_time_from_system()),
				"grow_seconds": GROW_SECONDS,
			})
			Audio.sfx("plant")
			_world.toast("种下一株%s" % GameState.HERB_NAME)

		"planted":
			if GameState.herb_ready(t):
				GameState.set_tile(gx, gy, {"kind": "cleared"})
				GameState.add_item("herb", 1)
				GameState.unlock_herb_slot()
				Audio.sfx("harvest"); _play_fx("harvest", gx, gy)
				_world.toast("收割了一株%s" % GameState.HERB_NAME, Style.JADE)
			elif tool == "elixir":
				if not GameState.use_item("elixir", 1):
					_world.toast("没有灵液", Style.DANGER); return
				t["grow_seconds"] = 0
				GameState.set_tile(gx, gy, t)
				Audio.sfx("water")
				_world.toast("灵液催发，立刻成熟", Style.JADE)
			else:
				var left := GameState.herb_remaining(t)
				_world.toast("还需 %s 成熟（做功课可抵扣）" % _fmt(left), Style.TEXT_DIM)


func _start_battle(gx: int, gy: int) -> void:
	if _battle_active or _kind(gx, gy) != "beast":
		return
	_battle_active = true
	var battle := SpiritBattle.new(Vector2i(gx, gy), _win_battle.bind(gx, gy))
	battle.tree_exited.connect(func() -> void: _battle_active = false)
	_world.open_panel(battle)


func _win_battle(gx: int, gy: int) -> void:
	GameState.set_tile(gx, gy, {"kind": "cleared"})
	Audio.sfx("levelup")
	_world.toast("器灵青璃击退 Lv.%d 灵兽" % GameState.BEAST_LEVEL, Style.GOLD)
	_board.queue_redraw()


## 地块上显示的短倒计时，只留两位
func _fmt_short(sec: float) -> String:
	var t := int(sec)
	if t >= 3600:
		return "%d:%02d" % [t / 3600, (t % 3600) / 60]
	return "%d:%02d" % [t / 60, t % 60]


func _fmt(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d 时 %d 分" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d 分 %d 秒" % [s / 60, s % 60]
	return "%d 秒" % s


# ---------------------------------------------------------------- 绘制

const BASE_COLOR := {
	"grass":   Color("364a37"),
	"wild":    Color("4a4433"),
	"cleared": Color("3a5240"),
	"planted": Color("46603f"),
	"rock":    Color("3c4048"),
	"tree":    Color("24331f"),
	"beast":   Color("4a2c2c"),
	"hill":    Color("544a3c"),
	"stream":  Color("1d3f5c"),
	"bridge":  Color("6b5334"),
}


## 从 3×3 套图里挑出该用哪一格。
## 行：上面不是同类 → 0，下面不是同类 → 2，否则 1（内部）
## 列：左边不是同类 → 0，右边不是同类 → 2，否则 1
func _slice_of(x: int, y: int, kind: String) -> Rect2:
	var row := 1
	if not _same(x, y - 1, kind):
		row = 0
	elif not _same(x, y + 1, kind):
		row = 2
	var col := 1
	if not _same(x - 1, y, kind):
		col = 0
	elif not _same(x + 1, y, kind):
		col = 2
	return Rect2(col * TILE, row * TILE, TILE, TILE)


## 桥在套图里取哪一列。桥是横着一行，两端要有桥头，中间才是平铺的桥面。
func _bridge_col(x: int, y: int) -> int:
	var left := _kind(x - 1, y) == "bridge"
	var right := _kind(x + 1, y) == "bridge"
	if left and right:
		return 1
	if right:
		return 0
	if left:
		return 2
	return 1


## 邻格是不是同一种 —— 山包和溪流靠它画成连成一片，而不是一格一格的方块
func _same(x: int, y: int, kind: String) -> bool:
	if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H:
		return false                       # 地图外一律算「不同类」，边缘照样画岸/坡
	var k := _kind(x, y)
	if kind == "stream" and k == "bridge":
		return true                        # 桥是架在水上的，别在桥两边多画一道岸线
	return k == kind


func _draw_board() -> void:
	var o := _cam_offset
	var f := ThemeDB.fallback_font
	_drawn_plant_overlays = 0

	for y in range(GRID_H):
		for x in range(GRID_W):
			var t := GameState.get_tile(x, y)
			var kind := str(t.get("kind", "cleared"))
			var p := Vector2(x * TILE, y * TILE) + o
			var r := Rect2(p, Vector2(TILE, TILE))

			# ---- 第一层：地面 ----
			# 树、灵兽、灵草的贴图是带透明的精灵，必须先铺一层地，
			# 否则透明处会直接露出窗口底色（黑方块）。
			var ground := "wild"
			if kind == "cleared" or kind == "planted":
				ground = kind
			elif kind in PERMANENT:
				ground = ""                      # 山包/溪流自己就是地面，不铺土
			elif kind == "bridge" and _set_tex.has("bridge"):
				ground = ""                      # 桥的套图里自带水面，同理
			if ground != "" and _tex.has(ground):
				_board.draw_texture_rect(_tex[ground], r, false)
			else:
				_board.draw_rect(r, BASE_COLOR.get(kind, Color("2f4034")), true)
				# 这圈描边是压着格子边线画的，有一半落在邻格上。邻格已经画完了，
				# 于是自带地面的格子（山包/溪流/桥）之间会留下一条深缝。
				if not (kind in PERMANENT or (kind == "bridge" and _set_tex.has("bridge"))):
					_board.draw_rect(r, Color(0, 0, 0, 0.20), false, 1.0)

			# 山包 / 溪流：从九宫格套图里挑对应的边角格
			var drew_tex := false
			if kind in PERMANENT and _set_tex.has(kind):
				_board.draw_texture_rect_region(_set_tex[kind], r, _slice_of(x, y, kind))
				drew_tex = true
			elif kind == "bridge" and _set_tex.has("bridge"):
				# 桥永远是东西向横跨竖着的溪流，只占一行，所以固定取套图中间那行。
				# 列由左右邻格决定：桥头 / 中段 / 桥尾。
				_board.draw_texture_rect_region(_set_tex["bridge"], r,
					Rect2(_bridge_col(x, y) * TILE, TILE, TILE, TILE))
				drew_tex = true

			# ---- 第二层：地块自己的贴图（叠在地面上）----
			if kind in ["tree", "beast", "grass", "rock"] and _tex.has(kind):
				_board.draw_texture_rect(_tex[kind], r, false)
				drew_tex = true
			elif kind in ["wild", "cleared"] and _tex.has(kind):
				drew_tex = true              # 这几种的贴图在上面当地面铺过了
			# planted 虽然也已经铺了土地底图，但不能设 drew_tex：下面的
			# match 还要继续叠加四阶段灵草、进度条和倒计时。

			# 下面 match 里全是**没有美术素材时的占位图形**。
			# 有贴图就一律跳过 —— 之前只挡了 tree/beast，结果荒地的小石子、
			# 杂石的多边形、野草的草叶全画在了真贴图上，看着像打补丁。
			if not drew_tex:
				match kind:
					"grass":
						for i in range(3):
							var g := p + Vector2(11 + i * 13, 34)
							_board.draw_line(g, g + Vector2(-3, -11), Color("6d9152"), 2.0)
							_board.draw_line(g, g + Vector2(3, -13), Color("7ea35e"), 2.0)

					"wild":
						_board.draw_circle(p + Vector2(14, 30), 4, Color("6a6350"))
						_board.draw_circle(p + Vector2(32, 18), 3, Color("6a6350"))

					"rock":
						_board.draw_colored_polygon(PackedVector2Array([
							p + Vector2(10, 36), p + Vector2(17, 18),
							p + Vector2(28, 22), p + Vector2(26, 37)]), Color("7b8189"))
						_board.draw_colored_polygon(PackedVector2Array([
							p + Vector2(27, 37), p + Vector2(33, 25),
							p + Vector2(40, 31), p + Vector2(39, 38)]), Color("656b73"))

					"tree":
						_board.draw_circle(p + Vector2(24, 22), 15, Color("2f6b3a"))
						_board.draw_rect(Rect2(p + Vector2(21, 32), Vector2(6, 12)),
							Color("4a3524"), true)

					"beast":
						_board.draw_circle(p + Vector2(24, 26), 13, Color("a84b4b"))
						_board.draw_circle(p + Vector2(19, 22), 2.5, Color.WHITE)
						_board.draw_circle(p + Vector2(29, 22), 2.5, Color.WHITE)

					"hill":
						_board.draw_circle(p + Vector2(24, 26), 20, Color("60543f"))
						if not _same(x, y - 1, "hill"):
							_board.draw_line(p + Vector2(1, 5), p + Vector2(47, 5),
								Color("7d6e52"), 3.0)
						if not _same(x, y + 1, "hill"):
							_board.draw_line(p + Vector2(1, 45), p + Vector2(47, 45),
								Color("3b3327"), 3.0)

					"bridge":
						# 木桥：先铺水（有套图就用套图的内部格），再铺横板 + 两侧栏杆
						if _set_tex.has("stream"):
							_board.draw_texture_rect_region(_set_tex["stream"], r,
								Rect2(TILE, TILE, TILE, TILE))
						else:
							_board.draw_rect(r, BASE_COLOR["stream"], true)
						for i in range(5):
							_board.draw_rect(Rect2(p + Vector2(2, 4 + i * 9),
								Vector2(44, 6)), Color("8a6b42"), true)
						_board.draw_rect(Rect2(p + Vector2(0, 2), Vector2(4, 44)),
							Color("5e4630"), true)
						_board.draw_rect(Rect2(p + Vector2(44, 2), Vector2(4, 44)),
							Color("5e4630"), true)

					"stream":
						for i in range(2):
							var wy := p.y + 16 + i * 16
							_board.draw_line(Vector2(p.x + 6, wy), Vector2(p.x + 42, wy),
								Color(0.55, 0.78, 0.92, 0.32), 2.0)
						if not _same(x - 1, y, "stream") and _kind(x - 1, y) != "bridge":
							_board.draw_line(p + Vector2(3, 0), p + Vector2(3, 48),
								Color("6f93ad"), 3.0)
						if not _same(x + 1, y, "stream") and _kind(x + 1, y) != "bridge":
							_board.draw_line(p + Vector2(45, 0), p + Vector2(45, 48),
								Color("6f93ad"), 3.0)

					"planted":
						_drawn_plant_overlays += 1
						var ready := GameState.herb_ready(t)
						var left := GameState.herb_remaining(t)
						var total: float = max(1.0, float(t.get("grow_seconds", GROW_SECONDS)))
						var prog: float = clamp(1.0 - left / total, 0.0, 1.0)
						if _herb_tex.size() == 4:
							# 按生长进度切四阶段贴图
							var stage := 3 if ready else int(prog * 3.0)
							_board.draw_texture_rect(_herb_tex[clampi(stage, 0, 3)], r, false)
						else:
							var col := Style.JADE if ready else Color("7fa85e")
							var h := 6.0 + 20.0 * prog
							_board.draw_rect(Rect2(p + Vector2(22, 40 - h), Vector2(4, h)), col, true)
							if ready:
								_board.draw_circle(p + Vector2(24, 40 - h), 6, Style.JADE)
						if not ready:
							# 成熟倒计时：进度条 + 剩余时间，不用点开也看得见还要多久
							_board.draw_rect(Rect2(p + Vector2(6, 43), Vector2(36, 3)),
								Color(0, 0, 0, 0.45), true)
							_board.draw_rect(Rect2(p + Vector2(6, 43),
								Vector2(36 * prog, 3)), Color("9ec27a"), true)
							var cd := _fmt_short(left)
							var cw := f.get_string_size(cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
							_board.draw_rect(Rect2(p + Vector2(24 - cw * 0.5 - 3, 2),
								Vector2(cw + 6, 14)), Color(0, 0, 0, 0.55), true)
							_board.draw_string(f, p + Vector2(24 - cw * 0.5, 13), cd,
								HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("d7e8c4"))
						else:
							# 熟了给个明显的标记
							_board.draw_string(f, p + Vector2(15, 14), "熟",
								HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.GOLD)

	# 据点入口
	var door := Rect2(Vector2(TILE * 1.0, TILE * 3.0) + o, Vector2(TILE * 2, TILE * 2))
	if _door_tex != null:
		# 建筑正好 96×96，铺满 2×2 格。带透明边，所以底下的地照样露出来。
		_board.draw_texture_rect(_door_tex, door, false)
	else:
		_board.draw_rect(door, Color("3b3550"), true)
		_board.draw_rect(door, Style.GOLD, false, 2.0)
	# 名字压在建筑身上会看不清，挪到下面，加一条底衬。
	var nm := "宗门据点"
	var nw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var nx := door.position.x + door.size.x * 0.5 - nw * 0.5
	var ny := door.position.y + door.size.y + 15.0
	_board.draw_rect(Rect2(Vector2(nx - 5, ny - 13), Vector2(nw + 10, 18)),
		Color(0, 0, 0, 0.55), true)
	_board.draw_string(f, Vector2(nx, ny), nm,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Style.GOLD)
	if _near_door():
		var tip := "按 E 进入"
		var tw := f.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var tx := door.position.x + door.size.x * 0.5 - tw * 0.5
		_board.draw_rect(Rect2(Vector2(tx - 5, ny + 5), Vector2(tw + 10, 17)),
			Color(0, 0, 0, 0.55), true)
		_board.draw_string(f, Vector2(tx, ny + 18), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.TEXT)

	# 特效（画在地块之上、道身之下）
	for e in _fx_playing:
		var fr: int = clampi(int(float(e["t"]) / 0.07), 0, 5)
		_board.draw_texture_rect_region(e["tex"],
			Rect2(e["pos"] + o, Vector2(TILE, TILE)),
			Rect2(fr * 64, 0, 64, 64))

	# 道身
	var pp := _player_pos + o
	_board.draw_circle(pp + Vector2(0, 6), 11, Color(0, 0, 0, 0.28))     # 影子
	if _walk != null:
		# 行走图：4 行（下/左/右/上）× 4 帧，每帧 48×64
		var row := 0
		if absf(_facing.x) > absf(_facing.y):
			row = 2 if _facing.x > 0.0 else 1
		else:
			row = 0 if _facing.y > 0.0 else 3
		var frame := int(_anim_t * 8.0) % 4 if _moving else 0
		var src := Rect2(frame * 48, row * 64, 48, 64)
		_board.draw_texture_rect_region(_walk, Rect2(pp - Vector2(24, 52), Vector2(48, 64)), src)
	else:
		_board.draw_rect(Rect2(pp - Vector2(9, 20), Vector2(18, 26)), Style.JADE_DIM, true)
		_board.draw_circle(pp - Vector2(0, 22), 8, Color("e8d5b0"))
		_board.draw_circle(pp + _facing * 16 - Vector2(0, 6), 3, Style.GOLD)
