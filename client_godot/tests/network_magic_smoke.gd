extends Node

const Protocol = preload("res://scripts/network/protocol.gd")

const MAGIC_ID := 17
const MAGIC_KEY := 120

enum Stage { WAIT_READY, WAIT_BOUND, WAIT_CAST }

var _main: Control
var _stage := Stage.WAIT_READY
var _learned_received := false
var _config_received := false
var _health_received := false
var _local_action_started := false
var _buff_list_received := false
var _finished := false
var _capture_started := false
var _cast_started_msec := 0
var _initial_hp := 0
var _expected_buff_id := 0
var _fixture_started := false


func _ready() -> void:
	NetworkClient.connection_changed.connect(_on_connection_changed)
	NetworkClient.message_received.connect(_on_message_received)
	NetworkClient.connect_to_server()
	get_tree().create_timer(35.0).timeout.connect(_on_timeout)


func _process(_delta: float) -> void:
	if _finished or _main == null:
		return
	match _stage:
		Stage.WAIT_READY:
			if _main.get_node("MapLoadingOverlay").visible:
				return
			if not _config_received or not _health_received:
				return
			if GameState.player_hp <= 0:
				return
			if not _has_learned_magic() or GameState.player_hp >= GameState.player_hp_max:
				if not _fixture_started:
					_fixture_started = true
					_prepare_healing_fixture()
				return
			if not _learned_received:
				return
			_initial_hp = GameState.player_hp
			if _initial_hp >= GameState.player_hp_max:
				_fail("healing fixture reached full health before casting: %d/%d" % [_initial_hp, GameState.player_hp_max], 7)
				return
			var panel := _main.get_node("SkillPanel") as Control
			var resources: RefCounted = _main.get("_resources")
			_expected_buff_id = _buff_id_by_name(resources, "治愈术")
			if _expected_buff_id == 0:
				_fail("healing buff metadata is unavailable", 12)
				return
			var layout: PackedInt32Array = resources.call("skill_layout", MAGIC_ID)
			if layout.size() < 5:
				_fail("healing skill layout is unavailable", 8)
				return
			panel.show()
			panel.call("_select_tab", layout[1])
			var button := _magic_button(panel)
			if button == null or not button.visible:
				return
			button.mouse_entered.emit()
			if OS.has_environment("MIR2X_NETWORK_MAGIC_EXPECT_PERSISTED"):
				if int(GameState.magic_keys.get(MAGIC_ID, 0)) != MAGIC_KEY:
					_fail("server-generated player config did not reload healing=X: %s" % GameState.magic_keys, 9)
					return
			else:
				var bind_event := InputEventKey.new()
				bind_event.keycode = KEY_X
				bind_event.unicode = MAGIC_KEY
				bind_event.pressed = true
				panel.call("_unhandled_key_input", bind_event)
				if int(GameState.magic_keys.get(MAGIC_ID, 0)) != MAGIC_KEY:
					_fail("visible skill panel did not bind healing=X: %s" % GameState.magic_keys, 10)
					return
			_stage = Stage.WAIT_BOUND
		Stage.WAIT_BOUND:
			if OS.has_environment("MIR2X_NETWORK_MAGIC_SCREENSHOT") and not _capture_started:
				_capture_started = true
				await RenderingServer.frame_post_draw
				var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_NETWORK_MAGIC_SCREENSHOT"))
				if error != OK:
					_fail("failed to save learned-skill screenshot: %s" % error, 11)
					return
			var panel := _main.get_node("SkillPanel") as Control
			panel.hide()
			_local_action_started = false
			_buff_list_received = false
			_health_received = false
			var cast_event := InputEventKey.new()
			cast_event.keycode = KEY_X
			cast_event.unicode = MAGIC_KEY
			cast_event.pressed = true
			_main.call("_unhandled_input", cast_event)
			_local_action_started = GameState.player_action_type == 9 and GameState.magic_cast_times.has(MAGIC_ID)
			_cast_started_msec = Time.get_ticks_msec()
			_stage = Stage.WAIT_CAST
		Stage.WAIT_CAST:
			if not _local_action_started or not _buff_list_received or not _health_received or GameState.player_hp <= _initial_hp:
				return
			if not GameState.buff_list.has(_expected_buff_id):
				_fail("authoritative healing buff is missing: expected=%d actual=%s" % [_expected_buff_id, GameState.buff_list], 13)
				return
			var hud := _main.get_node("SkillBuffHUD") as Control
			if int(hud.call("buff_icon_count")) < 1:
				_fail("authoritative healing buff has no drawable HUD icon: id=%d" % _expected_buff_id, 14)
				return
			if OS.has_environment("MIR2X_NETWORK_MAGIC_RESULT_SCREENSHOT"):
				await RenderingServer.frame_post_draw
				var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_NETWORK_MAGIC_RESULT_SCREENSHOT"))
				if error != OK:
					_fail("failed to save authoritative-buff screenshot: %s" % error, 15)
					return
			print("NETWORK MAGIC PASS: healing=%d buff=%d key=X hp=%d->%d local-action+authoritative-buff/health+HUD" % [MAGIC_ID, _expected_buff_id, _initial_hp, GameState.player_hp])
			_finished = true
			NetworkClient.disconnect_from_server()
			get_tree().quit()


