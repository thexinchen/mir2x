extends Node

const Bar = preload("res://scripts/game/item_shortcut_bar.gd")

class InventoryProbe extends Control:
	var uses := 0
	func _use_inventory_item(_item: Dictionary) -> Error:
		uses += 1
		return OK

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.inventory = [{"itemID": 6, "seqID": 101, "count": 2}]
	GameState.grabbed_item = {}
	GameState.grabbed_shortcut = {}
	GameState.item_shortcuts.clear_all()
	GameState.item_shortcuts.bind_item(0, GameState.inventory[0], true)
	var inventory := InventoryProbe.new()
	add_child(inventory)
	var bar := Bar.new()
	add_child(bar)
	bar.inventory_panel = inventory
	# Keep a synthetic outstanding callback alive beyond the manual retry
	# threshold, so transport expiry cannot hide the shortcut's own predicate.
	NetworkClient.set("_item_use_pending_token", 901)
	NetworkClient.set("_item_use_response_id", 902)
	NetworkClient.pending_item_use = {"itemID": 6, "seqID": 101}
	NetworkClient.get("_response_callbacks")[902] = {"expires": Time.get_ticks_msec() + 10000, "callback": func(_head, _payload): pass}
	NetworkClient.set("_item_use_sent_ms", Time.get_ticks_msec() - 1000)
	if bar.use_slot(0) != 0 or inventory.uses != 0:
		_fail("fresh pending request did not block the digit route")
		return
	NetworkClient.set("_item_use_sent_ms", Time.get_ticks_msec() - 3500)
	if bar.use_slot(0) != 3 or inventory.uses != 1:
		_fail("digit route still rejects pending request after the original3000ms retry window")
		return
	if int(NetworkClient.get("_item_use_pending_token")) != 901:
		_fail("readiness probe replaced or cleared the live pending request")
		return
	NetworkClient.set("_item_use_sent_ms", Time.get_ticks_msec())
	NetworkClient.pending_item_use = {} # A belt pending request has no inventory identity.
	if bar.use_slot(0) != 0 or inventory.uses != 1:
		_fail("fresh belt pending request did not block the digit route")
		return
	NetworkClient.get("_response_callbacks").clear()
	NetworkClient.disconnect_from_server()
	print("ITEM SHORTCUT PENDING PASS: digit manual3000ms retry, fresh inventory/belt suppression, readiness preserves live pending")
	get_tree().quit()

func _fail(message: String) -> void:
	NetworkClient.get("_response_callbacks").clear()
	NetworkClient.disconnect_from_server()
	push_error("ITEM SHORTCUT PENDING: " + message)
	get_tree().quit(1)
