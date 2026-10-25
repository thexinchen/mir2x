# Godot 客户端移植手机版（Android/iOS）可行性与工作量评估

评估对象：`mir2x/client_godot`（Godot 4.7.1 版传奇2客户端）
评估日期：2026-10-21
评估方式：代码/资源/构建脚本静态审计 + 本机工具链核查（未做真机验证，文中已标注哪些结论需要真机确认）

---

## 0. 结论

**可以做，引擎层没有硬阻塞。** 这个客户端是纯 GDScript（无 C#、无 GDExtension、无原生插件），
渲染用 `gl_compatibility`，网络用内置 `StreamPeerTCP`，这三条决定了它天然能编到 Android/iOS。

**但"能跑"和"能玩"之间隔着四件事，工程量 90% 在这里：**

| # | 问题 | 现状 | 性质 |
|---|---|---|---|
| 1 | 811 MB 资源不在 pck 里，运行时按绝对路径直读 | `world_res` 带 `.gdignore`，走 `FileAccess` 直读 PNG | 必须重做打包/下载 |
| 2 | 800×600 绝对像素 UI + 固定逻辑分辨率 | 482 处 `offset_*`，`SCREEN_W/H` 写死 | 必须适配 |
| 3 | 全鼠标/键盘操作 | 右键跟随、滚轮、悬停 tooltip、B/C/S/T/F/数字键 | 必须重做触摸层 |
| 4 | 纹理缓存无上限 | `_textures` / `_texture_cache` 只增不减 | 必须加预算，否则会 OOM |

**给三个档位的判断：**

- **3–5 人日**：能装、能登录、能在手机上走动打怪（横屏 letterbox + 触摸映射 hack）。适合先做技术验证。
- **3–5 周（1 人）**：可玩的内测版 Android 包（触摸层完整 + 资源在线下载 + 基础适配 + 性能兜底）。
- **6–10 周**：可发布质量（多机型适配、弱网重连、内存/帧率达标、商店资源分发）。iOS 再加 1–2 周（需 macOS）。

---

## 1. 现状盘点（实测）

| 项目 | 数据 | 证据 |
|---|---|---|
| 引擎 | Godot 4.7.1（`config/features="4.7"`），`gl_compatibility`，2D 像素风，`default_texture_filter=0`（最近邻） | `client_godot/project.godot` |
| 代码规模 | 119 个 `.gd` / 29,133 行；98 个 `.tscn` | 统计 |
| 语言/依赖 | 100% GDScript，无 C#、无 GDExtension、无第三方插件 | 全仓扫描 |
| 资源（运行时直读） | `build/world_res` **811.4 MB / 377,535 文件**：sprites 625.5 MB/356,412、textures 180.3 MB/21,118、maps 5.7 MB/4 张 | `actor_resource.gd:59`、`world_resource.gd:128` |
| 音频 | `build/audio` **226.4 MB**：850 个 WAV（138.5 MB）+ 23 个 MP3（87.9 MB），另带 `.gdignore` | `audio_service.gd` |
| 已导入资源 | `assets/` 124.2 MB（含 15 个 TTF、UI 图、emoji），会进 pck | `build_remote.sh` |
| 网络 | `StreamPeerTCP` + 每帧 `poll()`，自研 VLQ 封包，无 asio/无线程 | `network_client.gd:165-201` |
| 分辨率 | 逻辑 800×600，`stretch/mode=canvas_items`，`aspect=keep` | `project.godot`；`game_state.gd:117-118` |
| 输入 | `InputEventMouseButton` / `InputEventKey` 混用，无任何触摸事件处理 | 101 处匹配，见 §2.3 |
| 平台 API 依赖 | 仅 `OS.get_environment`、`OS.get_executable_path`（资源回退路径）、`DisplayServer.window_set_mode`、截图调试钩子 | 无 `Thread`、无 `OS.execute`、无外部进程 |
| 构建链 | Linux 远端 `build_remote.sh`：转资源 → `--export-pack Linux` 出 `.pck`；**无 Android preset** | `export_presets.cfg` 只有 Linux |
| 本机 Android 链 | SDK 有（platforms 34/36.1、build-tools 33/34/36、NDK 25.1/29.0、JBR 21）；**`export_templates` 为空** | `%APPDATA%\Godot`、`%LOCALAPPDATA%\Android\Sdk` |

