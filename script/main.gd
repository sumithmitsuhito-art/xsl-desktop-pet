extends Node2D

# 待机静态图（从 assets/animations/idle 目录加载，两张透明静态图）。运行时动态补建成名叫 idle 的动画
const IDLE_TEX_PATHS := [
	"res://assets/animations/idle/idle_1.png",
	"res://assets/animations/idle/idle_2.png",
]
# 待机/走路共用的触发定时器：间隔基准（秒）+ 上下随机浮动
const IDLE_SWITCH_SECONDS := 10.0
const IDLE_SWITCH_JITTER := 5.0
# 到点时的行为概率：WALK 走路 / EMOTION 随机小情绪，剩余概率 = 待机切帧（三者和为 1）
const WALK_CHANCE := 0.35
const EMOTION_CHANCE := 0.3
# 走路时窗口每次平移的距离（像素）+ 走一步耗时（秒）
const WALK_DISTANCE := 200.0
const WALK_STEP_TIME := 0.9
# 角色显示目标宽度（像素）
const TARGET_WIDTH := 300.0
# 松开时鼠标位移小于该值视为“点击”，否则视为“拖动”（像素）
const CLICK_THRESHOLD := 5.0
# 单击切换动画的冷却：冷却内点击不切动画也不计数值（防连点狂切动画）
const CLICK_ANIM_COOLDOWN := 2.0
# 回车=cheer、退格=scary，两者共用冷却（秒）；键码用 Windows 虚拟键码
const VK_ENTER := 0x0D
const VK_BACKSPACE := 0x08
const SPECIAL_KEY_ANIM_COOLDOWN := 10.0
# ---------- 喂食模式（食物贴图贴鼠标跟随，桌宠平移窗口靠近，点击角色完成投喂） ----------
# 气泡小窗：字母雨/emoji/消息条都画在这个独立置顶小窗里（主窗轮廓完全不参与，见坑21）
const BUBBLE_WIN_SIZE := Vector2i(440, 360)      # 气泡小窗尺寸
const ANCHOR_IN_BUBBLE_WIN := Vector2(220, 290)  # 头顶锚点在气泡小窗内的位置
const FOOD_TEX_PATH := "res://assets/food/food.png"   # 荷包蛋贴图放这里；没放就用代码画的占位煎蛋
const FOOD_WIN_SIZE := 160                # 食物独立小窗的边长（正方形，蛋画在中间）
const FOOD_HEIGHT := 70.0                  # 食物显示高度（像素，等比缩放）
const FOOD_OFFSET := Vector2(8.0, -30.0)   # 食物中心相对鼠标的偏移（略上浮，不被鼠标箭头挡住）
const FOOD_BOB_AMP := 3.0                  # 食物上下浮动幅度（像素）
const FOOD_BOB_FREQ := 4.0                 # 食物浮动频率
const FEED_APPROACH_SPEED := 300.0         # 桌宠靠近鼠标的速度（窗口平移，像素/秒）
const FEED_ARRIVE_DIST := 60.0             # 角色中心距鼠标该距离内算"到位"（像素）
# 一期脚本：气泡是 Node2D 自绘（本机透明窗口只有 Node2D 能渲染）；菜单用 PopupMenu 弹窗（实测可渲染）
const NurtureScript := preload("res://script/nurture.gd")
const BubbleScript := preload("res://script/bubble.gd")
# 每个按键都打印到输出面板（验证键盘钩子用；高频打字时控制台 IO 会拖性能，平时保持 false）
const DEBUG_PRINT_KEYS := false
# 喂食全流程详细调试打印（[feed] 前缀；验收通过后改 false 静音）
const DEBUG_FEED := true

# 单击角色时的情绪动画权重（shy 最常见 → scary 最少见）
const CLICK_ANIM_WEIGHTS := {"shy": 4, "cheer": 3, "cry": 2, "scary": 1}
# 右键菜单项 ID
const MENU_ID_FEED := 100
const MENU_ID_REPORT := 101
const MENU_ID_BUBBLE := 102
const MENU_ID_QUIT := 103

@onready var sprite: AnimatedSprite2D = get_node("Character")

# 待机静态切换状态
var _idle_frame := 0          # 当前待机显示的是 idle 的第几帧（0/1）
var _switch_timer: Timer

# 走路状态：正在走的方向（-1 左 / +1 右），0 表示没在走
var _walking := 0
var _walk_tween: Tween     # 走路的窗口平移动画；走路被打断时必须杀掉，否则残留 tween 会继续拉窗口
# 当前被临时设为循环播放的动画名（用于拖动/走路，停止时要还原成单次）
var _looping_anim := ""
# 穿透轮廓缓存：键=动画名（如 "cheer"/"idle"），值=已换算成窗口坐标的穿透点数组。
# 同动画重复播放时直接复用，避免每次重扫几万像素+算凸包（实测单次约 50ms）
var _polygon_cache := {}

# 拖动状态：按下时记录“鼠标屏幕坐标 + 窗口位置”，拖动中 窗口位置 = 起点 + 鼠标位移
var _dragging := false
var _drag_mouse_pos := Vector2i.ZERO
var _drag_window_pos := Vector2i.ZERO
# 是否已开始拖动并播放过 lifted（点击不播，只有真正拖动才播）
var _lifted_started := false

