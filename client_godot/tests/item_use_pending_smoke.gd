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
	var id: int = network.sent.back()[2]
	_expect(int(network._response_callbacks[id].expires) - Time.get_ticks_msec() in range(2990, 3001), "manual pending window is3000ms")
	_expect(network.send_consume_belt_item(0) == ERR_BUSY and network.send_consume_item(6, 102) == ERR_BUSY, "inventory blocks both entry paths")
	_expect(network.sent.size() == 1, "busy uses never reach transport")
	network.finish(id, NetworkClient.SM_OK)
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
	_expect(network.send_consume_belt_item(0) == ERR_BUSY, "pre-disconnect callback cannot release new-session use")
	network.disconnect_from_server()
	if _failures.is_empty():
		print("ITEM USE PENDING PASS: shared inventory/belt gate, immediate result release,3000ms retry, stale completion, failed send and disconnect")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
