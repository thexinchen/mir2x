extends Node

class CaptureMain extends "res://scripts/game/main.gd":
	var sent: Dictionary = {}
	func _send_spell_action(action_type: int, magic_id: int, aim_grid: Vector2i, aim_uid: int) -> bool:
		sent = {"action": action_type, "magic": magic_id, "grid": aim_grid, "uid": aim_uid}
		return true


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 24 << 35
	GameState.player_map_id = 24
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.runtime_config.clear()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(CaptureMain)
	add_child(main)
	main.set_process(false)
	main.get_node("MapLoadingOverlay").hide()
	var renderer: Node = main.get_node("WorldRenderer")
	var resources: RefCounted = main.get("_resources")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_QUOTELEFT
	var rect := Rect2(get_viewport().get_mouse_position() - Vector2(10, 10), Vector2(20, 20))
	for uid in [606, 707, 808]:
		GameState.update_creature(uid, {"uid": uid, "name": "target%d" % uid, "type": 2, "x": 12, "y": 10, "action_type": 13 if uid == 808 else 2})
	renderer.set("_actor_target_rects", {606: {"rect": rect, "map_y": 10}})
	main.call("_unhandled_input", key)
	if main.get("_locked_magic_target_uid") != 0:
		_fail("factory default enabled target locking")
		return
	var panel: Control = load("res://scenes/game/panels/runtime_config.tscn").instantiate()
	add_child(panel)
	panel.call("_select_main_page", 3)
	var check := panel.get_node("SystemPage/Config49") as Button
	if check.button_pressed:
		_fail("panel default differs from disabled runtime default")
		return
	check.button_pressed = true
	main.call("_unhandled_input", key)
	if main.get("_locked_magic_target_uid") != 606 or main.get("_magic_focus_uid") != 0:
		_fail("keyboard did not create an independent lock through actual panel setting")
		return
	main.call("_process", 0.0)
	if not str(main.get_node("Location").text).contains("target606"):
		_fail("valid target name absent from status text")
		return
	renderer.set("_actor_target_rects", {})
	renderer.set("_corpse_target_rects", {808: {"rect": rect, "map_y": 10}})
	main.call("_unhandled_input", key)
	if main.get("_locked_magic_target_uid") != 606:
		_fail("different corpse replaced the live lock")
		return
	renderer.set("_corpse_target_rects", {})
	renderer.set("_actor_target_rects", {707: {"rect": rect, "map_y": 10}})
	for name in ["火球术", "火墙", "抗拒火环"]:
		main.set("_last_magic_request_ms", -10000)
		GameState.magic_cast_times.clear()
		var mid: int = resources.magic_id(name)
		if not main.call("_cast_magic", mid, Vector2i(15, 12)) or main.get("sent").get("uid") != 606:
			_fail("eligible spell ignored lock: " + name)
			return
		if main.get("_magic_focus_uid") != 707:
			_fail("explicit lock replaced independent mouse/history focus")
			return
	main.set("_last_magic_request_ms", -10000)
	GameState.magic_cast_times.clear()
	if not main.call("_cast_magic", resources.magic_id("魔法盾"), Vector2i(15, 12)) or main.get("sent").get("uid") != GameState.player_uid:
		_fail("ineligible self spell was redirected to lock")
		return
	main.set("sent", {})
	main.set("_last_magic_request_ms", -10000)
	if main.call("_cast_magic", resources.magic_id("野蛮冲撞"), Vector2i(15, 12)) or not main.get("sent").is_empty():
		_fail("lock permission accidentally implemented an unsupported command as ordinary spell")
		return
	# Every resource skill must agree with independently extracted permission.
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reverse/mir3-skill-identity.json"))
	var policy: Dictionary = main.Mir3TargetLockScript.ALLOWED
	for row in evidence.skills:
		if policy.has(row.current_name) != bool(row.explicit_lock_allowed):
			_fail("runtime permission disagrees with original evidence: " + row.current_name)
			return
	main.call("_unhandled_input", key)
	if main.get("_locked_magic_target_uid") != 707:
		_fail("different live target did not replace lock")
		return
	main.call("_unhandled_input", key)
	if main.get("_locked_magic_target_uid") != 0:
		_fail("same target did not clear lock")
		return
	main.set("_locked_magic_target_uid", 606)
	renderer.set("_actor_target_rects", {})
	main.call("_unhandled_input", key)
	if main.get("_locked_magic_target_uid") != 0:
		_fail("empty hover did not clear lock")
		return
	main.set("_locked_magic_target_uid", 606)
	check.button_pressed = false
	if main.call("_valid_locked_magic_target") != 0:
		_fail("disabled setting still resolved locked target")
		return
	check.button_pressed = true
	GameState.remove_creature(606)
	if main.get("_locked_magic_target_uid") != 0:
		_fail("actor removal retained lock")
		return
	main.set("_locked_magic_target_uid", 707)
	main.call("_switch_player_map", 1 << 35, {"x": 10, "y": 10})
	if main.get("_locked_magic_target_uid") != 0:
		_fail("map switch retained lock")
		return
	GameState.runtime_config.clear()
	print("MIR3 TARGET LOCK PASS: default/panel/key, corpse/live/same/empty hover, independent focus, spell routing, evidence permissions, status and lifecycle")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("TARGET LOCK: " + message)
	get_tree().quit(1)


