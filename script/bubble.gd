extends Node2D
## 头顶气泡（一期）：字母雨（小写）+ emoji 彩蛋 + 系统反馈消息条，不含任何台词。
## ⚠️ 渲染位置：本节点由 main 放进一个独立的置顶透明小窗（气泡小窗，见 main 的
## _setup_nurture_and_bubble），不画在主窗里——主窗穿透轮廓恒为纯角色，UI 出现消失不会引起闪屏。
## ⚠️ 实现约束：本机透明窗口下 Control 类节点（Label/面板）不渲染，Node2D 渲染正常（角色就是证据），
## 所以这里不用任何 Control，全部在 _draw() 里自绘：文字用 draw_string，面板用渐变圆角多边形。
## 本脚本内的坐标全部是气泡小窗内坐标（锚点由 main 用 ANCHOR_IN_BUBBLE_WIN 设定）。

# ---------- 可调常数 ----------
const LETTER_LIFETIME := 0.9          # 字母存活总时长（秒）
const LETTER_FADE_IN := 0.10          # 字母淡入时长
const LETTER_FADE_OUT := 0.35         # 字母淡出时长
const LETTER_FONT_SIZE := 42
const LETTER_RISE := 28.0             # 存活期间上飘距离
const LETTER_REGION_HALF_W := 110.0   # 字母随机区域：以角色中轴为中心的半宽
const LETTER_REGION_H := 90.0         # 字母随机区域高度
const LETTER_GAP_ABOVE_HEAD := 24.0   # 区域最低点距头顶的间隙
# emoji 彩蛋：打字间隙小概率随字母弹出可爱风 emoji（比字母大、上浮更慢、存活更久）
const EMOJI_CHANCE := 0.08            # 每个字母键的触发概率
const EMOJI_FONT_SIZE := 40
const EMOJI_LIFETIME := 1.6           # 存活总时长（秒）
const EMOJI_FADE_OUT := 0.4
const EMOJI_RISE := 20.0
# 可爱风 emoji 池：表情 + 食物 + 绿色植物（贴合小松绿），用 Windows 自带 Segoe UI Emoji 彩色字体渲染；
# 若某条在游戏里不显示或变黑白，换掉/删掉那条即可
const EMOJI_POOL := [
	"🥺", "🥰", "😊", "😋", "🤤", "🥳", "😭", "😴",
	"🍳", "🍙", "🌸", "🍀", "🌱", "💚", "✨", "🐾",
]
const MSG_FONT_SIZE := 19
const MSG_DEFAULT_HOLD := 2.5         # 消息条默认停留时长（秒）
const MSG_FADE_OUT := 0.25            # 消息条淡出时长（秒）
const MSG_TOP_GAP := 14.0             # 消息条底部距头顶的间隙（紧贴人物）
const MSG_MARGIN_L := 14.0
const MSG_MARGIN_R := 14.0
const MSG_MARGIN_T := 8.0
const MSG_MARGIN_B := 8.0
# ---------- 消息条视觉：渐变圆角面板 + 投影 + 小尾巴 + 进度条（毛玻璃质感用半透明渐变近似） ----------
const MSG_PANEL_RADIUS := 14.0        # 面板圆角半径
const MSG_TAIL_W := 16.0              # 气泡尾巴宽度
const MSG_TAIL_H := 9.0               # 气泡尾巴高度
const MSG_SHADOW_OFFSET := 3.0        # 投影向下偏移
const COL_TEXT := Color(0.26, 0.38, 0.28)            # 正文墨绿灰
const COL_PANEL_TOP := Color(1.0, 1.0, 1.0, 0.94)    # 面板渐变顶（奶白）
const COL_PANEL_BOTTOM := Color(0.90, 0.96, 0.90, 0.90)  # 面板渐变底（薄荷）
const COL_BORDER := Color(0.58, 0.75, 0.58, 0.95)    # 面板描边（淡绿）
const COL_TRACK := Color(0.30, 0.42, 0.32, 0.16)     # 进度条轨道（半透明深绿）
# 进度条
const BAR_ROW_H := 24.0               # 每条进度条的行高
const BAR_LABEL_W := 50.0             # 左侧标签宽
const BAR_TRACK_W := 196.0            # 轨道宽
const BAR_TRACK_H := 12.0
const BAR_FONT_SIZE := 15

