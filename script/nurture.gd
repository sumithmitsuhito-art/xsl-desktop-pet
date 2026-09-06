extends Node
## 养成数值系统（一期）：三大数值 + 每20秒结算 + 打字统计 + 数值加权动画池 + 存档。
## 纯本地、无台词，数值全部整数。main 在按键/单击/拖动/菜单里调用本节点的方法，
## 本节点通过信号通知 main：food_gained / feed_feedback / feed_success / cheer_burst / should_sleep。

# ---------- 可调常数（数值一律整数；改完保存重跑即生效，TICK_SECONDS 可临时调小加速验证） ----------
const TICK_SECONDS := 20.0            # 结算周期（秒）
const ACTIVE_KEYS_PER_TICK := 15      # 一个结算周期内 ≥ 该键数算"活跃打字"
const ENERGY_COST_ACTIVE := 2         # 活跃打字：每周期精力 -2
const ENERGY_REGEN_QUIET := 1         # 安静：每周期精力 +1
const MOOD_DECAY_QUIET := 2           # 安静：每周期心情 -2
const FOOD_PROGRESS_NEED := 15        # 食物进度攒满该值 → 获得 1 个食物
const FOOD_MAX := 20                  # 食物库存上限
const FEED_ENERGY := 30               # 投喂：精力 +30
const FEED_MOOD := 5                  # 投喂：心情 +5
const FEED_INTIMACY := 2              # 投喂：亲密度 +2
const CLICK_MOOD := 3                 # 单击：心情 +3
const CLICK_COOLDOWN := 10.0          # 单击计数值冷却（秒）
const DRAG_MOOD := 1                  # 拖动：心情 +1
const DRAG_COOLDOWN := 30.0           # 拖动计数值冷却（秒）
const CHEER_BURST_KEYS := 80          # 滑动窗口内 ≥ 该键数 = "敲得欢"（边沿触发：从低于涨破阈值那一刻触发一次，停手回落到阈值下才重新武装）
const CHEER_BURST_WINDOW := 30.0      # 敲得欢滑动窗口（秒）
const CHEER_BURST_MOOD := 1           # 敲得欢：心情 +1
const NO_KEY_SLEEPY_SECONDS := 60.0   # 该秒数无键入 → 睡觉（sleepy 循环）
const HAPPY_MOOD := 80                # 心情 ≥ 该值算"开心时光"
const HAPPY_TICKS_NEED := 6           # 开心 tick 累计该值（=3 分钟）→ 亲密度 +1
const INTERACT_INTIMACY_MOOD := 80    # 心情 ≥ 该值时，单击互动额外 +1 亲密度
# 自动动画加权池：基础 sleepy 权重 3，按数值增减（详见 AGENTS.md 9.1 ⑤）
const AUTO_W_SLEEPY := 3
const AUTO_W_SLEEPY_TIRED := 3        # 精力 ≤15 时 sleepy 额外权重
const AUTO_W_CHEER_MOOD := 2          # 心情 ≥60 时 cheer 权重
const AUTO_W_CHEER_ENERGY := 2        # 精力 ≥60 时 cheer 追加权重
const AUTO_W_CRY := 4                 # 心情 ≤20 时 cry 权重
const MOOD_CHEER := 60
const ENERGY_HIGH := 60               # 精力 ≥ 该值：cheer 追加、走路概率 ×1.5
const MOOD_LOW := 20
const ENERGY_LOW := 15                # 精力 ≤ 该值：走路概率 ×0.3、sleepy 加权
const WALK_MULT_HIGH := 1.5
const WALK_MULT_LOW := 0.3
const SAVE_PATH := "user://save.json"
const SAVE_DEBOUNCE := 5.0            # 数值变动后延迟合并写盘（秒）
const OFFLINE_SLEEP_SECONDS := 3600.0 # 离线超 1 小时视为"它睡了"：精力回满、心情不动

# ---------- 对 main 的通知 ----------
signal food_gained(count: int)        # 获得 1 个食物（count = 当前库存）
signal feed_feedback(text: String)    # 投喂结果（成功/拒绝/没食物，极简系统反馈）
signal feed_success                   # 投喂成功（main 播 cheer）
signal cheer_burst                    # 敲得欢（main 播 cheer）
signal should_sleep                   # 该睡觉了（main 进 sleepy 循环；已睡/忙碌由 main 忽略）

# ---------- 数值状态（全部 int） ----------
var energy := 80
var mood := 60
var intimacy := 0
var food := 0
var food_progress := 0
var keys_today := 0
var keys_total := 0
var companion_seconds_today := 0      # 今日陪伴秒数（按 tick 粗略累计）

