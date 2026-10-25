extends Node

const Protocol = preload("res://scripts/network/protocol.gd")

const ITEM_ID := 6
const ITEM_COUNT := 10

enum Stage { WAIT_READY, WAIT_GRABBED, WAIT_DROPPED, WAIT_PICKED, WAIT_CLEANUP }

var _main: Control
var _stage := Stage.WAIT_READY
var _inventory_received := false
var _finished := false
var _initial_seq_id := 0
var _cleanup_failure := ""
var _cleanup_started_msec := 0


func _ready() -> void:
	NetworkClient.connection_changed.connect(_on_connection_changed)
	NetworkClient.message_received.connect(_on_message_received)
	NetworkClient.connect_to_server()
	get_tree().create_timer(30.0).timeout.connect(_on_timeout)


func _process(_delta: float) -> void:
	if _finished or _main == null:
		return
	var inventory_panel := _main.get_node("InventoryPanel") as Control
	match _stage:
		Stage.WAIT_READY:
			if _main.get_node("MapLoadingOverlay").visible or not GameState.player_health_initialized:
				return
			var item := _inventory_item()
			if not _inventory_received or int(item.get("count", 0)) != ITEM_COUNT or not GameState.grabbed_item.is_empty() or _ground_has_item():
				return
			_initial_seq_id = int(item.get("seqID", 0))
			inventory_panel.show()
			if not _emit_inventory_click(inventory_panel, _initial_seq_id):
				return
			_stage = Stage.WAIT_GRABBED
		Stage.WAIT_GRABBED:
			if int(GameState.grabbed_item.get("itemID", 0)) != ITEM_ID or int(GameState.grabbed_item.get("count", 0)) != ITEM_COUNT:
				return
			inventory_panel.hide()
			var renderer := _main.get_node("WorldRenderer") as Control
			var point := _empty_world_point(renderer)
			if point.x < 0:
				_fail("no empty visible world point was available for dropping", 7)
				return
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = point
			click.pressed = true
			_main.call("_unhandled_input", click)
			_stage = Stage.WAIT_DROPPED
		Stage.WAIT_DROPPED:
			if not GameState.grabbed_item.is_empty() or not _inventory_item().is_empty() or not _ground_has_item():
				return
			if OS.has_environment("MIR2X_NETWORK_GROUND_ITEM_SCREENSHOT"):
				Input.warp_mouse(Vector2(
					GameState.player_x * GameState.GRID_XP - GameState.view_x + GameState.GRID_XP / 2,
					GameState.player_y * GameState.GRID_YP - GameState.view_y + GameState.GRID_YP / 2,
				))
				await RenderingServer.frame_post_draw
				var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_NETWORK_GROUND_ITEM_SCREENSHOT"))
				if error != OK:
					_begin_cleanup("failed to save ground-item screenshot: %s" % error)
					return
			_send_tab_pickup()
			_stage = Stage.WAIT_PICKED
		Stage.WAIT_PICKED:
			var returned := _inventory_item()
			if int(returned.get("count", 0)) != ITEM_COUNT or not GameState.grabbed_item.is_empty() or _ground_has_item():
				return
			print("NETWORK GROUND ITEM PASS: item=%d:%d count=%d inventory->ground(%d,%d)->inventory returned_seq=%d" % [ITEM_ID, _initial_seq_id, ITEM_COUNT, GameState.player_x, GameState.player_y, int(returned.get("seqID", 0))])
			_finished = true
			NetworkClient.disconnect_from_server()
			get_tree().quit()
		Stage.WAIT_CLEANUP:
			if int(_inventory_item().get("count", 0)) == ITEM_COUNT and not _ground_has_item():
				_fail(_cleanup_failure, 10)
				return
			if Time.get_ticks_msec() - _cleanup_started_msec >= 5000:
				_fail("%s; cleanup pickup also timed out" % _cleanup_failure, 11)


func _emit_inventory_click(panel: Control, seq_id: int) -> bool:
	var key := "%d:%d" % [ITEM_ID, seq_id]
	var bin: Dictionary = panel.get("_bins").get(key, {})
	if bin.is_empty():
		return false
	var expected := Vector2(int(bin.x) * 38, (int(bin.y) - int(panel.get("_scroll_row"))) * 38)
	for child in panel.get_node("ItemGrid").get_children():
		if child is TextureButton and child.position == expected:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			child.gui_input.emit(event)
			return true
	return false


func _empty_world_point(renderer: Control) -> Vector2:
	for y in range(48, 369, 32):
		for x in range(48, 561, 48):
			var point := Vector2(x, y)
			if int(renderer.call("focus_uid_at_screen", point, true)) == 0:
				return point
	return Vector2(-1, -1)


func _send_tab_pickup() -> void:
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	_main.call("_unhandled_input", tab)


func _ground_has_item() -> bool:
	var key := "%d,%d" % [GameState.player_x, GameState.player_y]
	var items: Array = GameState.ground_items.get(key, [])
	return items.has(ITEM_ID)


func _inventory_item() -> Dictionary:
	for value in GameState.inventory:
		var item: Dictionary = value
		if int(item.get("itemID", 0)) == ITEM_ID:
			return item
	return {}


func _begin_cleanup(message: String) -> void:
	_cleanup_failure = message
	_cleanup_started_msec = Time.get_ticks_msec()
	NetworkClient.send_pickup(GameState.player_x, GameState.player_y, GameState.player_map_uid)
	_stage = Stage.WAIT_CLEANUP


func _on_connection_changed(connected: bool, _message: String) -> void:
	if connected and NetworkClient.login("id_4", "123456") != OK:
		_fail("failed to send login", 2)


func _on_message_received(head_code: int, payload: PackedByteArray) -> void:
	if _finished:
		return
	match head_code:
		NetworkClient.SM_LOGINOK:
			if NetworkClient.enter_game() != OK:
				_fail("failed to enter game", 3)
		NetworkClient.SM_ONLINEOK:
			var online := Protocol.decode_sm_online_ok(payload)
			var action: Dictionary = online.get("action", {})
			GameState.set_player_online({"uid": online.get("uid", 0), "name": online.get("name", ""), "gender": online.get("gender", 0), "job": online.get("job", 0), "map_uid": online.get("mapUID", 0), "x": action.get("x", 0), "y": action.get("y", 0), "direction": action.get("direction", 0)})
			_main = load("res://scenes/game/main.tscn").instantiate() as Control
			add_child(_main)
		NetworkClient.SM_INVENTORY:
			_inventory_received = true
		NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR:
			_fail("server rejected login or online", 4)


func _on_timeout() -> void:
	if _finished or _stage == Stage.WAIT_CLEANUP:
		return
	var message := "timed out stage=%d inventory=%s ground=%s grabbed=%s" % [_stage, _inventory_item(), GameState.ground_items.get("%d,%d" % [GameState.player_x, GameState.player_y], []), GameState.grabbed_item]
	if _ground_has_item():
		_begin_cleanup(message)
	else:
		_fail(message, 6)


func _fail(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	push_error("NETWORK_GROUND_ITEM_SMOKE %s" % message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(code)