---

## 2. 逐项评估

### 2.1 引擎与语言 —— 🟢 绿灯

- 纯 GDScript 意味着不需要 NDK 交叉编译自己的代码，导出只有"引擎模板 + pck"两件事。
- `gl_compatibility` 在 Android 上走 OpenGL ES 3.0，中低端机兼容性最好；2D 不受 Vulkan 驱动差异影响。
- 没用 `Thread`、`OS.execute`、动态库加载，也就没有"桌面能跑手机崩"的常见雷区。
- 代码里已有的平台判断只有三处（`actor_resource.gd:51`、`world_resource.gd:151`、`audio_service.gd:290`），逻辑简单。
- **唯一需要注意**：Godot 4.7 比较新，Android 导出模板必须与编辑器版本严格一致（4.7.1.stable），否则 pck 版本校验会拒绝加载。

### 2.2 资源管道 —— 🟡 黄灯，工程量第 1 名

**现状机制**：`build_remote.sh` 用自研 `godotworldres` 把地图/角色/物品 ZSDB 转成海量单帧 PNG + `.m2xindex/.m2xmeta` 二进制索引，放进 `build/world_res`，
并故意加 `.gdignore` 让编辑器不去导入 37 万个文件。运行时由 GDScript 用 `FileAccess.get_file_as_bytes()` 读原始 PNG 再 `Image.load_png_from_buffer()` 解码：

```gdscript
# actor_resource.gd:50-55
candidates.append("res://world_res")
if not OS.has_feature("editor"):
    candidates.append(OS.get_executable_path().get_base_dir().path_join("world_res"))
```

**移植到手机的两个具体障碍：**

1. `OS.get_executable_path().get_base_dir()` 在 Android 上指向 APK 内部（`lib/<abi>/`）目录，不可写也不能放资源 → 这个回退分支直接失效。
2. `.gdignore` 里的文件不会被导出，`export_filter="all_resources"` 也带不走 → 现在导出的 pck 里**根本没有 world_res 和 audio**。

**好消息**：`res://world_res` 是首选项，所以只要让资源"出现在 `res://` 下"，代码零改动即可工作。

**三种打包方案对比：**

| 方案 | 做法 | 包体 | 首启体验 | 改动量 | 评价 |
|---|---|---|---|---|---|
| A. 全部塞进 pck | 去掉 `.gdignore` 或用 include_filter 强行打进去 | APK ≈ 950 MB | 装完即玩 | 小 | ❌ Play 基础包 200 MB 上限，iOS 蜂窝下载也会拦；用户流失 |
| B. 首启下载 zip + `ZIPReader` 随机读 | 资源打成单个 `world_res.zip` 放 CDN，下载到 `user://`，用 `ZIPReader` 按条目读字节 | APK ≈ 150–200 MB + 700 MB 下载 | 需下载进度页 | 中（约 100 行封装） | ✅ 推荐：不解压、不占双倍空间 |
| C. 下载后整包解压到 `user://` | 下载 zip 解压 37 万个小文件 | 同上 + 双倍临时空间 | 解压可能要 3–10 分钟 | 中 | ⚠️ 首启太慢，且小文件占 inode |

**配套优化（收益大、成本低）：**

- **音频先砍一半以上**：138.5 MB 的 WAV 转 OGG（`AudioStreamOggVorbis`），226 MB → 约 50–60 MB。`audio_service.gd` 里加一个 `"ogg"` 分支即可。
- **地图按需下载**：现在只有 4 张图（5.7 MB），正式服地图多了以后按地图 id 拆包下载，避免一次性 800 MB。
- **中期做图集重打包**：37 万个小 PNG 是"每帧一个文件"，改成"每个动作一个图集"后文件数降 1–2 个数量级，PNG 解码尖峰也会消失（见 §2.5）。这项是性能优化，不是移植必需。

