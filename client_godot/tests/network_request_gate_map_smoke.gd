extends Node

const Protocol = preload("res://scripts/network/protocol.gd")

class HoldMain:
	extends "res://scripts/game/main.gd"
	var held: Array[Dictionary] = []
	func _on_action_receipt(head: int, body: PackedByteArray, token: int, uid: int, map_uid: int) -> void:
		held.append({"head": head, "body": body, "token": token, "uid": uid, "map": map_uid})
	func deliver(receipt: Dictionary) -> void:
		super._on_action_receipt(receipt.head, receipt.body, receipt.token, receipt.uid, receipt.map)

var main: Control
var origin := Vector2i.ZERO
var origin_map := 0
var target_map := 0
var own_stands := 0
var finished := false
var stage := "login"

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(30.0).timeout.connect(func(): _fail("timeout: " + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job, "map_uid": data.mapUID, "x": data.action.x, "y": data.action.y, "direction": data.action.direction})
		origin_map = data.mapUID
		origin = Vector2i(data.action.x, data.action.y)
		main = load("res://scenes/game/main.tscn").instantiate()
		main.set_script(HoldMain)
		add_child(main)
		main.set_process(false)
		_run()
	elif head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if int(data.get("uid", 0)) == GameState.player_uid and int(data.get("action", {}).get("type", 0)) == 2:
			own_stands += 1
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _pending() -> int:
	return int(main.get("_action_request_gate").pending_token)

func _stand() -> PackedByteArray:
	return Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, {"type": 2, "speed": 100, "direction": 3, "x": GameState.player_x, "y": GameState.player_y})

func _receipt() -> Dictionary:
	for _attempt in range(150):
		if not main.get("held").is_empty():
			return main.get("held").pop_front()
		await get_tree().create_timer(0.01).timeout
	return {}

func _relocate(map_uid: int, position: Vector2i) -> bool:
	var before := own_stands
	if NetworkClient.send_request_space_move(map_uid, position.x, position.y) != OK:
		return false
	for _attempt in range(500):
		# requestMapSwitch reports the new map with a real SM_ACTION/Stand;
		# SM_STARTGAMESCENE is an initial-login message, not a map-switch reply.
		if own_stands > before and GameState.player_map_uid == map_uid and Vector2i(GameState.player_x, GameState.player_y) == position:
			return main.get("world_renderer").world_resource.map_id == GameState.player_map_id
		await get_tree().create_timer(0.01).timeout
	return false

func _run() -> void:
	stage = "initial scene"
	await get_tree().create_timer(2.0).timeout
	# The fixture uses two safe town positions and restores its original map.
	var target_id := 1 if GameState.player_map_id != 1 else 24
	var target_position := Vector2i(371, 335) if target_id == 1 else Vector2i(405, 118)
	NetworkClient.send_query_map_base_uid(target_id, func(head, payload):
		if head == NetworkClient.SM_UID and payload.size() == 8: target_map = payload.decode_u64(0))
	for _attempt in range(150):
		if target_map != 0: break
		await get_tree().create_timer(0.01).timeout
	if target_map == 0:
		_fail("destination map UID unavailable")
		return
	main.call("_send_player_action", _stand())
	var old := await _receipt()
	if old.is_empty() or _pending() == 0:
		_fail("origin pending request unavailable")
		return
	stage = "outbound map switch"
	if not await _relocate(target_map, target_position) or _pending() != 0:
		_fail("real destination scene did not clear the old request")
		return
	main.call("_send_player_action", _stand())
	var target_token := _pending()
	main.call("deliver", old)
	var target_receipt := await _receipt()
	if target_token == 0 or _pending() != target_token or target_receipt.is_empty():
		_fail("old-map receipt interfered with destination request")
		return
	stage = "return map switch"
	# Keep the destination receipt pending while the actual return scene arrives.
	if not await _relocate(origin_map, origin) or _pending() != 0:
		_fail("real return scene did not clear the destination request")
		return
	main.call("_send_player_action", _stand())
	var fresh_token := _pending()
	main.call("deliver", old)
	main.call("deliver", target_receipt)
	var fresh := await _receipt()
	if fresh_token == 0 or _pending() != fresh_token or fresh.is_empty():
		_fail("old generation receipt cleared request after returning to the same map")
		return
	main.call("deliver", fresh)
	if _pending() != 0 or not main.call("_action_request_ready"):
		_fail("new map receipt did not release input")
		return
	print("NETWORK REQUEST GATE MAP PASS: maps=%d->%d->%d pos=%s; real Stand transitions, pending reset, old-map/same-map generation isolation, loaded world matches map and origin restored" % [GameState.player_map_id, target_id, GameState.player_map_id, origin])
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	if origin_map != 0 and NetworkClient.is_connected_to_server():
		NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
		await get_tree().create_timer(1.0).timeout
	push_error("REQUEST GATE MAP: " + reason)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
