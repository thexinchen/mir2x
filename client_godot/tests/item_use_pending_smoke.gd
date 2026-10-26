extends Node

const NetworkScript = preload("res://scripts/network/network_client.gd")

class ProbeNetwork extends NetworkScript:
	var sent: Array = []
	var send_error := OK
	func _send_fixed_message(head: int, payload: PackedByteArray, response_id: int = 0) -> Error:
		sent.append([head, payload, response_id])
		return send_error
	func finish(id: int, head: int) -> Callable:
		var entry: Dictionary = _response_callbacks[id]
		_response_callbacks.erase(id)
		var callback: Callable = entry.callback
		callback.call(head, PackedByteArray())
		return callback


var _failures: Array[String] = []


func _ready() -> void:
	var network := ProbeNetwork.new()
	add_child(network)
	network.set_process(false)
	_expect(network.send_consume_item(6, 101) == OK, "first inventory use accepted")
	_expect(network.pending_item_use == {"itemID": 6, "seqID": 101}, "pending use exposes exact inventory identity for reference retention")
	var id: int = network.sent.back()[2]
	_expect(int(network._response_callbacks[id].expires) - Time.get_ticks_msec() in range(2990, 3001), "manual pending window is3000ms")
	_expect(network.send_consume_belt_item(0) == ERR_BUSY and network.send_consume_item(6, 102) == ERR_BUSY, "inventory blocks both entry paths")
	_expect(network.sent.size() == 1, "busy uses never reach transport")
	network.finish(id, NetworkClient.SM_OK)
	_expect(network.pending_item_use.is_empty(), "matching receipt clears pending reference identity")
	_expect(network.send_consume_belt_item(0) == OK, "success immediately permits next use without fixed cooldown")
	id = network.sent.back()[2]
	_expect(network.send_consume_item(6, 101) == ERR_BUSY, "belt also blocks inventory")
	network.finish(id, NetworkClient.SM_ERROR)
	_expect(network.send_consume_item(6, 101) == OK, "explicit failure permits retry")
	id = network.sent.back()[2]
	var old_callback: Callable = network._response_callbacks[id].callback
	network._response_callbacks[id].expires = Time.get_ticks_msec()
	_expect(network.send_consume_belt_item(1) == OK, "expired pending use permits retry on next attempt")
	var new_id: int = network.sent.back()[2]
	old_callback.call(NetworkClient.SM_OK, PackedByteArray())
	_expect(network.send_consume_item(6, 101) == ERR_BUSY, "late old success cannot release newer use")
	network.finish(new_id, NetworkClient.SM_OK)
	network.send_error = ERR_UNCONFIGURED
	_expect(network.send_consume_item(6, 101) == ERR_UNCONFIGURED, "failed send reports transport error")
	network.send_error = OK
	_expect(network.send_consume_belt_item(2) == OK, "failed send leaves no pending use")
	old_callback = network._response_callbacks[network.sent.back()[2]].callback
	network.disconnect_from_server()
	_expect(network.send_consume_item(6, 101) == OK, "disconnect releases pending state")
	old_callback.call(NetworkClient.SM_ERROR, PackedByteArray())
	_expect(network.pending_item_use == {"itemID": 6, "seqID": 101}, "pre-disconnect result cannot erase new inventory identity")
	_expect(network.send_consume_belt_item(0) == ERR_BUSY, "pre-disconnect callback cannot release new-session use")
	network.disconnect_from_server()
	_expect(network.send_consume_item(6, 101) == OK, "manual request starts shared automatic window")
	id = network.sent.back()[2]
	network._item_use_sent_ms = Time.get_ticks_msec() - 700
	_expect(network.send_consume_item(10, 102, 1, Callable(), true) == ERR_BUSY, "automatic path waits800ms")
	network._item_use_sent_ms = Time.get_ticks_msec() - 800
	_expect(network.send_consume_item(10, 102, 1, Callable(), true) == OK, "automatic path replaces pending at800ms")
	new_id = network.sent.back()[2]
	_expect(network._response_callbacks.has(id), "replacement keeps older correlated callback")
	network.finish(id, NetworkClient.SM_OK)
	_expect(network.pending_item_use == {"itemID": 10, "seqID": 102}, "older success does not clear automatic replacement")
	network._item_use_sent_ms = Time.get_ticks_msec() - 800
	_expect(network.send_consume_item(6, 101) == ERR_BUSY, "manual path still waits3000ms after automatic use")
	network.send_error = ERR_UNCONFIGURED
	_expect(network.send_consume_item(6, 103, 1, Callable(), true) == ERR_UNCONFIGURED, "replacement transport failure reported")
	_expect(network.pending_item_use == {"itemID": 10, "seqID": 102}, "failed replacement restores live pending identity")
	network.send_error = OK
	network.finish(new_id, NetworkClient.SM_ERROR)
	_expect(network.send_consume_item(6, 101, 1, Callable(), true) == OK, "automatic failure immediately permits next request")
	network.disconnect_from_server()
	_expect(network.send_consume_belt_item(0) == OK, "belt starts a pending item with no inventory identity")
	id = network.sent.back()[2]
	network._item_use_sent_ms = Time.get_ticks_msec() - 5000
	network._response_callbacks[id].expires = Time.get_ticks_msec() + 10000
	_expect(network.pending_item_use.is_empty() and network.is_item_use_pending(), "empty inventory identity is not an idle pending object")
	_expect(network.send_protection_book(151, 301) == ERR_BUSY, "Book never replaces live pending item after800 or3000ms")
	network.finish(id, NetworkClient.SM_OK)
	_expect(network.send_protection_book(151, 301) == OK, "Book dispatches when shared pending object is empty")
	id = network.sent.back()[2]
	var book_tick: int = network.protection_book_sent_ms
	_expect(network.send_consume_item(6, 101) == ERR_BUSY, "Book pending also blocks manual use")
	network.finish(id, NetworkClient.SM_ERROR)
	_expect(network.protection_book_sent_ms == book_tick, "server rejection does not undo locally dispatched Book interval")
	network.protection_book_sent_ms = 123
	network.send_error = ERR_UNCONFIGURED
	_expect(network.send_protection_book(151, 301) == ERR_UNCONFIGURED and network.protection_book_sent_ms == 123, "failed Book transport does not update global tick")
	network.send_error = OK
	_expect(network.send_consume_item(6, 101) == OK and network.protection_book_sent_ms == 123, "manual use does not start Book global interval")
	network.disconnect_from_server()
	_expect(network.protection_book_sent_ms == 123, "Book interval survives disconnect into next character session")
	if _failures.is_empty():
		print("ITEM USE PENDING PASS: shared inventory/belt gate, immediate result release, automatic800/manual3000ms retry, stale completion, failed replacement restoration and disconnect")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
