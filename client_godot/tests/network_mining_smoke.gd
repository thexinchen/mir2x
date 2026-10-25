extends "res://tests/mir3_movement_visual.gd"

const Protocol = preload("res://scripts/network/protocol.gd")
const Movement = preload("res://scripts/game/mir3_movement.gd")
var finished := false
var old_weapon := 0
var resources: RefCounted
var stage := "login"

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(25.0).timeout.connect(func(): _fail("timeout at " + stage))

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
		renderer = main.get_node("WorldRenderer")
		resources = main.get("_resources")
		_run()
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _run() -> void:
	stage = "ready"
	await get_tree().create_timer(3.0).timeout
	old_weapon = int(GameState.wear.get(3, {}).get("itemID", 0))
	if main.get_node("MapLoadingOverlay").visible or GameState.player_hp <= 0 or old_weapon == 0 or resources.item_can_mine(old_weapon):
		_fail("requires living standard test actor with a non-mining weapon")
		return
	start = _position()
	var target := start
	var occupied: Dictionary = main.call("_ground_occupied")
	for offset in Movement.DIRECTIONS:
		var candidate: Vector2i = start + offset * 3
		if Movement.can_step(start, start + offset, renderer.can_walk, occupied) and renderer.focus_uid_at_screen(_point(candidate), true) == 0:
			target = candidate
			break
	if target == start:
		_fail("no empty target with walkable front")
		return
	var front: Vector2i = start + (target - start) / 3
	var before := _ore_count()
	stage = "non-mining weapon rejection"
	_raw_mine(front)
	await get_tree().create_timer(0.4).timeout
	if _ore_count() != before:
		_fail("server rewarded mining without a pickaxe")
		return
	stage = "equip pickaxe"
	var pickaxe: Dictionary = _inventory_item(824)
	if pickaxe.is_empty():
		NetworkClient.send_make_item(824)
		await get_tree().create_timer(0.4).timeout
		pickaxe = _inventory_item(824)
	if pickaxe.is_empty():
		_fail("pickaxe fixture unavailable")
		return
	NetworkClient.send_request_equip_wear(824, int(pickaxe.seqID), 3)
	await get_tree().create_timer(0.4).timeout
	if int(GameState.wear.get(3, {}).get("itemID", 0)) != 824:
		_fail("pickaxe equip rejected")
		return
	stage = "invalid range rejection"
	_raw_mine(start + Vector2i.RIGHT * 5)
	_raw_mine(start)
	await get_tree().create_timer(0.4).timeout
	if _ore_count() != before:
		_fail("server rewarded out-of-range or same-cell mining")
		return
	stage = "actual Shift mining input"
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	Input.parse_input_event(key)
	_press(MOUSE_BUTTON_LEFT, _point(target), true)
	await get_tree().create_timer(0.08).timeout
	var local_mine := GameState.player_action_type == 14
	var mine_target: Vector2i = main.get("_mine_target")
	_release(MOUSE_BUTTON_LEFT, _point(target))
	key = InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().create_timer(1.2).timeout
	main.call("_cancel_movement")
	if not local_mine or mine_target != front or _position() != start or _ore_count() != before + 1:
		_fail("stationary strike mismatch: ore delta=%d position=%s local_mine=%s target=%s expected=%s" % [_ore_count() - before, _position(), local_mine, mine_target, front])
		return
	stage = "restore equipment"
	if not await _restore_weapon():
		_fail("original weapon restoration failed")
		return
	print("NETWORK MINING PASS: no-pickaxe/range rejection, actual Shift input, stationary server reward +1, no open-ground repeat, original weapon restored")
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _raw_mine(target: Vector2i) -> void:
	NetworkClient.send_action(Protocol.encode_cm_action(GameState.player_uid, GameState.player_map_uid, {"type": 14, "speed": 100, "x": target.x, "y": target.y}))

func _ore_count() -> int:
	var count := 0
	for item in GameState.inventory:
		if resources.item_name(int(item.get("itemID", 0))) == "黑铁": count += int(item.get("count", 0))
	return count

func _inventory_item(item_id: int) -> Dictionary:
	for item in GameState.inventory:
		if int(item.get("itemID", 0)) == item_id: return item
	return {}

func _restore_weapon() -> bool:
	if old_weapon == 0 or int(GameState.wear.get(3, {}).get("itemID", 0)) == old_weapon: return true
	var item := _inventory_item(old_weapon)
	if item.is_empty(): return false
	NetworkClient.send_request_equip_wear(old_weapon, int(item.seqID), 3)
	for _i in range(40):
		await get_tree().create_timer(0.05).timeout
		if int(GameState.wear.get(3, {}).get("itemID", 0)) == old_weapon: return true
	return false

func _fail(message: String) -> void:
	if finished: return
	finished = true
	if main != null:
		main.call("_cancel_movement")
		if not await _restore_weapon(): push_error("MINING FIXTURE: original weapon could not be restored")
	push_error("NETWORK MINING: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
