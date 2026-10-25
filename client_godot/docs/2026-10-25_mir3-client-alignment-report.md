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

## 当前边界与下一批

- 普通人物一次走 1 格、跑 2 格；原版特殊状态 3 格尚未迁移。
- 下一批核实并恢复 `67849C` 的前向五邻格入口条件，以及 `4AB2A8` 的阻挡终点单圈调整。
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
