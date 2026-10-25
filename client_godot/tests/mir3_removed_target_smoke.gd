extends Node

func _offline(uid: int, map_uid: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(16)
	payload.encode_u64(0, uid)
	payload.encode_u64(8, map_uid)
	return payload

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 24 << 35
	GameState.player_map_id = 24
	GameState.player_x = 10
	GameState.player_y = 10
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for uid in [606, 707, 808, 909]:
		GameState.update_creature(uid, {"uid": uid, "type": 2, "x": 12, "y": 10, "action_type": 2})
	main.set("_magic_focus_uid", 606)
	main.set("_follow_focus_uid", 707)
	main.set("_attack_focus_uid", 808)
	main.set("_chase_target_uid", 606)
	main.set("_shift_chase_active", true)
	main.set("_move_step_timer", 0.6)
	var route: Array[Vector2i] = [Vector2i(11, 10), Vector2i(12, 10)]
	main.set("_move_path", route.duplicate())
	main.get("_summon_spawn_blockers")[606] = {"token": 1, "map_uid": GameState.player_map_uid}
	main.call("_on_server_message", NetworkClient.SM_OFFLINE, _offline(606, 1 << 35))
	main.call("_on_server_message", NetworkClient.SM_OFFLINE, _offline(909, GameState.player_map_uid))
	if GameState.get_creature(606).is_empty() or main.get("_magic_focus_uid") != 606 or main.get("_chase_target_uid") != 606 or main.get("_move_path") != route:
		_fail("foreign-map or unrelated removal changed current target")
		return
	main.call("_on_server_message", NetworkClient.SM_OFFLINE, _offline(606, GameState.player_map_uid))
	if not GameState.get_creature(606).is_empty() or main.get("_magic_focus_uid") != 0 or main.get("_chase_target_uid") != 0 \
			or not main.get("_move_path").is_empty() or main.get("_shift_chase_active") \
			or main.get("_move_step_timer") != 0.6 or main.get("_summon_spawn_blockers").has(606):
		_fail("removed target retained history/chase/spawn state or truncated committed movement")
		return
	if main.get("_follow_focus_uid") != 707 or main.get("_attack_focus_uid") != 808:
		_fail("removing one actor cleared unrelated focus channels")
		return
	main.call("_finish_summon_spawn", 606, 1)
	if not GameState.get_creature(606).is_empty():
		_fail("old summon callback recreated removed actor")
		return
	main.set("_move_path", route.duplicate())
	GameState.remove_creature(0)
	if main.get("_move_path") != route:
		_fail("empty UID was mistaken for an active chase target")
		return
	main.set("_move_path", [] as Array[Vector2i])
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 12, "y": 10, "action_type": 2})
	main.get_node("WorldRenderer")._actor_target_rects = {}
	if main.call("_update_magic_focus", Vector2i.ZERO) != 0:
		_fail("re-entering actor restored old magic history without a new hover")
		return
	GameState.remove_creature(707)
	if main.get("_follow_focus_uid") != 0 or main.get("_attack_focus_uid") != 808:
		_fail("central removal did not clear only its matching follow focus")
		return
	GameState.update_creature(808, {"uid": 808, "type": 2, "x": 12, "y": 10, "action_type": 13, "action_speed": 100, "action_started_ms": 1})
	main.call("_request_dead_fade_out", 808)
	if main.get("_attack_focus_uid") != 808:
		_fail("fade request cleared target before actor removal")
		return
	main.get_node("WorldRenderer").call("_update_dead_fades", Time.get_ticks_msec() + 30000)
	if not GameState.get_creature(808).is_empty() or main.get("_attack_focus_uid") != 0:
		_fail("completed corpse fade retained removed attack focus")
		return
	print("MIR3 REMOVED TARGET PASS: wire offline/map filtering, matching focus cleanup, chase cancellation preserves committed step, old summon ignored, re-entry does not revive magic history and corpse fade clears at removal")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("REMOVED TARGET: " + message)
	get_tree().quit(1)
