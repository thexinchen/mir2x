extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const SYS_ENTER := "_RSVD_NAME_ENTER_90360178872"
var main: Control
var finished := false
var stage := "login"
var sent_attacks := 0
var server_attacks := 0
var role := "killer"
var exchange := ""
var origin_map := 0
var origin := Vector2i.ZERO
var own_stands := 0

func _ready() -> void:
	exchange = OS.get_environment("MIR3_CORPSE_EXCHANGE")
	role = OS.get_environment("MIR3_CORPSE_ROLE") if not exchange.is_empty() else "killer"
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_3" if role == "contender" else "id_4", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(60.0).timeout.connect(func(): _fail("timeout at " + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	if head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if data.get("uid", 0) == GameState.player_uid and data.get("action", {}).get("type", 0) in [2, 6]: own_stands += 1
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		var action: Dictionary = data.action
		origin_map = data.mapUID
		origin = Vector2i(action.x, action.y)
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job, "map_uid": data.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
		main = load("res://scenes/game/main.tscn").instantiate()
		add_child(main)
		_run()
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")
	elif head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if int(data.get("uid", 0)) == GameState.player_uid and int(data.get("action", {}).get("type", 0)) == 7:
			server_attacks += 1

func _run() -> void:
	stage = "load map"
	await get_tree().create_timer(3.0).timeout
	var resources = main.get("_resources")
	if role == "contender":
		await _contend(resources)
		return
	# The standard id_4 fixture may be naked and have zero physical damage.
	# Give this test actor the same starter weapon used by wear smoke tests.
	if GameState.wear.get(3, {}).is_empty():
		var weapon: Dictionary = {}
		for item in GameState.inventory:
			if int(item.get("itemID", 0)) == 826: weapon = item
		if weapon.is_empty():
			NetworkClient.send_make_item(826)
			await get_tree().create_timer(0.5).timeout
			for item in GameState.inventory:
				if int(item.get("itemID", 0)) == 826: weapon = item
		if weapon.is_empty():
			_fail("starter weapon fixture unavailable")
			return
		NetworkClient.send_request_equip_wear(826, int(weapon.seqID), 3)
		await get_tree().create_timer(0.5).timeout
	var npc := 0
	for uid in GameState.creatures:
		var creature: Dictionary = GameState.creatures[uid]
		if creature.get("type", 0) == 3 and creature.get("x", 0) == 406 and creature.get("y", 0) == 126:
			npc = int(uid)
	if npc == 0:
		_fail("fixture requires map24 summoner at406,126")
		return
	stage = "summon chicken"
	NetworkClient.send_npc_event(npc, "", SYS_ENTER)
	await get_tree().create_timer(0.5).timeout
	var parser := XMLParser.new()
	parser.open_buffer(str(GameState.npc_dialog.get("xmlLayout", "")).to_utf8_buffer())
	var event_id := ""
	var chicken_event := ""
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "event":
			event_id = parser.get_named_attribute_value_safe("id")
		elif parser.get_node_type() == XMLParser.NODE_TEXT and parser.get_node_data() == "鸡，":
			chicken_event = event_id
	if chicken_event.is_empty():
		_fail("summoner chicken event unavailable")
		return
	var existing_uids := GameState.creatures.keys()
	NetworkClient.send_npc_event(npc, str(GameState.npc_dialog.get("eventPath", "")), chicken_event)
	await get_tree().create_timer(1.0).timeout
	var chicken := 0
	for uid in GameState.creatures:
		var creature: Dictionary = GameState.creatures[uid]
		if uid not in existing_uids and resources.monster_name(int(creature.get("monster_id", 0))) == "鸡" and creature.get("action_type", 2) != 13:
			chicken = int(uid)
			break
	if chicken == 0:
		_fail("summoned chicken not visible")
		return
	stage = "live target rejection"
	var before := _meat_count(resources)
	NetworkClient.send_harvest_corpse(chicken)
	await get_tree().create_timer(1.1).timeout
	if _meat_count(resources) != before:
		_fail("live monster granted meat")
		return
	stage = "kill chicken"
	var ground_meat_before := _ground_meat_count(resources)
	main.call("_start_chase", chicken)
	for _i in range(100):
		await get_tree().create_timer(0.2).timeout
		if GameState.player_action_type == 7: sent_attacks += 1
		if int(GameState.creatures.get(chicken, {}).get("action_type", 2)) == 13: break
	main.call("_cancel_movement")
	var corpse: Dictionary = GameState.creatures.get(chicken, {})
	if corpse.get("action_type", 2) != 13:
		_fail("normal attack did not leave harvestable corpse: hero=(%d,%d) hp=%d target=%s local_attack_frames=%d server_attacks=%d" % [GameState.player_x, GameState.player_y, GameState.player_hp, corpse, sent_attacks, server_attacks])
		return
	if _meat_count(resources) != before:
		_fail("death awarded meat before harvesting")
		return
	await get_tree().create_timer(0.3).timeout
	if _ground_meat_count(resources) != ground_meat_before:
		_fail("death placed harvestable meat on the ground")
		return
	stage = "claim meat"
	var point := Vector2i(int(corpse.x), int(corpse.y))
	main.call("_start_move_to", point)
	for _i in range(50):
		await get_tree().create_timer(0.2).timeout
		if Vector2i(GameState.player_x, GameState.player_y) == point and main.get("_move_step_timer") <= 0.0: break
	main.call("_cancel_movement")
	await get_tree().create_timer(1.1).timeout
	if not exchange.is_empty():
		_write("corpse.json", {"uid": str(chicken), "x": point.x, "y": point.y})
		if not await _wait_file("contender.ready"):
			_fail("contender did not reach corpse")
			return
		_write("claim.go", {"at": int(Time.get_unix_time_from_system() * 1000.0) + 250})
		await _race_claim(chicken, before, resources)
		return
	NetworkClient.send_harvest_corpse(chicken)
	await get_tree().create_timer(0.8).timeout
	var after := _meat_count(resources)
	if after <= before:
		_fail("corpse claim did not grant rolled meat")
		return
	stage = "duplicate claim rejection"
	await get_tree().create_timer(0.4).timeout
	NetworkClient.send_harvest_corpse(chicken)
	await get_tree().create_timer(0.8).timeout
	if _meat_count(resources) != after:
		_fail("duplicate claim granted meat twice")
		return
	finished = true
	if not await _restore_origin():
		push_error("CORPSE HARVEST origin restoration failed")
		get_tree().quit(1)
		return
	print("NETWORK CORPSE HARVEST PASS: normal kill, live rejection, retained corpse, meat gain=%d, duplicate rejection; origin=%s" % [after - before, origin])
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _meat_count(resources) -> int:
	var count := 0
	for item in GameState.inventory:
		if resources.item_name(int(item.get("itemID", 0))) == "鸡肉": count += int(item.get("count", 0))
	return count

