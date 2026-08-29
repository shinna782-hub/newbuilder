extends Node
##
## 法宝桥客户端 —— 游戏 <-> ZCode 桌面端
##
## 派发出去的任务会在 ZCode 桌面端开一个**原生会话**，观众看得见，也能多轮对话。
## 桥：node 黑客松/法宝桥/bridge.js
##

signal bridge_ok(ok: bool)
signal bridge_info_changed()
signal task_phase_changed(task_id: String, phase: String)

const BASE := "http://127.0.0.1:7777"
const POLL_INTERVAL := 3.0

var connected := false
var workspace_path := ""
var workspace_registered := false
var workspace_added_this_run := false

var _pollers := {}          # task_id -> HTTPRequest
var _running_since := {}    # task_id -> unix time（用来累计 Agent 工时）


func _ready() -> void:
	check_health()
	var t := Timer.new()
	t.wait_time = POLL_INTERVAL
	t.timeout.connect(_poll_all)
	add_child(t)
	t.start()


func _process(delta: float) -> void:
	# Agent 正在跑的时候，累计工时 —— 这段时间会抵扣灵草成熟倒计时
	if not _running_since.is_empty():
		GameState.agent_seconds += delta


func check_health() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			connected = (code == 200)
			if connected:
				var data: Variant = JSON.parse_string(body.get_string_from_utf8())
				if typeof(data) == TYPE_DICTIONARY:
					workspace_path = str(data.get("workspace", ""))
					workspace_registered = bool(data.get("workspaceRegistered", false))
					workspace_added_this_run = bool(data.get("workspaceAddedThisRun", false))
			else:
				workspace_registered = false
			bridge_ok.emit(connected)
			bridge_info_changed.emit()
			http.queue_free()
	)
	if http.request(BASE + "/health") != OK:
		connected = false
		workspace_registered = false
		bridge_ok.emit(false)
		bridge_info_changed.emit()
		http.queue_free()


## 把任务派发给本命法器。成功则把 automation_id 写回任务。
func dispatch(task: Dictionary) -> void:
	var prompt := "%s\n\n%s" % [task["title"], task.get("desc", "")]
	var body := JSON.stringify({
		"title": task["title"],
		"prompt": prompt.replace("\n", " "),
	})

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, resp: PackedByteArray) -> void:
			if code == 200:
				var d: Variant = JSON.parse_string(resp.get_string_from_utf8())
				if typeof(d) == TYPE_DICTIONARY and d.get("ok", false):
					task["automation_id"] = str(d["automationId"])
					task["status"] = "running"
					task["started_at"] = Time.get_unix_time_from_system()
					_running_since[task["id"]] = Time.get_unix_time_from_system()
					GameState.tasks_changed.emit()
					GameState.save_game()
					task_phase_changed.emit(task["id"], "running")
				else:
					task_phase_changed.emit(task["id"], "error")
			else:
				task_phase_changed.emit(task["id"], "error")
			http.queue_free()
	)

	if http.request(BASE + "/dispatch", ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, body) != OK:
		task_phase_changed.emit(task["id"], "error")
		http.queue_free()


## 把任务放回「未开始」，让玩家能重新派发。
## 只动游戏这边的状态 —— ZCode 那边已经开的会话不去打扰它。
func cancel(task: Dictionary) -> void:
	var tid: String = task["id"]
	_running_since.erase(tid)
	if _pollers.has(tid):
		_pollers[tid].queue_free()
		_pollers.erase(tid)
	task["status"] = "open"
	task["automation_id"] = ""
	task["started_at"] = 0
	GameState.tasks_changed.emit()
	GameState.save_game()
	task_phase_changed.emit(tid, "open")


func _poll_all() -> void:
	for t in GameState.all_tasks():
		if t["status"] == "running" and str(t.get("automation_id", "")) != "":
			_poll(t)


func _poll(task: Dictionary) -> void:
	var tid: String = task["id"]
	if not _pollers.has(tid):
		var h := HTTPRequest.new()
		add_child(h)
		_pollers[tid] = h

	var http: HTTPRequest = _pollers[tid]
	if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	for c in http.request_completed.get_connections():
		http.request_completed.disconnect(c["callable"])

	http.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, resp: PackedByteArray) -> void:
			if code != 200:
				return
			var d: Variant = JSON.parse_string(resp.get_string_from_utf8())
			if typeof(d) != TYPE_DICTIONARY:
				return
			var phase := str(d.get("phase", ""))
			if phase == "completed":
				# 结算 Token 消耗 —— 桥暂时不回传真实用量，按工时估一个
				var secs: float = Time.get_unix_time_from_system() - float(_running_since.get(tid, 0))
				task["token_used"] = int(max(500.0, secs * 120.0))
				task["status"] = "done"        # 待领取，任务列表出小红点
				_running_since.erase(tid)
				GameState.tasks_changed.emit()
				GameState.save_game()
				Audio.sfx("notify")
				task_phase_changed.emit(tid, "completed")
			elif phase == "error":
				task["status"] = "open"
				_running_since.erase(tid)
				GameState.tasks_changed.emit()
				task_phase_changed.emit(tid, "error")
	)

	http.request(BASE + "/status?id=" + str(task["automation_id"]).uri_encode())
