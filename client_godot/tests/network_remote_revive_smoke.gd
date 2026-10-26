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
	elif head in [NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR]:
		_finish(false, "observer login rejected")


func _process(_delta: float) -> void:
	if finished or main == null: return
	var actor: Dictionary = GameState.get_creature(subject_uid)
	if not ready_sent and not actor.is_empty() and actor.get("health_initialized", false) and int(actor.get("hp", 0)) > 0:
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
			_finish(true, "real remote HP0/death -> positive HP/Stand restored living actor")
	elif Time.get_ticks_msec() - positive_after_death_ms > 5000:
		_finish(false, "positive HP and real Stand left remote actor dead: " + str(actor.get("action_type", 0)))


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
