extends Node

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	var panel: Control = load("res://scenes/game/panels/inventory.tscn").instantiate()
	GameState.inventory = [
		{"itemID": 766, "seqID": 111, "count": 1, "duration": [17, 25]},
		{"itemID": 6, "seqID": 222, "count": 3},
		{"itemID": 6, "seqID": 333, "count": 2},
	]
	GameState.grabbed_item = {}
	GameState.grabbed_shortcut = {}
	add_child(panel)
	var size: Vector2i = panel.call("_item_grid_size", 766)
	if size.x <= 1:
		_fail("requires a real armor wider than one cell")
		return
	for scenario in ["occupied", "right_edge", "clear"]:
		# Only local layout is adjusted. Real item sizes and ownership are used.
		var bins: Dictionary = panel.get("_bins")
		bins["766:111"].x = 0
		bins["766:111"].y = 5
		bins["6:222"].x = 9 if scenario == "right_edge" else 2
		bins["6:222"].y = 0
		bins["6:333"].x = 2 + (1 if size.x > 1 else 0) if scenario == "occupied" else 0
		bins["6:333"].y = (0 if size.x > 1 else 1) if scenario == "occupied" else 0
		GameState.state_changed.emit()
		panel.call("_grab_item", "766:111")
		panel.call("_grab_item", "6:222")
		if GameState.grabbed_item.get("seqID", 0) != 222 or GameState.inventory.size() != 2:
			_fail(scenario + ": exchange lost the displaced cursor or duplicated inventory")
			return
		bins = panel.get("_bins")
		if bins["766:111"].item.get("duration") != [17, 25]:
			_fail(scenario + ": exchange changed item attributes")
			return
		for key in bins:
			var bin: Dictionary = bins[key]
			if int(bin.x) < 0 or int(bin.x) + int(bin.w) > 10 or int(bin.y) < 0 or panel.call("_occupied", int(bin.x), int(bin.y), int(bin.w), int(bin.h), key):
				_fail(scenario + ": exchanged item overlaps another bin or escapes the grid")
				return
		if scenario == "clear" and Vector2i(bins["766:111"].x, bins["766:111"].y) != Vector2i(2, 0):
			_fail("valid exchange did not retain the requested destination")
			return
		panel.call("cancel_grabbed_item")
		if not GameState.grabbed_item.is_empty() or GameState.inventory.size() != 3:
			_fail(scenario + ": displaced cursor could not return to inventory")
			return
	print("INVENTORY SWAP GEOMETRY PASS: real multi-cell occupied/edge/valid targets, displaced cursor, attributes and cancel ownership")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("INVENTORY SWAP GEOMETRY: " + message)
	get_tree().quit(1)
