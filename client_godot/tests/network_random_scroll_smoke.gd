extends "res://tests/network_item_use_receipt_smoke.gd"

const SCROLL := 151
var teleports: Array[Dictionary] = []
var origin := Vector2i.ZERO
var origin_map := 0

func _message(head: int, payload: PackedByteArray) -> void:
	if head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if data.get("uid", 0) == GameState.player_uid and data.get("action", {}).get("type", 0) == 6:
			teleports.append(data)
	super._message(head, payload)

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "scroll inventory/map"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live scroll actor"): return
	origin = Vector2i(GameState.player_x, GameState.player_y)
	origin_map = GameState.player_map_uid
	if OS.has_environment("MIR3_SCROLL_FIXTURE_TOWN") and GameState.player_map_id == 24:
		origin = Vector2i(407, 126)
		if Vector2i(GameState.player_x, GameState.player_y) != origin:
			NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
			if not await _wait(func(): return Vector2i(GameState.player_x, GameState.player_y) == origin, "prepare standard town fixture"): return
		teleports.clear()
	var belt_before := belt_signature()
	var slot := -1
	for index in GameState.belt.size():
		if _belt_item(index).is_empty(): slot = index; break
	if slot < 0:
		_fail("requires empty belt slot")
		return
	var baseline := scroll_count()
	NetworkClient.send_make_item(SCROLL, 4)
	if not await _wait(func(): return scroll_count() == baseline + 4, "seed four scrolls"): return
	var item := scroll_item()
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(SCROLL, int(item.seqID), 2, cb), NetworkClient.SM_ERROR, "reject two scrolls in one use"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(SCROLL, 2147483647, 1, cb), NetworkClient.SM_ERROR, "reject unowned scroll"): return
	if scroll_count() != baseline + 4 or not teleports.is_empty():
		_fail("rejected scroll changed position or quantity")
		return
	_submit_command("@die")
	if not await _wait(func(): return GameState.player_hp == 0, "dead inventory scroll actor"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(SCROLL, int(item.seqID), 1, cb), NetworkClient.SM_ERROR, "dead inventory scroll rejection"): return
	if scroll_count() != baseline + 4 or not teleports.is_empty():
		_fail("dead inventory scroll consumed or teleported")
		return
	_submit_command("@revive")
	if not await _wait(func(): return GameState.player_hp > 0 and GameState.player_action_type != 13, "revive inventory scroll actor"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_item(SCROLL, int(item.seqID), 1, cb), NetworkClient.SM_OK, "direct random scroll"): return
	if not await expect_teleport(1, baseline + 3): return
	item = scroll_item()
	var response: int = NetworkClient.get("_next_response_id")
	if int(_main.get_node("InventoryPanel").call("_use_inventory_item", item)) != OK:
		_fail("inventory GUI rejected random scroll")
		return
	if not await _wait(func(): return _wire_receipts.has(response), "GUI scroll receipt"): return
	if _wire_receipts[response] != NetworkClient.SM_OK:
		_fail("GUI scroll use failed")
		return
	if not await expect_teleport(2, baseline + 2): return
	item = scroll_item()
	NetworkClient.send_request_equip_belt(SCROLL, int(item.seqID), slot)
	if not await _wait(func(): return int(_belt_item(slot).get("itemID", 0)) == SCROLL, "equip scroll belt"): return
	var belt_count := int(_belt_item(slot).count)
	_submit_command("@die")
	if not await _wait(func(): return GameState.player_hp == 0, "dead belt scroll actor"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_belt_item(slot, cb), NetworkClient.SM_ERROR, "dead belt scroll rejection"): return
	if int(_belt_item(slot).count) != belt_count or teleports.size() != 2:
		_fail("dead belt scroll consumed or teleported")
		return
	_submit_command("@revive")
	if not await _wait(func(): return GameState.player_hp > 0 and GameState.player_action_type != 13, "revive belt scroll actor"): return
	if not await _expect_reply(func(cb): return NetworkClient.send_consume_belt_item(slot, cb), NetworkClient.SM_OK, "belt random scroll"): return
	if not await _wait(func(): return teleports.size() == 3 and int(_belt_item(slot).get("count", 0)) == belt_count - 1, "belt teleport and consume"): return
	if not _belt_item(slot).is_empty():
		NetworkClient.send_request_grab_belt(slot)
		if not await _wait(func(): return GameState.grabbed_item.get("itemID", 0) == SCROLL and _belt_item(slot).is_empty(), "restore belt scroll inventory"): return
		_main.get_node("InventoryPanel").call("_place_grabbed", Vector2i(5, 5))
		if not await _wait(func(): return GameState.grabbed_item.is_empty() and scroll_count() == baseline + 1, "place restored scroll"): return
	item = scroll_item()
	var inventory: Control = _main.get_node("InventoryPanel")
	inventory.call("_grab_item", "%d:%d" % [SCROLL, item.seqID])
	var bar: Control = _main.get("item_shortcut_bar")
	if int(bar.call("activate_slot", 9, MOUSE_BUTTON_LEFT)) != 1:
		_fail("scroll shortcut binding failed")
		return
	response = int(NetworkClient.get("_next_response_id"))
	var key := InputEventKey.new()
	key.keycode = KEY_0
	key.pressed = true
	_main.call("_unhandled_input", key)
	if not await _wait(func(): return _wire_receipts.has(response), "scroll zero-key receipt"): return
	if _wire_receipts[response] != NetworkClient.SM_OK:
		_fail("scroll zero-key failed")
		return
	if not await expect_teleport(4, baseline): return
	if scroll_count() != baseline or belt_signature() != belt_before:
		_fail("successful uses did not restore initial fixture quantities/belt: quantity=%d expected=%d belt=%s initial=%s" % [scroll_count(), baseline, GameState.belt, belt_before])
		return
	if OS.has_environment("MIR3_RANDOM_SCROLL_SCREENSHOT"):
		if not await _wait(func(): return GameState.player_action_type == 2, "teleport animation returns to stand"): return
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_RANDOM_SCROLL_SCREENSHOT"))
	if GameState.player_map_uid != origin_map or Vector2i(GameState.player_x, GameState.player_y) != origin:
		NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
		if not await _wait(func(): return GameState.player_map_uid == origin_map and Vector2i(GameState.player_x, GameState.player_y) == origin, "restore scroll origin"): return
	print("NETWORK RANDOM SCROLL PASS: direct/GUI/zero-key/belt authoritative teleports, one scroll per success, invalid and dead uses rejected, original quantities/belt/location restored")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func belt_signature() -> Array:
	var result: Array = []
	for slot in GameState.belt.size(): result.append(_belt_item(slot).duplicate(true))
	return result

