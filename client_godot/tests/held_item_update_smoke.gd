extends Node

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.inventory = []
	GameState.grabbed_item = {"itemID": 6, "seqID": 101, "count": 3}
	if GameState.update_item({"itemID": 6, "seqID": 101, "count": 5}) != 2:
		_fail("held stack gain did not return the authoritative +2 delta")
		return
	if not GameState.inventory.is_empty() or GameState.grabbed_item.count != 5:
		_fail("held stack update duplicated ownership or lost the new count")
		return
	if GameState.update_item({"itemID": 6, "seqID": 101, "count": 5, "duration": [7, 20]}) != 0 or GameState.grabbed_item.duration != [7, 20]:
		_fail("same-count attribute update should replace data without a gain")
		return
	if GameState.update_item({"itemID": 6, "seqID": 101, "count": 2}) != -3:
		_fail("held stack loss did not return its negative delta")
		return
	if GameState.update_item({"itemID": 10, "seqID": 202, "count": 4}) != 4 or GameState.grabbed_item.count != 2:
		_fail("another item update changed the held item")
		return
	if GameState.update_item({"itemID": 10, "seqID": 202, "count": 5}) != 1 or GameState.inventory.size() != 1:
		_fail("ordinary inventory delta changed")
		return
	if GameState.update_item({"itemID": 6, "seqID": 101, "count": 0}) != -2 or not GameState.grabbed_item.is_empty():
		_fail("zero held count did not clear the cursor and return its loss")
		return
	print("HELD ITEM UPDATE PASS: gain/loss deltas, no duplicate inventory, same-count attributes, independent items and zero clear")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("HELD ITEM UPDATE: " + message)
	get_tree().quit(1)
