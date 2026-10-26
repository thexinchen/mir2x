extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const ITEM_ID := 6
var _main: Control
var _finished := false
var _stage := "login"
var _wire_receipts: Dictionary = {}
var _inventory_received := false
var _belt_received := false


func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _text):
		if connected: NetworkClient.login("id_4", "123456"))
	NetworkClient.response_received.connect(func(id, head, _payload): _wire_receipts[id] = head)
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(35.0).timeout.connect(func(): _fail("timeout at " + _stage))


func _message(head: int, payload: PackedByteArray) -> void:
	if _finished: return
	match head:
		NetworkClient.SM_LOGINOK:
			NetworkClient.enter_game()
		NetworkClient.SM_ONLINEOK:
			var online := Protocol.decode_sm_online_ok(payload)
			var action: Dictionary = online.action
			GameState.set_player_online({"uid": online.uid, "name": online.name, "gender": online.gender, "job": online.job, "map_uid": online.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
			_main = load("res://scenes/game/main.tscn").instantiate()
			add_child(_main)
			_run()
		NetworkClient.SM_INVENTORY:
			_inventory_received = true
		NetworkClient.SM_BELT:
			_belt_received = true
		NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR:
			_fail("login rejected")


func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "initial inventory and map"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "restore initial live test actor"): return
	# This harmless request also serves as an old-server negative: a callback
	# timeout must never count as a received SM_ERROR.
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_belt_item(65535, cb), NetworkClient.SM_ERROR, "invalid belt slot"): return
	var empty_slot := -1
	for slot in GameState.belt.size():
		if _belt_item(slot).is_empty():
			empty_slot = slot
			break
	if empty_slot < 0:
		_fail("fixture requires one empty belt slot")
		return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_belt_item(empty_slot, cb), NetworkClient.SM_ERROR, "empty belt slot"): return
	var initial := _count()
	NetworkClient.send_make_item(ITEM_ID, 3)
	if not await _wait(func(): return _count() == initial + 3, "seed three potions"): return
	var item := _item()
	var seq := int(item.seqID)
	var before := _count()
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(0, seq, 1, cb), NetworkClient.SM_ERROR, "unknown item"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(ITEM_ID, 0, 1, cb), NetworkClient.SM_ERROR, "missing instance"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(ITEM_ID, 2147483647, 1, cb), NetworkClient.SM_ERROR, "unowned instance"): return
	for count in [0, 2]:
		if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(ITEM_ID, seq, count, cb), NetworkClient.SM_ERROR, "invalid count %d" % count): return
	if _count() != before:
		_fail("rejected inventory use changed quantity")
		return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(ITEM_ID, seq, 1, cb), NetworkClient.SM_OK, "inventory success"): return
	if not await _wait(func(): return _count() == before - 1, "one inventory item consumed"): return
	item = _item()
	var belt_before := int(item.count)
	NetworkClient.send_request_equip_belt(ITEM_ID, int(item.seqID), empty_slot)
	if not await _wait(func(): return int(_belt_item(empty_slot).get("count", 0)) == belt_before, "equip potion"): return
	var quick_bar: Control = _main.get_node("QuickBar")
	quick_bar.show()
	var dead_key := OS.has_environment("MIR3_ITEM_USE_DEAD_KEY")
	if dead_key:
		_submit_command("@die")
		if not await _wait(func(): return GameState.player_hp == 0, "actual death before number key"): return
	var belt_response := int(NetworkClient.get("_next_response_id"))
	# Exercise the production GUI entry without supplying a test-only callback.
	if dead_key:
		var key := InputEventKey.new()
		key.keycode = KEY_1 + empty_slot
		key.pressed = true
		_main.call("_unhandled_input", key)
	elif int(quick_bar.call("activate_slot", empty_slot, MOUSE_BUTTON_RIGHT)) != 3:
		_fail("real quick-bar use rejected the potion")
		return
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	if int(quick_bar.call("activate_slot", empty_slot, MOUSE_BUTTON_RIGHT)) != 0 or AudioService.last_seff_id != AudioService.INVALID_SEFF_ID:
		_fail("repeated real quick-bar use accepted or replayed sound while pending")
		return
	if not await _wait(func(): return _wire_receipts.has(belt_response), "real quick-bar correlated result"): return
	if int(_wire_receipts[belt_response]) != NetworkClient.SM_OK:
		_fail("real quick-bar use failed")
		return
	if not await _wait(func(): return int(_belt_item(empty_slot).get("count", 0)) == belt_before - 1, "one belt item consumed"): return
	if dead_key:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "restore test actor after dead number key"): return
	NetworkClient.send_request_grab_belt(empty_slot)
	if not await _wait(func(): return int(GameState.grabbed_item.get("itemID", 0)) == ITEM_ID and _belt_item(empty_slot).is_empty(), "return belt potion"): return
	var inventory: Control = _main.get_node("InventoryPanel")
	inventory.show()
	inventory.call("_place_grabbed", Vector2i(5, 5))
	if not await _wait(func(): return GameState.grabbed_item.is_empty() and _count() == before - 2, "restore unused potion inventory"): return
	# Legacy respID=0 use must still update inventory without a result packet.
	var wire_before := _wire_receipts.size()
	item = _item()
	var legacy := PackedByteArray()
	legacy.resize(10)
	legacy.encode_u32(0, ITEM_ID)
	legacy.encode_u32(4, int(item.seqID))
	legacy.encode_u16(8, 1)
	NetworkClient.call("_send_fixed_message", NetworkClient.CM_CONSUMEITEM, legacy)
	if not await _wait(func(): return _count() == before - 3, "legacy inventory use"): return
	if _wire_receipts.size() != wire_before:
		_fail("legacy use unexpectedly generated a correlated reply")
		return
	print("NETWORK ITEM USE RECEIPT PASS: dead_key=%s; seven explicit failures, inventory/belt success, shared pending suppression, one unit per use, unchanged rejected quantities, legacy no-reply use, restored belt" % dead_key)
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()


