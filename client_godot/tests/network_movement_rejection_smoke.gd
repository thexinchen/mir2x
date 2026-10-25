extends "res://tests/mir3_movement_visual.gd"

const Protocol = preload("res://scripts/network/protocol.gd")
const Movement = preload("res://scripts/game/mir3_movement.gd")
var finished := false
var stand_count := 0
var self_moves := 0
var authoritative := Vector2i.ZERO

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(20.0).timeout.connect(func(): _fail("timed out"))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		var action: Dictionary = data.action
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job, "map_uid": data.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
		main = load("res://scenes/game/main.tscn").instantiate()
		add_child(main)
		renderer = main.get_node("WorldRenderer")
		_run()
	elif head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		var action: Dictionary = data.get("action", {})
		if int(data.get("uid", 0)) == GameState.player_uid and int(action.get("type", 0)) == 2:
			authoritative = Vector2i(int(action.x), int(action.y))
			stand_count += 1
		elif int(data.get("uid", 0)) == GameState.player_uid and int(action.get("type", 0)) in [3, 5]:
			self_moves += 1
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	if main.get_node("MapLoadingOverlay").visible or GameState.player_hp <= 0:
		_fail("test actor is not ready")
		return
	main.set_process(false)
	start = _position()
	var target := start
	var occupied: Dictionary = main.call("_ground_occupied")
	for offset in Movement.DIRECTIONS:
		if Movement.can_step(start, start + offset * 2, renderer.can_walk, occupied):
			target = start + offset * 4
			break
	if target == start:
		_fail("no clear two-cell movement fixture")
		return
	_press(MOUSE_BUTTON_RIGHT, _point(target))
	await get_tree().process_frame
	# Reproduce an interrupted ground route without sending its queued nodes.
	var route: Array[Vector2i] = [start + (target - start) / 2, target]
	main.set("_move_path", route)
	main.set("_ground_path_active", true)
	var held = main.get("_ground_input")
	held.pending = false
	var before := stand_count
	_send_invalid_origin()
	for _i in range(100):
		await get_tree().create_timer(0.02).timeout
		if stand_count > before: break
	await get_tree().process_frame
	if stand_count <= before or authoritative != start or main.get("_ground_path_active") or not main.get("_move_path").is_empty():
		_fail("server rejection did not clear route: stands=%d latch=%s position=%s" % [stand_count, main.get("_ground_path_active"), authoritative])
		return
	if held.button != MOUSE_BUTTON_RIGHT:
		_fail("server rejection lost physically held button")
		return
	main.set_process(true)
	for _i in range(100):
		await get_tree().create_timer(0.02).timeout
		if _position() != start: break
	_release(MOUSE_BUTTON_RIGHT, Vector2(400, 570))
	var resumed := _position()
	if resumed == start:
		_fail("held input did not resume after real server rejection")
		return
	await get_tree().create_timer(0.8).timeout
	# A second rejected request reports the server position after the resumed
	# valid step, proving that step was accepted rather than only predicted.
	before = stand_count
	_send_invalid_origin()
	for _i in range(100):
		await get_tree().create_timer(0.02).timeout
		if stand_count > before: break
	if stand_count <= before or authoritative != resumed:
		_fail("resumed move was not accepted: predicted=%s server=%s" % [resumed, authoritative])
		return
	main.call("_start_move_to", start)
	for _i in range(150):
		await get_tree().create_timer(0.02).timeout
		if _position() == start and main.get("_move_step_timer") <= 0.0: break
	before = stand_count
	_send_invalid_origin()
	for _i in range(100):
		await get_tree().create_timer(0.02).timeout
		if stand_count > before: break
	if stand_count <= before or authoritative != start:
		_fail("test actor did not return to its initial server position")
		return
	if self_moves != 0:
		_fail("normal client movement unexpectedly echoed to self: %d" % self_moves)
		return
	print("NETWORK MOVEMENT REJECTION PASS: real reportStand, old route cleared, held input resumed, server accepted %s -> %s, no normal self-move echo" % [start, resumed])
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _send_invalid_origin() -> void:
	var action := {"type": 3, "speed": 100, "x": GameState.player_x + 10, "y": GameState.player_y, "aimX": GameState.player_x + 11, "aimY": GameState.player_y}
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("NETWORK MOVEMENT REJECTION: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
