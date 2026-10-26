extends "res://tests/network_inventory_cancel_smoke.gd"

const Movement = preload("res://scripts/game/mir3_movement.gd")
const LOCATION_PROBE = preload("res://tests/network_inventory_refresh_smoke.gd").LOCATION_PROBE

class HoldMain:
	extends "res://scripts/game/main.gd"
	var peer_uid := 0
	var hold_moves := false
	var held_moves: Array[PackedByteArray] = []
	func _on_server_message(head: int, payload: PackedByteArray) -> void:
		if hold_moves and head == NetworkClient.SM_ACTION:
			var data := Protocol.decode_sm_action(payload)
			if int(data.get("uid", 0)) == peer_uid and int(data.get("action", {}).get("type", 0)) in [2, 3, 5]:
				held_moves.append(payload.duplicate())
				return
		super._on_server_message(head, payload)
	func release_moves() -> void:
		hold_moves = false
		for payload in held_moves: super._on_server_message(NetworkClient.SM_ACTION, payload)

var role := ""
var exchange := ""
var original := Vector2i.ZERO
var original_map := 0
var aborting := false

func _ready() -> void:
	role = OS.get_environment("MIR3_REMOTE_BATCH_ROLE")
	exchange = OS.get_environment("MIR3_REMOTE_BATCH_EXCHANGE")
	if role not in ["actor", "observer"] or not DirAccess.dir_exists_absolute(exchange) or not OS.has_environment("MIR3_TEST_SERVER_DB"):
		_fail("requires actor/observer role, existing shared directory and read-only DB probe path")
		return
	var config := "user://network_remote_batch_%s.cfg" % role
	OS.set_environment("MIR3_PROTECTION_CONFIG", config)
	if FileAccess.file_exists(config): DirAccess.remove_absolute(config)
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4" if role == "actor" else "id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	get_tree().create_timer(45.0).timeout.connect(func(): _fail("overall timeout at " + _stage))
	NetworkClient.connect_to_server()

func _message(head: int, payload: PackedByteArray) -> void:
	if role == "observer" and head == NetworkClient.SM_ONLINEOK:
		var online := Protocol.decode_sm_online_ok(payload)
		GameState.set_player_online({"uid": online.uid, "name": online.name, "gender": online.gender, "job": online.job, "map_uid": online.mapUID, "x": online.action.x, "y": online.action.y, "direction": online.action.direction})
		_main = load("res://scenes/game/main.tscn").instantiate()
		_main.set_script(HoldMain)
		add_child(_main)
		_run()
		return
	super._message(head, payload)

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "batch world ready"): return
	original = Vector2i(GameState.player_x, GameState.player_y)
	original_map = GameState.player_map_uid
	var inventory_before := _inventory_signature()
	var belt_before: Array = GameState.belt.duplicate(true)
	var wear_before: Dictionary = GameState.wear.duplicate(true)
	if role == "actor": await _actor_run()
	else: await _observer_run()
	if _finished or aborting: return
	if _inventory_signature() != inventory_before or GameState.belt != belt_before or GameState.wear != wear_before or Vector2i(GameState.player_x, GameState.player_y) != original or GameState.player_map_uid != original_map:
		_fail("fixture changed inventory/equipment or failed to restore location")
		return
	if not _server_position(GameState.player_name, GameState.player_map_id, original):
		_fail("server DB does not confirm own original location")
		return
	_store(role + ".pass", "ok")
	print("NETWORK REMOTE MOVE BATCH PASS: role=" + role + "; real wire moves, ordered repeated edges, server DB endpoints, original inventory/equipment/location")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _actor_run() -> void:
	var destination := original
	var renderer: Control = _main.get_node("WorldRenderer")
	for offset in Movement.DIRECTIONS:
		if Movement.can_step(original, original + offset, renderer.can_walk, _main.call("_ground_occupied")):
			destination = original + offset
			break
	if destination == original:
		_fail("no legal actor walking edge")
		return
	_store("actor.json", JSON.stringify({"uid": str(GameState.player_uid), "map_uid": str(original_map), "map_id": GameState.player_map_id, "name": GameState.player_name, "x": original.x, "y": original.y, "dx": destination.x, "dy": destination.y}))
	if not await _wait(func(): return FileAccess.file_exists(exchange + "/observer.ready"), "observer capture ready"): return
	for step in 4:
		var target: Vector2i = destination if step % 2 == 0 else original
		_main.call("_start_move_to", target)
		if not await _wait(func(): return Vector2i(GameState.player_x, GameState.player_y) == target and _main.get("_move_step_timer") <= 0.0 and _main.get("_move_path").is_empty(), "real actor walking leg%d" % step): return
		if not await _wait(func(): return _server_position(GameState.player_name, GameState.player_map_id, target), "server DB leg%d" % step): return
		print("REMOTE BATCH DB LEG: %d target=%s" % [step, target])
	_store("actor.done", "ok")
	if not await _wait(func(): return FileAccess.file_exists(exchange + "/observer.done"), "observer ordered replay"): return

