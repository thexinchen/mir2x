extends Node

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.inventory = [{"itemID": 6, "seqID": 101, "count": 3}, {"itemID": 826, "seqID": 202, "count": 1}]
	GameState.inventory_initialized = true
	GameState.grabbed_item = {}
	GameState.grabbed_shortcut = {}
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var panel: Control = main.get_node("InventoryPanel")
	var original: Dictionary = panel.get("_bins")["6:101"].duplicate(true)
	panel.call("_grab_item", "6:101")
	main.set("_move_step_timer", 0.25)
	main.set("_player_action_timer", 0.4)
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	main.call("_input", cancel)
	if not GameState.grabbed_item.is_empty() or GameState.inventory.size() != 2:
		_fail("right press did not cancel real inventory drag")
		return
	var returned: Dictionary = panel.get("_bins")["6:101"]
	if returned.x != original.x or returned.y != original.y or returned.item.count != 3:
		_fail("cancel did not preserve original position and quantity")
		return
	if main.get("_move_step_timer") != 0.25 or main.get("_player_action_timer") != 0.4:
		_fail("cancel truncated committed animation timers")
		return
	var weapon: Dictionary = panel.get("_bins")["826:202"].duplicate(true)
	panel.call("_grab_item", "826:202")
	var blocker := {"itemID": 6, "seqID": 303, "count": 1}
	GameState.inventory.append(blocker)
	panel.get("_bins")["6:303"] = {"x": weapon.x, "y": weapon.y, "w": 1, "h": 1, "item": blocker}
	GameState.state_changed.emit()
	main.call("_input", cancel)
	if not GameState.grabbed_item.is_empty() or GameState.inventory.size() != 3:
		_fail("occupied origin prevented returning a multi-cell item")
		return
	var bins: Dictionary = panel.get("_bins")
	for key in bins:
		var bin: Dictionary = bins[key]
		if panel.call("_occupied", int(bin.x), int(bin.y), int(bin.w), int(bin.h), key):
			_fail("cancel fallback overlapped an existing item")
			return
	GameState.item_shortcuts.bind_item(0, GameState.inventory[0], true)
	GameState.grabbed_shortcut = GameState.item_shortcuts.begin_drag(0)
	main.call("_input", cancel)
	if not GameState.grabbed_shortcut.is_empty() or not GameState.item_shortcuts.bindings[0].is_empty() or GameState.inventory.size() != 3:
		_fail("shortcut cancellation changed real ownership")
		return
	if panel.call("cancel_grabbed_item"):
		_fail("empty cursor cancellation must do nothing")
		return
	print("INVENTORY CANCEL PASS: global right cancel, original grid/count, occupied-origin fallback, animation timers, shortcut isolation and empty cursor")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("INVENTORY CANCEL: " + message)
	get_tree().quit(1)
