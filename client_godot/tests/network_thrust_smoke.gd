extends "res://tests/network_combat_job_smoke.gd"

var original_map := 0
var original_position := Vector2i.ZERO
var thrust_hits := 0
var fixture_map := 0
var attack_origin := Vector2i.ZERO
var attack_facing := Vector2i.ZERO
var testing_thrust := false

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4" if OS.has_environment("MIR2X_THRUST_UNLEARNED") else "good", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(60.0).timeout.connect(func(): _fail("timeout at " + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	super._message(head, payload)
	if head == NetworkClient.SM_ACTION and target_uid != 0:
		var data := Protocol.decode_sm_action(payload)
		var action: Dictionary = data.get("action", {})
		if int(data.get("uid", 0)) == target_uid and int(action.get("type", 0)) == 11 and int(action.get("aimUID", 0)) == GameState.player_uid:
			var hit_position := Vector2i(action.get("x", -1), action.get("y", -1))
			if testing_thrust and hit_position == attack_origin + attack_facing * 2:
				thrust_hits += 1

func _run() -> void:
	stage = "prepare warrior"
	await get_tree().create_timer(3.0).timeout
	original_map = GameState.player_map_uid
	original_position = Vector2i(GameState.player_x, GameState.player_y)
	var unlearned := OS.has_environment("MIR2X_THRUST_UNLEARNED")
	if not unlearned and (GameState.player_job & 1) == 0:
		_fail("fixture requires warrior job")
		return
	if not unlearned and GameState.player_level < 19:
		NetworkClient.send_request_add_exp(maxi(0, 618400 - GameState.player_exp))
		await get_tree().create_timer(0.5).timeout
	if not unlearned and GameState.player_level < 19:
		_fail("could not prepare level19 warrior")
		return
	var resources: RefCounted = main.get("_resources")
	var books: Array = [] if unlearned else ["基本剑术", "攻杀剑术", "刺杀剑术"]
	for name in books:
		var magic: int = resources.magic_id(name)
		if main.call("_has_learned_magic", magic): continue
		var book := 0
		for id in resources.item_names:
			if resources.item_names[id] == name: book = int(id)
		if book == 0:
			_fail("missing book metadata: " + name)
			return
		NetworkClient.send_make_item(book)
		await get_tree().create_timer(0.3).timeout
		var item: Dictionary = {}
		for value in GameState.inventory:
			if int(value.get("itemID", 0)) == book: item = value
		if item.is_empty():
			_fail("book fixture unavailable: " + name)
			return
		NetworkClient.send_consume_item(book, int(item.seqID), 1)
		await get_tree().create_timer(0.4).timeout
		if not main.call("_has_learned_magic", magic):
			_fail("server did not confirm learning: " + name)
			return
	NetworkClient.send_query_map_base_uid(24, func(head, payload):
		if head == NetworkClient.SM_UID and payload.size() >= 8: fixture_map = payload.decode_u64(0))
	await get_tree().create_timer(0.3).timeout
	if fixture_map == 0 or not await _relocate(fixture_map, Vector2i(407, 127)):
		_fail("could not relocate to summoner fixture")
		return
	stage = "summon"
	target_uid = await _summon_chicken()
	if target_uid == 0:
		_fail("could not summon target")
		return
	target_hp = int(GameState.creatures.get(target_uid, {}).get("hp", 10))
	var initial_hp := target_hp
	if not await _align_target():
		_fail("could not prepare two-cell attack line")
		return
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var target := _target_grid()
	main.call("_send_attack_action", 0, target)
	await get_tree().create_timer(0.8).timeout
	if target_hp != initial_hp:
		_fail("normal directional attack unexpectedly damaged second-cell target")
		return
	stage = "bind thrust"
	var thrust: int = resources.magic_id("刺杀剑术")
	if unlearned:
		if main.call("_has_learned_magic", thrust):
			_fail("negative-control fixture unexpectedly learned thrust")
			return
		stage = "reject unlearned raw thrust"
		for _i in range(4):
			if not await _align_target():
				_fail("negative-control line moved")
				return
			attack_origin = Vector2i(GameState.player_x, GameState.player_y)
			target = _target_grid()
			attack_facing = Vector2i(signi(target.x - attack_origin.x), signi(target.y - attack_origin.y))
			testing_thrust = true
			var action := {"type": 7, "speed": 100, "direction": main.call("_direction_to", attack_origin.x, attack_origin.y, target.x, target.y), "x": attack_origin.x, "y": attack_origin.y, "aimUID": 0, "magicID": thrust}
			NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, action))
			await get_tree().create_timer(0.8).timeout
		if thrust_hits != 0 or target_hp != initial_hp:
			_fail("server accepted unlearned thrust: hits=%d hp=%d->%d" % [thrust_hits, initial_hp, target_hp])
			return
		if not await _restore_position():
			_fail("negative-control position restoration failed")
			return
		print("NETWORK THRUST UNLEARNED PASS: raw two-cell thrust rejected, no authoritative hit or HP loss")
		finished = true
		NetworkClient.disconnect_from_server()
		get_tree().quit()
		return
	var panel: Control = main.get_node("SkillPanel")
	panel.show()
	panel.call("_select_tab", resources.skill_layout(thrust)[1])
	panel.call("_show_magic", thrust)
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	panel.call("_unhandled_key_input", key)
	panel.hide()
	main.call("_try_magic_key", key)
	if not bool(main.get("_swing_magic").get(thrust, false)):
		_fail("F12 did not enable learned thrust")
		return
	stage = "second-cell thrust"
	for _i in range(10):
		if target_hp < initial_hp and thrust_hits > 0: break
		if not await _align_target(): break
		origin = Vector2i(GameState.player_x, GameState.player_y)
		target = _target_grid()
		attack_origin = origin
		attack_facing = Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
		main.call("_send_attack_action", 0, target)
		testing_thrust = GameState.player_action_magic_id == thrust
		print("THRUST ATTEMPT magic=%d origin=%s target=%s" % [GameState.player_action_magic_id, origin, target])
		# The server may schedule an attack bonus after the negative control.
		# Respect that higher-priority attack and continue on the next cycle.
		await get_tree().create_timer(0.8).timeout
	if target_hp >= initial_hp or thrust_hits == 0:
		_fail("no authoritative second-cell hit/damage: hits=%d hp=%d->%d" % [thrust_hits, initial_hp, target_hp])
		return
	print("NETWORK THRUST PASS: learned warrior, normal attack leaves second-cell target intact, F12-enabled thrust causes authoritative hit+HP %d->%d, hits=%d origin=%s target=%s" % [initial_hp, target_hp, thrust_hits, origin, target])
	if not await _restore_position():
		_fail("could not restore original map position")
		return
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _target_grid() -> Vector2i:
	var actor: Dictionary = GameState.creatures.get(target_uid, {})
	return Vector2i(actor.get("x", -1), actor.get("y", -1))

