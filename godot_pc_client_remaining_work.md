# Godot PC 客户端：未完成 / 未完善工作盘点

盘点对象：`mir2x/client_godot`（Godot 4.7.1，分支 `br_godot`，最新提交 `86bd909`）
盘点日期：2026-10-21
方法：工作区 diff 审计 + 协议/资源/场景静态比对 + 与 C++ 原版源码对照 + 运行日志复核
（未跑真机/真服验证的部分已标注）

---

## 0. 结论摘要

主干已经相当完整，不是"半成品"：

- **协议层无缺口**：`common/src/servermsg.hpp` 的 `SMType` 枚举里，除哨兵 `SM_END` 外**全部 76 个消息都有解析属性**（`network_client.gd:921-1000`），未知消息才会 `push_error("暂不支持服务器消息")`。
- **资源引用无断链**：全项目 394 个 `res://` 引用，缺失的只有 `res://world_res`、`res://audio` 两个按设计由外部注入的运行时目录。
- **回归资产厚**：73 个 `tests/*.tscn`、15,479 行测试脚本；16 个面板全部有 smoke。

真正的"未完成"集中在四类，按优先级：

| 类别 | 数量 | 性质 |
|---|---|---|
| ① 工作区里正在改、未提交未回归的特性 | 2 个特性 / 6 个文件 | **含 1 个方向可疑的改动，风险最高** |
| ② 有界面无逻辑的空壳面板 | 3 个（拍卖/行会/坐骑） | 与原版 C++ 一致，但功能确实没有 |
| ③ 健壮性 / 工程性缺口 | 10 项 | PC 版自身欠账，影响长期维护与线上问题定位 |
| ④ 细粒度视觉/交互差异 | 3 项 | 低优先，需人工比对截图 |

---

## 1. ① 进行中未提交的改动（最高优先级）

`git status`：4 个产品文件 + 2 个测试文件处于修改未提交状态（+88/−31 行）。

### 1.1 UID 记录 ID 偏移改动 —— ⚠️ 方向可疑，按现状发布会造成全量错配

改动内容（`game_state.gd`、`main.gd`、`npc_chat_panel.gd`）：

```gdscript
# 旧（已提交）
func _map_id_from_uid(map_uid: int) -> int:
    # UID layout matches uidf::getUID(): the 24-bit record ID starts at bit 35.
    return (map_uid >> 35) & 0xFFFFFF

# 新（工作区）
const UID_RECORD_ID_BIT_OFFSET := 32
func uid_record_id(uid: int) -> int:
    # Mirrors common/src/uidf.cpp: the 24-bit record ID occupies bits 55..32.
    return (uid >> UID_RECORD_ID_BIT_OFFSET) & UID_RECORD_ID_MASK
```

**与权威实现矛盾**。`common/src/uidf.cpp` 的布局是：

```cpp
constexpr static size_t reservedBitWidth = 1;
constexpr static size_t  uidTypeBitWidth = 4;     // bits 62..59
constexpr static size_t       idBitWidth = 24;
constexpr static size_t   idBitOff = 64 - 1 - 4 - 24;   // = 35，即 bits 58..35
uint32_t getMonsterID(uint64_t uid){ return (uid & idBitMask) >> idBitOff; }  // 右移 35
```

取 `buildMapUID(1, 0)` 的真实值 `0x1000000800000002` 验证：
- `>> 35 & 0xFFFFFF` → **1**（正确）
- `>> 32 & 0xFFFFFF` → **8**（错误）

即按当前工作区改动，地图 1 会被解成 8，怪物/NPC 的 `monster_id` / `npc_id` 全部变成 8 倍值，直接导致怪物外观、名字、NPC 对话全错。

**更麻烦的是新加的测试 fixture 本身不合法**：

```gdscript
# tests/account_flow_smoke.gd
var production_map_uid := 0x080000010000000D
if GameState.call("_map_id_from_uid", production_map_uid) != 1 ...
```

`0x080000010000000D` 的类型字段 `(uid >> 59) & 0xF = 1`，是 `UID_COR`（核心对象），不是 `UID_MAP`（=2）；任何真实地图 UID 都不会长这样。所以这条断言既不能证明旧代码错，也不能证明新代码对。

历史佐证：`>> 35` 是 `82810e4 修复Godot好友聊天自身身份` 引入的正确写法，现在被改回 `>>32` 属于回退。

**收尾动作**：用 `uidf::buildMapUID/buildMonsterUID` 的真实算式造 fixture（含类型位），对真实服务器抓一次 `SM_ACTION` 的 uid 解一次，确认后再决定保留/回滚。

### 1.2 地图加载进度重做 —— 功能生效但边界没收干净

改动（`main.gd` + `world_renderer.gd`）：`load_map()` 不再接收进度回调，改为 `_preload_visible_map_textures()` 在 40% 之后逐格预取视野内纹理直到 100%；新增 `world_renderer.loading_map` 作为绘制门闸；`_set_map_loading_progress()` 里删掉了 `RenderingServer.force_draw()`。

