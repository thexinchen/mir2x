extends "res://tests/network_item_shortcuts_smoke.gd"


func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "drag map and inventory"): return
	var chosen: Array[Dictionary] = []
	for item: Dictionary in GameState.inventory:
		if int(item.get("count", 0)) > 0 and (chosen.is_empty() or item.itemID != chosen[0].itemID): chosen.append(item.duplicate(true))
		if chosen.size() == 2: break
	if chosen.size() != 2:
		_fail("drag fixture requires two owned item kinds")
		return
	var before := _inventory_signature()
	var belt_before: Array = GameState.belt.duplicate(true)
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var origin_map := GameState.player_map_uid
	var inventory: Control = _main.get_node("InventoryPanel")
	var bar: Control = _main.get("item_shortcut_bar")
	for slot in 2:
		inventory.call("_grab_item", "%d:%d" % [chosen[slot].itemID, chosen[slot].seqID])
		if int(bar.call("activate_slot", slot, MOUSE_BUTTON_LEFT)) != 1:
			_fail("could not bind owned drag fixture")
			return
	await get_tree().process_frame
	var request_before := int(NetworkClient.get("_next_response_id"))
	await _click_shortcut(bar, 0)
	if GameState.item_shortcuts.bindings[0].is_empty() or GameState.grabbed_shortcut.get("source_slot", -1) != 0:
		_fail("pickup removed source before transfer")
		return
	await _click_shortcut(bar, 1)
	if int(GameState.item_shortcuts.bindings[0].item.itemID) != int(chosen[1].itemID) or int(GameState.item_shortcuts.bindings[1].item.itemID) != int(chosen[0].itemID) or int(GameState.grabbed_shortcut.get("item", {}).get("itemID", 0)) != int(chosen[1].itemID):
		_fail("occupied drop lost displaced reference or ended cursor")
		return
	var resources: RefCounted = _main.get("_resources")
	var expected: Dictionary = resources.frame("item", resources.item_package_gfx_id(int(chosen[1].itemID)) | 0x01000000)
	var icon: TextureRect = _main.get_node("GrabbedItemIcon")
	if expected.is_empty() or not icon.visible or icon.texture != expected.texture:
		_fail("displaced item was not shown on the actual cursor")
		return
	if OS.has_environment("MIR3_SHORTCUT_DRAG_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_SHORTCUT_DRAG_SCREENSHOT")) != OK:
			_fail("drag screenshot failed")
			return
	await _click_shortcut(bar, 0)
	if not GameState.grabbed_shortcut.is_empty() or GameState.item_shortcuts.bindings[0].is_empty():
		_fail("same-source click deleted the reference")
		return
	await _click_shortcut(bar, 0)
	await _click_shortcut(bar, 9)
	if not GameState.grabbed_shortcut.is_empty() or not GameState.item_shortcuts.bindings[0].is_empty() or int(GameState.item_shortcuts.bindings[9].item.itemID) != int(chosen[1].itemID):
		_fail("empty drop did not commit the reference move")
		return
	await _click_shortcut(bar, 9)
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_LEFT
	cancel.pressed = true
	inventory.call("_on_grid_input", cancel)
	if not GameState.grabbed_shortcut.is_empty() or not GameState.item_shortcuts.bindings[9].is_empty() or GameState.item_shortcuts.bindings[1].is_empty():
		_fail("inventory cancellation cleared the wrong reference")
		return
	inventory.call("_grab_item", "%d:%d" % [chosen[1].itemID, chosen[1].seqID])
	bar.call("activate_slot", 9, MOUSE_BUTTON_LEFT)
	await get_tree().process_frame
	await _click_shortcut(bar, 9)
	inventory.call("_on_item_input", cancel, "%d:%d" % [chosen[0].itemID, chosen[0].seqID])
	await get_tree().process_frame
	if not GameState.grabbed_shortcut.is_empty() or not GameState.grabbed_item.is_empty() or not GameState.item_shortcuts.bindings[9].is_empty():
		_fail("occupied inventory target picked a real item instead of cancelling the shortcut")
		return
	if _inventory_signature() != before or GameState.belt != belt_before or int(NetworkClient.get("_next_response_id")) != request_before:
		_fail("reference drag changed inventory/belt or submitted a request")
		return
	_expected_uid = GameState.player_uid
	_reconnecting = true
	NetworkClient.disconnect_from_server()
	await get_tree().process_frame
	NetworkClient.connect_to_server()
	if not await _wait(func(): return _reconnected and _inventory_received and _belt_received and GameState.inventory_initialized and not _main.get_node("MapLoadingOverlay").visible, "authoritative inventory after drag"): return
	if _inventory_signature() != before or GameState.belt != belt_before or Vector2i(GameState.player_x, GameState.player_y) != origin or GameState.player_map_uid != origin_map:
		_fail("re-login authority changed after reference-only drag")
		return
	print("NETWORK SHORTCUT DRAG PASS: real GUI pickup/swap/displaced cursor/same-source cancel/empty move, inventory cancel, no use request, re-login verifies authoritative inventory and belt unchanged, original position preserved")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()


func _inventory_signature() -> Dictionary:
	var result := {}
	for item: Dictionary in GameState.inventory:
		result["%d:%d" % [item.itemID, item.seqID]] = int(item.count)
	return result


func _click_shortcut(bar: Control, slot: int) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = bar.get_node("Slot%d" % slot).get_global_rect().get_center()
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	press.pressed = false
	Input.parse_input_event(press)
	await get_tree().process_frame
