extends "res://tests/mir3_movement_visual.gd"

var mines := 0
var last_started := -1

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.creatures.clear()
	GameState.ground_items.clear()
	GameState.grabbed_item = {}
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	renderer = main.get_node("WorldRenderer")
	if not main.call("_load_world_map", 24):
		get_tree().quit(1)
		return
	var resources: RefCounted = main.get("_resources")
	var weapon := 0
	for item in resources.item_attributes:
		if resources.item_can_mine(int(item)):
			weapon = int(item)
			break
	_expect(weapon != 0, "mine-capable weapon fixture exists", weapon)
	GameState.wear = {3: {"itemID": weapon}}
	start = _find_corridor()
	_reset_hero()
	await get_tree().create_timer(0.4).timeout
	main.get_node("MapLoadingOverlay").hide()
	GameState.state_changed.connect(_count_mines)
	var target := start + Vector2i.RIGHT * 6
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	await get_tree().create_timer(0.8).timeout
	_expect(_position() == start + Vector2i.RIGHT and mines == 0, "pickaxe click on open ground walks one cell without mining", _position())
	_reset_hero()
	await get_tree().create_timer(0.1).timeout
	var resource: RefCounted = renderer.world_resource
	var front := start + Vector2i.RIGHT
	var index: int = front.x + front.y * resource.width
	var old_land: int = resource.land[index]
	resource.land[index] = 0
	main.set("_move_step_timer", 0.4)
	main.call("_set_player_action", 3)
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	_expect(mines == 0 and main.get("_move_step_timer") > 0.0 and GameState.player_action_type == 3, "mining click preserves an in-flight move and waits for readiness", main.get("_move_step_timer"))
	_reset_hero()
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	_expect(_position() == start and mines == 1 and main.get("_mine_target") == front and main.get("_move_path").is_empty(), "distant click against adjacent wall mines in place without a route", main.get("_mine_target"))
	await get_tree().create_timer(1.0).timeout
	_expect(mines >= 2 and _position() == start, "mining repeats independently after mouse release while wall remains", mines)
	await _click(MOUSE_BUTTON_RIGHT, _point(target))
	var before := mines
	await get_tree().create_timer(1.0).timeout
	_expect(main.get("_mine_target") == Vector2i(-1, -1) and mines == before, "new right operation cancels unsent mining repeats", mines)
	resource.land[index] = old_land
	_reset_hero()
	await get_tree().create_timer(0.1).timeout
	before = mines
	_modifier(KEY_SHIFT, true)
	_modifier(KEY_ALT, true)
	var point := _point(target)
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.shift_pressed = true
	click.alt_pressed = true
	click.position = point
	Input.parse_input_event(click)
	await get_tree().create_timer(0.08).timeout
	_release(MOUSE_BUTTON_LEFT, point)
	_modifier(KEY_SHIFT, false)
	_modifier(KEY_ALT, false)
	_expect(mines == before + 1 and _position() == start and main.get("_last_corpse_interaction_ms") == -1001, "pickaxe Shift forces a stationary strike before Alt harvesting", mines)
	before = mines
	await get_tree().create_timer(1.1).timeout
	_expect(mines == before and GameState.player_action_type == 2, "open front suppresses automatic mining repeats", mines)
	resource.land[index] = 0
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	before = mines
	GameState.wear = {}
	await get_tree().create_timer(1.1).timeout
	_expect(mines == before and main.get("_mine_target") == Vector2i(-1, -1), "removing pickaxe cancels automatic mining", mines)
	resource.land[index] = old_land
	_reset_hero()
	GameState.wear = {3: {"itemID": weapon}}
	var distant_wall := start + Vector2i.RIGHT * 3
	var distant_index: int = distant_wall.x + distant_wall.y * resource.width
	var old_distant_land: int = resource.land[distant_index]
	resource.land[distant_index] = 0
	await get_tree().create_timer(0.1).timeout
	before = mines
	_press(MOUSE_BUTTON_LEFT, _point(target))
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and mines == before:
		Input.warp_mouse(_point(target))
		await get_tree().create_timer(0.02).timeout
	_release(MOUSE_BUTTON_LEFT, _point(target))
	_expect(_position() == start + Vector2i.RIGHT * 2 and mines > before and main.get("_mine_target") == distant_wall, "held pickaxe walking switches to mining only upon reaching the wall", _position())
	main.call("_cancel_movement")
	resource.land[distant_index] = old_distant_land
	if failures.is_empty(): print("MIR3 MINING PASS: open-ground walking, adjacent wall strike, persistent repeat, right cancellation, Shift-before-Alt, equipment recheck")
	get_tree().quit(0 if failures.is_empty() else 1)

func _reset_hero() -> void:
	main.call("_cancel_movement")
	main.set("_player_action_timer", -1.0)
	GameState.player_x = start.x
	GameState.player_y = start.y
	GameState.player_direction = 3
	main.call("_set_player_action", 2)
	main.call("_center_hero")

func _modifier(key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _count_mines() -> void:
	if GameState.player_action_type == 14 and GameState.player_action_started_ms != last_started:
		last_started = GameState.player_action_started_ms
		mines += 1
