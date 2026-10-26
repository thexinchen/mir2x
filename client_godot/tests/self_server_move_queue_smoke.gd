extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
var failures: Array[String] = []
const MAP_UID := 1 << 35
var main: Control

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = MAP_UID
	GameState.player_map_id = 1
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var ground: RefCounted = main.get("_ground_input")
	ground.press(MOUSE_BUTTON_RIGHT, Vector2i(20, 10), false)
	var old_path: Array[Vector2i] = [Vector2i(20, 10)]
	main.set("_move_path", old_path)
	main.set("_pickup_action_timer", 0.15)
	_deliver(_move(10, 11))
	var started: int = GameState.player_action_started_ms
	_deliver(_move(10, 11))
	_expect(main.get("_player_server_action_queue").is_empty() and GameState.player_action_started_ms == started, "immediate active duplicate does not queue or restart animation")
	_deliver(_move(11, 12))
	_deliver(_move(11, 12))
	_deliver(_stand(12))
	_expect(GameState.player_x == 11 and GameState.player_action_from_x == 10 and GameState.player_action_started_ms == started, "later authoritative move does not overwrite first animation")
	_expect(main.get("_player_server_action_queue").size() == 2, "second move and stand queue once in receive order")
	_expect(main.get("_move_path").is_empty() and ground.button == MOUSE_BUTTON_RIGHT, "forced move clears stale local route while preserving held button")
	_expect(main.get("_pickup_action_timer") < 0.0, "forced move cancels delayed pickup from the old tile")
	main.call("_process_ground_input", 0.5)
	_expect(ground.button == MOUSE_BUTTON_RIGHT and not ground.pending and ground.held_seconds >= 0.5, "held polling pauses while its time continues accumulating")
	_expect(main.call("_player_input_blocked"), "local actions wait for authority sequence")
	main.call("_release_ground_input")
	# Render real frame time so the renderer's movement clock is also tested.
	main.set_process(true)
	await get_tree().create_timer(0.3).timeout
	_expect(GameState.player_x == 11 and GameState.player_action_from_x == 10, "first leg remains active at half duration")
	var renderer: Control = main.get_node("WorldRenderer")
	var drawn: Vector2 = renderer.player_draw_grid()
	_expect(drawn.x > 10.0 and drawn.x < 11.0, "first leg interpolates rather than jumping to second endpoint")
	for _frame in range(120):
		await get_tree().process_frame
		if GameState.player_x == 12: break
	_expect(GameState.player_x == 12 and GameState.player_action_from_x == 11 and GameState.player_action_type == 3, "second leg starts after first completes: x=%d from=%d type=%d timer=%s queued=%s" % [GameState.player_x, GameState.player_action_from_x, GameState.player_action_type, main.get("_player_action_timer"), main.get("_player_server_action_queue")])
	for _frame in range(120):
		await get_tree().process_frame
		if GameState.player_action_type == 2: break
	_expect(GameState.player_x == 12 and GameState.player_action_type == 2 and main.get("_player_server_action_queue").is_empty(), "terminal stand applies after both legs")
	_expect(not main.call("_player_input_blocked"), "input resumes when authority sequence finishes")
	main.set_process(false)
	_deliver(_move(12, 13))
	_deliver(_move(13, 14))
	_deliver({"uid": 101, "mapUID": MAP_UID, "action": {"type": 6, "x": 15, "y": 10, "aimX": 15, "aimY": 10, "speed": 100, "direction": 3}})
	_expect(GameState.player_x == 15 and main.get("_player_server_action_queue").is_empty() and not main.get("_player_server_move_active"), "teleport invalidates older queued movement")
	_deliver(_move(15, 16))
	_deliver(_move(16, 17))
	main.call("_switch_player_map", MAP_UID, {"x": 15, "y": 10})
	_expect(main.get("_player_server_action_queue").is_empty() and not main.get("_player_server_move_active"), "scene change clears old authority queue")
	_deliver(_move(15, 16))
	GameState.player_hp = 0
	_deliver({"uid": 101, "mapUID": MAP_UID, "action": {"type": 13, "x": 16, "y": 10, "speed": 100, "direction": 3}})
	_expect(GameState.player_action_type == 3, "queued death waits for committed server move")
	main.call("_process_player_action", 0.61)
	_expect(GameState.player_action_type == 13 and GameState.player_x == 16, "death follows server move at its endpoint")
	GameState.player_hp = 100
	_deliver(_stand(16))
	_expect(GameState.player_action_type == 13, "revive still waits for death animation")
	main.call("_process_player_action", 1.1)
	_expect(GameState.player_action_type == 2 and not main.call("_player_input_blocked"), "revive and input recover after queued death")
	# A repeated edge after an intervening return leg is new motion, even
	# while the first copy is still the active animation on screen.
	_deliver(_move(16, 17))
	var cycle_started: int = GameState.player_action_started_ms
	_deliver(_move(17, 16))
	_deliver(_move(16, 17))
	_deliver(_move(16, 17))
	_deliver(_stand(17))
	_expect(main.get("_player_server_action_queue").size() == 3, "forward-return-forward retains repeated edge after intervening action while deduplicating adjacent copies")
	_expect(GameState.player_action_started_ms == cycle_started and GameState.player_x == 17, "queued cyclic movement preserves the active first leg")
	main.set_process(true)
	for _frame in range(120):
		await get_tree().create_timer(0.01).timeout
		if GameState.player_x == 16: break
	_expect(GameState.player_x == 16 and GameState.player_action_from_x == 17 and GameState.player_action_type == 3, "return leg plays before repeated forward edge")
	for _frame in range(120):
		await get_tree().create_timer(0.01).timeout
		if GameState.player_x == 17: break
	_expect(GameState.player_x == 17 and GameState.player_action_from_x == 16 and GameState.player_action_type == 3, "repeated forward edge animates instead of jumping straight to final stand")
	await get_tree().create_timer(0.2).timeout
	drawn = renderer.player_draw_grid()
	_expect(drawn.x > 16.0 and drawn.x < 17.0, "repeated forward edge has a real interpolated midpoint")
	if OS.has_environment("MIR3_SERVER_CYCLE_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		_expect(get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_SERVER_CYCLE_SCREENSHOT")) == OK, "cycle screenshot saves")
	for _frame in range(120):
		await get_tree().create_timer(0.01).timeout
		if GameState.player_action_type == 2: break
	_expect(GameState.player_x == 17 and GameState.player_action_type == 2 and main.get("_player_server_action_queue").is_empty(), "terminal stand follows all three cyclic legs")
	if failures.is_empty(): print("SELF SERVER MOVE QUEUE PASS: ordered legs/stand, adjacent duplicate suppression, repeated edges after return, real-frame interpolation, held/input handling, teleport/scene cleanup and death/revive ordering")
	get_tree().quit(0 if failures.is_empty() else 1)

func _move(from_x: int, to_x: int) -> Dictionary:
	return {"uid": 101, "mapUID": MAP_UID, "action": {"type": 3, "x": from_x, "y": 10, "aimX": to_x, "aimY": 10, "speed": 100, "direction": 3}}

func _stand(x: int) -> Dictionary:
	return {"uid": 101, "mapUID": MAP_UID, "action": {"type": 2, "x": x, "y": 10, "speed": 100, "direction": 3}}

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _deliver(data: Dictionary) -> void:
	var payload: PackedByteArray = Protocol.encode_cm_action(int(data.uid), int(data.mapUID), data.action)
	main.call("_on_server_message", NetworkClient.SM_ACTION, payload)
