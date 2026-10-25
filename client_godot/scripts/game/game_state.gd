extends Node

# Game state manager - tracks all client-side game state
# Corresponds to ProcessRun in the C++ client

signal state_changed

const UID_RECORD_ID_BIT_OFFSET := 35
const UID_RECORD_ID_MASK := 0xFFFFFF

# Player state
var player_uid: int = 0
var player_name: String = ""
var player_name_color: int = 0xFFFFFFFF
var player_gender: int = 0
var player_job: int = 0
var player_level: int = 1
var player_exp: int = 0
var player_gold: int = 0
var player_x: int = 0
var player_y: int = 0
var player_direction: int = 0
var player_action_type: int = 2
var player_action_started_ms: int = 0
var player_action_speed: int = 100
var player_action_magic_id: int = 0
var player_action_step: int = 0
var player_action_from_x: int = 0
var player_action_from_y: int = 0
var player_hp: int = 0
var player_hp_max: int = 0
var player_mp: int = 0
var player_mp_max: int = 0
var player_health_initialized := false
var player_map_uid: int = 0
var player_map_id: int = 0
var player_map_name: String = ""
var player_desp: Dictionary = {}

# Combat stats
var ac_min: int = 0
var ac_max: int = 0
var dc_min: int = 0
var dc_max: int = 0
var ac_magic: bool = false  # show MA instead of AC
var dc_magic: bool = false  # show MC instead of DC

# Inventory (10x10 grid, 38px cells)
var inventory: Array = []  # compact list of SDItem; the panel computes grid placement
var belt: Array = []  # 6 slots, each is SDItem or null
var wear: Dictionary = {}  # wear location -> SDItem
var grabbed_item: Dictionary = {}
var secured_items: Array = []
var secured_items_reset_serial := 0

# Buffs
var buff_list: Array = []  # list of {id, type, state}

# All visible creatures (players, monsters, NPCs)
var creatures: Dictionary = {}  # uid -> CreatureData

# Ground items
var ground_items: Dictionary = {}  # "x,y" -> list of item IDs

# Chat log
var chat_log: Array = []  # list of {type, text, color, background_color}
var player_say_messages: Dictionary = {}  # hero uid -> [{text, start_time}]
const CHAT_LOG_MAX := 200
const PLAYER_SAY_LIMIT := 10

# Persistent friend-chat state (separate from nearby/world chat).
var chat_friends: Array = []
var chat_peers: Dictionary = {} # CPID -> SDChatPeer
var chat_conversations: Array = [] # newest conversation first
var chat_messages: Dictionary = {} # DB message id -> SDChatMessage

# Magic/skill list
var learned_magic: Array = []  # list of magic IDs
var magic_keys: Dictionary = {}  # magicID -> key char
var magic_cast_times: Dictionary = {}  # magicID -> local monotonic milliseconds
var magic_key_hud_visible := true
var runtime_config: Dictionary = {}

# Panel-backed gameplay state
var team_leader: int = 0
var team_members: Array = []
var team_candidates: Array = []
var quests: Dictionary = {}
var quest_reset_serial := 0
var npc_dialog: Dictionary = {}
var npc_sell: Dictionary = {}
var npc_sell_detail: Dictionary = {}
var npc_sell_reset_serial := 0
var pending_input: Dictionary = {}
var inventory_operation: Dictionary = {}
var inventory_operation_cost: Dictionary = {}
var firewalls: Array = []
var _firewall_variant_serial := 0
var magic_effects: Array = []
var attached_magic_effects: Array = []

# Camera position (pixel coordinates)
var view_x: float = 0.0
var view_y: float = 0.0
var hud_minimized := false
var _camera_scrolling := false

# Strike grids (recently attacked grid cells, for red flash overlay)
var strike_grids: Dictionary = {}  # "x,y" -> timestamp_msec

# Ascend strings (floating damage/heal/exp text)
var ascend_strings: Array = []  # list of {x, y, type, value, start_time}

