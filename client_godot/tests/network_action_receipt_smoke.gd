extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
var uid := 0
var map_uid := 0
var position := Vector2i.ZERO
var receipts: Dictionary = {}
var issued: Dictionary = {}
var response_counts: Dictionary = {}
var own_stands := 0
var last_stand := Vector2i.ZERO
var raw_receipts := 0
var finished := false

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.response_received.connect(func(id, _head, _payload): response_counts[id] = int(response_counts.get(id, 0)) + 1)
	NetworkClient.connect_to_server()
	get_tree().create_timer(20.0).timeout.connect(func(): _fail("overall timeout"))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		uid = int(data.uid)
		map_uid = int(data.mapUID)
		position = Vector2i(data.action.x, data.action.y)
		_run()
	elif head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if int(data.get("uid", 0)) == uid and int(data.get("action", {}).get("type", 0)) == 2:
			own_stands += 1
			last_stand = Vector2i(data.action.x, data.action.y)
	elif head in [NetworkClient.SM_OK, NetworkClient.SM_ERROR]:
		raw_receipts += 1
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _node(action_type := 2) -> Dictionary:
	return {"type": action_type, "speed": 100, "direction": 3, "x": position.x, "y": position.y, "aimX": position.x, "aimY": position.y}

func _receipt(head: int, _payload: PackedByteArray, token: String) -> void:
	var values: Array = receipts.get(token, [])
	values.append(head)
	receipts[token] = values

func _send(token: String, node: Dictionary, action_uid := -1, action_map := -1) -> bool:
	var before := Time.get_ticks_msec()
	var id := int(NetworkClient.get("_next_response_id"))
	issued[token] = id
	var payload := Protocol.encode_cm_action(uid if action_uid < 0 else action_uid, map_uid if action_map < 0 else action_map, node)
	if NetworkClient.send_action_request(payload, _receipt.bind(token)) != OK:
		_fail("send failed: " + token)
		return false
	var entry: Dictionary = NetworkClient.get("_response_callbacks").get(id, {})
	var expires := int(entry.get("expires", -1))
	if expires < before + 10001 or expires > Time.get_ticks_msec() + 10001:
		_fail("action receipt did not use its strict 10-second expiry tick: " + token)
		return false
	return true

func _wait(token: String, expected_head: int) -> bool:
	for _attempt in range(150):
		if receipts.has(token): break
		await get_tree().create_timer(0.01).timeout
	if receipts.get(token, []) != [expected_head]:
		_fail("wrong/missing/duplicate callback %s: %s" % [token, receipts.get(token, [])])
		return false
	var id: int = issued[token]
	if int(response_counts.get(id, 0)) != 1 or NetworkClient.get("_response_callbacks").has(id):
		_fail("response ID correlation/removal failed: " + token)
		return false
	return true

func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var before_id := int(NetworkClient.get("_next_response_id"))
	if NetworkClient.send_action_request(PackedByteArray(), _receipt.bind("bad-size")) != ERR_INVALID_DATA or int(NetworkClient.get("_next_response_id")) != before_id:
		_fail("malformed local payload consumed a request ID")
		return
	if not _send("stand", _node()) or not await _wait("stand", NetworkClient.SM_OK): return
	var stands_before := own_stands
	var invalid_move := _node(3)
	invalid_move.x += 20
	invalid_move.y += 20
	invalid_move.aimX = invalid_move.x + 1
	invalid_move.aimY = invalid_move.y
	if not _send("rejected-move", invalid_move) or not await _wait("rejected-move", NetworkClient.SM_OK): return
	for _attempt in range(50):
		if own_stands > stands_before: break
		await get_tree().create_timer(0.01).timeout
	if own_stands <= stands_before or last_stand != position:
		_fail("processing receipt was not accompanied by the independent rejected-move correction")
		return
	if not _send("wrong-owner", _node(), uid + 1) or not await _wait("wrong-owner", NetworkClient.SM_ERROR): return
	if not _send("wrong-map", _node(), uid, map_uid + 1) or not await _wait("wrong-map", NetworkClient.SM_ERROR): return
	if not _send("unknown-action", _node(31)) or not await _wait("unknown-action", NetworkClient.SM_ERROR): return
	if not _send("parallel-a", _node()) or not _send("parallel-b", _node()): return
	if not await _wait("parallel-a", NetworkClient.SM_OK) or not await _wait("parallel-b", NetworkClient.SM_OK): return
	if issued["parallel-a"] == issued["parallel-b"]:
		_fail("concurrent requests reused an ID")
		return
	var responses_before := response_counts.size()
	stands_before = own_stands
	NetworkClient.send_action(Protocol.encode_cm_action(uid, map_uid, _node()))
	await get_tree().create_timer(0.2).timeout
	if own_stands <= stands_before or response_counts.size() != responses_before or raw_receipts != 0:
		_fail("legacy action compatibility or response routing failed")
		return
	NetworkClient.get("_response_callbacks")[2147483647] = {"expires": -1, "callback": _receipt.bind("expired")}
	NetworkClient.call("_expire_responses")
	NetworkClient.call("_expire_responses")
	if receipts.get("expired", []) != [NetworkClient.SM_ERROR] or NetworkClient.get("_response_callbacks").has(2147483647):
		_fail("local expiry callback was not removed exactly once")
		return
	NetworkClient.get("_response_callbacks")[2147483646] = {"expires": -1, "callback": _receipt.bind("normal-not-timeout"), "timeout_callback": _receipt.bind("distinct-timeout")}
	NetworkClient.call("_expire_responses")
	if receipts.has("normal-not-timeout") or receipts.get("distinct-timeout", []) != [NetworkClient.SM_ERROR]:
		_fail("transport timeout was confused with a server receipt")
		return
	print("NETWORK ACTION RECEIPT PASS: correlated completion, rejected move correction, wrong owner/map/type, concurrent IDs, strict 10s expiry slot, local timeout and legacy action compatibility")
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("ACTION RECEIPT: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
