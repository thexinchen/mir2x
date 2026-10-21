extends RefCounted

# ZSDB 只读访问器，与 common/src/zsdb.hpp 一一对应。
#
# 容器布局（小端、紧凑排列）：
#   [ 0,  4) magic "ZSDB"
#   [ 4,  8) formatVersion u32（当前为 1）
#   [ 8, 16) entryNum      u64
#   [16, 24) dictOffset    u64   [24, 32) dictLength   u64
#   [32, 40) entryOffset   u64   [40, 48) entryLength   u64
#   [48, 56) fileNameOffset u64  [56, 64) fileNameLength u64
#   [64, 72) streamOffset  u64   [72, 80) streamLength  u64
#
# entry 表与文件名表都以 zstd 压缩形式存放，数据块按 entry 的 attribute 位决定是否压缩。
# 每条 entry 32 字节：offset u64 / length u64 / nameOffset u64 / attribute u64。
# attribute bit0 = F_COMPRESSED。
#
# 文件名格式与 tools/godotworldres/src/main.cpp:497-500 保持一致：
#   "%08X" + dx符号 + dy符号 + "%04X"(|dx|) + "%04X"(|dy|) + ".PNG"
#   符号位为 '0' 表示负，其它表示正。
#
# 生产环境的 12 个纹理包里只有 monster/proguse/magic/map 存在极少量压缩块
# （monster 28/82820、proguse 8/1633、magic 4/8253、map 1092/132497），
# 其余全部是裸 PNG，因此这里的解压分支是冷路径。

const MAGIC := "ZSDB"
const FORMAT_VERSION := 1
const HEADER_SIZE := 80
const ENTRY_SIZE := 32
const ENTRY_FLAG_COMPRESSED := 1
const MAX_INFLATE_SIZE := 64 * 1024 * 1024
const MAX_BLOCK_SIZE := 16 * 1024 * 1024

var path := ""
var entry_count := 0
var last_error := ""

var _file: FileAccess = null
var _stream_offset := 0
var _stream_length := 0
var _slot_offset := PackedInt64Array()
var _slot_length := PackedInt64Array()
var _slot_attribute := PackedInt64Array()
var _slot_dx := PackedInt32Array()
var _slot_dy := PackedInt32Array()
var _slot_by_key: Dictionary = {}


func open(source_path: String) -> bool:
	close()
	path = source_path
	_file = FileAccess.open(source_path, FileAccess.READ)
	if _file == null:
		last_error = "无法打开 ZSDB：%s（%s）" % [source_path, error_string(FileAccess.get_open_error())]
		return false

	var header := _file.get_buffer(HEADER_SIZE)
	if header.size() != HEADER_SIZE:
		return _reject("ZSDB 头部不完整：%s" % source_path)
	if header.slice(0, 4).get_string_from_ascii() != MAGIC:
		return _reject("ZSDB 魔数不匹配：%s" % source_path)
	var version := int(header.decode_u32(4))
	if version != FORMAT_VERSION:
		return _reject("ZSDB 版本不支持：%s v%d" % [source_path, version])

	var count := int(header.decode_u64(8))
	var dict_length := int(header.decode_u64(24))
	var entry_offset := int(header.decode_u64(32))
	var entry_length := int(header.decode_u64(40))
	var name_offset := int(header.decode_u64(48))
	var name_length := int(header.decode_u64(56))
	_stream_offset = int(header.decode_u64(64))
	_stream_length = int(header.decode_u64(72))

	if dict_length != 0:
		# Godot 内置 zstd 不支持字典解压，遇到带字典的包必须显式失败而不是静默返回空数据。
		return _reject("ZSDB 使用了 zstd 字典，当前读取器不支持：%s" % source_path)
	if count <= 0 or count > 4000000:
		return _reject("ZSDB 条目数异常：%s entryNum=%d" % [source_path, count])

	var file_length := _file.get_length()
	if entry_offset <= 0 or entry_length <= 0 or name_offset <= 0 or name_length <= 0:
		return _reject("ZSDB 段偏移异常：%s" % source_path)
	if entry_offset + entry_length > file_length or name_offset + name_length > file_length:
		return _reject("ZSDB 段越界：%s" % source_path)
	if _stream_offset + _stream_length > file_length:
		return _reject("ZSDB 数据区越界：%s" % source_path)

	var entry_table := _read_inflated(entry_offset, entry_length, count * ENTRY_SIZE + 8192)
	if entry_table.is_empty():
		return _reject("ZSDB entry 表解压失败：%s（%s）" % [source_path, last_error])

	@warning_ignore("integer_division")
	var record_count := entry_table.size() / ENTRY_SIZE
	if record_count <= 0:
		return _reject("ZSDB entry 表为空：%s" % source_path)

	var name_blob := _read_inflated(name_offset, name_length, maxi(4096, count * 32))
	if name_blob.is_empty():
		return _reject("ZSDB 文件名表解压失败：%s（%s）" % [source_path, last_error])

	if not _build_slots(entry_table, record_count, name_blob):
		return _reject("ZSDB 文件名索引构建失败：%s（%s）" % [source_path, last_error])

	return entry_count > 0


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
	entry_count = 0
	_stream_offset = 0
	_stream_length = 0
	_slot_offset = PackedInt64Array()
	_slot_length = PackedInt64Array()
	_slot_attribute = PackedInt64Array()
	_slot_dx = PackedInt32Array()
	_slot_dy = PackedInt32Array()
	_slot_by_key = {}


