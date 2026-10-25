extends "res://tests/mir3_movement_visual.gd"

const Protocol = preload("res://scripts/network/protocol.gd")


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.creatures.clear()
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	renderer = main.get_node("WorldRenderer")
	if not main.call("_load_world_map", 24):
		get_tree().quit(1)
		return
	start = _find_corridor()
	GameState.player_x = start.x
	GameState.player_y = start.y
	main.call("_set_player_action", 2)
	await get_tree().create_timer(0.4).timeout
	main.get_node("MapLoadingOverlay").hide()
	var middle := start + Vector2i.RIGHT
	var end := start + Vector2i.RIGHT * 2
	GameState.creatures[123] = {"x": middle.x, "y": middle.y, "action_type": 2}
	var started := GameState.player_action_started_ms
	_expect(not main.call("_send_move_action", end.x, end.y), "submit rejects occupied run intermediate cell", _position())
	_expect(_position() == start and GameState.player_action_started_ms == started, "rejection preserves position and animation clock", _position())
	GameState.creatures[123].action_type = 13
	_expect(not main.call("_ground_occupied").has(middle), "corpse does not block movement", middle)
	var goals: Array[Vector2i] = [end]
	var path: Array[Vector2i] = main.call("_find_path", goals)
	_expect(path == goals, "pathfinding and submission agree on corpse occupancy", path)
	GameState.creatures.clear()
	var resource: RefCounted = renderer.world_resource
	var key: int = middle.x + middle.y * resource.width
	var land: int = resource.land[key]
	resource.land[key] = 0
	_expect(not main.call("_send_move_action", end.x, end.y), "submit rechecks newly closed terrain intermediate cell", _position())
	resource.land[key] = land
	_expect(not main.call("_send_move_action", start.x + 3, start.y), "submit rejects more than two cells", _position())
	_expect(not main.call("_send_move_action", start.x + 2, start.y + 1), "submit rejects non-eight-way hop", _position())
	main.call("_start_move_to", start + Vector2i.RIGHT * 4)
	GameState.creatures[123] = {"x": middle.x, "y": middle.y, "action_type": 2}
	main.call("_process_movement", 0.0)
	_expect(_position() == start and main.get("_move_step_timer") <= 0.0, "invalid path hop is not committed and does not start cooldown", _position())
	path = main.get("_move_path")
	_expect(not path.is_empty(), "dynamic occupant triggers path replanning", path)
	GameState.creatures.clear()
	main.call("_process_movement", 0.0)
	_expect(_position() != start and main.get("_move_step_timer") > 0.0, "valid replanned action commits before cooldown", _position())
	# A server rejection is an authoritative stand, not a mouse release.
	# It must clear the obsolete route while allowing held input to retry.
	var held = main.get("_ground_input")
	held.press(MOUSE_BUTTON_RIGHT, start + Vector2i.RIGHT * 6, false)
	held.pending = false
	main.set("_ground_path_active", true)
	var stand := {"uid": GameState.player_uid, "mapUID": GameState.player_map_uid, "action": {"type": 2, "speed": 100, "direction": 3, "x": start.x, "y": start.y}}
	main.call("_handle_action", Protocol.encode_cm_action(stand.uid, stand.mapUID, stand.action))
	_expect(_position() == start and main.get("_move_path").is_empty(), "server stand restores authoritative grid and discards old route", _position())
	_expect(not main.get("_ground_path_active"), "server stand clears ground path latch so held input can retry", main.get("_ground_path_active"))
	_expect(held.button == MOUSE_BUTTON_RIGHT, "server rejection does not synthesize mouse release", held.button)
	held.advance(0.301, start + Vector2i.DOWN * 4, false, true, main.get("_ground_path_active"))
	_expect(held.pending and held.target == start + Vector2i.DOWN * 4, "held cursor redirection resumes after server rejection", held.target)
	# The final queued path node may have been sent before the stand arrives.
	main.set("_ground_path_active", true)
	main.call("_handle_action", Protocol.encode_cm_action(stand.uid, stand.mapUID, stand.action))
	_expect(not main.get("_ground_path_active"), "stand also clears stale latch with no remaining path nodes", main.get("_ground_path_active"))
	main.call("_release_ground_input")
	_expect(main.call("_send_move_action", start.x + 1, start.y), "accepted-echo fixture submits a valid move", _position())
	main.set("_ground_path_active", true)
	started = GameState.player_action_started_ms
	var accepted := {"type": 3, "speed": 100, "x": start.x, "y": start.y, "aimX": start.x + 1, "aimY": start.y}
	main.call("_handle_action", Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, accepted))
	_expect(main.get("_ground_path_active") and GameState.player_action_started_ms == started, "accepted move echo preserves route latch and animation clock", main.get("_ground_path_active"))
	if failures.is_empty():
		print("MIR3 ACTION VALIDATION PASS: commit-time terrain/actor checks, corpse consistency, invalid hop rejection, dynamic replan")
	get_tree().quit(0 if failures.is_empty() else 1)
