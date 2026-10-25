extends Node

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 24 << 35
	GameState.player_map_id = 24
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_hp = 100
	GameState.player_health_initialized = true
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var fireball: int = resources.magic_id("火球术")
	if fireball <= 0:
		_fail("fireball metadata unavailable")
		return
	GameState.learned_magic = [{"magicID": fireball, "exp": 0}]
	GameState.magic_keys = {fireball: 49}
	main.get_node("MapLoadingOverlay").hide()
	var magic_key := InputEventKey.new()
	magic_key.keycode = KEY_F1
	magic_key.pressed = true
	for action in [7, 8, 9, 11, 12, 14]:
		main.call("_cancel_movement")
		GameState.player_action_type = action
		main.set("_player_action_timer", 0.25)
		main.set("_pickup_action_timer", 0.2 if action == 8 else -1.0)
		main.set("_last_magic_request_ms", -500)
		GameState.magic_cast_times.clear()
		var effects := GameState.magic_effects.size()
		var log_count := GameState.chat_log.size()
		var route: Array[Vector2i] = [Vector2i(11, 10)]
		main.set("_move_path", route)
		if main.call("_cast_magic", fireball, Vector2i(12, 10)):
			_fail("ordinary cast interrupted action %d" % action)
			return
		main.call("_unhandled_input", magic_key)
		if GameState.player_action_type != action or main.get("_player_action_timer") != 0.25 \
				or main.get("_last_magic_request_ms") != -500 or not GameState.magic_cast_times.is_empty() \
				or GameState.magic_effects.size() != effects or GameState.chat_log.size() != log_count \
				or not main.get("_pending_spell_action").is_empty() or main.get("_move_path") != route:
			_fail("busy rejection changed action/request state: %d" % action)
			return
		# Finish the actual timers; the next input may then cast normally.
		main.call("_process_pickup_action", 0.3)
		main.call("_process_player_action", 0.3)
		if not main.call("_cast_magic", fireball, Vector2i(12, 10)) or GameState.player_action_type != 9:
			_fail("ordinary cast remained blocked after action %d ended" % action)
			return
	# A pickup with zero remaining time is still active until its dispatch runs.
	GameState.player_action_type = 2
	main.set("_player_action_timer", -1.0)
	main.set("_pickup_action_timer", 0.0)
	GameState.magic_cast_times.clear()
	if main.call("_send_spell_action", 9, fireball, Vector2i(12, 10), 0):
		_fail("zero-time pickup was treated as completed before dispatch")
		return
	main.call("_process_pickup_action", 0.01)
	if not main.call("_send_spell_action", 9, fireball, Vector2i(12, 10), 0):
		_fail("completed pickup did not release ordinary casting")
		return
	# Non-casting sword commands use their own command gate, not 68F640.
	GameState.player_action_type = 7
	main.set("_player_action_timer", 0.25)
	main.set("_last_magic_request_ms", -500)
	var thrust: int = resources.magic_id("刺杀剑术")
	if not main.call("_cast_magic", thrust, Vector2i.ZERO) or GameState.player_action_type != 7 or main.get("_player_action_timer") != 0.25:
		_fail("ordinary-cast busy gate leaked into a sword toggle")
		return
	print("MIR3 SPELL BUSY PASS: attack/pickup/spell/hit/kick/mining preserve committed action, silent rejection leaves clocks/effects/route intact, completion releases casting, zero-time pickup waits and sword commands stay independent")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("SPELL BUSY: " + message)
	get_tree().quit(1)