未收干净的四处：

1. **off-by-one**：`for y in range(y0, y1)` 少遍历最后一行，而 `total_grid_count = (y1 - y0 + 1) * (x1 - x0 + 1)` 按含 `y1` 计算 → 自算进度永远到不了 60%（只能靠末尾 `_on_map_load_progress(100, ...)` 强行兜底），进度条会有"卡在 90 多突然 100%"的观感。
2. **预取窗口写死 1200×1200 像素**（`MAP_PRELOAD_WINDOW_WIDTH/HEIGHT`），而运行配置允许 800×600 ~ 1280×800 的窗口；1280 宽时视野右侧 80px 未被预取，第一帧仍会解码缺帧。
3. **解码在主线程同步跑**，只在"百分比整数变化"时 `await process_frame` 让出一帧；一个 1200×1200 窗口约 25×37 个格、每格又带 0/1 层地表物件，单帧可能连续解上百张 PNG → 加载期掉帧。
4. 相关常量 `MAP_LOADING_PROGRESS_STEP_SECONDS` / `_map_loading_progress_samples` 被删，`PANELS.md`、`progress.md` 里对"逐格进度"的描述已过期。

### 1.3 Windows `frame_post_draw` 死等 workaround

```gdscript
await get_tree().process_frame
RenderingServer.force_draw()
```
只在 Windows/RDP + Compatibility 渲染器上验证过；Linux 上与原来的 `await RenderingServer.frame_post_draw` 语义不同（少等一帧绘制）。需要两端各回归一次。

### 1.4 测试侧配套改动

- `account_flow_smoke.gd`：`resume_message_dispatch()` 由测试直接调用改为"等一帧，断言主场景已自行恢复"——这是把测试从"驱动产品"改成"观察产品"，方向正确，但依赖 1.3 的时序，需要与 1.3 一起提交。
- `map_loading_smoke.gd`：新增"纹理缓存非空"断言，用于证明预取生效；对上面 1.2 的 off-by-one 没有覆盖。

---

## 2. ② 有界面无逻辑的空壳面板

| 面板 | 现状证据 | 协议支持 | 与原版 C++ 对照 |
|---|---|---|---|
| 拍卖 `auction.tscn` | 720×440 仅一张背景 `00001400.png` + `closable_panel.gd`（53 行通用关闭/拖动），**无专属脚本、无测试** | `clientmsg.hpp` / `servermsg.hpp` 中**完全没有 AUCTION 消息** | `ImAcutionBoard` 同样只画背景；原版也未实现 |
| 行会 `guild.tscn` + `guild_panel.gd` | 脚本仅 26 行，只有滑条拖动与 knob 位置计算，无成员列表、无公告、无操作按钮逻辑 | 无 GUILD 消息 | `ImGuildBoard` 八个功能按钮回调全为空，只有关闭与滑条有效 |
| 坐骑 `horse.tscn` | 场景有 Up/Down/Hide/Show/Close 五个按钮，但 `main.gd` 只做面板开关；**无 `send_horse_*` 任何上行** | 无 HORSE 消息 | `ImHorseBoard` 四个动作按钮回调为空，只有关闭生效 |

**判断**：这三处不是 Godot 移植缺陷，而是"原版就没做"。但它们客观是"客户端未实现功能"，且短期无法补——**要补必须先加服务端协议**（`CMType`/`SMType` + 两端 handler），工作量在服务端。

`luaEditor` 同理：`control_panel.gd:507` 打印 `">> Lua 编辑器尚未实现"`，与 `processrun.cpp:1151` 的 `addCBLog(CBLOG_ERR, u8">> Lua editor not implemented yet")` 逐字对应，属刻意保持。

---

## 3. ③ 健壮性 / 工程性缺口

按影响排序：

