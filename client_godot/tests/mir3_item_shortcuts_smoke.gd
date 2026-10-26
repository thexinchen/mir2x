extends Node

const Model = preload("res://scripts/game/mir3_item_shortcuts.gd")
var failures: Array[String] = []


func _ready() -> void:
	var model := Model.new()
	var a := {"itemID": 6, "seqID": 101, "count": 2}
	var b := {"itemID": 6, "seqID": 102, "count": 3}
	model.bind_item(0, a, true)
	_expect(model.resolve(0, [a, b]).count == 5, "grouped reference totals inventory stacks")
	_expect(model.resolve(0, [a], a).count == 2, "held identity is not counted twice")
	_expect(model.resolve(0, [a], b).count == 5, "locally held inventory item remains available")
	_expect(model.resolve(0, []).count == 0 and not model.bindings[0].is_empty(), "grouped empty reference remains available for later acquisition")
	_expect(model.resolve(0, [b]).seqID == 102, "grouped reference resolves a new inventory instance")
	model.bind_item(1, a, false)
	_expect(model.resolve(1, [], {}, a).count == 0, "matching pending instance preserves a non-grouped reference")
	_expect(model.resolve(1, [b]).is_empty(), "unrelated instance cannot satisfy exact reference")
	_expect(not model.bind_item(10, a, true) and Model.key_slot(KEY_MINUS) == -1, "invalid slot and non-digit rejected")
	var drag := Model.new()
	var other := {"itemID": 7, "seqID": 103, "count": 1}
	drag.bind_item(0, a, true)
	drag.bind_item(1, other, false)
	var cursor := drag.begin_drag(0)
	_expect(not drag.bindings[0].is_empty(), "pickup keeps source reference")
	cursor = drag.place_drag(1, cursor)
	_expect(drag.bindings[0].item.itemID == 7 and drag.bindings[1].item.itemID == 6 and cursor.item.itemID == 7, "occupied target swaps references and continues with displaced item")
	cursor = drag.place_drag(0, cursor)
	_expect(cursor.is_empty() and drag.bindings[0].item.itemID == 7, "same-source click ends drag without deleting reference")
	cursor = drag.begin_drag(0)
	cursor = drag.place_drag(9, cursor)
	_expect(cursor.is_empty() and drag.bindings[0].is_empty() and drag.bindings[9].item.itemID == 7, "empty target commits a move and ends drag")
	drag.cancel_drag(drag.begin_drag(9))
	_expect(drag.bindings[9].is_empty() and not drag.bindings[1].is_empty(), "discard removes only the active source reference")
	var scoped = GameState.get_script().new()
	scoped.set_player_online({"uid": 41})
	scoped.item_shortcuts.bind_item(0, a, true)
	scoped.set_player_online({"uid": 41})
	_expect(scoped.item_shortcuts.bindings[0].is_empty() and not scoped.inventory_initialized, "new login session clears references even for the same character")
	scoped.item_shortcuts.bind_item(0, a, true)
	scoped.start_game_scene({"uid": 41})
	_expect(not scoped.item_shortcuts.bindings[0].is_empty(), "ordinary scene update does not reset inventory references")
	scoped.set_player_online({"uid": 42})
	_expect(scoped.item_shortcuts.bindings[0].is_empty(), "another character cannot inherit shortcut references")
	scoped.free()
	GameState.inventory = [{"itemID": 6, "seqID": 505, "count": 4}]
	GameState.inventory_initialized = true
	GameState.item_shortcuts.clear_all()
	GameState.grabbed_item = {}
	GameState.grabbed_shortcut = {}
	var belt_before: Array = GameState.belt.duplicate(true)
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var bar: Control = main.get("item_shortcut_bar")
	var inventory: Control = main.get_node("InventoryPanel")
	var next_id := int(NetworkClient.get("_next_response_id"))
	for slot in 10:
		inventory.call("_grab_item", "6:505")
		if slot == 0:
			var click_slot := InputEventMouseButton.new()
			click_slot.button_index = MOUSE_BUTTON_LEFT
			click_slot.pressed = true
			click_slot.position = bar.get_node("Slot0").get_global_rect().get_center()
			Input.parse_input_event(click_slot)
			await get_tree().process_frame
			_expect(GameState.item_shortcuts.bindings[0].is_empty(), "shortcut press alone does not complete a reference transfer")
			click_slot.pressed = false
			click_slot.position -= Vector2(40, 0)
			Input.parse_input_event(click_slot)
			await get_tree().process_frame
			_expect(GameState.item_shortcuts.bindings[0].is_empty() and not GameState.grabbed_item.is_empty(), "release outside the pressed shortcut does not transfer the reference")
			click_slot.position += Vector2(40, 0)
			click_slot.pressed = true
			Input.parse_input_event(click_slot)
			await get_tree().process_frame
			click_slot.pressed = false
			Input.parse_input_event(click_slot)
			await get_tree().process_frame
			await get_tree().process_frame
			_expect(not GameState.item_shortcuts.bindings[0].is_empty(), "real GUI click binds the inventory reference")
			_expect(not bar.get_node("Slot0").tooltip_text.is_empty() and bar.get_node("Slot0").get_child_count() >= 2, "real GUI click finishes refreshing its icon and tooltip")
		else:
			_expect(bar.call("activate_slot", slot, MOUSE_BUTTON_LEFT) == 1, "bind slot%d from held inventory" % slot)
		_expect(GameState.inventory == [{"itemID": 6, "seqID": 505, "count": 4}] and GameState.grabbed_item.is_empty(), "binding returns the same item without moving ownership")
	_expect(GameState.belt == belt_before and int(NetworkClient.get("_next_response_id")) == next_id, "binding never equips or consumes a belt item")
	await get_tree().process_frame
	var stable_holder := bar.get_node("Slot0").get_instance_id()
	GameState.state_changed.emit()
	await get_tree().process_frame
	_expect(bar.get_node("Slot0").get_instance_id() == stable_holder, "unrelated scene state preserves existing shortcut HUD nodes")
	var used: Array = []
	bar.slot_action_requested.connect(func(action, slot):
		if action == 3: used.append(slot))
	_expect(bar.call("activate_slot", 0, MOUSE_BUTTON_RIGHT) == 0 and used.is_empty(), "right click does not invoke shortcut use")
	for slot in 10:
		var key := InputEventKey.new()
		key.keycode = KEY_1 + slot if slot < 9 else KEY_0
		key.pressed = true
		main.call("_unhandled_input", key)
	_expect(used == range(10), "all ten digits dispatch their inventory shortcut")
	for slot in 10:
		var control: Control = bar.get_node("Slot%d" % slot)
		_expect(control.position == Vector2(bar.SLOT_X[slot], 8) and control.size == Vector2(29, 32), "original slot%d inner geometry" % slot)
	GameState.item_shortcuts.clear(9)
	bar.call("activate_slot", 0, MOUSE_BUTTON_LEFT)
	_expect(not GameState.item_shortcuts.bindings[0].is_empty(), "picking up a shortcut keeps its source until transfer succeeds")
	var held_key := InputEventKey.new()
	held_key.keycode = KEY_1
	held_key.pressed = true
	main.call("_unhandled_input", held_key)
	_expect(used.back() == 0 and not GameState.grabbed_shortcut.is_empty(), "source digit remains usable while its shortcut reference is on the cursor")
	_expect(GameState.grabbed_item.is_empty() and not GameState.grabbed_shortcut.is_empty(), "moving a shortcut cursor does not grab another inventory item")
	bar.call("activate_slot", 9, MOUSE_BUTTON_LEFT)
	_expect(GameState.grabbed_shortcut.is_empty() and GameState.item_shortcuts.bindings[0].is_empty() and not GameState.item_shortcuts.bindings[9].is_empty(), "shortcut reference moves between slots")
	bar.call("activate_slot", 9, MOUSE_BUTTON_LEFT)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(400, 200)
	main.call("_handle_mouse_click", click)
	_expect(GameState.grabbed_shortcut.is_empty() and GameState.inventory == [{"itemID": 6, "seqID": 505, "count": 4}], "discarding shortcut cursor never drops or duplicates inventory")
	if failures.is_empty(): print("MIR3 ITEM SHORTCUTS PASS: ten inventory references, grouped/exact refresh, pending retention, bind/move/discard without inventory or belt transfer, all digit routes and source geometry")
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
