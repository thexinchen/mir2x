extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const Movement = preload("res://scripts/game/mir3_movement.gd")
var role := ""
var main: Control
var online := false
var actor_uid := 0
var attacks: Array[Dictionary] = []
var finished := false
var expected_attacks := 2


func _ready() -> void:
	role = OS.get_environment("MIR2X_DIRECTIONAL_ROLE")
	expected_attacks = 3 if OS.has_environment("MIR2X_DIRECTIONAL_INPUT") else 2
	if role not in ["actor", "observer"]:
		_fail("MIR2X_DIRECTIONAL_ROLE must be actor or observer")
		return
	NetworkClient.connection_changed.connect(_on_connection)
	NetworkClient.message_received.connect(_on_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(15.0).timeout.connect(func(): _fail("timed out role=%s attacks=%d" % [role, attacks.size()]))


func _on_connection(connected: bool, _message: String) -> void:
	if connected:
		NetworkClient.login("id_4" if role == "actor" else "id_3", "123456")


func _on_message(head: int, payload: PackedByteArray) -> void:
	if finished:
		return
	if head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("server rejected login")
	elif head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		var action: Dictionary = data.get("action", {})
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job, "map_uid": data.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
		main = load("res://scenes/game/main.tscn").instantiate()
		add_child(main)
		online = true
		if role == "actor":
			_run_actor()
	elif role == "observer" and head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		var action: Dictionary = data.get("action", {})
		# id_4 is database player 7 in the standard test fixture.
		if (int(data.get("uid", 0)) & 0xFFFFFFFF) != 7 or int(action.get("type", 0)) != 7:
			return
		actor_uid = int(data.uid)
		if action.get("aimUID", 0) != 0 or action.get("speed", 0) != 100 or int(action.get("direction", 0)) not in range(1, 9):
			_fail("invalid authoritative empty swing: %s" % action)
			return
		if main.call("_attack_direction", actor_uid, action) != action.direction:
			_fail("observer did not preserve explicit empty-swing facing")
			return
		attacks.append(action)
		if attacks.size() > expected_attacks:
			_fail("server accepted an invalid or cooldown-bypassing attack")
		elif attacks.size() == expected_attacks:
			_verify_observer()


func _run_actor() -> void:
	await get_tree().create_timer(2.0).timeout
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var occupied: Dictionary = main.call("_ground_occupied")
	var facing := 0
	for d in range(8):
		if not occupied.has(origin + Movement.DIRECTIONS[d]):
			facing = d + 1
			break
	if not facing or main.get_node("MapLoadingOverlay").visible or not NetworkClient.is_connected_to_server():
		_fail("test actor not ready or no empty front cell")
		return
	var physical: int = main.get("_resources").magic_id("物理攻击")
	if physical == 0:
		_fail("physical attack metadata unavailable")
		return
	if OS.has_environment("MIR2X_DIRECTIONAL_INPUT"):
		await _run_actor_input(origin, facing, physical)
		return
	var action := {"type": 7, "speed": 500, "direction": facing, "x": origin.x, "y": origin.y, "aimUID": 0, "magicID": physical}
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
	await get_tree().create_timer(0.1).timeout
	# A valid-looking burst and invalid origin/facing must all be rejected.
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
	action.x = origin.x + 10
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
	action.x = origin.x
	action.direction = 0
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
	await get_tree().create_timer(0.8).timeout
	action.direction = facing
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
	await get_tree().create_timer(1.5).timeout
	if Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("directional attack moved its actor")
		return
	print("DIRECTIONAL ATTACK ACTOR PASS: two valid attacks, invalid burst/origin/facing sent, unchanged position=%s" % origin)
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit(0)


func _verify_observer() -> void:
	await get_tree().create_timer(1.0).timeout
	if attacks.size() != expected_attacks or attacks[0].x != attacks[-1].x or attacks[0].y != attacks[-1].y:
		_fail("observer expected exactly %d in-place swings" % expected_attacks)
		return
	print("DIRECTIONAL ATTACK OBSERVER PASS: %d server broadcasts, speed=100, facing preserved, no extra attacks" % attacks.size())
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit(0)


func _run_actor_input(origin: Vector2i, facing: int, physical: int) -> void:
	var target: Vector2i = origin + Movement.DIRECTIONS[facing - 1] * 4
	var point := Vector2(target.x * 48 + 24 - int(GameState.view_x), target.y * 32 + 16 - int(GameState.view_y))
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	Input.parse_input_event(key)
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.pressed = true
	click.shift_pressed = true
	Input.parse_input_event(click)
	await get_tree().create_timer(0.1).timeout
	var output := OS.get_environment("MIR2X_DIRECTIONAL_SCREENSHOT")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(output)
	var duration: float = main.call("_action_duration", 7, 100, 2, physical)
	await get_tree().create_timer(duration * 2.0 + 0.15).timeout
	click.pressed = false
	Input.parse_input_event(click)
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().create_timer(1.0).timeout
	if Vector2i(GameState.player_x, GameState.player_y) != origin or main.get("_ground_input").button != 0:
		_fail("Shift input moved its actor or remained stuck after release")
		return
	print("DIRECTIONAL ATTACK ACTOR PASS: actual held Shift input/release, unchanged position=%s" % origin)
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit(0)


func _fail(message: String) -> void:
	if finished:
		return
	finished = true
	push_error("NETWORK DIRECTIONAL ATTACK: %s" % message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
