extends "res://tests/mir3_movement_visual.gd"

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.grabbed_item = {}
	GameState.creatures.clear()
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	renderer = main.get_node("WorldRenderer")
	if not main.call("_load_world_map", 24):
		get_tree().quit(1)
		return
	start = _find_corridor()
	GameState.player_x = start.x
	GameState.player_y = start.y
	main.call("_set_player_action", 2)
	main.call("_center_hero")
	await get_tree().create_timer(0.4).timeout
	main.set_process(false)
	renderer.set_process(false)
	var target := start + Vector2i.RIGHT * 3
	var point := _point(target)
	for actor_type in [1, 2, 3]:
		main.call("_cancel_movement")
		GameState.creatures.clear()
		GameState.creatures[707] = {"uid": 707, "type": actor_type, "x": target.x, "y": target.y, "action_type": 2}
		renderer.set("_actor_target_rects", {707: {"rect": Rect2(point - Vector2(10, 20), Vector2(30, 40)), "map_y": target.y}})
		renderer.set("_mouse_focus_uid", 707)
		var old_path: Array[Vector2i] = [start + Vector2i.DOWN]
		main.set("_move_path", old_path)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		click.position = point
		main.call("_handle_mouse_click", click)
		var input = main.get("_ground_input")
		_expect(input.button == MOUSE_BUTTON_RIGHT and input.target == target and input.pending, "right click on actor type%d records ground run request" % actor_type, input.target)
		_expect(main.get("_move_path").is_empty() and main.get("_follow_focus_uid") == 707, "actor type%d focus does not retain obsolete route" % actor_type, main.get("_move_path"))
		var decision: Dictionary = input.decide(start, renderer.can_walk, main.call("_ground_occupied"))
		_expect(decision.get("move") == start + Vector2i.RIGHT * 2, "actor type%d right input permits clear first run hop" % actor_type, decision)
	main.call("_release_ground_input")
	if DisplayServer.get_name() != "headless":
		main.get_node("MapLoadingOverlay").hide()
		main.set_process(true)
		_press(MOUSE_BUTTON_RIGHT, point)
		await get_tree().create_timer(0.08).timeout
		_release(MOUSE_BUTTON_RIGHT, point)
		_expect(_position() == start + Vector2i.RIGHT * 2 and main.get("_follow_focus_uid") == 707, "actual right mouse input over NPC starts a run hop", _position())
	if failures.is_empty(): print("MIR3 RIGHT ACTOR PASS: ordinary right click over monster/player/NPC enters ground movement while preserving focus")
	get_tree().quit(0 if failures.is_empty() else 1)
