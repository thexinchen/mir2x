extends Node

const CORPSE_UID := 606
var main: Control

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 1 << 35
	GameState.player_map_id = 1
	GameState.player_x = 441
	GameState.player_y = 381
	GameState.creatures.clear()
	GameState.update_creature(CORPSE_UID, {"uid": CORPSE_UID, "type": 2, "gender": 0, "desp": {}, "x": 442, "y": 385, "direction": 5, "action_type": 13, "action_started_ms": 1, "action_speed": 100})
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	if not main.call("_load_world_map", 1):
		_fail("visual fixture map is unavailable")
		return
	main.call("_center_hero")
	main.get_node("MapLoadingOverlay").hide()
	var renderer: Control = main.get_node("WorldRenderer")
	GameState.player_map_name = renderer.world_resource.map_name
	# Use the stable final corpse frame rather than an early falling frame.
	await get_tree().create_timer(1.1).timeout
	for _frame in range(120):
		await get_tree().process_frame
		if not main.get_node("MapLoadingOverlay").visible and renderer.get("_corpse_target_rects").has(CORPSE_UID): break
	if not renderer.get("_corpse_target_rects").has(CORPSE_UID):
		_fail("actual corpse sprite did not create a target rectangle")
		return
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	var revive: int = main.get("_resources").magic_id("回生术")
	GameState.learned_magic = [{"magicID": revive}]
	GameState.magic_keys = {revive: 60}
	GameState.magic_cast_times.clear()
	var rect: Rect2 = renderer.get("_corpse_target_rects")[CORPSE_UID].rect
	Input.warp_mouse(rect.get_center())
	await get_tree().process_frame
	var actual_mouse := get_viewport().get_mouse_position()
	if not rect.has_point(actual_mouse) or renderer.focus_uid_at_screen(actual_mouse) != 0:
		_fail("mouse did not reach corpse hitbox or ordinary focus included it: %s" % actual_mouse)
		return
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	var matched := false
	for effect in GameState.magic_effects:
		if int(effect.get("magicID", 0)) == revive and int(effect.get("aimUID", 0)) == CORPSE_UID and int(effect.get("direction", 0)) == 5: matched = true
	if not matched or GameState.player_action_type != 9 or GameState.player_direction != 5 or main.get("_magic_focus_uid") != CORPSE_UID:
		_fail("F12 did not cast downward at the rendered near-axis corpse: action=%d focus=%s effects=%s" % [GameState.player_action_type, main.get("_magic_focus_uid"), GameState.magic_effects])
		return
	if OS.has_environment("MIR2X_RESURRECTION_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_RESURRECTION_SCREENSHOT")) != OK:
			_fail("could not save target screenshot")
			return
	print("MIR3 RESURRECTION TARGET VISUAL PASS: actual corpse sprite/hitbox, cursor warp and F12 event, local spell retains corpse UID and original near-axis down direction; no server revival claimed")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("RESURRECTION TARGET VISUAL: " + message)
	get_tree().quit(1)