func _observer_run() -> void:
	if not await _wait(func(): return FileAccess.file_exists(exchange + "/actor.json"), "actor metadata"): return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/actor.json"))
	var uid: int = str(meta.uid).to_int()
	if str(meta.map_uid).to_int() != GameState.player_map_uid:
		_fail("test peers must start on the same map")
		return
	if not await _wait(func(): return not GameState.get_creature(uid).is_empty(), "known remote actor"): return
	_main.set("peer_uid", uid)
	_main.set("hold_moves", true)
	_store("observer.ready", "ok")
	if not await _wait(func(): return FileAccess.file_exists(exchange + "/actor.done") and _main.get("held_moves").size() >= 4, "four real server move broadcasts"): return
	var from := Vector2i(int(meta.x), int(meta.y))
	var destination := Vector2i(int(meta.dx), int(meta.dy))
	var actual: Array[PackedByteArray] = _main.get("held_moves")
	var steps := 0
	var packet_hex: Array[String] = []
	for payload in actual:
		packet_hex.append(payload.hex_encode())
		var action: Dictionary = Protocol.decode_sm_action(payload).action
		if int(action.type) != 3: continue
		var expected_from: Vector2i = from if steps % 2 == 0 else destination
		var expected_to: Vector2i = destination if steps % 2 == 0 else from
		if Vector2i(action.x, action.y) != expected_from or Vector2i(action.aimX, action.aimY) != expected_to:
			_fail("wire movement did not match ordered actor edge")
			return
		steps += 1
	if steps != 4 or not _server_position(str(meta.name), int(meta.map_id), from):
		_fail("requires exactly four authority-confirmed real walking packets")
		return
	_store("wire-moves.json", JSON.stringify({"uid": str(uid), "payload_hex": packet_hex}, "\t"))
	_main.call("release_moves")
	var peer := GameState.get_creature(uid)
	if Vector2i(peer.x, peer.y) != destination or Vector2i(peer.action_from_x, peer.action_from_y) != from or peer.get("motion_action_queue", []).size() < 3:
		_fail("batch overwrote first leg or lost repeated return edges")
		return
	await get_tree().create_timer(0.2).timeout
	peer = GameState.get_creature(uid)
	var renderer: Control = _main.get_node("WorldRenderer")
	var visual_started: int = renderer.call("_visual_movement_started_ms", "creature:%d" % uid, int(peer.action_started_ms), int(peer.action_type))
	var drawn: Vector2 = renderer.call("_action_draw_grid", int(peer.x), int(peer.y), int(peer.action_from_x), int(peer.action_from_y), int(peer.action_type), visual_started, int(peer.action_speed))
	var progress := (drawn - Vector2(from)).dot(Vector2(destination - from)) / float((destination - from).length_squared())
	if progress <= 0.0 or progress >= 1.0 or int(peer.action_type) != 3:
		_fail("real first movement did not interpolate before queued legs")
		return
	print("REMOTE BATCH DRAW: progress=%f captured=%d" % [progress, steps])
	if OS.has_environment("MIR3_REMOTE_BATCH_SCREENSHOT"):
		_main.set_process(false)
		GameState.center_camera_on_grid(drawn)
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_REMOTE_BATCH_SCREENSHOT"))
		_main.set_process(true)
		if error != OK:
			_fail("could not save real remote movement screenshot")
			return
	for target in [from, destination, from]:
		if not await _wait(func(): return Vector2i(GameState.get_creature(uid).x, GameState.get_creature(uid).y) == target and int(GameState.get_creature(uid).action_type) == 3, "observer ordered animation leg"): return
	if not await _wait(func(): return int(GameState.get_creature(uid).action_type) == 2 and GameState.get_creature(uid).get("motion_action_queue", []).is_empty(), "observer final idle"): return
	if Vector2i(GameState.get_creature(uid).x, GameState.get_creature(uid).y) != from:
		_fail("observer final actor position differs from server")
		return
	_store("observer.done", "ok")

func _server_position(player_name: String, map_id: int, target: Vector2i) -> bool:
	var output: Array = []
	var code := OS.execute("python3", PackedStringArray(["-c", LOCATION_PROBE, OS.get_environment("MIR3_TEST_SERVER_DB"), player_name]), output, true)
	if code != 0: return false
	var observed = JSON.parse_string("".join(output))
	return observed is Array and observed.size() == 3 and observed[0] == float(map_id) and observed[1] == float(target.x) and observed[2] == float(target.y)

func _store(name: String, value: String) -> void:
	var file := FileAccess.open(exchange + "/" + name, FileAccess.WRITE)
	if file == null:
		_fail("cannot write fixture exchange " + name)
		return
	file.store_string(value)
	file.close()

func _fail(message: String) -> void:
	if _finished or aborting: return
	aborting = true
	if role == "actor" and original_map > 0 and is_instance_valid(_main) and NetworkClient.is_connected_to_server() and Vector2i(GameState.player_x, GameState.player_y) != original:
		_main.call("_cancel_movement")
		NetworkClient.send_request_space_move(original_map, original.x, original.y)
		for _attempt in 200:
			if Vector2i(GameState.player_x, GameState.player_y) == original: break
			await get_tree().create_timer(0.01).timeout
	super._fail("remote batch " + role + ": " + message)
