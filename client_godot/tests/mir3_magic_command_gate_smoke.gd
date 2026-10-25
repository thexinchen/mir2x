extends Node

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.creatures.clear()
	GameState.magic_cast_times.clear()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var renderer: Control = main.get_node("WorldRenderer")
	renderer.world_resource.width = 30
	renderer.world_resource.height = 30
	renderer.world_resource.land.resize(900)
	renderer.world_resource.land.fill(0)
	main.set("_last_magic_request_ms", 10000)
	for name in ["刺杀剑术", "烈火剑法", "翔空剑法", "莲月剑法", "半月弯刀", "十方斩", "空拳刀法", "野蛮冲撞"]:
		var magic: int = resources.magic_id(name)
		_expect(not main.call("_magic_ready", magic, 10499), "499ms rejects " + name)
		_expect(main.call("_magic_ready", magic, 10500), "500ms accepts " + name)
	var fireball: int = resources.magic_id("火球术")
	var thrust: int = resources.magic_id("刺杀剑术")
	var half: int = resources.magic_id("半月弯刀")
	_expect(main.call("_magic_ready", fireball, 10001), "ordinary magic is not given a new generic 500ms cooldown")
	main.set("_last_magic_request_ms", -500)
	_expect(main.call("_cast_magic", thrust, Vector2i.ZERO), "first sword command accepted")
	var accepted_clock := _request_clock(main)
	_expect(accepted_clock >= 0, "sword stamps request clock")
	var logs_before := GameState.chat_log.size()
	_expect(not main.call("_cast_magic", half, Vector2i.ZERO) and not bool(main.get("_swing_magic").get(half, false)), "different sword shares the active gate")
	_expect(GameState.chat_log.size() == logs_before, "rapid command rejection stays silent")
	_expect(_request_clock(main) == accepted_clock, "rejection does not extend request clock")
	main.set("_last_magic_request_ms", -500)
	GameState.player_action_type = 2
	main.call("_cast_magic", fireball, Vector2i(14, 11))
	_expect(_request_clock(main) >= 0 and not main.call("_magic_ready", half), "accepted ordinary cast also delays command skills")
	GameState.magic_cast_times.clear()
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec()
	main.set("_last_magic_request_ms", -500)
	main.call("_cast_magic", fireball, Vector2i(14, 11))
	_expect(not main.get("_pending_spell_action").is_empty() and _request_clock(main) >= 0 and not main.call("_magic_ready", half), "moving spell stamps before queue release")
	main.set("_last_magic_request_ms", 10000)
	main.call("_release_pending_spell")
	_expect(_request_clock(main) == 10000, "queue execution does not restart accepted-request gate")
	if failures.is_empty(): print("MIR3 MAGIC COMMAND GATE PASS: 499/500ms boundary, shared swords/impulse commands, ordinary-cast stamp, rejected request isolation and pre-queue timing")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _request_clock(main: Control) -> int:
	var value: Variant = main.get("_last_magic_request_ms")
	return -1 if value == null else int(value)