var _keys_this_tick := 0
var _recent_key_times: Array[float] = []   # 最近一个窗口内的按键时间戳（敲得欢判定用）
var _last_key_msec := 0
var _burst_armed := true                   # 敲得欢边沿触发臂：触发后落下，键数回落后重新武装
var _click_last_msec := -1000000
var _drag_last_msec := -1000000
var _happy_ticks := 0
var _today := ""
var _save_dirty := false
var _tick_timer: Timer
var _save_timer: Timer

func _ready() -> void:
	_load()
	_rollover_if_new_day()
	_tick_timer = Timer.new()
	_tick_timer.wait_time = TICK_SECONDS
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)
	_save_timer = Timer.new()
	_save_timer.wait_time = SAVE_DEBOUNCE
	_save_timer.one_shot = true
	_save_timer.timeout.connect(flush_save)
	add_child(_save_timer)

# ---------- main 每个按键"按下"时调用 ----------
func on_key_down(_vk: int) -> void:
	var now := Time.get_ticks_msec()
	_last_key_msec = now
	_keys_this_tick += 1
	keys_today += 1
	keys_total += 1
	var now_sec := float(now) / 1000.0
	_recent_key_times.append(now_sec)
	_prune_recent_keys(now_sec)
	# 敲得欢：边沿触发（无固定冷却）——键数涨破阈值那一刻触发一次，停手回落到阈值下才重新武装
	if _recent_key_times.size() >= CHEER_BURST_KEYS:
		if _burst_armed:
			_burst_armed = false
			mood = clampi(mood + CHEER_BURST_MOOD, 0, 100)
			cheer_burst.emit()
	else:
		_burst_armed = true
	_mark_dirty()

func _prune_recent_keys(now_sec: float) -> void:
	# 只保留最近一个窗口内的按键时间戳
	while _recent_key_times.size() > 0 and now_sec - _recent_key_times[0] > CHEER_BURST_WINDOW:
		_recent_key_times.remove_at(0)

# ---------- main 单击/拖动时调用（内部带冷却，重复调用安全） ----------
func on_click() -> void:
	var now := Time.get_ticks_msec()
	if now - _click_last_msec < int(CLICK_COOLDOWN * 1000.0):
		return
	_click_last_msec = now
	mood = clampi(mood + CLICK_MOOD, 0, 100)
	if mood >= INTERACT_INTIMACY_MOOD:
		intimacy = clampi(intimacy + 1, 0, 100)
	_mark_dirty()

func on_drag() -> void:
	var now := Time.get_ticks_msec()
	if now - _drag_last_msec < int(DRAG_COOLDOWN * 1000.0):
		return
	_drag_last_msec = now
	mood = clampi(mood + DRAG_MOOD, 0, 100)
	_mark_dirty()

# ---------- 投喂（右键菜单 → 喂食模式 → 点击角色完成） ----------
# 预检：返回拒绝原因文本，空串 = 可以喂（main 进喂食模式前调用）。
# 精力满不再拒绝（2026-09-06 用户要求删除"精力满不吃"限制），只有没食物才拒
func feed_precheck() -> String:
	if food <= 0:
		return "没有食物了，多敲敲键盘攒食物吧"
	return ""

# 正式投喂结算：会再次校验（喂食模式期间精力可能变化），成功返回 true
func try_feed() -> bool:
	var err := feed_precheck()
	if err != "":
		feed_feedback.emit(err)
		return false
	food -= 1
	energy = clampi(energy + FEED_ENERGY, 0, 100)
	mood = clampi(mood + FEED_MOOD, 0, 100)
	intimacy = clampi(intimacy + FEED_INTIMACY, 0, 100)
	_mark_dirty()
	feed_feedback.emit("开饭啦 精力+%d 心情+%d 亲密+%d" % [FEED_ENERGY, FEED_MOOD, FEED_INTIMACY])
	feed_success.emit()
	return true

# 喂食等"互动"也算陪伴：重置无键入睡计时（main 在投喂成功后调用）
func mark_interacted() -> void:
	_last_key_msec = Time.get_ticks_msec()