1. **没有 CI**。仓库无 `.github/`，73 个 smoke 只能手工或在远端 SSH 跑；且其中大量测试靠"截 PNG 人工看"判定（`MIR2X_*_SCREENSHOT` 环境变量驱动），无法在 PR 上自动卡口。
2. **游戏内断线无任何处理**。`connection_changed` 只有 `login.gd:20` 接了；`main.gd` 完全没接，`NetworkClient` 也只发信号（`network_client.gd:169-177`）。断线后玩家卡在静止的世界画面，没有提示、没有回登录入口、没有重连。
3. **服务器地址只能改工程**。`network_client.gd:195` 只读 `ProjectSettings.network/server_host`（默认 `127.0.0.1`），登录页没有地址输入，`run_client.*` 也不透传参数。换服=改 `project.godot` 重新打包。
4. **资源缺失是静默降级**。`actor_resource.frame()` / `world_resource.texture()` 找不到 PNG 就返回 `{}`/`null`，画面上就是不显示；BGM 缺失只 `push_warning`。没有占位图、没有"资源不完整"提示。更极端的情况见 8/20 日志：字体文件未被打进包时，`preload` 失败会连锁 `Parse Error`，一次刷出 40 条 ERROR 并让 `world_renderer.gd`、`player_state_panel.gd` 等脚本整体加载失败。
5. **纹理缓存无上限**。`actor_resource._textures`（`actor_resource.gd:22`）、`world_resource._texture_cache`（`world_resource.gd:118`）都只增不减，装着 `ImageTexture`。PC 上表现为长时间挂机/换图内存单调上涨。
6. **退出时仍有 ObjectDB 泄漏警告**。`progress.md` 记录：世界动作回归剩 6 个、打包态剩 4 个；曾专门消除联机态 2 个，但未归零。
7. **单体大文件**。`main.gd` 2,823 行、`world_renderer.gd` 1,939 行、`friend_chat_panel.gd` 733 行；测试侧 `magic_effect_smoke.gd` 97 KB、`world_action_smoke.gd` 220 KB。新增行为的落点越来越难找。
8. **无落盘日志**。客户端不写日志文件，只能靠启动脚本重定向 stdout/stderr；出问题要复现就只能开截图环境变量。
9. **版本签名与 CMakeCache 强绑**。`network_client.gd:811` 用 `res://assets/generated/build_signature.txt` 与服务端比对，签名由 `build_remote.sh` 从 `CMakeCache.txt` 提取。只改客户端不重编服务端 → 登录直接被拒（只能用 `--disable-version-check` 绕过），本地开发摩擦大。
10. **Windows 启动链路脆弱**。`run_client.bat` 依赖本机安装的 Godot（WinGet 目录探测），每次启动都先跑一遍 `--headless --editor --quit` 做导入；机器上没装 Godot 或版本不匹配就跑不起来。

---

## 4. ④ 细粒度视觉/交互差异（低优先，需复核）

来自 `findings.md`（2026-08-03）尚未闭环、且当前代码里看不到对应实现的点：

1. **好友搜索建议缺"匹配子串红色高亮"**。C++ 把命中的 ID/名字片段在 `x=33,y=8` 处染成分段红色；Godot 现在整行是单个白色 Button 文本（`friend_chat_panel.gd` 无 highlight 切分逻辑）。
2. **陌生人操作条几何**。C++ 是固定 54px 圆角 alpha64 面板、文本 `(8,6)`、按钮 `y=27`；Godot 用 VBox/HBox 自适应，没有显式内容边距，视觉只在"子节点数量"层面被测试覆盖。
3. **小地图两处字体**（坐标提示 vs 缩放百分比）历史上用了不同字体资源，`findings` 记录过一次修正，建议重新截图比对确认没有回归。

---

## 5. 建议收尾顺序

| 优先级 | 事项 | 判定标准 |
|---|---|---|
| P0 | 处理 1.1 UID 改动 | 用 `uidf` 真实算式造 fixture；真服抓一个 `SM_ACTION`/`SM_STARTGAMESCENE` 的 uid 解码正确；`account_flow_smoke` + `world_action_smoke` 通过 |
| P0 | 处理 1.2 地图进度 | 修 off-by-one；预取窗口按 `get_viewport_rect()` 算；`map_loading_smoke` 增加"最后一次回调必须是 100"的断言 |
| P1 | 断线处理 | `main.gd` 接 `connection_changed` → 提示 + 回登录 + 可选自动重连 |
| P1 | 服务器地址可配 | 登录页输入或 `user://server.cfg`，不重新打包即可换服 |
| P2 | 纹理缓存上限 | LRU + 像素预算；长挂机内存曲线平坦 |
| P2 | 清 ObjectDB 泄漏 | 测试退出时 0 warning |
| P3 | CI | headless 跑全部 73 个 smoke，截图类降级为产物 |
| P4 | 空壳面板 / 视觉差异 | 需服务端协议或明确文档标注"与原版一致" |

---

## 附录：本次盘点的客观数据

| 指标 | 数值 |
|---|---|
| 分支/提交 | `br_godot` @ `86bd909`（2026-08-22 前后） |
| 工作区未提交 | 4 产品文件 + 2 测试文件，+88/−31 |
| GDScript | 119 文件 / 29,133 行（含测试） |
| 场景 | 98 个 `.tscn`，其中面板 15 个、测试 73 个 |
| 协议覆盖 | `SMType` 有效消息 76 个，解析属性表 76 个（缺口 0） |
| 资源引用 | 394 个 `res://`，断链 0（仅 `world_res`/`audio` 两个设计上的外部目录） |
| 测试 | 73 个测试场景 / 15,479 行；无 CI |
| 运行日志遗留 | `godot-run.stderr.log` 40 条 ERROR（字体未打包导致的级联解析失败，8/20）；Windows 日志有 WASAPI 设备告警（环境相关） |
