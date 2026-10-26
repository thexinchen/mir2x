extends "res://tests/self_server_move_queue_smoke.gd"

const REMOTE_UID := (5 << 59) | 991

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = MAP_UID
	GameState.player_map_id = 1
	GameState.player_x = 10
	GameState.player_y = 12
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	if not main.call("_load_world_map", 1):
		_expect(false, "remote movement map resource available")
		get_tree().quit(1)
		return
	GameState.player_map_name = main.get_node("WorldRenderer").world_resource.map_name
	for _attempt in 500:
		await get_tree().create_timer(0.01).timeout
		if not main.get_node("MapLoadingOverlay").visible: break
	if main.get_node("MapLoadingOverlay").visible:
		_expect(false, "remote movement world finishes loading")
		get_tree().quit(1)
		return
	main.set_process(false)
	GameState.update_creature(REMOTE_UID, {"uid": REMOTE_UID, "type": 2, "gender": 0, "job": 1, "x": 10, "y": 10, "action_type": 2, "direction": 3})
	_deliver(_move(10, 11))
	var started: int = _actor().action_started_ms
	_deliver(_move(10, 11))
	_deliver(_move(11, 12))
	_deliver(_move(11, 12))
	_deliver(_stand(12))
	_expect(_actor().x == 11 and _actor().action_from_x == 10 and _actor().action_started_ms == started, "remote next leg/stand preserves first animation")
	_expect(_actor().get("motion_action_queue", []).size() == 2, "remote second leg and stand queue once")
	await _sample_midpoint(10, 11)
	_finish()
	_expect(_actor().x == 12 and _actor().action_from_x == 11 and _actor().action_type == 3, "remote second leg starts after first")
	await _sample_midpoint(11, 12)
	_finish()
	_expect(_actor().x == 12 and _actor().action_type == 2 and not _actor().has("motion_action_queue"), "remote stand follows both legs")
	_deliver(_move(12, 13))
	_deliver(_stand(13))
	_deliver(_move(13, 12))
	_deliver(_move(12, 13))
	_finish()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_actor().x == 12 and _actor().action_type == 3, "zero-duration queued stand does not strand later movement")
	_finish()
	_expect(_actor().x == 13 and _actor().action_from_x == 12 and _actor().action_type == 3, "remote repeated edge survives return leg")
	_deliver({"action": {"type": 6, "x": 15, "y": 10, "aimX": 15, "aimY": 10, "direction": 3}})
	_expect(_actor().x == 15 and not _actor().has("motion_action_queue"), "remote teleport clears queued normal moves")
	_deliver(_move(15, 16))
	_deliver(_move(16, 17))
	_deliver({"action": {"type": 11, "x": 16, "y": 10, "direction": 3}})
	_expect(_actor().action_type == 11 and not _actor().has("motion_action_queue"), "remote hit still interrupts normal movement queue")
	# Exercise a correction prefix with a later genuine movement appended.
	var renderer: Control = main.get_node("WorldRenderer")
	var line: Array[Vector2i] = []
	if renderer.load_map(24):
		for y in range(120, 131):
			for x in range(400, 421):
				var valid := true
				for offset in 5:
					if not renderer.can_walk(x + offset, y): valid = false
				if valid:
					for offset in 5: line.append(Vector2i(x + offset, y))
					break
			if not line.is_empty(): break
	if line.size() != 5:
		_expect(false, "real map correction fixture available")
	else:
		var actor := _actor()
		actor.merge({"x": line[0].x, "y": line[0].y, "action_type": 2}, true)
		GameState.update_creature(REMOTE_UID, actor)
		for index in [2, 3]:
			_deliver({"action": {"type": 3, "speed": 100, "x": line[index].x, "y": line[index].y, "aimX": line[index + 1].x, "aimY": line[index + 1].y}})
		for _step in range(3): _finish()
		_expect(_actor().x == line[4].x and _actor().action_from_x == line[3].x and _actor().action_type == 3, "remote correction preserves subsequent received movement")
	if failures.is_empty(): print("REMOTE SERVER MOVE QUEUE PASS: ordered legs/stand, real-frame midpoints, adjacent duplicates, return edges, stand drain, teleport/hit interruption and correction continuation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _actor() -> Dictionary:
	return GameState.get_creature(REMOTE_UID)

func _finish() -> void:
	main.call("_finish_creature_action", REMOTE_UID, int(_actor().action_type), int(_actor().action_started_ms))

func _sample_midpoint(from_x: int, end_x: int) -> void:
	main.set_process(true)
	await get_tree().create_timer(0.25).timeout
	var renderer: Control = main.get_node("WorldRenderer")
	var actor := _actor()
	var visual_started: int = renderer.call("_visual_movement_started_ms", "creature:%d" % REMOTE_UID, int(actor.action_started_ms), int(actor.action_type))
	var drawn: Vector2 = renderer.call("_action_draw_grid", int(actor.x), int(actor.y), int(actor.action_from_x), int(actor.action_from_y), int(actor.action_type), visual_started, int(actor.action_speed))
	_expect(actor.x == end_x and drawn.x > from_x and drawn.x < end_x, "remote leg has real interpolated midpoint")
	if from_x == 11 and OS.has_environment("MIR3_REMOTE_MOVE_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		_expect(get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_REMOTE_MOVE_SCREENSHOT")) == OK, "remote movement screenshot saves")
	main.set_process(false)

func _deliver(data: Dictionary) -> void:
	data["uid"] = REMOTE_UID
	data["mapUID"] = MAP_UID
	super._deliver(data)
