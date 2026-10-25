extends "res://tests/mir3_movement_visual.gd"


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
	if failures.is_empty():
		print("MIR3 ACTION VALIDATION PASS: commit-time terrain/actor checks, corpse consistency, invalid hop rejection, dynamic replan")
	get_tree().quit(0 if failures.is_empty() else 1)
