extends Node

var main: Control
var failures: Array[String] = []
const UID := 606


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 24 << 35
	GameState.player_map_id = 24
	GameState.player_x = 10
	GameState.player_y = 10
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	_dead_fixture()
	_health(20)
	_expect(_actor().action_type == 13, "HP alone does not replace a corpse action")
	_stand()
	_expect(_actor().action_type == 2, "HP before Stand revives")
	_dead_fixture()
	_stand()
	_expect(_actor().action_type == 13, "Stand alone does not revive HP0")
	_health(20)
	_expect(_actor().action_type == 2, "Stand before HP revives")
	_dead_fixture(50)
	_stand()
	_health(50)
	_expect(_actor().action_type == 13, "stale positive HP plus Stand is not a zero-to-positive transition")
	_health(0)
	_health(20)
	_expect(_actor().action_type == 2, "fresh zero-to-positive transition can release queued Stand")
	main.call("_load_world_map", 24)
	var renderer: Node = main.get_node("WorldRenderer")
	var correction_start := Vector2i(-1, -1)
	for x in range(400, 411):
		if renderer.can_walk(x, 118) and renderer.can_walk(x + 1, 118) and renderer.can_walk(x + 2, 118):
			correction_start = Vector2i(x, 118)
			break
	if correction_start.x < 0:
		push_error("REMOTE REVIVE: no actual walkable correction fixture")
		get_tree().quit(1)
		return
	var correction_end := correction_start + Vector2i(2, 0)
	GameState.update_creature(UID, {"uid": UID, "type": 2, "x": correction_start.x, "y": correction_start.y,
		"action_type": 2, "hp": 0, "health_initialized": true})
	main.call("_start_creature_death_action", UID, {"type": 13, "x": correction_end.x, "y": correction_end.y, "direction": 3}, _actor())
	var move_started: int = _actor().action_started_ms
	_stand(correction_end)
	_health(20)
	_expect(_actor().action_type == 3 and not _actor().get("forced_action_queue", []).is_empty(), "early revive waits behind committed death correction")
	main.call("_finish_creature_action", UID, 3, move_started)
	_expect(_actor().action_type == 13, "early revive still plays death motion")
	var death_started := Time.get_ticks_msec() - 1100
	_actor()["action_started_ms"] = death_started
	main.call("_finish_creature_action", UID, 13, death_started)
	_expect(_actor().action_type == 2 and Vector2i(_actor().x, _actor().y) == correction_end, "revive releases after correction and death motion")
	_dead_fixture()
	_actor()["action_started_ms"] = Time.get_ticks_msec()
	_health(20)
	_stand()
	var stale_started: int = _actor().action_started_ms
	GameState.remove_creature(UID)
	_dead_fixture()
	_actor()["action_started_ms"] = stale_started + 1
	main.call("_finish_creature_action", UID, 13, stale_started)
	_expect(_actor().action_type == 13 and not _actor().has("remote_revive_action"), "stale completion cannot revive a replacement actor")
	_dead_fixture()
	main.call("_request_dead_fade_out", UID)
	var fade_started: int = _actor().dead_fade_requested_ms - 1000
	_actor()["dead_fade_requested_ms"] = fade_started
	main.call("_request_dead_fade_out", UID)
	_expect(_actor().dead_fade_requested_ms == fade_started, "duplicate fade request does not restart progress")
	_health(20)
	_stand()
	_expect(_actor().action_type == 2 and not _actor().has("dead_fade_requested_ms"), "revival clears previous fade lifecycle")
	var notify := PackedByteArray()
	notify.resize(8)
	notify.encode_u64(0, UID)
	main.call("_handle_notify_dead", notify)
	_expect(_actor().action_type == 13 and not _actor().has("dead_fade_requested_ms") and not _actor().has("remote_revive_health"), "next death does not inherit revive/fade state")
	if failures.is_empty(): print("REMOTE REVIVE PASS: both packet orders, paired health/Stand, stale positive rejection, correction/death ordering, stale callback isolation, duplicate fade and next-life cleanup")
	get_tree().quit(0 if failures.is_empty() else 1)


func _actor() -> Dictionary:
	return GameState.get_creature(UID)


func _dead_fixture(hp := 0) -> void:
	GameState.update_creature(UID, {"uid": UID, "type": 2, "x": 12, "y": 10,
		"action_type": 13, "action_speed": 100, "action_started_ms": Time.get_ticks_msec() - 2000,
		"hp": hp, "health_initialized": true})


func _stand(grid := Vector2i(12, 10)) -> void:
	main.call("_handle_action_data", {"uid": UID, "mapUID": GameState.player_map_uid,
		"action": {"type": 2, "speed": 100, "direction": 3, "x": grid.x, "y": grid.y}})


func _health(hp: int) -> void:
	var payload := PackedByteArray()
	payload.resize(66)
	payload[0] = 1
	payload.encode_u64(1, UID)
	for index in range(6):
		payload.encode_s32(9 + index * 4, [hp, 10, 100, 10, 0, 0][index])
	main.call("_handle_health", payload)


func _expect(success: bool, reason: String) -> void:
	if not success:
		failures.append(reason)
		push_error("REMOTE REVIVE: " + reason)