# System constants
const GRID_XP := 48
const GRID_YP := 32
const SCREEN_W := 800
const SCREEN_H := 600
const HUD_SHIFT_HEIGHT := 131
# C++ ProcessRun::scrollMap() advances 3/2 pixels in a 70 Hz update loop.
const CAMERA_SCROLL_X_SPEED := 3.0 * 70.0
const CAMERA_SCROLL_Y_SPEED := 2.0 * 70.0
const CAMERA_REFERENCE_DELTA := 1.0 / 70.0
const CAMERA_MAX_DELTA := 1.0 / 30.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().root.size = Vector2i(SCREEN_W, SCREEN_H)
	belt.resize(6)
	for i in range(6):
		belt[i] = null


func add_team_candidate(candidate: Dictionary) -> void:
	var candidate_uid: int = candidate.get("uid", 0)
	for member_value in team_members:
		var member: Dictionary = member_value
		if member.get("uid", 0) == candidate_uid:
			return
	for index in range(team_candidates.size() - 1, -1, -1):
		if team_candidates[index].get("uid", 0) == candidate_uid:
			team_candidates.remove_at(index)
	team_candidates.push_front(candidate)
	state_changed.emit()


func set_team_member_list(leader: int, members: Array) -> void:
	team_leader = leader
	team_members = members
	for index in range(team_candidates.size() - 1, -1, -1):
		var candidate_uid: int = team_candidates[index].get("uid", 0)
		for member_value in team_members:
			var member: Dictionary = member_value
			if member.get("uid", 0) == candidate_uid:
				team_candidates.remove_at(index)
				break
	state_changed.emit()


func set_quest_list(value: Dictionary) -> void:
	quests = value
	quest_reset_serial += 1
	state_changed.emit()


func set_secured_items(items: Array) -> void:
	secured_items = items
	secured_items_reset_serial += 1
	state_changed.emit()


func set_npc_sell(value: Dictionary) -> void:
	npc_sell = value
	npc_sell_detail = {}
	npc_sell_reset_serial += 1
	state_changed.emit()


func update_quest_description(name: String, fsm: String, desp: Variant, main_fsm: String) -> void:
	if desp == null and fsm == main_fsm:
		quests.erase(name)
	else:
		var state_map: Dictionary = quests.get(name, {})
		if desp == null:
			state_map.erase(fsm)
		else:
			state_map[fsm] = str(desp)
		quests[name] = state_map
	state_changed.emit()


func set_player_online(online_data: Dictionary) -> void:
	hud_minimized = false
	player_health_initialized = false
	player_hp = 0
	player_hp_max = 0
	player_mp = 0
	player_mp_max = 0
	player_exp = 0
	player_level = 0
	inventory.clear()
	chat_log.clear()
	creatures.clear()
	ground_items.clear()
	player_say_messages.clear()
	buff_list.clear()
	firewalls.clear()
	_firewall_variant_serial = 0
	magic_effects.clear()
	attached_magic_effects.clear()
	strike_grids.clear()
	ascend_strings.clear()
	player_gold = 0
	belt.resize(6)
	belt.fill(null)
	wear.clear()
	player_desp.clear()
	grabbed_item.clear()
	secured_items.clear()
	chat_friends.clear()
	chat_peers.clear()
	chat_conversations.clear()
	chat_messages.clear()
	learned_magic.clear()
	magic_keys.clear()
	magic_cast_times.clear()
	magic_key_hud_visible = true
	runtime_config.clear()
	team_leader = 0
	team_members.clear()
	team_candidates.clear()
	quests.clear()
	npc_dialog.clear()
	npc_sell.clear()
	npc_sell_detail.clear()
	pending_input.clear()
	inventory_operation.clear()
	inventory_operation_cost.clear()
	ac_magic = false
	dc_magic = false
	player_uid = online_data.get("uid", 0)
	player_name = online_data.get("name", "")
	player_name_color = 0xFFFFFFFF
	player_gender = online_data.get("gender", 0)
	player_job = online_data.get("job", 0)
	player_map_uid = online_data.get("map_uid", 0)
	player_x = online_data.get("x", 0)
	player_y = online_data.get("y", 0)
	player_direction = online_data.get("direction", 0)
	player_action_type = online_data.get("action_type", 2)
	player_action_started_ms = Time.get_ticks_msec()
	player_action_speed = online_data.get("action_speed", 100)
	player_action_magic_id = online_data.get("action_magic_id", 0)
	player_action_step = 0
	player_action_from_x = player_x
	player_action_from_y = player_y
	player_map_id = _map_id_from_uid(player_map_uid)
	player_map_name = ""
	center_camera_on_player()
	state_changed.emit()


