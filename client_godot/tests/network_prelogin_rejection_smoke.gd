extends Node

var rejected := false
var finished := false

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if not connected: return
		# Both legacy traffic and a correlated invalid request must leave login usable.
		NetworkClient.send_request_space_move(24, 405, 118)
		var payload := PackedByteArray()
		payload.resize(12)
		NetworkClient.call("_send_request", NetworkClient.CM_REQUESTSPACEMOVE, payload, false,
			func(head, _body):
				rejected = head == NetworkClient.SM_ERROR
				NetworkClient.login("id_3", "123456")))
	NetworkClient.message_received.connect(func(head, _payload):
		if head == NetworkClient.SM_LOGINOK:
			finished = true
			NetworkClient.disconnect_from_server()
			if not rejected:
				push_error("PRELOGIN REJECTION: missing correlated rejection")
				get_tree().quit(1)
			else:
				print("PRELOGIN REJECTION PASS: legacy and correlated gameplay rejected; following login remains usable")
				get_tree().quit(0)
		elif head == NetworkClient.SM_LOGINERROR:
			_fail("login rejected"))
	NetworkClient.connect_to_server()
	get_tree().create_timer(5.0).timeout.connect(func(): _fail("timeout"))

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	NetworkClient.disconnect_from_server()
	push_error("PRELOGIN REJECTION: " + reason)
	get_tree().quit(1)
