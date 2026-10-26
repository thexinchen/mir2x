extends "res://tests/network_item_use_receipt_smoke.gd"

const CONFIG := "user://network_shortcut_retry_smoke.cfg"

func _ready() -> void:
	OS.set_environment("MIR3_PROTECTION_CONFIG", CONFIG)
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	super._ready()

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "shortcut retry world"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live retry actor"): return
	var baseline := _count()
	var belt_before: Array = GameState.belt.duplicate(true)
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var map_uid: int = GameState.player_map_uid
	NetworkClient.send_make_item(ITEM_ID, 2)
	if not await _wait(func(): return _count() == baseline + 2, "seed two retry potions"): return
	var panel: Control = _main.get_node("InventoryPanel")
	var bar: Control = _main.get("item_shortcut_bar")
	panel.call("_grab_item", "%d:%d" % [ITEM_ID, _item().seqID])
	if bar.call("activate_slot", 0, MOUSE_BUTTON_LEFT) != 1:
		_fail("could not bind digit1")
		return
	bar.call("activate_slot", 0, MOUSE_BUTTON_LEFT)
	if GameState.grabbed_shortcut.is_empty():
		_fail("could not hold source reference")
		return
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	# Controlled client-side receive delay, not a real packet-loss claim.
	# Keep the first callback alive past3000ms to exercise the manual retry
	# predicate independently of the adapter's normal3000ms expiry.
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	NetworkClient.set_process(false)
	_main.call("_unhandled_input", key)
	var first_id: int = NetworkClient.get("_item_use_response_id")
	var first_tick: int = NetworkClient.get("_item_use_sent_ms")
	var callbacks: Dictionary = NetworkClient.get("_response_callbacks")
	if not callbacks.has(first_id):
		_fail("first digit request did not establish callback")
		return
	callbacks[first_id].expires = Time.get_ticks_msec() + 10000
	var first_callback: Callable = callbacks[first_id].callback
	var next_token := [0]
	var old_reply_preserved_new := [false]
	callbacks[first_id].callback = func(head, payload):
		first_callback.call(head, payload)
		old_reply_preserved_new[0] = int(NetworkClient.get("_item_use_pending_token")) == int(next_token[0]) and int(next_token[0]) != 0
	var next_id: int = NetworkClient.get("_next_response_id")
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	_main.call("_unhandled_input", key)
	if int(NetworkClient.get("_next_response_id")) != next_id or AudioService.last_seff_id != AudioService.INVALID_SEFF_ID:
		_fail("fresh digit repeat sent again or replayed sound")
		return
	while Time.get_ticks_msec() - first_tick < 3100:
		await get_tree().process_frame
	if not NetworkClient.is_item_use_pending() or not callbacks.has(first_id):
		_fail("first callback expired instead of exercising live retry")
		return
	_main.call("_unhandled_input", key)
	var elapsed: int = int(NetworkClient.get("_item_use_sent_ms")) - first_tick
	var second_id: int = NetworkClient.get("_item_use_response_id")
	next_token[0] = int(NetworkClient.get("_item_use_pending_token"))
	if second_id == first_id or int(NetworkClient.get("_next_response_id")) != next_id + 1 or elapsed < 3000 or _count() != baseline + 2:
		_fail("digit retry failed or optimistically changed inventory: elapsed=%d" % elapsed)
		return
	_main.process_mode = Node.PROCESS_MODE_INHERIT
	NetworkClient.set_process(true)
	if not await _wait(func(): return _wire_receipts.has(first_id) and _wire_receipts.has(second_id) and _count() == baseline, "two real delayed digit receipts and quantity"): return
	if _wire_receipts[first_id] != NetworkClient.SM_OK or _wire_receipts[second_id] != NetworkClient.SM_OK or not old_reply_preserved_new[0] or NetworkClient.is_item_use_pending():
		_fail("delayed first receipt released replacement or real item use was rejected")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if int(GameState.grabbed_shortcut.get("item", {}).get("count", -1)) != baseline or GameState.belt != belt_before or GameState.player_map_uid != map_uid or Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("held reference, belt or location changed incorrectly after retry")
		return
	if OS.has_environment("MIR3_SHORTCUT_RETRY_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_SHORTCUT_RETRY_SCREENSHOT"))
	print("NETWORK SHORTCUT RETRY PASS: held-source digit1, fresh repeat suppressed, real interval=%dms with controlled receive delay, two wire SM_OK/one item each, stale receipt preserves replacement, original quantity/belt/location" % elapsed)
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(message: String) -> void:
	if _finished: return
	NetworkClient.set_process(true)
	if is_instance_valid(_main): _main.process_mode = Node.PROCESS_MODE_INHERIT
	super._fail("shortcut retry: " + message)
