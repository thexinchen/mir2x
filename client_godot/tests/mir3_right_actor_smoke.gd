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
		main.call("_cancel_movement")
		click.alt_pressed = true
		main.call("_handle_mouse_click", click)
		_expect(input.button == MOUSE_BUTTON_RIGHT and input.target == target and input.pending, "Alt right click on actor type%d still records ground run request" % actor_type, input.target)
		decision = input.decide(start, renderer.can_walk, main.call("_ground_occupied"))
		_expect(decision.get("move") == start + Vector2i.RIGHT * 2, "Alt actor type%d still permits first run hop" % actor_type, decision)
		main.call("_cancel_movement")
		click.alt_pressed = false
		click.ctrl_pressed = true
		old_path = [start + Vector2i.DOWN]
		main.set("_move_path", old_path.duplicate())
		main.set("_move_step_timer", 0.4)
		main.call("_handle_mouse_click", click)
		_expect(input.button == MOUSE_BUTTON_RIGHT and not input.pending, "Ctrl actor type%d retains hold without initial ground dispatch" % actor_type, input.button)
		_expect(main.get("_move_path") == old_path and main.get("_move_step_timer") == 0.4, "Ctrl actor type%d preserves committed movement and previous route" % actor_type, main.get("_move_path"))
		input.advance(0.300, target, true, true, false)
		_expect(not input.pending, "Ctrl actor type%d does not repeat at exactly 300ms" % actor_type, input.pending)
		input.advance(0.001, target, true, true, false)
		var repeat_pending: bool = input.pending
		decision = input.decide(start, renderer.can_walk, main.call("_ground_occupied"))
		_expect(repeat_pending and decision.get("move") == start + Vector2i.RIGHT * 2, "Ctrl actor type%d held repeat resumes ground run" % actor_type, decision)
		main.call("_cancel_movement")
		input.press(MOUSE_BUTTON_LEFT, start + Vector2i.DOWN, false)
		main.call("_handle_mouse_click", click)
		_expect(input.button == MOUSE_BUTTON_LEFT and input.pending and input.target == start + Vector2i.DOWN, "Ctrl actor type%d does not replace an active left press" % actor_type, input.target)
	main.call("_release_ground_input")
	if DisplayServer.get_name() != "headless":
		main.get_node("MapLoadingOverlay").hide()
		main.set_process(true)
		_press(MOUSE_BUTTON_RIGHT, point)
		await get_tree().create_timer(0.08).timeout
		_release(MOUSE_BUTTON_RIGHT, point)
		_expect(_position() == start + Vector2i.RIGHT * 2 and main.get("_follow_focus_uid") == 707, "actual right mouse input over NPC starts a run hop", _position())
		await get_tree().create_timer(0.7).timeout
		main.set_process(false)
		GameState.player_x = start.x
		GameState.player_y = start.y
		main.call("_cancel_movement")
		main.call("_set_player_action", 2)
		main.call("_center_hero")
		point = _point(target)
		renderer.set("_actor_target_rects", {707: {"rect": Rect2(point - Vector2(10, 20), Vector2(30, 40)), "map_y": target.y}})
		renderer.set("_mouse_focus_uid", 707)
		main.set_process(true)
		var ctrl := InputEventKey.new()
		ctrl.keycode = KEY_CTRL
		ctrl.pressed = true
		Input.parse_input_event(ctrl)
		Input.warp_mouse(point)
		var motion := InputEventMouseMotion.new()
		motion.position = point
		Input.parse_input_event(motion)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_RIGHT
		press.position = point
		press.ctrl_pressed = true
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().create_timer(0.08).timeout
		_expect(_position() == start, "actual Ctrl right actor press does not immediately move", _position())
		await get_tree().create_timer(0.36).timeout
		_release(MOUSE_BUTTON_RIGHT, Vector2(400, 570))
		ctrl.pressed = false
		Input.parse_input_event(ctrl)
		var after_hold := _position()
		_expect(after_hold == start + Vector2i.RIGHT * 2, "actual Ctrl right actor hold resumes run after threshold", after_hold)
		await get_tree().create_timer(0.7).timeout
		_expect(_position() == after_hold and main.get("_ground_input").button == 0, "Ctrl right release over HUD cancels further held dispatch", _position())
	if failures.is_empty(): print("MIR3 RIGHT ACTOR PASS: monster/player/NPC ordinary and Alt ground input, Ctrl held repeat after 300ms, preserved route/timer, left priority and window release over HUD")
	get_tree().quit(0 if failures.is_empty() else 1)
