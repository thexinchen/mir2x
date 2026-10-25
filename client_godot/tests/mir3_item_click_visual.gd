extends "res://tests/mir3_movement_visual.gd"

class PickupMain:
	extends "res://scripts/game/main.gd"
	var pickup_requests := 0
	func _request_pickup() -> void:
		pickup_requests += 1

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.creatures.clear()
	GameState.wear = {}
	GameState.grabbed_item = {}
	main = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(PickupMain)
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
	var target := start + Vector2i.RIGHT * 3
	GameState.ground_items["%d,%d" % [target.x, target.y]] = [6]
	await _click(MOUSE_BUTTON_LEFT, _point(target))
	_expect(_position() == start + Vector2i.RIGHT, "single cached-item click walks one cell", _position())
	await get_tree().create_timer(1.0).timeout
	_expect(_position() == start + Vector2i.RIGHT and main.get("pickup_requests") == 0 and main.get("_move_path").is_empty(), "released item click neither auto-chases nor picks up", _position())
	main.call("_cancel_movement")
	GameState.player_x = start.x
	GameState.player_y = start.y
	main.call("_set_player_action", 2)
	main.call("_center_hero")
	await get_tree().create_timer(0.1).timeout
	_press(MOUSE_BUTTON_LEFT, _point(target))
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline and main.get("pickup_requests") == 0:
		# Keep pointing at the same world tile while the camera scrolls.
		Input.warp_mouse(_point(target))
		await get_tree().create_timer(0.02).timeout
	_release(MOUSE_BUTTON_LEFT, Vector2(400, 570))
	var count: int = main.get("pickup_requests")
	_expect(_position() == target and count > 0, "held left reaches item then requests current-cell pickup", _position())
	_expect(main.get("_pickup_action_timer") < 0.0, "held pickup does not create delayed auto-pickup animation", main.get("_pickup_action_timer"))
	await get_tree().create_timer(0.4).timeout
	_expect(main.get("pickup_requests") == count, "HUD release stops held current-cell pickup polling", main.get("pickup_requests"))
	if failures.is_empty(): print("MIR3 ITEM CLICK PASS: single-step item click, no automatic chase, held approach and current-cell pickup, HUD release")
	get_tree().quit(0 if failures.is_empty() else 1)
