# Mir3.dat 客户端行为对齐记录

本记录按可独立验证的行为分批维护。目标环境是 104 主机 Linux/Godot 4.7.1；Windows 开发副本同步实现。原样本是 `G:\游戏\Mir3\Mir3.dat`，不是资源目录 Data。

## 证据范围

- 原文件 SHA256：`7965910be6d980fea18dc73c9d4b366683f372cacdbfb5120e8008f4d3461c4d`。
- UPX 解包副本 SHA256：`eef5bc3ce72b8db3449389f21c367f9795dacbf919480c606717a49b052d7021`。
- 地址采用解包映像 VA，基址 `00400000`。本地证据目录：`G:\mir3\work\mir3-movement`，含 IDB、反编译和关键汇编；原样本未修改。
- 当前 Godot 对接 mir2x 服务端；原版行为通过当前协议表达。未把原 Mir3 包编号或角色内存字段直接用于 mir2x。
- 这是一项持续对照工作，不代表全部技能、交互、动画、物品或服务端规则已经还原。

## 批次 1：动作提交时复核通行

**Evidence → Finding → Path**：

1. `678228` 检查跑动的中间格和终点，`678330/678370` 区分地形与角色占用；`6DB2F0:6DB3DA–6DB429` 在实际应用本地走/跑动作前再次检查。
2. Godot 旧 `_send_move_action` 只查终点地形，只有普通地面绕障路径复核途中角色。小地图、拾取和追击的既有路径可能在计算完成后遇到新阻挡仍继续提交。
3. `Mir3Movement.can_step` 统一检查八方向一步/两步及每个跨越格；`main.gd` 在所有普通移动提交时调用。返回成功后才消费路径节点、开始 600 ms 动作节拍；失败则重算路径。
4. `_find_path` 与动作提交共用活体占用集合，尸体动作 13 不再只在某一个入口放行。原版其他角色标志尚未全部映射，不能据此声称所有特殊穿越规则已恢复。

验证：104 上 `mir3_action_validation_smoke.tscn` 检查动态中间格角色、动态地形、非法长跳和非八向移动、尸体一致性、拒绝后保持坐标/动画时间、动态重算与成功后开始节拍；`mir3_movement_smoke`、`minimap_movement_smoke` 和 Xvfb 中的实际主场景 `mir3_movement_visual` 回归通过。

## 批次 2：前向入口和阻挡终点调整

**Evidence → Finding → Path**：

1. `67849C` 的八个 switch 分支分别查询请求方向左右各 90° 范围内五个邻格，调用 `678330` 合并地形与角色判断；`67AD78:67B2FB`、`67B398:67B5F6` 在提交地面走/跑请求前使用该条件。初次近距离右键转向分支不要求它。
2. `4AB72C:4AB785–4AB7B3` 先拒绝越界目标；目标阻挡时 `4AB7E5` 将父栈帧压栈传给 `4AB2A8`。后者的 `esi=parent+0Ch` 是目标 Y，`parent+10h` 是目标 X，而不是两者相反。首候选是 `(X,Y-1)`，随后 NE、E、SE、S、SW、W、NW；`4AB71B inc ebx; 4AB71C cmp ebx,2; 4AB71F jnz 4AB2BC` 证明只检查半径 1。
3. `Mir3Movement.can_approach` 复现入口条件，避免只因身后有空格而启动反方向绕障。`WorldPathfinder.resolve_mir3_goal` 复现固定顺序的单圈调整，`main.gd:_find_ground_path` 传入真实地图边界。先选首个可进入邻格，再对它寻路；不会在该候选不可达时偷偷改选另一候选。

Linux 验证：八方向全部测试封闭前半平面与 90° 边界；阻挡目标选北、北被占用选东北、单圈全部阻挡不扩大半径、边界候选检查及越界目标拒绝。并回归第一批提交复核、小地图逐步寻路、原有三角路径测试与真实窗口长按操作。

## 批次 3：空操作不提前取消现有动作

当前移动决策对目标等于人物格返回空请求，但主场景原先先 `_cancel_movement()`，使后续空请求仍取消采矿等现有操作。现先记录按键；当前格空操作保留原操作，长按超过 300 ms 后指针改向才取消旧操作并等待已有动画完成。松键仍清按住状态，新的普通请求仍遵守前两批的通行检查。

证据区分：300 ms 与按住重新派发来自 Mir3 `65F7B8/66DB48`；“空请求不破坏现有操作”是使主场景取消时机与其既有决策和采矿回归契约一致的修复，未声称已经恢复 Mir3 全部采矿分支。实际窗口新增“当前格右键保持操作”和“按住后改向能取消旧操作并移动”两项检查。