### 2.3 输入 —— 🟡 黄灯偏红，工程量第 2 名

现在的交互**完全以鼠标/键盘为中心**，逐条映射如下：

| 现有操作 | 代码位置 | 触摸方案 | 难度 |
|---|---|---|---|
| 左键点地移动 / 点怪追击 / 点 NPC 对话 / 点地上物品拾取 / 挖矿 | `main.gd:370-405` | 单击直接可用（Godot 默认 `emulate_mouse_from_touch=true`） | 🟢 零成本 |
| 右键 = 跟随目标 / 走向点 | `main.gd:380-386` | 长按 300–400 ms 合成右键 | 🟡 需手势层 |
| 面板滚轮翻页（背包/技能/任务/商店/好友） | 8 个面板 `MOUSE_BUTTON_WHEEL_*` | 面板内单指拖动 + 惯性；或双指 | 🟡 逐面板改造 |
| 悬停显示物品 tooltip | `inventory_panel.gd` `mouse_entered` | 改为"点击选中后显示 2 秒"或"长按查看" | 🟡 交互语义要重定 |
| 双击标题栏最小化窗口 | `control_panel.gd:329` | 双击天然可用（触摸双击会生成 double_click） | 🟢 |
| 面板拖动/改变大小 | `closable_panel.gd:34` | 单指拖动可用 | 🟢 |
| `B`背包 `C`属性 `S`技能 `T`队伍 `F`好友 `ESC`回中 `TAB`拾取 `Enter`聊天 `1-6`快捷栏 | `main.gd:268-301`、`443-463` | **必须新增屏幕按钮组**（6–8 个）+ 快捷栏点击 | 🔴 新 UI |
| 聊天输入（中文） | `control_panel.gd:443` | 点击输入框弹虚拟键盘；中文依赖系统 IME，需真机验证 | 🟡 |
| 队伍旗标需要鼠标位置 | `main.gd:207`、`_update_team_flag_cursor` | 改成"点选目标" | 🟡 |

**关键点**：传奇的核心操作（点地走、点怪砍、点 NPC 说话、点地捡物）恰好都是"左键"，这在手机上就是"点屏幕"，
所以**核心战斗循环天然可玩**，真正要补的是"右键语义 + 键盘替代 + 滚轮替代"这三块。这是移植里少见的利好。

### 2.4 显示与 UI 适配 —— 🟡 黄灯

- 现在 `aspect="keep"`：800×600（4:3）等比缩放，20:9 手机上左右各留约 15% 黑边。**这是唯一零代码改动的方案**，观感"原味"但黑边明显。
- 想全屏就必须动渲染层：`world_renderer._draw()` 用常量 `SCREEN_W/SCREEN_H` 做视野裁剪（`world_renderer.gd:188-189`、`1589`），
  `game_state` 用常量算相机居中（`game_state.gd:780`、`824-829`）。改成取 `get_viewport_rect().size` 大概 10 处调用点，**工作量不大**。
- 真正麻烦的是 HUD：底部控制栏根节点写死 `offset_right=800 / offset_bottom=152`（`control_panel.tscn`），全项目 **482 处** `offset_*`。
  全屏后底部栏要么三宫格拉伸（左右角 + 中间平铺），要么居中留边。这块是纯体力活 + 美术配合。
- 另有两处具体项：
  - `window/handheld/orientation=1`：按 Godot 枚举（0=横屏、1=竖屏）当前是**竖屏锁定**，横屏需改 `0`（横屏）或 `4`（传感器横屏）。建议真机确认一次。
  - 字号普遍 11–15 px 且是像素风点阵字体，6.7" 屏上物理尺寸偏小；要么提高 DPI 缩放，要么给"大字号 HUD"档。
  - 刘海/挖孔安全区未处理（`DisplayServer.get_display_safe_area()`）。

### 2.5 性能与内存 —— 🟡 黄灯（必须真机数据）

