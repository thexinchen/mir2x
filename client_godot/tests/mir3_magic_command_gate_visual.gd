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
	GameState.magic_cast_times.clear()
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	if not main.call("_load_world_map", 1):
		_fail("map unavailable")
		return
	main.call("_center_hero")
	main.get_node("MapLoadingOverlay").hide()
	var thrust: int = main.get("_resources").magic_id("刺杀剑术")
	var half: int = main.get("_resources").magic_id("半月弯刀")
	GameState.learned_magic = [{"magicID": thrust}, {"magicID": half}]
	GameState.magic_keys = {thrust: 49, half: 50}
	await get_tree().process_frame
	_press(KEY_F1)
	await get_tree().process_frame
	if not bool(main.get("_swing_magic").get(thrust, false)):
		_fail("first F1 did not enable thrust")
		return
	_press(KEY_F2)
	await get_tree().process_frame
	if bool(main.get("_swing_magic").get(half, false)):
		_fail("rapid F2 bypassed shared command gate")
		return
	await get_tree().create_timer(0.52).timeout
	_press(KEY_F2)
	await get_tree().process_frame
	if not bool(main.get("_swing_magic").get(half, false)):
		_fail("F2 remained blocked after 500ms")
		return
	_press(KEY_F1)
	await get_tree().process_frame
	if not bool(main.get("_swing_magic").get(thrust, false)):
		_fail("rapid F1 disabled thrust inside gate")
		return
	await get_tree().create_timer(0.52).timeout
	_press(KEY_F1)
	await get_tree().process_frame
	if bool(main.get("_swing_magic").get(thrust, false)):
		_fail("F1 could not disable thrust after 500ms")
		return
	var rush: int = main.get("_resources").magic_id("野蛮冲撞")
	GameState.learned_magic.append({"magicID": rush})
	GameState.magic_keys[rush] = 51
	for uid in [606, 707, 808, 909]:
		GameState.update_creature(uid, {"uid": uid, "type": 2, "x": 443, "y": 381, "action_type": 2})
	var renderer: Control = main.get_node("WorldRenderer")
	var mouse := get_viewport().get_mouse_position()
	# A deterministic hover fixture exercises the actual focus resolver if the
	# command incorrectly enters it; no focus/send method is replaced.
	renderer.set("_actor_target_rects", {606: {"rect": Rect2(mouse - Vector2(10, 10), Vector2(20, 20)), "map_y": 381}})
	if int(renderer.call("focus_uid_at_screen", mouse)) != 606:
		_fail("rush hover fixture is not selectable")
		return
	main.set("_magic_focus_uid", 707)
	main.set("_magic_history_uid", 808)
	main.set("_locked_magic_target_uid", 909)
	var response_before := int(NetworkClient.get("_next_response_id"))
	_press(KEY_F3)
	if not _rush_preserved_targets(): return
	main.set("_last_magic_request_ms", -500)
	main.set("_last_impulse_magic_ms", -3000)
	_press(KEY_F3)
	if not _rush_preserved_targets(): return
	if int(NetworkClient.get("_next_response_id")) != response_before or GameState.player_x != 441 or GameState.player_y != 381 or GameState.player_action_type != 2:
		_fail("unsupported rush sent a request or predicted an action/displacement")
		return
	print("MIR3 MAGIC COMMAND GATE VISUAL PASS: real F1/F2/F3 events, cross-skill500ms gate, rush preserves focus/history/lock before and after readiness, no fake rush action")
	get_tree().quit()


func _rush_preserved_targets() -> bool:
	if main.get("_magic_focus_uid") != 707 or main.get("_magic_history_uid") != 808 or main.get("_locked_magic_target_uid") != 909:
		_fail("rush function key replaced an ordinary spell target channel")
		return false
	return true

func _press(keycode: int) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)

func _fail(message: String) -> void:
	push_error("COMMAND GATE VISUAL: " + message)
	get_tree().quit(1)
