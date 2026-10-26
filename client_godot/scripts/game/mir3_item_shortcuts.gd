extends RefCounted

const SLOT_COUNT := 10
var bindings: Array[Dictionary] = []


func _init() -> void:
	for slot in SLOT_COUNT: bindings.append({})


static func key_slot(key: int) -> int:
	if key >= KEY_1 and key <= KEY_9: return key - KEY_1
	return 9 if key == KEY_0 else -1


func bind_item(slot: int, item: Dictionary, grouped: bool) -> bool:
	if slot < 0 or slot >= SLOT_COUNT or int(item.get("itemID", 0)) <= 0 or int(item.get("count", 0)) <= 0:
		return false
	bindings[slot] = {"item": item.duplicate(true), "grouped": grouped}
	return true


func clear(slot: int) -> void:
	if slot >= 0 and slot < SLOT_COUNT: bindings[slot] = {}


func clear_all() -> void:
	for slot in SLOT_COUNT: clear(slot)


func begin_drag(slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT or bindings[slot].is_empty(): return {}
	var cursor := bindings[slot].duplicate()
	cursor.source_slot = slot
	return cursor


func place_drag(slot: int, cursor: Dictionary) -> Dictionary:
	var source := int(cursor.get("source_slot", -1))
	if slot < 0 or slot >= SLOT_COUNT or source < 0 or source >= SLOT_COUNT: return cursor
	if slot == source: return {}
	var incoming := cursor.duplicate()
	incoming.erase("source_slot")
	var displaced := bindings[slot].duplicate()
	bindings[slot] = incoming
	if displaced.is_empty():
		clear(source)
		return {}
	bindings[source] = displaced
	var next_cursor := displaced.duplicate()
	next_cursor.source_slot = source
	return next_cursor


func cancel_drag(cursor: Dictionary) -> void:
	clear(int(cursor.get("source_slot", -1)))


func resolve_use(slot: int, inventory: Array, held: Dictionary = {}, pending: Dictionary = {}, cursor: Dictionary = {}) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT: return {}
	var current := resolve(slot, inventory, held, pending)
	if cursor.is_empty() or int(cursor.get("source_slot", -1)) != slot: return current
	var saved: Dictionary = cursor.get("item", {})
	# The original source key selects the held proxy before the slot reference.
	# A detached proxy must still resolve to an actually owned instance.
	var candidates := inventory.duplicate()
	if not held.is_empty(): candidates.append(held)
	for item: Dictionary in candidates:
		if item.get("itemID", 0) == saved.get("itemID", 0) and item.get("seqID", 0) == saved.get("seqID", 0) and int(item.get("count", 0)) > 0:
			return saved.duplicate(true)
	return {}


func resolve(slot: int, inventory: Array, held: Dictionary = {}, pending: Dictionary = {}) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT or bindings[slot].is_empty(): return {}
	var binding: Dictionary = bindings[slot]
	var saved: Dictionary = binding.item
	var candidates := inventory.duplicate()
	if not held.is_empty():
		var already_present := false
		for item: Dictionary in candidates:
			if item.get("itemID", 0) == held.get("itemID", 0) and item.get("seqID", 0) == held.get("seqID", 0): already_present = true
		if not already_present: candidates.append(held)
	var found: Dictionary = {}
	var count := 0
	for item: Dictionary in candidates:
		if item.get("itemID", 0) != saved.get("itemID", 0) or int(item.get("count", 0)) <= 0: continue
		if found.is_empty(): found = item.duplicate(true)
		count += int(item.count)
		if not binding.grouped: break
	if not found.is_empty():
		found.count = count
		# A held shortcut shares this reference, like the original interface proxy.
		saved.clear()
		saved.merge(found.duplicate(true))
		return found
	var pending_match: bool = pending.get("itemID", 0) == saved.get("itemID", 0)
	if binding.grouped:
		var empty := saved.duplicate(true)
		empty.count = 0
		saved.count = 0
		return empty
	if pending_match: return saved.duplicate(true)
	clear(slot)
	return {}