func start_game_scene(scene_data: Dictionary) -> void:
	player_uid = scene_data.get("uid", player_uid)
	player_map_uid = scene_data.get("mapUID", player_map_uid)
	player_map_id = _map_id_from_uid(player_map_uid)
	player_map_name = ""
	player_name = scene_data.get("name", player_name)
	player_x = scene_data.get("x", player_x)
	player_y = scene_data.get("y", player_y)
	player_direction = scene_data.get("direction", player_direction)
	player_action_type = 2
	player_action_started_ms = Time.get_ticks_msec()
	player_action_speed = 100
	player_action_magic_id = 0
	player_action_step = 0
	player_action_from_x = player_x
	player_action_from_y = player_y
	player_desp = scene_data.get("desp", player_desp)
	wear = player_desp.get("wear", wear)
	player_say_messages.clear()
	magic_effects.clear()
	attached_magic_effects.clear()
	center_camera_on_player()
	state_changed.emit()


func switch_player_map(map_uid: int, x: int, y: int) -> void:
	player_map_uid = map_uid
	player_map_id = _map_id_from_uid(map_uid)
	player_map_name = ""
	player_x = x
	player_y = y
	player_action_from_x = x
	player_action_from_y = y
	creatures.clear()
	ground_items.clear()
	var self_say: Array = player_say_messages.get(player_uid, [])
	player_say_messages.clear()
	if not self_say.is_empty():
		player_say_messages[player_uid] = self_say
	firewalls.clear()
	_firewall_variant_serial = 0
	magic_effects.clear()
	var self_attachments: Array = []
	for effect_value in attached_magic_effects:
		if effect_value is Dictionary and int(effect_value.get("uid", 0)) == player_uid:
			self_attachments.append(effect_value)
	attached_magic_effects = self_attachments
	strike_grids.clear()
	ascend_strings.clear()
	center_camera_on_player()
	state_changed.emit()


func update_health(hp: int, hp_max: int, mp: int, mp_max: int) -> void:
	player_hp = hp
	player_hp_max = hp_max
	player_mp = mp
	player_mp_max = mp_max
	state_changed.emit()


func update_exp(exp: int) -> void:
	player_exp = exp
	player_level = _level_from_exp(exp)
	state_changed.emit()


func update_gold(gold: int) -> void:
	player_gold = gold
	state_changed.emit()


func level_ratio() -> float:
	var current_base := 0 if player_level == 0 else _sum_exp(player_level - 1)
	var required := _sum_exp(player_level) - current_base
	return clampf(float(player_exp - current_base) / float(required), 0.0, 1.0)


func inventory_ratio() -> float:
	return clampf(float(inventory.size()) / 100.0, 0.0, 1.0)


func add_chat_log(text: String, log_type: int = 0, background_color: Color = Color.TRANSPARENT) -> void:
	var color := Color.WHITE
	match log_type:
		0: color = Color(1, 1, 1, 1)      # white
		1: color = Color(0, 1, 0, 1)       # green
		2: color = Color8(64, 128, 255, 255) # blue
		3: color = Color8(255, 64, 64, 255)  # red
	chat_log.append({"type": log_type, "text": text, "color": color, "background_color": background_color})
	if chat_log.size() > CHAT_LOG_MAX:
		chat_log.pop_front()
	state_changed.emit()


func add_player_say(uid: int, text: String) -> void:
	if uid == 0 or text.is_empty():
		return
	var messages: Array = player_say_messages.get(uid, [])
	while messages.size() >= PLAYER_SAY_LIMIT:
		messages.pop_front()
	messages.append({"text": text, "start_time": Time.get_ticks_msec()})
	player_say_messages[uid] = messages
	state_changed.emit()


func self_chat_cpid() -> int:
	var dbid := player_uid & 0xFFFFFFFF
	return (2 << 32) | dbid


func set_chat_friends(friends: Array) -> void:
	chat_friends = friends.duplicate(true)
	for peer in chat_friends:
		chat_peers[int(peer.get("cpid", 0))] = peer
	state_changed.emit()


