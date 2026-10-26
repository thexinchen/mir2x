extends Node

var panel: Control
var grid: Control
var created := 0

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.inventory.clear()
	GameState.inventory_operation = {}
	GameState.inventory_operation_cost = {}
	GameState.grabbed_item = {}
	for index in 32:
		GameState.inventory.append({"itemID": 6, "seqID": 100 + index, "count": 3})
	GameState.inventory.append({"itemID": 826, "seqID": 1001, "count": 1, "duration": [10, 20]})
	panel = load("res://scenes/game/panels/inventory.tscn").instantiate()
	add_child(panel)
	panel.show()
	grid = panel.get_node("ItemGrid")
	get_tree().node_added.connect(func(node):
		if node.get_parent() == grid: created += 1)
	var first_id := grid.get_child(0).get_instance_id()
	grid.get_child(0).mouse_entered.emit()
	var tooltip_id := panel.get_node("ItemTooltip").get_child(0).get_instance_id()
	var start := Time.get_ticks_usec()
	for index in 120:
		GameState.player_x = index
		GameState.player_hp = 100 - index % 20
		GameState.state_changed.emit()
	print("INVENTORY REFRESH MEASURE: items=33 unrelated_events=120 created_buttons=%d elapsed_us=%d" % [created, Time.get_ticks_usec() - start])
	if grid.get_child(0).get_instance_id() != first_id or created != 0:
		_fail("walking/health events replaced unchanged inventory controls")
		return
	if grid.get_child(0).get_node("Overlay").color != Color(1, 1, 1, 48.0 / 255.0) or not panel.get_node("ItemTooltip").visible:
		_fail("unrelated updates lost hovered item feedback")
		return
	if panel.get_node("ItemTooltip").get_child(0).get_instance_id() != tooltip_id:
		_fail("unrelated updates rebuilt unchanged tooltip lines")
		return
	GameState.player_gold = 12345
	GameState.state_changed.emit()
	if panel.get_node("Gold").text != "12,345" or grid.get_child(0).get_instance_id() != first_id:
		_fail("gold did not refresh independently of item controls")
		return
	GameState.inventory[0].count = 9
	GameState.state_changed.emit()
	if grid.get_child(0).get_node("Count").text != "9":
		_fail("in-place stack update did not refresh count")
		return
	var weapon_id := grid.get_child(32).get_instance_id()
	GameState.inventory[32].duration[0] = 7
	GameState.state_changed.emit()
	if grid.get_child(32).get_instance_id() == weapon_id:
		_fail("nested item change did not refresh tooltip source")
		return
	panel.set("_selected_key", "6:100")
	GameState.inventory_operation = {"invOp": 1}
	GameState.inventory_operation_cost = {"itemID": 6, "seqID": 100, "cost": 456}
	GameState.state_changed.emit()
	if grid.get_child(0).get_node("Overlay").color != Color(0, 0, 1, 48.0 / 255.0) or not panel.get_node("OperationCost").visible or panel.get_node("OperationCost").text != "456":
		_fail("operation selection/cost did not refresh")
		return
	first_id = grid.get_child(0).get_instance_id()
	GameState.inventory_operation_cost.cost = 789
	GameState.state_changed.emit()
	if panel.get_node("OperationCost").text != "789" or grid.get_child(0).get_instance_id() != first_id:
		_fail("operation quote did not refresh independently of item controls")
		return
	GameState.inventory_operation = {}
	GameState.state_changed.emit()
	if grid.get_child(0).get_node("Overlay").color != Color.TRANSPARENT:
		_fail("closing operation left stale selection")
		return
	panel.call("_grab_item", "6:100")
	if grid.get_child_count() != 32 or GameState.grabbed_item.get("seqID", 0) != 100:
		_fail("drag did not remove visible source")
		return
	panel.call("_place_grabbed", Vector2i(8, 8))
	if grid.get_child_count() != 33 or not GameState.grabbed_item.is_empty() or panel.get("_bins")["6:100"].y < 7:
		_fail("placing item did not refresh its grid position")
		return
	print("INVENTORY REFRESH PASS: retained controls/hover, live gold/count/nested item/selection/quote updates, drag and place")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("INVENTORY REFRESH: " + message)
	get_tree().quit(1)