# 一期新增：养成数值 / 头顶气泡 / 右键菜单 / 睡觉态（全部运行时创建，场景保持三节点不动）
var nurture               # nurture.gd 实例（纯逻辑节点，不涉及渲染）
var bubble                # bubble.gd 实例（Node2D 自绘气泡）
var _menu: PopupMenu
var _sleeping := false    # sleepy 循环播放中（=睡觉态），敲键/单击/拖动/右键唤醒
# 喂食模式状态：_feeding=模式开启（输入接管；食物画在独立置顶小窗里，主窗穿透轮廓不受影响）；
# _feed_closing=食物滑入嘴里的收尾段；_chewing=咀嚼压扁动画进行中。后两者会短暂屏蔽定时器/点击等触发
var _feeding := false
var _feed_closing := false
var _chewing := false
var _food_win: Window         # 食物独立小窗（置顶、透明、整窗点击穿透；喂食期间只挪它的位置）
var _food_sprite: Sprite2D    # 小窗里的荷包蛋贴图
var _food_bob_t := 0.0        # 食物浮动计时
var _feed_dbg_t := 0.0        # 喂食调试打印节流计时（0.5 秒一条状态，避免每帧刷屏）
var _feed_walk_dir := 0       # 喂食靠近时的朝向（-1 左 / 1 右 / 0 停）
var _click_anim_last_msec := -1000000     # 单击切动画冷却
var _special_key_last_msec := -1000000    # 回车/退格动画共用冷却
# UI 显示期间的穿透辅助：mouse_passthrough_polygon 轮廓外的像素会被整块裁掉不渲染，
# 所以气泡/菜单显示时必须把它们的区域并进轮廓（和角色动画换轮廓同一套逻辑）
var _base_polygon := PackedVector2Array()   # 最近一次的"角色本体"轮廓（主窗轮廓=纯角色，恒定内容）
var _last_win_pos := Vector2i(-2147483648, -2147483648)   # 上次窗口位置（哨兵值，保证首帧刷一次）
# 气泡小窗：字母雨/emoji/消息条的独立渲染窗口（置顶+整窗穿透），跟随主窗平移
var _bubble_win: Window
var _bubble_win_offset := Vector2i.ZERO     # 气泡小窗相对主窗的固定偏移（由头顶锚点算出，恒定）

func _ready() -> void:
	_build_idle_animation()
	_build_walk_right_animation()
	# 先切到待机动作并静态显示（不播放）
	sprite.animation = "idle"
	sprite.stop()
	sprite.animation_finished.connect(_on_animation_finished)   # 非待机动画播完回到待机
	_setup_window()
	_center_and_scale()
	_apply_click_polygon()
	_setup_switch_timer()
	_connect_keyboard_hook()
	_setup_nurture_and_bubble()
	_setup_menu()

# 连接 C# 全局键盘钩子（GlobalKeyboardHook 节点）的 KeyPressed 信号，收到按键打印到控制台做验证
func _connect_keyboard_hook() -> void:
	var hook := get_node_or_null("GlobalKeyboardHook")
	if hook == null:
		push_warning("场景里找不到 GlobalKeyboardHook 节点，跳过键盘监听")
		return
	hook.connect("KeyPressed", _on_global_key)
	print("[key] 已连接全局键盘监听")

# 回调：收到全局按键（keyCode=虚拟键码，isDown=true按下/false抬起）
func _on_global_key(keyCode: int, isDown: bool) -> void:
	if not isDown:
		return
	if _sleeping:
		_wake()   # 敲键唤醒
	nurture.on_key_down(keyCode)
	var key_label: String = _key_name(keyCode)
	if key_label.length() == 1:
		bubble.pop_letter(key_label.to_lower())   # 字母雨回显小写字母/数字
	# 回车=cheer、退格=scary（共用 10 秒冷却；喂食/拖动/走路/有动作在播时不播，睡觉在函数开头已先唤醒）
	if keyCode == VK_ENTER or keyCode == VK_BACKSPACE:
		var now := Time.get_ticks_msec()
		if (now - _special_key_last_msec >= int(SPECIAL_KEY_ANIM_COOLDOWN * 1000.0)
				and not _feeding and not _chewing and not _dragging and _walking == 0
				and not sprite.is_playing()):
			_special_key_last_msec = now
			_play_action("cheer" if keyCode == VK_ENTER else "scary")
	if DEBUG_PRINT_KEYS:
		print("[key] ", key_label)   # 每键一条控制台输出开销不小，验证钩子时再开

# 把虚拟键码转成可读按键名（简化版，覆盖常用键）
func _key_name(vk: int) -> String:
	# 字母 A-Z
	if vk >= 0x41 and vk <= 0x5A:
		return char(vk)
	# 数字 0-9
	if vk >= 0x30 and vk <= 0x39:
		return char(vk)
	match vk:
		0x08: return "Backspace"
		0x09: return "Tab"
		0x0D: return "Enter"
		0x1B: return "Esc"
		0x20: return "Space"
		0x2E: return "Delete"
		0x25: return "Left"
		0x26: return "Up"
		0x27: return "Right"
		0x28: return "Down"
		0x11: return "Ctrl"
		0x10: return "Shift"
		0x12: return "Alt"
		0x70: return "F1"
		0x71: return "F2"
		0x72: return "F3"
		0x73: return "F4"
		0x74: return "F5"
		0x75: return "F6"
		0x76: return "F7"
		0x77: return "F8"
		0x78: return "F9"
		0x79: return "F10"
		0x7A: return "F11"
		0x7B: return "F12"
	return "0x" + str(vk)

# 运行时用 idle_1/idle_2 两张静态图动态建一个叫 idle 的动画
func _build_idle_animation() -> void:
	var sf := sprite.sprite_frames
	if not sf.has_animation("idle"):
		sf.add_animation("idle")
	for i in IDLE_TEX_PATHS.size():
		var tex: Texture2D = load(IDLE_TEX_PATHS[i])
		if tex != null:
			sf.add_frame("idle", tex)

# 镜像 walk 生成一份朝右走的动画 walk_r（水平翻转 walk 的每一帧）
func _build_walk_right_animation() -> void:
	var sf := sprite.sprite_frames
	if not sf.has_animation("walk_r"):
		sf.add_animation("walk_r")
	# walk 朝左，镜像后变朝右。循环以保持 walking 期间连续迈步
	var count := sf.get_frame_count("walk")
	for i in count:
		var tex: Texture2D = sf.get_frame_texture("walk", i)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.flip_x()   # 水平翻转（原地翻转，不改变画布尺寸 372x360）
		sf.add_frame("walk_r", ImageTexture.create_from_image(img))