func _align_target() -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	var directions: Array = [1, 3, 5, 7] if OS.has_environment("MIR2X_THRUST_DIAGONAL") else range(8)
	# Chickens move normally. Rebuild the fixture if it moved while the
	# relocation acknowledgement was in flight; never test a stale line.
	for _attempt in range(6):
		var target := _target_grid()
		var occupied: Dictionary = main.call("_ground_occupied")
		occupied.erase(Vector2i(GameState.player_x, GameState.player_y))
		for index in directions:
			var offset: Vector2i = Move.DIRECTIONS[int(index)]
			var from: Vector2i = target - offset * 2
			var front: Vector2i = target - offset
			if occupied.has(from) or occupied.has(front) or not renderer.can_walk(from.x, from.y) or not renderer.can_walk(front.x, front.y): continue
			if not await _relocate(fixture_map, from): return false
			if _target_grid() == target: return true
			break
	return false

func _relocate(map_uid: int, position: Vector2i) -> bool:
	main.call("_cancel_movement")
	NetworkClient.send_request_space_move(map_uid, position.x, position.y)
	for _i in range(60):
		await get_tree().create_timer(0.05).timeout
		if GameState.player_map_uid == map_uid and Vector2i(GameState.player_x, GameState.player_y) == position and not main.get_node("MapLoadingOverlay").visible:
			await get_tree().create_timer(0.15).timeout
			return true
	return false

func _restore_position() -> bool:
	return await _relocate(original_map, original_position) if original_map != 0 else true

func _fail(message: String) -> void:
	if finished: return
	finished = true
	if main != null and not await _restore_position(): push_error("THRUST FIXTURE: original map position restoration failed")
	push_error("NETWORK THRUST: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