| 风险 | 细节 | 缓解 |
|---|---|---|
| 纹理缓存无上限 | `actor_resource.gd:22` `_textures`、`world_resource.gd:118` `_texture_cache` 都是只增不减的 `Dictionary`，装着 `ImageTexture` | 加 LRU + 像素预算（如 256 MB），`ImageTexture` 释放后显存归还 |
| 运行时 PNG 解码尖峰 | 每个动画帧是独立 PNG，首次遇到某种怪要连续解 8 方向×N 帧，每次 `load_png_from_buffer` 在手机上 1–3 ms | 进图时按视野预取；中期改图集/KTX2（ASTC） |
| 每帧绘制调用多 | 单 `CanvasItem._draw()` 里逐 tile / 逐 actor `draw_texture`，800×600 约 250 个 tile + 数十 actor，纹理会话切换多 | 已在 `gl_compatibility` 下自动批处理；偏低端机建议限 30 fps |
| GDScript 每帧遍历 | `main.gd:184-207` + `world_renderer._draw()` 全量遍历 `game_state.creatures` | 手机上先测；必要时把排序/裁剪结果缓存到"视野变化才重算" |

已有 `fps_label`（`main.gd:360`）和 `--draw-hp-bar` 之类的调试开关，真机取数很方便。

### 2.6 网络与服务器 —— 🟢 绿灯 + 小改

- `StreamPeerTCP` 在主线程每帧 `poll()`，Android/iOS 均原生支持，无需中间件；服务器端**完全不用改**。
- 需要补的三件事：
  1. **服务器地址可配**：现在只读 `ProjectSettings` 的 `network/server_host=127.0.0.1`（`network_client.gd:195`），手机上必然连不上。改成 `user://server.cfg` + 登录页输入，或按渠道预置。
  2. **弱网/切后台重连**：现在只在状态变化时发信号（`network_client.gd:165-177`），没有自动重连与"断线保留进度"策略。手机会频繁切后台，这块不做体验会很差。
  3. **超时提示**：`_expire_responses()` 已有，够用。
- 明文 TCP + 7000 端口无加密，公网暴露有被扫的风险，移动端建议顺手加个连接层校验（可选）。

### 2.7 构建链与发布 —— 🟡 黄灯

- **本机可编 Android**：JDK 有（Android Studio JBR）、SDK 有（platforms 34/36.1 + NDK）、缺 **Godot 4.7.1 导出模板**（需下载 ~1 GB）与 debug keystore（编辑器可自动生成）。
- 现有 `build_remote.sh` 只产 `.pck`，需要新增 `Android` preset 与"模板 + pck → APK/AAB"的步骤；建议直接接进现有远端构建机（Linux 也能编 Android，SDK 装好即可）。
- **iOS**：必须 macOS + Xcode。且 `gl_compatibility` 在 iOS 上走的是 Apple 已弃用的 OpenGL ES，稳妥路径是切 Mobile renderer（Vulkan/MoltenVK）——**这条需要单独验证 2D 表现**，不能假设零成本。
- **发布合规**：Google Play 基础包 200 MB 上限，811 MB 资源必须走 Play Asset Delivery 或自家 CDN 首启下载。另外素材来自原版传奇2，公开上架存在版权/法务风险，实际多半只能内部或私服渠道分发——这点建议先确认发行范围再决定投入。

---

## 3. 里程碑与工期（单人体感，含自测，不含美术重做）

| 里程碑 | 内容 | 人日 |
|---|---|---|
| M0 环境打通 | 装 4.7.1 导出模板、配 SDK/keystore、加 Android preset、打出第一个能装能启动的 APK | 1–2 |
| M1 资源可加载 | `user://world_res` 候选 + 首启下载/进度/校验/断点；音频转 OGG | 3–5 |
| M2 触摸可玩 | 手势层（长按=右键、滑动=滚动）、屏幕按钮组、tooltip 语义、面板触摸回归、虚拟键盘/中文输入 | 5–8 |
| M3 显示适配 | 动态视野裁剪 + 相机、HUD 三宫格、安全区、字号档、横屏锁定 | 4–7 |
| M4 性能与稳定 | 纹理 LRU/预取、限帧、内存监测、3–5 台真机矩阵、发热与耗电 | 5–10 |
| M5 发布 | 签名、AAB/Asset Pack 或 CDN、崩溃上报、灰度 | 3–5 |
| **合计（Android 可发布）** | | **21–37 人日 ≈ 6–10 周** |
| iOS 追加 | Mac 环境、Mobile renderer 验证、证书/审核 | +5–10 |

