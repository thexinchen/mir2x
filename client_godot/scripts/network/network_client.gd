extends Node

signal connection_changed(connected: bool, message: String)
signal message_received(head_code: int, payload: PackedByteArray)
signal response_received(response_id: int, head_code: int, payload: PackedByteArray)

# CMType enum (client -> server)
const CM_PING := 1
const CM_LOGIN := 2
const CM_QUERYCHAR := 3
const CM_CREATECHAR := 4
const CM_DELETECHAR := 5
const CM_CHANGEPASSWORD := 6
const CM_ONLINE := 7
const CM_ACTION := 8
const CM_SETMAGICKEY := 9
const CM_SETRUNTIMECONFIG := 10
const CM_QUERYCORECORD := 11
const CM_REQUESTADDHP := 12
const CM_REQUESTADDEXP := 13
const CM_REQUESTDIE := 14
const CM_REQUESTKILLPETS := 15
const CM_PICKUP := 19
const CM_QUERYMAPBASEUID := 20
const CM_QUERYGOLD := 21
const CM_QUERYUIDBUFF := 22
const CM_QUERYPLAYERNAME := 23
const CM_QUERYPLAYERWLDESP := 24
const CM_QUERYCHATPEERLIST := 25
const CM_QUERYCHATMESSAGE := 26
const CM_CREATECHATGROUP := 27
const CM_NPCEVENT := 29
const CM_QUERYSELLITEMLIST := 30
const CM_DROPITEM := 31
const CM_CONSUMEITEM := 32
const CM_MAKEITEM := 33
const CM_BUY := 34
const CM_ADDFRIEND := 35
const CM_ACCEPTADDFRIEND := 36
const CM_REJECTADDFRIEND := 37
const CM_BLOCKPLAYER := 38
const CM_CHATMESSAGE := 39
const CM_PLAYERSAY := 40
const CM_PLAYERBROADCAST := 41
const CM_REQUESTEQUIPWEAR := 42
const CM_REQUESTGRABWEAR := 43
const CM_REQUESTEQUIPBELT := 44
const CM_REQUESTGRABBELT := 45
const CM_REQUESTJOINTEAM := 46
const CM_REQUESTLEAVETEAM := 47
const CM_REQUESTLATESTCHATMESSAGE := 48
const CM_CONSUMEBELTITEM := 49
const CM_HARVESTCORPSE := 50
const CM_REQUESTRETRIEVESECUREDITEM := 16
const CM_REQUESTSPACEMOVE := 17
const CM_CREATEACCOUNT := 28

# SMType enum (server -> client)
const SM_OK := 1
const SM_ERROR := 2
const SM_PING := 3
const SM_UID := 4
const SM_LOGINOK := 5
const SM_LOGINERROR := 6
const SM_CREATEACCOUNTOK := 7
const SM_CREATEACCOUNTERROR := 8
const SM_CHANGEPASSWORDOK := 9
const SM_CHANGEPASSWORDERROR := 10
const SM_QUERYCHAROK := 11
const SM_QUERYCHARERROR := 12
const SM_CREATECHAROK := 13
const SM_CREATECHARERROR := 14
const SM_CREATECHATGROUP := 15
const SM_ADDFRIENDACCEPTED := 16
const SM_ADDFRIENDREJECTED := 17
const SM_DELETECHAROK := 18
const SM_DELETECHARERROR := 19
const SM_ONLINEOK := 20
const SM_ONLINEERROR := 21
const SM_STARTGAMESCENE := 22
const SM_PLAYERCONFIG := 23
const SM_FRIENDLIST := 24
const SM_LEARNEDMAGICLIST := 25
const SM_PLAYERWLDESP := 26
const SM_ACTION := 27
const SM_CORECORD := 28
const SM_HEALTH := 29
const SM_NEXTSTRIKE := 30
const SM_NOTIFYDEAD := 31
const SM_DEADFADEOUT := 32
const SM_EXP := 33
const SM_BUFF := 34
const SM_BUFFIDLIST := 35
const SM_MISS := 36
const SM_CASTMAGIC := 37
const SM_OFFLINE := 38
const SM_PICKUPERROR := 39
const SM_REMOVEGROUNDITEM := 40
const SM_NPCXMLLAYOUT := 41
const SM_NPCSELL := 42
const SM_STARTINVOP := 43
const SM_STARTINPUT := 44
const SM_GOLD := 45
const SM_INVOPCOST := 46
const SM_STRIKEGRID := 47
const SM_SELLITEMLIST := 48
const SM_TEXT := 49
const SM_PLAYERNAME := 50
const SM_BUILDVERSION := 51
const SM_INVENTORY := 52
const SM_BELT := 53
const SM_UPDATEITEM := 54
const SM_REMOVEITEM := 55
const SM_REMOVESECUREDITEM := 56
const SM_BUYSUCCEED := 57
const SM_BUYERROR := 58
const SM_GROUNDITEMIDLIST := 59
const SM_GROUNDFIREWALLLIST := 60
const SM_EQUIPWEAR := 61
const SM_EQUIPWEARERROR := 62
const SM_GRABWEAR := 63
const SM_GRABWEARERROR := 64
const SM_EQUIPBELT := 65
const SM_EQUIPBELTERROR := 66
const SM_GRABBELT := 67
const SM_GRABBELTERROR := 68
const SM_SHOWSECUREDITEMLIST := 69
const SM_TEAMMEMBERLIST := 70
const SM_TEAMCANDIDATE := 71
const SM_TEAMERROR := 72
const SM_QUESTDESPUPDATE := 73
const SM_QUESTDESPLIST := 74
const SM_CHATMESSAGELIST := 75
const SM_PLAYERSAY := 76
const SM_PLAYERBROADCAST := 77

