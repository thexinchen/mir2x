extends "res://tests/network_item_use_receipt_smoke.gd"

const CONFIG := "user://network_mir3_protection_smoke.cfg"

func _ready() -> void:
	OS.set_environment("MIR3_PROTECTION_CONFIG", CONFIG)
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	super._ready()

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "initial protection map/inventory"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live protection actor"): return
	var helper: RefCounted = _main.get_mir3_protection()
	var panel: Control = load("res://scenes/game/panels/runtime_config.tscn").instantiate()
	_main.add_child(panel)
	panel.call("_select_main_page", 3)
	panel.call("_select_game_tab", 2)
	if panel.get("_protection") != helper:
		_fail("configuration is not attached to active controller")
		return
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var map_uid: int = GameState.player_map_uid
	var belt_before: Array = GameState.belt.duplicate(true)
	for channel in 3:
		var item_id: int = [6, 10, 14][channel]
		var before := count_item(item_id)
		NetworkClient.send_make_item(item_id, 1)
		if not await _wait(func(): return count_item(item_id) == before + 1, "seed protection medicine"): return
		var controls: Dictionary = panel.get("_protection_controls")[channel]
		controls.interval.value = 300
		controls.threshold.value = GameState.player_mp_max + 1 if channel == 1 else GameState.player_hp_max + 1
		helper.last_request = {}
		helper.channels[channel].last_tick = Time.get_ticks_msec()
		controls.enabled.button_pressed = true
		var restored = load("res://scripts/game/mir3_protection.gd").new()
		restored.load_role(helper.role)
		if not restored.channels[channel].enabled or restored.channels[channel].interval != 300:
			_fail("real configuration controls did not persist")
			return
		if not await _wait(func(): return not helper.last_request.is_empty(), "automatic channel request"): return
		controls.enabled.button_pressed = false
		var request: Dictionary = helper.last_request.duplicate(true)
		if request.error != OK or request.channel != channel or request.item.itemID != item_id:
			_fail("wrong automatic dispatch: %s" % request)
			return
		if not await _wait(func(): return _wire_receipts.has(request.id) and count_item(item_id) == before, "correlated automatic consumption"): return
		if _wire_receipts[request.id] != NetworkClient.SM_OK:
			_fail("automatic use did not receive real SM_OK")
			return
	if OS.has_environment("MIR3_PROTECTION_SCREENSHOT"):
		panel.show()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_PROTECTION_SCREENSHOT"))
	if GameState.belt != belt_before or GameState.player_map_uid != map_uid or Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("automatic recovery changed belt/map/position")
		return
	DirAccess.remove_absolute(CONFIG)
	print("NETWORK MIR3 PROTECTION PASS: real settings persistence, HP/MP/special timed requests, matching wire SM_OK, one item each, unchanged belt/map/position")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func count_item(item_id: int) -> int:
	var count := 0
	for value in GameState.inventory:
		if int(value.get("itemID", 0)) == item_id: count += int(value.get("count", 0))
	return count