func add_chat_peer(peer: Dictionary, friend: bool = false, preview: String = "") -> void:
	var cpid := int(peer.get("cpid", 0))
	if cpid == 0:
		return
	chat_peers[cpid] = peer
	if friend:
		var found := false
		for current in chat_friends:
			if int(current.get("cpid", 0)) == cpid:
				found = true
				break
		if not found:
			chat_friends.append(peer)
	if not preview.is_empty():
		ensure_chat_conversation(cpid, preview)
	state_changed.emit()


func add_chat_group(peer: Dictionary, preview: String) -> bool:
	var cpid := int(peer.get("cpid", 0))
	if cpid == 0 or chat_peers.has(cpid):
		return false
	add_chat_peer(peer, true, preview)
	return true


func ensure_chat_conversation(cpid: int, preview: String) -> void:
	for index in range(chat_conversations.size()):
		if int(chat_conversations[index].get("cpid", 0)) == cpid:
			var conversation: Dictionary = chat_conversations[index]
			conversation["preview"] = preview
			chat_conversations.remove_at(index)
			chat_conversations.push_front(conversation)
			return
	chat_conversations.push_front({"cpid": cpid, "messages": [], "unread": 0, "preview": preview})


func cache_chat_message(message: Dictionary) -> void:
	var seq: Variant = message.get("seq")
	if seq == null:
		return
	var message_id := int(seq.get("id", 0))
	if message_id != 0:
		chat_messages[message_id] = message
		state_changed.emit()


func add_chat_message(message: Dictionary) -> void:
	var seq: Variant = message.get("seq")
	if seq == null:
		return
	var message_id := int(seq.get("id", 0))
	if message_id == 0 or chat_messages.has(message_id):
		return
	chat_messages[message_id] = message
	var self_cpid := self_chat_cpid()
	var from_cpid := int(message.get("from", 0))
	var to_cpid := int(message.get("to", 0))
	var peer_cpid := to_cpid if from_cpid == self_cpid else from_cpid
	if ((to_cpid >> 32) & 0xFFFFFFFF) == 3:
		peer_cpid = to_cpid
	if peer_cpid == 0:
		return
	var conversation: Dictionary = {}
	var existing_index := -1
	for index in range(chat_conversations.size()):
		if int(chat_conversations[index].get("cpid", 0)) == peer_cpid:
			conversation = chat_conversations[index]
			existing_index = index
			break
	if existing_index >= 0:
		chat_conversations.remove_at(existing_index)
	else:
		conversation = {"cpid": peer_cpid, "messages": [], "unread": 0}
	var messages: Array = conversation.get("messages", [])
	messages.append(message)
	messages.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_seq: Dictionary = a.get("seq", {})
		var b_seq: Dictionary = b.get("seq", {})
		var a_time := int(a_seq.get("timestamp", 0))
		var b_time := int(b_seq.get("timestamp", 0))
		return a_time < b_time or (a_time == b_time and int(a_seq.get("id", 0)) < int(b_seq.get("id", 0)))
	)
	conversation["messages"] = messages
	conversation["preview"] = chat_message_text(message)
	conversation["unread"] = int(conversation.get("unread", 0)) + 1
	chat_conversations.push_front(conversation)
	state_changed.emit()


func mark_chat_read(cpid: int) -> void:
	for conversation in chat_conversations:
		if int(conversation.get("cpid", 0)) == cpid:
			conversation["unread"] = 0
			state_changed.emit()
			return


func chat_message_text(message: Dictionary) -> String:
	var xml := chat_message_xml(message)
	if xml.is_empty():
		return "[无效消息]"
	var result := ""
	var in_tag := false
	for character in xml:
		if character == "<":
			in_tag = true
		elif character == ">":
			in_tag = false
		elif not in_tag and character != "\r" and character != "\n":
			result += character
	return result.xml_unescape()


func chat_message_xml(message: Dictionary) -> String:
	var payload: PackedByteArray = message.get("message", PackedByteArray())
	if payload.is_empty():
		return ""
	var reader_script = load("res://scripts/network/cereal_reader.gd")
	var reader = reader_script.new(payload)
	if not reader.valid:
		return ""
	return reader.read_string()


func update_creature(uid: int, data: Dictionary) -> void:
	creatures[uid] = data
	state_changed.emit()


func remove_creature(uid: int) -> void:
	creatures.erase(uid)
	player_say_messages.erase(uid)
	state_changed.emit()