# StaticBuffer<N> = uint16_t size + uint8_t[N+1], padded to 2-byte alignment
# N=64: 2+65=67 -> pad to 68; N=128: 2+129=131 -> pad to 132
const STATIC_ID_SIZE := 68    # StaticBuffer<64>
const STATIC_NAME_SIZE := 68  # StaticBuffer<64>
const STATIC_PWD_SIZE := 68   # StaticBuffer<64>
const STATIC_BIGBUF_SIZE := 132 # StaticBuffer<128>

# GCC packs the three ActionNode bitfields into 3 bytes.
const ACTION_NODE_SIZE := 27

# System constants
const SYS_MAPGRIDXP := 48
const SYS_MAPGRIDYP := 32
const SYS_OBJMAXW := 3
const SYS_OBJMAXH := 25
const SYS_DEFFPS := 10
const SYS_DEFSPEED := 100
const SYS_U32NIL := 4294967295  # 0xFFFFFFFF
const SYS_U64NIL := -1           # 0xFFFFFFFFFFFFFFFF as signed int64

var _peer := StreamPeerTCP.new()
var _receive_buffer := PackedByteArray()
var _last_status := StreamPeerTCP.STATUS_NONE
var _next_response_id := 1
var _response_callbacks: Dictionary = {}
var _item_use_serial := 0
var _item_use_pending_token := 0
var _message_dispatch_paused := false
var _deferred_messages: Array[Dictionary] = []


func _process(_delta: float) -> void:
	_expire_responses()
	_peer.poll()
	var status := _peer.get_status()
	if status != _last_status:
		_last_status = status
		match status:
			StreamPeerTCP.STATUS_CONNECTED:
				connection_changed.emit(true, "已连接服务器")
			StreamPeerTCP.STATUS_ERROR:
				_item_use_pending_token = 0
				connection_changed.emit(false, "连接服务器失败")
			StreamPeerTCP.STATUS_NONE:
				_item_use_pending_token = 0
				connection_changed.emit(false, "服务器连接已断开")
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := _peer.get_available_bytes()
	if available > 0:
		var read_result := _peer.get_data(available)
		if read_result[0] == OK:
			_receive_buffer.append_array(read_result[1])
			_parse_packets()


func connect_to_server() -> Error:
	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return OK
	_peer = StreamPeerTCP.new()
	_item_use_pending_token = 0
	_receive_buffer.clear()
	_last_status = StreamPeerTCP.STATUS_NONE
	var host := str(ProjectSettings.get_setting("network/server_host", "127.0.0.1"))
	var port := int(ProjectSettings.get_setting("network/server_port", 7000))
	var error := _peer.connect_to_host(host, port)
	if error != OK:
		connection_changed.emit(false, "无法连接 %s:%d" % [host, port])
	return error


func is_connected_to_server() -> bool:
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


func disconnect_from_server() -> void:
	_peer.disconnect_from_host()
	_receive_buffer.clear()
	_response_callbacks.clear()
	_item_use_pending_token = 0
	_message_dispatch_paused = false
	_deferred_messages.clear()


func pause_message_dispatch() -> void:
	_message_dispatch_paused = true


func resume_message_dispatch() -> void:
	_message_dispatch_paused = false
	while not _message_dispatch_paused and not _deferred_messages.is_empty():
		var message: Dictionary = _deferred_messages.pop_front()
		message_received.emit(message.head_code, message.payload)


func _dispatch_message(head_code: int, payload: PackedByteArray) -> void:
	if _message_dispatch_paused:
		_deferred_messages.append({"head_code": head_code, "payload": payload})
	else:
		message_received.emit(head_code, payload)


func login(account: String, password: String) -> Error:
	return _send_fixed_message(CM_LOGIN, _make_account_payload(account, password))


func create_account(account: String, password: String) -> Error:
	return _send_fixed_message(CM_CREATEACCOUNT, _make_account_payload(account, password))


func change_password(account: String, old_password: String, new_password: String) -> Error:
	var payload := PackedByteArray()
	payload.append_array(_make_static_buffer(account))
	payload.append_array(_make_static_buffer(old_password))
	payload.append_array(_make_static_buffer(new_password))
	return _send_fixed_message(CM_CHANGEPASSWORD, payload)


