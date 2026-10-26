extends "res://tests/network_inventory_cancel_smoke.gd"

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "swap inventory/map"): return
	var panel: Control = _main.get_node("InventoryPanel")
	var target_key := ""
	var wide_key := ""
	var blocker_key := ""
	for key in panel.get("_bins"):
		var bin: Dictionary = panel.get("_bins")[key]
		if int(bin.w) > 1: wide_key = key
		elif target_key.is_empty(): target_key = key
		elif blocker_key.is_empty(): blocker_key = key
	if wide_key.is_empty() or target_key.is_empty() or blocker_key.is_empty():
		_fail("requires an owned wide item and two narrow items")
		return
	var before := _inventory_records()
	var belt_before: Array = GameState.belt.duplicate(true)
	var wear_before: Dictionary = GameState.wear.duplicate(true)
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var origin_map: int = GameState.player_map_uid
	var next_id: int = NetworkClient.get("_next_response_id")
	panel.show()
	panel.position = Vector2.ZERO
	for scenario in ["occupied", "right_edge", "clear"]:
		var bins: Dictionary = panel.get("_bins")
		var row := 12
		for key in bins:
			bins[key].x = 0
			bins[key].y = row
			row += int(bins[key].h)
		bins[wide_key].y = 5
		bins[target_key].x = 9 if scenario == "right_edge" else 2
		bins[target_key].y = 0
		bins[blocker_key].x = 3 if scenario == "occupied" else 0
		bins[blocker_key].y = 0
		panel.set("_scroll_value", 0.0)
		GameState.state_changed.emit()
		await get_tree().process_frame
		# Pick up the wide item using the production method, then exercise the
		# actual deferred GUI exchange with a generated left click on the target.
		panel.call("_grab_item", wide_key)
		var target: Dictionary = panel.get("_bins")[target_key]
		await _left_at(panel.get_node("ItemGrid").global_position + Vector2(int(target.x) * 38 + 8, 8))
		if GameState.grabbed_item.is_empty() or "%d:%d" % [GameState.grabbed_item.itemID, GameState.grabbed_item.seqID] != target_key:
			_fail(scenario + ": GUI did not leave displaced target on cursor: " + str(GameState.grabbed_item))
			return
		if not _valid_bins(panel): return
		if scenario == "clear" and Vector2i(bins[wide_key].x, bins[wide_key].y) != Vector2i(2, 0):
			_fail("legal exchange moved the held item away from requested target")
			return
		await _right_at(Vector2(200, 40))
		if not GameState.grabbed_item.is_empty() or _inventory_records() != before or int(NetworkClient.get("_next_response_id")) != next_id:
			_fail(scenario + ": exchange/cancel changed item records or sent item request")
			return
		if not _valid_bins(panel): return
		if OS.has_environment("MIR3_INVENTORY_SWAP_SCREENSHOT"):
			await RenderingServer.frame_post_draw
			var path: String = OS.get_environment("MIR3_INVENTORY_SWAP_SCREENSHOT").get_basename() + "-" + scenario + ".png"
			if get_viewport().get_texture().get_image().save_png(path) != OK:
				_fail("could not save swap screenshot")
				return
	if GameState.belt != belt_before or GameState.wear != wear_before or Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("exchange changed equipment or location")
		return
	_expected_uid = GameState.player_uid
	_reconnecting = true
	NetworkClient.disconnect_from_server()
	await get_tree().process_frame
	NetworkClient.connect_to_server()
	if not await _wait(func(): return _reconnected and _inventory_received and _belt_received and not _main.get_node("MapLoadingOverlay").visible, "swap authoritative re-login"): return
	if _inventory_records() != before or GameState.belt != belt_before or GameState.wear != wear_before or GameState.player_map_uid != origin_map or Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("server re-login did not confirm original inventory/equipment/location")
		return
	print("NETWORK INVENTORY SWAP PASS: generated GUI occupied/edge/legal exchanges, no overlap, displaced cursor and cancel; re-login verifies complete item records, equipment and location")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _inventory_records() -> Dictionary:
	var records := {}
	for item: Dictionary in GameState.inventory:
		records["%d:%d" % [item.itemID, item.seqID]] = item.duplicate(true)
	return records

func _valid_bins(panel: Control) -> bool:
	var bins: Dictionary = panel.get("_bins")
	for key in bins:
		var bin: Dictionary = bins[key]
		if int(bin.x) < 0 or int(bin.x) + int(bin.w) > 10 or int(bin.y) < 0 or panel.call("_occupied", int(bin.x), int(bin.y), int(bin.w), int(bin.h), key):
			_fail("overlapping or out-of-bounds inventory bin")
			return false
	return true

func _left_at(point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.pressed = true
	Input.parse_input_event(click)
	await get_tree().process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await get_tree().process_frame
	await get_tree().process_frame