func get_creature(uid: int) -> Dictionary:
	return creatures.get(uid, {})


func update_inventory(items: Array) -> void:
	inventory = items
	state_changed.emit()


func start_inventory_operation(operation: Dictionary) -> void:
	inventory_operation = operation
	inventory_operation_cost = {}
	state_changed.emit()


func clear_inventory_operation() -> void:
	inventory_operation = {}
	inventory_operation_cost = {}
	state_changed.emit()


func set_inventory_operation_cost(data: Dictionary) -> void:
	if int(inventory_operation.get("invOp", 0)) != int(data.get("invOp", -1)):
		return
	inventory_operation_cost = data
	state_changed.emit()


func remove_secured_item(item_id: int, seq_id: int) -> void:
	for index in range(secured_items.size() - 1, -1, -1):
		var item: Dictionary = secured_items[index]
		if int(item.get("itemID", 0)) == item_id and int(item.get("seqID", 0)) == seq_id:
			secured_items.remove_at(index)
	state_changed.emit()


func update_belt(items: Array) -> void:
	belt = items
	state_changed.emit()


func update_item(item: Dictionary) -> int:
	var item_id: int = item.get("itemID", 0)
	var seq_id: int = item.get("seqID", 0)
	var grabbed_match: bool = grabbed_item.get("itemID", 0) == item_id and grabbed_item.get("seqID", 0) == seq_id
	if grabbed_match:
		grabbed_item = item if item.get("count", 0) > 0 else {}
	for index in range(inventory.size()):
		if inventory[index].get("itemID", 0) == item_id and inventory[index].get("seqID", 0) == seq_id:
			var changed: int = item.get("count", 0) - inventory[index].get("count", 0)
			if item.get("count", 0) > 0:
				inventory[index] = item
			else:
				inventory.remove_at(index)
			state_changed.emit()
			return changed
	if grabbed_match:
		state_changed.emit()
		return 0
	if item_id != 0 and item.get("count", 0) > 0:
		inventory.append(item)
		state_changed.emit()
		return item.get("count", 0)
	return 0


func remove_item(item_id: int, seq_id: int, count: int) -> void:
	if grabbed_item.get("itemID", 0) == item_id and grabbed_item.get("seqID", 0) == seq_id:
		var grabbed_remaining: int = maxi(0, grabbed_item.get("count", 0) - count)
		if grabbed_remaining == 0:
			grabbed_item = {}
		else:
			grabbed_item["count"] = grabbed_remaining
		state_changed.emit()
		return
	for index in range(inventory.size()):
		var item: Dictionary = inventory[index]
		if item.get("itemID", 0) != item_id or item.get("seqID", 0) != seq_id:
			continue
		var remaining: int = maxi(0, item.get("count", 0) - count)
		if remaining == 0:
			inventory.remove_at(index)
		else:
			item["count"] = remaining
			inventory[index] = item
		state_changed.emit()
		return


func update_ground_item_grids(grids: Array) -> void:
	for grid in grids:
		var key := "%d,%d" % [grid.get("x", 0), grid.get("y", 0)]
		var items: Array = grid.get("items", [])
		if items.is_empty():
			ground_items.erase(key)
		else:
			ground_items[key] = items
	state_changed.emit()


func reconcile_firewalls(grids: Array, now: int, fire_ash_magic_id: int) -> Dictionary:
	var added: Array = []
	var fading: Array = []
	for grid_value in grids:
		var grid: Dictionary = grid_value
		var x: int = grid.get("x", 0)
		var y: int = grid.get("y", 0)
		var desired_count := maxi(0, int(grid.get("count", 0)))
		var active: Array = []
		for firewall_value in firewalls:
			var firewall: Dictionary = firewall_value
			if firewall.get("x", 0) == x and firewall.get("y", 0) == y and firewall.get("fade_start_time", -1) < 0:
				active.append(firewall)
		var count_diff := active.size() - desired_count
		if count_diff > 0:
			for index in count_diff:
				var firewall: Dictionary = active[index]
				firewall["fade_start_time"] = now
				fading.append(firewall)
				if fire_ash_magic_id > 0:
					var serial: int = firewall.get("variant_serial", 0)
					magic_effects.append({
						"magicID": fire_ash_magic_id,
						"source": "firewall_ash",
						"x": x,
						"y": y,
						"start_time": now,
						"ash_direction": serial % 5,
						"frame_offset": serial % 10,
						"rotation": (serial * 73) % 360,
					})
		elif count_diff < 0:
			for _index in -count_diff:
				var serial := _firewall_variant_serial
				_firewall_variant_serial += 1
				var firewall := {
					"x": x,
					"y": y,
					"start_time": now,
					"frame_offset": serial % 10,
					"variant_serial": serial,
					"fade_start_time": -1,
				}
				firewalls.append(firewall)
				added.append(firewall)
	state_changed.emit()
	return {"added": added, "fading": fading}


