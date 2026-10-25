extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
var main: Control
var role := ""
var token := ""
var target_file := ""
var finished := false
var finishing := false
var target_cpid := 0

func _ready() -> void:
	role = OS.get_environment("MIR2X_PRIVATE_ROLE")
	token = OS.get_environment("MIR2X_PRIVATE_TOKEN")
	target_file = OS.get_environment("MIR2X_PRIVATE_TARGET_FILE")
	if role not in ["sender", "receiver"] or token.is_empty() or target_file.is_empty():
		_fail("missing isolated runner environment")
		return
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4" if role == "sender" else "id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(20.0).timeout.connect(func(): _fail("timed out role=" + role))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		var action: Dictionary = data.action
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job, "map_uid": data.mapUID, "x": action.x, "y": action.y, "direction": action.direction})
		main = load("res://scenes/game/main.tscn").instantiate()
		add_child(main)
		_run()
	elif head == NetworkClient.SM_PLAYERSAY and payload.slice(8).get_string_from_utf8().contains(token):
		_fail("private command leaked into nearby chat")
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	main.set_process(false)
	if role == "receiver":
		var file := FileAccess.open(target_file, FileAccess.WRITE)
		# JSON numbers lose the low bits of a 64-bit actor UID in Godot.
		file.store_string(JSON.stringify({"name": GameState.player_name, "uid": str(GameState.player_uid)}))
		file.close()
		return
	for _i in range(100):
		if FileAccess.file_exists(target_file): break
		await get_tree().create_timer(0.05).timeout
	var target = JSON.parse_string(FileAccess.get_file_as_string(target_file))
	if not target is Dictionary:
		_fail("receiver fixture unavailable")
		return
	target_cpid = (2 << 32) | (int(target.uid) & 0xFFFFFFFF)
	var renderer: Control = main.get_node("WorldRenderer")
	var point := Vector2(420, 240)
	GameState.creatures[int(target.uid)] = {"uid": int(target.uid), "name": str(target.name), "type": 2, "x": GameState.player_x + 3, "y": GameState.player_y, "action_type": 2}
	renderer.set("_actor_target_rects", {int(target.uid): {"rect": Rect2(point - Vector2(10, 20), Vector2(30, 40)), "map_y": GameState.player_y}})
	renderer.set("_mouse_focus_uid", int(target.uid))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.alt_pressed = true
	click.position = point
	if DisplayServer.get_name() == "headless":
		main.call("_handle_mouse_click", click)
	else:
		main.get_node("MapLoadingOverlay").hide()
		Input.warp_mouse(point)
		var motion := InputEventMouseMotion.new()
		motion.position = point
		Input.parse_input_event(motion)
		Input.parse_input_event(click)
		await get_tree().process_frame
	var panel: Control = main.get_node("ControlPanel")
	var command: LineEdit = panel.get("command")
	if command.text != "/%s " % target.name or command.caret_column != command.text.length():
		_fail("Alt target did not prefill private command and caret")
		return
	if main.get("_ground_input").button != MOUSE_BUTTON_RIGHT:
		_fail("Alt private prefill swallowed ground movement")
		return
	command.text = "/%s %s <>&" % [target.name, token]
	command.text_submitted.emit(command.text)
	# A missing name must fail privately too, never fall back to nearby say.
	panel.call("_on_command_submitted", "/missing_%s %s" % [token, token])

func _process(_delta: float) -> void:
	if finished or finishing or main == null: return
	for message in GameState.chat_messages.values():
		if GameState.chat_message_text(message) != token + " <>&": continue
		if role == "sender" and int(message.get("to", 0)) != target_cpid:
			_fail("sender acknowledgement cached wrong recipient: expected=%d actual=%d" % [target_cpid, int(message.get("to", 0))])
			return
		if role == "receiver" and (int(message.get("from", 0)) != (2 << 32 | 7) or int(message.get("to", 0)) != GameState.self_chat_cpid()):
			_fail("receiver message routing mismatch")
			return
		finishing = true
		_finish()
		return

func _finish() -> void:
	await get_tree().create_timer(1.0).timeout
	if finished: return
	if role == "sender":
		var rejected := false
		for line in GameState.chat_log:
			if str(line.get("text", "")).begins_with("找不到私聊角色：missing_"):
				rejected = true
		if not rejected:
			_fail("missing recipient did not report a private failure")
			return
	print("PRIVATE COMMAND %s PASS: Alt prefill, private delivery, literal XML characters, no nearby broadcast" % role.to_upper())
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(message: String) -> void:
	if finished: return
	finished = true
	push_error("PRIVATE COMMAND %s: %s" % [role, message])
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
