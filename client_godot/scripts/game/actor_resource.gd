class_name ActorResource
extends RefCounted

const MAGIC := "M2SP"
const ResourceStoreScript = preload("res://scripts/resource/resource_store.gd")

var base_path: String = ""
var offsets: Dictionary = {}
var monster_meta: Dictionary = {}
var monster_names: Dictionary = {}
var item_meta: Dictionary = {}
var item_attributes: Dictionary = {}
var item_details: Dictionary = {}
var item_names: Dictionary = {}
var item_types: Dictionary = {}
var potion_effects: Dictionary = {}
var skill_meta: Dictionary = {}
var buff_meta: Dictionary = {}
var buff_names: Dictionary = {}
var magic_meta: Dictionary = {}
var magic_loop_meta: Dictionary = {}
var magic_names: Dictionary = {}
var magic_ids_by_name: Dictionary = {}
var hero_weapon_orders := PackedByteArray()
var _textures: Dictionary = {}
var _store = null
var _sprite_offset_count := 0


func configure(path: String) -> bool:
	_store = ResourceStoreScript.shared()
	_store.adopt(path)
	base_path = _store.base_path
	var loaded: bool = _store.is_ready()
	_sprite_offset_count = 0
	for family in ResourceStoreScript.SPRITE_FAMILIES:
		var archive = _store.sprite_archive(family)
		if archive != null:
			_sprite_offset_count += archive.entry_count
		else:
			# 兼容旧的解包目录：没有 ZSDB 时退回 .m2xindex + PNG。
			loaded = _load_index(family) or loaded
	_load_hero_weapon_orders()
	_load_monster_meta()
	_load_monster_names()
	_load_item_meta()
	_load_item_details()
	_load_item_names()
	_load_item_types()
	_load_potion_effects()
	_load_skill_meta()
	_load_buff_meta()
	_load_buff_names()
	_load_magic_meta("magic.m2xmeta", magic_meta)
	magic_loop_meta.clear()
	_load_magic_meta("magic_loop.m2xmeta", magic_loop_meta)
	_load_magic_names()
	return loaded


func configure_default() -> bool:
	_store = ResourceStoreScript.shared()
	if not _store.is_ready() and not _store.configure():
		return false
	return configure(_store.base_path)


func sprite_offset_count() -> int:
	return _sprite_offset_count if _sprite_offset_count > 0 else offsets.size()


func frame(family: String, key: int) -> Dictionary:
	var cache_key := "%s:%08X" % [family, key]
	if _textures.has(cache_key):
		return _textures[cache_key]
	if _store == null:
		_store = ResourceStoreScript.shared()
	var source: Dictionary = _store.sprite_frame(family, key)
	if source.is_empty():
		_textures[cache_key] = {}
		return {}
	var image := Image.new()
	if image.load_png_from_buffer(source["bytes"]) != OK:
		_textures[cache_key] = {}
		return {}
	var result := {"texture": ImageTexture.create_from_image(image), "offset": source["offset"]}
	_textures[cache_key] = result
	return result


func monster_look(monster_id: int) -> int:
	return monster_meta.get(monster_id, PackedInt32Array([monster_id, 1]))[0]


func monster_has_shadow(monster_id: int) -> bool:
	return bool(monster_meta.get(monster_id, PackedInt32Array([monster_id, 1]))[1])


func monster_dead_fade_out(monster_id: int) -> bool:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta.size() >= 7 and bool(meta[6])