# ---------- 待机/走路/随机情绪共用的定时切换 ----------
func _setup_switch_timer() -> void:
	_switch_timer = Timer.new()
	_switch_timer.wait_time = _next_switch_delay()
	_switch_timer.autostart = true
	_switch_timer.timeout.connect(_on_switch_timeout)
	add_child(_switch_timer)

func _next_switch_delay() -> float:
	return IDLE_SWITCH_SECONDS + randf_range(-IDLE_SWITCH_JITTER, IDLE_SWITCH_JITTER)

# 到点：空闲待机时按权重随机分到 走路 / 随机小情绪 / 待机切帧 三者之一；非空闲则只重设下次间隔
func _on_switch_timeout() -> void:
	if not _feeding and not _chewing and not _dragging and sprite.animation == "idle" and not sprite.is_playing():
		var r := randf()
		var walk_chance: float = WALK_CHANCE * nurture.walk_multiplier()
		if r < walk_chance:
			# 走路：随机方向（精力充足更爱走，精力不足几乎不走）
			var dir := -1 if randf() < 0.5 else 1
			_start_walk(dir)
		elif r < walk_chance + EMOTION_CHANCE:
			# 情绪动画从养成数值加权池里抽（sleepy/cheer/cry，见 nurture.gd）
			var anim: String = nurture.pick_auto_anim()
			_play_action(anim)
		else:
			# 待机静态切帧
			_idle_frame = 1 - _idle_frame   # 当前0切到1，当前1切到0
			sprite.frame = _idle_frame
			_apply_click_polygon()   # 待机图变了，alpha 轮廓也要跟着重算
	# 无论是否切换，都重新随机下一次间隔
	_switch_timer.wait_time = _next_switch_delay()

# 开始走路：朝 dir 方向走，窗口平移最多 WALK_DISTANCE 像素，结束后回待机。
# ⚠️ 钳制必须锚定"角色屏幕位置"，不能锚定窗口位置：窗口会被拖动/喂食挪到屏幕外很远，
# 用窗口位置钳制会让目标点翻到另一侧 → 朝左动画+向右滑行（"倒着走"bug：角色在屏幕
# 左侧区域 + 掷出向左走时触发，小概率难复现的就是它）
func _start_walk(dir: int) -> void:
	_walking = dir
	var anim: String = "walk" if dir < 0 else "walk_r"
	_play_looping(anim)
	var win := get_window()
	var sx: int = DisplayServer.screen_get_position().x
	var sw: int = DisplayServer.screen_get_size().x
	var margin := TARGET_WIDTH / 2.0   # 角色半宽：保证角色整个留在屏幕内
	var char_now := float(win.position.x) + sprite.position.x
	var char_target := clampf(char_now + dir * WALK_DISTANCE, sx + margin, sx + sw - margin)
	var step_x := int(round(char_target - char_now))
	_walk_tween = create_tween()
	_walk_tween.tween_property(win, "position", win.position + Vector2i(step_x, 0), WALK_STEP_TIME)
	# 走路结束回待机。若中途被喂食等打断（_walking 已被清零/抢占）则放弃收尾，交给打断者处理
	await get_tree().create_timer(WALK_STEP_TIME).timeout
	if _walking != dir:
		return
	_walking = 0
	_stop_to_idle()

# ---------- 播放动作动画 ----------
# 播放某个动作（单次，播完 animation_finished 回待机）。动画期间用“该动作所有帧 alpha 并集轮廓”当穿透。
func _play_action(anim: String) -> void:
	if not sprite.sprite_frames.has_animation(anim):
		push_warning("没有动画: " + anim)
		return
	sprite.play(anim)
	_apply_action_union_polygon(anim)

# 循环播放某个动作（用于拖动被拎起来、走路）：强制把该动画设为 loop=true 再播放，播多久都不会停
func _play_looping(anim: String) -> void:
	if not sprite.sprite_frames.has_animation(anim):
		push_warning("没有动画: " + anim)
		return
	# 换动画时把上一个循环动画还原成单次（喂食靠近切朝向 walk↔walk_r 时旧动画会残留 loop=true）
	if _looping_anim != "" and _looping_anim != anim:
		sprite.sprite_frames.set_animation_loop(_looping_anim, false)
	sprite.sprite_frames.set_animation_loop(anim, true)   # 临时强制循环
	_looping_anim = anim
	sprite.play(anim)   # 不传 from_frame，避免播放器停在开始不推进
	_apply_action_union_polygon(anim)

# 停掉当前循环动画并回到待机静态；把临时改过 loop 的动画恢复成单次（loop=false）
func _stop_to_idle() -> void:
	# 走路被打断时杀掉残留的窗口平移 tween，防止它继续按旧目标拉窗口（和当前移动方向打架）
	if _walk_tween != null and _walk_tween.is_valid():
		_walk_tween.kill()
		_walk_tween = null
	if _looping_anim != "":
		sprite.sprite_frames.set_animation_loop(_looping_anim, false)
		_looping_anim = ""
	sprite.stop()
	sprite.animation = "idle"
	sprite.frame = _idle_frame
	_apply_click_polygon()

# 播放某动作时应用穿透：优先用缓存（同动画重复播不再重算），未命中才计算并缓存。
func _apply_action_union_polygon(anim: String) -> void:
	if _polygon_cache.has(anim):
		_apply_passthrough(_polygon_cache[anim])
		return
	var points := _compute_union_polygon_points(anim)
	if points.is_empty():
		return
	_polygon_cache[anim] = points
	_apply_passthrough(points)

