# 人物受击后仰对比（2026-10-26）

原始对象：G:/游戏/Mir3/Mir3.dat；分析使用既有解包样本Mir3-unpacked.exe（SHA256 eef5bc3ce72b8db3449389f21c367f9795dacbf919480c606717a49b052d7021）。本次IDA会话644d6dd0。当前Godot基线00bb783。

## 已核实

- 原6DB2F0的动作31分支（6DB4AB–6DB51B）保留位置与朝向，触发现有护盾受击段；随后进入动作初始化。6DE6E0普通分支6DF427/6DF42C选择人物帧表偏移0xB4；两张人物表72789C/727A00该记录均为3帧、方向间隔7、帧间隔100ms。普通分支与当前Godot motion15、3帧、speed100时每帧100ms一致。特殊分支使用0xFC，本次未完整展开，不推广为所有状态都一致。
- Godot main._handle_action_data对普通本机预测移动收到动作11，会立即切受击、把action_from设为逻辑终点；world_renderer._action_draw_grid对非移动动作直接返回终点。因此半步移动会跳至终点，摄像机再追随，可能表现为后仰时位置/画面抽动。
- 同一入口再次收到动作11会重置player_action_started_ms；连续间隔短于300ms时可反复从第一帧开始。尚未捕获用户本次战斗的真实报文频率，不能认定用户遇到的一定是此条件。

## 104复现

临时离线探针通过真实main处理入口注入受击，不连接服务器、不操作玩家账号；三百毫秒的半步移动绘制位置(10.5,10)在受击后变为(11,10)。122ms后再注入受击，开始时间更新122ms，动作总时长0.3秒。日志/tmp/mir3-hit-comparison.log。脚本保存在G:/mir3/work/mir3-movement/hit_comparison_probe.gd和.tscn；远端临时场景测试后清理。

这些证据证明当前实现的跳格和重启动作条件，不证明用户画面发生时的实际条件。既有world_action_smoke只检查受击后逻辑位置/朝向及护盾切段，没有检查移动插值连续性。原6DB054有动作队列追加机制，但本次尚未完整证明每一种受击消息进入该队列及其打断优先级；不能据此直接替换全部动作调度。原消息31的684718还处理HP与伤害文字，不能只按同号认作当前ACTION_HITTED的完整协议。

本次未改玩法参数，尤其未凭观感修改3帧/100ms。下一步根据站立、走路或连续受击的具体场景，补充实际帧/报文采样，确认原动作调度后修复。

## 受击完成后的额外等待修复

用户进一步描述后仰延时、卡住约三分之一秒。发现确定的时钟不一致：绘制使用Time.get_ticks_msec，而main._process把限幅到1/30秒的motion_delta传入受击恢复计时。慢帧下图像已结束，输入锁仍未结束。现仅对本机动作11按同一开始时间和真实经过时间计算剩余时长；不改三帧100ms、不改走路限幅、不改受击队列优先级。后仰开始前的延迟尚未通过真实战斗采样归因，不声称全部症状消失。

104新增hero_hit_recovery_clock_smoke，模拟150ms仍应保持受击、350ms必须结束，但每次只提供1/30秒的运动增量。旧版明确失败于动画结束仍等待；新版通过，self_server_move_queue_smoke亦通过。日志/tmp/mir3-hit-clock-before.log、/tmp/mir3-hit-hero_hit_recovery_clock_smoke.log和/tmp/mir3-hit-self_server_move_queue_smoke.log。没有变更C++或重启服务器。