完整 `world_action_smoke` 原先在测试地图切换后立即检查死亡输入，但可见纹理预加载此时尚未完成，遮罩仍会拦截输入。测试现等待遮罩实际消失，有 5 秒超时，不跳过死亡/复活断言。随后发现并修复上述真实空操作取消问题；104 上最终输出 `WORLD ACTION PASS`，覆盖该套测试的攻击追击、施法、采矿、拾取、死亡/地图过滤等全部后续断言。

这里的 PASS 指现有客户端测试契约，不证明这些子系统已全部与 Mir3 原程序一致。早期 Windows 的施法元数据失败未在本次 Linux 资源上复现，仍需分别管理两端资源生成与版本。

## 批次 4：NPC 对话入口节流

`67AD78:67B04E` 的 NPC 分支先清待处理移动目标；`67B05F–67B063` 拒绝长按重复派发；`67B073 cmp edx,5DCh` 与 `67B079 jbe` 证明间隔必须严格大于 1500 ms。请求前在 `67B087` 更新共享时间戳，再调用 `68F830`。被拒绝的点击不刷新时间戳，换一个 NPC 也共用该限制。

Godot `main.gd:_request_npc_dialogue` 采用相同边界与共享时间戳。真实 NPC 点击先清普通地面按住请求，再进入该入口；已提交动作的节拍不被清除，NPC 点击也不进入地面长按重发。对话里的具体菜单事件沿用原处理，不将所有菜单操作都套上入口节流。

104 验证：`mir3_npc_interaction_smoke` 检查首次请求、1499/1500/1501 ms 边界、跨 NPC 共享间隔、拒绝不延长等待、真实命中框点击、停止旧地面按住状态而保留动作节拍；原 `npc_dialog_smoke` 与完整 `world_action_smoke` 均到达 PASS。

## 批次 5：当前格左键拾取不依赖缓存

`67B26D–67B2B5` 明确比较鼠标格和人物的当前 X/Y，要求普通移动模式为空及角色就绪，随后调用 `68F984`。该函数汇编从角色 `+15h/+19h` 取位置并以命令 `3E8h` 调用发送函数，没有查询客户端地面物品列表。`689164` 进一步表明同一发送入口既能不查物品列表直接调用，也能按物品缓存查到当前格后调用。

Godot 原先只在 `ground_items` 中发现目标格时才走鼠标拾取分支；左键自身命中框又会提前返回。现对普通当前格左键采用就绪检查后请求现有 `CM_PICKUP`，并记录按住状态以保留后续改向。自身命中框只在团队指向模式处理之后排除；其他角色命中与拖放物品优先级保持原处理。移动未完成、攻击/施法动画未完成或强制动作进行时不提前拾取逻辑终点。右键当前格依旧是空请求。

验证：`mir3_current_cell_pickup_smoke` 用主场景子类计数现有拾取入口，检查自身命中框、空缓存、动作就绪、拖放优先级和按住状态。`network_current_cell_pickup_smoke` 使用既有联机物品往返夹具，物品确实落地后主动移除客户端缓存，再经 `_unhandled_input` 发左键；104 服务端返回物品，最终背包数量恢复到 10，地面条目消失。完整 `world_action_smoke` 回归通过。联机物品夹具也增加等待地图遮罩消失，避免加载阶段吞掉测试输入。

## 批次 6：服务端方向攻击与观察端方向

原版 `67AD78:67B035` 在 Shift 分支接受无选中角色的攻击；`67B169–67B266` 检查动作与攻击就绪后按指针方向入队攻击，不生成步行目标。mir2x 的 `Player::onCMActionAttack` 原先先查目标 UID，UID 为 0 时直接退出，因而只实现客户端挥刀动画不能完成这个能力。

现对 UID=0 的方向攻击检查服务器当前坐标、合法方向、存活/移动锁状态以及当前 600 ms 攻击间隔，采用服务端自己的攻击速度。服务器查询正前一格目标；若存在玩家/怪物候选则使用其位置重新核实，若为空则允许原地空挥。后续沿用 mir2x 已有近战魔法白名单、伤害目标选择和伤害派发，空 UID 不参与伤害派发。目标存活和伤害接受仍遵守现有派发规则；范围攻击沿用现有格子选择，没有添加原版服务端伤害公式。

攻击广播携带明确方向，Godot 在无 UID 的攻击上采用它；带 UID 的攻击继续按目标位置处理。新增能力并非网络结构体变更，仍使用现有 ACTION_ATTACK/ActionNode。

