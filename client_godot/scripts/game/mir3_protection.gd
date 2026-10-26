extends RefCounted

# Original helper.Set controller; separate from GUI.MFA automatic recovery.
const NAMES := ["HP", "MP", "Special"]
const DEFAULT_INTERVALS := [2500, 3500, 300]
const MEDICINES := [["金创药(小)", "金创药(中)", "强效金创药"], ["魔法药(小)", "魔法药(中)", "强效魔法药"], ["太阳水", "强效太阳水", "万年雪霜", "疗伤药"]]
var config_path := "user://mir3_helper.cfg"
var role := ""
var channels: Array[Dictionary] = []
var last_request := {}
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
	for index in 3:
		var key: String = "Renew" + NAMES[index]
		channels.append({"enabled": bool(file.get_value(role, key + "IsAuto", false)) if not role.is_empty() else false, "interval": maxi(0, int(file.get_value(role, key + "Time", DEFAULT_INTERVALS[index]))) if not role.is_empty() else DEFAULT_INTERVALS[index], "threshold": maxi(0, int(file.get_value(role, key + "Percent", 10))) if not role.is_empty() else 10, "last_tick": now})


func save() -> Error:
	if role.is_empty(): return OK
	var file := ConfigFile.new()
	var error := file.load(config_path)
	if error not in [OK, ERR_FILE_NOT_FOUND]: return error
	for index in 3:
		var key: String = "Renew" + NAMES[index]
		file.set_value(role, key + "IsAuto", channels[index].enabled)
		file.set_value(role, key + "Time", channels[index].interval)
		file.set_value(role, key + "Percent", channels[index].threshold)
	return file.save(config_path)


func poll(now: int, hp: int, mp: int, inventory: Array, belt: Array, resources: RefCounted) -> Dictionary:
	if ((now - _last_poll) & 0xFFFFFFFF) < 50: return {}
	_last_poll = now
	var channel := _channel
	_channel = (_channel + 1) % 4
	if channel == 3: return {}
	var settings: Dictionary = channels[channel]
	if not settings.enabled or settings.interval == 0 or ((now - int(settings.last_tick)) & 0xFFFFFFFF) < int(settings.interval) or (mp if channel == 1 else hp) >= int(settings.threshold):
		if _channel == 3: _channel = 0 # Disabled book channel is checked in this callback.
		return {}
	settings.last_tick = now
	for grade in MEDICINES[channel].size():
		var found := _find(MEDICINES[channel][grade], inventory, belt, resources)
		if not found.is_empty():
			found.channel = channel
			# Direct solar branch does not set the helper's stop flag.
			if channel == 2 and grade == 0: _channel = 0
			return found
	if _channel == 3: _channel = 0
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
