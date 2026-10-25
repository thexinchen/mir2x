extends Node

const Shortcuts = preload("res://scripts/game/magic_shortcuts.gd")
class ShortcutMain:
	extends "res://scripts/game/main.gd"
	var cast_id := 0
	func _cast_magic(magic_id: int, _grid: Vector2i) -> bool:
		cast_id = magic_id
		return true

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	var main := load("res://scenes/game/main.tscn").instantiate() as Control
	main.set_script(ShortcutMain)
	add_child(main)
	main.set_process(false)
	var resources: RefCounted = main.get("_resources")
	var healing: int = resources.magic_id("治愈术")
	var fireball: int = resources.magic_id("火球术")
	GameState.learned_magic = [{"magicID": healing}, {"magicID": fireball}]
	GameState.magic_keys.clear()
	var panel: Control = main.get_node("SkillPanel")
	panel.show()
	main.get_node("%QuickBar").show()
	_bind(panel, resources, healing, KEY_F1, false)
	_bind(panel, resources, fireball, KEY_F1, true)
	_expect(GameState.magic_keys.get(healing) == 49 and GameState.magic_keys.get(fireball) == 65, "F1 banks bind independently while potion bar is visible")
	_expect(main.call("_try_magic_key", _key(KEY_F1, false)) and main.get("cast_id") == healing, "F1 dispatches first bank")
	_expect(main.call("_try_magic_key", _key(KEY_F1, true)) and main.get("cast_id") == fireball, "Shift-F1 dispatches second bank")
	_expect(not main.call("_try_magic_key", _key(KEY_A, false)), "Shift-F1 storage does not collide with legacy A")
	_bind(panel, resources, healing, KEY_F12, false)
	_bind(panel, resources, fireball, KEY_F12, true)
	_expect(GameState.magic_keys.get(healing) == 60 and GameState.magic_keys.get(fireball) == 76, "F12 bank endpoints match original slot codes")
	_expect(main.call("_try_magic_key", _key(KEY_F12, false)) and main.get("cast_id") == healing, "F12 dispatches first bank")
	_expect(main.call("_try_magic_key", _key(KEY_F12, true)) and main.get("cast_id") == fireball, "Shift-F12 dispatches second bank")
	var labels := 0
	for button in panel.get_node("PageViewport/LearnedSkills").get_children():
		if int(button.get_meta("magic_id", 0)) != fireball: continue
		for child in button.get_children():
			if child is Label and child.text == "S-F12":
				labels += 1
				_expect(child.get_minimum_size().x <= button.size.x, "shifted F12 label fits its skill button")
	_expect(labels == 2, "skill panel displays both shifted F12 label layers")
	_bind(panel, resources, fireball, KEY_F12, false)
	_expect(not GameState.magic_keys.has(healing) and GameState.magic_keys.get(fireball) == 60, "assigning same bank slot replaces its old owner")
	var keys := GameState.magic_keys.duplicate()
	_bind(panel, resources, fireball, KEY_F13, false)
	_expect(GameState.magic_keys == keys, "F13 does not create an unsupported slot")
	_bind(panel, resources, fireball, KEY_X, true)
	_expect(GameState.magic_keys.get(fireball) == 120 and Shortcuts.label(120) == "X", "legacy shifted X remains lowercase protocol storage")
	for index in range(12):
		_expect(Shortcuts.event_key(_key(KEY_F1 + index, false)) == 49 + index, "unshifted function slot %d" % (index + 1))
		_expect(Shortcuts.event_key(_key(KEY_F1 + index, true)) == 65 + index, "shifted function slot %d" % (index + 1))
	if failures.is_empty(): print("MIR3 MAGIC SHORTCUTS PASS: two F1-F12 banks, binding/casting, no legacy A collision, unique assignment, fitting labels, legacy X")
	get_tree().quit(0 if failures.is_empty() else 1)

func _bind(panel: Control, resources: RefCounted, magic_id: int, code: int, shift: bool) -> void:
	panel.call("_select_tab", resources.skill_layout(magic_id)[1])
	panel.call("_show_magic", magic_id)
	panel.call("_unhandled_key_input", _key(code, shift))

func _key(code: int, shift: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.shift_pressed = shift
	event.pressed = true
	return event

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
