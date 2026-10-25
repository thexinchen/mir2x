extends Node

var main: Control
var renderer: Control
var failures: Array[String] = []
var start := Vector2i.ZERO


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.set_player_online({"uid": (5 << 59) | (1 << 35) | 1, "name": "移动验证", "map_uid": 24 << 35, "x": 405, "y": 120, "direction": 3})
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	renderer = main.get_node("WorldRenderer")
	if not main.call("_load_world_map", 24):
		push_error("movement test map unavailable")
		get_tree().quit(1)
		return
	start = _find_corridor()
	GameState.player_x = start.x
	GameState.player_y = start.y
	GameState.player_map_name = renderer.world_resource.map_name
	main.call("_set_player_action", 2)
	main.call("_center_hero")
	await get_tree().create_timer(0.4).timeout
	main.get_node("MapLoadingOverlay").hide()
	await _click(MOUSE_BUTTON_LEFT, _point(start + Vector2i(5, 0)))
	_expect(_position() == start + Vector2i(1, 0), "single click moves one cell", _position())
	await get_tree().create_timer(0.8).timeout
	_expect(_position() == start + Vector2i(1, 0), "single click does not walk to target", _position())
	var before := _position()
	_press(MOUSE_BUTTON_LEFT, _point(before + Vector2i(6, 0)))
	await get_tree().create_timer(1.9).timeout
	_release(MOUSE_BUTTON_LEFT, Vector2(400, 570))
	var after := _position()
	_expect(after.x >= before.x + 3 and after.y == before.y, "held left repeats", after)
	await get_tree().create_timer(0.8).timeout
	_expect(_position() == after, "release over HUD stops repeats", _position())
	before = _position()
	await _click(MOUSE_BUTTON_RIGHT, _point(before + Vector2i(0, 1)))
	_expect(_position() == before and GameState.player_direction == 5, "near right only turns", _position())
	_press(MOUSE_BUTTON_RIGHT, _point(before + Vector2i(6, 0)))
	await get_tree().create_timer(1.4).timeout
	_release(MOUSE_BUTTON_RIGHT, _point(before + Vector2i(6, 0)))
	after = _position()
	_expect(after.x >= before.x + 4 and after.y == before.y, "held right runs", after)
	await get_tree().create_timer(0.8).timeout
	_expect(_position() == after, "right release stops", _position())
	# A real GUI panel catches the press; it must not start ground input.
	_press(MOUSE_BUTTON_LEFT, Vector2(400, 570))
	await get_tree().create_timer(0.8).timeout
	_expect(_position() == after, "HUD press does not move", _position())
	_release(MOUSE_BUTTON_LEFT, Vector2(400, 570))
	await get_tree().process_frame
	var output := OS.get_environment("MIR2X_MOVEMENT_SCREENSHOT")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(output)
	if failures.is_empty():
		print("MIR3 MOVEMENT VISUAL PASS: real main scene, map 24, Input.parse_input_event, click/held left/held right/release over HUD/near turn. start=%s end=%s" % [start, _position()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _find_corridor() -> Vector2i:
	for y in range(100, 450):
		for x in range(300, 450):
			var clear := true
			for dx in range(22):
				for dy in range(-1, 2):
					if not renderer.can_walk(x + dx, y + dy):
						clear = false
			if clear:
				return Vector2i(x, y)
	push_error("no test corridor found")
	return Vector2i(405, 120)


func _position() -> Vector2i:
	return Vector2i(GameState.player_x, GameState.player_y)


func _point(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * 48 + 24 - int(GameState.view_x), tile.y * 32 + 16 - int(GameState.view_y))


func _press(button: int, point: Vector2) -> void:
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)


func _release(button: int, point: Vector2) -> void:
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = false
	Input.parse_input_event(event)


func _click(button: int, point: Vector2) -> void:
	_press(button, point)
	await get_tree().create_timer(0.08).timeout
	_release(button, point)


func _expect(value: bool, message: String, actual: Variant) -> void:
	print("MOVEMENT CHECK %s: %s actual=%s" % ["PASS" if value else "FAIL", message, actual])
	if not value:
		failures.append(message)
		push_error(message)