var enabled := true

var _cjk_font: SystemFont
var _emoji_font: SystemFont           # emoji 彩色字体（Segoe UI Emoji）
var _anchor := Vector2.ZERO           # 角色头顶中点（气泡小窗内坐标）
var _letters: Array = []              # {ch, pos, rot, age}
var _emojis: Array = []               # emoji 彩蛋 {text, pos, age}
var _msg_queue: Array = []            # {text, hold, bars}
var _msg: Dictionary = {}             # 当前显示的消息 {text, hold, age, bars}
var _msg_bars: Array = []             # 当前消息的进度条数据（show_report 用，普通消息为空）
var _msg_rect := Rect2()              # 当前消息条底板矩形（画板和穿透轮廓共用，取出消息时算好缓存）
var _msg_lines: PackedStringArray = []  # 消息按行拆好的缓存（显示期间不变，避免每帧重新排版）
var _msg_line_h := 0.0
var _msg_ascent := 0.0

func _ready() -> void:
	_cjk_font = SystemFont.new()
	_cjk_font.font_names = ["Microsoft YaHei", "SimHei"]
	_emoji_font = SystemFont.new()
	_emoji_font.font_names = ["Segoe UI Emoji", "Segoe UI Symbol"]   # Windows 自带彩色 emoji 字体

func set_head_anchor(p: Vector2) -> void:
	_anchor = p
	queue_redraw()

# 气泡总开关（右键菜单"气泡开关"）：同时控制字母雨和消息条
func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		_letters.clear()
		_emojis.clear()
		_msg_queue.clear()
		_msg = {}
		_msg_bars = []
		_msg_rect = Rect2()
		_msg_lines = PackedStringArray()
		queue_redraw()

# ---------- 字母雨：main 每收到一个字母/数字键调用一次（main 传小写） ----------
func pop_letter(ch: String) -> void:
	if not enabled or ch.is_empty():
		return
	var x := _anchor.x + randf_range(-LETTER_REGION_HALF_W, LETTER_REGION_HALF_W)
	var y := maxf(_anchor.y - LETTER_GAP_ABOVE_HEAD - randf_range(0.0, LETTER_REGION_H), 12.0)   # 别弹到屏幕顶外
	_letters.append({
		"ch": ch,
		"pos": Vector2(x, y),
		"rot": randf_range(-0.15, 0.15),
		"age": 0.0,
	})
	# emoji 彩蛋：打字间隙小概率冒一个
	if randf() < EMOJI_CHANCE:
		_pop_emoji()
	queue_redraw()

# 随机弹一个 emoji（pop_letter 里小概率触发；比字母大、上浮慢、存活久）
func _pop_emoji() -> void:
	var text: String = EMOJI_POOL[randi() % EMOJI_POOL.size()]
	var est_w := text.length() * EMOJI_FONT_SIZE * 1.0   # emoji 约占一个字宽，够把起点钳在屏幕内
	var x := _anchor.x + randf_range(-LETTER_REGION_HALF_W, LETTER_REGION_HALF_W)
	var y := maxf(_anchor.y - LETTER_GAP_ABOVE_HEAD - randf_range(0.0, LETTER_REGION_H), 12.0)
	var vp := get_viewport_rect().size
	x = clampf(x, 12.0, maxf(12.0, vp.x - est_w - 12.0))
	_emojis.append({"text": text, "pos": Vector2(x, y), "age": 0.0})
	queue_redraw()

# ---------- 系统反馈消息条（队列显示；渐变圆角面板+尾巴+投影，聊天/系统消息都走它） ----------
func say(text: String, hold: float = MSG_DEFAULT_HOLD) -> void:
	if not enabled or text.is_empty():
		return
	_msg_queue.append({"text": text, "hold": hold, "bars": []})

