extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const SYS_ENTER := "_RSVD_NAME_ENTER_90360178872"
var main: Control
var finished := false
var stage := "login"
var sent_attacks := 0
var server_attacks := 0

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(60.0).timeout.connect(func(): _fail("timeout at " + stage))

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
	stage = "claim meat"
	var point := Vector2i(int(corpse.x), int(corpse.y))
	main.call("_start_move_to", point)
	for _i in range(50):
		await get_tree().create_timer(0.2).timeout
		if Vector2i(GameState.player_x, GameState.player_y) == point and main.get("_move_step_timer") <= 0.0: break
	main.call("_cancel_movement")
	await get_tree().create_timer(1.1).timeout
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
	print("NETWORK CORPSE HARVEST PASS: normal kill, live rejection, retained corpse, meat gain=%d, duplicate rejection" % (after - before))
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _meat_count(resources) -> int:
	var count := 0
	for item in GameState.inventory:
		if resources.item_name(int(item.get("itemID", 0))) == "鸡肉": count += int(item.get("count", 0))
	return count

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("NETWORK CORPSE HARVEST: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
