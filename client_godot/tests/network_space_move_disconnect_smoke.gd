extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const ROUNDS := 12
var rounds := 0
var expected_position := Vector2i.ZERO
var expected_map := 0
var finished := false
var online_retries := 0

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(30.0).timeout.connect(func(): _fail("overall timeout"))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEERROR and payload.size() == 1 and payload[0] == 3 and online_retries < 20:
		online_retries += 1
		await get_tree().create_timer(0.15).timeout
		NetworkClient.enter_game()
	elif head in [NetworkClient.SM_ONLINEERROR, NetworkClient.SM_LOGINERROR]:
		_fail("login/online rejected")
	elif head == NetworkClient.SM_ONLINEOK:
		online_retries = 0
		var data := Protocol.decode_sm_online_ok(payload)
		var point := Vector2i(data.action.x, data.action.y)
		if expected_map == 0:
			expected_map = data.mapUID
			expected_position = point
		if data.mapUID != expected_map or point != expected_position:
			_fail("same-position request changed persisted origin")
			return
		if rounds == ROUNDS:
			finished = true
			NetworkClient.disconnect_from_server()
			print("NETWORK SPACE MOVE DISCONNECT PASS: rounds=%d same-position bursts, immediate close, final relog origin=%s" % [rounds, point])
			get_tree().quit()
			return
		for _index in 3:
			if NetworkClient.send_request_space_move(data.mapUID, point.x, point.y) != OK:
				_fail("space move send failed")
				return
		rounds += 1
		NetworkClient.disconnect_from_server()
		await get_tree().create_timer(0.3).timeout
		if not finished: NetworkClient.connect_to_server()

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("SPACE MOVE DISCONNECT " + message + " rounds=" + str(rounds))
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
