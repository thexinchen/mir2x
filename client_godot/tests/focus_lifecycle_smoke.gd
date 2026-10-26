extends Node

var main: Control
var renderer: Control
var body: Dictionary
const POINT := Vector2(110, 110)


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_action_type = 2
	GameState.creatures.clear()
	main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	renderer = main.get_node("WorldRenderer")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	body = {"texture": ImageTexture.create_from_image(image), "offset": Vector2i.ZERO}
	_actor(606, 2)
	_record(606, 2)
	renderer.set("_mouse_focus_uid", 606)
	renderer.call("set_focus_channels", 606, 707, 808)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 606, "initial rendered actor is selectable"): return
	GameState.remove_creature(606)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 0, "removed actor must not be reselected from the previous frame"): return
	if not _expect(renderer.get("_magic_focus_uid") == 0 and renderer.get("_follow_focus_uid") == 707 \
			and renderer.get("_attack_focus_uid") == 808, "renderer clears only matching focus snapshots before another process frame"): return
	_actor(606, 2)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 0, "same-frame UID reentry must wait for a fresh rendered hitbox"): return
	_record(606, 2)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 606, "new rendered actor is selectable again"): return
	_actor(606, 13)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 0 and renderer.focus_uid_at_screen(POINT, false, true) == 606,
			"normal selection rejects new death while the explicit corpse exception remains available"): return
	renderer.set("_actor_target_rects", {})
	_record(606, 13)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 0 and renderer.focus_uid_at_screen(POINT, false, true) == 606,
			"fresh corpse hitbox requires explicit corpse selection"): return
	_actor(606, 2)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 0 and renderer.focus_uid_at_screen(POINT, false, true) == 606,
			"corpse-inclusive lookup still accepts the scene member before the next draw"): return
	renderer.set("_corpse_target_rects", {})
	_record(606, 2)
	_actor(707, 2)
	_record(707, 2, 11)
	renderer.set("_mouse_focus_uid", 606)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 606, "valid retained actor keeps original overlap priority"): return
	GameState.remove_creature(606)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 707, "removed retained actor cannot mask another live actor"): return
	renderer.set("_actor_target_rects", {})
	renderer.set("_mouse_focus_uid", 0)
	_record(101, 2)
	if not _expect(renderer.focus_uid_at_screen(POINT) == 0 and renderer.focus_uid_at_screen(POINT, true) == 101,
			"local-player inclusion policy is preserved"): return
	GameState.player_action_type = 13
	if not _expect(renderer.focus_uid_at_screen(POINT, true) == 0 and renderer.focus_uid_at_screen(POINT, true, true) == 101,
			"local death respects normal versus corpse-inclusive selection"): return
	print("FOCUS LIFECYCLE PASS: same-frame removal/reentry, live/dead membership validation, explicit corpse exception, overlap priority and self inclusion")
	get_tree().quit()


func _actor(uid: int, action_type: int) -> void:
	GameState.update_creature(uid, {"uid": uid, "type": 2, "action_type": action_type, "x": 12, "y": 10})


func _record(uid: int, action_type: int, map_y := 10) -> void:
	renderer.call("_record_actor_target", uid, 2, map_y, action_type, body, 100, 100)


func _expect(success: bool, reason: String) -> bool:
	if not success:
		push_error("FOCUS LIFECYCLE: " + reason)
		get_tree().quit(1)
	return success