func _ground_meat_count(resources) -> int:
	var count := 0
	for items in GameState.ground_items.values():
		for item in items:
			if resources.item_type(int(item.get("itemID", 0))) == "肉": count += int(item.get("count", 0))
	return count

func _write(name: String, value: Dictionary) -> void:
	FileAccess.open(exchange + "/" + name, FileAccess.WRITE).store_string(JSON.stringify(value))

func _wait_file(name: String) -> bool:
	for _attempt in 2000:
		if finished: return false
		if FileAccess.file_exists(exchange + "/" + name): return true
		await get_tree().create_timer(0.01).timeout
	return false

func _contend(resources) -> void:
	stage = "wait for killed corpse"
	if not await _wait_file("corpse.json"):
		_fail("killer did not publish corpse")
		return
	var corpse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/corpse.json"))
	var point := Vector2i(int(corpse.x) + 1, int(corpse.y))
	var before := _meat_count(resources)
	NetworkClient.send_request_space_move(origin_map, point.x, point.y)
	for _attempt in 500:
		if Vector2i(GameState.player_x, GameState.player_y) == point: break
		await get_tree().create_timer(0.01).timeout
	if Vector2i(GameState.player_x, GameState.player_y) != point:
		_fail("contender could not reach neighboring corpse tile")
		return
	main.call("_cancel_movement")
	await get_tree().create_timer(1.1).timeout
	if _meat_count(resources) != before:
		_fail("unclaimed corpse changed contender inventory")
		return
	_write("contender.ready", {"uid": str(GameState.player_uid)})
	await _race_claim(int(corpse.uid), before, resources)

func _race_claim(corpse_uid: int, before: int, resources) -> void:
	stage = "simultaneous corpse claim"
	if not await _wait_file("claim.go"):
		_fail("claim barrier unavailable")
		return
	var barrier: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/claim.go"))
	while int(Time.get_unix_time_from_system() * 1000.0) < int(barrier.at):
		await get_tree().create_timer(0.005).timeout
	var sent_ms := int(Time.get_unix_time_from_system() * 1000.0)
	NetworkClient.send_harvest_corpse(corpse_uid)
	await get_tree().create_timer(0.8).timeout
	var after := _meat_count(resources)
	await get_tree().create_timer(0.4).timeout
	NetworkClient.send_harvest_corpse(corpse_uid)
	await get_tree().create_timer(0.8).timeout
	if _meat_count(resources) != after:
		_fail("repeat claim granted meat again")
		return
	_write(role + ".result", {"gain": after - before, "sent_ms": sent_ms})
	var other := "killer" if role == "contender" else "contender"
	if not await _wait_file(other + ".result"):
		_fail("other claimant did not finish")
		return
	var peer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/" + other + ".result"))
	var own_gain := after - before
	# The unchanged chicken table guarantees one meat and rolls a second at1/10.
	if (own_gain > 0) == (int(peer.gain) > 0) or own_gain + int(peer.gain) not in [1, 2] or abs(sent_ms - int(peer.sent_ms)) > 100:
		_fail("claim was not exclusive or simultaneous: own=%d peer=%s" % [own_gain, peer])
		return
	finished = true
	if not await _restore_origin():
		push_error("CORPSE RACE origin restoration failed " + role)
		get_tree().quit(1)
		return
	print("NETWORK CORPSE RACE PASS role=%s own_gain=%d other_gain=%d send_skew_ms=%d origin=%s; one rolled reward, duplicate rejected" % [role, own_gain, int(peer.gain), abs(sent_ms - int(peer.sent_ms)), origin])
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _restore_origin() -> bool:
	if origin_map == 0 or not NetworkClient.is_connected_to_server(): return false
	main.call("_cancel_movement")
	if GameState.player_map_uid == origin_map and Vector2i(GameState.player_x, GameState.player_y) == origin: return true
	var before := own_stands
	NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
	for _attempt in 500:
		if own_stands > before and GameState.player_map_uid == origin_map and Vector2i(GameState.player_x, GameState.player_y) == origin: return true
		await get_tree().create_timer(0.01).timeout
	return false

func _fail(message: String) -> void:
	if finished: return
	finished = true
	await _restore_origin()
	push_error("NETWORK CORPSE HARVEST: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