func monster_spawn_look(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[7] if meta.size() >= 8 else 0


func monster_death_magic_id(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[19] if meta.size() >= 20 else 0


func monster_attack_motion_magic_id(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[20] if meta.size() >= 21 else 0


func monster_transform_effect_magic_id(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[21] if meta.size() >= 22 else 0


func monster_spawn_effect_magic_id(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[22] if meta.size() >= 23 else 0


func monster_spawn_direction(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[31] if meta.size() >= 32 else 0


func monster_behave_mode(monster_id: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	return meta[33] if meta.size() >= 34 else 0


func monster_body_sequence(monster_id: int, action_type: int, magic_id := 0) -> PackedInt32Array:
	var sequence: PackedInt32Array
	match action_type:
		3, 5: sequence = PackedInt32Array([1, 6, -1])
		7: sequence = PackedInt32Array([2, 6, -1])
		11: sequence = PackedInt32Array([3, 2, -1])
		13: sequence = PackedInt32Array([4, 10, -1])
		9: sequence = PackedInt32Array([6, 10, -1])
		1: sequence = PackedInt32Array([8, 10, -1])
		_: sequence = PackedInt32Array([0, 4, -1])
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	if meta.size() < 32:
		return sequence
	var flags := int(meta[30])
	if bool(flags & 1) and action_type != 11:
		sequence[0] = meta[23] if meta[24] > 0 else 0
		sequence[1] = meta[24] if meta[24] > 0 else 4
	elif action_type == 2 and meta[24] > 0:
		sequence[0] = meta[23]
		sequence[1] = meta[24]
	elif action_type == 7:
		if meta[27] > 0 and magic_id == meta[27]:
			sequence[0] = meta[28]
			sequence[1] = meta[29]
		elif meta[26] > 0:
			sequence[0] = meta[25]
			sequence[1] = meta[26]
	if bool(flags & 2):
		sequence[2] = 0
	return sequence


func monster_transform(monster_id: int) -> Dictionary:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	if meta.size() < 19 or meta[14] <= 0:
		return {}
	var flags := int(meta[18])
	return {
		"hidden_look": meta[8],
		"hidden_stand": PackedInt32Array([meta[9], meta[10], meta[11]]),
		"active_transform": PackedInt32Array([meta[12], meta[13], meta[14]]),
		"hidden_transform": PackedInt32Array([meta[15], meta[16], meta[17]]),
		"active_reverse": bool(flags & 1),
		"hidden_reverse": bool(flags & 2),
		"hidden_focusable": bool(flags & 4),
		"fixed_direction": bool(flags & 8),
		"reveal_on_hit": bool(flags & 16),
	}


func monster_motion_correction(monster_id: int, action_type: int) -> bool:
	var transform: Dictionary = monster_transform(monster_id)
	if transform.is_empty():
		return action_type in [2, 3, 7, 11]
	if action_type == 3:
		return true
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	var flags := int(meta[32]) if meta.size() >= 33 else 0
	if action_type == 2:
		return bool(flags & 1)
	if action_type == 7:
		return bool(flags & 2)
	if action_type == 11:
		return not bool(transform.get("reveal_on_hit", false))
	return false


func monster_seff(monster_id: int, action_type: int) -> int:
	var meta: PackedInt32Array = monster_meta.get(monster_id, PackedInt32Array())
	if meta.size() < 6:
		return 0xFFFFFFFF
	match action_type:
		1: return meta[2]
		7: return meta[3]
		11: return meta[4]
		13: return meta[5]
	return 0xFFFFFFFF


func item_shape(item_id: int) -> int:
	return item_meta.get(item_id, PackedInt32Array([0, 0]))[0]


func item_package_gfx_id(item_id: int) -> int:
	return item_meta.get(item_id, PackedInt32Array([0, 0]))[1]


func item_is_packable(item_id: int) -> bool:
	return bool(item_meta.get(item_id, PackedInt32Array([0, 0, 0]))[2])


func item_attribute(item_id: int) -> Dictionary:
	return item_attributes.get(item_id, {})


func item_weapon_sound(item_id: int) -> int:
	return item_attribute(item_id).get("weapon_sound", 7)


func item_can_mine(item_id: int) -> bool:
	return bool(item_attribute(item_id).get("mine", false))


func item_weight(item_id: int) -> int:
	return item_attribute(item_id).get("weight", 0)


func item_detail(item_id: int) -> Dictionary:
	return item_details.get(item_id, {})


func item_name(item_id: int) -> String:
	return item_names.get(item_id, "物品 %d" % item_id)


func item_potion_effect(item_id: int) -> Dictionary:
	return potion_effects.get(item_id, {})


func item_type(item_id: int) -> String:
	return item_types.get(item_id, "")


func item_can_wear(item_id: int, location: int, gender: bool) -> bool:
	var expected := {
		1: ["衣服"], 2: ["头盔"], 3: ["武器"], 4: ["鞋"], 5: ["项链"],
		6: ["手镯"], 7: ["手镯"], 8: ["戒指"], 9: ["戒指"], 10: ["火把"],
		11: ["魅力", "护身符", "药粉"],
	}
	if item_type(item_id) not in expected.get(location, []):
		return false
	if location != 1:
		return true
	var name := item_name(item_id)
	if "（男）" in name:
		return gender
	if "（女）" in name:
		return not gender
	return false


func item_sound_effect(item_id: int) -> int:
	if item_id <= 0:
		return 0xFFFFFFFF
	match item_type(item_id):
		"恢复药水", "功能药水", "强效药水": return 0x0102006C
		"武器": return 0x0102006F
		"衣服": return 0x01020070
		"戒指": return 0x01020071
		"手镯": return 0x01020072
		"项链": return 0x01020073
		"头盔": return 0x01020074
		"勋章": return 0x01020075
		_: return 0x01020076


func item_icon(item_id: int) -> Dictionary:
	var package_gfx_id := item_package_gfx_id(item_id)
	var icon := frame("item", package_gfx_id | 0x02000000)
	return frame("item", package_gfx_id | 0x01000000) if icon.is_empty() else icon


func secured_item_icon(item_id: int) -> Dictionary:
	return frame("item", item_package_gfx_id(item_id) | 0x02000000)


func ground_item(item_id: int) -> Dictionary:
	return frame("item", item_package_gfx_id(item_id))


func skill_layout(magic_id: int) -> PackedInt32Array:
	return skill_meta.get(magic_id, PackedInt32Array())


func buff_layout(buff_id: int) -> PackedInt32Array:
	return buff_meta.get(buff_id, PackedInt32Array())


func monster_name(monster_id: int) -> String:
	return monster_names.get(monster_id, "")


func buff_name(buff_id: int) -> String:
	return buff_names.get(buff_id, "")


func magic_layout(magic_id: int, stage: int) -> PackedInt32Array:
	return magic_meta.get(magic_id * 8 + stage, PackedInt32Array())


func magic_loop_layout(magic_id: int, stage: int) -> PackedInt32Array:
	return magic_loop_meta.get(magic_id * 8 + stage, PackedInt32Array())


func magic_seff(magic_id: int, stage: int) -> int:
	var meta := magic_layout(magic_id, stage)
	return meta[8] if meta.size() >= 9 else 0xFFFFFFFF


func magic_target_offset(magic_id: int, stage: int, direction: int) -> Vector2i:
	var meta := magic_layout(magic_id, stage)
	var index := 9 + clampi(direction, 0, 15) * 2
	if meta.size() <= index + 1:
		return Vector2i.ZERO
	return Vector2i(meta[index], meta[index + 1])


func magic_cast_motion(magic_id: int) -> int:
	var meta := magic_layout(magic_id, 1)
	if meta.size() >= 42 and meta[41] in [3, 4, 8]:
		return meta[41] - 1
	return 2


func magic_id(name: String) -> int:
	return magic_ids_by_name.get(name, 0)


func hero_weapon_order(gfx_motion: int, direction: int, frame_index: int) -> int:
	if gfx_motion < 0 or gfx_motion >= 33 or direction < 1 or direction > 8 or frame_index < 0 or frame_index >= 10:
		return -1
	var index := gfx_motion * 80 + (direction - 1) * 10 + frame_index
	return hero_weapon_orders[index] if hero_weapon_orders.size() == 2640 else 0


func _load_index(family: String) -> bool:
	var file := FileAccess.open("%s/sprites/%s.m2xindex" % [base_path, family], FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return false
	if file.get_32() != 1:
		return false
	var count := file.get_32()
	for _index in range(count):
		var key := file.get_32()
		var dx := file.get_16()
		var dy := file.get_16()
		if dx & 0x8000:
			dx -= 0x10000
		if dy & 0x8000:
			dy -= 0x10000
		offsets["%s:%08X" % [family, key]] = Vector2i(dx, dy)
	return true


func _load_hero_weapon_orders() -> void:
	hero_weapon_orders.clear()
	var file := FileAccess.open("%s/sprites/weapon_order.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1 or file.get_32() != 2640:
		return
	var values := file.get_buffer(2640)
	if values.size() == 2640:
		hero_weapon_orders = values


func _load_monster_meta() -> void:
	var file := FileAccess.open("%s/sprites/monster.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	var version := file.get_32()
	if version not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]:
		return
	var count := file.get_32()
	for _index in range(count):
		var monster_id := file.get_32()
		var look_id := file.get_16()
		var shadow := file.get_8()
		var flags := file.get_8()
		var meta := PackedInt32Array([look_id, shadow])
		if version >= 2:
			for _seff_index in range(4):
				meta.append(file.get_32())
		if version >= 3:
			meta.append(flags & 1)
		if version >= 4:
			meta.append(file.get_16())
		if version >= 5:
			meta.append(file.get_16())
			for _transform_index in range(10):
				meta.append(file.get_8())
		if version >= 6:
			meta.append(file.get_32())
		if version >= 7:
			meta.append(file.get_32())
		if version >= 8:
			meta.append(file.get_32())
		if version >= 9:
			meta.append(file.get_32())
		if version >= 10:
			for _body_index in range(4):
				meta.append(file.get_8())
			meta.append(file.get_32())
			for _body_index in range(4):
				meta.append(file.get_8())
		if version >= 11:
			meta.append(file.get_8())
		if version >= 12:
			meta.append(file.get_8())
		monster_meta[monster_id] = meta


func _load_monster_names() -> void:
	var file := FileAccess.open("%s/sprites/monster_name.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var monster_id := file.get_32()
		var length := file.get_16()
		monster_names[monster_id] = file.get_buffer(length).get_string_from_utf8()


func _load_item_meta() -> void:
	var file := FileAccess.open("%s/sprites/item.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	var version := file.get_32()
	if version not in [1, 2, 3, 4, 5]:
		return
	var count := file.get_32()
	for _index in range(count):
		var item_id := file.get_32()
		var shape := file.get_16()
		var flags := file.get_16()
		var package_gfx_id := file.get_32()
		item_meta[item_id] = PackedInt32Array([shape, package_gfx_id, flags])
		if version >= 2:
			item_attributes[item_id] = {
				"weight": _read_s32(file),
				"dc": _read_pair(file),
				"mc": _read_pair(file),
				"sc": _read_pair(file),
				"ac": _read_pair(file),
				"mac": _read_pair(file),
				"dc_hit": _read_s32(file),
				"mc_hit": _read_s32(file),
				"dc_dodge": _read_s32(file),
				"mc_dodge": _read_s32(file),
				"speed": _read_s32(file),
				"comfort": _read_s32(file),
				"luck_curse": _read_s32(file),
				"dc_elem": _read_values(file, 7),
				"ac_elem": _read_values(file, 7),
				"load": _read_values(file, 3),
			}
			if version >= 3:
				item_attributes[item_id]["double_hand"] = file.get_8() != 0
				if version >= 4:
					item_attributes[item_id]["weapon_sound"] = file.get_8()
					if version >= 5:
						item_attributes[item_id]["mine"] = file.get_8() != 0
						file.get_8()
					else:
						file.get_buffer(2)
				else:
					file.get_buffer(3)


func _read_s32(file: FileAccess) -> int:
	var value := file.get_32()
	return value - 0x100000000 if value >= 0x80000000 else value


func _read_pair(file: FileAccess) -> PackedInt32Array:
	return PackedInt32Array([_read_s32(file), _read_s32(file)])


func _read_values(file: FileAccess, count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for _index in range(count):
		result.append(_read_s32(file))
	return result


func _load_item_details() -> void:
	var file := FileAccess.open("%s/sprites/item_detail.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var item_id := file.get_32()
		var detail := {
			"duration": _read_s32(file),
			"hp": _read_values(file, 3),
			"mp": _read_values(file, 3),
			"req": _read_values(file, 4),
		}
		var description_length := file.get_16()
		detail["description"] = file.get_buffer(description_length).get_string_from_utf8()
		var job_length := file.get_16()
		detail["job"] = file.get_buffer(job_length).get_string_from_utf8()
		item_details[item_id] = detail


func _load_item_names() -> void:
	var file := FileAccess.open("%s/sprites/item_name.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var item_id := file.get_32()
		var length := file.get_16()
		item_names[item_id] = file.get_buffer(length).get_string_from_utf8()


func _load_item_types() -> void:
	var file := FileAccess.open("%s/sprites/item_type.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var item_id := file.get_32()
		var length := file.get_16()
		item_types[item_id] = file.get_buffer(length).get_string_from_utf8()


func _load_potion_effects() -> void:
	potion_effects.clear()
	var file := FileAccess.open("%s/sprites/potion_effect.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_length() < 12 or file.get_buffer(4).get_string_from_ascii() != MAGIC or file.get_32() != 1:
		return
	var count := file.get_32()
	if file.get_length() != 12 + count * 60: return
	var loaded := {}
	for _index in count:
		var item_id := file.get_32()
		var effect := {"buff_id": file.get_32(), "flags": file.get_32(), "hp": _read_values(file, 2), "mp": _read_values(file, 2), "hp_pulse": _read_values(file, 4), "mp_pulse": _read_values(file, 4)}
		if item_id == 0 or loaded.has(item_id): return
		loaded[item_id] = effect
	potion_effects = loaded


func _load_skill_meta() -> void:
	var file := FileAccess.open("%s/sprites/skill.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	var version := file.get_32()
	if version not in [1, 2]:
		return
	var count := file.get_32()
	for _index in range(count):
		var magic_id := file.get_32()
		var icon_id := file.get_32()
		var cool_down := file.get_32() if version >= 2 else 0
		var page := file.get_8()
		var x := file.get_8()
		var y := file.get_8()
		var flags := file.get_8()
		skill_meta[magic_id] = PackedInt32Array([icon_id, page, x, y, flags, cool_down])


func _load_buff_meta() -> void:
	var file := FileAccess.open("%s/sprites/buff.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var buff_id := file.get_32()
		var icon_id := file.get_32()
		var favor := file.get_8()
		if favor & 0x80:
			favor -= 0x100
		file.get_buffer(3)
		buff_meta[buff_id] = PackedInt32Array([icon_id, favor])


func _load_buff_names() -> void:
	var file := FileAccess.open("%s/sprites/buff_name.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var buff_id := file.get_32()
		var length := file.get_16()
		buff_names[buff_id] = file.get_buffer(length).get_string_from_utf8()


func _load_magic_meta(filename: String, destination: Dictionary) -> void:
	var file := FileAccess.open("%s/sprites/%s" % [base_path, filename], FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	var version := file.get_32()
	if version not in [1, 2, 3, 4, 5]:
		return
	var count := file.get_32()
	for _index in range(count):
		var magic_id := file.get_32()
		var gfx_id := file.get_32()
		var mod_color := file.get_32()
		var frame_count := file.get_16()
		var gfx_id_count := file.get_16()
		var speed := file.get_16()
		var stage := file.get_8()
		var type := file.get_8()
		var gfx_dir_type := file.get_8()
		var flags := file.get_8()
		var meta := PackedInt32Array([
			gfx_id, mod_color, frame_count, gfx_id_count, speed, type, gfx_dir_type, flags,
		])
		if version >= 2:
			meta.append(file.get_32())
		if version >= 4:
			for _offset_index in 32:
				var target_offset := file.get_16()
				meta.append(target_offset - 0x10000 if target_offset >= 0x8000 else target_offset)
		if version >= 5:
			meta.append(file.get_8())
		destination[magic_id * 8 + stage] = meta


func _load_magic_names() -> void:
	var file := FileAccess.open("%s/sprites/magic_name.m2xmeta" % base_path, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return
	if file.get_32() != 1:
		return
	var count := file.get_32()
	for _index in range(count):
		var id := file.get_32()
		var length := file.get_16()
		var name := file.get_buffer(length).get_string_from_utf8()
		magic_names[id] = name
		magic_ids_by_name[name] = id
