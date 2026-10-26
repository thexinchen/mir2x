extends RefCounted

# Original helper.Set controller; separate from GUI.MFA automatic recovery.
const NAMES := ["HP", "MP", "Special", "Book"]
const DEFAULT_INTERVALS := [2500, 3500, 300, 100]
const BOOK_NAMES := [["地牢逃脱卷", "回城卷", "盟重传送石", "比奇传送石", "苍月岛传送石", "白日门传送石", "封魔谷传送石"], ["随机传送卷", "随机传送石"], ["行会回城卷"]]
const SUPPORTED_BOOK_ITEMS := ["随机传送卷"] # Current backend settlement.
const MEDICINES := [["金创药(小)", "金创药(中)", "强效金创药"], ["魔法药(小)", "魔法药(中)", "强效魔法药"], ["太阳水", "强效太阳水", "万年雪霜", "疗伤药"]]
var config_path := "user://mir3_helper.cfg"
var role := ""
var channels: Array[Dictionary] = []
var last_request := {}
var book_selection := -1
var book_dispatch_tick := 0 # Never saved or reset when loading another role.
var _channel := 0
var _last_poll := 0


func _init() -> void:
	if OS.has_environment("MIR3_PROTECTION_CONFIG"): config_path = OS.get_environment("MIR3_PROTECTION_CONFIG")
	load_role("")


func load_role(value: String, now: int = -1) -> void:
	if now < 0: now = Time.get_ticks_msec()
	role = value
	channels.clear()
	_channel = 0
	_last_poll = now
	last_request = {}
	var file := ConfigFile.new()
	if not role.is_empty(): file.load(config_path)
	book_selection = int(file.get_value(role, "RenewBookNowBookIndex", -1)) if not role.is_empty() else -1
	for index in 4:
		var key: String = "Renew" + NAMES[index]
		channels.append({"enabled": bool(file.get_value(role, key + "IsAuto", false)) if not role.is_empty() else false, "interval": maxi(0, int(file.get_value(role, key + "Time", DEFAULT_INTERVALS[index]))) if not role.is_empty() else DEFAULT_INTERVALS[index], "threshold": maxi(0, int(file.get_value(role, key + "Percent", 10))) if not role.is_empty() else 10, "last_tick": now})


func save() -> Error:
	if role.is_empty(): return OK
	var file := ConfigFile.new()
	var error := file.load(config_path)
	if error not in [OK, ERR_FILE_NOT_FOUND]: return error
	for index in 4:
		var key: String = "Renew" + NAMES[index]
		file.set_value(role, key + "IsAuto", channels[index].enabled)
		file.set_value(role, key + "Time", channels[index].interval)
		file.set_value(role, key + "Percent", channels[index].threshold)
	file.set_value(role, "RenewBookNowBookIndex", book_selection)
	return file.save(config_path)


func poll(now: int, hp: int, mp: int, inventory: Array, belt: Array, resources: RefCounted, sender := Callable(), pending := Callable()) -> Dictionary:
	if ((now - _last_poll) & 0xFFFFFFFF) < 50: return {}
	_last_poll = now
	var channel := _channel
	var attempt := _attempt(channel, now, hp, mp, inventory, belt, resources, pending)
	var selected: Dictionary = attempt.selected
	_dispatch(selected, sender)
	_channel = (_channel + 1) % 4
	# 6C4A40 only loops immediately when the preceding attempt did not stop
	# and the next channel is Book. Dispatch first so Book sees live pending.
	if not attempt.stop and _channel == 3:
		attempt = _attempt(3, now, hp, mp, inventory, belt, resources, pending)
		_dispatch(attempt.selected, sender)
		if selected.is_empty(): selected = attempt.selected
		_channel = 0
	return selected


func _dispatch(selected: Dictionary, sender: Callable) -> void:
	if selected.is_empty() or not sender.is_valid(): return
	var result: Dictionary = sender.call(selected)
	if selected.channel == 3 and int(result.error) == OK:
		book_dispatch_tick = int(result.sent_ms)


func _attempt(channel: int, now: int, hp: int, mp: int, inventory: Array, belt: Array, resources: RefCounted, pending: Callable) -> Dictionary:
	var settings: Dictionary = channels[channel]
	if not settings.enabled or settings.interval == 0 or ((now - int(settings.last_tick)) & 0xFFFFFFFF) < int(settings.interval) or (mp if channel == 1 else hp) >= int(settings.threshold):
		return {"selected": {}, "stop": false}
	if channel == 3 and book_selection == -1: return {"selected": {}, "stop": false}
	settings.last_tick = now
	if channel == 3:
		if book_dispatch_tick != 0 and ((now - book_dispatch_tick) & 0xFFFFFFFF) < 20000:
			return {"selected": {}, "stop": false}
		# A permitted Book attempt reports handled even when every name fails
		# or the shared pending object blocks dispatch. It has no belt fallback.
		if pending.is_valid() and bool(pending.call()): return {"selected": {}, "stop": true}
		return {"selected": _find_book(inventory, resources), "stop": true}
	for grade in MEDICINES[channel].size():
		var found := _find(MEDICINES[channel][grade], inventory, belt, resources)
		if not found.is_empty():
			found.channel = channel
			# Direct solar branch does not set the helper's stop flag.
			return {"selected": found, "stop": channel != 2 or grade != 0}
	return {"selected": {}, "stop": false}


func _find_book(inventory: Array, resources: RefCounted) -> Dictionary:
	if book_selection < 0 or book_selection >= BOOK_NAMES.size(): return {}
	for name in BOOK_NAMES[book_selection]:
		if name not in SUPPORTED_BOOK_ITEMS: continue
		for index in range(inventory.size() - 1, -1, -1):
			if not inventory[index] is Dictionary: continue
			var item: Dictionary = inventory[index]
			if int(item.get("count", 0)) > 0 and resources.item_name(int(item.get("itemID", 0))) == name:
				return {"item": item.duplicate(true), "belt_slot": -1, "channel": 3}
	return {}


func _find(name: String, inventory: Array, belt: Array, resources: RefCounted) -> Dictionary:
	for location in 2:
		var items: Array = inventory if location == 0 else belt
		for index in items.size():
			if not items[index] is Dictionary or items[index].is_empty(): continue
			var item: Dictionary = items[index]
			if int(item.get("count", 0)) <= 0: continue
			var item_id := int(item.get("itemID", 0))
			var current: String = resources.item_name(item_id).replace("（", "(").replace("）", ")")
			var effect: Dictionary = resources.item_potion_effect(item_id)
			if current.nocasecmp_to(name) == 0 and not effect.is_empty() and (int(effect.flags) & 6) == 0:
				return {"item": item.duplicate(true), "belt_slot": index if location == 1 else -1}
	return {}