func query_character() -> Error:
	return _send_empty_message(CM_QUERYCHAR)


func create_character(character_name: String, job: int, male: bool) -> Error:
	var payload := _make_static_buffer(character_name)
	payload.append(job)
	payload.append(1 if male else 0)
	return _send_fixed_message(CM_CREATECHAR, payload)


func delete_character(password: String) -> Error:
	return _send_fixed_message(CM_DELETECHAR, _make_static_buffer(password))


func enter_game() -> Error:
	return _send_empty_message(CM_ONLINE)


func send_ping(tick: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, tick)
	return _send_raw_message(CM_PING, payload)


func send_action(action_data: PackedByteArray) -> Error:
	return _send_fixed_message(CM_ACTION, action_data)


# Optional processing receipt, separate from authoritative action/correction
# broadcasts. SM_OK means processing ended, not that the action succeeded.
func send_action_request(action_data: PackedByteArray, callback: Callable, timeout_callback := Callable()) -> Error:
	if action_data.size() != 43:
		return ERR_INVALID_DATA
	# Original elapsed > 10000 expires on tick 10001; other requests keep 1s.
	return _send_request(CM_ACTION, action_data, false, callback, 10001, timeout_callback)


func send_player_say(content: String) -> Error:
	var payload := PackedByteArray()
	payload.resize(128)
	payload.fill(0)
	var encoded := content.to_utf8_buffer()
	for i in range(mini(encoded.size(), 127)):
		payload[i] = encoded[i]
	return _send_fixed_message(CM_PLAYERSAY, payload)


func send_player_broadcast(content: String) -> Error:
	var payload := PackedByteArray()
	payload.resize(128)
	payload.fill(0)
	var encoded := content.to_utf8_buffer()
	for i in range(mini(encoded.size(), 127)):
		payload[i] = encoded[i]
	return _send_fixed_message(CM_PLAYERBROADCAST, payload)