func _fail(message: String) -> void:
	if _finished: return
	_finished = true
	push_error("NETWORK RANDOM SCROLL: " + message)
	if origin_map > 0 and NetworkClient.is_connected_to_server():
		NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
		for attempt in 400:
			if GameState.player_map_uid == origin_map and Vector2i(GameState.player_x, GameState.player_y) == origin: break
			await get_tree().create_timer(0.01).timeout
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)

func expect_teleport(count: int, quantity: int) -> bool:
	if not await _wait(func(): return teleports.size() == count and scroll_count() == quantity, "scroll teleport and quantity"): return false
	var data: Dictionary = teleports.back()
	var target := Vector2i(int(data.action.aimX), int(data.action.aimY))
	if GameState.player_map_uid != origin_map or Vector2i(GameState.player_x, GameState.player_y) != target or not _main.get_node("WorldRenderer").can_walk(target.x, target.y):
		_fail("scroll did not follow same-map authoritative traversable destination")
		return false
	if _main.get_node("WorldRenderer").player_draw_grid().distance_to(Vector2(target)) > 0.01:
		_fail("teleport draw position interpolated from the old tile")
		return false
	if not is_equal_approx(GameState.view_x, target.x * 48.0 - 400.0) or not is_equal_approx(GameState.view_y, target.y * 32.0 - GameState.camera_center_y()):
		_fail("teleport camera is still converging from old location")
		return false
	return true

func scroll_item() -> Dictionary:
	for item in GameState.inventory:
		if int(item.get("itemID", 0)) == SCROLL: return item
	return {}

func scroll_count() -> int:
	var count := 0
	for item in GameState.inventory:
		if int(item.get("itemID", 0)) == SCROLL: count += int(item.get("count", 0))
	return count
