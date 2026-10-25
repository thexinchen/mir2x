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
	print("MIR3 MAGIC COMMAND GATE VISUAL PASS: real F1/F2 events, rapid cross-skill rejection, wall-clock enable/disable after 500ms")
	get_tree().quit()

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