# 遍历该动作所有帧，把各自非透明的像素合并成并集 mask，求凸包并换算成窗口坐标的穿透点。
# 动作可能有分离的身体部分（举手/扬角），凸包保证一个多边形且覆盖全部，不会缺角。
func _compute_union_polygon_points(anim: String) -> PackedVector2Array:
	var sf := sprite.sprite_frames
	var frame_count := sf.get_frame_count(anim)
	if frame_count == 0:
		return PackedVector2Array()
	var tex0: Texture2D = sf.get_frame_texture(anim, 0)
	if tex0 == null:
		return PackedVector2Array()
	var tex_size := tex0.get_size()

	# 1) 用最大 alpha 合并出“并集 mask”：区域里任一帧不透明则该点算作角色
	var mask := BitMap.new()
	mask.create(Vector2i(tex_size))
	for f in frame_count:
		var tex: Texture2D = sf.get_frame_texture(anim, f)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		var bmp := BitMap.new()
		bmp.create_from_image_alpha(img, 0.1)
		# 把该帧不透明点叠到并集 mask
		var w: int = tex_size.x
		var h: int = tex_size.y
		for y in h:
			for x in w:
				if bmp.get_bit(x, y):
					mask.set_bit(x, y, true)

	# 2) 收集并集 mask 里所有不透明像素坐标，算凸包作为单一穿透轮廓
	var pts := PackedVector2Array()
	for y in int(tex_size.y):
		for x in int(tex_size.x):
			if mask.get_bit(x, y):
				pts.append(Vector2(x, y))
	if pts.is_empty():
		push_error("动作没有不透明区域，穿透未生效")
		return PackedVector2Array()
	var hull := _convex_hull(pts)
	# 3) 换算成窗口坐标（角色固定在窗口中心，position/scale 不变）
	var points := PackedVector2Array()
	for p in hull:
		points.append(sprite.position + (p - tex_size / 2.0) * sprite.scale.x)
	return points

# 用单调链（Andrew）求点集的凸包，返回逆时针的凸多边形顶点（简化版，只保留角点）
func _convex_hull(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	# 排序：先 x 后 y（GDScript 的 sort_custom 按自定义规则）
	var arr := pts.duplicate()
	arr.sort()
	var lower := PackedVector2Array()
	for p in arr:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], p) <= 0:
			lower.remove_at(lower.size() - 1)
		lower.append(p)
	var upper := PackedVector2Array()
	for i in range(arr.size() - 1, -1, -1):
		var p := arr[i]
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], p) <= 0:
			upper.remove_at(upper.size() - 1)
		upper.append(p)
	lower.remove_at(lower.size() - 1)
	upper.remove_at(upper.size() - 1)
	lower.append_array(upper)
	return lower

# 叉积：判断三点方向（>0 逆时针，<0 顺时针，=0 共线）
func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)

# 窗口位置监视：穿透轮廓只在设置那一刻的位置生效，窗口挪走后必须重贴一遍，
# 否则 UI 的"框"会留在原地不跟角色走（拖动/自动走路都靠这里兜底）
func _process(delta: float) -> void:
	# 气泡小窗跟随主窗（偏移恒定；拖动/走路/喂食引起的窗口移动都靠这里同步）
	if _bubble_win != null:
		_bubble_win.position = get_window().position + _bubble_win_offset
	if _feeding:
		_feed_tick(delta)
		# 喂食中窗口在平移：穿透轮廓内容不变但仍需重贴（轮廓不跟窗口自动走，见坑21；
		# 内容恒定的重贴与拖动/走路时同类，不会触发可见重绘）。食物在小窗渲染，与主窗轮廓无关
		_refresh_passthrough()
		return
	var wp := get_window().position
	if wp != _last_win_pos:
		_last_win_pos = wp
		if _base_polygon.size() > 0:
			_refresh_passthrough()

# 所有穿透设置的统一入口：记下角色本体轮廓并立即重贴（UI 不在此列，见 _refresh_passthrough）
func _apply_passthrough(points: PackedVector2Array) -> void:
	_base_polygon = points
	_refresh_passthrough()

# 主窗穿透轮廓 = 纯角色本体，内容恒定（拖动/走路/喂食都只是重贴同样内容，不会闪）。
# ⚠️ 任何 UI 都不要再并进这个轮廓：字母雨/emoji/消息条在气泡小窗渲染，菜单是原生弹窗——
# 轮廓动态扩缩会白条+闪、清空会全屏闪，血泪史见坑21
func _refresh_passthrough() -> void:
	if _base_polygon.is_empty():
		return
	get_window().mouse_passthrough_polygon = _base_polygon

# 动画播完（单次动作 loop=false 会触发）；拖动/走路的动画已临时强制循环，不会走到这
func _on_animation_finished() -> void:
	# 出于防御：若此刻仍在拖/走（理论上不该发生），就继续循环对应动画
	if _dragging:
		_play_looping("lifted")
		return
	if _walking != 0:
		_play_looping("walk" if _walking < 0 else "walk_r")
		return
	# 单次动作播完：回到待机静态
	sprite.animation = "idle"
	sprite.frame = _idle_frame
	sprite.stop()
	_apply_click_polygon()

# ---------- 窗口 / 缩放 / 穿透 ----------
func _setup_window() -> void:
	var win := get_window()
	win.size = DisplayServer.screen_get_size() - Vector2i(1, 1)
	win.position = DisplayServer.screen_get_position()

func _center_and_scale() -> void:
	# 用 idle 第 0 帧的尺寸来算缩放（各帧尺寸一致：372x360）
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture("idle", 0)
	var image_size := tex.get_size()
	sprite.scale = Vector2.ONE * (TARGET_WIDTH / image_size.x)
	sprite.position = get_viewport_rect().size / 2.0

# 鼠标穿透：取当前显示帧的纹理做单帧轮廓。优先用缓存（同一帧重复用不再重算），未命中才算并缓存。
func _apply_click_polygon() -> void:
	var key := "%s#%d" % [sprite.animation, sprite.frame]
	if _polygon_cache.has(key):
		_apply_passthrough(_polygon_cache[key])
		return
	var points := _compute_frame_points(sprite.animation, sprite.frame)
	if points.is_empty():
		return
	_polygon_cache[key] = points
	_apply_passthrough(points)

