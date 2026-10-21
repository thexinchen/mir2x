extends Node

# ZSDB 读取校验。
#
# 需要两个目录同时存在才能做「逐字节等价」比对：
#   MIR2X_WORLD_RES   = godotworldres 导出的旧目录（sprites/<family>/<KEY>.png + <family>.m2xindex）
#   MIR2X_TEXTURE_RES = install_res 产出的 ZSDB 目录（build/Release/res/texture）
#
# 默认每个家族抽样比对（含首/中/末帧）；设置 MIR2X_ZSDB_FULL_CHECK=1 则比对全部帧。
# 不带旧目录时退化为结构校验（PNG 头 + IHDR + 偏移规则自洽）。

const ResourceStoreScript = preload("res://scripts/resource/resource_store.gd")

const SAMPLE_PER_FAMILY := 64
const PNG_MAGIC := [0x89, 0x50, 0x4E, 0x47]

var _store = null
var _checks := 0
var _full := false


func _ready() -> void:
	_full = OS.get_environment("MIR2X_ZSDB_FULL_CHECK") == "1"
	_store = ResourceStoreScript.new()
	if not _store.configure():
		_fail("资源目录解析失败：%s" % _store.last_error)
		return
	if _store.base_path.is_empty():
		_fail("资源根目录为空")
		return

	print("ZSDB SMOKE: base=%s texture=%s full=%s" % [_store.base_path, _store.texture_path, _full])
	if not _check_sprites():
		return
	if not _check_textures():
		return
	print("ZSDB SMOKE PASS: %d checks, base=%s texture=%s" % [_checks, _store.base_path, _store.texture_path])
	get_tree().quit()


func _check_sprites() -> bool:
	var families := 0
	var keys := 0
	for family in ResourceStoreScript.SPRITE_FAMILIES:
		var archive = _store.sprite_archive(family)
		var archive_path: String = String(_store.texture_path).path_join("%s.zsdb" % family)
		if archive == null:
			if FileAccess.file_exists(archive_path):
				_fail("ZSDB 打开失败：%s（%s）" % [archive_path, _store.last_error])
				return false
			continue
		families += 1
		if archive.entry_count <= 0:
			_fail("%s 条目数为 0" % family)
			return false
		var legacy_index := _load_legacy_index(family)
		if not legacy_index.is_empty():
			if archive.entry_count != legacy_index.size():
				_fail("%s 条目数不一致：zsdb=%d index=%d" % [family, archive.entry_count, legacy_index.size()])
				return false
			for key in legacy_index:
				_checks += 1
				if not archive.has(key):
					_fail("%s 缺少条目：%08X" % [family, key])
					return false
				if archive.frame_offset(key) != legacy_index[key]:
					_fail("%s 偏移不一致：%08X zsdb=%s index=%s" % [family, key, archive.frame_offset(key), legacy_index[key]])
					return false

		var sample := _sample_keys(archive, legacy_index)
		for key in sample:
			keys += 1
			var bytes: PackedByteArray = archive.read(key)
			if bytes.is_empty():
				_fail("%s 读取为空：%08X（%s）" % [family, key, archive.last_error])
				return false
			if not _is_png(bytes):
				_fail("%s 不是 PNG：%08X head=%s" % [family, key, bytes.slice(0, 8).hex_encode()])
				return false
			var legacy_path := "%s/sprites/%s/%08X.png" % [_store.base_path, family, key]
			if not FileAccess.file_exists(legacy_path):
				continue
			var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
			_checks += 1
			if legacy_bytes != bytes:
				_fail("%s 字节不一致：%08X zsdb=%d png=%d" % [family, key, bytes.size(), legacy_bytes.size()])
				return false

	print("ZSDB SMOKE sprites: families=%d keys=%d checks=%d" % [families, keys, _checks])
	return families > 0


func _check_textures() -> bool:
	var archive = _store.texture_archive()
	if archive == null:
		print("ZSDB SMOKE textures: 未找到 map.zsdb，跳过")
		return true
	if archive.entry_count <= 0:
		_fail("map.zsdb 条目数为 0")
		return false
	var sample_keys: Array = archive.keys()
	var picked := 0
	@warning_ignore("integer_division")
	var stride := maxi(1, sample_keys.size() / 32)
	for i in range(0, sample_keys.size(), stride):
		if picked >= 32:
			break
		var key := int(sample_keys[i])
		var bytes: PackedByteArray = archive.read(key)
		if bytes.is_empty() or not _is_png(bytes):
			_fail("map.zsdb 读取失败：%08X（%s）" % [key, archive.last_error])
			return false
		picked += 1
		_checks += 1
		var legacy_path := "%s/textures/%08X.png" % [_store.base_path, key]
		if not FileAccess.file_exists(legacy_path):
			continue
		if FileAccess.get_file_as_bytes(legacy_path) != bytes:
			_fail("map.zsdb 字节不一致：%08X" % key)
			return false
	print("ZSDB SMOKE textures: entries=%d sampled=%d" % [archive.entry_count, picked])
	return true


func _sample_keys(archive, legacy_index: Dictionary) -> Array:
	var source: Array = legacy_index.keys() if not legacy_index.is_empty() else archive.keys()
	if source.is_empty():
		return []
	if _full:
		return source
	var picked: Array = []
	@warning_ignore("integer_division")
	var stride := maxi(1, source.size() / SAMPLE_PER_FAMILY)
	for i in range(0, source.size(), stride):
		picked.append(source[i])
		if picked.size() >= SAMPLE_PER_FAMILY:
			break
	@warning_ignore("integer_division")
	var middle: int = source.size() / 2
	for key in [source[0], source[middle], source[source.size() - 1]]:
		if not picked.has(key):
			picked.append(key)
	return picked


func _load_legacy_index(family: String) -> Dictionary:
	var offsets := {}
	if _store.base_path.is_empty():
		return offsets
	var file := FileAccess.open("%s/sprites/%s.m2xindex" % [_store.base_path, family], FileAccess.READ)
	if file == null:
		return offsets
	if file.get_buffer(4).get_string_from_ascii() != "M2SP":
		return offsets
	if file.get_32() != 1:
		return offsets
	var count := file.get_32()
	for _index in range(count):
		var key := file.get_32()
		var dx := file.get_16()
		var dy := file.get_16()
		if dx & 0x8000:
			dx -= 0x10000
		if dy & 0x8000:
			dy -= 0x10000
		offsets[key] = Vector2i(dx, dy)
	return offsets


func _is_png(bytes: PackedByteArray) -> bool:
	if bytes.size() < 33:
		return false
	for i in range(PNG_MAGIC.size()):
		if bytes[i] != PNG_MAGIC[i]:
			return false
	return bytes.decode_u32(16) > 0 and bytes.decode_u32(20) > 0


func _fail(message: String) -> void:
	push_error("ZSDB_SMOKE %s" % message)
	get_tree().quit(1)
