extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const Reader = preload("res://scripts/network/cereal_reader.gd")
var role := ""
var exchange := ""
var main: Control
var started := false
var finished := false
var target_uid := 0
var appearances := 0

func _ready() -> void:
	role = OS.get_environment("MIR3_INSPECTION_ROLE")
	exchange = OS.get_environment("MIR3_INSPECTION_EXCHANGE")
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_4" if role == "actor" else "id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(30.0).timeout.connect(func(): _fail("overall timeout"))

func _message(head: int, payload: PackedByteArray) -> void:
	if finished: return
	if head == NetworkClient.SM_LOGINOK:
		NetworkClient.enter_game()
	elif head == NetworkClient.SM_ONLINEOK:
		var data := Protocol.decode_sm_online_ok(payload)
		GameState.set_player_online({"uid": data.uid, "name": data.name, "gender": data.gender, "job": data.job,
			"map_uid": data.mapUID, "x": data.action.x, "y": data.action.y, "direction": data.action.direction})
		main = load("res://scenes/game/main.tscn").instantiate()
		add_child(main)
	elif head == NetworkClient.SM_PLAYERWLDESP:
		var reader := Reader.new(payload)
		var data := reader.read_sd_uid_wldesp()
		if reader.valid and reader.at_end() and data.uid == target_uid:
			appearances += 1
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_fail("login rejected")

func _process(_delta: float) -> void:
	if finished or main == null: return
	if role == "actor" and FileAccess.file_exists(exchange + "/done"):
		_pass("actor closed")
		return
	if started or main.get_node("MapLoadingOverlay").visible or GameState.player_hp <= 0:
		return
	if role == "actor":
		started = true
		var file := FileAccess.open(exchange + "/actor.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"uid": str(GameState.player_uid), "name": GameState.player_name,
			"gender": GameState.player_gender, "desp": GameState.player_desp}))
		file.close()
	elif FileAccess.file_exists(exchange + "/actor.json"):
		var actor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange + "/actor.json"))
		target_uid = int(actor.uid)
		if not GameState.get_creature(target_uid).is_empty():
			started = true
			_run_observer(actor)

func _run_observer(expected: Dictionary) -> void:
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	var actor: Dictionary = GameState.get_creature(target_uid)
	GameState.view_x = int(actor.x) * 48 - 400
	GameState.view_y = int(actor.y) * 32 - 280
	renderer.queue_redraw()
	await RenderingServer.frame_post_draw
	var rectangles: Dictionary = renderer.get("_actor_target_rects")
	if not rectangles.has(target_uid):
		_fail("real remote player did not produce a rendered hit rectangle")
		return
	var point: Vector2 = rectangles[target_uid].rect.get_center()
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_CTRL
	ctrl.pressed = true
	Input.parse_input_event(ctrl)
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = point
	click.ctrl_pressed = true
	click.pressed = true
	var before := appearances
	Input.parse_input_event(click)
	await get_tree().process_frame
	click.pressed = false
	Input.parse_input_event(click)
	ctrl.pressed = false
	Input.parse_input_event(ctrl)
	var panel: Control
	for _attempt in range(150):
		panel = main.get("_extra_panel_nodes").get(main.PLAYER_INSPECTION_PANEL_PATH) as Control
		if panel != null and panel.visible and panel.get("inspected_uid") == target_uid and appearances > before:
			break
		await get_tree().create_timer(0.01).timeout
	if panel == null or not panel.visible or appearances <= before:
		_fail("Ctrl right did not show inspection after actual query response")
		return
	if panel.get_node("Name").text != expected.name or panel.get_node("CharacterLayers").get("_appearance").gender != bool(expected.gender):
		_fail("panel name/gender differs from the other client's own state")
		return
	for location in range(1, 12):
		var wanted: Dictionary = expected.desp.wear.get(str(location), {})
		var actual: Dictionary = panel.get_node("EquipmentSlots/Slot%d" % location).get_meta("item")
		if int(actual.get("itemID", 0)) != int(wanted.get("itemID", 0)) or int(actual.get("seqID", 0)) != int(wanted.get("seqID", 0)):
			_fail("server equipment differs from actor snapshot at slot %d" % location)
			return
	var own_wear := GameState.wear.duplicate(true)
	var own_grabbed := GameState.grabbed_item.duplicate(true)
	var slot_point: Vector2 = panel.get_node("EquipmentSlots/Slot3").get_global_rect().get_center()
	Input.warp_mouse(slot_point)
	motion.position = slot_point
	Input.parse_input_event(motion)
	var slot_click := InputEventMouseButton.new()
	slot_click.button_index = MOUSE_BUTTON_LEFT
	slot_click.position = slot_point
	slot_click.pressed = true
	Input.parse_input_event(slot_click)
	await get_tree().process_frame
	slot_click.pressed = false
	Input.parse_input_event(slot_click)
	if GameState.wear != own_wear or GameState.grabbed_item != own_grabbed or main.get("_ground_input").button != 0:
		_fail("readonly equipment click changed own items or leaked into world input")
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(exchange + "/inspection.png")
	(panel.get_node("CloseButton") as BaseButton).pressed.emit()
	before = appearances
	NetworkClient.send_query_player_wldesp(target_uid)
	for _attempt in range(100):
		if appearances > before: break
		await get_tree().create_timer(0.01).timeout
	if panel.visible or appearances <= before:
		_fail("closed panel reopened on unsolicited appearance response")
		return
	FileAccess.open(exchange + "/done", FileAccess.WRITE).store_string("done")
	_pass("observer: actual remote player hit, Ctrl query/response, cross-client equipment, preview, close and late reply")

func _pass(message: String) -> void:
	finished = true
	print("NETWORK PLAYER INSPECTION PASS " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(message: String) -> void:
	finished = true
	push_error("NETWORK INSPECTION " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