func remove_ground_item(x: int, y: int, item_id: int) -> void:
	var key := "%d,%d" % [x, y]
	if not ground_items.has(key):
		return
	var items: Array = ground_items[key]
	items.erase(item_id)
	if items.is_empty():
		ground_items.erase(key)
	state_changed.emit()


func add_magic_effect(data: Dictionary, source: String) -> void:
	var effect := data.duplicate(true)
	effect["source"] = source
	effect["start_time"] = Time.get_ticks_msec()
	magic_effects.append(effect)
	state_changed.emit()


func add_cast_magic_attachment(data: Dictionary, magic_name: String) -> bool:
	var effect := data.duplicate(true)
	effect["magicID"] = data.get("magic", data.get("magicID", 0))
	effect["start_time"] = Time.get_ticks_msec()
	effect["cycles"] = 1
	effect["kind"] = ""
	match magic_name:
		"魔法盾":
			effect["target_uid"] = data.get("uid", 0)
			effect["cycles"] = 2
			effect["kind"] = "shield"
		"阴阳法环":
			effect["target_uid"] = data.get("uid", 0)
			effect["cycles"] = 2
			effect["kind"] = "yin_yang_ring"
		"雷电术", "沃玛教主_雷电术":
			effect["target_uid"] = data.get("aimUID", 0)
			effect["kind"] = "thunderbolt"
			effect["play_seff"] = true
		_:
			return false
	if effect.target_uid == 0 or effect.magicID == 0:
		return false
	if effect.target_uid != player_uid and not creatures.has(effect.target_uid):
		return false
	attached_magic_effects.append(effect)
	state_changed.emit()
	return true


func trigger_shield_hit(uid: int) -> bool:
	for effect_value in attached_magic_effects:
		var effect: Dictionary = effect_value
		if effect.get("target_uid", 0) != uid or effect.get("kind", "") not in ["shield", "shield_hit"]:
			continue
		effect["stage"] = 5
		effect["kind"] = "shield_hit"
		effect["start_time"] = Time.get_ticks_msec()
		effect["cycles"] = 1
		effect.erase("_seff_played")
		state_changed.emit()
		return true
	return false


func update_entity_health(data: Dictionary) -> void:
	var uid: int = data.get("uid", 0)
	if uid == player_uid:
		var initialized := player_health_initialized
		var previous_hp := player_hp
		var previous_mp := player_mp
		update_health(data.get("hp", 0), data.get("maxHP", 0), data.get("mp", 0), data.get("maxMP", 0))
		player_health_initialized = true
		if initialized:
			_add_health_feedback(player_x, player_y, player_hp - previous_hp, player_mp - previous_mp)
		return
	var creature: Dictionary = creatures.get(uid, {})
	if creature.is_empty():
		return
	var initialized: bool = creature.get("health_initialized", false)
	var previous_hp: int = creature.get("hp", 0)
	var previous_mp: int = creature.get("mp", 0)
	creature["hp"] = data.get("hp", 0)
	creature["mp"] = data.get("mp", 0)
	creature["hp_max"] = data.get("maxHP", 0)
	creature["mp_max"] = data.get("maxMP", 0)
	creature["health_initialized"] = true
	creatures[uid] = creature
	if initialized:
		_add_health_feedback(creature.get("x", 0), creature.get("y", 0), creature.hp - previous_hp, creature.mp - previous_mp)
	state_changed.emit()