func _expect_reply(sender: Callable, expected: int, label: String) -> bool:
	_stage = label
	var response_id := int(NetworkClient.get("_next_response_id"))
	var result := {"done": false, "head": -1}
	var error: int = sender.call(func(head, _payload):
		result.done = true
		result.head = head)
	if error != OK:
		_fail("send failed at " + label)
		return false
	if NetworkClient.send_consume_item(ITEM_ID, 0, 1) != ERR_BUSY or NetworkClient.send_consume_belt_item(0) != ERR_BUSY:
		_fail("shared pending state allowed another inventory/belt use at " + label)
		return false
	if not await _wait(func(): return result.done, label): return false
	if not _wire_receipts.has(response_id):
		_fail("no actual wire reply at %s; callback timeout is not a server failure result" % label)
		return false
	if int(result.head) != expected or int(_wire_receipts[response_id]) != expected:
		_fail("unexpected correlated result at %s: %s" % [label, result])
		return false
	return true


func _wait(predicate: Callable, label: String) -> bool:
	_stage = label
	var deadline := Time.get_ticks_msec() + 6000
	while not _finished and not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			_fail("wait expired at " + label)
			return false
		await get_tree().process_frame
	return not _finished


func _item() -> Dictionary:
	for value in GameState.inventory:
		if int(value.get("itemID", 0)) == ITEM_ID: return value
	return {}


func _submit_command(text: String) -> void:
	var command: LineEdit = _main.get_node("ControlPanel").get_node("%Command")
	command.text = text
	command.text_submitted.emit(text)


func _count() -> int:
	var count := 0
	for value in GameState.inventory:
		if int(value.get("itemID", 0)) == ITEM_ID: count += int(value.get("count", 0))
	return count


func _belt_item(slot: int) -> Dictionary:
	var value = GameState.belt[slot]
	return value if value is Dictionary and int(value.get("itemID", 0)) > 0 else {}


func _fail(message: String) -> void:
	if _finished: return
	_finished = true
	push_error("NETWORK_ITEM_USE_RECEIPT_SMOKE " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
