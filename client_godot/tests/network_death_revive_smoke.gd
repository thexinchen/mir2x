extends Node

const Protocol = preload("res://scripts/network/protocol.gd")

enum Stage { WAIT_READY, WAIT_DEAD, WAIT_REVIVED }

var _main: Control
var _stage := Stage.WAIT_READY
var _health_received := false
var _revive_health_msec := 0
var _finished := false
var _early_revive := false
var _saw_forced_correction := false
var _saw_death_after_revive := false
var _saw_health_death_gate := false
var _saw_health_revive_release := false
var _authoritative_position := Vector2i.ZERO
var _aura_mode := false
var _aura_sent := false
var _aura_received_ms := 0


func _ready() -> void:
	_early_revive = OS.has_environment("MIR2X_NETWORK_DEATH_EARLY_REVIVE")
	_aura_mode = OS.get_environment("MIR3_NETWORK_DEATH_AURA") == "1"
	NetworkClient.connection_changed.connect(_on_connection_changed)
	NetworkClient.message_received.connect(_on_message_received)
	NetworkClient.connect_to_server()
	get_tree().create_timer(30.0).timeout.connect(_on_timeout)


func _process(_delta: float) -> void:
	if _finished or _main == null:
		return
	var renderer := _main.get_node("WorldRenderer") as Control
	var overlay := _main.get_node("DeathOverlay") as ColorRect
	match _stage:
		Stage.WAIT_READY:
			if not _health_received or GameState.player_hp <= 0 or GameState.player_action_type == 13:
				return
			var world: RefCounted = renderer.get("world_resource")
			if int(world.get("map_id")) != GameState.player_map_id:
				return
			if _aura_mode:
				if not _aura_sent:
					if not _main.call("_action_request_ready"): return
					var resources: RefCounted = _main.get("_resources")
					_aura_sent = _main.call("_send_spell_action", 9, resources.magic_id("魔法盾"), Vector2i(GameState.player_x, GameState.player_y), GameState.player_uid)
					return
				if _aura_received_ms == 0 or Time.get_ticks_msec() - _aura_received_ms < 1200: return
				if GameState.attached_magic_effects.is_empty():
					_fail("real shield reply did not create death fixture", 19)
					return
			_authoritative_position = Vector2i(GameState.player_x, GameState.player_y)
			if _early_revive and not _prepare_forced_correction(renderer):
				_fail("no walkable client/server death-correction fixture was available", 13)
				return
			_submit_command("@die")
			_stage = Stage.WAIT_DEAD
		Stage.WAIT_DEAD:
			if GameState.player_hp != 0:
				return
			if _aura_mode and not GameState.attached_magic_effects.is_empty():
				_fail("real HP=0 retained shield attachment", 20)
				return
			if _early_revive:
				var forced_queue: Array = _main.get("_player_forced_action_queue")
				if forced_queue.is_empty() or GameState.player_action_type == 13:
					return
				_saw_forced_correction = true
				if not _escape_recenters("forced death correction"):
					return
				_submit_command("@revive")
				_stage = Stage.WAIT_REVIVED
				return
			if GameState.player_action_type != 13:
				return
			_main.call("_update_death_overlay")
			if not overlay.visible or not overlay.color.is_equal_approx(Color(128.0 / 255.0, 0, 0, 64.0 / 255.0)):
				_fail("authoritative death did not show the original red veil", 7)
				return
			_main.set("_follow_focus_uid", 777)
			var blocked_click := InputEventMouseButton.new()
			blocked_click.button_index = MOUSE_BUTTON_RIGHT
			blocked_click.pressed = true
			blocked_click.position = Vector2(500, 300)
			_main.call("_unhandled_input", blocked_click)
			if int(_main.get("_follow_focus_uid")) != 777:
				_fail("dead player accepted a world mouse command", 8)
				return
			if not _escape_recenters("dead player"):
				return
			if OS.has_environment("MIR2X_NETWORK_DEATH_SCREENSHOT"):
				await RenderingServer.frame_post_draw
				var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_NETWORK_DEATH_SCREENSHOT"))
				if error != OK:
					_fail("failed to save authoritative death screenshot: %s" % error, 9)
					return
			_submit_command("@revive")
			_stage = Stage.WAIT_REVIVED
		Stage.WAIT_REVIVED:
			if GameState.player_hp <= 0:
				return
			if _revive_health_msec == 0:
				_revive_health_msec = Time.get_ticks_msec()
			if GameState.player_action_type == 13:
				_saw_death_after_revive = true
			if GameState.player_action_type != 2 or not (_main.get("_player_forced_action_queue") as Array).is_empty() or not (_main.get("_player_post_forced_action") as Dictionary).is_empty():
				if Time.get_ticks_msec() - _revive_health_msec >= 5000:
					_fail("revive health recovered but correction/death/stand did not finish", 10)
				return
			if not _saw_health_death_gate or not _saw_health_revive_release:
				_fail("real health packets did not drive both sides of the C++ death gate", 16)
				return
			if _early_revive and (not _saw_forced_correction or not _saw_death_after_revive or Vector2i(GameState.player_x, GameState.player_y) != _authoritative_position):
				_fail("early revive skipped correction/death or missed authoritative position: forced=%s death=%s pos=%s expected=%s" % [_saw_forced_correction, _saw_death_after_revive, Vector2i(GameState.player_x, GameState.player_y), _authoritative_position], 14)
				return
			_main.call("_update_death_overlay")
			if overlay.visible:
				_fail("revived player retained the death veil", 11)
				return
			if _aura_mode and not GameState.attached_magic_effects.is_empty():
				_fail("revival resurrected pre-death shield", 21)
				return
			var live_click := InputEventMouseButton.new()
			live_click.button_index = MOUSE_BUTTON_RIGHT
			live_click.pressed = true
			live_click.position = Vector2(500, 300)
			_main.set("_follow_focus_uid", 777)
			_main.call("_unhandled_input", live_click)
			if int(_main.get("_follow_focus_uid")) == 777:
				_fail("revived player did not regain world mouse input", 12)
				return
			print("NETWORK DEATH REVIVE PASS: visible @die -> @revive hp=%d/action=%d forced=%s death=%s pos=%s world-input" % [GameState.player_hp, GameState.player_action_type, _saw_forced_correction, _saw_death_after_revive, Vector2i(GameState.player_x, GameState.player_y)])
			if _aura_mode: print("NETWORK AURA DEATH PASS: actual shield cast, health death clears attachment, revival does not restore it")
			_finished = true
			NetworkClient.disconnect_from_server()
			get_tree().quit()


