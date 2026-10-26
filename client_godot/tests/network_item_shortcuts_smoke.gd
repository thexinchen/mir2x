extends "res://tests/network_item_use_receipt_smoke.gd"

var _reconnecting := false
var _reconnected := false
var _same_uid_reset := false
var _expected_uid := 0


func _message(head: int, payload: PackedByteArray) -> void:
	if _reconnecting and head == NetworkClient.SM_ONLINEOK:
		var online := Protocol.decode_sm_online_ok(payload)
		if int(online.uid) != _expected_uid:
			_fail("reconnected to another character")
			return
		_inventory_received = false
		_belt_received = false
		var action: Dictionary = online.action
		GameState.set_player_online({"uid": online.uid, "name": online.name, "gender": online.gender, "job": online.job, "map_uid": online.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
		_same_uid_reset = _all_shortcuts_clear() and GameState.grabbed_shortcut.is_empty()
		_reconnected = true
		return
	super._message(head, payload)


func _all_shortcuts_clear() -> bool:
	for binding in GameState.item_shortcuts.bindings:
		if not binding.is_empty(): return false
	return true


func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "initial shortcut map/inventory"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "initial live shortcut actor"): return
	var initial := _count()
	NetworkClient.send_make_item(ITEM_ID, 12)
	if not await _wait(func(): return _count() == initial + 12, "seed twelve potions"): return
	var inventory: Control = _main.get_node("InventoryPanel")
	var bar: Control = _main.get("item_shortcut_bar")
	var belt_before: Array = GameState.belt.duplicate(true)
	var next_id := int(NetworkClient.get("_next_response_id"))
	inventory.show()
	for slot in 10:
		var item := _item()
		inventory.call("_grab_item", "%d:%d" % [ITEM_ID, item.seqID])
		if int(bar.call("activate_slot", slot, MOUSE_BUTTON_LEFT)) != 1 or _count() != initial + 12 or not GameState.grabbed_item.is_empty():
			_fail("binding changed actual inventory ownership at slot%d" % slot)
			return
	if GameState.belt != belt_before or int(NetworkClient.get("_next_response_id")) != next_id:
		_fail("binding ten references changed belt or sent a request")
		return
	inventory.hide()
	_main.get_node("QuickBar").hide()
	if OS.has_environment("MIR3_ITEM_SHORTCUTS_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_ITEM_SHORTCUTS_SCREENSHOT"))
		if error != OK:
			_fail("shortcut screenshot failed")
			return
	var dead_key := OS.has_environment("MIR3_SHORTCUTS_DEAD_KEY")
	for slot in 10:
		if dead_key and slot == 9:
			_submit_command("@die")
			if not await _wait(func(): return GameState.player_hp == 0, "death before zero key"): return
		var response_id := int(NetworkClient.get("_next_response_id"))
		var key := InputEventKey.new()
		key.keycode = KEY_1 + slot if slot < 9 else KEY_0
		key.pressed = true
		_main.call("_unhandled_input", key)
		AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
		_main.call("_unhandled_input", key)
		if int(NetworkClient.get("_next_response_id")) != response_id + 1 or AudioService.last_seff_id != AudioService.INVALID_SEFF_ID:
			_fail("repeated digit escaped pending gate or replayed sound")
			return
		if not await _wait(func(): return _wire_receipts.has(response_id), "actual digit%d reply" % slot): return
		if int(_wire_receipts[response_id]) != NetworkClient.SM_OK:
			_fail("inventory digit%d was rejected" % slot)
			return
		if not await _wait(func(): return _count() == initial + 11 - slot, "one inventory potion per digit"): return
		for other in 10:
			if int(GameState.item_shortcuts.resolve(other, GameState.inventory).get("count", -1)) != _count():
				_fail("shared shortcut references missed authoritative quantity update")
				return
	if dead_key:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "restore shortcut actor"): return
	for extra in 2:
		var id := int(NetworkClient.get("_next_response_id"))
		bar.call("activate_slot", 9, MOUSE_BUTTON_RIGHT)
		if not await _wait(func(): return _wire_receipts.has(id), "remaining fixture potion"): return
		if int(_wire_receipts[id]) != NetworkClient.SM_OK:
			_fail("remaining potion use rejected")
			return
	if not await _wait(func(): return _count() == initial, "restore initial inventory quantity"): return
	if GameState.belt != belt_before:
		_fail("inventory shortcuts altered belt storage")
		return
	if OS.has_environment("MIR3_SHORTCUTS_RECONNECT"):
		_expected_uid = GameState.player_uid
		_reconnecting = true
		NetworkClient.disconnect_from_server()
		await get_tree().process_frame
		NetworkClient.connect_to_server()
		if not await _wait(func(): return _reconnected and _inventory_received and _belt_received and GameState.inventory_initialized and not _main.get_node("MapLoadingOverlay").visible, "same-character re-login"): return
		if not _same_uid_reset or not _all_shortcuts_clear():
			_fail("same-character new session inherited old shortcut references")
			return
		await get_tree().process_frame
		for slot in 10:
			if not bar.get_node("Slot%d" % slot).tooltip_text.is_empty() or bar.get_node("Slot%d" % slot).get_child_count() != 1:
				_fail("old shortcut icon survived new-session inventory refresh")
				return
		var before_key := int(NetworkClient.get("_next_response_id"))
		var empty_key := InputEventKey.new()
		empty_key.keycode = KEY_0
		empty_key.pressed = true
		_main.call("_unhandled_input", empty_key)
		if int(NetworkClient.get("_next_response_id")) != before_key or _count() != initial:
			_fail("cleared shortcut consumed inventory after re-login")
			return
		var current := _item()
		inventory.call("_grab_item", "%d:%d" % [ITEM_ID, current.seqID])
		if int(bar.call("activate_slot", 9, MOUSE_BUTTON_LEFT)) != 1 or _count() != initial:
			_fail("new session could not bind an inventory reference again")
			return
		print("NETWORK SHORTCUT SESSION RESET PASS: same UID new login clears ten references, late inventory cannot restore them, old zero key sends nothing, new binding works")
	print("NETWORK ITEM SHORTCUTS PASS: ten real inventory bindings, digits1-0 each consume one with matching wire receipt, duplicate suppression, all references refresh, belt untouched, fixture quantity restored, dead_zero=%s" % dead_key)
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()
