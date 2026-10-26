extends Node

var failures: Array[String] = []
var main: Control

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 1 << 35
	GameState.player_map_id = 1
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_action_type = 2
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	GameState.center_camera_on_grid(Vector2(10, 10))
	GameState.set("_camera_scrolling", true)
	var path: Array[Vector2i] = [Vector2i(11, 10), Vector2i(12, 10)]
	main.set("_move_path", path)
	main.set("_move_step_timer", 0.2)
	main.set("_pending_spell_action", {"action_type": 9})
	main.set("_pickup_action_timer", 0.2)
	main.get("_ground_input").press(MOUSE_BUTTON_LEFT, Vector2i(12, 10), false)
	main.set("_player_server_move_active", true)
	var queued: Array[Dictionary] = [warp(101, Vector2i(11, 10))]
	main.set("_player_server_action_queue", queued)
	main.call("_handle_action_data", warp(101, Vector2i(60, 65)))
	check_position(Vector2i(60, 65))
	check(main.get("_move_path").is_empty() and main.get("_pending_spell_action").is_empty() and main.get("_pickup_action_timer") < 0.0 and main.get("_ground_input").button == 0, "warp cancels old movement/spell/pickup/input")
	check(main.get("_player_server_action_queue").is_empty() and not main.get("_player_server_move_active"), "warp supersedes server motion queue")
	main.call("_process_player_action", 5.0)
	check(GameState.player_action_type == 2 and Vector2i(GameState.player_x, GameState.player_y) == Vector2i(60, 65), "old actions do not resume after warp")
	GameState.player_action_type = 13
	var forced: Array[Dictionary] = [{"kind": "move", "x": 9, "y": 9}, {"kind": "death", "action": {"type": 13}}]
	main.set("_player_forced_action_queue", forced)
	main.set("_player_post_forced_action", {"action": {"type": 2, "x": 9, "y": 9}})
	main.call("_handle_action_data", warp(101, Vector2i(80, 82)))
	check_position(Vector2i(80, 82))
	check(main.get("_player_forced_action_queue").is_empty() and main.get("_player_post_forced_action").is_empty(), "authoritative warp flushes stale forced/death display")
	var view := Vector2(GameState.view_x, GameState.view_y)
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 20, "y": 20, "action_type": 2})
	main.call("_handle_action_data", warp(606, Vector2i(90, 20)))
	check(Vector2(GameState.view_x, GameState.view_y) == view and GameState.get_creature(606).x == 90, "remote warp does not recenter local view")
	if failures.is_empty(): print("SELF SPACE MOVE PASS: immediate position/camera, local queue cancellation, forced/death display override, no stale action replay, remote view isolation")
	get_tree().quit(0 if failures.is_empty() else 1)

func check_position(target: Vector2i) -> void:
	check(Vector2i(GameState.player_x, GameState.player_y) == target, "authoritative warp position")
	check(is_equal_approx(GameState.view_x, target.x * 48.0 - 400.0) and is_equal_approx(GameState.view_y, target.y * 32.0 - GameState.camera_center_y()), "warp camera centers immediately")
	check(not GameState.get("_camera_scrolling"), "warp clears old camera convergence")

func warp(uid: int, target: Vector2i) -> Dictionary:
	return {"uid": uid, "mapUID": GameState.player_map_uid, "action": {"type": 6, "x": GameState.player_x, "y": GameState.player_y, "aimX": target.x, "aimY": target.y, "direction": 3, "speed": 100}}

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