func _submit_command(text: String) -> void:
	var command := _main.get_node("ControlPanel").get_node("%Command") as LineEdit
	command.text = text
	command.text_submitted.emit(command.text)


func _escape_recenters(context: String) -> bool:
	_main.call("_center_hero")
	var centered_view := Vector2(GameState.view_x, GameState.view_y)
	GameState.view_x += 123.0
	GameState.view_y += 77.0
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	_main.call("_unhandled_input", escape_key)
	if not Vector2(GameState.view_x, GameState.view_y).is_equal_approx(centered_view):
		_fail("%s did not preserve the original Escape camera recenter" % context, 15)
		return false
	return true


func _prepare_forced_correction(renderer: Control) -> bool:
	for radius in range(6, 2, -1):
		for offset_value in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
			var offset: Vector2i = offset_value
			var candidate: Vector2i = _authoritative_position + offset
			if not renderer.call("can_walk", candidate.x, candidate.y):
				continue
			var correction: Array = _main.call("_forced_correction_steps", candidate, _authoritative_position, 2)
			if correction.size() < 2:
				continue
			GameState.player_x = candidate.x
			GameState.player_y = candidate.y
			GameState.player_action_from_x = candidate.x
			GameState.player_action_from_y = candidate.y
			return true
	return false


func _on_connection_changed(connected: bool, _message: String) -> void:
	if connected and NetworkClient.login("id_4", "123456") != OK:
		_fail("failed to send login", 2)


func _on_message_received(head_code: int, payload: PackedByteArray) -> void:
	if _finished:
		return
	match head_code:
		NetworkClient.SM_CASTMAGIC:
			var cast := Protocol.decode_sm_cast_magic(payload)
			if _aura_mode and cast.get("uid", 0) == GameState.player_uid and cast.get("magic", 0) == 13:
				_aura_received_ms = Time.get_ticks_msec()
		NetworkClient.SM_LOGINOK:
			if NetworkClient.enter_game() != OK:
				_fail("failed to enter game", 3)
		NetworkClient.SM_ONLINEOK:
			var online := Protocol.decode_sm_online_ok(payload)
			var action: Dictionary = online.get("action", {})
			GameState.set_player_online({"uid": online.get("uid", 0), "name": online.get("name", ""), "gender": online.get("gender", 0), "job": online.get("job", 0), "map_uid": online.get("mapUID", 0), "x": action.get("x", 0), "y": action.get("y", 0), "direction": action.get("direction", 0)})
			_main = load("res://scenes/game/main.tscn").instantiate() as Control
			add_child(_main)
		NetworkClient.SM_HEALTH:
			_health_received = true
			if _main != null and _stage in [Stage.WAIT_DEAD, Stage.WAIT_REVIVED]:
				# This callback was connected before Main, so apply the authoritative
				# health packet here to inspect the state before the following action.
				_main.call("_handle_health", payload)
				_main.call("_update_death_overlay")
				var overlay := _main.get_node("DeathOverlay") as ColorRect
				if _stage == Stage.WAIT_DEAD and GameState.player_hp == 0:
					if not bool(_main.call("_player_dead")) or not overlay.visible:
						_fail("HP=0 did not activate the death gate before ACTION_DIE", 17)
						return
					_saw_health_death_gate = true
				elif _stage == Stage.WAIT_REVIVED and GameState.player_hp > 0:
					if bool(_main.call("_player_dead")) or overlay.visible:
						_fail("HP recovery did not release the death gate before ACTION_STAND", 18)
						return
					_saw_health_revive_release = true
		NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR:
			_fail("server rejected login or online", 4)


func _on_timeout() -> void:
	_fail("timed out stage=%d hp=%d action=%d health=%s" % [_stage, GameState.player_hp, GameState.player_action_type, _health_received], 6)


func _fail(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	push_error("NETWORK_DEATH_REVIVE_SMOKE %s" % message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(code)