# ---------- 每 20 秒结算一次 ----------
func _on_tick() -> void:
	_rollover_if_new_day()
	companion_seconds_today += int(TICK_SECONDS)
	if _keys_this_tick >= ACTIVE_KEYS_PER_TICK:
		# 活跃打字：耗精力、攒食物进度（库存满时进度停住，等有空间再转）
		energy = clampi(energy - ENERGY_COST_ACTIVE, 0, 100)
		if food < FOOD_MAX:
			food_progress += 1
			if food_progress >= FOOD_PROGRESS_NEED:
				food_progress = 0
				food += 1
				food_gained.emit(food)
	else:
		# 安静（含睡觉循环中）：回精力、掉心情
		energy = clampi(energy + ENERGY_REGEN_QUIET, 0, 100)
		mood = clampi(mood - MOOD_DECAY_QUIET, 0, 100)
	_keys_this_tick = 0
	# 开心时光 → 亲密度
	if mood >= HAPPY_MOOD:
		_happy_ticks += 1
		if _happy_ticks >= HAPPY_TICKS_NEED:
			_happy_ticks = 0
			intimacy = clampi(intimacy + 1, 0, 100)
	else:
		_happy_ticks = 0
	# 3 分钟没敲键 → 通知 main 睡觉（已睡/忙碌时 main 会忽略，下个周期会再发）
	if Time.get_ticks_msec() - _last_key_msec >= int(NO_KEY_SLEEPY_SECONDS * 1000.0):
		should_sleep.emit()
	_mark_dirty()

# ---------- 自动动画加权池（main 的定时器到点时来抽） ----------
func pick_auto_anim() -> String:
	var weights := {"sleepy": AUTO_W_SLEEPY}
	if mood >= MOOD_CHEER:
		weights["cheer"] = int(weights.get("cheer", 0)) + AUTO_W_CHEER_MOOD
	if energy >= ENERGY_HIGH:
		weights["cheer"] = int(weights.get("cheer", 0)) + AUTO_W_CHEER_ENERGY
	if mood <= MOOD_LOW:
		weights["cry"] = int(weights.get("cry", 0)) + AUTO_W_CRY
	if energy <= ENERGY_LOW:
		weights["sleepy"] = int(weights["sleepy"]) + AUTO_W_SLEEPY_TIRED
	var total := 0
	for k in weights:
		total += int(weights[k])
	var r := randi() % total
	for k in weights:
		r -= int(weights[k])
		if r < 0:
			return String(k)
	return "sleepy"

# 走路概率倍率（main 用 WALK_CHANCE × 该值）
func walk_multiplier() -> float:
	if energy <= ENERGY_LOW:
		return WALK_MULT_LOW
	if energy >= ENERGY_HIGH:
		return WALK_MULT_HIGH
	return 1.0

# ---------- 每日报告（右键菜单调用，消息条展示） ----------
func report_text() -> String:
	return "今日按键 %d\n累计按键 %d\n陪伴 %d 分钟\n精力 %d  心情 %d  亲密 %d\n食物 %d 个" % [
		keys_today, keys_total, int(companion_seconds_today / 60.0),
		energy, mood, intimacy, food,
	]

# ---------- 存档 ----------
func _mark_dirty() -> void:
	_save_dirty = true
	if _save_timer != null and _save_timer.is_stopped():
		_save_timer.start()

func flush_save() -> void:
	if _save_timer != null:
		_save_timer.stop()
	_save_dirty = false
	var data := {
		"energy": energy,
		"mood": mood,
		"intimacy": intimacy,
		"food": food,
		"food_progress": food_progress,
		"keys_today": keys_today,
		"keys_total": keys_total,
		"companion_seconds_today": companion_seconds_today,
		"today": _today,
		"last_save_unix": int(Time.get_unix_time_from_system()),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败: " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()

func _load() -> void:
	_today = Time.get_date_string_from_system()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	energy = int(data.get("energy", 80))
	mood = int(data.get("mood", 60))
	intimacy = int(data.get("intimacy", 0))
	food = int(data.get("food", 0))
	food_progress = int(data.get("food_progress", 0))
	keys_today = int(data.get("keys_today", 0))
	keys_total = int(data.get("keys_total", 0))
	companion_seconds_today = int(data.get("companion_seconds_today", 0))
	_today = String(data.get("today", ""))
	# 离线不惩罚：超过 1 小时视为"它睡着了"→ 精力回满、心情不动
	var gap: float = Time.get_unix_time_from_system() - float(data.get("last_save_unix", 0))
	if gap > OFFLINE_SLEEP_SECONDS:
		energy = 100

func _rollover_if_new_day() -> void:
	var d := Time.get_date_string_from_system()
	if d != _today:
		_today = d
		keys_today = 0
		companion_seconds_today = 0
