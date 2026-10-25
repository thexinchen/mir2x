extends "res://tests/network_corpse_harvest_smoke.gd"

const Reader = preload("res://scripts/network/cereal_reader.gd")
const Calculator = preload("res://scripts/game/combat_calculator.gd")
const Move = preload("res://scripts/game/mir3_movement.gd")
var target_uid := 0
var naked_hits := 0
var target_hp := -1
var old_weapon := 0
var saved_weapon: Dictionary = {}

func _message(head: int, payload: PackedByteArray) -> void:
	super._message(head, payload)
	if finished or target_uid == 0: return
	if head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		var action: Dictionary = data.get("action", {})
		if stage == "naked attack" and int(data.get("uid", 0)) == target_uid and int(action.get("type", 0)) == 11 and int(action.get("aimUID", 0)) == GameState.player_uid:
			naked_hits += 1
	elif head == NetworkClient.SM_HEALTH:
		var reader := Reader.new(payload)
		var health: Dictionary = reader.read_sd_health()
		if reader.valid and int(health.get("uid", 0)) == target_uid:
			target_hp = int(health.get("hp", -1))

func _run() -> void:
	stage = "ready"
	await get_tree().create_timer(3.0).timeout
	var resources: RefCounted = main.get("_resources")
	old_weapon = int(GameState.wear.get(3, {}).get("itemID", 0))
	if GameState.player_level < 2:
		# Keep the standard test actor at the first deterministic base-DC
		# level. This fixture experience is retained for future reruns.
		NetworkClient.send_request_add_exp(maxi(0, 1300 - GameState.player_exp))
		await get_tree().create_timer(0.4).timeout
	if old_weapon == 0 or GameState.wear.size() != 1 or GameState.player_job != 2 or GameState.player_level < 2:
		_fail("requires standard Taoist id_4 fixture with only weapon equipped and level >=2: job=%d level=%d wear=%s" % [GameState.player_job, GameState.player_level, GameState.wear])
		return
	stage = "summon chicken"
	target_uid = await _summon_chicken()
	if target_uid == 0:
		_fail("could not summon a fresh chicken")
		return
	target_hp = int(GameState.creatures.get(target_uid, {}).get("hp", 10))
	var initial_hp := target_hp
	stage = "disarm"
	NetworkClient.send_request_grab_wear(3)
	await get_tree().create_timer(0.4).timeout
	if not GameState.wear.is_empty() or int(GameState.grabbed_item.get("itemID", 0)) != old_weapon:
		_fail("could not disarm test weapon")
		return
	# The server has already returned this item to inventory. Mirror placing
	# the grabbed item into an inventory cell so normal attack input is free.
	saved_weapon = GameState.grabbed_item.duplicate(true)
	GameState.inventory.append(saved_weapon)
	GameState.grabbed_item = {}
	var combat: Dictionary = Calculator.calculate(GameState, resources)
	if combat.dc != PackedInt32Array([0, 0]):
		_fail("naked Taoist HUD fixture must have zero physical damage")
		return
	stage = "naked attack"
	main.call("_start_chase", target_uid)
	for _i in range(240):
		await get_tree().create_timer(0.05).timeout
		if not await _separate_overlap():
			_fail("could not separate overlapping summon fixture")
			return
		if naked_hits > 0 or target_hp != initial_hp: break
	main.call("_cancel_movement")
	if naked_hits > 0 and target_hp == initial_hp:
		# Probe damage calculation repeatedly while the actor is in range.
		# This is a protocol-level attribute test, not an attack-cadence test.
		var creature: Dictionary = GameState.creatures.get(target_uid, {})
		var action := {"type": 7, "speed": 100, "x": GameState.player_x, "y": GameState.player_y, "direction": main.call("_direction_to", GameState.player_x, GameState.player_y, creature.get("x", 0), creature.get("y", 0)), "aimUID": target_uid, "magicID": resources.magic_id("物理攻击")}
		for _i in range(20):
			NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
		await get_tree().create_timer(0.8).timeout
	var attack_state := "hero=(%d,%d) hp=%d action=%d target=%s" % [GameState.player_x, GameState.player_y, GameState.player_hp, GameState.player_action_type, GameState.creatures.get(target_uid, {})]
	await get_tree().create_timer(0.2).timeout
	var naked_hp := target_hp
	if not await _restore_weapon():
		_fail("original weapon restoration failed")
		return
	if naked_hits < 10 or naked_hp != initial_hp:
		_fail("naked Taoist damage differed from HUD: hits=%d hp=%d->%d level=%d dbid=%d %s" % [naked_hits, initial_hp, naked_hp, GameState.player_level, GameState.player_uid & 0xFFFFFFFF, attack_state])
		return
	stage = "armed positive control"
	main.call("_start_chase", target_uid)
	for _i in range(160):
		await get_tree().create_timer(0.05).timeout
		if not await _separate_overlap():
			_fail("could not separate armed positive-control fixture")
			return
		if target_hp < initial_hp: break
	main.call("_cancel_movement")
	if target_hp >= initial_hp:
		_fail("restored weapon did not produce authoritative damage")
		return
	print("NETWORK COMBAT JOB PASS: Taoist job2/dbid7, zero-DC HUD matches ten authoritative naked hits, restored weapon damages target")
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _separate_overlap() -> bool:
	var creature: Dictionary = GameState.creatures.get(target_uid, {})
	var from := Vector2i(GameState.player_x, GameState.player_y)
	if Vector2i(int(creature.get("x", -1)), int(creature.get("y", -1))) != from: return true
	var renderer: Control = main.get_node("WorldRenderer")
	var occupied: Dictionary = main.call("_ground_occupied")
	for offset in Move.DIRECTIONS:
		var goal: Vector2i = from + offset
		if not Move.can_step(from, goal, renderer.can_walk, occupied): continue
		main.call("_start_move_to", goal)
		for _i in range(60):
			await get_tree().create_timer(0.05).timeout
			if Vector2i(GameState.player_x, GameState.player_y) == goal and main.get("_move_step_timer") <= 0.0:
				main.call("_start_chase", target_uid)
				return true
		return false
	return false

