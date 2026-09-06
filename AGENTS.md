# AGENTS.md — 小松绿桌宠

> 给下一次会话（人或 AI）的完整交接文档。读完这页即可直接继续开发，无需重新摸索。

## 一、项目是什么

- **Godot 4.6.1 stable (mono) 桌面宠物项目**，目标平台 Windows，技术栈为 **GDScript + C# 混合**（场景/动画/触发用 GDScript，全局键盘钩子用 C#）
- 角色：**小松绿**——绿短发、粉眼睛的少女，标志元素：绿色针织背心、腿上创可贴、头上的煎蛋/向日葵装饰
- 最终愿景：可长期挂在桌面上的桌宠——置顶显示、透明背景、鼠标拖动、点击穿透、待机/互动动画、右键菜单（**不做系统托盘**，Godot 无原生支持，一期已定案）、（二期）截屏感知 + LLM + TTS

## 二、当前进度（更新于 2026-09-06）

| 状态 | 内容 |
|---|---|
| ✅ 已完成 | 最小原型：全屏透明覆盖层 + 置顶 + 鼠标穿透（按贴图轮廓）+ 按住角色拖动 + Esc 退出 |
| ✅ 已完成 | 导出 exe 并手动验收通过（`test.exe` + `test.pck`，在项目根目录） |
| ✅ 已完成 | **序列帧动画 + 触发体系**：角色节点改为 `AnimatedSprite2D` + `SpriteFrames`，动作动画（cheer/cry/lifted/scary/shy/sleepy/walk 均为单次 loop=false；idle 为运行时动态补建、loop=true），并实现完整触发：● 共用定时器（20±5 秒）到点随机触发走路 / sleepy 困倦 / 待机静态切帧 ● 单击随机触发 cheer/cry/scary/shy 情绪 ● 拖动循环播 lifted ● 走路用镜像 walk_r 支持左右双向 |
| ✅ 已完成 | 鼠标穿透轮廓：待机用待机帧轮廓；**动作/走路/拖动期间用该动作 alpha 并集后求凸包的轮廓**（单一多边形、覆盖全部含分离部分，不缺角），播完回待机轮廓，并用字典缓存避免重复计算 |
| ✅ 已完成 | **C# 全局键盘钩子**：项目改为 GDScript + C# 混合，`GlobalKeyboardHook.cs`（后台线程钩子 + `KeyPressed(keyCode,isDown)` 信号）已接入 `main.gd`，控制台能监听到任意窗口的按键并打印 `[key] <键名>`（验证通过）。后续可基于它做"敲代码互动、头顶按键气泡"等 |
| ✅ 已完成（2026-09-06） | **一期主体（已人工验收通过）**：字母雨气泡 + 系统反馈消息条（Node2D 自绘，见坑 21）+ 养成数值系统（三数值/30 秒 tick/敲得欢/睡觉/加权动画池/投喂/存档）+ 右键菜单（投喂一份/每日报告/气泡开关/退出，Esc 退出已删除）。设计细节见第九节 9.1，代码见第四节"一期新增模块" |
| ✅ 已完成（2026-09-06 下午） | **一期优化第一批**：**喂食交互**（食物独立小窗贴鼠标跟随 + 桌宠平移窗口靠近 + 点击角色投喂，含滑入嘴/咀嚼/取消；贴图 `assets/food/food.png`，2048 原图存 `原始素材/荷包蛋.png`）+ 定时器 20±5→**10±5 秒** + 入睡 180→**60 秒** + 敲得欢 **80 键/30 秒窗口/边沿触发**（无固定冷却）+ **回车 cheer / 退格 scary**（10 秒共用冷却）+ 单击 **2 秒动画冷却**（防连点狂切）+ scary 贴图文件 sad_* 统一改名 scary_* |
| ✅ 已完成（2026-09-06 晚） | **修复两枚**：① 投喂不再因"精力满"拒绝（只查没食物，`FEED_REFUSE_ENERGY` 常数已删，9.1 设计表里"精力≥95 拒绝"作废）② **"倒着走" bug**——`_start_walk` 屏幕钳制原来锚定**窗口位置**，窗口被拖/喂食挪到屏幕左侧外后，向左走的目标点被钳到右侧 → 朝左动画+向右滑行约 800px（小概率：角色在屏幕左侧约 40% 区域+掷出向左走）。改为锚定**角色屏幕位置**钳制（走完后角色 x 夹在 `[屏幕左+半宽, 屏幕右-半宽]`）；配套三处加固：走路被打断时 `_stop_to_idle` 杀掉残留窗口 tween（否则继续按旧目标拉窗口）、`_play_looping` 切朝向时还原上一个动画的 loop 标志（防泄漏）、走路收尾前校验 `_walking` 未被抢占 |
| ✅ 已完成（2026-09-06 最终） | **白条根治 + 气泡小窗 + UI 美化批**：字母雨/emoji/消息条搬进**独立置顶穿透气泡小窗**（主窗轮廓恒纯角色、`gui_embed_subwindows` 启动时全局关、右键菜单变原生弹窗——三类轮廓伪影全灭，详见坑 21/22）+ **喂食超时机制删除**（取消=右键/点空白）+ 敲得欢窗口 20→**30 秒**、**tick 30→20 秒** + 字母雨 **42 号/白字绿描边** + 颜文字改**可爱 emoji**（🥺🥰🍳🍀✨ 等 16 个，Segoe UI Emoji 彩色字体渲染）+ 消息条视觉重做（**渐变圆角面板+投影+气泡尾巴+顶部高光+入场下滑淡入**）+ **每日报告改带进度条**（精力/心情/亲密/下一餐，`bubble.show_report()`，数值只读自 nurture）+ 右键菜单换肤（奶油白圆角面板+淡绿描边+投影+薄荷悬停）。**`需求文档.md` 已删除，全部需求已实施、内容并入本文档** |
| ✅ 已完成（2026-09-06 晚） | **修复两枚**：① 投喂不再因精力满拒绝（只查没食物，`FEED_REFUSE_ENERGY` 常数已删，9.1 设计表里"精力≥95 拒绝"作废）② **"倒着走" bug**——`_start_walk` 屏幕钳制原来锚定**窗口位置**，窗口被拖/喂食挪到屏幕左侧外后，向左走的目标点被钳到右侧 → 朝左动画+向右滑行约 800px（小概率：角色在屏幕左侧约 40% 区域+掷出向左走）。改为锚定**角色屏幕位置**钳制（走完后角色 x 夹在 `[屏幕左+半宽, 屏幕右-半宽]`）；配套三处加固：走路被打断时 `_stop_to_idle` 杀掉残留窗口 tween（否则继续按旧目标拉窗口）、`_play_looping` 切朝向时还原上一个动画的 loop 标志（防泄漏）、走路收尾前校验 `_walking` 未被抢占 |
| ⬜ 未开始 | 远期（见 9.3）：分发优化（GDExtension 迁移或 self-contained）、设置界面、开机自启、换装等；二期（截屏感知+LLM+TTS）已取消（9.2 仅留档） |

