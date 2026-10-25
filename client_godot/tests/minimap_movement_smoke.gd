extends "res://tests/mir3_movement_visual.gd"


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "name": "移动验证", "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
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
	main.call("_center_hero")
	await get_tree().create_timer(0.4).timeout
	main.get_node("MapLoadingOverlay").hide()
	var panel: Control = main.call("_ensure_extra_panel", "res://scenes/game/panels/minimap.tscn")
	var target := start + Vector2i(6, 0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = panel.call("_map_to_canvas", target.x, target.y)
	panel.call("_on_map_input", click)
	_expect(_position() == start, "minimap right click does not teleport", _position())
	_expect(not main.get("_move_path").is_empty(), "minimap right click plans a path", main.get("_move_path"))
	main.call("_process", 0.0)
	_expect(_position() == start + Vector2i(2, 0), "first action advances only two tiles", _position())
	_expect(renderer.call("player_draw_grid").distance_to(Vector2(start)) < 0.05, "visual move starts at original position", renderer.call("player_draw_grid"))
	for i in range(6):
		main.call("_process", 0.05)
	var halfway: Vector2 = renderer.call("player_draw_grid")
	_expect(halfway.x > start.x and halfway.x < start.x + 2, "character interpolates instead of teleporting", halfway)
	click.pressed = false
	main.call("_input", click)
	_expect(not main.get("_move_path").is_empty(), "minimap release preserves destination path", main.get("_move_path"))
	for i in range(60):
		main.call("_process", 0.05)
	_expect(_position() == target, "normal movement reaches minimap destination", _position())
	if failures.is_empty():
		print("MINIMAP MOVEMENT PASS: right click routes through path movement, animated two-cell steps, no teleport")
	get_tree().quit(0 if failures.is_empty() else 1)