104 使用已有依赖配置重编译 `server` 成功并运行新服务端。双客户端测试发送两次合法方向攻击，穿插冷却内重复、错误起点和方向 0 请求；观察端严格收到两次原地攻击、速度 100、合法方向。客户端试图上报速度 500，服务器仍广播 100。测试角色位置保持不变；完整 `world_action_smoke` 回归通过。这里验证了空挥与拒绝条件，尚不替代 Shift 输入或所有范围技能伤害验证。

## 批次 7：Shift 强制攻击输入（2026-10-26）

`67AD78:67B035` 的 Shift 分支优先于普通地面行走；无选中角色时，`67B169–67B266` 使用指针方向进入攻击就绪检查和动作队列，不要求前方地形可进入。`661BF8` 清按住标志和未执行目标，`65F7B8/66DB48` 则为持续按住重新派发请求。

Godot 的普通地面输入现区分 Shift 强制攻击：左键空地原地攻击，对墙也不进入行走或绕障；Ctrl+Shift 仍优先攻击；当前格 Shift 不触发拾取；持采矿武器或地面有物品时仍优先 Shift 攻击。NPC 交互与拖放保留各自入口。命中怪物仍用原目标追击；Shift 显式命中玩家允许进入目标追击，但松鼠标或 Shift 会取消尚未执行的玩家追击路径。已提交动画保留，不会因松键回滚。

长按使用已有严格超过 300 ms 的重复门槛，实际重复间隔服从当前 mir2x 攻击动画/恢复节拍（普通攻击约 900 ms），没有用 300 ms 作为攻击频率。松开 Shift 后左键可恢复普通步行请求。

验证包括：

- 纯决策检查 Ctrl+Shift、阻挡地形、当前格和修饰键释放。
- Xvfb 实际主场景检查单次空挥、长按重复、HUD 松键、采矿/拾取优先级、普通行走恢复、Shift 玩家追击与释放取消。
- 双客户端 `--input` 模式通过真实键盘/鼠标事件驱动 Xvfb 中的角色；观察端恰好收到 3 次服务器攻击广播，方向与速度正确，角色坐标不变，松键后没有多余攻击。截图在验证主机 `/tmp/mir3-shift-network/actor.png`。
- NPC 与当前格拾取专项、完整 `world_action_smoke` 及普通移动窗口回归通过。部分 Godot 测试退出报告 ObjectDB 泄漏警告，尚未将其当作已修复的清理问题。

## 当前边界与后续工作

- 普通人物一次走 1 格、跑 2 格；原版特殊状态 3 格尚未迁移。
- 加权寻路仍采用单前沿堆式 Dijkstra；代价规则对齐，未声称等代价路线的取舍与原双前沿逐指令一致。
- 尚需继续核实：攻击/施法与移动仲裁、目标追踪、技能动作映射、服务器拒绝后的路径处理、交互修饰键、物品与场景状态。数值权威仍在 mir2x 服务端。

## Linux 复跑

在 `/home/czx/mir3/mir2x` 设置资源路径后运行：

```bash
export MIR2X_WORLD_RES="$PWD/client_godot/build/world_res"
export MIR2X_TEXTURE_RES="$PWD/build/Release/res/texture"
export MIR2X_AUDIO_RES="$PWD/client_godot/build/audio"
/home/czx/godot --headless --path client_godot res://tests/mir3_action_validation_smoke.tscn
/home/czx/godot --headless --path client_godot res://tests/mir3_movement_smoke.tscn
/home/czx/godot --headless --path client_godot res://tests/minimap_movement_smoke.tscn
/home/czx/godot --headless --path client_godot res://tests/mir3_npc_interaction_smoke.tscn
/home/czx/godot --headless --path client_godot res://tests/mir3_current_cell_pickup_smoke.tscn
xvfb-run -a /home/czx/godot --path client_godot res://tests/mir3_movement_visual.tscn
```

以上是离线真实场景与输入/动作层验证。联机物品往返测试在服务端运行且现有测试角色物品夹具可用时执行：

```bash
/home/czx/godot --headless --max-fps 60 --path client_godot res://tests/network_current_cell_pickup_smoke.tscn
```

方向攻击双客户端验证（需要本仓库标准测试账号及 104 上本机测试服务器）：

```bash
python3 client_godot/tests/run_network_directional_attack.py --godot /home/czx/godot --output-dir /tmp/mir3-directional-attack
python3 client_godot/tests/run_network_directional_attack.py --godot /home/czx/godot --output-dir /tmp/mir3-shift-network --input
```

不要把一种验证范围替代另一种。Alt 尸体交互仍需恢复；原版 `679018` 查询尸体邻域，再调用 `689210`，不是普通地面采矿分支。仍需验证方向攻击的全部范围技能/伤害场景。新发现的攻击就绪函数 `68F6F0` 使用原角色属性计算间隔，尚不能直接将当前 mir2x 的动作时长替换成它的常量。
