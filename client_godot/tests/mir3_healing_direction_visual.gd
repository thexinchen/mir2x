extends Node

var main: Control

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 1 << 35
	GameState.player_map_id = 1
	GameState.player_x = 441
	GameState.player_y = 381
	GameState.player_action_type = 2
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.creatures.clear()
	GameState.magic_effects.clear()
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	if not main.call("_load_world_map", 1):
		_fail("map unavailable")
		return
	main.call("_center_hero")
	main.get_node("MapLoadingOverlay").hide()
	var heal: int = main.get("_resources").magic_id("治愈术")
	GameState.learned_magic = [{"magicID": heal}]
	GameState.magic_keys = {heal: 60}
	await get_tree().process_frame
	var anchor := Vector2(GameState.player_x * 48 - int(GameState.view_x), GameState.player_y * 32 - int(GameState.view_y))
	# These shallow/steep offsets distinguish pixel sectors from tile signs.
	var cases := [[Vector2(180, 32), 3], [Vector2(60, -180), 1], [Vector2(120, -80), 2], [Vector2(120, 80), 4], [Vector2(60, 180), 5], [Vector2(-120, 80), 6], [Vector2(-180, 32), 7], [Vector2(-120, -80), 8], [Vector2.ZERO, 5]]
	for sample in cases:
		GameState.magic_cast_times.clear()
		GameState.player_direction = 1
		GameState.player_action_type = 2
		Input.warp_mouse(anchor + sample[0])
		await get_tree().process_frame
		if get_viewport().get_mouse_position().distance_to(anchor + sample[0]) > 1:
			_fail("cursor warp failed")
			return
		var key := InputEventKey.new()
		key.keycode = KEY_F12
		key.pressed = true
		Input.parse_input_event(key)
		await get_tree().process_frame
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		if GameState.player_direction != sample[1] or GameState.player_action_type != 9:
			_fail("F12 pixel offset %s: expected %d actual %d action %d" % [sample[0], sample[1], GameState.player_direction, GameState.player_action_type])
			return
	# Capture a shallow rightward cursor while moving, then move it left before release.
	GameState.player_action_type = 3
	GameState.player_action_from_x = GameState.player_x
	GameState.player_action_from_y = GameState.player_y
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec()
	Input.warp_mouse(anchor + Vector2(180, 32))
	await get_tree().process_frame
	main.call("_send_spell_action", 9, heal, Vector2i(445, 382), 0)
	if main.get("_pending_spell_action").get("direction_override", 0) != 3:
		_fail("moving request did not capture rightward screen-facing")
		return
	Input.warp_mouse(anchor + Vector2(-180, 32))
	await get_tree().process_frame
	main.call("_release_pending_spell")
	if GameState.player_direction != 3:
		_fail("queued heal resampled cursor at release")
		return
	# A moving hero is drawn left of its logical destination. Aim steeply down
	# from that drawn position; using the destination instead would face down-left.
	GameState.player_action_type = 3
	GameState.player_action_from_x = GameState.player_x - 1
	GameState.player_action_from_y = GameState.player_y
	GameState.player_action_started_ms = Time.get_ticks_msec()
	var renderer: Control = main.get_node("WorldRenderer")
	var draw_grid: Vector2 = renderer.player_draw_grid()
	var moving_anchor := Vector2(roundi(draw_grid.x * 48) - int(GameState.view_x), roundi(draw_grid.y * 32) - int(GameState.view_y))
	Input.warp_mouse(moving_anchor + Vector2(12, 60))
	await get_tree().process_frame
	main.call("_send_spell_action", 9, heal, Vector2i(441, 383), 0)
	if main.get("_pending_spell_action").get("direction_override", 0) != 5:
		_fail("moving heal used logical destination instead of interpolated screen anchor")
		return
	print("MIR3 HEALING DIRECTION VISUAL PASS: F12 screen sectors, all eight directions, zero offset down, queued direction survives cursor change")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("HEALING DIRECTION: " + message)
	get_tree().quit(1)