交互现状（2026-09-06 一期优化后定稿）：**拖动**=按住角色移动（循环播 lifted，真拖动心情+1、30 秒冷却）；**单击**=按权重（shy4:cheer3:cry2:scary1）播情绪动画（数值 10 秒冷却 + 动画 2 秒冷却防连点），心情+3、加完心情≥80 额外+1 亲密；**右键点角色**弹菜单（**原生弹窗**、奶油白圆角皮肤）：投喂一份 / 每日报告（**带 4 条渐变进度条**：精力/心情/亲密/下一餐）/ 气泡开关 / 退出（唯一退出入口，退出前存档）；打字时头顶**字母雨**（**小写**字母+数字、字号 42、白字绿描边、0.9 秒淡出）+ 8% 概率可爱 **emoji 彩蛋**（🥺🥰🍳🍀✨ 等 16 个，Segoe UI Emoji 彩色字体、1.6 秒淡出，概率/池子在 bubble.gd 顶部 EMOJI_*）；**喂食**：菜单预检（只查没食物，精力满也能喂）→ 食物独立小窗贴鼠标跟随 → 桌宠 300px/s 平移窗口靠近（<60px 到位）→ 左键点角色=食物滑入嘴+咀嚼压扁+结算（精力+30 心情+5 亲密+2）+cheer，右键/点空白取消不扣食物，喂食成功重置入睡计时；键盘互动：**敲得欢**（30 秒窗口 ≥80 键、边沿触发）心情+1、**回车** cheer / **退格** scary（10 秒共用冷却）、**60 秒**不敲入睡（sleepy 循环，敲键/单击/拖动/右键/投喂唤醒）；数值：**tick 20 秒**结算（活跃≥15 键：精力-2+食物进度+1（满 15 得 1 食物，库存上限 20）；安静：精力+1 心情-2；心情≥80 每 6 tick 亲密+1），离线超 1 小时精力回满不惩罚。**UI 架构（重点）**：字母雨/emoji/消息条画在独立置顶穿透**气泡小窗**、喂食食物在**食物小窗**、右键菜单为原生弹窗——主窗穿透轮廓**恒为纯角色本体**（`gui_embed_subwindows` 启动时全局关闭），任何 UI 出现消失都不会引起闪屏/白条/裁切（三轮血泪史见坑 21/22）。所有数值/视觉常数集中在各脚本顶部，先实跑再按体感调参。

## 三、核心架构（改动前必读）

**方案：全屏透明覆盖层 + 平移窗口**（参考项目 xccds/DesktopPet 的思路）

1. 启动时窗口铺满整个屏幕（**比屏幕小 1 像素**），无边框、置顶、透明，之后窗口尺寸/内容**永不改变**
2. 所谓"拖动桌宠" = 平移这个覆盖层窗口。窗口内容零重绘 → 不会有重影花边，且和编辑器/导出版行为一致
3. 鼠标穿透：从贴图 alpha 提取不透明轮廓，换算到窗口坐标，设置 `mouse_passthrough_polygon`。角色**不再全程静止**（有动画），所以穿透**不是一次性**的了：待机时用当前待机帧轮廓，**动作播放期间用该动作所有帧 alpha 并集后求凸包的轮廓**（一个多边形、覆盖全部含分离部分，不缺角），播完/切待机帧后重算。凸包结果按动画/帧用字典缓存（实测单次凸包约 50ms，缓存后同动画第二次≈0ms）
4. 关键约束：**穿透轮廓必须跟着当前显示内容走**。待机静态切换帧、以及动作动画的开始/结束，都要重设穿透多边形，否则会出现"动作被穿透隐藏"或"残留旧轮廓"。**`mouse_passthrough_polygon` 只支持一个连续多边形**，所以分离的身体部分（手/衣角等）要用凸包合并成一个轮廓，不能传多个分离多边形。**另外（2026-09-06 实测）：本机轮廓外的像素会被整块裁掉不渲染（不只是不响应鼠标），所以任何 UI 显示期间都要把 UI 区域并入轮廓，见 main.gd 的 `_apply_passthrough()` / `_refresh_passthrough()` 和坑 21**

为什么不是其他方案（都实测踩过坑）：
- ~~小窗口跟随鼠标挪~~：每帧移动系统窗口触发 DWM 重复合成，卡顿闪烁
- ~~窗口焊死 + 挪贴图~~：GL Compatibility 下贴图快速移动会重影花边（本机实测）

## 四、代码地图