func send_pickup(x: int, y: int, map_uid: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(12)
	payload.encode_u16(0, x)
	payload.encode_u16(2, y)
	_encode_u64(payload, 4, map_uid)
	return _send_fixed_message(CM_PICKUP, payload)


func send_harvest_corpse(corpse_uid: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, corpse_uid)
	return _send_fixed_message(CM_HARVESTCORPSE, payload)


func send_request_space_move(map_uid: int, x: int, y: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(12)
	payload.encode_u64(0, map_uid)
	payload.encode_u16(8, x)
	payload.encode_u16(10, y)
	return _send_fixed_message(CM_REQUESTSPACEMOVE, payload)


func send_request_add_hp(value: int) -> Error:
	return _send_u64_message(CM_REQUESTADDHP, value)


func send_request_add_exp(value: int) -> Error:
	return _send_u64_message(CM_REQUESTADDEXP, value)


func send_request_die() -> Error:
	return _send_empty_message(CM_REQUESTDIE)


func send_request_kill_pets() -> Error:
	return _send_empty_message(CM_REQUESTKILLPETS)


func send_query_gold() -> Error:
	return _send_empty_message(CM_QUERYGOLD)


func send_query_map_base_uid(map_id: int, callback: Callable) -> Error:
	var payload := PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, map_id)
	return _send_request(CM_QUERYMAPBASEUID, payload, false, callback)


func send_query_uid_buff(uid: int) -> Error:
	return _send_u64_message(CM_QUERYUIDBUFF, uid)


func send_query_player_name(uid: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, uid)
	return _send_fixed_message(CM_QUERYPLAYERNAME, payload)


func send_query_player_wldesp(uid: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, uid)
	return _send_fixed_message(CM_QUERYPLAYERWLDESP, payload)


func send_query_corecord(uid: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, uid)
	return _send_fixed_message(CM_QUERYCORECORD, payload)


func send_set_magic_key(magic_id: int, key: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(5)
	payload.encode_u32(0, magic_id)
	payload[4] = key & 0xFF
	return _send_fixed_message(CM_SETMAGICKEY, payload)


func send_set_runtime_config(config_type: int, value: PackedByteArray) -> Error:
	var payload := PackedByteArray()
	payload.resize(262)
	payload.fill(0)
	payload.encode_u16(0, config_type)
	var encoded := value
	if encoded.size() > 256:
		encoded = encoded.slice(0, 256)
	payload.encode_u16(2, encoded.size())
	for index in encoded.size():
		payload[4 + index] = encoded[index]
	return _send_fixed_message(CM_SETRUNTIMECONFIG, payload)


func send_runtime_bool(config_type: int, value: bool) -> Error:
	return send_set_runtime_config(config_type, PackedByteArray([1, 1 if value else 0, 0]))


func send_runtime_float(config_type: int, value: float) -> Error:
	var archive := PackedByteArray()
	archive.resize(6)
	archive[0] = 1
	archive.encode_float(1, value)
	archive[5] = 0
	return send_set_runtime_config(config_type, archive)


func send_runtime_int(config_type: int, value: int) -> Error:
	var archive := PackedByteArray()
	archive.resize(6)
	archive[0] = 1
	archive.encode_s32(1, value)
	archive[5] = 0
	return send_set_runtime_config(config_type, archive)


func send_runtime_pair(config_type: int, first: int, second: int) -> Error:
	var archive := PackedByteArray()
	archive.resize(10)
	archive[0] = 1
	archive.encode_s32(1, first)
	archive.encode_s32(5, second)
	archive[9] = 0
	return send_set_runtime_config(config_type, archive)


func _make_npc_event_payload(uid: int, path: String, event: String, value: Variant = null) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(410)
	payload.fill(0)
	_encode_u64(payload, 0, uid)
	_write_c_string(payload, 8, 100, path)
	_write_c_string(payload, 108, 100, event)
	if value == null:
		payload.encode_u16(408, 0xFFFF)
		return payload
	var value_bytes := str(value).to_utf8_buffer()
	if value_bytes.size() > 200:
		value_bytes = value_bytes.slice(0, 200)
	for index in value_bytes.size():
		payload[208 + index] = value_bytes[index]
	payload.encode_u16(408, value_bytes.size())
	return payload


func send_npc_event(uid: int, path: String, event: String, value: Variant = null) -> Error:
	return _send_fixed_message(CM_NPCEVENT, _make_npc_event_payload(uid, path, event, value))


func send_query_sell_item_list(npc_uid: int, item_id: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(12)
	_encode_u64(payload, 0, npc_uid)
	payload.encode_u32(8, item_id)
	return _send_fixed_message(CM_QUERYSELLITEMLIST, payload)


func send_buy(npc_uid: int, item_id: int, seq_id: int, count: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(20)
	_encode_u64(payload, 0, npc_uid)
	payload.encode_u32(8, item_id)
	payload.encode_u32(12, seq_id)
	payload.encode_u32(16, count)
	return _send_fixed_message(CM_BUY, payload)


func send_drop_item(item_id: int, seq_id: int, count: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u32(0, item_id)
	payload.encode_u32(4, seq_id)
	payload.encode_u16(8, clampi(count, 0, 0xFFFF))
	return _send_fixed_message(CM_DROPITEM, payload)


func send_consume_item(item_id: int, seq_id: int, count: int = 1, callback := Callable()) -> Error:
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u32(0, item_id)
	payload.encode_u32(4, seq_id)
	payload.encode_u16(8, clampi(count, 0, 0xFFFF))
	return _send_item_use_request(CM_CONSUMEITEM, payload, callback)


func send_consume_belt_item(slot: int, callback := Callable()) -> Error:
	var payload := PackedByteArray()
	payload.resize(2)
	payload.encode_u16(0, slot)
	return _send_item_use_request(CM_CONSUMEBELTITEM, payload, callback)


func _send_item_use_request(head: int, payload: PackedByteArray, callback: Callable) -> Error:
	_expire_responses()
	if _item_use_pending_token != 0:
		return ERR_BUSY
	_item_use_serial += 1
	var token := _item_use_serial
	_item_use_pending_token = token
	var complete := func(reply_head: int, reply_payload: PackedByteArray):
		if _item_use_pending_token == token:
			_item_use_pending_token = 0
		if callback.is_valid():
			callback.call(reply_head, reply_payload)
	# Original manual slots enter690494's shared3000ms pending check.
	# Inventory remains authoritative here, so failure/timeout requires no
	# optimistic quantity rollback. A stale callback cannot release a newer use.
	var error := _send_request(head, payload, false, complete, 3000)
	if error != OK and _item_use_pending_token == token:
		_item_use_pending_token = 0
	return error


func send_make_item(item_id: int, count: int = 1) -> Error:
	var payload := PackedByteArray()
	payload.resize(6)
	payload.encode_u32(0, item_id)
	payload.encode_u16(4, clampi(count, 0, 0xFFFF))
	return _send_fixed_message(CM_MAKEITEM, payload)


func send_retrieve_secured_item(item_id: int, seq_id: int) -> Error:
	return _send_item_pair(CM_REQUESTRETRIEVESECUREDITEM, item_id, seq_id)


func send_request_equip_wear(item_id: int, seq_id: int, wear_type: int) -> Error:
	return _send_item_pair_slot(CM_REQUESTEQUIPWEAR, item_id, seq_id, wear_type)


func send_request_grab_wear(wear_type: int) -> Error:
	return _send_u16(CM_REQUESTGRABWEAR, wear_type)


func send_request_equip_belt(item_id: int, seq_id: int, slot: int) -> Error:
	return _send_item_pair_slot(CM_REQUESTEQUIPBELT, item_id, seq_id, slot)


func send_request_grab_belt(slot: int) -> Error:
	return _send_u16(CM_REQUESTGRABBELT, slot)


func send_request_join_team(uid: int) -> Error:
	return _send_u64_message(CM_REQUESTJOINTEAM, uid)


func send_request_leave_team(uid: int) -> Error:
	return _send_u64_message(CM_REQUESTLEAVETEAM, uid)


func query_chat_peers(query: String, callback: Callable) -> Error:
	return _send_request(CM_QUERYCHATPEERLIST, _make_static_buffer_capacity(query, 128), false, callback)


func query_chat_message(message_id: int, callback: Callable) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, message_id)
	return _send_request(CM_QUERYCHATMESSAGE, payload, false, callback)


func create_chat_group(group_name: String, player_ids: Array, callback: Callable) -> Error:
	var payload := _make_static_buffer_capacity(group_name, 128)
	var list := PackedByteArray()
	# StaticVector<uint32_t, 512>: uint16 size + 2-byte alignment pad + data.
	list.resize(4 + 512 * 4)
	list.fill(0)
	list.encode_u16(0, mini(player_ids.size(), 512))
	for index in range(mini(player_ids.size(), 512)):
		list.encode_u32(4 + index * 4, int(player_ids[index]))
	payload.append_array(list)
	return _send_request(CM_CREATECHATGROUP, payload, false, callback)


func send_add_friend(cpid: int, callback: Callable) -> Error:
	return _send_u64_request(CM_ADDFRIEND, cpid, callback)


func send_accept_friend(cpid: int, callback: Callable = Callable()) -> Error:
	return _send_u64_request(CM_ACCEPTADDFRIEND, cpid, callback)


func send_reject_friend(cpid: int, callback: Callable = Callable()) -> Error:
	return _send_u64_request(CM_REJECTADDFRIEND, cpid, callback)


func send_block_player(cpid: int, callback: Callable = Callable()) -> Error:
	return _send_u64_request(CM_BLOCKPLAYER, cpid, callback)


func send_chat_message(cpid: int, text: String, refer_id: Variant, callback: Callable) -> Error:
	var serialized := _serialize_cereal_string("<layout><par>%s</par></layout>" % text)
	var payload := PackedByteArray()
	payload.resize(16)
	_encode_u64(payload, 0, cpid)
	var ref_bits := 0
	if refer_id != null:
		ref_bits = (int(refer_id) << 1) | 1
	_encode_u64(payload, 8, ref_bits)
	payload.append_array(serialized)
	return _send_request(CM_CHATMESSAGE, payload, true, callback)


func request_latest_chat_messages(cpids: Array, limit_count: int = 50, include_send: bool = true, include_recv: bool = true) -> Error:
	var payload := PackedByteArray()
	# StaticVector<uint64_t, 128>: uint16 size + 6-byte alignment pad + data.
	payload.resize(8 + 128 * 8 + 4)
	payload.fill(0)
	payload.encode_u16(0, mini(cpids.size(), 128))
	for index in range(mini(cpids.size(), 128)):
		_encode_u64(payload, 8 + index * 8, int(cpids[index]))
	var flags := clampi(limit_count, 0, 0x3FFFFFFF)
	if include_send:
		flags |= 1 << 30
	if include_recv:
		flags |= 1 << 31
	payload.encode_u32(8 + 128 * 8, flags)
	return _send_fixed_message(CM_REQUESTLATESTCHATMESSAGE, payload)


func _send_item_pair(head_code: int, item_id: int, seq_id: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	payload.encode_u32(0, item_id)
	payload.encode_u32(4, seq_id)
	return _send_fixed_message(head_code, payload)


func _send_item_pair_slot(head_code: int, item_id: int, seq_id: int, slot: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u32(0, item_id)
	payload.encode_u32(4, seq_id)
	payload.encode_u16(8, slot)
	return _send_fixed_message(head_code, payload)


func _send_u16(head_code: int, value: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(2)
	payload.encode_u16(0, value)
	return _send_fixed_message(head_code, payload)


func _send_u64_message(head_code: int, value: int) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, value)
	return _send_fixed_message(head_code, payload)


func _write_c_string(target: PackedByteArray, offset: int, capacity: int, value: String) -> void:
	var encoded := value.to_utf8_buffer()
	for index in range(mini(encoded.size(), capacity - 1)):
		target[offset + index] = encoded[index]


func _make_account_payload(account: String, password: String) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.append_array(_make_static_buffer(account))
	payload.append_array(_make_static_buffer(password))
	return payload


func _make_static_buffer(value: String) -> PackedByteArray:
	return _make_static_buffer_capacity(value, 64)


func _make_static_buffer_capacity(value: String, capacity: int) -> PackedByteArray:
	var encoded := value.to_utf8_buffer()
	if encoded.size() > capacity:
		encoded = encoded.slice(0, capacity)
	var result := PackedByteArray()
	# StaticBuffer itself has uint16 alignment, so its odd field size gets one tail pad byte.
	result.resize((2 + capacity + 1 + 1) & ~1)
	result.fill(0)
	result[0] = encoded.size() & 0xff
	result[1] = (encoded.size() >> 8) & 0xff
	for index in encoded.size():
		result[index + 2] = encoded[index]
	return result


func _send_u64_request(head_code: int, value: int, callback: Callable) -> Error:
	var payload := PackedByteArray()
	payload.resize(8)
	_encode_u64(payload, 0, value)
	return _send_request(head_code, payload, false, callback)


func _send_request(head_code: int, payload: PackedByteArray, variable: bool, callback: Callable, timeout_ms := 1000, timeout_callback := Callable()) -> Error:
	var response_id := _next_response_id
	_next_response_id += 1
	if callback.is_valid():
		_response_callbacks[response_id] = {"callback": callback, "timeout_callback": timeout_callback if timeout_callback.is_valid() else callback, "expires": Time.get_ticks_msec() + timeout_ms}
	var error := _send_variable_message(head_code, payload, response_id) if variable else _send_fixed_message(head_code, payload, response_id)
	if error != OK:
		_response_callbacks.erase(response_id)
	return error


func _expire_responses() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array[int] = []
	for response_id in _response_callbacks:
		if now >= int(_response_callbacks[response_id].get("expires", 0)):
			expired.append(response_id)
	for response_id in expired:
		var entry: Dictionary = _response_callbacks.get(response_id, {})
		_response_callbacks.erase(response_id)
		var callback: Callable = entry.get("timeout_callback", entry.get("callback", Callable()))
		if callback.is_valid():
			callback.call(SM_ERROR, PackedByteArray())


func _serialize_cereal_string(value: String) -> PackedByteArray:
	var encoded := value.to_utf8_buffer()
	var result := PackedByteArray([1])
	var size_offset := result.size()
	result.resize(size_offset + 8)
	_encode_u64(result, size_offset, encoded.size())
	result.append_array(encoded)
	result.append(0) # cerealf::CF_NONE
	return result


func _send_fixed_message(head_code: int, payload: PackedByteArray, response_id: int = 0) -> Error:
	if not is_connected_to_server():
		return ERR_UNCONFIGURED
	var compressed := _xor_encode(payload)
	var packet := PackedByteArray([head_code | 0x80 if response_id > 0 else head_code])
	if response_id > 0:
		packet.append_array(_encode_vlq(response_id))
	packet.append_array(_encode_vlq(compressed[0]))
	packet.append_array(compressed[1])
	return _peer.put_data(packet)


func _send_variable_message(head_code: int, payload: PackedByteArray, response_id: int = 0) -> Error:
	if not is_connected_to_server():
		return ERR_UNCONFIGURED
	var packet := PackedByteArray([head_code | 0x80 if response_id > 0 else head_code])
	if response_id > 0:
		packet.append_array(_encode_vlq(response_id))
	packet.append_array(_encode_vlq(payload.size()))
	packet.append_array(payload)
	return _peer.put_data(packet)


func _send_raw_message(head_code: int, payload: PackedByteArray) -> Error:
	if not is_connected_to_server():
		return ERR_UNCONFIGURED
	var packet := PackedByteArray([head_code])
	packet.append_array(payload)
	return _peer.put_data(packet)


func _send_empty_message(head_code: int) -> Error:
	if not is_connected_to_server():
		return ERR_UNCONFIGURED
	return _peer.put_data(PackedByteArray([head_code]))


func _xor_encode(payload: PackedByteArray) -> Array:
	var use_wide := payload.size() >= 256
	var mask_size := (payload.size() + (63 if use_wide else 7)) / (64 if use_wide else 8)
	var mask := PackedByteArray()
	mask.resize(mask_size)
	mask.fill(0)
	var body := PackedByteArray()
	if use_wide:
		for chunk_start in range(0, payload.size(), 8):
			var chunk_size := mini(8, payload.size() - chunk_start)
			var has_data := false
			for offset in chunk_size:
				has_data = has_data or payload[chunk_start + offset] != 0
			if has_data:
				mask[chunk_start / 64] |= 1 << ((chunk_start % 64) / 8)
				body.append_array(payload.slice(chunk_start, chunk_start + chunk_size))
	else:
		for index in payload.size():
			if payload[index] != 0:
				mask[index / 8] |= 1 << (index % 8)
				body.append(payload[index])
	mask.append_array(body)
	return [body.size(), mask]


func _encode_vlq(value: int) -> PackedByteArray:
	var result := PackedByteArray()
	while true:
		var bits := value & 0x7f
		value >>= 7
		result.append(bits | 0x80 if value > 0 else bits)
		if value == 0:
			return result
	return result


func _encode_u64(buf: PackedByteArray, offset: int, value: int) -> void:
	buf.encode_u32(offset, value & 0xFFFFFFFF)
	buf.encode_u32(offset + 4, (value >> 32) & 0xFFFFFFFF)


func _decode_u64(buf: PackedByteArray, offset: int) -> int:
	return buf.decode_u32(offset) | (buf.decode_u32(offset + 4) << 32)


func _parse_packets() -> void:
	while not _receive_buffer.is_empty():
		var parsed := _try_parse_packet()
		if not parsed[0]:
			return
		var consumed: int = parsed[1]
		var response_id: int = parsed[4]
		if response_id == 0 and parsed[2] == SM_BUILDVERSION:
			_receive_buffer = _receive_buffer.slice(consumed)
			if not _accept_build_version(parsed[3]):
				return
			continue
		if response_id > 0:
			response_received.emit(response_id, parsed[2], parsed[3])
			var entry: Dictionary = _response_callbacks.get(response_id, {})
			var callback: Callable = entry.get("callback", Callable())
			_response_callbacks.erase(response_id)
			if callback.is_valid():
				callback.call(parsed[2], parsed[3])
		else:
			_dispatch_message(parsed[2], parsed[3])
		_receive_buffer = _receive_buffer.slice(consumed)


func _accept_build_version(payload: PackedByteArray) -> bool:
	if "--disable-version-check" in OS.get_cmdline_args() or "--disable-version-check" in OS.get_cmdline_user_args():
		return true
	var server_signature := _decode_build_signature(payload)
	if server_signature.is_empty():
		_reject_build_version("服务端版本信息无效")
		return false
	var client_signature := FileAccess.get_file_as_string("res://assets/generated/build_signature.txt").strip_edges()
	if client_signature.is_empty():
		client_signature = "VENGINEERING-development"
	if server_signature != client_signature:
		_reject_build_version("客户端与服务器版本不一致：客户端 %s，服务器 %s" % [client_signature, server_signature])
		return false
	return true


func _decode_build_signature(payload: PackedByteArray) -> String:
	if payload.size() != STATIC_BIGBUF_SIZE:
		return ""
	var text_size := payload.decode_u16(0)
	if text_size <= 0 or text_size > 128 or 2 + text_size > payload.size():
		return ""
	return payload.slice(2, 2 + text_size).get_string_from_utf8()


func _reject_build_version(message: String) -> void:
	disconnect_from_server()
	_last_status = StreamPeerTCP.STATUS_NONE
	connection_changed.emit(false, message)


func _try_parse_packet() -> Array:
	var cursor := 0
	var encoded_head := _receive_buffer[cursor]
	cursor += 1
	var head_code := encoded_head & 0x7f
	var response_id := 0
	if encoded_head & 0x80:
		var response_result := _try_decode_vlq(cursor)
		if not response_result[0]:
			return [false]
		cursor = response_result[2]
		response_id = response_result[1]
	var attribute := _server_message_attribute(head_code)
	if attribute.is_empty():
		push_error("暂不支持服务器消息: %d" % head_code)
		_receive_buffer.clear()
		return [false]
	var message_type: int = attribute[0]
	var data_length: int = attribute[1]
	if message_type == 0:
		return [true, cursor, head_code, PackedByteArray(), response_id]
	if message_type == 2:
		if _receive_buffer.size() < cursor + data_length:
			return [false]
		return [true, cursor + data_length, head_code, _receive_buffer.slice(cursor, cursor + data_length), response_id]
	var size_result := _try_decode_vlq(cursor)
	if not size_result[0]:
		return [false]
	var body_size: int = size_result[1]
	cursor = size_result[2]
	if message_type == 3:
		if _receive_buffer.size() < cursor + body_size:
			return [false]
		return [true, cursor + body_size, head_code, _receive_buffer.slice(cursor, cursor + body_size), response_id]
	var mask_size := (data_length + 63) / 64 if data_length >= 256 else (data_length + 7) / 8
	if _receive_buffer.size() < cursor + mask_size + body_size:
		return [false]
	var mask := _receive_buffer.slice(cursor, cursor + mask_size)
	cursor += mask_size
	var body := _receive_buffer.slice(cursor, cursor + body_size)
	return [true, cursor + body_size, head_code, _xor_decode(data_length, mask, body), response_id]


func _try_decode_vlq(offset: int) -> Array:
	var value := 0
	var shift := 0
	var cursor := offset
	while cursor < _receive_buffer.size():
		var byte := _receive_buffer[cursor]
		value |= (byte & 0x7f) << shift
		cursor += 1
		if not byte & 0x80:
			return [true, value, cursor]
		shift += 7
		if shift >= 64:
			push_error("服务器发送了无效的变长整数")
			return [false]
	return [false]


func _xor_decode(data_length: int, mask: PackedByteArray, body: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(data_length)
	result.fill(0)
	var body_index := 0
	if data_length >= 256:
		for chunk_start in range(0, data_length, 8):
			var chunk_size := mini(8, data_length - chunk_start)
			if mask[chunk_start / 64] & (1 << ((chunk_start % 64) / 8)):
				if body_index + chunk_size > body.size():
					break
				for offset in chunk_size:
					result[chunk_start + offset] = body[body_index + offset]
				body_index += chunk_size
		return result
	for index in data_length:
		if mask[index / 8] & (1 << (index % 8)):
			if body_index >= body.size():
				break
			result[index] = body[body_index]
			body_index += 1
	return result


# Server message attribute table: [type, dataLen]
# type 0: empty, type 1: fixed+compressed, type 2: fixed+raw, type 3: variable
func _server_message_attribute(head_code: int) -> Array:
	match head_code:
		SM_OK:                   return [3, 0]
		SM_ERROR:                return [3, 0]
		SM_PING:                 return [2, 4]
		SM_UID:                  return [2, 8]
		SM_LOGINOK:              return [0, 0]
		SM_LOGINERROR:           return [1, 1]
		SM_CREATEACCOUNTOK:      return [0, 0]
		SM_CREATEACCOUNTERROR:   return [1, 4]
		SM_CHANGEPASSWORDOK:     return [0, 0]
		SM_CHANGEPASSWORDERROR:  return [1, 4]
		SM_QUERYCHAROK:          return [1, 74]
		SM_QUERYCHARERROR:       return [1, 1]
		SM_CREATECHAROK:         return [0, 0]
		SM_CREATECHARERROR:      return [1, 1]
		SM_CREATECHATGROUP:      return [3, 0]
		SM_ADDFRIENDACCEPTED:    return [3, 0]
		SM_ADDFRIENDREJECTED:    return [3, 0]
		SM_DELETECHAROK:         return [0, 0]
		SM_DELETECHARERROR:      return [1, 1]
		SM_ONLINEOK:             return [1, 176]
		SM_ONLINEERROR:          return [1, 1]
		SM_STARTGAMESCENE:       return [3, 0]
		SM_PLAYERCONFIG:         return [3, 0]
		SM_FRIENDLIST:           return [3, 0]
		SM_LEARNEDMAGICLIST:     return [3, 0]
		SM_PLAYERWLDESP:         return [3, 0]
		SM_ACTION:               return [1, 43]
		SM_CORECORD:             return [1, 48]
		SM_HEALTH:               return [3, 0]
		SM_NEXTSTRIKE:           return [0, 0]
		SM_NOTIFYDEAD:           return [1, 8]
		SM_DEADFADEOUT:          return [1, 24]
		SM_EXP:                  return [1, 4]
		SM_BUFF:                 return [1, 16]
		SM_BUFFIDLIST:           return [3, 0]
		SM_MISS:                 return [1, 8]
		SM_CASTMAGIC:            return [1, 36]
		SM_OFFLINE:              return [1, 16]
		SM_PICKUPERROR:          return [1, 4]
		SM_REMOVEGROUNDITEM:     return [1, 12]
		SM_NPCXMLLAYOUT:         return [3, 0]
		SM_NPCSELL:              return [3, 0]
		SM_STARTINVOP:           return [3, 0]
		SM_STARTINPUT:           return [3, 0]
		SM_GOLD:                 return [1, 4]
		SM_INVOPCOST:            return [1, 16]
		SM_STRIKEGRID:           return [1, 8]
		SM_SELLITEMLIST:         return [3, 0]
		SM_TEXT:                 return [3, 0]
		SM_PLAYERNAME:           return [3, 0]
		SM_BUILDVERSION:         return [1, 132]
		SM_INVENTORY:            return [3, 0]
		SM_BELT:                 return [3, 0]
		SM_UPDATEITEM:           return [3, 0]
		SM_REMOVEITEM:           return [1, 10]
		SM_REMOVESECUREDITEM:    return [1, 8]
		SM_BUYSUCCEED:           return [1, 16]
		SM_BUYERROR:             return [1, 18]
		SM_GROUNDITEMIDLIST:     return [3, 0]
		SM_GROUNDFIREWALLLIST:   return [3, 0]
		SM_EQUIPWEAR:            return [3, 0]
		SM_EQUIPWEARERROR:       return [1, 10]
		SM_GRABWEAR:             return [3, 0]
		SM_GRABWEARERROR:        return [1, 2]
		SM_EQUIPBELT:            return [3, 0]
		SM_EQUIPBELTERROR:       return [1, 10]
		SM_GRABBELT:             return [3, 0]
		SM_GRABBELTERROR:        return [1, 2]
		SM_SHOWSECUREDITEMLIST:  return [3, 0]
		SM_TEAMMEMBERLIST:       return [3, 0]
		SM_TEAMCANDIDATE:        return [3, 0]
		SM_TEAMERROR:            return [1, 1]
		SM_QUESTDESPUPDATE:      return [3, 0]
		SM_QUESTDESPLIST:        return [3, 0]
		SM_CHATMESSAGELIST:      return [3, 0]
		SM_PLAYERSAY:            return [1, 136]
		SM_PLAYERBROADCAST:      return [1, 136]
		_: return []
