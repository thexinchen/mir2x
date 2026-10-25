extends "res://tests/mir3_movement_visual.gd"

var attack_count := 0
var last_attack_started := -1


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
	var resource: RefCounted = renderer.world_resource
	var front_index: int = start.x + 1 + start.y * resource.width
	var old_land: int = resource.land[front_index]
	resource.land[front_index] = 0
	var target := start + Vector2i(6, 0)
	GameState.ground_items["%d,%d" % [target.x, target.y]] = [1]
	var actor_resources: RefCounted = main.get("_resources")
	for item in actor_resources.item_attributes:
		if actor_resources.item_can_mine(int(item)):
			GameState.wear = {3: {"itemID": int(item)}}
			break
	GameState.state_changed.connect(_count_attacks)
	_shift(true)
	_press(MOUSE_BUTTON_LEFT, _point(target), true)
	await get_tree().create_timer(0.08).timeout
	_release(MOUSE_BUTTON_LEFT, _point(target))
	_expect(attack_count == 1 and _position() == start and GameState.player_direction == 3, "single Shift click swings east without moving across blocked ground", attack_count)
	_expect(main.get("_move_path").is_empty() and main.get("_mine_target") == Vector2i(-1, -1) and main.get("_pickup_target") == Vector2i(-1, -1), "Shift overrides mining, pickup and pathfinding", main.get("_move_path"))
	await get_tree().create_timer(0.9).timeout
	_expect(attack_count == 1, "single Shift click does not repeat after mouse release", attack_count)
	var before := attack_count
	_press(MOUSE_BUTTON_LEFT, _point(target), true)
	var physical_id: int = actor_resources.magic_id("物理攻击")
	var attack_duration: float = main.call("_action_duration", 7, 100, 2, physical_id)
	await get_tree().create_timer(attack_duration * 2.0 + 0.3).timeout
	_release(MOUSE_BUTTON_LEFT, Vector2(400, 570))
	_shift(false)
	_expect(attack_count >= before + 3 and _position() == start, "held Shift repeats attacks at action boundaries without moving", attack_count)
	before = attack_count
	await get_tree().create_timer(1.1).timeout
	_expect(attack_count == before, "HUD mouse release stops repeated attacks", attack_count)
	resource.land[front_index] = old_land
	GameState.ground_items.clear()
	GameState.wear = {}
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	_expect(_position() == start + Vector2i.RIGHT, "ordinary left click still walks after Shift release", _position())
	await get_tree().create_timer(0.7).timeout
	# Shift targeting a player uses chase/attack, but releasing Shift or the
	# mouse must not leave an unbounded player-attack chase running.
	GameState.creatures[123] = {"uid": 123, "type": 2, "x": start.x + 6, "y": start.y, "action_type": 2}
	renderer.set("_actor_target_rects", {123: {"rect": Rect2(180, 180, 40, 40), "map_y": start.y}})
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.shift_pressed = true
	click.position = Vector2(200, 200)
	main.call("_handle_mouse_click", click)
	_expect(main.get("_shift_chase_active") and main.get("_chase_target_uid") == 123, "Shift can explicitly target a player", main.get("_chase_target_uid"))
	click.pressed = false
	main.call("_input", click)
	_expect(main.get("_chase_target_uid") == 0 and main.get("_move_path").is_empty(), "mouse release cancels unsent Shift player chase", main.get("_chase_target_uid"))
	click.pressed = true
	main.call("_handle_mouse_click", click)
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = false
	main.call("_input", key)
	_expect(main.get("_chase_target_uid") == 0, "Shift release cancels unsent player chase", main.get("_chase_target_uid"))
	GameState.creatures.clear()
	GameState.state_changed.disconnect(_count_attacks)
	if failures.is_empty():
		print("MIR3 SHIFT ATTACK VISUAL PASS: single/held Shift, blocked ground, mining/pickup priority, release cancellation, ordinary movement")
	get_tree().quit(0 if failures.is_empty() else 1)


func _shift(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = pressed
	Input.parse_input_event(key)


func _count_attacks() -> void:
	if GameState.player_action_type == 7 and GameState.player_action_started_ms != last_attack_started:
		last_attack_started = GameState.player_action_started_ms
		attack_count += 1
