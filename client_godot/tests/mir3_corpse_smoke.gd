extends Node

const Movement = preload("res://scripts/game/mir3_movement.gd")
var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.grabbed_item = {}
	var movement := Movement.new()
	movement.press(MOUSE_BUTTON_LEFT, Vector2i(20, 10), true, true, true)
	_expect(movement.decide(Vector2i(10, 10), func(_x, _y): return false, {}).get("harvest") == 3, "Alt precedes Shift, Ctrl and terrain checks")
	movement.advance(0.301, Vector2i(10, 10), false, true, false, true, false)
	_expect(not movement.harvest and movement.force_attack, "held modifier changes replace harvesting with Shift attack")
	movement.release()
	_expect(not movement.harvest and not movement.force_attack, "release clears modifier intent")
	var main := load("res://scenes/game/main.tscn").instantiate() as Control
	add_child(main)
	main.set_process(false)
	main.get_node("WorldRenderer").set_process(false)
	GameState.creatures.clear()
	GameState.creatures[201] = {"x": 20, "y": 10, "action_type": 2}
	GameState.creatures[202] = {"x": 21, "y": 11, "action_type": 13}
	GameState.creatures[203] = {"x": 20, "y": 10, "action_type": 13}
	_expect(main.call("_find_corpse_near", Vector2i(20, 10)) == 202, "first corpse in actor order wins over exact clicked cell")
	_expect(main.call("_find_corpse_near", Vector2i(18, 10)) == 0, "corpse search does not expand beyond one cell")
	GameState.creatures.clear()
	_expect(main.call("_try_harvest_corpse", Vector2i(20, 10), 3, 0), "empty ground still attempts bend")
	_expect(GameState.player_action_type == 8 and GameState.player_direction == 3, "empty ground bends toward click")
	_expect(main.get("_pickup_action_timer") < 0.0, "harvest bend never schedules ground pickup")
	_expect(not main.call("_try_harvest_corpse", Vector2i(20, 10), 3, 1000), "exactly 1000 ms remains gated")
	_expect(main.call("_try_harvest_corpse", Vector2i(20, 10), 3, 1001), "strictly over 1000 ms permits next attempt")
	_expect(Vector2i(GameState.player_x, GameState.player_y) == Vector2i(10, 10) and main.get("_move_path").is_empty(), "harvesting does not move hero or schedule a path")
	if failures.is_empty():
		print("MIR3 CORPSE PASS: Alt priority, modifier release, actor-order selection, 3x3 search, empty bend, strict cooldown, no movement or ground pickup")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
