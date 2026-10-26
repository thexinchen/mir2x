extends "res://tests/network_item_use_receipt_smoke.gd"

const CONFIG := "user://network_book_protection_smoke.cfg"
const SCROLL := 151
var reconnecting := false
var reconnected := false
var expected_uid := 0
var origin := Vector2i.ZERO
var origin_map := 0
var teleports: Array[Dictionary] = []

func _ready() -> void:
	OS.set_environment("MIR3_PROTECTION_CONFIG", CONFIG)
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	super._ready()

func _message(head: int, payload: PackedByteArray) -> void:
	if head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if data.get("uid", 0) == GameState.player_uid and data.get("action", {}).get("type", 0) == 6: teleports.append(data)
	if reconnecting and head == NetworkClient.SM_ONLINEOK:
		var online := Protocol.decode_sm_online_ok(payload)
		if int(online.uid) != expected_uid:
			_fail("reconnected to different role")
			return
		var action: Dictionary = online.action
		GameState.set_player_online({"uid": online.uid, "name": online.name, "gender": online.gender, "job": online.job, "map_uid": online.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
		_main = load("res://scenes/game/main.tscn").instantiate()
		add_child(_main)
		reconnected = true
		return
	super._message(head, payload)

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "Book initial world"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live Book actor"): return
	origin = Vector2i(GameState.player_x, GameState.player_y)
	origin_map = GameState.player_map_uid
	var baseline := scroll_count()
	NetworkClient.send_make_item(SCROLL, 2)
	if not await _wait(func(): return scroll_count() == baseline + 2, "seed two Book scrolls"): return
	var panel := make_panel()
	var helper: RefCounted = _main.get_mir3_protection()
	var controls: Dictionary = panel.get("_protection_controls")[3]
	var choice: OptionButton = panel.get_node("SystemPage/BookChoice")
	choice.select(1)
	choice.item_selected.emit(1)
	controls.threshold.value = GameState.player_hp_max + 1
	controls.enabled.button_pressed = true
	if helper.book_selection != 1 or helper.channels[3].interval != 100:
		_fail("GUI did not select original Book mode1/default100ms")
		return
	if not await _wait(func(): return not helper.last_request.is_empty(), "first automatic Book request"): return
	var first: Dictionary = helper.last_request.duplicate(true)
	if first.channel != 3 or first.error != OK or first.item.itemID != SCROLL:
		_fail("first Book dispatch invalid: %s" % first)
		return
	var first_tick: int = NetworkClient.protection_book_sent_ms
	if not await _wait(func(): return _wire_receipts.has(first.id) and scroll_count() == baseline + 1 and teleports.size() == 1, "first Book real receipt/teleport"): return
	if _wire_receipts[first.id] != NetworkClient.SM_OK:
		_fail("first Book was not acknowledged by server")
		return
	expected_uid = GameState.player_uid
	reconnecting = true
	_main.queue_free()
	_main = null
	NetworkClient.disconnect_from_server()
	_inventory_received = false
	_belt_received = false
	await get_tree().process_frame
	NetworkClient.connect_to_server()
	if not await _wait(func(): return reconnected and _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "Book same-role reconnect"): return
	helper = _main.get_mir3_protection()
	if not helper.channels[3].enabled or helper.book_selection != 1 or NetworkClient.protection_book_sent_ms != first_tick:
		_fail("Book settings or process dispatch tick did not survive new main/login")
		return
	_stage = "real twenty-second Book interval"
	while not _finished and helper.last_request.is_empty():
		if Time.get_ticks_msec() - first_tick > 24500:
			_fail("second Book request did not arrive after twenty seconds")
			return
		await get_tree().process_frame
	if _finished: return
	var second: Dictionary = helper.last_request.duplicate(true)
	var elapsed: int = NetworkClient.protection_book_sent_ms - first_tick
	panel = make_panel()
	panel.get("_protection_controls")[3].enabled.button_pressed = false
	if elapsed < 20000 or second.channel != 3 or second.error != OK:
		_fail("Book bypassed real twenty-second global gate: elapsed=%d request=%s" % [elapsed, second])
		return
	if not await _wait(func(): return _wire_receipts.has(second.id) and scroll_count() == baseline and teleports.size() == 2, "second Book real receipt/teleport"): return
	if _wire_receipts[second.id] != NetworkClient.SM_OK:
		_fail("second Book was not acknowledged by server")
		return
	var point := Vector2i(GameState.player_x, GameState.player_y)
	if GameState.player_map_uid != origin_map or not _main.get_node("WorldRenderer").can_walk(point.x, point.y) or not is_equal_approx(GameState.view_x, point.x * 48.0 - 400.0):
		_fail("automatic Book did not follow authoritative same-map view")
		return
	if OS.has_environment("MIR3_BOOK_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_BOOK_SCREENSHOT"))
	if point != origin:
		NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
		if not await _wait(func(): return GameState.player_map_uid == origin_map and Vector2i(GameState.player_x, GameState.player_y) == origin, "restore Book origin"): return
	DirAccess.remove_absolute(CONFIG)
	print("NETWORK BOOK PROTECTION PASS: real GUI/default100ms, automatic scroll receipts/teleports, fresh main on same UID relog, preserved global20s gate elapsed=%dms, original quantity/location restored" % elapsed)
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func make_panel() -> Control:
	var panel: Control = load("res://scenes/game/panels/runtime_config.tscn").instantiate()
	_main.add_child(panel)
	panel.call("_select_main_page", 3)
	panel.call("_select_game_tab", 2)
	return panel

func scroll_count() -> int:
	var count := 0
	for item in GameState.inventory:
		if int(item.get("itemID", 0)) == SCROLL: count += int(item.get("count", 0))
	return count

func _fail(message: String) -> void:
	if _finished: return
	_finished = true
	push_error("NETWORK BOOK PROTECTION: " + message)
	if is_instance_valid(_main): _main.get_mir3_protection().channels[3].enabled = false
	if origin_map > 0 and NetworkClient.is_connected_to_server() and Vector2i(GameState.player_x, GameState.player_y) != origin:
		NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
		for attempt in 400:
			if Vector2i(GameState.player_x, GameState.player_y) == origin: break
			await get_tree().create_timer(0.01).timeout
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
