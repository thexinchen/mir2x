extends Node

const Protection = preload("res://scripts/game/mir3_protection.gd")
class Resources extends RefCounted:
	func item_name(id: int) -> String:
		return {6: "金创药（小）", 7: "金创药(中)", 10: "魔法药(小)", 14: "太阳水", 15: "强效太阳水", 99: "强效金创药", 151: "随机传送卷", 152: "随机传送卷 ", 153: "回城卷", 154: "随机传送石"}.get(id, "")
	func item_potion_effect(id: int) -> Dictionary:
		if id >= 150: return {}
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
	helper.channels[3].enabled = true
	helper.book_selection = 1
	helper.book_dispatch_tick = 321
	check(helper.save() == OK, "save per role")
	var restored := Protection.new()
	restored.config_path = helper.config_path
	restored.load_role("server/one", 800)
	check(restored.channels[0].enabled and restored.channels[0].threshold == 123 and restored.channels[0].last_tick == 800, "restores settings but starts fresh timer")
	check(restored.channels[3].enabled and restored.book_selection == 1 and restored.book_dispatch_tick == 0, "book settings persist but process tick is not stored")
	helper.load_role("server/two", 850)
	check(helper.book_dispatch_tick == 321, "loading another role does not clear global Book interval")
	restored.load_role("server/two", 900)
	check(not restored.channels[0].enabled, "different role stays disabled")
	DirAccess.remove_absolute(helper.config_path)
	book_cases()
	if failures.is_empty(): print("MIR3 PROTECTION PASS: defaults, timing, raw thresholds, grade/location order, special rotation, unsupported effects, wrap and per-role persistence")
	get_tree().quit(0 if failures.is_empty() else 1)

func item(id: int, seq := 1) -> Dictionary:
	return {"itemID": id, "seqID": seq, "count": 1}

func book_helper() -> RefCounted:
	var helper := Protection.new()
	helper.load_role("", 0)
	helper.channels[3].enabled = true
	helper.book_selection = 1
	return helper

func book_cases() -> void:
	var helper := book_helper()
	check(helper.channels[3].interval == 100 and helper.channels[3].threshold == 10, "original Book defaults")
	var requests: Array = []
	var sender := func(choice):
		requests.append(choice)
		return {"error": OK, "sent_ms": 155}
	helper.poll(50, 1, 100, [], [], resources, sender)
	helper.poll(100, 1, 100, [], [], resources, sender)
	var selected: Dictionary = helper.poll(150, 1, 100, [item(151, 1), item(152, 9), item(151, 7)], [], resources, sender)
	check(selected.get("channel", -1) == 3 and selected.get("item", {}).get("seqID", 0) == 7 and requests.size() == 1, "Book follows inactive Special immediately and chooses last exact inventory match")
	check(helper.channels[3].last_tick == 150 and helper.book_dispatch_tick == 155 and helper._channel == 0, "attempt tick differs from actual accepted dispatch tick")
	for elapsed in [19999, 20000]:
		helper = book_helper()
		helper._channel = 3
		helper.book_dispatch_tick = 100
		selected = helper.poll(100 + elapsed, 1, 100, [item(151)], [], resources)
		check(selected.is_empty() == (elapsed < 20000), "Book twenty-second equality boundary")
		check(helper.channels[3].last_tick == 100 + elapsed, "global twenty-second rejection still advances channel attempt tick")
	helper = book_helper()
	helper._channel = 3
	check(helper.poll(100, 10, 0, [item(151)], [], resources).is_empty() and helper.channels[3].last_tick == 0, "Book checks raw HP strictly below threshold, not MP")
	helper = book_helper()
	helper._channel = 3
	check(helper.poll(100, 1, 1, [], [item(151)], resources).is_empty(), "Book never searches belt")
	helper = book_helper()
	helper._channel = 3
	check(helper.poll(100, 1, 1, [item(151)], [], resources, Callable(), func(): return true).is_empty() and helper.channels[3].last_tick == 100, "live pending object prevents Book while advancing attempt tick")
	for selection in [-1, -2, 0, 2, 99]:
		helper = book_helper()
		helper._channel = 3
		helper.book_selection = selection
		check(helper.poll(100, 1, 1, [item(151), item(153), item(154)], [], resources).is_empty(), "unsupported/invalid Book selection never invents settlement")
		check(helper.channels[3].last_tick == (0 if selection == -1 else 100), "minus1 is excluded before Book attempt; other unknown selections are handled")
	helper = book_helper()
	helper._channel = 3
	helper.book_dispatch_tick = 0xFFFFFFF0
	check(not helper.poll(19984, 1, 1, [item(151)], [], resources).is_empty(), "Book global interval handles32-bit wrap")
	for error in [OK, ERR_UNCONFIGURED]:
		helper = book_helper()
		helper.channels[2].enabled = true
		helper._channel = 2
		requests.clear()
		var state := {"pending": false}
		var send_solar := func(choice):
			requests.append(choice)
			if choice.channel == 2:
				state.pending = error == OK
				return {"error": error, "sent_ms": 1000}
			return {"error": OK, "sent_ms": 1005}
		helper.poll(1000, 1, 1, [item(14), item(151)], [], resources, send_solar, func(): return state.pending)
		check(requests.size() == (1 if error == OK else 2) and helper.channels[3].last_tick == 1000, "direct solar dispatch precedes same-callback Book pending check")
		check(helper.book_dispatch_tick == (0 if error == OK else 1005), "only locally dispatched Book starts global interval")
	helper = book_helper()
	helper.channels[2].enabled = true
	helper._channel = 2
	helper.poll(1000, 1, 1, [item(15), item(151)], [], resources)
	check(helper._channel == 3 and helper.channels[3].last_tick == 0, "higher Special grade leaves Book for next timer callback")
	helper._channel = 3
	helper.poll(1050, 1, 1, [item(151)], [], resources, func(_choice): return {"error": ERR_UNCONFIGURED, "sent_ms": 999})
	check(helper.book_dispatch_tick == 0, "failed local Book send does not start global interval")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
