extends Node

const Protocol = preload("res://scripts/network/protocol.gd")

const MAP_UID := 1 << 35
var main: Control
var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = MAP_UID
	GameState.player_map_id = 1
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_action_type = 2
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.creatures.clear()
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	_expect(main.call("_load_world_map", 1), "map fixture loads")
	var thrust: int = main.get("_resources").magic_id("刺杀剑术")
	main.set("_last_magic_request_ms", -500)
	main.set("_last_impulse_magic_ms", -3000)
	GameState.update_creature(808, {"uid": 808, "type": 2, "x": 11, "y": 10, "action_type": 2})
	_deliver(808, MAP_UID, 6)
	_expect(_clock() == -500, "remote relocation does not gate local commands")
	_deliver(808, 24 << 35, 6)
	_expect(_clock() == -500, "foreign-map relocation is ignored")
	var before := Time.get_ticks_msec()
	_deliver(101, MAP_UID, 6)
	var relocation_clock := _clock()
	_expect(relocation_clock >= before and relocation_clock <= Time.get_ticks_msec(), "own space action stamps receive time")
	_expect(not main.call("_magic_ready", thrust, relocation_clock + 499) and main.call("_magic_ready", thrust, relocation_clock + 500), "self relocation activates exact command gate boundary")
	_expect(main.get("_last_impulse_magic_ms") == -3000, "current space action ID6 is not confused with original impulse message6")
	main.set("_last_magic_request_ms", -500)
	GameState.player_action_type = 2
	_deliver(101, MAP_UID, 3)
	_expect(_clock() == -500, "ordinary server walk does not inherit relocation clock reset")
	before = Time.get_ticks_msec()
	main.call("_switch_player_map", MAP_UID, {"x": 10, "y": 10})
	_expect(_clock() >= before, "scene location reset stamps after map setup")
	main.set("_last_magic_request_ms", -500)
	before = Time.get_ticks_msec()
	_deliver(101, 24 << 35, 2)
	_expect(GameState.player_map_id == 24 and _clock() >= before, "own cross-map action activates map-reset gate even without space action type")
	if failures.is_empty(): print("MIR3 MAGIC POSITION GATE PASS: self-space clock, 499/500 boundary, remote/foreign/walk isolation, map-change reset and impulse-clock separation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _clock() -> int:
	var value: Variant = main.get("_last_magic_request_ms")
	return -1 if value == null else int(value)

func _deliver(uid: int, map_uid: int, action_type: int) -> void:
	var payload: PackedByteArray = Protocol.encode_cm_action(uid, map_uid, {"type": action_type, "speed": 100, "direction": 3, "x": 10, "y": 10, "aimX": 11 if action_type == 3 else 10, "aimY": 10})
	main.call("_on_server_message", NetworkClient.SM_ACTION, payload)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