如果只做"内测可玩"，M0+M1(简化为手动侧载)+M2(精简) 约 **8–12 人日**。

---

## 4. 建议路线：先花 3 天验证，再决定投入

**第 1 阶段（技术验证，3–5 人日，强烈建议先做）**

1. 装 Godot 4.7.1 导出模板，配 Android SDK，加 `Android` preset（`orientation=sensor_landscape`），出 debug APK。
2. 资源先用最土的办法：`build/world_res` 打包成 zip，`adb push` 到 `/sdcard/Android/data/<pkg>/files/`，代码里给 `world_res` / `audio` 各加一个 `user://` 候选（约 10 行）。
3. 借 Godot 默认的"触摸模拟鼠标"，先用单击跑通：登录 → 进图 → 点地走 → 点怪砍。
4. 加一个 300 ms 长按 → `MOUSE_BUTTON_RIGHT` 的手势，验证右键跟随/移动。
5. 真机看三组数：进图内存峰值、走路/打怪的 fps、切后台再回来的表现。

**这一步的产出决定后面值不值得做**：如果中端机 800×600 能稳定 40–60 fps、进图内存 < 600 MB，那就按 §3 走；如果掉到 20 fps 或频繁 OOM，就要先做图集/KTX2 重打包（+2–3 周）再谈适配。

**第 2 阶段**：正式的触摸层与 UI 适配（M2/M3）。
**第 3 阶段**：性能、弱网、发布（M4/M5）。

---

## 5. 需要先拍板的三个问题

1. **平台范围**：只 Android，还是也要 iOS？（iOS 会牵出"必须换渲染后端 + 需要 Mac"的额外验证）
2. **发行方式**：内测直发 APK（资源走自家 CDN 下载），还是上架商店（必须 Asset Pack + 合规评估）？
3. **画面取舍**：接受"横屏 4:3 原味 + 左右黑边"（省 5–7 人日），还是要真正的自适应全屏（HUD 要重排）？

---

## 附录 A：关键改动点索引

| 用途 | 文件:行 |
|---|---|
| 逻辑分辨率常量 | `client_godot/scripts/game/game_state.gd:117-118`、`world_renderer.gd:9-10` |
| 视野裁剪（用常量） | `world_renderer.gd:186-193`、`:1589` |
| 相机居中计算 | `game_state.gd:771-829` |
| 资源根路径解析 | `actor_resource.gd:45-56`、`world_resource.gd:145-157`、`audio_service.gd:283-293` |
| 纹理加载与缓存 | `actor_resource.gd:59-74`、`world_resource.gd:128-142` |
| 鼠标输入总入口 | `main.gd:232-301`、`:370-405` |
| 面板热键表 | `main.gd:63-68`、`:288-301` |
| 网络连接参数 | `network_client.gd:165-201` |
| HUD 根节点尺寸 | `scenes/game/control_panel.tscn`（`offset_right=800`、`offset_bottom=152`） |
| 导出配置 | `client_godot/export_presets.cfg`（当前仅 Linux） |

## 附录 B：待真机验证清单

- [ ] `window/handheld/orientation=1` 实际是竖屏还是横屏（改 `4` 传感器横屏）
- [ ] 虚拟键盘能否弹出、中文 IME 能否输入（登录/聊天）
- [ ] 长按 300 ms 合成右键是否与"点地移动"冲突（误触跟随）
- [ ] 触摸下 `mouse_entered` 型 tooltip 是否会卡住不消失
- [ ] 中端机（骁龙 6xx/天玑 700 级）800×600 静帧/战斗帧率
- [ ] 连续换图 20 次后的内存曲线（验证缓存无上限的真实影响）
- [ ] 切后台 5 分钟后回来，TCP 是否已断、有无重连
- [ ] 4:3 平板 / 20:9 手机 / 折叠屏 三种屏幕的 HUD 观感