func has(key: int) -> bool:
	return _slot_by_key.has(key)


func keys() -> Array:
	return _slot_by_key.keys()


func frame_offset(key: int) -> Vector2i:
	var slot := int(_slot_by_key.get(key, -1))
	if slot < 0:
		return Vector2i.ZERO
	return Vector2i(_slot_dx[slot], _slot_dy[slot])


func read(key: int) -> PackedByteArray:
	if _file == null:
		last_error = "ZSDB 未打开：%s" % path
		return PackedByteArray()
	var slot := int(_slot_by_key.get(key, -1))
	if slot < 0:
		return PackedByteArray()

	var offset := _slot_offset[slot]
	var length := _slot_length[slot]
	if offset < 0 or length <= 0 or length > MAX_BLOCK_SIZE or offset + length > _stream_length:
		last_error = "ZSDB 数据块越界：%s key=%08X offset=%d length=%d" % [path, key, offset, length]
		return PackedByteArray()

	_file.seek(_stream_offset + offset)
	var block := _file.get_buffer(length)
	if block.size() != length:
		last_error = "ZSDB 读取不完整：%s key=%08X 期望 %d 实得 %d" % [path, key, length, block.size()]
		return PackedByteArray()

	if _slot_attribute[slot] & ENTRY_FLAG_COMPRESSED:
		block = _inflate(block, length * 8)
		if block.is_empty():
			last_error = "ZSDB 数据块解压失败：%s key=%08X" % [path, key]
	return block


func _build_slots(entry_table: PackedByteArray, record_count: int, name_blob: PackedByteArray) -> bool:
	# 名字表是 NUL 分隔的原始字节。Godot 的 String 内部以 NUL 结尾，无法用 "\u0000" 做分隔符，
	# 因此这里全程在 PackedByteArray 上切分并直接解析十六进制，既不经过 String 也不受编码影响。
	var starts := PackedInt32Array()
	var ends := PackedInt32Array()
	var cursor := 0
	var total := name_blob.size()
	while cursor < total:
		var stop := name_blob.find(0, cursor)
		if stop < 0:
			stop = total
		starts.append(cursor)
		ends.append(stop)
		cursor = stop + 1

	_slot_offset.resize(record_count)
	_slot_length.resize(record_count)
	_slot_attribute.resize(record_count)
	_slot_dx.resize(record_count)
	_slot_dy.resize(record_count)
	_slot_by_key = {}

	# 第一遍：把每条记录的 offset/length/attribute 读出来（与名字配对无关，先填满）。
	for slot in range(record_count):
		var base: int = slot * ENTRY_SIZE
		_slot_offset[slot] = int(entry_table.decode_u64(base))
		_slot_length[slot] = int(entry_table.decode_u64(base + 8))
		_slot_attribute[slot] = int(entry_table.decode_u64(base + 24))
		_slot_dx[slot] = 0
		_slot_dy[slot] = 0

	# 名字按偏移递增，entry 记录里的 nameOffset 指向该缓冲区内的字节偏移。
	# 正常生产包满足“名字顺序 == entry 顺序”，这里走双指针 O(n)；
	# 一旦发现顺序不一致（末尾哨兵记录即属此类）就退回按偏移建索引。
	var ordered := true
	var probe := 0
	for slot in range(record_count):
		var base: int = slot * ENTRY_SIZE
		var name_offset := int(entry_table.decode_u64(base + 16))
		while probe < starts.size() and starts[probe] < name_offset:
			probe += 1
		if probe < starts.size() and starts[probe] == name_offset:
			_name_slot(slot, name_blob, starts[probe], ends[probe])
		else:
			ordered = false
			break

	if not ordered:
		_slot_by_key = {}
		for slot in range(record_count):
			_slot_dx[slot] = 0
			_slot_dy[slot] = 0
		var by_offset := {}
		for i in range(starts.size()):
			by_offset[starts[i]] = i
		for slot in range(record_count):
			var base: int = slot * ENTRY_SIZE
			var index := int(by_offset.get(int(entry_table.decode_u64(base + 16)), -1))
			if index >= 0 and index < starts.size():
				_name_slot(slot, name_blob, starts[index], ends[index])

	entry_count = _slot_by_key.size()
	if entry_count == 0:
		last_error = "没有任何有效文件名"
		return false
	return true


