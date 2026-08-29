extends Node
##
## 全局游戏状态 + 存档
##
## 【开始游戏】读存档继续；【重置游戏】清档从头开始（路演/测试用）。
##

signal stones_changed(value: int)
signal exp_changed(value: int, level: int)
signal inventory_changed()
signal tasks_changed()

const SAVE_PATH := "user://saved.json"

# ---- 命名（策划案里定过的口径） ----
# 最基础的灵草，名字不用高大上
const HERB_NAME := "青芒草"
# Token 消耗换算来的额外灵石，不能在游戏里直说"Token"
const TOKEN_BONUS_NAME := "吐纳所得"
const TOKEN_PER_STONE := 1000          # 1000 Token = 1 灵石

# ---- 价格 ----
const PRICE := {
	"seed":  10,   # 灵草种子
	"bomb":  5,    # 爆破符
	"elixir": 5,   # 灵液（立刻催熟）
}

# ---- 玩家 ----
var player_name := "萌主"
var realm := "筑基"                      # 当前境界
var realm_index := 3                     # 十境中的第 3 境（凡人/练气/筑基…）
var level := 21                          # 筑基 = Lv21–30
var exp_value := 0
var exp_to_next := 100
var stones := 0                          # 灵石
var artifact := "ZCode"                  # 本命法器
const SPIRIT_NAME := "青璃"
const SPIRIT_LEVEL := 2
const BEAST_LEVEL := 2

# 六脉（各十窍）。产品脉是主脉，当前最突出。
var meridians := {
	"产品脉": 4, "技术脉": 2, "商业脉": 1,
	"内容脉": 2, "表达脉": 2, "思维脉": 1,
}
const MERIDIAN_ORDER := ["产品脉", "技术脉", "商业脉", "内容脉", "表达脉", "思维脉"]

# ---- 背包 / 工具格 ----
var inventory := {"bomb": 0, "seed": 0, "elixir": 0, "herb": 0}

# 剧情开关（新手礼包是否已领、历练任务是否已接…）
var flags := {}
const TOOLBAR := ["bomb", "seed", "elixir", "spirit"]
var selected_tool := 0
## 自动化验收会临时改动背包和地块；禁止把这些测试夹具写回玩家存档。
var suppress_persistence := false


func should_play_intro() -> bool:
	return not bool(flags.get("intro_seen", false))


func mark_intro_seen() -> void:
	flags["intro_seen"] = true
	save_game()

const ITEM_NAME := {
	"bomb": "爆破符", "seed": "%s种子" % HERB_NAME,
	"elixir": "灵液", "herb": HERB_NAME, "spirit": "器灵·%s" % SPIRIT_NAME,
}

# ---- 秘境地块 ----
# key = "x,y" -> {kind: wild|cleared|planted|tree|beast, planted_at: int, ready_at: int}
var tiles := {}
var mijing_entered := false

# ---- 任务 ----
# {id, title, desc, kind: main|drill, status: open|running|done|claimed,
#  reward_stones, token_used, automation_id}
var tasks := []
var _task_seq := 0

# Agent 累计工作秒数 —— 用来抵扣灵草成熟时间
var agent_seconds := 0.0


func _ready() -> void:
	load_game()


# ---------------------------------------------------------------- 资源

func add_stones(n: int) -> void:
	stones += n
	stones_changed.emit(stones)
	save_game()


func spend_stones(n: int) -> bool:
	if stones < n:
		return false
	stones -= n
	stones_changed.emit(stones)
	save_game()
	return true


func add_exp(n: int) -> void:
	exp_value += n
	while exp_value >= exp_to_next:
		exp_value -= exp_to_next
		level += 1
		exp_to_next = int(exp_to_next * 1.25)
	exp_changed.emit(exp_value, level)
	save_game()


func add_item(key: String, n: int) -> void:
	inventory[key] = inventory.get(key, 0) + n
	inventory_changed.emit()
	save_game()


func use_item(key: String, n: int = 1) -> bool:
	if inventory.get(key, 0) < n:
		return false
	inventory[key] -= n
	inventory_changed.emit()
	save_game()
	return true


func item_count(key: String) -> int:
	return inventory.get(key, 0)


func herb_slot_unlocked() -> bool:
	return bool(flags.get("herb_slot_unlocked", false))


func unlock_herb_slot() -> void:
	if herb_slot_unlocked():
		return
	flags["herb_slot_unlocked"] = true
	inventory_changed.emit()
	save_game()


func current_tool() -> String:
	return TOOLBAR[selected_tool]


# ---------------------------------------------------------------- 秘境地块

func tile_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func get_tile(x: int, y: int) -> Dictionary:
	return tiles.get(tile_key(x, y), {})


func set_tile(x: int, y: int, data: Dictionary) -> void:
	tiles[tile_key(x, y)] = data
	save_game()


## 灵草是否已成熟。自然流逝时间 + Agent 工作时长 共同计入。
func herb_ready(t: Dictionary) -> bool:
	if t.get("kind", "") != "planted":
		return false
	var elapsed := Time.get_unix_time_from_system() - float(t.get("planted_at", 0))
	return (elapsed + agent_seconds) >= float(t.get("grow_seconds", 3600))


func herb_remaining(t: Dictionary) -> float:
	var elapsed := Time.get_unix_time_from_system() - float(t.get("planted_at", 0))
	return max(0.0, float(t.get("grow_seconds", 3600)) - elapsed - agent_seconds)


# ---------------------------------------------------------------- 任务