# 每日报告：两行文本 + 精力/心情/亲密/下一餐进度条。只读数值做展示，不改养成逻辑
func show_report(d: Dictionary) -> void:
	if not enabled:
		return
	var text := "今日按键 %d（累计 %d）\n陪伴 %d 分钟 · 食物库存 %d 个" % [
		int(d.get("keys_today", 0)), int(d.get("keys_total", 0)),
		int(d.get("minutes", 0)), int(d.get("food", 0)),
	]
	var bars := [
		{"label": "精力", "frac": float(d.get("energy", 0)) / 100.0, "text": "%d" % int(d.get("energy", 0)),
			"c": Color(0.52, 0.78, 0.50)},
		{"label": "心情", "frac": float(d.get("mood", 0)) / 100.0, "text": "%d" % int(d.get("mood", 0)),
			"c": Color(0.96, 0.64, 0.74)},
		{"label": "亲密", "frac": float(d.get("intimacy", 0)) / 100.0, "text": "%d" % int(d.get("intimacy", 0)),
			"c": Color(0.95, 0.58, 0.50)},
		{"label": "下一餐", "frac": float(d.get("food_progress", 0)) / maxf(float(d.get("food_need", 1)), 1.0),
			"text": "%d/%d" % [int(d.get("food_progress", 0)), int(d.get("food_need", 1))],
			"c": Color(0.97, 0.80, 0.45)},
	]
	_msg_queue.append({"text": text, "hold": 8.0, "bars": bars})

func _process(delta: float) -> void:
	var dirty := false
	# 字母雨计时，到寿命令删除（倒序原地删，避免每帧新建数组）
	if _letters.size() > 0:
		for i in range(_letters.size() - 1, -1, -1):
			var l: Dictionary = _letters[i]
			l["age"] = float(l["age"]) + delta
			if float(l["age"]) >= LETTER_LIFETIME:
				_letters.remove_at(i)
		dirty = true
	# emoji 计时（同字母雨倒序删）
	if _emojis.size() > 0:
		for i in range(_emojis.size() - 1, -1, -1):
			var f: Dictionary = _emojis[i]
			f["age"] = float(f["age"]) + delta
			if float(f["age"]) >= EMOJI_LIFETIME:
				_emojis.remove_at(i)
		dirty = true
	# 消息条：空闲时取下一条（文本布局只在取出那一刻算一次并缓存）
	if _msg.is_empty() and not _msg_queue.is_empty():
		var item: Dictionary = _msg_queue.pop_front()
		_msg = {"text": item["text"], "hold": float(item["hold"]), "age": 0.0, "bars": item["bars"]}
		_cache_msg_layout()
		dirty = true
	if not _msg.is_empty():
		_msg["age"] = float(_msg["age"]) + delta
		if float(_msg["age"]) >= float(_msg["hold"]) + MSG_FADE_OUT:
			_msg = {}
			_msg_bars = []
			_msg_rect = Rect2()
			_msg_lines = PackedStringArray()
		dirty = true
	if dirty:
		queue_redraw()

# 消息显示期间不变的布局（拆行/行高/文本宽/底板矩形/进度条）只在取出消息时算一次并缓存
func _cache_msg_layout() -> void:
	_msg_lines = String(_msg["text"]).split("\n")
	_msg_bars = _msg["bars"]
	_msg_line_h = _cjk_font.get_height(MSG_FONT_SIZE)
	_msg_ascent = _cjk_font.get_ascent(MSG_FONT_SIZE)
	var text_w := 0.0
	for ln in _msg_lines:
		text_w = maxf(text_w, _cjk_font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, MSG_FONT_SIZE).x)
	# 面板内宽 = 文本与进度条行的较宽者（标签+轨道+右侧数值）
	var inner_w := maxf(text_w, BAR_LABEL_W + BAR_TRACK_W + 56.0)
	var inner_h := _msg_line_h * float(_msg_lines.size()) + BAR_ROW_H * float(_msg_bars.size())
	var box_w := inner_w + MSG_MARGIN_L + MSG_MARGIN_R
	var box_h := inner_h + MSG_MARGIN_T + MSG_MARGIN_B
	var pos := _anchor + Vector2(-box_w / 2.0, -box_h - MSG_TOP_GAP)
	# 角色被拖到屏幕边缘时把消息条钳回屏幕内，别整个跑到屏幕外"失效"
	var vp := get_viewport_rect().size
	pos.y = maxf(pos.y, 8.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - box_w - 8.0))
	_msg_rect = Rect2(pos, Vector2(box_w, box_h))