func _add_health_feedback(grid_x: int, grid_y: int, diff_hp: int, diff_mp: int) -> void:
	var pixel_x := grid_x * GRID_XP + GRID_XP / 2
	var pixel_y := grid_y * GRID_YP - GRID_YP
	if diff_hp > 0:
		add_ascend_value(pixel_x, pixel_y, 3, diff_hp)
	elif diff_hp < 0:
		add_ascend_value(pixel_x, pixel_y, 1, diff_hp)
	if diff_mp > 0:
		add_ascend_value(pixel_x, pixel_y - (GRID_YP if diff_hp != 0 else 0), 2, diff_mp)


func camera_center_y() -> int:
	var visible_height := SCREEN_H if hud_minimized else SCREEN_H - HUD_SHIFT_HEIGHT
	return floori(float(visible_height) * 0.5)


func center_camera_on_player() -> void:
	center_camera_on_grid(Vector2(player_x, player_y))


func center_camera_on_grid(grid_position: Vector2) -> void:
	view_x = grid_position.x * GRID_XP - SCREEN_W * 0.5
	view_y = grid_position.y * GRID_YP - camera_center_y()
	if player_action_type not in [3, 5]:
		_camera_scrolling = false


func _map_id_from_uid(map_uid: int) -> int:
	return uid_record_id(map_uid)


func uid_record_id(uid: int) -> int:
	# common/src/uidf.cpp: 64 - reserved(1) - type(4) - record(24) = 35.
	return (uid >> UID_RECORD_ID_BIT_OFFSET) & UID_RECORD_ID_MASK


func _level_from_exp(exp: int) -> int:
	var level := 0
	while true:
		var sum_exp := _sum_exp(level)
		if sum_exp > exp:
			return level
		level += 1
	return 0


func _sum_exp(level: int) -> int:
	return 100 * level * level * level + 100 * level * level + 100 * level + 1000


func scroll_camera() -> void:
	scroll_camera_to(Vector2(player_x, player_y))


func scroll_camera_to(target_grid: Vector2, delta_seconds: float = CAMERA_REFERENCE_DELTA) -> void:
	# ProcessRun::update() calls centerMyHero() after advancing the current
	# motion.  While a hero is walking, that makes the camera follow the
	# motion-frame pixel offset directly (the hero stays centered), instead of
	# waiting for the one-sixth-screen dead zone in scrollMap().
	if player_action_type in [3, 5]:
		center_camera_on_grid(target_grid)
		_camera_scrolling = false
		return
	# Keep a stable one-sixth-screen dead zone, then continue converging until
	# the player's visual position is centered and the movement has ended.
	var target_x := target_grid.x * GRID_XP - SCREEN_W * 0.5
	var target_y := target_grid.y * GRID_YP - camera_center_y()
	var dx := target_x - view_x
	var dy := target_y - view_y
	var visible_height := SCREEN_H if hud_minimized else SCREEN_H - HUD_SHIFT_HEIGHT
	if _camera_scrolling or abs(dx) > SCREEN_W / 6.0 or abs(dy) > visible_height / 6.0:
		_camera_scrolling = true
		var elapsed := clampf(delta_seconds, 0.0, CAMERA_MAX_DELTA)
		if not is_zero_approx(dx):
			view_x += sign(dx) * min(abs(dx), CAMERA_SCROLL_X_SPEED * elapsed)
		if not is_zero_approx(dy):
			view_y += sign(dy) * min(abs(dy), CAMERA_SCROLL_Y_SPEED * elapsed)
		view_x = maxf(0.0, view_x)
		view_y = maxf(0.0, view_y)
	if is_equal_approx(view_x, target_x) and is_equal_approx(view_y, target_y) and player_action_type not in [3, 5]:
		_camera_scrolling = false


func add_ascend_miss(pixel_x: int, pixel_y: int) -> void:
	ascend_strings.append({
		"x": pixel_x,
		"y": pixel_y,
		"type": 0,
		"value": 0,
		"start_time": Time.get_ticks_msec(),
	})


func add_ascend_value(pixel_x: int, pixel_y: int, type: int, value: int) -> void:
	ascend_strings.append({
		"x": pixel_x,
		"y": pixel_y,
		"type": type,
		"value": value,
		"start_time": Time.get_ticks_msec(),
	})


func update_ascend_strings() -> void:
	var now := Time.get_ticks_msec()
	var to_keep: Array = []
	for s in ascend_strings:
		var age: int = now - s.get("start_time", 0)
		if age < 3000:
			to_keep.append(s)
	ascend_strings = to_keep
