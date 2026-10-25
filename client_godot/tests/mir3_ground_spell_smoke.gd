extends Node

class GroundMain:
	extends "res://scripts/game/main.gd"
	var request: Dictionary = {}
	var test_focus := 0
	func _update_magic_focus(_grid: Vector2i) -> int:
		return test_focus
	func _send_spell_action(action_type: int, magic_id: int, grid: Vector2i, uid: int) -> bool:
		request = {"type": action_type, "magic": magic_id, "grid": grid, "uid": uid}
		return true

const Movement = preload("res://scripts/game/mir3_movement.gd")
var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(GroundMain)
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var map: RefCounted = main.get_node("WorldRenderer").world_resource
	map.width = 12
	map.height = 10
	GameState.player_x = 5
	GameState.player_y = 5
	GameState.player_uid = 101
	GameState.magic_cast_times.clear()
	var firewall: int = resources.magic_id("火墙")
	main.set("test_focus", 606)
	_expect(main.call("_cast_magic", firewall, Vector2i(-20, 99)) and main.get("request").grid == Vector2i(0, 9) and main.get("request").uid == 0, "ground branch clamps both axes without adopting actor focus")
	main.call("_cast_magic", firewall, Vector2i(11, 0))
	_expect(main.get("request").grid == Vector2i(11, 0), "valid boundary target is unchanged")
	for direction in range(1, 9):
		GameState.player_direction = direction
		main.call("_cast_magic", firewall, Vector2i(5, 5))
		_expect(main.get("request").grid == Vector2i(5, 5) + Movement.DIRECTIONS[direction - 1], "same-cell ground cast steps in direction %d" % direction)
	GameState.player_x = 0
	GameState.player_y = 0
	GameState.player_direction = 1
	main.call("_cast_magic", firewall, Vector2i(-20, -30))
	_expect(main.get("request").grid == Vector2i(0, -1), "clamping occurs before same-cell step, without a second clamp")
	GameState.player_x = 5
	GameState.player_y = 5
	GameState.player_direction = 3
	main.call("_cast_magic", resources.magic_id("瞬息移动"), Vector2i(1, 8))
	_expect(main.get("request").grid == Vector2i(6, 5), "teleport ground request uses fixed front-cell exception")
	main.call("_cast_magic", resources.magic_id("魔法盾"), Vector2i(-20, 99))
	_expect(main.get("request").grid == Vector2i(5, 5) and main.get("request").uid == 101, "self spell keeps hero target")
	main.call("_cast_magic", resources.magic_id("火球术"), Vector2i(-20, 99))
	_expect(main.get("request").grid == Vector2i(-20, 99) and main.get("request").uid == 606, "actor-target branch is not rewritten by ground normalization")
	if failures.is_empty(): print("MIR3 GROUND SPELL PASS: map bounds, same-cell eight directions, clamp-before-step, teleport front override, self/actor-target isolation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
