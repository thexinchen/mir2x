extends Node

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var thrust: int = resources.magic_id("刺杀剑术")
	var physical: int = resources.magic_id("物理攻击")
	var charged: int = resources.magic_id("烈火剑法")
	var half: int = resources.magic_id("半月弯刀")
	GameState.player_uid = 101
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.learned_magic = [{"magicID": thrust}]
	GameState.creatures.clear()
	GameState.magic_keys = {thrust: 49}
	var event := InputEventKey.new()
	event.keycode = KEY_F1
	event.pressed = true
	_expect(main.call("_try_magic_key", event), "F1 consumes learned thrust shortcut")
	_expect(bool(main.get("_swing_magic").get(thrust, false)), "thrust shortcut enables persistent mode")
	_expect(main.call("_consume_attack_magic_id", 3) == physical, "empty second tile uses normal attack")
	GameState.creatures[201] = {"type": 1, "x": 12, "y": 10, "action_type": 2}
	_expect(main.call("_consume_attack_magic_id", 3) == thrust and main.call("_consume_attack_magic_id", 3) == thrust, "live second-tile target selects thrust without consuming toggle")
	GameState.creatures[201].action_type = 13
	_expect(main.call("_consume_attack_magic_id", 3) == physical, "corpse does not activate thrust")
	GameState.creatures[201].action_type = 2
	GameState.creatures[201].type = 3
	_expect(main.call("_consume_attack_magic_id", 3) == physical, "NPC does not activate thrust")
	GameState.creatures[201].type = 2
	_expect(main.call("_consume_attack_magic_id", 3) == thrust, "live player in attack line activates thrust")
	GameState.creatures[201].y = 11
	_expect(main.call("_consume_attack_magic_id", 3) == physical, "off-axis target does not activate thrust")
	GameState.creatures[201].y = 12
	_expect(main.call("_consume_attack_magic_id", 4) == thrust, "diagonal second tile activates thrust")
	GameState.creatures[201].y = 10
	main.get("_swing_magic")[half] = true
	_expect(main.call("_consume_attack_magic_id", 3) == thrust, "thrust takes priority over persistent half-moon")
	main.get("_swing_magic")[charged] = true
	_expect(main.call("_consume_attack_magic_id", 3) == charged and main.call("_consume_attack_magic_id", 3) == thrust, "charged sword takes priority once, then thrust resumes")
	main.set("_next_strike", true)
	_expect(main.call("_consume_attack_magic_id", 3) == resources.magic_id("攻杀剑术"), "scheduled strike takes priority over thrust")
	main.call("_send_attack_action", 0, Vector2i(12, 10))
	_expect(GameState.player_action_type == 7 and GameState.player_action_magic_id == thrust and GameState.player_direction == 3, "directional attack carries thrust into real local action path")
	main.call("_try_magic_key", event)
	_expect(not bool(main.get("_swing_magic").get(thrust, false)) and main.call("_consume_attack_magic_id", 3) == half, "second shortcut disables thrust and restores persistent fallback")
	main.get("_swing_magic")[thrust] = true
	GameState.learned_magic.clear()
	_expect(main.call("_consume_attack_magic_id", 3) == half, "stale toggle cannot select an unlearned thrust")
	if failures.is_empty(): print("MIR3 THRUST PASS: shortcut toggle, live two-tile line, diagonal, corpse/NPC/off-axis rejection, priority, persistent mode and real attack dispatch")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
