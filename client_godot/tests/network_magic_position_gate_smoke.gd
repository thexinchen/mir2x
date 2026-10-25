extends "res://tests/network_thrust_smoke.gd"

var observed_space := false

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("good", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(45.0).timeout.connect(func(): _fail("timeout at " + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	super._message(head, payload)
	if head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if int(data.get("uid", 0)) == GameState.player_uid and int(data.get("action", {}).get("type", 0)) == 6:
			observed_space = true

func _run() -> void:
	stage = "prepare position clock"
	await get_tree().create_timer(3.0).timeout
	original_map = GameState.player_map_uid
	original_position = Vector2i(GameState.player_x, GameState.player_y)
	var target := original_position + Vector2i.RIGHT
	var renderer: Control = main.get_node("WorldRenderer")
	if not renderer.can_walk(target.x, target.y):
		_fail("adjacent test position is blocked")
		return
	var before := Time.get_ticks_msec()
	main.set("_last_magic_request_ms", -500)
	observed_space = false
	if not await _relocate(original_map, target):
		_fail("server did not confirm exact test relocation")
		return
	var clock: int = main.get("_last_magic_request_ms")
	var thrust: int = main.get("_resources").magic_id("刺杀剑术")
	if not observed_space or clock < before or main.call("_magic_ready", thrust, clock + 499) or not main.call("_magic_ready", thrust, clock + 500):
		_fail("own authoritative space message did not set the command gate")
		return
	if not await _restore_position():
		_fail("could not restore original position")
		return
	print("NETWORK MAGIC POSITION GATE PASS: real self-space packet resets command clock, 499/500ms boundary, original position restored")
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()
