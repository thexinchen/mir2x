extends Node

class RequestMain:
	extends "res://scripts/game/main.gd"
	var requests := 0
	var focus_updates := 0
	var requested_uid := -1
	func _update_magic_focus(_grid: Vector2i, _magic_id := 0) -> int:
		focus_updates += 1
		return 606
	func _send_spell_action(_action_type: int, _magic_id: int, _aim: Vector2i, _uid: int) -> bool:
		requests += 1
		requested_uid = _uid
		return true

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(RequestMain)
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var kick: int = resources.magic_id("空拳刀法")
	var rush: int = resources.magic_id("野蛮冲撞")
	var fireball: int = resources.magic_id("火球术")
	_expect(kick != 0 and rush != 0 and fireball != 0, "impulse fixtures are present")
	GameState.magic_cast_times.clear()
	main.set("_last_impulse_magic_ms", 10000)
	for id in [kick, rush]:
		_expect(not main.call("_magic_ready", id, 10800), "metadata 800ms cannot bypass shared gate")
		_expect(not main.call("_magic_ready", id, 12999), "2999ms remains blocked")
		_expect(main.call("_magic_ready", id, 13000), "exactly 3000ms permits request")
	_expect(main.call("_magic_ready", fireball, 10001), "unrelated spell does not inherit impulse gate")
	main.set("_last_impulse_magic_ms", -3000)
	_expect(main.call("_cast_magic", kick, Vector2i.ZERO) and main.get("requests") == 1, "first kick queues normally")
	_expect(main.get("focus_updates") == 0 and main.get("requested_uid") == 0, "kick neither refreshes spell focus nor adopts a target UID")
	_expect(main.get("_last_impulse_magic_ms") >= 0, "kick stamps shared gate even before action executes")
	_expect(not main.call("_cast_magic", kick, Vector2i.ZERO) and main.get("requests") == 1, "immediate retry does not queue a second kick")
	_expect(not main.call("_magic_ready", rush), "kick also closes shared rush gate")
	if failures.is_empty(): print("MIR3 IMPULSE GATE PASS: 800/2999ms blocked, 3000ms accepted, request-time stamp, shared gate and unrelated spell isolation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
