extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const Movement = preload("res://scripts/game/mir3_movement.gd")

class HoldMain:
	extends "res://scripts/game/main.gd"
	var held_receipts: Array[Dictionary] = []
	func _on_action_receipt(head: int, payload: PackedByteArray, token: int, uid: int, map_uid: int) -> void:
		held_receipts.append({"head": head, "payload": payload, "token": token, "uid": uid, "map": map_uid})
	func deliver(record: Dictionary) -> void:
		super._on_action_receipt(record.head, record.payload, record.token, record.uid, record.map)

var main: Control
var origin := Vector2i.ZERO
var map_uid := 0
var stands := 0
var authoritative := Vector2i.ZERO
var stage := "connect"
var finished := false
var reconnect_started := false
var online_session := false
var reconnected := false
var reconnect_online_retries := 0
var scene_messages := 0
var wire_receipts: Array[Dictionary] = []

func _ready() -> void:
	NetworkClient.response_received.connect(func(id, head, _payload):
		wire_receipts.append({"id": id, "head": head, "pending": _pending() if main != null else 0}))
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(25.0).timeout.connect(func(): _fail("overall timeout stage=" + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		online_session = true
		var data := Protocol.decode_sm_online_ok(payload)
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job, "map_uid": data.mapUID, "x": data.action.x, "y": data.action.y, "direction": data.action.direction})
		if main != null:
			reconnected = true
			return
		main = load("res://scenes/game/main.tscn").instantiate()
		main.set_script(HoldMain)
		add_child(main)
		_run()
	elif head == NetworkClient.SM_STARTGAMESCENE:
		scene_messages += 1
	elif head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if int(data.get("uid", 0)) == GameState.player_uid and int(data.get("action", {}).get("type", 0)) == 2:
			stands += 1
			authoritative = Vector2i(data.action.x, data.action.y)
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		# The old player detaches on a different actor bucket after its channel
		# closes. Retry only the documented transient duplicate-online result.
		if reconnect_started and head == NetworkClient.SM_ONLINEERROR and payload.size() == 1 and payload[0] == 3 and reconnect_online_retries < 10:
			reconnect_online_retries += 1
			get_tree().create_timer(0.15).timeout.connect(func():
				if not finished: NetworkClient.enter_game())
			return
		_fail("login rejected head=%d reconnect=%s payload=%s" % [head, reconnect_started, payload.hex_encode()])

func _held() -> Array:
	return main.get("held_receipts")

func _pending() -> int:
	return int(main.get("_action_request_gate").pending_token)

func _wait_receipt() -> bool:
	for _attempt in range(100):
		if not _held().is_empty(): return true
		await get_tree().create_timer(0.01).timeout
	return false

func _probe(expected: Vector2i) -> bool:
	var before := stands
	# A deliberately invalid origin elicits the real server position without
	# moving the player. This separate Stand must not complete the held receipt.
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, map_uid, {"type": 3, "speed": 100, "direction": 3, "x": expected.x + 20, "y": expected.y + 20, "aimX": expected.x + 21, "aimY": expected.y + 20}))
	for _attempt in range(100):
		if stands > before: return authoritative == expected
		await get_tree().create_timer(0.01).timeout
	return false