# 对某个动画的第 frame 帧求凸包并换算成窗口坐标的穿透点（覆盖任何分离部分，不至于缺角）
func _compute_frame_points(anim: String, frame: int) -> PackedVector2Array:
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(anim, frame)
	if tex == null:
		return PackedVector2Array()
	var image: Image = tex.get_image()
	if image.is_compressed():
		image.decompress()
	var bmp := BitMap.new()
	bmp.create_from_image_alpha(image, 0.1)
	var tex_size := image.get_size()
	var pts := PackedVector2Array()
	for y in int(tex_size.y):
		for x in int(tex_size.x):
			if bmp.get_bit(x, y):
				pts.append(Vector2(x, y))
	if pts.is_empty():
		return PackedVector2Array()
	var hull := _convex_hull(pts)
	var points := PackedVector2Array()
	for p in hull:
		points.append(sprite.position + (p - tex_size / 2.0) * sprite.scale.x)
	return points

# ---------- 输入 ----------
func _input(event: InputEvent) -> void:
	# 喂食模式输入接管：右键=取消；左键按下点中角色=喂、点空白=取消（按下即判定，喂食中无拖动）
	if _feeding and event is InputEventMouseButton:
		if _feed_closing:
			return   # 食物飞入嘴里的收尾段，输入忽略
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if DEBUG_FEED:
				print("[feed] 输入: 右键按下 → 取消")
			_cancel_feeding()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var dist: float = event.position.distance_to(sprite.position)
			if dist <= TARGET_WIDTH / 2.0:
				if DEBUG_FEED:
					print("[feed] 输入: 左键命中角色 (距中心 %.0fpx)" % dist)
				_complete_feed()
			else:
				if DEBUG_FEED:
					print("[feed] 输入: 左键未命中角色 (距中心 %.0fpx > %d) → 视为点空白取消" % [dist, int(TARGET_WIDTH / 2.0)])
				_cancel_feeding()
			return
		return
	# 右键点角色 → 弹菜单（投喂/报告/气泡开关/退出；Esc 退出已按一期设计删除）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _sleeping:
			_wake()
		# 菜单锚定角色：固定开在角色右侧偏上，与右键点哪儿无关（位置稳定，框不会漂）
		# 横向 -40 是抵消贴图四周的透明留白，让菜单视觉上贴近角色
		var vp := get_viewport_rect().size
		var menu_pos: Vector2 = sprite.position + Vector2(TARGET_WIDTH / 2.0 - 40.0, -40.0)
		menu_pos.x = clampf(menu_pos.x, 8.0, maxf(8.0, vp.x - 220.0))   # 角色贴边时把菜单钳回屏幕内
		menu_pos.y = clampf(menu_pos.y, 8.0, maxf(8.0, vp.y - 180.0))
		_show_menu(menu_pos)

	# 按在角色身上开始拖，松开结束
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dragging and not _walking:
			if event.position.distance_to(sprite.position) <= TARGET_WIDTH / 2.0:
				if _sleeping:
					_wake()
				_dragging = true
				_lifted_started = false   # 先不播 lifted，等确认是“拖动”才播
				# 两个坐标必须同源（都是屏幕坐标），混用画布坐标会导致抓取瞬间瞬移
				_drag_mouse_pos = DisplayServer.mouse_get_position()
				_drag_window_pos = get_window().position
		elif not event.pressed and _dragging:
			_dragging = false
			_stop_to_idle()
			_lifted_started = false
			# 按下时已记录 _drag_mouse_pos（鼠标屏幕坐标），松手时若位移很小视为点击，否则是拖动
			if DisplayServer.mouse_get_position().distance_to(_drag_mouse_pos) <= CLICK_THRESHOLD:
				_on_click()

	# 拖动 = 平移整个窗口，窗口内内容零重绘（避免重影花边）。
	if event is InputEventMouseMotion and _dragging:
		var mouse_delta := DisplayServer.mouse_get_position() - _drag_mouse_pos
		# 使用属性赋值
		get_window().position = _drag_window_pos + mouse_delta
		# 鼠标真正在移动 = 确实是拖动，此时才循环播“被拎起来”（点击松开时不会闪）
		if not _lifted_started:
			_lifted_started = true
			nurture.on_drag()   # 真拖动才计数值（内部 30 秒冷却）
			_play_looping("lifted")

func _on_click() -> void:
	# 单击角色 → 按权重播情绪动画并计数值。正在走/拖/播其它动作/喂食/咀嚼时忽略
	if _walking != 0 or _dragging or sprite.is_playing() or _feeding or _chewing:
		return
	# 动画冷却：短冷却内连点不切动画（数值另有 10 秒冷却在 nurture 里）
	var now := Time.get_ticks_msec()
	if now - _click_anim_last_msec < int(CLICK_ANIM_COOLDOWN * 1000.0):
		return
	_click_anim_last_msec = now
	nurture.on_click()
	_play_action(_pick_weighted_anim(CLICK_ANIM_WEIGHTS))

# 按权重字典随机挑一个键（如 {"shy":4, "cheer":3, ...}）
func _pick_weighted_anim(weights: Dictionary) -> String:
	var total := 0
	for w in weights.values():
		total += int(w)
	var r := randi() % maxi(total, 1)
	for anim in weights:
		r -= int(weights[anim])
		if r < 0:
			return String(anim)
	return "sleepy"