func _name_slot(slot: int, blob: PackedByteArray, start: int, end: int) -> void:
	# 名字格式："%08X" + dx符号 + dy符号 + "%04X"(|dx|) + "%04X"(|dy|) + ".PNG"
	if end - start < 8:
		return
	var key := _hex_value(blob, start, 8)
	if key < 0:
		return
	_slot_by_key[key] = slot
	if end - start >= 18:
		var dx := _hex_value(blob, start + 10, 4)
		var dy := _hex_value(blob, start + 14, 4)
		if dx < 0 or dy < 0:
			return
		_slot_dx[slot] = -dx if blob[start + 8] == 0x30 else dx
		_slot_dy[slot] = -dy if blob[start + 9] == 0x30 else dy


func _hex_value(blob: PackedByteArray, start: int, count: int) -> int:
	var value := 0
	for i in range(count):
		var byte := blob[start + i]
		var nibble := -1
		if byte >= 0x30 and byte <= 0x39:
			nibble = byte - 0x30
		elif byte >= 0x41 and byte <= 0x46:
			nibble = byte - 0x37
		elif byte >= 0x61 and byte <= 0x66:
			nibble = byte - 0x57
		if nibble < 0:
			return -1
		value = (value << 4) | nibble
	return value


func _read_inflated(offset: int, length: int, bound: int) -> PackedByteArray:
	_file.seek(offset)
	var raw := _file.get_buffer(length)
	if raw.size() != length:
		last_error = "段读取不完整：offset=%d length=%d 实得 %d" % [offset, length, raw.size()]
		return PackedByteArray()
	return _inflate(raw, bound)


func _inflate(raw: PackedByteArray, bound: int) -> PackedByteArray:
	if raw.size() < 6 or not _is_zstd_frame(raw):
		return raw
	# Godot 的 decompress_dynamic() 只支持 gzip/DEFLATE/Brotli，zstd 只能走
	# decompress(长度, COMPRESSION_ZSTD)，因此必须先拿到解压后长度；
	# 生产包的 zstd 帧头都写入了 Frame_Content_Size，直接读出来即可。
	var declared := _frame_content_size(raw)
	var limit := clampi(declared if declared > 0 else maxi(bound, 4096), 256, MAX_INFLATE_SIZE)
	var result := raw.decompress(limit, FileAccess.COMPRESSION_ZSTD)
	while result.is_empty() and declared <= 0 and limit < MAX_INFLATE_SIZE:
		limit = mini(limit * 4, MAX_INFLATE_SIZE)
		result = raw.decompress(limit, FileAccess.COMPRESSION_ZSTD)
	if result.is_empty():
		last_error = "zstd 解压失败（声明长度 %d，上限 %d）" % [declared, limit]
	return result


# 解析 zstd 帧头的 Frame_Content_Size（RFC 8878 §3.1.1.1.4）。
# 返回 -1 表示帧头没有写入内容长度。
func _frame_content_size(raw: PackedByteArray) -> int:
	if raw.size() < 6:
		return -1
	var descriptor := raw[4]
	var fcs_flag := (descriptor >> 6) & 0x3
	var single_segment := (descriptor >> 5) & 0x1
	var dict_flag := descriptor & 0x3
	var cursor := 5
	if single_segment == 0:
		cursor += 1
	cursor += [0, 1, 2, 4][dict_flag]
	var field_size := 0
	if fcs_flag == 0:
		field_size = 1 if single_segment == 1 else 0
	else:
		field_size = [0, 2, 4, 8][fcs_flag]
	if field_size == 0 or cursor + field_size > raw.size():
		return -1
	var size := 0
	for i in range(field_size):
		size |= raw[cursor + i] << (8 * i)
	if field_size == 2:
		size += 256
	return size


func _is_zstd_frame(raw: PackedByteArray) -> bool:
	return raw[0] == 0x28 and raw[1] == 0xB5 and raw[2] == 0x2F and raw[3] == 0xFD


func _reject(message: String) -> bool:
	last_error = message
	close()
	return false
