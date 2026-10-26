extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const SYS_ENTER := "_RSVD_NAME_ENTER_90360178872"
var main: Control
var finished := false
var stage := "login"
var sent_attacks := 0
var server_attacks := 0
var origin_map := 0
var origin := Vector2i.ZERO
var own_stands := 0
var online_retries := 0
var faded: Dictionary = {}

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(60.0).timeout.connect(func(): _fail("timeout at " + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	if head == NetworkClient.SM_DEADFADEOUT:
		faded[int(Protocol.decode_sm_dead_fade_out(payload).uid)] = true
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
	elif head == NetworkClient.SM_ONLINEERROR and payload.size() == 1 and payload[0] == 3 and online_retries < 8:
		online_retries += 1
		await get_tree().create_timer(0.25).timeout
		NetworkClient.enter_game()
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
	var point := Vector2i(int(corpse.x), int(corpse.y))
	stage = "death drop and corpse traversal"
	await get_tree().create_timer(1.5).timeout
	if _ground_meat_count(resources) <= ground_meat_before:
		_fail("death did not drop meat directly")
		return
	for _attempt in 50:
		if faded.has(chicken): break
		await get_tree().create_timer(0.1).timeout
	if not faded.has(chicken):
		_fail("corpse did not clear within normal death lifecycle")
		return
	print("BEFORE move target=", point, " hero=", Vector2i(GameState.player_x,GameState.player_y), " occupied=", main.call("_ground_occupied").has(point))
	main.call("_start_move_to", point)
	print("PATH=",main.get("_move_path"), " HP=",GameState.player_hp)
	for _i in range(40):
		await get_tree().create_timer(0.2).timeout
		if _server_at(point): break
	main.call("_cancel_movement")
	if not _server_at(point):
		_fail("server did not confirm movement onto corpse tile; hero=%s target=%s path=%s timers=%s/%s" % [Vector2i(GameState.player_x,GameState.player_y),point,main.get("_move_path"),main.get("_move_step_timer"),main.get("_player_action_timer")])
		return
	finished = true
	if not await _restore_origin():
		get_tree().quit(1)
		return
	print("DEATH DROP MOVEMENT PASS: meat on ground; server confirmed corpse tile ", point)
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
			# Ground snapshots contain item IDs, one entry per visible item.
			if resources.item_type(int(item)) == "肉": count += 1
	return count

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
	push_error("DEATH DROP MOVEMENT: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)

func _server_at(point: Vector2i) -> bool:
	var output: Array = []
	var probe = preload("res://tests/network_inventory_refresh_smoke.gd").LOCATION_PROBE
	if OS.execute("python3", PackedStringArray(["-c", probe, OS.get_environment("MIR3_TEST_SERVER_DB"), GameState.player_name]), output, true) != 0: return false
	var observed = JSON.parse_string("".join(output))
	return observed is Array and observed.size() == 3 and observed[0] == 24.0 and observed[1] == float(point.x) and observed[2] == float(point.y)
