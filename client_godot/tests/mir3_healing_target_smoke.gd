extends Node

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_x = 5
	GameState.player_y = 5
	GameState.player_direction = 1
	GameState.creatures.clear()
	GameState.magic_effects.clear()
	GameState.magic_cast_times.clear()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	# Direction uses the existing terrain gate. Supply a real loaded map.
	_expect(main.call("_load_world_map", 1), "map fixture loads")
	var heal: int = main.get("_resources").magic_id("治愈术")
	_expect(heal > 0, "healing metadata exists")
	var expected_direction := 4 if renderer.can_walk(9, 8) else 1
	main.call("_execute_spell_action", 9, heal, Vector2i(9, 8), 0)
	_expect(GameState.player_direction == expected_direction, "self-coordinate substitution preserves existing mouse-facing calculation")
	_expect_heal(heal, Vector2i(5, 5), 0, "unowned healing")
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 8, "y": 7, "action_type": 2})
	main.call("_execute_spell_action", 9, heal, Vector2i(9, 8), 606)
	_expect_heal(heal, Vector2i(8, 7), 606, "selected live actor")
	main.call("_execute_spell_action", 9, heal, Vector2i(9, 8), 999)
	_expect_heal(heal, Vector2i(9, 8), 0, "removed selected actor retains existing stale-target policy")
	# Exercise the real movement brake and queued release, not a send stub.
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec()
	main.call("_send_spell_action", 9, heal, Vector2i(9, 8), 0)
	_expect(not main.get("_pending_spell_action").is_empty(), "moving heal queues")
	GameState.player_x = 6
	main.call("_release_pending_spell")
	_expect_heal(heal, Vector2i(6, 5), 0, "queued unowned healing uses current self position")
	var fireball: int = main.get("_resources").magic_id("火球术")
	main.call("_execute_spell_action", 9, fireball, Vector2i(9, 8), 0)
	_expect_heal(fireball, Vector2i(9, 8), 0, "ordinary spell retains ground aim")
	if failures.is_empty(): print("MIR3 HEALING TARGET PASS: unowned self coordinates/zero UID, live actor, stale actor isolation, movement queue release, ordinary spell isolation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect_heal(magic_id: int, grid: Vector2i, uid: int, label: String) -> void:
	var matched: Dictionary = {}
	for effect in GameState.magic_effects:
		if int(effect.get("magicID", 0)) == magic_id: matched = effect
	_expect(not matched.is_empty() and Vector2i(matched.get("aimX", -1), matched.get("aimY", -1)) == grid and int(matched.get("aimUID", -1)) == uid, label + ": " + str(matched))

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