func _draw() -> void:
	# 字母雨：按存活时间淡入淡出 + 缓慢上飘，每个字母带一点随机旋转
	for l in _letters:
		var age: float = float(l["age"])
		var a := 1.0
		if age < LETTER_FADE_IN:
			a = age / LETTER_FADE_IN
		elif age > LETTER_LIFETIME - LETTER_FADE_OUT:
			a = (LETTER_LIFETIME - age) / LETTER_FADE_OUT
		a = clampf(a, 0.0, 1.0)
		var rise := LETTER_RISE * clampf(age / LETTER_LIFETIME, 0.0, 1.0)
		draw_set_transform(Vector2(l["pos"]) + Vector2(0.0, -rise), float(l["rot"]), Vector2.ONE)
		draw_string_outline(_cjk_font, Vector2.ZERO, l["ch"], HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT_SIZE, 8, Color(0.30, 0.52, 0.34, 0.9 * a))
		draw_string(_cjk_font, Vector2.ZERO, l["ch"], HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT_SIZE, Color(1, 1, 1, 0.95 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # 还原变换，别影响后面的绘制
	# emoji 彩蛋：Segoe UI Emoji 彩色字形，不加描边（描边会破坏彩色位图），只做透明度渐隐
	for f in _emojis:
		var f_age: float = float(f["age"])
		var fa := 1.0
		if f_age < LETTER_FADE_IN:
			fa = f_age / LETTER_FADE_IN
		elif f_age > EMOJI_LIFETIME - EMOJI_FADE_OUT:
			fa = (EMOJI_LIFETIME - f_age) / EMOJI_FADE_OUT
		fa = clampf(fa, 0.0, 1.0)
		var f_rise := EMOJI_RISE * clampf(f_age / EMOJI_LIFETIME, 0.0, 1.0)
		var f_pos: Vector2 = Vector2(f["pos"]) + Vector2(0.0, -f_rise)
		draw_string(_emoji_font, f_pos, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, EMOJI_FONT_SIZE, Color(1, 1, 1, fa))
	# 消息条：渐变圆角面板 + 投影 + 小尾巴 + 进度条；入场轻微下滑淡入，尾段淡出
	# （"毛玻璃"用半透明渐变 + 顶部高光 + 投影近似；Godot 拿不到桌面画面做不了真模糊）
	if _msg.is_empty():
		return
	var box := _msg_rect
	var alpha := 1.0
	var tail_t := float(_msg["age"]) - float(_msg["hold"])
	if tail_t > 0.0:
		alpha = clampf(1.0 - tail_t / MSG_FADE_OUT, 0.0, 1.0)
	var t_in := clampf(float(_msg["age"]) / 0.18, 0.0, 1.0)
	alpha = minf(alpha, t_in)
	box.position.y += (1.0 - t_in) * -8.0
	# 投影（比面板大一点偏下，暖绿灰半透明）
	_draw_rounded_rect(Rect2(box.position + Vector2(1.0, MSG_SHADOW_OFFSET), box.size), MSG_PANEL_RADIUS, Color(0.20, 0.30, 0.22, 0.10), Color(0.20, 0.30, 0.22, 0.13), alpha)
	# 面板（奶白→薄荷垂直渐变）+ 描边
	_draw_rounded_rect(box, MSG_PANEL_RADIUS, COL_PANEL_TOP, COL_PANEL_BOTTOM, alpha)
	var border := _rounded_rect_points(box, MSG_PANEL_RADIUS)
	border.append(border[0])
	draw_polyline(border, Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, COL_BORDER.a * alpha), 1.5, true)
	# 小尾巴（面板底色三角，指向角色头顶）
	var tail_x := box.position.x + box.size.x * 0.5
	var tail_tri := PackedVector2Array([
		Vector2(tail_x - MSG_TAIL_W * 0.5, box.end.y - 1.0),
		Vector2(tail_x + MSG_TAIL_W * 0.5, box.end.y - 1.0),
		Vector2(tail_x + 2.0, box.end.y + MSG_TAIL_H),
	])
	draw_colored_polygon(tail_tri, Color(COL_PANEL_BOTTOM.r, COL_PANEL_BOTTOM.g, COL_PANEL_BOTTOM.b, COL_PANEL_BOTTOM.a * alpha))
	# 顶部高光（玻璃感的一笔）
	draw_line(Vector2(box.position.x + 10.0, box.position.y + 1.5), Vector2(box.position.x + box.size.x - 10.0, box.position.y + 1.5), Color(1, 1, 1, 0.6 * alpha), 1.5)
	# 文本行
	var ty := box.position.y + MSG_MARGIN_T + _msg_ascent
	for i in _msg_lines.size():
		draw_string(_cjk_font, Vector2(box.position.x + MSG_MARGIN_L, ty + _msg_line_h * i), _msg_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, MSG_FONT_SIZE, Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, alpha))
	# 进度条行
	var by := box.position.y + MSG_MARGIN_T + _msg_line_h * _msg_lines.size()
	for b in _msg_bars:
		_draw_bar(Vector2(box.position.x + MSG_MARGIN_L, by), b, alpha)
		by += BAR_ROW_H