# ---------- 一期新增：睡觉 / 右键菜单 / 投喂 / 每日报告 ----------
# 养成数值 + 头顶气泡（运行时创建）
func _setup_nurture_and_bubble() -> void:
	# 嵌入模式全局关闭：气泡小窗/食物小窗都需要原生子窗口（嵌入的子窗口会被主窗轮廓裁掉，坑21），
	# PopupMenu 随之变成原生弹窗（自己的窗口，不再被轮廓裁剪，也不需要并入轮廓）
	get_window().gui_embed_subwindows = false
	# 气泡小窗：置顶+透明+整窗点击穿透（点击直接落到桌面，无遮罩死区），位置由 _process 每帧跟随主窗
	_bubble_win = Window.new()
	_bubble_win.borderless = true
	_bubble_win.transparent = true
	_bubble_win.always_on_top = true
	_bubble_win.transparent_bg = true
	_bubble_win.mouse_passthrough = true
	_bubble_win.size = BUBBLE_WIN_SIZE
	bubble = BubbleScript.new()
	bubble.set_head_anchor(ANCHOR_IN_BUBBLE_WIN)   # 锚点用小窗内坐标（主窗里的头顶点换算成固定偏移）
	_bubble_win.add_child(bubble)
	add_child(_bubble_win)
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture("idle", 0)
	var half_h: float = tex.get_size().y * sprite.scale.y / 2.0
	var head := sprite.position + Vector2(0.0, -half_h)   # 头顶中点（主窗坐标，缩放后恒定不动）
	_bubble_win_offset = Vector2i(int(head.x - ANCHOR_IN_BUBBLE_WIN.x), int(head.y - ANCHOR_IN_BUBBLE_WIN.y))
	_bubble_win.position = get_window().position + _bubble_win_offset
	_bubble_win.show()
	nurture = NurtureScript.new()
	add_child(nurture)
	nurture.food_gained.connect(_on_food_gained)
	nurture.feed_feedback.connect(_on_feed_feedback)
	nurture.feed_success.connect(_on_feed_success)
	nurture.cheer_burst.connect(_on_cheer_burst)
	nurture.should_sleep.connect(_on_should_sleep)

# 右键菜单（原生弹窗）。皮肤与气泡一致：奶油白面板 + 淡绿描边圆角 + 投影 + 薄荷悬停
func _setup_menu() -> void:
	_menu = PopupMenu.new()
	_menu.add_theme_font_override("font", _make_cjk_font())
	_menu.add_theme_font_size_override("font_size", 18)
	_menu.add_theme_color_override("font_color", Color(0.26, 0.38, 0.28))
	_menu.add_theme_color_override("font_hover_color", Color(0.18, 0.32, 0.22))
	_menu.add_theme_color_override("font_pressed_color", Color(0.18, 0.32, 0.22))
	# 面板：奶油白 + 淡绿 1px 描边 + 圆角 + 柔和投影（毛玻璃质感同款配色）
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.985, 0.995, 0.97)
	panel.border_color = Color(0.60, 0.76, 0.60)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 6.0
	panel.content_margin_right = 6.0
	panel.content_margin_top = 7.0
	panel.content_margin_bottom = 7.0
	panel.shadow_color = Color(0.20, 0.30, 0.22, 0.18)
	panel.shadow_size = 8
	_menu.add_theme_stylebox_override("panel", panel)
	# 悬停项：薄荷绿圆角条
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.88, 0.94, 0.86)
	hover.set_corner_radius_all(8)
	hover.content_margin_left = 10.0
	hover.content_margin_right = 10.0
	hover.content_margin_top = 4.0
	hover.content_margin_bottom = 4.0
	_menu.add_theme_stylebox_override("hover", hover)
	# 分隔线：细淡绿
	var sep := StyleBoxLine.new()
	sep.color = Color(0.62, 0.76, 0.62, 0.6)
	sep.thickness = 1.0
	_menu.add_theme_stylebox_override("separator", sep)
	_menu.min_size = Vector2i(190, 0)   # 中文字体测量偶尔偏小，强制最小宽防止菜单文字被裁
	_menu.add_item("投喂一份", MENU_ID_FEED)
	_menu.add_item("每日报告", MENU_ID_REPORT)
	_menu.add_check_item("气泡开关", MENU_ID_BUBBLE)
	_menu.set_item_checked(_menu.get_item_index(MENU_ID_BUBBLE), true)
	_menu.add_separator()
	_menu.add_item("退出", MENU_ID_QUIT)
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)

func _show_menu(pos: Vector2) -> void:
	# gui_embed_subwindows 已全局关闭（见 _setup_nurture_and_bubble）→ PopupMenu 弹出为原生窗口，
	# 自己的 HWND 不受主窗轮廓裁剪，也就不需要把菜单区域并进轮廓（老方案见坑22，已成历史）
	# 原生弹窗的 position 是屏幕坐标：主窗位置 + 窗口内坐标
	_menu.position = get_window().position + Vector2i(int(pos.x), int(pos.y))
	_menu.popup()

func _on_menu_id(id: int) -> void:
	match id:
		MENU_ID_FEED:
			_do_feed()
		MENU_ID_REPORT:
			# 报告走带进度条的 UI 入口（数值只读自 nurture，nurture 本身不动）
			bubble.show_report({
				"keys_today": nurture.keys_today,
				"keys_total": nurture.keys_total,
				"minutes": int(nurture.companion_seconds_today / 60.0),
				"energy": nurture.energy,
				"mood": nurture.mood,
				"intimacy": nurture.intimacy,
				"food": nurture.food,
				"food_progress": nurture.food_progress,
				"food_need": nurture.FOOD_PROGRESS_NEED,
			})
		MENU_ID_BUBBLE:
			bubble.set_enabled(not bubble.enabled)
			_menu.set_item_checked(_menu.get_item_index(MENU_ID_BUBBLE), bubble.enabled)
		MENU_ID_QUIT:
			nurture.flush_save()
			get_tree().quit()

