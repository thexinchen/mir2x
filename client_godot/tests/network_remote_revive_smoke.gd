extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const CerealReader = preload("res://scripts/network/cereal_reader.gd")
var main: Control
var exchange := ""
var subject_uid := 0
var finished := false
var ready_sent := false
var saw_zero_health := false
var saw_death_action := false
var positive_after_death_ms := 0
var stands_after_death := 0
var correction := false
var original_position := Vector2i.ZERO
var saw_correction := false
var saw_death_after_health := false
var verifying_display := false
var appearance_replies := 0


func _ready() -> void:
	exchange = OS.get_environment("MIR3_DEATH_OBSERVER_EXCHANGE")
	correction = OS.get_environment("MIR3_REMOTE_REVIVE_CORRECTION") == "1"
	subject_uid = FileAccess.get_file_as_string(exchange + "/subject.uid").to_int()
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("id_3", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(25.0).timeout.connect(func(): _finish(false, "observer timeout"))


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
	elif head == NetworkClient.SM_HEALTH:
		var reader := CerealReader.new(payload)
		var data := reader.read_sd_health()
		if reader.valid and data.get("uid", 0) == subject_uid:
			if int(data.get("hp", 0)) == 0: saw_zero_health = true
			elif saw_zero_health and positive_after_death_ms == 0: positive_after_death_ms = Time.get_ticks_msec()
	elif head == NetworkClient.SM_ACTION:
		var data := Protocol.decode_sm_action(payload)
		if data.get("uid", 0) == subject_uid:
			if data.action.get("type", 0) == 13: saw_death_action = true
			elif data.action.get("type", 0) == 2 and saw_death_action: stands_after_death += 1
	elif head == NetworkClient.SM_PLAYERWLDESP:
		var reader := CerealReader.new(payload)
		var data := reader.read_sd_uid_wldesp()
		if reader.valid and data.get("uid", 0) == subject_uid: appearance_replies += 1
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_finish(false, "observer login rejected")


func _process(_delta: float) -> void:
	if finished or main == null or verifying_display: return
	var actor: Dictionary = GameState.get_creature(subject_uid)
	if not ready_sent and not main.get_node("MapLoadingOverlay").visible and not main.get_node("WorldRenderer").loading_map \
			and not actor.is_empty() and actor.get("health_initialized", false) and int(actor.get("hp", 0)) > 0:
		original_position = Vector2i(actor.x, actor.y)
		if correction and not _prepare_correction(actor):
			_finish(false, "no walkable remote correction fixture")
			return
		var ready_file := FileAccess.open(exchange + "/observer.ready", FileAccess.WRITE)
		ready_file.store_string("ready")
		ready_file.close()
		ready_sent = true
	if ready_sent and not actor.get("forced_action_queue", []).is_empty(): saw_correction = true
	if positive_after_death_ms > 0 and actor.get("action_type", 0) == 13: saw_death_after_health = true
	if positive_after_death_ms == 0 or not saw_death_action or stands_after_death == 0: return
	if actor.is_empty():
		_finish(false, "reviving actor disappeared while subject stayed online")
		return
	if actor.get("action_type", 0) == 2 and int(actor.get("hp", 0)) > 0:
		if correction and (not saw_correction or not saw_death_after_health or Vector2i(actor.x, actor.y) != original_position):
			_finish(false, "early remote revival skipped correction/death or failed to restore authoritative position")
		elif actor.has("dead_fade_requested_ms") or not actor.get("forced_action_queue", []).is_empty():
			_finish(false, "revived actor retained death/fade state")
		else:
			verifying_display = true
			_verify_revived_display(actor)
	elif Time.get_ticks_msec() - positive_after_death_ms > 5000:
		_finish(false, "positive HP and real Stand left remote actor dead: " + str(actor.get("action_type", 0)))


func _verify_revived_display(actor: Dictionary) -> void:
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	GameState.view_x = int(actor.x) * 48 - 400
	GameState.view_y = int(actor.y) * 32 - 260
	renderer.draw_hp_bar = true
	renderer.queue_redraw()
	# Revival can complete after this frame's draw commands were built. Inspect
	# the next completed frame, rather than the previous corpse hitbox cache.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rectangles: Dictionary = renderer.get("_actor_target_rects")
	if not rectangles.has(subject_uid) or renderer.get("_corpse_target_rects").has(subject_uid) \
			or not renderer.call("_should_draw_actor_status", int(actor.action_type)) \
			or renderer.call("_dead_actor_alpha", actor, Time.get_ticks_msec()) != 1.0:
		_finish(false, "revival display mismatch: live=%s corpse=%s status=%s alpha=%s action=%s view=%s loading=%s" % [
			rectangles.has(subject_uid), renderer.get("_corpse_target_rects").has(subject_uid),
			renderer.call("_should_draw_actor_status", int(actor.action_type)), renderer.call("_dead_actor_alpha", actor, Time.get_ticks_msec()),
			actor.action_type, Vector2(GameState.view_x, GameState.view_y), renderer.loading_map])
		return
	var point: Vector2 = rectangles[subject_uid].rect.get_center()
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var fireball: int = main.get("_resources").magic_id("火球术")
	if main.call("_update_magic_focus", Vector2i(actor.x, actor.y), fireball) != subject_uid:
		_finish(false, "revived player could not be selected through its rendered hitbox")
		return
	var before := appearance_replies
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_CTRL
	ctrl.pressed = true
	Input.parse_input_event(ctrl)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = point
	click.ctrl_pressed = true
	click.pressed = true
	Input.parse_input_event(click)
	await get_tree().process_frame
	click.pressed = false
	Input.parse_input_event(click)
	ctrl.pressed = false
	Input.parse_input_event(ctrl)
	var panel: Control
	for _attempt in range(150):
		panel = main.get("_extra_panel_nodes").get(main.PLAYER_INSPECTION_PANEL_PATH) as Control
		if panel != null and panel.visible and panel.get("inspected_uid") == subject_uid and appearance_replies > before: break
		await get_tree().create_timer(0.01).timeout
	if panel == null or not panel.visible or appearance_replies <= before:
		_finish(false, "revived player inspection did not receive a fresh real appearance reply")
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(exchange + "/revived-inspection.png")
	_finish(true, "real remote revival, live rendered hitbox/status/opacity, selection and Ctrl-right fresh inspection reply")


func _prepare_correction(actor: Dictionary) -> bool:
	var renderer: Node = main.get_node("WorldRenderer")
	for radius in [6, 4]:
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var clear := true
			for distance in range(1, radius + 1):
				var tile: Vector2i = original_position + direction * distance
				if not renderer.can_walk(tile.x, tile.y): clear = false
			if clear:
				var displaced: Vector2i = original_position + direction * radius
				actor["x"] = displaced.x
				actor["y"] = displaced.y
				actor["action_from_x"] = displaced.x
				actor["action_from_y"] = displaced.y
				GameState.update_creature(subject_uid, actor)
				return true
	return false


func _finish(success: bool, reason: String) -> void:
	if finished: return
	finished = true
	var done_file := FileAccess.open(exchange + "/observer.done", FileAccess.WRITE)
	if done_file != null:
		done_file.store_string(reason)
		done_file.close()
	if success: print("NETWORK REMOTE REVIVE PASS: " + reason)
	else: push_error("NETWORK REMOTE REVIVE: " + reason)
	NetworkClient.disconnect_from_server()
	get_tree().quit(0 if success else 1)
