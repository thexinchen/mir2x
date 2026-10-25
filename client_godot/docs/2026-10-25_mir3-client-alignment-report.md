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
xvfb-run -a /home/czx/godot --path client_godot res://tests/mir3_movement_visual.tscn
```

这些是离线真实场景与输入/动作层验证；服务器持久化位置验证需另行运行联机测试。不要把一种验证范围替代另一种。
