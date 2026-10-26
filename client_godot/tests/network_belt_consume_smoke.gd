extends Node

const Protocol = preload("res://scripts/network/protocol.gd")

const ITEM_ID := 6
var _initial_count := 0
const BELT_SLOT := 0

enum Stage { WAIT_READY, WAIT_GRABBED, WAIT_EQUIPPED, WAIT_DEAD, WAIT_CONSUMED, WAIT_RETURNED, WAIT_PLACED, WAIT_INVENTORY_CONSUMED }

var _main: Control
var _stage := Stage.WAIT_READY
var _inventory_received := false
var _belt_received := false
var _finished := false
var _initial_seq_id := 0
var _expected_count := 0
var _deferred_failure := ""
var _consume_started_msec := 0
var _death_key_mode := false


func _ready() -> void:
	_death_key_mode = OS.has_environment("MIR2X_NETWORK_BELT_DEAD_KEY")
	NetworkClient.connection_changed.connect(_on_connection_changed)
	NetworkClient.message_received.connect(_on_message_received)
	NetworkClient.connect_to_server()
	get_tree().create_timer(30.0).timeout.connect(_on_timeout)


func _process(_delta: float) -> void:
	if _finished or _main == null:
		return
	var inventory_panel := _main.get_node("InventoryPanel") as Control
	var quick_bar := _main.get_node("QuickBar") as Control
	match _stage:
		Stage.WAIT_READY:
			var item := _inventory_item()
			if not _inventory_received or not _belt_received or int(item.get("count", 0)) < 2 or not _belt_item().is_empty() or not GameState.grabbed_item.is_empty():
				return
			_initial_seq_id = int(item.get("seqID", 0))
			_initial_count = int(item.get("count", 0))
			_expected_count = _initial_count - 1
			inventory_panel.show()
			if not _emit_inventory_click(inventory_panel, _initial_seq_id):
				return
			_stage = Stage.WAIT_GRABBED
		Stage.WAIT_GRABBED:
			if int(GameState.grabbed_item.get("itemID", 0)) != ITEM_ID or int(GameState.grabbed_item.get("count", 0)) != _initial_count:
				return
			if int(quick_bar.call("activate_slot", BELT_SLOT, MOUSE_BUTTON_LEFT)) == 0:
				_fail("visible quick slot rejected the recovery potion", 7)
				return
			_stage = Stage.WAIT_EQUIPPED
		Stage.WAIT_EQUIPPED:
			if int(_belt_item().get("itemID", 0)) != ITEM_ID or int(_belt_item().get("count", 0)) != _initial_count or not GameState.grabbed_item.is_empty():
				return
			inventory_panel.hide()
			quick_bar.show()
			if OS.has_environment("MIR2X_NETWORK_BELT_CONSUME_SCREENSHOT"):
				await RenderingServer.frame_post_draw
				var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_NETWORK_BELT_CONSUME_SCREENSHOT"))
				if error != OK:
					_fail("failed to save belt-consume screenshot: %s" % error, 8)
					return
			if _death_key_mode:
				_submit_command("@die")
				_stage = Stage.WAIT_DEAD
				return
			if int(quick_bar.call("activate_slot", BELT_SLOT, MOUSE_BUTTON_RIGHT)) == 0:
				_fail("visible quick slot rejected potion consumption", 9)
				return
			_consume_started_msec = Time.get_ticks_msec()
			_stage = Stage.WAIT_CONSUMED
		Stage.WAIT_DEAD:
			if GameState.player_hp != 0:
				return
			var before_key := int(NetworkClient.get("_next_response_id"))
			var key_event := InputEventKey.new()
			key_event.keycode = KEY_1
			key_event.pressed = true
			_main.call("_unhandled_input", key_event)
			if int(NetworkClient.get("_next_response_id")) != before_key:
				_fail("empty inventory shortcut consumed separately stored belt item", 11)
				return
			if int(quick_bar.call("activate_slot", BELT_SLOT, MOUSE_BUTTON_RIGHT)) == 0:
				_fail("dead right click rejected legacy belt item", 11)
				return
			_consume_started_msec = Time.get_ticks_msec()
			_stage = Stage.WAIT_CONSUMED
		Stage.WAIT_CONSUMED:
			var belt_count := int(_belt_item().get("count", 0))
			if belt_count == _initial_count - 1:
				if _death_key_mode:
					print("NETWORK DEAD BELT ISOLATION PASS: unbound digit ignores belt; right click consumes one item while dead")
					_submit_command("@revive")
				quick_bar.call("activate_slot", BELT_SLOT, MOUSE_BUTTON_LEFT)
				_stage = Stage.WAIT_RETURNED
				return
			if Time.get_ticks_msec() - _consume_started_msec < 1000:
				return
			if _death_key_mode:
				_fail("dead right click did not decrement belt slot 0: %s" % [_belt_item()], 11)
				return
			_expected_count = _initial_count
			_deferred_failure = "belt potion consumption applied without decrementing slot 0: %s" % [_belt_item()]
			quick_bar.call("activate_slot", BELT_SLOT, MOUSE_BUTTON_LEFT)
			_stage = Stage.WAIT_RETURNED
		Stage.WAIT_RETURNED:
			if not _belt_item().is_empty() or int(GameState.grabbed_item.get("itemID", 0)) != ITEM_ID or int(GameState.grabbed_item.get("count", 0)) != _expected_count:
				return
			inventory_panel.show()
			inventory_panel.call("_place_grabbed", Vector2i(5, 5))
			_stage = Stage.WAIT_PLACED
		Stage.WAIT_PLACED:
			var restored := _inventory_item()
			if not GameState.grabbed_item.is_empty() or int(restored.get("count", 0)) != _expected_count:
				return
			if not _deferred_failure.is_empty():
				_fail(_deferred_failure, 10)
				return
			if not _emit_inventory_click(inventory_panel, int(restored.get("seqID", 0)), MOUSE_BUTTON_RIGHT):
				return
			_stage = Stage.WAIT_INVENTORY_CONSUMED
		Stage.WAIT_INVENTORY_CONSUMED:
			if _death_key_mode and GameState.player_hp <= 0: return
			var remaining := _inventory_item()
			if int(remaining.get("count", 0)) != _expected_count - 1:
				return
			print("NETWORK BELT CONSUME PASS: item=%d:%d belt=%d->%d inventory=%d->%d" % [ITEM_ID, _initial_seq_id, _initial_count, _expected_count, _expected_count, _expected_count - 1])
			_finished = true
			NetworkClient.disconnect_from_server()
			get_tree().quit()


