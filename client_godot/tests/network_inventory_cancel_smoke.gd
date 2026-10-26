extends "res://tests/network_item_shortcuts_smoke.gd"

const CONFIG := "user://network_inventory_cancel_smoke.cfg"
var fixture_slot := -1
var cleaning := false

func _ready() -> void:
	OS.set_environment("MIR3_PROTECTION_CONFIG", CONFIG)
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	super._ready()

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "inventory cancel world"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live cancel actor"): return
	var potion := _item()
	if potion.is_empty():
		_fail("fixture requires an owned potion")
		return
	var target_key := ""
	var large_key := ""
	var panel: Control = _main.get_node("InventoryPanel")
	for key in panel.get("_bins"):
		var bin: Dictionary = panel.get("_bins")[key]
		if int(bin.item.itemID) != ITEM_ID and target_key.is_empty(): target_key = key
		if int(bin.w) * int(bin.h) > 1: large_key = key
	if target_key.is_empty() or large_key.is_empty():
		_fail("fixture requires another item and a multi-cell inventory item")
		return
	var before := _inventory_signature()
	var totals := _inventory_totals()
	var belt_before: Array = GameState.belt.duplicate(true)
	var wear_before: Dictionary = GameState.wear.duplicate(true)
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var origin_map: int = GameState.player_map_uid
	var request_before: int = NetworkClient.get("_next_response_id")
	panel.show()
	panel.call("_grab_item", "%d:%d" % [ITEM_ID, potion.seqID])
	var target: Dictionary = panel.get("_bins")[target_key]
	await _right_at(panel.get_node("ItemGrid").global_position + Vector2(target.x * 38 + 8, (int(target.y) - int(panel.get("_scroll_row"))) * 38 + 8))
	if not _cancel_unchanged(before, request_before): return
	panel.call("_grab_item", large_key)
	panel.hide()
	await _right_at(Vector2(200, 200))
	await get_tree().create_timer(0.3).timeout
	if not _cancel_unchanged(before, request_before): return
	if Vector2i(GameState.player_x, GameState.player_y) != origin or not _main.get("_move_path").is_empty() or _main.get("_ground_input").button != 0:
		_fail("cancel press reached ground movement")
		return
	# The current server explicitly puts belt/wear grabs into inventory. Check
	# that canceling such a cursor returns it to inventory without re-equipping.
	for slot in GameState.belt.size():
		if int(GameState.belt[slot].get("itemID", 0)) == 0:
			fixture_slot = slot
			break
	if fixture_slot < 0:
		_fail("fixture requires an initially empty belt slot")
		return
	potion = _item()
	NetworkClient.send_request_equip_belt(ITEM_ID, int(potion.seqID), fixture_slot)
	if not await _wait(func(): return int(GameState.belt[fixture_slot].get("itemID", 0)) == ITEM_ID, "prepare belt grab"): return
	NetworkClient.send_request_grab_belt(fixture_slot)
	if not await _wait(func(): return int(GameState.grabbed_item.get("itemID", 0)) == ITEM_ID and int(GameState.belt[fixture_slot].get("itemID", 0)) == 0, "actual belt grab"): return
	var expected := _inventory_signature()
	expected["%d:%d" % [ITEM_ID, GameState.grabbed_item.seqID]] = int(GameState.grabbed_item.count)
	var quick_bar: Control = _main.get_node("QuickBar")
	quick_bar.show()
	await get_tree().process_frame
	var cancel_id_before: int = NetworkClient.get("_next_response_id")
	await _right_at(quick_bar.get_node("Slots/Slot%d" % fixture_slot).get_global_rect().get_center())
	if not _cancel_unchanged(expected, cancel_id_before): return
	if _inventory_totals() != totals or _belt_signature() != _belt_signature(belt_before) or GameState.wear != wear_before:
		_fail("belt cursor cancel changed quantities or equipment")
		return
	if OS.has_environment("MIR3_INVENTORY_CANCEL_SCREENSHOT"):
		panel.show()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_INVENTORY_CANCEL_SCREENSHOT"))
	_expected_uid = GameState.player_uid
	_reconnecting = true
	NetworkClient.disconnect_from_server()
	await get_tree().process_frame
	NetworkClient.connect_to_server()
	if not await _wait(func(): return _reconnected and _inventory_received and _belt_received and GameState.inventory_initialized and not _main.get_node("MapLoadingOverlay").visible, "cancel authoritative re-login"): return
	if _inventory_signature() != expected or _inventory_totals() != totals or _belt_signature() != _belt_signature(belt_before) or GameState.wear != wear_before or GameState.player_map_uid != origin_map or Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("re-login did not confirm canceled inventory/belt/location")
		return
	print("NETWORK INVENTORY CANCEL PASS: generated GUI right clicks over another item/world/belt, real multi-cell and belt-origin cursors, no fallthrough use or movement, re-login confirms inventory totals/equipment/location")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _inventory_signature() -> Dictionary:
	var result := {}
	for item: Dictionary in GameState.inventory: result["%d:%d" % [item.itemID, item.seqID]] = int(item.count)
	return result

func _inventory_totals() -> Dictionary:
	var result := {}
	for item: Dictionary in GameState.inventory: result[int(item.itemID)] = int(result.get(int(item.itemID), 0)) + int(item.count)
	return result

func _belt_signature(items: Array = GameState.belt) -> Array:
	var result := []
	for item: Dictionary in items: result.append(item if int(item.get("itemID", 0)) > 0 else {})
	return result

func _cancel_unchanged(expected: Dictionary, next_id: int) -> bool:
	if not GameState.grabbed_item.is_empty() or _inventory_signature() != expected or int(NetworkClient.get("_next_response_id")) != next_id:
		_fail("right cancel lost inventory or reached item use")
		return false
	return true

func _right_at(point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = point
	click.pressed = true
	Input.parse_input_event(click)
	await get_tree().process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await get_tree().process_frame
	await get_tree().process_frame

func _fail(message: String) -> void:
	if _finished or cleaning: return
	cleaning = true
	if fixture_slot >= 0 and NetworkClient.is_connected_to_server() and int(GameState.belt[fixture_slot].get("itemID", 0)) > 0:
		NetworkClient.send_request_grab_belt(fixture_slot)
		for _attempt in 200:
			if not GameState.grabbed_item.is_empty(): break
			await get_tree().create_timer(0.01).timeout
	if is_instance_valid(_main): _main.get_node("InventoryPanel").call("cancel_grabbed_item")
	super._fail("inventory cancel: " + message)
