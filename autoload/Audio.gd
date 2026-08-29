extends Node
##
## 音频总管
##
##   BGM      赛博国风背景乐，循环
##   环境音   秘境里的户外底噪，循环（进别的地图自动停）
##   音效     一次性反馈：拔草、爆破、播种、收割、点击、领奖…
##
## 用法： Audio.sfx("blast")        播一个音效
##        Audio.step_on("grass")    走路脚步（自动限频，不会连成一串噪音）
##        Audio.ambience(true)      进/出秘境时开关环境音

const SFX := {
	"blast":   "res://assets/audio/blast.wav",       # 爆破符
	"grass":   "res://assets/audio/grass_pull.wav",  # 拔野草
	"tree":    "res://assets/audio/tree_fall.wav",   # 砍树 / 碎石
	"water":   "res://assets/audio/water.wav",       # 灵液 / 溪水
	"plant":   "res://assets/audio/plant.wav",       # 播种
	"harvest": "res://assets/audio/harvest.wav",     # 收割
	"click":   "res://assets/audio/click.wav",       # UI 点击
	"notify":  "res://assets/audio/notify.wav",      # 任务完成
	"levelup": "res://assets/audio/levelup.wav",     # 领奖 / 升级
	"bird":    "res://assets/audio/bird.wav",        # 鸟叫点缀
	"foxfire": "res://assets/audio/foxfire.wav",     # 器灵狐火
}

## 每张地图一首。key 跟 World.MAPS 的 id 对齐，另加一个 "title"（首页+开场）。
const BGM := {
	"title":   "res://assets/audio/bgm_title.mp3",     # 襟怀玉界
	"zongmen": "res://assets/audio/bgm_zongmen.mp3",   # 天下熙熙
	"jiezi":   "res://assets/audio/bgm_jiezi.mp3",     # 玲珑工巧
	"wenxian": "res://assets/audio/bgm_wenxian.mp3",   # 无俗念
	"qingwu":  "res://assets/audio/bgm_qingwu.mp3",    # 邀挽明月成宵宴
}

const STEP_GRASS := ["grass_1", "grass_2", "grass_3", "grass_4", "grass_5"]
const STEP_WOOD := ["wood_1", "wood_2", "wood_3"]

const BGM_DB := -14.0
const AMB_DB := -22.0
const SFX_DB := -8.0
const STEP_DB := -18.0
const STEP_INTERVAL := 0.34      # 两声脚步的最小间隔

var _bgm: AudioStreamPlayer
var _bgm_key := ""
var _bgm_tween: Tween = null
var _narr: AudioStreamPlayer          # PV 旁白
var _amb: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _cache := {}
var sfx_play_counts := {}
var _step_cd := 0.0
var _bird_cd := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()

	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = BGM_DB
	_bgm.bus = "Master"
	add_child(_bgm)

	_narr = AudioStreamPlayer.new()
	_narr.volume_db = -3.0
	add_child(_narr)
	_narr.finished.connect(func() -> void: _duck(false))

	_amb = AudioStreamPlayer.new()
	_amb.volume_db = AMB_DB
	add_child(_amb)
	var amb_path := "res://assets/audio/ambience_outdoor.wav"
	if ResourceLoader.exists(amb_path):
		var st2 := load(amb_path)
		if st2 is AudioStreamWAV:
			(st2 as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		_amb.stream = st2

	# 一次性音效用播放器池，避免互相打断
	for i in range(8):
		var pl := AudioStreamPlayer.new()
		pl.volume_db = SFX_DB
		add_child(pl)
		_pool.append(pl)


## 统一的按钮点击声。不去动各个按钮的 pressed 信号 ——
## 那样做会因为 lambda 没有属主而打断信号派发（踩过）。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered is BaseButton and not (hovered as BaseButton).disabled:
			sfx("click", -14.0)


func _process(delta: float) -> void:
	_step_cd = max(0.0, _step_cd - delta)
	# 环境音开着的时候，偶尔来一声鸟叫
	if _amb.playing:
		_bird_cd -= delta
		if _bird_cd <= 0.0:
			_bird_cd = _rng.randf_range(9.0, 20.0)
			sfx("bird", -20.0)


func _free_player() -> AudioStreamPlayer:
	for pl in _pool:
		if not pl.playing:
			return pl
	return _pool[0]


func _stream(path: String) -> Resource:
	if not _cache.has(path):
		if not ResourceLoader.exists(path):
			return null
		_cache[path] = load(path)
	return _cache[path]


## 播一个音效。缺文件就静默跳过，不报错。
func sfx(key: String, db: float = SFX_DB) -> bool:
	if not SFX.has(key):
		return false
	var st := _stream(SFX[key])
	if st == null:
		return false
	var pl := _free_player()
	pl.stream = st
	pl.volume_db = db
	pl.pitch_scale = _rng.randf_range(0.96, 1.05)   # 轻微变调，听着不机械
	pl.play()
	sfx_play_counts[key] = int(sfx_play_counts.get(key, 0)) + 1
	return true


## 脚步。surface = "grass" / "wood"（走在桥上）
func step_on(surface: String) -> void:
	if _step_cd > 0.0:
		return
	_step_cd = STEP_INTERVAL
	var names: Array = STEP_WOOD if surface == "wood" else STEP_GRASS
	var n: String = names[_rng.randi() % names.size()]
	var st := _stream("res://assets/audio/step/%s.wav" % n)
	if st == null:
		return
	var pl := _free_player()
	pl.stream = st
	pl.volume_db = STEP_DB
	pl.pitch_scale = _rng.randf_range(0.92, 1.08)
	pl.play()


## 换背景音乐。key 见 BGM 表；同一首不会重播，切换时淡入淡出。
func bgm(key: String) -> void:
	if key == _bgm_key:
		return
	if not BGM.has(key):
		return
	var st := _stream(BGM[key])
	if st == null:
		return
	_bgm_key = key

	# mp3 默认不循环，得显式打开，否则放完就没了
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true

	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()

	if not _bgm.playing:
		_bgm.stream = st
		_bgm.volume_db = BGM_DB
		_bgm.play()
		return

	# 旧曲淡出 → 换轨 → 新曲淡入
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm, "volume_db", -40.0, 0.6)
	_bgm_tween.tween_callback(func() -> void:
		_bgm.stream = st
		_bgm.play()
	)
	_bgm_tween.tween_property(_bgm, "volume_db", BGM_DB, 0.8)


## 播 PV 旁白。播的时候把 BGM 压下去，不然两条人声/乐器打架。
func play_narration(path: String) -> void:
	var st := _stream(path)
	if st == null:
		return
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = false
	_narr.stream = st
	_narr.play()
	_duck(true)


func stop_narration() -> void:
	if _narr.playing:
		_narr.stop()
	_duck(false)


## 旁白期间把背景乐压低
func _duck(on: bool) -> void:
	if _bgm_tween != null and _bgm_tween.is_valid():
		return                                   # 正在切歌就别插手
	var target := BGM_DB - 12.0 if on else BGM_DB
	create_tween().tween_property(_bgm, "volume_db", target, 0.35)


func ambience(on: bool) -> void:
	if _amb.stream == null:
		return
	if on and not _amb.playing:
		_amb.play()
		_bird_cd = _rng.randf_range(4.0, 10.0)
	elif not on and _amb.playing:
		_amb.stop()
