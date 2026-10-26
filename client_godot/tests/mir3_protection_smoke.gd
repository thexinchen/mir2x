extends Node

const Protection = preload("res://scripts/game/mir3_protection.gd")
class Resources extends RefCounted:
	func item_name(id: int) -> String:
		return {6: "金创药（小）", 7: "金创药(中)", 10: "魔法药(小)", 14: "太阳水", 15: "强效太阳水", 99: "强效金创药"}.get(id, "")
	func item_potion_effect(id: int) -> Dictionary:
		return {"flags": 4 if id == 99 else 1}

var failures: Array[String] = []
var resources := Resources.new()

func _ready() -> void:
	var helper := Protection.new()
	helper.config_path = "user://mir3_protection_smoke.cfg"
	if FileAccess.file_exists(helper.config_path): DirAccess.remove_absolute(helper.config_path)
	helper.load_role("server/one", 0)
	check(helper.channels[0].interval == 2500 and helper.channels[1].interval == 3500 and helper.channels[2].interval == 300, "original intervals")
	check(helper.poll(2500, 1, 1, [item(6)], [], resources).is_empty(), "default disabled")
	helper.load_role("server/one", 0)
	helper.channels[0].enabled = true
	check(helper.poll(2499, 1, 1, [item(6)], [], resources).is_empty(), "interval not reached")
	helper._channel = 0
	check(helper.poll(2549, 10, 1, [item(6)], [], resources).is_empty(), "threshold equality does not use")
	helper._channel = 0
	check(helper.poll(2599, 9, 1, [item(7)], [item(6)], resources).get("belt_slot", -1) == 0, "lower grade belt precedes higher grade inventory")
	check(helper.channels[0].last_tick == 2599, "due attempt advances timer")
	helper._channel = 0
	check(helper.poll(5100, 1, 1, [], [], resources).is_empty() and helper.channels[0].last_tick == 5100, "missing medicine still advances due timer")
	helper._channel = 0
	check(helper.poll(5200, 1, 1, [item(6)], [], resources).is_empty(), "no immediate retry after missing medicine")
	helper.channels[0].interval = 0
	helper._channel = 0
	check(helper.poll(9999, 1, 1, [item(6)], [], resources).is_empty(), "zero interval disables")
	check(helper._find("强效金创药", [item(99)], [], resources).is_empty(), "unsupported server effect rejected")
	check(helper._find("金创药(小)", [item(6)], [item(6)], resources).belt_slot == -1, "inventory precedes same grade belt")
	helper.channels[2].enabled = true
	helper._channel = 2
	check(helper.poll(10049, 1, 1, [item(14)], [], resources).channel == 2 and helper._channel == 0, "direct solar continues past disabled book in same callback")
	helper._channel = 2
	check(helper.poll(10349, 1, 1, [item(15)], [], resources).channel == 2 and helper._channel == 3, "higher special grade stops before book")
	helper.load_role("server/one", 0xFFFFFFF0)
	helper.channels[0].enabled = true
	helper.channels[0].interval = 50
	check(not helper.poll(34, 1, 1, [item(6)], [], resources).is_empty(), "unsigned tick wrap")
	helper.channels[0].threshold = 123
	check(helper.save() == OK, "save per role")
	var restored := Protection.new()
	restored.config_path = helper.config_path
	restored.load_role("server/one", 800)
	check(restored.channels[0].enabled and restored.channels[0].threshold == 123 and restored.channels[0].last_tick == 800, "restores settings but starts fresh timer")
	restored.load_role("server/two", 900)
	check(not restored.channels[0].enabled, "different role stays disabled")
	DirAccess.remove_absolute(helper.config_path)
	if failures.is_empty(): print("MIR3 PROTECTION PASS: defaults, timing, raw thresholds, grade/location order, special rotation, unsupported effects, wrap and per-role persistence")
	get_tree().quit(0 if failures.is_empty() else 1)

func item(id: int) -> Dictionary:
	return {"itemID": id, "seqID": 1, "count": 1}

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