func _run() -> void:
	stage = "load"
	await get_tree().create_timer(3.0).timeout
	origin = Vector2i(GameState.player_x, GameState.player_y)
	map_uid = GameState.player_map_uid
	if main.get_node("MapLoadingOverlay").visible or GameState.player_hp <= 0:
		_fail("loaded living player required")
		return
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	var target := origin
	for offset in Movement.DIRECTIONS:
		if Movement.can_step(origin, origin + offset, renderer.can_walk, main.call("_ground_occupied")):
			target = origin + offset
			break
	if target == origin or not main.call("_send_move_action", target.x, target.y) or not await _wait_receipt():
		_fail("first real move/receipt unavailable")
		return
	stage = "animate"
	var first: Dictionary = _held().pop_front()
	var token := _pending()
	# The normal movement dispatcher commits this timer after send_move_action.
	main.set("_move_step_timer", 0.6)
	GameState.update_creature(808, {"uid": 808, "type": 1, "x": target.x + 1, "y": target.y, "action_type": 2})
	main.set("_next_strike", true)
	main.call("_start_chase", 808)
	main.set_process(true)
	await get_tree().create_timer(0.3).timeout
	var drawn: Vector2 = renderer.player_draw_grid()
	if drawn.distance_to(Vector2(origin)) <= 0.0 or drawn.distance_to(Vector2(target)) <= 0.0:
		_fail("pending receipt froze or skipped committed movement interpolation: origin=%s target=%s drawn=%s action=%d position=(%d,%d) timer=%s" % [origin, target, drawn, GameState.player_action_type, GameState.player_x, GameState.player_y, main.get("_move_step_timer")])
		return
	await get_tree().create_timer(0.4).timeout
	main.set_process(false)
	if GameState.player_action_type != 2 or _pending() != token or main.get("_chase_target_uid") != 808 or not main.get("_next_strike"):
		_fail("animation did not finish independently of the pending receipt")
		return
	stage = "gui"
	main.call("_try_panel_hotkey", KEY_B)
	if not main.get_node("InventoryPanel").visible:
		_fail("waiting action blocked ordinary GUI interaction")
		return
	main.get_node("InventoryPanel").hide()
	if token == 0 or not await _probe(target) or _pending() != token:
		_fail("real server Stand incorrectly released pending action, or move was rejected")
		return
	stage = "blocked"
	var next_id := int(NetworkClient.get("_next_response_id"))
	if main.call("_send_move_action", origin.x, origin.y) or int(NetworkClient.get("_next_response_id")) != next_id:
		_fail("second move bypassed held receipt")
		return
	var effects_before := GameState.magic_effects.size()
	if main.call("_cast_magic", main.get("_resources").magic_id("治愈术"), target) or GameState.magic_effects.size() != effects_before:
		_fail("normal spell bypassed held action receipt")
		return
	var ground: RefCounted = main.get("_ground_input")
	ground.press(MOUSE_BUTTON_RIGHT, target + Vector2i.RIGHT, false)
	main.call("_process_ground_input", 0.35)
	if ground.button != MOUSE_BUTTON_RIGHT or not ground.pending or ground.held_seconds < 0.35:
		_fail("pending receipt lost held input or its queued cursor request")
		return
	main.call("_release_ground_input")
	if _pending() != token:
		_fail("mouse release forgot the in-flight action")
		return
	stage = "release-first"
	main.call("deliver", first)
	if _pending() != 0 or not main.call("_send_move_action", origin.x, origin.y):
		_fail("matching receipt did not allow next move")
		return
	var second_token := _pending()
	main.call("deliver", first)
	if _pending() != second_token or not await _wait_receipt() or not await _probe(origin):
		_fail("old receipt released the new request or return move failed")
		return
	stage = "scene"
	var second: Dictionary = _held().pop_front()
	main.call("_switch_player_map", map_uid, {"x": origin.x, "y": origin.y})
	if _pending() != 0:
		_fail("scene reset retained old waiting state")
		return
	var stand := Protocol.encode_cm_action(GameState.player_uid, map_uid, {"type": 2, "speed": 100, "direction": 3, "x": origin.x, "y": origin.y})
	main.call("_send_player_action", stand)
	var new_scene_token := _pending()
	main.call("deliver", second)
	if _pending() != new_scene_token or not await _wait_receipt():
		_fail("old scene receipt cleared a new request")
		return
	main.call("deliver", _held().pop_front())
	main.call("_send_player_action", stand)
	stage = "disconnect"
	main.set("_magic_focus_uid", 701)
	main.set("_locked_magic_target_uid", 704)
	main.set("_follow_focus_uid", 702)
	main.set("_attack_focus_uid", 703)
	main.get("_summon_spawn_blockers")[808] = {"token": 1, "map_uid": map_uid}
	online_session = false
	NetworkClient.disconnect_from_server()
	await get_tree().process_frame
	await get_tree().process_frame
	if _pending() != 0:
		_fail("disconnect did not clear pending action")
		return
	await get_tree().create_timer(0.5).timeout
	stage = "reconnect"
	reconnect_started = true
	NetworkClient.connect_to_server()
	for _attempt in range(250):
		if reconnected and scene_messages >= 2: break
		await get_tree().create_timer(0.01).timeout
	await get_tree().process_frame
	if not reconnected or scene_messages < 2:
		_fail("reconnection did not restore its scene")
		return
	if main.get("_magic_focus_uid") != 0 or main.get("_locked_magic_target_uid") != 0 or main.get("_follow_focus_uid") != 0 or main.get("_attack_focus_uid") != 0 or not main.get("_summon_spawn_blockers").is_empty():
		_fail("reconnection retained prior-scene targeting or summon blockers")
		return
	stage = "new-session"
	main.call("_send_player_action", stand)
	var reconnected_token := _pending()
	main.call("deliver", first)
	if _pending() != reconnected_token or not await _wait_receipt():
		_fail("old connection receipt cleared the reconnected request")
		return
	main.call("deliver", _held().pop_front())
	if _pending() != 0:
		_fail("reconnected request did not complete normally")
		return
	if not await _delayed_transport_receipt(stand):
		return
	print("NETWORK REQUEST GATE PASS: real move/receipt, committed interpolation/GUI, independent Stand isolation, blocked move/spell, held input preservation, matching/stale reply, map generation, reconnect target/blocker reset and receipt isolation, real 10s delayed-read expiry/late wire reply and original position restored")
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _delayed_transport_receipt(stand: PackedByteArray) -> bool:
	stage = "transport-delay"
	# Stop socket reads, not the scene clock. The server still processes this
	# real Stand; its response remains unread until after the request expires.
	NetworkClient.set_process(false)
	var old_id: int = NetworkClient.get("_next_response_id")
	main.call("_send_player_action", stand)
	var old_token := _pending()
	var entry: Dictionary = NetworkClient.get("_response_callbacks").get(old_id, {})
	var expires: int = entry.get("expires", 0)
	await get_tree().create_timer(1.1).timeout
	NetworkClient.call("_expire_responses")
	if old_token == 0 or _pending() != old_token or not NetworkClient.get("_response_callbacks").has(old_id):
		_fail("action expired at the generic one-second timeout")
		return false
	while Time.get_ticks_msec() < expires:
		await get_tree().create_timer(0.01).timeout
	NetworkClient.call("_expire_responses")
	if _pending() != 0 or NetworkClient.get("_response_callbacks").has(old_id):
		_fail("actual ten-second transport timeout did not clear its request")
		return false
	if main.call("_action_request_ready") or not main.call("_action_request_ready"):
		_fail("actual timeout did not deny the first check and allow the next")
		return false
	main.call("_send_player_action", stand)
	var current_token := _pending()
	NetworkClient.set_process(true)
	if not await _wait_receipt():
		_fail("new request failed after delayed socket reads resumed")
		return false
	var late_seen := false
	for receipt in wire_receipts:
		if receipt.id == old_id:
			late_seen = receipt.head == NetworkClient.SM_OK and receipt.pending == current_token
	if not late_seen or _pending() != current_token or _held().size() != 1:
		_fail("expired wire response interfered with the next request")
		return false
	main.call("deliver", _held().pop_front())
	if _pending() != 0:
		_fail("new response failed to release the request after timeout recovery")
		return false
	return true

func _fail(message: String) -> void:
	if finished: return
	finished = true
	NetworkClient.set_process(true)
	if online_session and map_uid != 0 and NetworkClient.is_connected_to_server():
		NetworkClient.send_request_space_move(map_uid, origin.x, origin.y)
		await get_tree().create_timer(0.5).timeout
	push_error("REQUEST GATE: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