func new_drill_task() -> Dictionary:
	_task_seq += 1
	var t := {
		"id": "drill-%d" % _task_seq,
		"title": "制作一个润色朋友圈文案的 Skill",
		"desc": "在工作目录里创建一个可复用的 Skill：输入一段朋友圈草稿，输出润色后的版本。要求写成 SKILL.md，包含用途说明、输入输出示例。",
		"kind": "drill",
		"status": "open",
		"reward_stones": 10,
		"reward_exp": 20,
		"token_used": 0,
		"automation_id": "",
	}
	tasks.append(t)
	tasks_changed.emit()
	save_game()
	return t


## 主任务 + 所有子任务展平成一个列表。轮询、计数、查找都走这个。
func all_tasks() -> Array:
	var out: Array = []
	for t in tasks:
		out.append(t)
		for st in t.get("subtasks", []):
			out.append(st)
	return out


func find_task(id: String) -> Dictionary:
	for t in all_tasks():
		if t["id"] == id:
			return t
	return {}


func unclaimed_count() -> int:
	var n := 0
	for t in all_tasks():
		if t["status"] == "done":
			n += 1
	return n


func claim_task(id: String) -> Dictionary:
	var t := find_task(id)
	if t.is_empty() or t["status"] != "done":
		return {}
	var bonus := int(float(t.get("token_used", 0)) / TOKEN_PER_STONE)
	var total := int(t["reward_stones"]) + bonus
	add_stones(total)
	add_exp(int(t.get("reward_exp", 0)))
	t["status"] = "claimed"
	_settle_parent(t)
	tasks_changed.emit()
	save_game()
	return {"base": t["reward_stones"], "bonus": bonus, "total": total}


## 四条 KR 都领完了，主线自动算达成（主线奖励已经分摊在 KR 里，这里不再重复发）
func _settle_parent(child: Dictionary) -> void:
	var pid := str(child.get("parent", ""))
	if pid == "":
		return
	for t in tasks:
		if t["id"] != pid:
			continue
		for st in t.get("subtasks", []):
			if st["status"] != "claimed":
				return
		if t["status"] != "claimed":
			t["status"] = "claimed"
		return


const TASK_CHAIN_PATH := "res://data/task_chain.json"


func _seed_tasks() -> void:
	# 八关任务链是外部数据（黑客松/八关任务链.json），改内容不用动代码。
	# 读不到就退回一个最小的占位主线，保证游戏还能跑。
	tasks = _load_task_chain()
	if tasks.is_empty():
		tasks = [{
			"id": "main-1", "title": "制作一款 AI 产品小程序",
			"desc": "任务链数据缺失（data/task_chain.json）",
			"kind": "main", "status": "open",
			"reward_stones": 200, "reward_exp": 200,
			"token_used": 0, "automation_id": "", "subtasks": [],
		}]
	_task_seq = 0


func _load_task_chain() -> Array:
	if not FileAccess.file_exists(TASK_CHAIN_PATH):
		return []
	var f := FileAccess.open(TASK_CHAIN_PATH, FileAccess.READ)
	if f == null:
		return []
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	var d: Dictionary = raw
	if not d.has("main") or not d.has("levels"):
		return []
	var main: Dictionary = d["main"]
	main["subtasks"] = d["levels"]
	return [main]


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	if suppress_persistence:
		return
	var d := {
		"player_name": player_name, "realm": realm, "realm_index": realm_index,
		"level": level, "exp_value": exp_value, "exp_to_next": exp_to_next,
		"stones": stones, "artifact": artifact, "meridians": meridians,
		"inventory": inventory, "flags": flags, "selected_tool": selected_tool,
		"tiles": tiles, "mijing_entered": mijing_entered,
		"tasks": tasks, "task_seq": _task_seq, "agent_seconds": agent_seconds,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_seed_tasks()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_seed_tasks(); return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		_seed_tasks(); return
	var d: Dictionary = raw
	player_name = d.get("player_name", player_name)
	realm = d.get("realm", realm)
	realm_index = int(d.get("realm_index", realm_index))
	level = int(d.get("level", level))
	exp_value = int(d.get("exp_value", exp_value))
	exp_to_next = int(d.get("exp_to_next", exp_to_next))
	stones = int(d.get("stones", stones))
	artifact = d.get("artifact", artifact)
	meridians = d.get("meridians", meridians)
	inventory = d.get("inventory", inventory)
	flags = d.get("flags", {})
	# 兼容旧存档：已经收割过青芒草的人不应该丢失库存格。
	if int(inventory.get("herb", 0)) > 0:
		flags["herb_slot_unlocked"] = true
	selected_tool = int(d.get("selected_tool", 0))
	tiles = d.get("tiles", {})
	mijing_entered = bool(d.get("mijing_entered", false))
	tasks = d.get("tasks", [])
	_task_seq = int(d.get("task_seq", 0))
	agent_seconds = float(d.get("agent_seconds", 0.0))
	if tasks.is_empty():
		_seed_tasks()


## 【重置游戏】—— 路演和测试用，每次从头开始
func reset_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	player_name = "萌主"; realm = "筑基"; realm_index = 3
	level = 21; exp_value = 0; exp_to_next = 100
	stones = 0; artifact = "ZCode"
	meridians = {"产品脉": 4, "技术脉": 2, "商业脉": 1, "内容脉": 2, "表达脉": 2, "思维脉": 1}
	inventory = {"bomb": 0, "seed": 0, "elixir": 0, "herb": 0}
	flags = {}
	selected_tool = 0
	tiles = {}; mijing_entered = false
	agent_seconds = 0.0
	_seed_tasks()
	save_game()
