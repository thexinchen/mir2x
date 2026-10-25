extends Node

const CerealReader = preload("res://scripts/network/cereal_reader.gd")


func _ready() -> void:
	if not _test_peer_list() or not _test_message_list() or not _test_state_ordering() or not _test_wire_builders():
		get_tree().quit(1)
		return
	print("FRIEND CHAT PASS")
	get_tree().quit()


func _test_peer_list() -> bool:
	var archive := PackedByteArray([1])
	_u64(archive, 3)
	_peer_special(archive, 0xFFFFFF01, "系统助手")
	_peer_player(archive, 42, "剑客", true, 1)
	_peer_group(archive, 77, "远征队", 42, [42, 99])
	var reader := CerealReader.new(_envelope(archive))
	var peers := reader.read_sd_chat_peer_list()
	return _expect(reader.valid and reader.at_end(), "peer archive invalid: %s" % reader.error) \
		and _expect(peers.size() == 3, "peer count mismatch") \
		and _expect(peers[0].cpid == ((1 << 32) | 0xFFFFFF01), "special CPID mismatch") \
		and _expect(peers[1].type == 2 and peers[1].gender and peers[1].job == 1, "player variant mismatch") \
		and _expect(peers[2].type == 3 and peers[2].members.size() == 2, "group variant mismatch")


func _test_message_list() -> bool:
	var inner := _serialized_string("<layout><par>你好</par></layout>")
	var archive := PackedByteArray([1])
	_u64(archive, 1)
	archive.append(0) # optional seq: not null
	_u64(archive, 9001)
	_u64(archive, 123456)
	archive.append(1) # optional refer: null
	_u64(archive, (2 << 32) | 42)
	_u64(archive, (2 << 32) | 99)
	_bytes(archive, inner)
	var reader := CerealReader.new(_envelope(archive))
	var messages := reader.read_sd_chat_message_list()
	return _expect(reader.valid and reader.at_end(), "message archive invalid: %s" % reader.error) \
		and _expect(messages.size() == 1 and messages[0].seq.id == 9001, "message sequence mismatch") \
		and _expect(_message_text(messages[0].message) == "<layout><par>你好</par></layout>", "inner cereal string mismatch")


func _test_state_ordering() -> bool:
	var state := get_node("/root/GameState")
	state.player_uid = (5 << 59) | 42
	state.chat_conversations.clear()
	state.chat_messages.clear()
	var self_cpid: int = state.self_chat_cpid()
	var peer_cpid: int = (2 << 32) | 99
	state.add_chat_message(_message(2, 200, peer_cpid, self_cpid, "后到"))
	state.add_chat_message(_message(1, 100, self_cpid, peer_cpid, "先到"))
	var messages: Array = state.chat_conversations[0].messages
	return _expect(self_cpid == ((2 << 32) | 42), "self CPID did not use original player DBID: %d" % self_cpid) \
		and _expect(messages.size() == 2, "conversation message count mismatch") \
		and _expect(messages[0].seq.id == 1 and messages[1].seq.id == 2, "message ordering mismatch") \
		and _expect(state.chat_message_text(messages[0]) == "先到", "message plain text mismatch") \
		and _expect(state.chat_message_text({"message": NetworkClient._serialize_cereal_string("<layout><par>&lt;标记&gt;&amp;</par></layout>")}) == "<标记>&", "plain-text preview did not decode XML entities after removing tags")


func _test_wire_builders() -> bool:
	var static128: PackedByteArray = NetworkClient._make_static_buffer_capacity("abc", 128)
	var inner: PackedByteArray = NetworkClient._serialize_cereal_string("测试")
	return _expect(static128.size() == 132 and static128.decode_u16(0) == 3, "StaticBuffer<128> ABI mismatch") \
		and _expect(inner[0] == 1 and inner[inner.size() - 1] == 0, "cereal string envelope mismatch") \
		and _expect(_message_text(inner) == "测试", "cereal string writer mismatch")


func _message(id: int, timestamp: int, from: int, to: int, text: String) -> Dictionary:
	return {"seq": {"id": id, "timestamp": timestamp}, "refer": null, "from": from, "to": to, "message": _serialized_string("<layout><par>%s</par></layout>" % text)}


func _peer_special(buf: PackedByteArray, id: int, name: String) -> void:
	_peer_base(buf, id, name)
	_s32(buf, 0)


func _peer_player(buf: PackedByteArray, id: int, name: String, gender: bool, job: int) -> void:
	_peer_base(buf, id, name)
	_s32(buf, 1)
	buf.append(1 if gender else 0)
	_s32(buf, job)


func _peer_group(buf: PackedByteArray, id: int, name: String, creator: int, members: Array) -> void:
	_peer_base(buf, id, name)
	_s32(buf, 2)
	_u32(buf, creator)
	_u64(buf, 456789)
	_u64(buf, members.size())
	for member in members:
		_u32(buf, member)
		_u16(buf, 0)


func _peer_base(buf: PackedByteArray, id: int, name: String) -> void:
	_u32(buf, id)
	_string(buf, name)
	buf.append(1) # optional avatar: null


func _message_text(payload: PackedByteArray) -> String:
	var reader := CerealReader.new(payload)
	return reader.read_string() if reader.valid else ""


func _serialized_string(value: String) -> PackedByteArray:
	var archive := PackedByteArray([1])
	_string(archive, value)
	return _envelope(archive)


func _envelope(archive: PackedByteArray) -> PackedByteArray:
	var result := archive.duplicate()
	result.append(0)
	return result


func _string(buf: PackedByteArray, value: String) -> void:
	_bytes(buf, value.to_utf8_buffer())


func _bytes(buf: PackedByteArray, value: PackedByteArray) -> void:
	_u64(buf, value.size())
	buf.append_array(value)


func _s32(buf: PackedByteArray, value: int) -> void:
	_u32(buf, value & 0xFFFFFFFF)


func _u16(buf: PackedByteArray, value: int) -> void:
	var offset := buf.size()
	buf.resize(offset + 2)
	buf.encode_u16(offset, value)


func _u32(buf: PackedByteArray, value: int) -> void:
	var offset := buf.size()
	buf.resize(offset + 4)
	buf.encode_u32(offset, value)


func _u64(buf: PackedByteArray, value: int) -> void:
	var offset := buf.size()
	buf.resize(offset + 8)
	buf.encode_u32(offset, value & 0xFFFFFFFF)
	buf.encode_u32(offset + 4, (value >> 32) & 0xFFFFFFFF)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
