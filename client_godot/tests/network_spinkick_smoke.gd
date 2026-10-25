extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const MARKER := "旋风腿方向验证"

var _role := "observer"
var _main: Control
var _online := false
var _armed := false
var _actor_started := false
var _finished := false
var _remote_uid := 0
var _reported_direction := -1
var _original_input := false


func _ready() -> void:
	_original_input = OS.get_environment("MIR2X_SPINKICK_INPUT") == "1"
	_role = OS.get_environment("MIR2X_SPINKICK_ROLE")
	if _role not in ["actor", "observer"]:
		_fail("invalid role: %s" % _role, 2)
		return
	NetworkClient.connection_changed.connect(_on_connection_changed)
	NetworkClient.message_received.connect(_on_message_received)
	NetworkClient.connect_to_server()
	get_tree().create_timer(25.0).timeout.connect(_on_timeout)


func _process(_delta: float) -> void:
	if _finished or not _online or _main == null:
		return
	if _main.get_node("MapLoadingOverlay").visible: return
	var remote := _find_remote_player()
	if remote.is_empty():
		return
	_remote_uid = int(remote.get("uid", 0))
	if _role == "actor":
		if not _actor_started:
			_actor_started = true
			_run_actor()
		return
	for message_value in GameState.player_say_messages.get(_remote_uid, []):
		if str(message_value.get("text", "")) == MARKER:
			_armed = true


func _on_connection_changed(connected: bool, _message: String) -> void:
	if not connected:
		return
	var account := "id_4" if _role == "actor" else "id_3"
	if NetworkClient.login(account, "123456") != OK:
		_fail("failed to send login for %s" % account, 3)


func _on_message_received(head_code: int, payload: PackedByteArray) -> void:
	if _finished:
		return
	match head_code:
		NetworkClient.SM_LOGINOK:
			if NetworkClient.enter_game() != OK:
				_fail("failed to enter game", 4)
		NetworkClient.SM_ONLINEOK:
			var online := Protocol.decode_sm_online_ok(payload)
			var action: Dictionary = online.get("action", {})
			GameState.set_player_online({
				"uid": online.get("uid", 0),
				"name": online.get("name", ""),
				"gender": online.get("gender", 0),
				"job": online.get("job", 0),
				"map_uid": online.get("mapUID", 0),
				"x": action.get("x", 0),
				"y": action.get("y", 0),
				"direction": action.get("direction", 0),
			})
			_main = load("res://scenes/game/main.tscn").instantiate() as Control
			add_child(_main)
			_online = true
		NetworkClient.SM_CORECORD:
			var record := Protocol.decode_sm_corecord(payload)
			if int(record.get("uid", 0)) == _remote_uid:
				_reported_direction = int(record.get("action", {}).get("direction", -1))
		NetworkClient.SM_ACTION:
			if _role != "observer" or not _armed:
				return
			var data := Protocol.decode_sm_action(payload)
			if int(data.get("uid", 0)) != _remote_uid:
				return
			var action: Dictionary = data.get("action", {})
			if int(action.get("type", 0)) == 2:
				_fail("actor sent an extra stand action before spin-kick", 8)
				return
			if int(action.get("type", 0)) != 12:
				return
			if int(action.get("direction", -1)) != (3 if _original_input else 0):
				_fail("broadcast spin-kick has an unexpected wire direction: %s" % action, 9)
				return
			if _original_input:
				if int(action.get("aimUID", -1)) != 0:
					_fail("original kick retained an actor target", 12)
					return
				await get_tree().process_frame
				if int(GameState.get_creature(_remote_uid).get("direction", 0)) != 3:
					_fail("observer did not render original rightward heading", 13)
					return
				_reported_direction = -1
				NetworkClient.send_query_corecord(_remote_uid)
				for _attempt in range(30):
					if _reported_direction >= 0: break
					await get_tree().create_timer(0.05).timeout
				if _reported_direction != 3:
					_fail("server core record did not retain original kick heading: %d" % _reported_direction, 14)
					return
			print("NETWORK SPINKICK OBSERVER PASS: uid=%d wire=%d original_input=%s no-extra-stand" % [_remote_uid, int(action.direction), _original_input])
			_finished = true
			NetworkClient.disconnect_from_server()
			get_tree().quit()
		NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR:
			_fail("server rejected login or online", 5)


func _run_actor() -> void:
	if _original_input:
		NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, {"type": 2, "speed": 100, "direction": 7, "x": GameState.player_x, "y": GameState.player_y}))
		GameState.player_direction = 7
		await get_tree().create_timer(0.3).timeout
	if NetworkClient.send_player_say(MARKER) != OK:
		_fail("failed to send observer marker", 6)
		return
	await get_tree().create_timer(0.6).timeout
	var initial_direction := GameState.player_direction
	var aim_grid := Vector2i(GameState.player_x + (-2 if initial_direction == 3 else 2), GameState.player_y)
	var resources: RefCounted = _main.get("_resources")
	var magic_id: int = resources.call("magic_id", "空拳刀法")
	var accepted := false
	if _original_input:
		var renderer: Control = _main.get_node("WorldRenderer")
		var draw_grid: Vector2 = renderer.player_draw_grid()
		Input.warp_mouse(Vector2(draw_grid.x * 48 - int(GameState.view_x) + 180, draw_grid.y * 32 - int(GameState.view_y)))
		await get_tree().process_frame
		_main.set("_magic_focus_uid", _remote_uid)
		accepted = _main.call("_cast_magic", magic_id, aim_grid)
	else:
		accepted = _main.call("_execute_spell_action", 12, magic_id, aim_grid, 0)
	if magic_id <= 0 or not accepted:
		_fail("local spin-kick action was rejected", 7)
		return
	if GameState.player_direction != (3 if _original_input else initial_direction):
		_fail("ground-only local spin-kick changed direction", 10)
		return
	await get_tree().create_timer(1.5).timeout
	print("NETWORK SPINKICK ACTOR PASS: local=%d aim=%s original_input=%s heading=%d" % [initial_direction, aim_grid, _original_input, GameState.player_direction])
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()


func _find_remote_player() -> Dictionary:
	# Standard fixture DB IDs: id_3=6, id_4=7, both on map24 within view.
	var expected_id := 6 if _role == "actor" else 7
	for uid_value in GameState.creatures:
		var creature: Dictionary = GameState.creatures[uid_value]
		if int(creature.get("type", 0)) == 2 and int(uid_value) != GameState.player_uid and (int(uid_value) & 0xFFFFFFFF) == expected_id:
			return creature
	return {}


func _on_timeout() -> void:
	_fail("timed out role=%s online=%s armed=%s remote=%d creatures=%s" % [_role, _online, _armed, _remote_uid, GameState.creatures], 11)


func _fail(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	push_error("NETWORK_SPINKICK_SMOKE %s" % message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(code)