# ---------- 消息条绘制辅助 ----------
# 圆角矩形顶点（4 段圆弧各 6 分割，顺时针闭合多边形）
func _rounded_rect_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var seg := 6
	var centers := [
		Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.position.y + rad),
	]
	var starts := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for i in 4:
		var c0: Vector2 = centers[i]
		for s in seg + 1:
			var ang: float = starts[i] + (PI / 2.0) * (float(s) / float(seg))
			pts.append(c0 + Vector2(cos(ang), sin(ang)) * rad)
	return pts

# 圆角矩形填充：c_a→c_b 沿垂直（默认）或水平方向逐顶点渐变，alpha 统一乘
func _draw_rounded_rect(r: Rect2, rad: float, c_a: Color, c_b: Color, alpha: float = 1.0, horizontal: bool = false) -> void:
	var pts := _rounded_rect_points(r, rad)
	var cols := PackedColorArray()
	for p in pts:
		var t := 0.0
		if horizontal:
			t = clampf((p.x - r.position.x) / maxf(r.size.x, 0.001), 0.0, 1.0)
		else:
			t = clampf((p.y - r.position.y) / maxf(r.size.y, 0.001), 0.0, 1.0)
		var c := c_a.lerp(c_b, t)
		c.a *= alpha
		cols.append(c)
	draw_polygon(pts, cols)

# 单条进度条：左标签 + 圆角轨道 + 水平渐变填充 + 右侧数值
func _draw_bar(pos: Vector2, b: Dictionary, alpha: float) -> void:
	var frac := clampf(float(b["frac"]), 0.0, 1.0)
	var col: Color = b["c"]
	var label_col := Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, alpha)
	draw_string(_cjk_font, pos + Vector2(0.0, 14.0), String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, BAR_FONT_SIZE, label_col)
	var track_pos := pos + Vector2(BAR_LABEL_W, 3.5)
	var track_col := Color(COL_TRACK.r, COL_TRACK.g, COL_TRACK.b, COL_TRACK.a * alpha)
	_draw_rounded_rect(Rect2(track_pos, Vector2(BAR_TRACK_W, BAR_TRACK_H)), 6.0, track_col, track_col)
	if frac > 0.01:
		var fill_w := clampf(BAR_TRACK_W * frac, BAR_TRACK_H, BAR_TRACK_W)
		var base := Color(col.r, col.g, col.b, 0.95 * alpha)
		_draw_rounded_rect(Rect2(track_pos, Vector2(fill_w, BAR_TRACK_H)), 6.0, base.darkened(0.10), base.lightened(0.18), 1.0, true)
	draw_string(_cjk_font, track_pos + Vector2(BAR_TRACK_W + 8.0, 13.0), String(b["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, BAR_FONT_SIZE, label_col)