func _summon_chicken() -> int:
	var npc := 0
	for uid in GameState.creatures:
		var creature: Dictionary = GameState.creatures[uid]
		if creature.get("type", 0) == 3 and creature.get("x", 0) == 406 and creature.get("y", 0) == 126:
			npc = int(uid)
	if npc == 0: return 0
	NetworkClient.send_npc_event(npc, "", SYS_ENTER)
	await get_tree().create_timer(0.4).timeout
	var parser := XMLParser.new()
	parser.open_buffer(str(GameState.npc_dialog.get("xmlLayout", "")).to_utf8_buffer())
	var event_id := ""
	var chicken_event := ""
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "event":
			event_id = parser.get_named_attribute_value_safe("id")
		elif parser.get_node_type() == XMLParser.NODE_TEXT and parser.get_node_data() == "鸡，":
			chicken_event = event_id
	if chicken_event.is_empty(): return 0
	var existing := GameState.creatures.keys()
	NetworkClient.send_npc_event(npc, str(GameState.npc_dialog.get("eventPath", "")), chicken_event)
	await get_tree().create_timer(0.6).timeout
	var resources: RefCounted = main.get("_resources")
	for uid in GameState.creatures:
		if uid not in existing and resources.monster_name(int(GameState.creatures[uid].get("monster_id", 0))) == "鸡": return int(uid)
	return 0

func _restore_weapon() -> bool:
	if old_weapon == 0 or int(GameState.wear.get(3, {}).get("itemID", 0)) == old_weapon: return true
	if saved_weapon.is_empty() and int(GameState.grabbed_item.get("itemID", 0)) == old_weapon:
		saved_weapon = GameState.grabbed_item.duplicate(true)
		GameState.inventory.append(saved_weapon)
		GameState.grabbed_item = {}
	if saved_weapon.is_empty(): return false
	NetworkClient.send_request_equip_wear(old_weapon, int(saved_weapon.seqID), 3)
	for _i in range(40):
		await get_tree().create_timer(0.05).timeout
		if int(GameState.wear.get(3, {}).get("itemID", 0)) == old_weapon: return true
	return false

func _fail(message: String) -> void:
	if finished: return
	finished = true
	if main != null:
		main.call("_cancel_movement")
		if not await _restore_weapon(): push_error("COMBAT FIXTURE: could not restore original weapon")
	push_error("NETWORK COMBAT JOB: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