# ---------- 喂食：右键菜单 → 食物贴鼠标 → 桌宠靠近 → 点击角色完成 ----------
# 菜单入口：预检（没食物/精力满直接反馈），通过则进喂食态
func _do_feed() -> void:
	var err: String = nurture.feed_precheck()
	if DEBUG_FEED:
		print("[feed] 菜单→投喂 | 预检: 食物=%d 精力=%d → %s" % [nurture.food, nurture.energy, "通过" if err == "" else err])
	if err != "":
		bubble.say(err)
		return
	_start_feeding()

# 进入喂食态：生成食物贴鼠标、打断当前动画（轮廓处理见 _refresh_passthrough / _process）
func _start_feeding() -> void:
	if _feeding:
		return
	var was_sleeping := _sleeping
	var was_walking := _walking
	var was_playing: bool = sprite.is_playing()
	if _sleeping:
		_wake()
	_walking = 0
	if sprite.animation != "idle" or sprite.is_playing():
		_stop_to_idle()   # 喂食优先级最高：打断走路/动作
	_feed_walk_dir = 0
	_feed_closing = false
	_feeding = true
	_food_bob_t = 0.0
	_feed_dbg_t = 0.0
	_ensure_food_window()
	if DEBUG_FEED:
		print("[feed] 进入喂食态 | 入口状态: 睡觉=%s 走路=%d 动画播放=%s（已打断归位待机）" % [was_sleeping, was_walking, was_playing])
		print("[feed] 食物小窗起始=%s 鼠标=%s 主窗=%s | 主窗轮廓保持不变（食物走独立小窗）" % [_food_win.position, DisplayServer.mouse_get_position(), get_window().position])
	bubble.say("把食物移到我面前，点击我就开饭", 3.0)

# 喂食态每帧：食物小窗跟鼠标浮动、桌宠平移窗口左右靠近鼠标
func _feed_tick(delta: float) -> void:
	if _feed_closing:
		return
	_food_bob_t += delta
	_feed_dbg_t += delta
	if _food_win != null:
		# 食物小窗中心贴鼠标（挪窗口=拖动同类，无区域重绘）；上下浮动画在小窗内容里
		var half := _food_win.size.x / 2.0
		_food_win.position = DisplayServer.mouse_get_position() \
				+ Vector2i(int(FOOD_OFFSET.x - half), int(FOOD_OFFSET.y - half))
		if _food_sprite != null:
			_food_sprite.position = Vector2(_food_win.size) / 2.0 \
					+ Vector2(0.0, sin(_food_bob_t * FOOD_BOB_FREQ) * FOOD_BOB_AMP)
	# 靠近 = 平移窗口（不挪精灵，避免重影）：把角色中心水平推到鼠标 x，钳在屏幕内
	var mouse_x: int = DisplayServer.mouse_get_position().x
	var sx: int = DisplayServer.screen_get_position().x
	var sw: int = DisplayServer.screen_get_size().x
	var margin: float = TARGET_WIDTH / 2.0
	var char_x: float = float(get_window().position.x) + sprite.position.x
	var target_x := clampf(float(mouse_x), sx + margin, sx + sw - margin)
	var dx := target_x - char_x
	if absf(dx) > FEED_ARRIVE_DIST:
		var step := clampf(dx, -FEED_APPROACH_SPEED * delta, FEED_APPROACH_SPEED * delta)
		get_window().position += Vector2i(int(round(step)), 0)
		var dir := -1 if dx < 0.0 else 1
		if dir != _feed_walk_dir:
			_feed_walk_dir = dir
			if DEBUG_FEED:
				print("[feed] 朝向切换 → %s (dx=%.0f)" % ["左 walk" if dir < 0 else "右 walk_r", dx])
			_play_looping("walk" if dir < 0 else "walk_r")
	elif _feed_walk_dir != 0:
		_feed_walk_dir = 0
		if DEBUG_FEED:
			print("[feed] 到位停住 (距鼠标 dx=%.0f ≤ %d) → 回待机等点击" % [dx, int(FEED_ARRIVE_DIST)])
		_stop_to_idle()
	# 周期状态行（0.5 秒一条，避免每帧刷屏）
	if DEBUG_FEED and _feed_dbg_t >= 0.5:
		_feed_dbg_t = 0.0
		print("[feed] 靠近中 | 鼠标x=%d 角色x=%.0f dx=%.0f 朝向=%d 窗口=%s" % [
			mouse_x, char_x, dx, _feed_walk_dir, get_window().position])

# 点击命中角色 → 食物飞入嘴里 → 回待机恢复穿透 → 结算 → 咀嚼（压扁回弹）
func _complete_feed() -> void:
	if _feed_closing:
		if DEBUG_FEED:
			print("[feed] 收尾中忽略重复点击")
		return
	_feed_closing = true
	if _feed_walk_dir != 0:
		_feed_walk_dir = 0
		_stop_to_idle()
	# 食物小窗滑向嘴部并缩小（移动窗口=拖动同类，无区域重绘、不会被裁），随后关小窗
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture("idle", 0)
	var mouth := sprite.position + Vector2(0.0, -tex.get_size().y * sprite.scale.y * 0.45)
	var mouth_screen: Vector2i = get_window().position + Vector2i(int(mouth.x), int(mouth.y))
	var half := int(FOOD_WIN_SIZE / 2.0)
	if DEBUG_FEED:
		print("[feed] 点击命中角色 → 食物飞入嘴 | 食物窗=%s → 嘴部屏幕=%s" % [_food_win.position, mouth_screen])
	var tw := create_tween()
	tw.tween_property(_food_win, "position", mouth_screen - Vector2i(half, half), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_food_sprite, "scale", _food_sprite.scale * 0.35, 0.25)
	await tw.finished
	_free_food_window()
	# 回到待机静态，退出喂食态
	_stop_to_idle()
	_feeding = false
	_refresh_passthrough()
	if DEBUG_FEED:
		print("[feed] 食物已入口 → 退出喂食态恢复穿透 (窗口=%s)" % get_window().position)
	# 结算（try_feed 内部再校验一次，喂食期间精力刚好满了会拒绝且不咀嚼）
	if nurture.try_feed():
		nurture.mark_interacted()   # 喂食算互动，推迟"无键入睡"
		if DEBUG_FEED:
			print("[feed] 结算成功 → 咀嚼 | 结算后: 食物=%d 精力=%d 心情=%d 亲密=%d" % [nurture.food, nurture.energy, nurture.mood, nurture.intimacy])
		var base: Vector2 = sprite.scale
		_chewing = true
		var tw2 := create_tween()
		tw2.tween_property(sprite, "scale", Vector2(base.x * 1.05, base.y * 0.88), 0.12)
		tw2.tween_property(sprite, "scale", base, 0.12)
		tw2.tween_property(sprite, "scale", Vector2(base.x * 1.05, base.y * 0.88), 0.12)
		tw2.finished.connect(func() -> void:
			sprite.scale = base
			_chewing = false
		)
	elif DEBUG_FEED:
		print("[feed] 结算被拒 → 不咀嚼 | 食物=%d" % nurture.food)
	# feed_success 信号会让 main 播 cheer（与咀嚼并行，视觉上像"吃完美滋滋"）