func _has_learned_magic() -> bool:
	for value in GameState.learned_magic:
		if value is Dictionary and int(value.get("magicID", 0)) == MAGIC_ID:
			return true
	return false


func _prepare_healing_fixture() -> void:
	if (GameState.player_job & 2) == 0:
		_fail("healing fixture requires a Taoist test character", 16)
		return
	var target_level := maxi(7, GameState.player_level)
	if GameState.player_hp >= GameState.player_hp_max:
		target_level = maxi(target_level, GameState.player_level + 1)
	# SYS_LEVEL reaches N at SYS_SUMEXP(N-1). Raising max HP without
	# filling current HP produces a damaged fixture through normal messages.
	var previous := target_level - 1
	var required_exp := 100 * previous * previous * previous + 100 * previous * previous + 100 * previous + 1000
	if GameState.player_exp < required_exp:
		NetworkClient.send_request_add_exp(required_exp - GameState.player_exp)
		for _i in range(40):
			await get_tree().create_timer(0.05).timeout
			if GameState.player_level >= target_level: break
	if GameState.player_level < target_level or GameState.player_hp >= GameState.player_hp_max:
		_fail("could not prepare healing level and missing-HP fixture", 17)
		return
	if _has_learned_magic(): return
	var book := _healing_book()
	if book.is_empty():
		NetworkClient.send_make_item(230)
		for _i in range(40):
			await get_tree().create_timer(0.05).timeout
			book = _healing_book()
			if not book.is_empty(): break
	if book.is_empty():
		_fail("could not create healing skill book fixture", 18)
		return
	NetworkClient.send_consume_item(230, int(book.seqID), 1)
	for _i in range(40):
		await get_tree().create_timer(0.05).timeout
		if _has_learned_magic(): return
	_fail("server did not confirm learning healing from its book", 19)


func _healing_book() -> Dictionary:
	for item in GameState.inventory:
		if int(item.get("itemID", 0)) == 230: return item
	return {}


func _buff_id_by_name(resources: RefCounted, buff_name: String) -> int:
	var names: Dictionary = resources.get("buff_names")
	for id_value in names:
		if str(names[id_value]) == buff_name:
			return int(id_value)
	return 0


func _magic_button(panel: Control) -> TextureButton:
	for child_value in panel.get_node("PageViewport/LearnedSkills").get_children():
		var button := child_value as TextureButton
		if button != null and int(button.get_meta("magic_id", 0)) == MAGIC_ID:
			return button
	return null


func _on_connection_changed(connected: bool, _message: String) -> void:
	var account := OS.get_environment("MIR2X_NETWORK_MAGIC_ACCOUNT")
	if account.is_empty():
		account = "id_4"
	if connected and NetworkClient.login(account, "123456") != OK:
		_fail("failed to send login", 2)


func _on_message_received(head_code: int, payload: PackedByteArray) -> void:
	if _finished:
		return
	match head_code:
		NetworkClient.SM_LOGINOK:
			if NetworkClient.enter_game() != OK:
				_fail("failed to enter game", 3)
		NetworkClient.SM_ONLINEOK:
			var online := Protocol.decode_sm_online_ok(payload)
			var action: Dictionary = online.get("action", {})
			GameState.set_player_online({"uid": online.get("uid", 0), "name": online.get("name", ""), "gender": online.get("gender", 0), "job": online.get("job", 0), "map_uid": online.get("mapUID", 0), "x": action.get("x", 0), "y": action.get("y", 0), "direction": action.get("direction", 0)})
			_main = load("res://scenes/game/main.tscn").instantiate() as Control
			add_child(_main)
		NetworkClient.SM_LEARNEDMAGICLIST:
			_learned_received = true
		NetworkClient.SM_PLAYERCONFIG:
			_config_received = true
		NetworkClient.SM_HEALTH:
			_health_received = true
		NetworkClient.SM_BUFFIDLIST:
			if _stage == Stage.WAIT_CAST:
				_buff_list_received = true
		NetworkClient.SM_LOGINERROR, NetworkClient.SM_ONLINEERROR:
			_fail("server rejected login or online", 4)


func _on_timeout() -> void:
	_fail("timed out stage=%d learned=%s keys=%s hp=%d local_action=%s buff_message=%s buffs=%s expected_buff=%d health=%s cast_ms=%d" % [_stage, GameState.learned_magic, GameState.magic_keys, GameState.player_hp, _local_action_started, _buff_list_received, GameState.buff_list, _expected_buff_id, _health_received, _cast_started_msec], 6)


func _fail(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	push_error("NETWORK_MAGIC_SMOKE %s" % message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(code)
