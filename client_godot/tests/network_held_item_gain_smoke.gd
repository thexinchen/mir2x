extends "res://tests/network_item_use_receipt_smoke.gd"

const CONFIG := "user://network_held_item_gain_smoke.cfg"
var latest_update := PackedByteArray()
var baseline := 0
var held_seq := 0
var seeded := false
var cleaning := false

func _ready() -> void:
	OS.set_environment("MIR3_PROTECTION_CONFIG", CONFIG)
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	super._ready()

func _message(head: int, payload: PackedByteArray) -> void:
	if head == NetworkClient.SM_UPDATEITEM: latest_update = payload.duplicate()
	super._message(head, payload)

func _run() -> void:
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "held gain world"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live held-gain actor"): return
	var item := _item()
	if item.is_empty() or int(item.count) >= 99:
		_fail("fixture requires an existing non-full potion stack")
		return
	baseline = _count()
	held_seq = int(item.seqID)
	var belt_before: Array = GameState.belt.duplicate(true)
	var origin := Vector2i(GameState.player_x, GameState.player_y)
	var map_uid: int = GameState.player_map_uid
	var panel: Control = _main.get_node("InventoryPanel")
	var control: Control = _main.get_node("ControlPanel")
	var resources: RefCounted = _main.get("_resources")
	panel.show()
	panel.call("_grab_item", "%d:%d" % [ITEM_ID, held_seq])
	control.call("stop_button_blink", "Inventory")
	var message := "你获得了1个%s" % resources.item_name(ITEM_ID)
	var messages_before := _message_count(message)
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	latest_update.clear()
	if NetworkClient.send_make_item(ITEM_ID) != OK:
		_fail("could not seed one additional item")
		return
	seeded = true
	if not await _wait(func(): return _owned_count() == baseline + 1, "real held stack update"): return
	if GameState.grabbed_item.get("seqID", 0) != held_seq or _inventory_has_held():
		_fail("server update duplicated the held item into inventory")
		return
	if _message_count(message) != messages_before + 1 or not control.get("_button_blinks").has("Inventory") or AudioService.last_seff_id != resources.item_sound_effect(ITEM_ID):
		_fail("real held gain lost notification, inventory blink or item sound")
		return
	var blink_end: int = control.get("_button_blinks").Inventory
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	# Replay the actual received payload through production decoding to verify
	# idempotent feedback; this replay is not a second server reward.
	_main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, latest_update)
	if _message_count(message) != messages_before + 1 or control.get("_button_blinks").Inventory != blink_end or AudioService.last_seff_id != AudioService.INVALID_SEFF_ID or _owned_count() != baseline + 1:
		_fail("duplicate authoritative count repeated gain feedback")
		return
	if not await _expect_reply(func(callback): return NetworkClient.send_consume_item(ITEM_ID, held_seq, 1, callback), NetworkClient.SM_OK, "consume added held potion"): return
	if not await _wait(func(): return _owned_count() == baseline, "restore held gain quantity"): return
	seeded = false
	panel.call("_place_grabbed", Vector2i.ZERO)
	if not GameState.grabbed_item.is_empty() or _count() != baseline or GameState.belt != belt_before or GameState.player_map_uid != map_uid or Vector2i(GameState.player_x, GameState.player_y) != origin:
		_fail("returning held item changed ownership, belt or location")
		return
	if OS.has_environment("MIR3_HELD_GAIN_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_HELD_GAIN_SCREENSHOT"))
	print("NETWORK HELD ITEM GAIN PASS: real same-stack update while dragging, exact gain message/blink/sound, no duplicate ownership or replay feedback, actual consumption SM_OK, original quantity/belt/location")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _owned_count() -> int:
	return _count() + (int(GameState.grabbed_item.get("count", 0)) if int(GameState.grabbed_item.get("itemID", 0)) == ITEM_ID else 0)

func _inventory_has_held() -> bool:
	for item: Dictionary in GameState.inventory:
		if int(item.get("itemID", 0)) == ITEM_ID and int(item.get("seqID", 0)) == held_seq: return true
	return false

func _message_count(message: String) -> int:
	var count := 0
	for entry: Dictionary in GameState.chat_log:
		if entry.get("text", "") == message: count += 1
	return count

func _fail(message: String) -> void:
	if _finished or cleaning: return
	cleaning = true
	if seeded and NetworkClient.is_connected_to_server() and _owned_count() == baseline + 1:
		var replied := [false]
		NetworkClient.send_consume_item(ITEM_ID, held_seq, 1, func(head, _payload): replied[0] = head == NetworkClient.SM_OK)
		for _attempt in 300:
			if replied[0] and _owned_count() == baseline: break
			await get_tree().create_timer(0.01).timeout
		print("HELD GAIN FAILURE CLEANUP: quantity=%d baseline=%d receipt_ok=%s" % [_owned_count(), baseline, replied[0]])
	if is_instance_valid(_main) and not GameState.grabbed_item.is_empty():
		_main.get_node("InventoryPanel").call("_place_grabbed", Vector2i.ZERO)
	super._fail("held gain: " + message)