func _emit_inventory_click(panel: Control, seq_id: int, button := MOUSE_BUTTON_LEFT) -> bool:
	var key := "%d:%d" % [ITEM_ID, seq_id]
	var bin: Dictionary = panel.get("_bins").get(key, {})
	if bin.is_empty():
		return false
	var expected := Vector2(int(bin.x) * 38, (int(bin.y) - int(panel.get("_scroll_row"))) * 38)
	for child in panel.get_node("ItemGrid").get_children():
		if child is TextureButton and child.position == expected:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = true
			child.gui_input.emit(event)
			return true
	return false


func _submit_command(text: String) -> void:
	var command := _main.get_node("ControlPanel").get_node("%Command") as LineEdit
	command.text = text
	command.text_submitted.emit(command.text)


func _belt_item() -> Dictionary:
	if BELT_SLOT >= GameState.belt.size() or not GameState.belt[BELT_SLOT] is Dictionary:
		return {}
	var item: Dictionary = GameState.belt[BELT_SLOT]
	return {} if int(item.get("itemID", 0)) == 0 else item


func _inventory_item() -> Dictionary:
	for value in GameState.inventory:
		var item: Dictionary = value
		if int(item.get("itemID", 0)) == ITEM_ID:
			return item
	return {}


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
		NetworkClient.SM_BELT:
			_belt_received = true
		NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR:
			_fail("server rejected login or online", 4)


func _on_timeout() -> void:
	_fail("timed out stage=%d inventory=%s belt=%s grabbed=%s" % [_stage, _inventory_item(), _belt_item(), GameState.grabbed_item], 6)


func _fail(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	push_error("NETWORK_BELT_CONSUME_SMOKE %s" % message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(code)
