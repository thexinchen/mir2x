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
	GameState.creatures.clear()
	GameState.runtime_config.clear()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(CaptureMain)
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var fireball: int = resources.magic_id("火球术")
	var renderer: Node = main.get_node("WorldRenderer")
	var rect := Rect2(get_viewport().get_mouse_position() - Vector2(10, 10), Vector2(20, 20))
	for uid in [606, 707]:
		GameState.update_creature(uid, {"uid": uid, "type": 2, "x": 12, "y": 10, "action_type": 2})
	renderer.set("_actor_target_rects", {606: {"rect": rect, "map_y": 10}})
	if not main.call("_cast_magic", fireball, Vector2i(12, 10)) or main.get("sent").get("uid") != 606:
		_fail("initial known-positive cast did not resolve its hovered actor")
		return
	# Establish two distinct pointer states, without inventing the unknown
	# original server target mode of another named spell.
	main.set("_magic_focus_uid", 707)
	renderer.set("_actor_target_rects", {})
	GameState.remove_creature(707)
	if not main.call("_cast_magic", fireball, Vector2i(15, 12)) or main.get("sent").get("uid") != 606:
		_fail("removing a different current target lost the independently remembered actor")
		return
	if main.get("_magic_focus_uid") != 606 or main.get("_magic_history_uid") != 606:
		_fail("history fallback did not update current selection separately")
		return
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 12, "y": 10, "action_type": 13})
	main.set("_magic_focus_uid", 0)
	if not main.call("_cast_magic", fireball, Vector2i(15, 12)) or main.get("sent").get("uid") != 0:
		_fail("history fallback reused a corpse")
		return
	GameState.remove_creature(606)
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 12, "y": 10, "action_type": 2})
	if main.get("_magic_history_uid") != 0 or not main.call("_cast_magic", fireball, Vector2i(15, 12)) or main.get("sent").get("uid") != 0:
		_fail("removed actor history survived same-frame UID reentry")
		return
	GameState.update_creature(707, {"uid": 707, "type": 2, "x": 13, "y": 10, "action_type": 2})
	GameState.runtime_config[49] = PackedByteArray([1, 1])
	main.set("_locked_magic_target_uid", 606)
	renderer.set("_actor_target_rects", {707: {"rect": rect, "map_y": 10}})
	GameState.magic_cast_times[fireball] = Time.get_ticks_msec()
	main.set("sent", {})
	if main.call("_cast_magic", fireball, Vector2i(15, 12)) or not main.get("sent").is_empty() \
			or main.get("_magic_focus_uid") != 606 or main.get("_magic_history_uid") != 606:
		_fail("cooldown rejection remembered hover instead of the resolved lock")
		return
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reverse/mir3-skill-identity.json"))
	var policy: Dictionary = main.Mir3TargetHistoryScript.KNOWN_POSITIVE
	for row in evidence.skills:
		if policy.has(row.current_name) != bool(row.history_known_positive) \
				or (policy.has(row.current_name) and policy[row.current_name] != row.original_resource_id):
			_fail("known-positive history policy disagrees with extracted identity: " + row.current_name)
			return
	print("MIR3 TARGET HISTORY PASS: separate current/history, independent removal, live-only fallback, same-frame UID reentry, resolved lock before cooldown, evidence-matched positive policy")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("TARGET HISTORY: " + message)
	get_tree().quit(1)