- `scenes/main.tscn`：`Main`(Node2D，挂脚本) + `Character`(**AnimatedSprite2D**，已挂 `SpriteFrames` 资源，含 7 个动作动画 cheer/cry/lifted/scary/shy/sleepy/walk，全部 `loop=false` 单次播；idle 由脚本运行时补建) + `GlobalKeyboardHook`(C# Node 子节点，挂 `res://GlobalKeyboardHook.cs`，做全局键盘监听)
- `script/main.gd`：窗口/动画/触发/输入/喂食主逻辑（一期优化后约 900 行，新增部分见下文"一期新增模块"与"喂食"条目）
  - `_ready()`：建 idle 动画 → 镜像建 walk_r → 切待机静态 → 连 `animation_finished` → 设窗口/居中/穿透 → 启动共用触发定时器 → 连接键盘钩子（`_connect_keyboard_hook`）→ 一期：`_setup_nurture_and_bubble()` → `_setup_menu()`
  - `_build_idle_animation()`：运行时加载 `idle_1/idle_2.png` 动态建 `idle` 动画（即使 SpriteFrames 没建也能用）
  - `_build_walk_right_animation()`：把 walk 的 3 帧 `flip_x()` 水平翻转，动态建朝右的 `walk_r` 动画（walk 朝左，镜像后朝右）
  - `_setup_window()`：铺满屏幕（-1px）并对齐屏幕原点
  - `_center_and_scale()`：按 `TARGET_WIDTH`（300px）缩放角色并放到屏幕中心（用 idle 帧尺寸定缩放）
  - `_setup_switch_timer()` / `_next_switch_delay()` / `_on_switch_timeout()`：**共用触发定时器**（20±5 秒随机），空闲时按权重随机分派：走路（概率 = 35% × `nurture.walk_multiplier()`，精力高更高/低更低）/ 情绪动画（30%，从 `nurture.pick_auto_anim()` 的数值加权池抽 sleepy/cheer/cry）/ 待机静态切帧（剩余概率），并重算穿透
  - `_start_walk(dir)`：朝 dir 走，播 walk/walk_r 循环 + 用 Tween 平移窗口 `WALK_DISTANCE` 像素，走完回待机
  - `_play_action(anim)`：单次播放某动作（播完 `animation_finished` 回待机），并调 `_apply_action_union_polygon`
  - `_play_looping(anim)`：临时把动画设 `loop=true` 再播放（拖动/走路用，播多久不停），并记 `_looping_anim`
  - `_stop_to_idle()`：把临时改过 loop 的动画还原成单次，`stop()` 回待机静态并重算穿透
  - `_apply_action_union_polygon(anim)`：播放动作时应用穿透，**优先查缓存**（同动画不再重算）；未命中才调 `_compute_union_polygon_points` 计算并存缓存
  - `_compute_union_polygon_points(anim)`：把该动作所有帧 alpha 合并成并集 mask，收集不透明像素，**求凸包**并换算成窗口坐标（动作有分离部分也不缺角）
  - `_apply_click_polygon()`：待机/当前帧穿透，**同样查缓存**；未命中调 `_compute_frame_points` 计算并存缓存
  - `_compute_frame_points(anim, frame)`：对单帧求凸包并换算成窗口坐标
  - `_convex_hull(pts)` / `_cross(o,a,b)`：凸包算法（Andrew 单调链）及叉积，用单一多边形覆盖所有分离像素点
  - `_on_animation_finished()`：单次动作播完回待机；若仍在拖/走则继续循环对应动画（防御）
  - `_input()`：**右键点角色**弹菜单（锚定角色右侧，见"一期新增模块"）；左键按住（命中半径 `TARGET_WIDTH/2`）开始拖动，真正移动时才循环播 lifted 并计数值（点击不播，避免闪），松开时位移<5px 视为点击 → `_on_click()`。Esc 退出已删除（一期设计，退出走菜单）
  - `_on_click()`：单击从 `CLICK_ANIM_WEIGHTS`（shy4:cheer3:cry2:scary1）按权重挑情绪播，并调 `nurture.on_click()` 计数值（正在走/拖/播动作时忽略）
  - `_connect_keyboard_hook()`：从场景里找 `GlobalKeyboardHook` 节点，connect 它的 `KeyPressed` 信号
  - `_on_global_key(keyCode, isDown)`：收到全局按键（isDown 才处理）：唤醒睡觉态 → `nurture.on_key_down()` 计统计 → 字母/数字键调 `bubble.pop_letter()` 字母雨 → `DEBUG_PRINT_KEYS` 为 true 时打印 `[key] <键名>`
  - `_key_name(vk)`：把虚拟键码转成可读按键名（A-Z、数字、常用功能键），后续做头顶气泡/互动可直接复用
  - 喂食（2026-09-06 新增）：`_do_feed()`（预检）→ `_start_feeding()`（进喂食态：创建食物独立小窗贴鼠标、打断当前动画，主窗轮廓不动）→ `_feed_tick()`（每帧：小窗跟随鼠标浮动/平移窗口靠近鼠标）→ `_complete_feed()`（小窗滑向嘴部缩小→try_feed 结算→咀嚼压扁）→ `_cancel_feeding()`（右键/点空白取消，不扣食物）；`_ensure_food_window()`/`_free_food_window()`/`_make_placeholder_food_tex()`（食物小窗的创建销毁与占位贴图，正式贴图 `assets/food/food.png`）
- 穿透缓存：`_polygon_cache`（键=动画名，或 `"动画名#帧"`，值=窗口坐标穿透点数组）
- main.gd 常量表：`WALK_CHANCE=0.35`、`EMOTION_CHANCE=0.3`（剩余=待机切帧）、`IDLE_SWITCH_SECONDS=10`（2026-09-06 由 20 改）、`IDLE_SWITCH_JITTER=5`、`WALK_DISTANCE=200`、`WALK_STEP_TIME=0.9`、`TARGET_WIDTH=300`、`CLICK_THRESHOLD=5`、`CLICK_ANIM_COOLDOWN=2`（单击切动画冷却）、`VK_ENTER/VK_BACKSPACE`+`SPECIAL_KEY_ANIM_COOLDOWN=10`（回车 cheer/退格 scary）、喂食组常数 `FOOD_TEX_PATH/FOOD_WIN_SIZE=160/FOOD_HEIGHT=70/FOOD_OFFSET/FEED_APPROACH_SPEED=300/FEED_ARRIVE_DIST=60`、气泡小窗 `BUBBLE_WIN_SIZE=440x360`/`ANCHOR_IN_BUBBLE_WIN=(220,290)`、`CLICK_ANIM_WEIGHTS={"shy":4,"cheer":3,"cry":2,"scary":1}`、`DEBUG_PRINT_KEYS=false`（每键打印开关）、`MENU_ID_*` 菜单项 ID。养成数值常数集中在 `nurture.gd` 顶部（tick 已改 **20 秒**、敲得欢 `CHEER_BURST_KEYS=80`/`CHEER_BURST_WINDOW=30` 边沿触发、`NO_KEY_SLEEPY_SECONDS=60`）、气泡常数在 `bubble.gd` 顶部（字母雨/`EMOJI_*` 彩蛋池与概率/消息条视觉 `COL_*`、`BAR_*` 进度条）

**常用调参速查（常数都在对应脚本顶部，改完保存重跑即生效；先实跑按体感调，不要一次性精算）**

| 想调什么 | 文件 · 常数 | 现值 |
|---|---|---|
| 数值结算节奏 | nurture · `TICK_SECONDS` | 20 秒 |
| 活跃打字门槛 | nurture · `ACTIVE_KEYS_PER_TICK` | 15 键/tick |
| 入睡等待 | nurture · `NO_KEY_SLEEPY_SECONDS` | 60 秒 |
| 敲得欢阈值 / 窗口 | nurture · `CHEER_BURST_KEYS` / `CHEER_BURST_WINDOW` | 80 键 / 30 秒 |
| 单击：数值冷却 / 动画冷却 | nurture · `CLICK_COOLDOWN` / main · `CLICK_ANIM_COOLDOWN` | 10 秒 / 2 秒 |
| 拖动数值冷却 | nurture · `DRAG_COOLDOWN` | 30 秒 |
| 投喂收益 | nurture · `FEED_ENERGY` / `FEED_MOOD` / `FEED_INTIMACY` | +30 / +5 / +2 |
| 喂食靠近速度 / 到位距离 | main · `FEED_APPROACH_SPEED` / `FEED_ARRIVE_DIST` | 300 px/s / 60 px |
| 待机触发间隔 | main · `IDLE_SWITCH_SECONDS` / `IDLE_SWITCH_JITTER` | 10±5 秒 |
| 走路 / 情绪触发概率 | main · `WALK_CHANCE` / `EMOTION_CHANCE` | 0.35 / 0.3 |
| 字母雨字号 / emoji 触发概率 | bubble · `LETTER_FONT_SIZE` / `EMOJI_CHANCE` | 42 / 0.08 |
| emoji 池 / 存活时长 | bubble · `EMOJI_POOL` / `EMOJI_LIFETIME` | 16 个 / 1.6 秒 |
| 消息条停留 / 面板配色 | bubble · `MSG_DEFAULT_HOLD` / `COL_*`、`BAR_*` | 2.5 秒 / 见常数 |
| 存档防抖 / 离线保护 | nurture · `SAVE_DEBOUNCE` / `OFFLINE_SLEEP_SECONDS` | 5 秒 / 1 小时 |

### C# 全局键盘钩子模块（关键系统功能）
- `GlobalKeyboardHook.cs`：**C# 的 Node 子类**，标了 `[GlobalClass]`，已作为子节点加进 `scenes/main.tscn`（节点名 `GlobalKeyboardHook`，挂 `res://GlobalKeyboardHook.cs`）。
- 原理：后台线程用 Windows 低级全局钩子 `SetWindowsHookEx(WH_KEYBOARD_LL)` 监听**任意窗口**的按键（不依赖 Godot 焦点）；按键事件塞进线程安全队列 `ConcurrentQueue`，Godot 主线程在 `_Process` 里取出，通过 **信号 `KeyPressed(keyCode, isDown)`** 发出来。
- **为什么必须走队列 + 主线程发信号**：Godot 禁止在非主线程碰节点/发信号。钩子回调在系统线程跑，所以只能先塞队列，主线程再发。
- **复用方法（后续做任何"键盘互动"都用它）**：`main.gd` 里已经 `_connect_keyboard_hook()` 连好了，新逻辑直接在 `_on_global_key(keyCode, isDown)` 里加分支即可。keyCode 是 Windows 虚拟键码（如 A=0x41、Enter=0x0D、Ctrl=0x11），用 `_key_name(vk)` 转成可读名。互动判定（如"敲得欢=cheer / 长时间不敲=sleepy"）可基于按键间隔/频率统计。
- 项目文件：`XiaoSongLv.csproj` + `XiaoSongLv.sln`（Godot 自动生成，程序集名 `XiaoSongLv`，命名空间 `XiaoSongLv`，TargetFramework net8.0，SDK `Godot.NET.Sdk/4.6.1`）。C# 代码编译产物在 `.godot/mono/temp/bin/Debug/XiaoSongLv.dll`。
- 独立验证过的基础版在 `技术验证/Program.cs`（纯控制台钩子），`GlobalKeyboardHook.cs` 是它的 Godot 移植版。

### 一期新增模块（2026-09-06，配合第九节 9.1 设计）
  - `script/nurture.gd`：养成数值系统（纯逻辑 Node，运行时创建）。可调常数全在文件顶部；通过信号 `food_gained/feed_feedback/feed_success/cheer_burst/should_sleep` 通知 main；每 20 秒 tick 结算；`pick_auto_anim()` 数值加权动画池、`walk_multiplier()` 走路概率倍率；存档 `user://save.json`（变更延迟 5 秒合并写 + 每 tick 兜底 + 菜单退出前必写；离线超 1 小时视为睡觉、精力回满不惩罚）
- `script/bubble.gd`：头顶气泡（**由 main 放进气泡小窗渲染，坐标全是小窗内坐标**，见坑 21），**Node2D `_draw()` 自绘**（本机透明窗口里 Control 不渲染）。`pop_letter()` 字母雨 + emoji 彩蛋（EMOJI_* 常数）、`say(text, hold)` 普通消息条、`show_report(dict)` **带进度条的每日报告**（精力/心情/亲密/下一餐四条渐变进度条，数值只读自 nurture）、`set_enabled()` 气泡开关。消息条视觉：**渐变圆角面板（`_rounded_rect_points`+`_draw_rounded_rect` 逐顶点渐变）+ 投影 + 气泡小尾巴 + 顶部高光 + 入场下滑淡入**（"毛玻璃"为半透明渐变近似，Godot 拿不到桌面做真模糊）；消息文本布局在取出那一刻算一次缓存
- `main.gd` 新增：`_process()`（**气泡小窗每帧跟随主窗** + 窗口位置监视：位置一变就重贴穿透轮廓——轮廓不跟窗口自动走，见坑 21）、`_apply_passthrough()` / `_refresh_passthrough()`（穿透统一入口 = **纯角色本体轮廓，内容恒定**；**任何 UI 都走独立小窗，别再往轮廓里并东西，也别直接赋值 `mouse_passthrough_polygon`**）、`_setup_nurture_and_bubble()`（**gui_embed_subwindows 全局关闭** + 气泡独立小窗创建/跟随偏移计算）、`_setup_menu()`（运行时创建 PopupMenu，现为**原生弹窗**，皮肤=奶油白圆角面板+淡绿描边+投影+薄荷悬停项，主题覆盖都在 `_setup_menu` 里）、`_show_menu()`（原生弹窗：position = 主窗位置 + 窗口内坐标；菜单锚定角色右侧 `sprite.position + (半宽-40, -40)` 并做屏幕边缘钳制）、`_on_menu_id()`、`_do_feed()`、睡觉/唤醒（`_sleeping` 状态，sleepy 循环播放 = 睡觉态；敲键/单击/拖动/右键四路唤醒）、`_pick_weighted_anim()`（单击权重 shy4:cheer3:cry2:scary1）、`DEBUG_PRINT_KEYS` 开关（默认 false，控制每键打印）。Esc 退出已删除，退出走右键菜单。**打印纪律：非必要不打印**（运行期常驻日志已全部移除，仅保留启动时一条钩子连接确认和默认关闭的 DEBUG_PRINT_KEYS）。2026-09-06 喂食调试期临时启用 `DEBUG_FEED=true`（`[feed]` 前缀的全流程输出：预检/进入/食物小窗/朝向切换/到位/点击命中/结算/取消，靠近中每 0.5 秒一条状态行；**验收通过后改回 false 静音**）

## 五、项目设置关键项（project.godot）

- `display/window/size/`：`borderless`、`always_on_top`、`transparent`、`per_pixel_transparency/allowed` 均 **true**；`viewport 324x324` 只是初始值，实际被代码覆盖
- `rendering/renderer/rendering_method = gl_compatibility`（当前配置下一切正常。曾怀疑渲染器导致重影/窗口不能动，最终定位是 API 调用路径问题，见下节；若未来出现渲染异常，可尝试切 `forward_plus` 对照）
- `rendering/viewport/transparent_background = true`（和窗口透明缺一不可）
- `[physics]`（Jolt）是新建项目残留，未使用
- `[dotnet]` 段**已启用**：`project/assembly_name="XiaoSongLv"`（原来中文名 `小松绿桌宠`，因触发 MSBuild "特性重复"坑改为纯英文）。项目的关键系统级功能（全局键盘钩子）用 **C#** 实现，场景/动画/触发逻辑仍是 **GDScript** —— 现在项目是 **GDScript + C# 混合**，必须用 **Godot mono 版**打开/编译

## 六、本机已知坑（血泪总结，动手前先看）

环境：Windows 11，Godot 4.6.1 stable **mono** 版，屏幕 2560x1600

1. **移动窗口必须用属性赋值** `get_window().position = ...`。`DisplayServer.window_set_position()` 在 4.6.1 上**静默失效**（无报错、无效果）——参考项目在 4.3 上能用，属版本行为差异
2. **窗口尺寸不能正好等于屏幕尺寸**：会被 Windows 当作"已最大化"而拒绝移动（Godot 还会骗你说位置改成功了）。代码里统一 `- Vector2i(1, 1)`
3. **拖动坐标必须同源**：按下记录和位移计算都用 `DisplayServer.mouse_get_position()`（屏幕坐标）。混用 `get_global_mouse_position()`（窗口内坐标）会导致再次抓取时角色瞬移一个窗口偏移
4. **编辑器"游戏嵌入模式"必须禁用**：编辑器设置 → 运行 → 窗口放置 → 游戏嵌入模式 = 禁用。否则游戏跑在编辑器"游戏"面板里，一切窗口操作无效。运行时可用 `get_window().is_embedded()` 自检
5. **GDScript 类型**：`Vector2i` 与 `Vector2` 不能混算（要显式 `Vector2i(...)` 转换）；`event.position` 这类子类属性是 Variant，`var x := event.position.xxx` 会报推断错误，要写 `var x: float = ...`
6. **鼠标穿透轮廓与透明边缘的"白框/轮廓线"**：穿透轮廓是从贴图 alpha 阈值（`create_from_image_alpha(img, 0.1)`）提取的。动画帧在角色边缘有一圈半透明白像素（肤色/衣服边缘的抗锯齿过渡），动作播放时轮廓若贴合外形，会在角色边缘露出**一圈细白边/轮廓线**，这是 alpha 抗锯齿残留，视觉影响很小，**属于可接受的视觉瑕疵**，不影响鼠标交互。若想去掉可提高 alpha 阈值（如 0.2~0.3），但会相应改变穿透贴合度，需权衡。此前用"矩形轮廓"（盖住整帧）会让动作段出现整圈白框，已弃用；当前用"alpha 并集后求凸包"的轮廓。
7. **`BitMap.get_bit/set_bit` 参数**：4.6 用 `get_bit(x, y)`、`set_bit(x, y, value)`（两个 int），**不是** `Vector2i`。用 `Vector2i` 会报 "Too few arguments" 解析错误。
8. **`SpriteFrames` 循环控制方法名**：是 `set_animation_loop(anim, bool)` / `get_animation_loop(anim)`，**不是** `set_loop`（那会报 "Nonexistent function 'set_loop'"）。运行时可临时把某动画设为循环再播，结束后记得还原成 false。
9. **`AnimatedSprite2D.play()` 的 from_frame 坑**：`play(anim, 0.0)` 会**让播放器停在开始不推进**（表现为"只有静态帧、动画不动"）——应写成 `play(anim)` 不传 from_frame，`is_playing()` 才正常推进动画。循环与否只由动画自身 loop 决定，`from` 参数不强制循环。
10. **无类型数组取下标要用显式类型**：`var anim := 数组[randi() % size()]` 会报 "Cannot infer the type"（因为数组元素是 Variant）。要写 `var anim: String = 数组[idx]`。
11. VS Code 的 gdtoolkit 插件可能误报"函数不存在"，**以 Godot 编辑器运行结果为准**
12. **C# 程序集名必须纯英文**：`[dotnet] project/assembly_name` 和 csproj 的 `AssemblyName` 用中文（如 `小松绿桌宠`）会触发 MSBuild "特性重复"（CS0579）。统一改成英文（本项目用 `XiaoSongLv`）即可。
13. **C# "特性重复"（CS0579）的根因**：Godot.NET.Sdk 和 MSBuild 都会自动生成程序集元数据（`Assembly*` 和 `TargetFramework`），两者叠加就重复。**在 csproj 里关掉 MSBuild 那套**即可：`<GenerateAssemblyInfo>false</GenerateAssemblyInfo>` + `<GenerateTargetFrameworkAttribute>false</GenerateTargetFrameworkAttribute>`。改完要 `rm -rf .godot/mono/temp/obj` 清缓存重编。
14. **不要在 Godot 项目里用命令行 `dotnet build` 反复构建**：会把输出/中间产物写到 `.godot/mono/temp/` 里，跟 Godot 自己的构建撞车，制造各种假报错。**让 Godot 编辑器自己构建**（重开编辑器 / 运行场景触发），命令行 build 只在排障时用、且要临时指到别处。
15. **C# 类要能被 Godot 搜索/实例化，必须标 `[GlobalClass]`**；且新增/改 C# 类后，Godot 需要**重新加载程序集**（重开编辑器）才认得到。C# 节点加进场景后，节点名要和脚本里 `get_node` 一致（本项目节点叫 `GlobalKeyboardHook`）。
16. **C# 钩子的线程安全**：全局钩子回调在后台线程，**禁止直接发 Godot 信号/碰节点**（会崩溃）。必须先用线程安全队列（`ConcurrentQueue`）缓存，再在主线程 `_Process` 里取出发信号。本项目 `GlobalKeyboardHook.cs` 已按此实现。
17. **GDScript 连接 C# 信号**：node 是 C# 节点时，`get_node_or_null("GlobalKeyboardHook").connect("KeyPressed", Callable)`，信号名用 C# 里 `[Signal]` 定义的名字（`KeyPressed`），参数为 `(keyCode: int, isDown: bool)`。
18. **刷新项目时"全局类缓存"是空的正常**：`.godot/global_script_class_cache.cfg` 是 `list=[]` 不代表搜不到 C# 类——C# 类走的是 GodotSharp 程序集扫描，不是这个缓存。搜不到 C# 类，先重开编辑器让它重载程序集。
19. **`mouse_passthrough_polygon` 只支持一个连续多边形**：不能传多个分离多边形（文档明确说不支持多分离轮廓）。动作角色常有分离的身体部分（举手/衣角），`opaque_to_polygons` 会返回多个不连通的多边形（实测 cheer 有 4 个）。**只取 `polys[0]` 会丢分离部分导致角色超出轮廓**；正确做法是把所有不透明像素**求凸包**合成一个单一轮廓。代价是角色凹处空白动作时也可点（可接受）。单次凸包约 50ms（5 万不透明像素），**务必用字典缓存**同一动画/帧的结果，否则频繁切动作会卡。
20. **Control 子类的方法名别和基类撞名**：`Control` 自带 `set_anchor(side, offset, ...)`（UI 锚点用），在 Control 子类里定义同名方法会报 "The function signature doesn't match the parent" 解析错误（且是 error 不是 warning）。起名前避开 `set_anchor`/`set_anchors_*` 这类基类方法名（本项目气泡脚本改用 `set_head_anchor`）。
21. **`mouse_passthrough_polygon` 轮廓外的像素会被整块裁掉（不渲染，不只是不响应鼠标）**：本机实测，任何画在角色轮廓之外的 UI（Label、自绘 Node2D、Popup 超出轮廓的部分）直接不可见。角色自己看得见是因为它永远在自己的轮廓里。**且轮廓不随窗口移动自动更新**：窗口（桌宠）挪走后轮廓留在原位置，必须重贴才生效（main.gd `_process` 监视 `get_window().position`，一动就重贴；设轮廓一律走 `_apply_passthrough()` → `_refresh_passthrough()`，别直接赋值）。**⚠️ 轮廓内容一变就会出伪影（2026-09-06 三轮试错后的最终架构）**：主窗轮廓=**纯角色本体、内容恒定**——恒定内容的重贴（拖动/走路/喂食每帧都做）不会闪；只要轮廓扩/缩/清空就出事：① 设**空数组**→清空/恢复瞬间**全屏闪**；② UI 矩形**并入轮廓每帧跟贴**→新暴露区域被重绘出**白条**、更新慢渲染一拍把东西**裁掉一块**；③ 字母雨显示区首次并入→**白框闪一下**。**最终方案：任何 UI 一律画独立置顶透明小窗**——气泡小窗（字母雨/emoji/消息条，常驻）+ 喂食食物小窗，配置 borderless+transparent+`transparent_bg`+`mouse_passthrough=true`（整窗穿透的窗口样式标记，一次设置不涉及轮廓，桌面无遮罩死区），`gui_embed_subwindows` **启动时全局 false** 使其成为原生窗口（嵌入的子窗口会被主窗轮廓裁掉），小窗位置在 `_process` 每帧跟随主窗。因此 `_menu_rect` 并轮廓、bubble 的 `ui_changed`/`get_cover_rects` 已全部废除。顺带：Control 类控件（Label/Panel 等）在本机透明窗口里同样不渲染，气泡因此全用 Node2D `_draw()` 自绘（文字 draw_string、底板 draw_style_box）。
22. **嵌入式 PopupMenu 的 `position` 是相对父窗口的，别再加窗口位置**：嵌入模式（`gui_embed_subwindows=true`）下 PopupMenu 渲染在主窗口内部，`position` 应直接用窗口内坐标；若按原生弹窗习惯加成 `窗口位置 + 局部坐标`，窗口在原点时碰巧正确，**窗口一旦挪动菜单就双重偏移**——这是当年"菜单位置漂移、框和菜单对不上"的根因。⚠️ **2026-09-06 起 `gui_embed_subwindows` 已全局关闭**（气泡/食物小窗需要原生子窗口，见坑 21），PopupMenu 走**原生分支**（`position = 主窗位置 + 窗口内坐标`，自己有 HWND、不再被主窗轮廓裁剪，也不需要把菜单区域并进轮廓）。本坑保留作历史记录；**若将来恢复嵌入模式必须重读本坑并恢复 `_show_menu` 的分支判断**。菜单锚定角色右侧固定位置（`sprite.position + (半宽-40, -40)`），与右键点哪儿无关，并做屏幕边缘钳制。

## 七、素材

**目录结构（2026-09-06 项目清理后）**：`assets/` 只放运行必需资产；`原始素材/` 是归档区——**内有 `.gdignore`，Godot 不扫描、不导入、不打包**；`.godot/` 缓存已于 2026-09-06 手动删除过一次（清掉 sad_* 改名遗留的孤儿导入等垃圾），**下次打开编辑器会全量重导（几分钟）+ 重建 C# 程序集，属正常现象**。清理时项目总占用从 ~300MB 降到 19MB（不含重导后的 .godot）。

- `assets/animations/<动作>/<动作>_1~3.png`：**动作序列帧**（透明、372x360），8 类动画各 3 帧（idle 只有 2 帧）：idle/sleepy/cheer/cry/shy/lifted/scary/walk（scary 目录内文件原名 sad_*，2026-09-06 已统一改名为 scary_*，main.tscn 引用同步更新）。源图与切图脚本都在 `原始素材/`（见下）
- `assets/food/food.png`：喂食用荷包蛋（256x256 透明底；由 2048 原图 `原始素材/荷包蛋.png` 按 alpha 裁边+缩放生成，2026-09-06）。显示高度约 70px（main.gd `FOOD_HEIGHT`）
- `audio/`：**空文件夹**（用户创建的占位目录，推测预留给音效；代码中无任何引用；含 `.gitkeep` 以便 git 记录空目录）
- `原始素材/`（归档区）：`荷包蛋.png`（2048 原图）；`初始人物形象参考/`（人物图标_透明居中/q 版形象/全身参考 1~4——远期换装参考；`序列帧动画2.png`+`待机序列帧1.png`——**切帧源图**；`make_transparent_centered.py` 抠图脚本，依赖 numpy/PIL/scipy）；`tools/`（`slice_frames.py` 切帧脚本 + `analyze_sheets.py` 网格分析 + `preview.png` 调试预览——**从 `assets/../tools` 搬来，脚本内是旧的相对路径，再用时要改**）
- 换贴图注意：必须用已抠透明背景的图，否则穿透和视觉都会出问题

## 八、导出

- **2026-09-06 晚已重新导出**：现行产物为 `testversion.exe` / `testversion.pck`（**6.2MB**，瘦身验证生效——对比参考图未清理前的 12MB）/ `testversion.console.exe` / `data_XiaoSongLv_windows_x86_64/`，**包含全部一期优化功能**；导出路径在预设里已改为 `./testversion.exe`
- **exe、pck、test.console.exe、`data_XiaoSongLv_windows_x86_64/` 四件必须一起带走**（当前未嵌入 pck）；首次导出前需安装导出模板（编辑器 → 管理导出模板）
- 参考素材已在 `原始素材/`（`.gdignore` 屏蔽），不会被导入/打包——pck 只含真实运行资产，**无需再配 exclude_filter**
- **应用图标已配置**（project.godot `config/icon`，2026-09-06 用户在编辑器里设置）
- 当前勾选了"导出调试 + 控制台封装"（调试期方便看输出）；正式发布时两个都关掉再导一次
- 打包前记得确认脚本已保存（Godot 导出的是磁盘上的版本）

## 九、功能规划（2026-09-06 拟定）

> **2026-09-06 变更**：二期（截屏感知 + LLM + TTS）已由用户决定**取消**，9.2 仅留档勿实施。"一期优化"（喂食交互、动画/数值参数调整、UI 美化）已全部实施完毕，详见"二、当前进度"——原承载需求梳理的根目录 `需求文档.md` 已完成使命并**删除**，其内容（现状梳理、需求条目、喂食方案、历次修订）全部并入本文档对应章节。下述 9.1 数值为设计期起始值，实际值以各脚本顶部常数为准。

### 9.1 一期：桌宠本体（字母雨气泡 + 养成 + 右键菜单）✅ 2026-09-06 已实施并验收

> **实施备注（验收后回填）**：功能与下述设计一致，另有三点实现层决定——① 气泡必须 Node2D `_draw()` 自绘、菜单为嵌入式 PopupMenu（原因见坑 21/22，设计阶段未预料）；② 消息条紧贴头顶（间隙 14px）、菜单位置锚定角色右侧固定点，二者均带屏幕边缘钳制；③ 数值/气泡常数分别集中在 `nurture.gd`、`bubble.gd`、`main.gd` 顶部。**新增 UI 必须遵守坑 21/22 的轮廓与坐标规矩；运行期非必要不打印。**

> **一期不做任何台词层面的东西**（吹捧、抱怨、闲聊、劝睡全部不做），台词/文案统一放到二期由 LLM 生成；气泡一期只承担"字母雨 + 极简系统反馈"两件事。所有养成数值一律 **int 整数**，不用小数。

**① 三大数值**

| 数值 | 范围 | 初始 | 定位 |
|---|---|---|---|
| 精力 | 0~100 | 80 | 打字消耗，投喂/安静恢复，管"能动多欢" |
| 心情 | 0~100 | 60 | 互动抬升、独处下降，管"自动播哪些动画" |
| 亲密度 | 0~100 | 0 | 只涨不跌的长线值；**本期无解锁行为**，怎么用交给二期 LLM 感知 |

**② 核心循环：每 30 秒结算一次（Godot Timer tick，不逐键结算，实现简单、参数好调）**

| 该 tick（30 秒）状态 | 结算 |
|---|---|
| 活跃打字（本 tick ≥15 键） | 精力 -2；食物进度 +1，**攒满 15 份进度 → 获得 1 个食物**（库存上限 20 个；满了进度保留，有空间自动转） |
| 安静（本 tick <15 键，含睡觉循环中） | 精力 +1 缓慢回血；心情 -2 独处下降 |
| 心情 ≥80 的 tick | 每累计满 6 个 tick（=3 分钟）→ 亲密度 +1（"开心时光"被动转化） |

**③ 打字即时反应（不走 tick）**
- **敲得欢**：30 秒滑动窗口内 ≥120 键 → 播 cheer，5 分钟冷却，心情 +1（台词二期由 LLM 生成）
- **长时间不敲**：清醒状态下 3 分钟无键入 → sleepy **循环播放 = 睡觉态**（期间结算同"安静"），敲键/单击/拖动/右键唤醒

**④ 互动规则（含防刷）**

| 玩家行为 | 效果 | 防刷 |
|---|---|---|
| 单击角色 | 随机情绪动画（权重 **shy 4 : cheer 3 : cry 2 : scary 1**），心情 +3 | 10 秒冷却，冷却内只播动画不加数值 |
| 拖动/拎起 | 心情 +1 | 30 秒冷却 |
| 右键菜单"投喂一份" | 消耗 1 食物：精力 +30、心情 +5、亲密度 +2，播 cheer + 系统反馈气泡 | 精力 ≥95 拒绝（反馈"精力已满"）；没食物反馈"多敲键盘" |

- **心情 → 亲密度**：心情 ≥80 时每次单击互动额外 +1 亲密度，加上 ② 的"开心时光"被动转化，两条路并存
- ~~双击投喂~~ 已取消（投喂只走菜单）；~~凌晨劝睡台词~~ 移到二期（LLM 感知生成）

**⑤ 数值驱动的自动动画（把现在"只会随机播 sleepy"的自动池改成按数值加权）**

自动定时器（20±5 秒）到点时，情绪动画从加权池里抽（基础 sleepy 权重 3）：
- 心情 ≥60：cheer 权重 +2
- 精力 ≥60：cheer 再 +2；走路概率 ×1.5（sleepy 相对变少）
- 心情 ≤20：cry 权重 +4
- 精力 ≤15：走路概率 ×0.3；sleepy 权重再 +3

**⑥ 亲密度**：本期只积累 + 存档，无阶段、无解锁（原四阶段表作废；二期由 LLM 感知数值自己生成对应回复）。

**⑦ 状态机（优先级从高到低）**：睡觉（sleepy 循环）> 被拎起(lifted) > 走路 > 互动(情绪动画) > 待机。现有 `_on_switch_timeout` 的随机触发收编进状态机，触发前先查状态和数值（如精力低就少派走路）。

**⑧ 气泡（一期只有两样东西）**
- **字母雨（打字回显）**：每敲一个键（**只认 26 个英文字母和数字**，不用中文和其他按键）在角色上方一小块区域**随机位置**弹出一个字母，快速淡入淡出（约 0.9 秒）随即消失，来不及消失叠在一起也不影响，可轻微上飘/旋转
- **系统反馈消息条**：头顶圆角 PanelContainer + Label，队列显示、每条最少停留 2.5 秒。一期只放极简系统反馈（获得食物 / 投喂结果）；状态台词和随机闲聊的**位置先占位**，二期由 LLM 通过 `say()` 注入
- **⚠️ 中文字体坑**：消息条和右键菜单有中文 → 必须建 `SystemFont`（指向"Microsoft YaHei"）做主题字体覆盖，否则中文全是方块；字母雨只有字母数字，同用该字体即可
- 所有气泡控件 `mouse_filter = IGNORE`，绝不挡鼠标（穿透归 main 的轮廓管）
- ~~隐私模式~~ 不做（已确认不考虑）

**⑨ 右键菜单（替代系统托盘）**：Godot 做不了原生系统托盘 → **右键点角色弹 PopupMenu**（纯 Godot UI）：投喂一份 / 每日报告（今日按键数、累计按键数、陪伴时长、三数值、食物库存，用消息条展示几秒）/ 气泡开关（勾选项，控制字母雨+消息条）/ 退出（退出前存档）。**Esc 退出删除**。开机自启暂不做，菜单留位。注意：菜单要右键点在角色身上（透明区域是穿透的）。

**⑩ 存档**（`user://save.json`）：三数值 + 食物库存/进度 + 今日/累计按键数 + 今日陪伴秒数 + 日期（跨天自动清零今日计数）+ 上次保存时间。改动后延迟 5 秒合并写入 + 每 tick 兜底写 + 退出必写。**离线不惩罚**：距上次保存超 1 小时视为"你不在时它睡了"，精力回满、心情不动——桌宠是治愈向，别让用户回来看到哭脸。

**⑪ 文件划分**：`script/nurture.gd`（数值 + tick + 打字统计 + 加权池 + 存档，用信号通知 main，挂 Main 下）、`script/bubble.gd`（字母雨 + 消息条）、`main.gd` 改造（右键菜单 / 睡觉唤醒 / 喂食 / 报告 / 退出存档，`_on_global_key` 喂统计和字母雨）。**不新增 C#**（托盘方案否决，全局键盘钩子沿用现有 `GlobalKeyboardHook.cs`）。**给二期预留接口**：气泡暴露 `say(text, hold)` 方法——将来 LLM 回复直接往这里塞，一期不感知二期。

### 9.2 二期：截屏感知 + LLM + TTS

**截屏时机（事件触发，非持续监控）**

| 触发 | 条件 | 上限 |
|---|---|---|
| 手动 | 热键"看看我的屏幕" | 用户主动，不限 |
| 好奇 | 无键入 ≥10 分钟且亲密度 ≥20，它好奇你在干嘛 | 每天 ≤5 次 |
| 定时关心 | 每 60 分钟一次 | 每天 ≤8 次 |

每天总量设预算（如 12 次/天），右键菜单一键关停。

**管线**：C# GDI `CopyFromScreen` 截主屏 → 缩到长边 ~1024、转 JPEG（几百 KB）→ C# HttpClient 直发视觉 LLM（GLM-4V 类；**图不进 Godot、不落盘**）→ 回复文字传回 GDScript → `bubble.say()` + TTS 播报。请求体带角色状态（三数值、今日按键数、当前时段）+ "小松绿"人设 system prompt，它才知道用什么口吻说。

**TTS**：先用 Windows 自带 SAPI 跑通"文字→出声"（免费离线、一行代码），后续再考虑 Edge TTS（免费、音色自然）或 GPT-SoVITS 本地音色克隆（可定制小松绿专属声音，需 Python + 显卡）。播放走 Godot 音频，右键菜单加"静音"。

**选型备忘**：纯文字聊天可用 DeepSeek（便宜、无视觉）；"看屏幕"要用带视觉的（GLM-4V / GLM-4.5V / Qwen-VL）。API key 放本地配置文件，不写死进代码。对话历史只留最近几轮（桌宠轻量长挂）。**本地动画反应永远即时，不等网络**（等 LLM 时气泡显示"…"）。

**IME 提醒**：低级键盘钩子拿到的是原始按键（中文输入法下是拼音字母，不是最终汉字），气泡 v1 显示字母串即可，LLM 读得懂拼音；要抓真中文需走 UI Automation，复杂度高，暂不做。

### 9.3 待办清单 / 远期备忘

**分发优化（零环境运行 + 减小体积）——已立项，二期前后择机做：**
- 现状：mono 导出包 ~90-110MB（大头是 mono 引擎本体 exe≈96MB，素材其实只占小头），且对方机器需装 .NET Desktop Runtime 8 才能跑 C# 键盘钩子
- 路线 A（勾选项，保留 C#）：导出预设开 Self-Contained 自包含，把 .NET 运行时打进包里 → 对方零环境，代价是体积涨到 ~200MB
- 路线 B（推荐、根治）：键盘钩子改写为 C++ GDExtension，项目迁移到**非 mono 标准版 Godot** → 对方零环境 + 总包 ~40MB + 解脱 mono 编辑器约束；代价：重写钩子（Win32 API 逻辑现成）、迁移项目、放弃 C#（本项目除钩子外没用任何 C# 特性）
- 立即可做的低成本项（不改代码）：① 导出预设"资源"页加排除过滤器 `原始素材/*`、`assets/初始人物形象参考/*`、`tools/*`、`技术验证/*`——参考图约 12MB 未被代码使用，pck 12MB 可减到 ~3MB；② 关调试改用 Release 模板导出；③ 分发时打 zip/7z（exe 压缩率高，下载体积减半）
- 已否决：UPX 压壳（杀软误报率极高，"常驻桌面+全局钩子+加壳"是完美误报组合）、贴图有损压缩（省几百 KB，损画质）

- 设置界面（角色大小、置顶开关、开机自启 [写注册表 Run 键]）
- **换装系统**：亲密度毕业奖励——素材里已有贝雷帽/花篮装扮立绘参考（美术工作量大，先记不做）
- 主动聊天输入框（热键召唤）、拖拽松手回弹
- ~~小清理：删除根目录残留的 `小松绿桌宠.csproj`~~（✅ 已删除，sln 只认 `XiaoSongLv.csproj`）；~~需求文档.md~~（✅ 2026-09-06 已删除，内容并入本文档）
- ~~双击互动~~ 已定为"投喂"（仅右键菜单投喂）

### 设计原则（全程遵守）

- **每次数值变动都要有即时可感知反馈**（动画或系统反馈气泡），否则养成系统在背后默默跑，用户无感等于没做
- **所有养成数值一律整数 int，不用小数**；数值常数集中在各自脚本顶部（nurture.gd / bubble.gd / main.gd），先实跑再调参，不要一开始精算
- 隐私：一期字母雨不做隐私模式（已确认不考虑）；二期截屏要有预算和总开关、截图不落盘
- 本地功能永远即时响应，联网功能异步不阻塞

## 十、协作约定

- 用户是 Godot/编程新手：解释要一步一步、给完整可粘贴的代码；用户已接受由 Agent 直接写文件
- 排查问题的固定打法：**先加 print 拿数据，再对症下药**——本项目所有疑难杂症都是这么解的，不要凭猜连续改
- git 提交**只在用户明确要求时**进行（提交规范见第十一节）；提交信息用中文，格式「模块：改动摘要」
- 参考项目在 `D:\agentworkspace\zcode\DesktopPet-main`（Godot 4.3，xccds/DesktopPet），其架构可借鉴，但 API 行为以 4.6.1 实测为准

## 十一、版本管理（git）

- **2026-09-06 初始化本地仓库**，分支 `main`；**仅本地、无远程**（远程推送需用户另行提供仓库地址）
- **入库**：全部源码（`scenes/`、`script/`、`GlobalKeyboardHook.cs`）、工程与导出配置、`assets/`（运行贴图）、`audio/`（含 `.gitkeep` 占位保住空目录）、`原始素材/`（源图归档——`.gdignore` 只影响 Godot 扫描不影响 git，属不可再生源材料必须入库）、`AGENTS.md`、`.gitignore`
- **不入库**（`.gitignore`）：`.godot/`（编辑器缓存，打开工程自动重建）、导出产物（`*.exe`/`*.pck`/`data_*/`，随时重新导出）、C# 中间产物（`*.pdb`/`.mono/`）、系统杂项
- 首个提交内容：一期 + 一期优化完整测试开发版（喂食交互、气泡小窗架构、UI 美化、全部 bug 修复与调参）
