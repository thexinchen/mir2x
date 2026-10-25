extends Node

class TargetMain:
	extends "res://scripts/game/main.gd"
	var requested_uid := -1
	func _send_spell_action(_action_type: int, _magic_id: int, _grid: Vector2i, uid: int) -> bool:
		requested_uid = uid
		return true

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 1 << 35
	GameState.player_map_id = 1
	GameState.player_x = 10
	GameState.player_y = 10
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(TargetMain)
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var revive: int = resources.magic_id("回生术")
	var fireball: int = resources.magic_id("火球术")
	var renderer: Control = main.get_node("WorldRenderer")
	var mouse := get_viewport().get_mouse_position()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var body := {"texture": ImageTexture.create_from_image(image), "offset": Vector2i.ZERO}
	var origin := Vector2i(mouse) - Vector2i(8, 8)
	GameState.creatures.clear()
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 11, "y": 10, "action_type": 13})
	renderer.call("_record_actor_target", 606, 2, 10, 13, body, origin.x, origin.y)
	_expect(renderer.focus_uid_at_screen(mouse) == 0, "ordinary focus ignores corpse hitbox")
	_expect(renderer.focus_uid_at_screen(mouse, false, true) == 606, "explicit corpse targeting includes rendered corpse")
	GameState.magic_cast_times.clear()
	GameState.learned_magic = [{"magicID": revive}]
	GameState.magic_keys = {revive: 60}
	var key := InputEventKey.new()
	key.keycode = KEY_F12
	key.pressed = true
	_expect(main.call("_try_magic_key", key) and main.get("requested_uid") == 606, "F12 resurrection dispatch keeps current corpse UID")
	main.call("_cast_magic", fireball, Vector2i(11, 10))
	_expect(main.get("requested_uid") == 0, "ordinary spell cannot reuse corpse focus")
	main.call("_cast_magic", revive, Vector2i(11, 10))
	renderer.get("_corpse_target_rects").clear()
	main.call("_cast_magic", revive, Vector2i(12, 10))
	_expect(main.get("requested_uid") == 0 and main.get("_magic_focus_uid") == 0, "dead history is discarded after mouse leaves corpse")
	renderer.call("_record_actor_target", 606, 2, 10, 13, body, origin.x, origin.y)
	GameState.remove_creature(606)
	main.call("_cast_magic", revive, Vector2i(11, 10))
	_expect(main.get("requested_uid") == 0, "stale corpse rectangle cannot select an actor absent from current scene")
	GameState.update_creature(707, {"uid": 707, "type": 2, "x": 12, "y": 10, "action_type": 2})
	renderer.call("_record_actor_target", 707, 2, 11, 2, body, origin.x, origin.y)
	main.call("_cast_magic", fireball, Vector2i(12, 10))
	_expect(main.get("requested_uid") == 707, "live actor remains targetable with corpse table present")
	renderer.get("_actor_target_rects").clear()
	main.call("_cast_magic", fireball, Vector2i(13, 10))
	_expect(main.get("requested_uid") == 707, "live history behavior is preserved")
	# A hovered new actor must not replace the spell history when toggling swords.
	GameState.update_creature(808, {"uid": 808, "type": 2, "x": 13, "y": 10, "action_type": 2})
	renderer.call("_record_actor_target", 808, 2, 11, 2, body, origin.x, origin.y)
	_expect(renderer.focus_uid_at_screen(mouse) == 808, "toggle fixture hovers a different live actor")
	for name in ["刺杀剑术", "烈火剑法", "翔空剑法", "莲月剑法", "半月弯刀", "十方斩"]:
		var sword: int = resources.magic_id(name)
		_expect(sword > 0, "sword toggle metadata exists: " + name)
		GameState.learned_magic = [{"magicID": sword}]
		GameState.magic_keys = {sword: 49}
		GameState.magic_cast_times.clear()
		main.set("_magic_focus_uid", 707)
		key.keycode = KEY_F1
		main.set("requested_uid", -1)
		_expect(main.call("_try_magic_key", key) and bool(main.get("_swing_magic").get(sword, false)), "F1 enables sword: " + name)
		_expect(main.get("_magic_focus_uid") == 707 and main.get("requested_uid") == -1, "sword toggle preserves spell history without a spell request: " + name)
		main.call("_try_magic_key", key)
		_expect(not bool(main.get("_swing_magic").get(sword, false)) and main.get("_magic_focus_uid") == 707, "disabling sword preserves spell history: " + name)
	# Cooldown-rejected actual spells still refresh focus, as before.
	GameState.magic_cast_times[fireball] = Time.get_ticks_msec()
	main.call("_cast_magic", fireball, Vector2i(13, 10))
	_expect(main.get("_magic_focus_uid") == 808, "cooldown-rejected spell still refreshes hovered target")
	if failures.is_empty(): print("MIR3 RESURRECTION TARGET PASS: separate corpse hitboxes, F12 corpse UID, ordinary-spell exclusion, dead-history clearing, stale-scene rejection, live fallback and sword-toggle focus isolation")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