# 取消喂食（右键/点空白）：食物淡出、退出模式（不扣食物）
func _cancel_feeding() -> void:
	if not _feeding or _feed_closing:
		return
	if DEBUG_FEED:
		print("[feed] 取消喂食 | 食物未扣(库存=%d) → 食物淡出" % nurture.food)
	_feeding = false
	_feed_walk_dir = 0
	if _food_win != null:
		var win := _food_win
		var spr := _food_sprite
		_food_win = null
		_food_sprite = null
		var tw := create_tween()
		tw.tween_property(spr, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func() -> void:
			win.queue_free()
			_free_food_window()
		)
	_stop_to_idle()
	_refresh_passthrough()

# 食物独立小窗：置顶、透明、整窗点击穿透。蛋画在小窗里，喂食期间只挪小窗位置——
# 挪窗口与拖动桌宠同类（无区域重绘），从根上避开"主窗轮廓跟随鼠标"的白条/裁切/闪屏问题
func _ensure_food_window() -> void:
	if _food_win != null:
		return
	var tex: Texture2D = null
	var src := "占位煎蛋（未找到 " + FOOD_TEX_PATH + "）"
	if ResourceLoader.exists(FOOD_TEX_PATH, "Texture2D"):
		tex = load(FOOD_TEX_PATH)
		src = FOOD_TEX_PATH
	if tex == null:
		tex = _make_placeholder_food_tex()
	# 嵌入模式已在启动时全局关闭（见 _setup_nurture_and_bubble），这里直接 add_child 即为原生窗口
	_food_win = Window.new()
	_food_win.borderless = true
	_food_win.transparent = true
	_food_win.always_on_top = true
	_food_win.transparent_bg = true
	_food_win.mouse_passthrough = true   # 整窗点击穿透（窗口样式标记，一次设置，不涉及轮廓）
	_food_win.size = Vector2i(FOOD_WIN_SIZE, FOOD_WIN_SIZE)
	_food_sprite = Sprite2D.new()
	_food_sprite.texture = tex
	var h := float(tex.get_height())
	if h > 0.0:
		_food_sprite.scale = Vector2.ONE * (FOOD_HEIGHT / h)
	_food_sprite.position = Vector2(FOOD_WIN_SIZE, FOOD_WIN_SIZE) / 2.0
	_food_win.add_child(_food_sprite)
	add_child(_food_win)
	var half := FOOD_WIN_SIZE / 2.0
	_food_win.position = DisplayServer.mouse_get_position() \
			+ Vector2i(int(FOOD_OFFSET.x - half), int(FOOD_OFFSET.y - half))
	_food_win.show()
	if DEBUG_FEED:
		print("[feed] 创建食物小窗 | 贴图=%s 原始尺寸=%s 缩放=%.3f 小窗=%dx%d" % [src, tex.get_size(), _food_sprite.scale.x, FOOD_WIN_SIZE, FOOD_WIN_SIZE])

# 关掉食物小窗（嵌入模式保持全局关闭，无需恢复）
func _free_food_window() -> void:
	if _food_win != null:
		_food_win.queue_free()
		_food_win = null
		_food_sprite = null

# 占位贴图：白蛋白黄的煎蛋（64x64）；把正式荷包蛋放进 assets/food/food.png 后自动替换
func _make_placeholder_food_tex() -> Texture2D:
	var s := 64
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length()
			if d <= 13.0:
				img.set_pixel(x, y, Color(1.0, 0.78, 0.25))   # 蛋黄
			elif d <= 28.0:
				img.set_pixel(x, y, Color(0.99, 0.98, 0.95))  # 蛋白
	return ImageTexture.create_from_image(img)

# 睡觉/唤醒：sleepy 循环播放 = 睡觉态（一期设计，无独立入睡动画）
func _on_should_sleep() -> void:
	if _sleeping or _feeding or _chewing or _dragging or _walking != 0 or sprite.is_playing():
		return
	_sleeping = true
	_play_looping("sleepy")

func _wake() -> void:
	if not _sleeping:
		return
	_sleeping = false
	_stop_to_idle()

func _on_cheer_burst() -> void:
	if _feeding or _chewing or _dragging or _walking != 0 or sprite.is_playing():
		return
	_play_action("cheer")

func _on_food_gained(count: int) -> void:
	bubble.say("获得 1 个食物（%d/%d）" % [count, nurture.FOOD_MAX])

func _on_feed_feedback(text: String) -> void:
	bubble.say(text)

func _on_feed_success() -> void:
	if not _dragging and _walking == 0 and not sprite.is_playing():
		_play_action("cheer")

# 中文字体：Godot 默认字体没有中文字形（会显示方块），统一用系统微软雅黑
func _make_cjk_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = ["Microsoft YaHei", "SimHei"]
	return f
