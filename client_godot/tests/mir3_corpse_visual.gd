extends "res://tests/mir3_movement_visual.gd"

var bends := 0
var last_started := -1

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
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
	main.get_node("MapLoadingOverlay").hide()
	GameState.state_changed.connect(_count_bends)
	var target := start + Vector2i(6, 0)
	_modifier(KEY_ALT, true)
	_modifier(KEY_SHIFT, true)
	_alt_press(_point(target))
	await get_tree().create_timer(0.08).timeout
	_release(MOUSE_BUTTON_LEFT, _point(target))
	_expect(bends == 1 and _position() == start and GameState.player_action_type == 8, "Alt+Shift click bends in place rather than attacking", bends)
	_expect(main.get("_pickup_action_timer") < 0.0 and main.get("_move_path").is_empty(), "empty-ground bend queues no pickup or walking", main.get("_pickup_action_timer"))
	await get_tree().create_timer(1.2).timeout
	_expect(bends == 1, "released mouse does not repeat bend", bends)
	_alt_press(_point(target))
	await get_tree().create_timer(2.3).timeout
	_release(MOUSE_BUTTON_LEFT, Vector2(400, 570))
	_expect(bends == 4 and _position() == start, "held Alt repeats three ready bends with one-second gate", bends)
	_modifier(KEY_ALT, false)
	_modifier(KEY_SHIFT, false)
	await get_tree().create_timer(1.2).timeout
	_expect(bends == 4, "release over HUD stops held harvesting", bends)
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	_expect(_position() == start + Vector2i.RIGHT, "ordinary left walking resumes after Alt release", _position())
	if failures.is_empty(): print("MIR3 CORPSE VISUAL PASS: actual Alt+Shift mouse input, in-place bend, held repeat, HUD release, ordinary walking")
	get_tree().quit(0 if failures.is_empty() else 1)

func _modifier(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _alt_press(point: Vector2) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.alt_pressed = true
	event.shift_pressed = true
	Input.parse_input_event(event)

func _count_bends() -> void:
	if GameState.player_action_type == 8 and GameState.player_action_started_ms != last_started:
		last_started = GameState.player_action_started_ms
		bends += 1
