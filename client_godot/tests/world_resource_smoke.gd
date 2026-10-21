extends Node

const WorldResourceScript = preload("res://scripts/game/world_resource.gd")
const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const WorldRendererScript = preload("res://scripts/game/world_renderer.gd")


class MapTextureProbe extends RefCounted:
	var objects: Array[Dictionary] = [{}, {}, {}, {}]
	var requested_texture_id := -1

	func texture(texture_id: int) -> Texture2D:
		requested_texture_id = texture_id
		return null


func _ready() -> void:
	var world: RefCounted = WorldResourceScript.new()
	if not world.load_map(24):
		_fail(world.last_error)
		return
	if world.width != 600 or world.height != 600 or world.tiles.size() != 89993:
		_fail("unexpected map data: %dx%d tiles=%d" % [world.width, world.height, world.tiles.size()])
		return
	if world.minimap_id != 0x19001003:
		_fail("unexpected minimap ID: %08X" % world.minimap_id)
		return
	if world.map_name != "道馆":
		_fail("unexpected map name: %s" % world.map_name)
		return
	if world.bgm_id != 0x00010002:
		_fail("unexpected BGM ID: %08X" % world.bgm_id)
		return
	if not await _test_map_object_animation_gate():
		return
	var first_texture_id: int = world.tiles.values()[0]
	if world.texture(first_texture_id) == null:
		_fail("failed to decode map texture %08X" % first_texture_id)
		return
	var actors: RefCounted = ActorResourceScript.new()
	if not actors.configure(world.base_path):
		_fail("failed to load actor indices")
		return
	if actors.sprite_offset_count() < 345000 or actors.monster_look(224) <= 0 or actors.item_meta.size() < 1000:
		_fail("incomplete actor indices")
		return
	if actors.item_details.size() != actors.item_meta.size() or actors.buff_names.is_empty():
		_fail("item-detail or buff-name metadata incomplete")
		return
	var spell1_motion_count := 0
	var attack_mode_motion_count := 0
	for magic_id_value in actors.magic_names:
		var startup_meta: PackedInt32Array = actors.magic_layout(int(magic_id_value), 1)
		if startup_meta.size() < 42:
			continue
		spell1_motion_count += 1 if startup_meta[41] == 4 else 0
		attack_mode_motion_count += 1 if startup_meta[41] == 8 else 0
	if spell1_motion_count != 29 or attack_mode_motion_count != 3:
		_fail("magic meta v5 cast-motion count mismatch: spell1=%d attack_mode=%d" % [spell1_motion_count, attack_mode_motion_count])
		return
	if actors.magic_cast_motion(actors.magic_id("火球术")) != 2 or actors.magic_cast_motion(actors.magic_id("治愈术")) != 3 or actors.magic_cast_motion(actors.magic_id("铁布衫")) != 7:
		_fail("magic meta v5 cast-motion identities mismatch")
		return
	var durable_item_count := 0
	var described_item_count := 0
	for item_id_value in actors.item_details:
		var detail: Dictionary = actors.item_detail(int(item_id_value))
		durable_item_count += 1 if int(detail.get("duration", 0)) > 0 else 0
		described_item_count += 1 if not str(detail.get("description", "")).is_empty() else 0
	if durable_item_count == 0 or described_item_count == 0:
		_fail("item-detail metadata lacks durable or described records")
		return
	if actors.monster_seff(224, 7) == 0xFFFFFFFF:
		_fail("monster SEFF metadata unavailable")
		return
	var special_spawn_count := 0
	for monster_id_value in actors.monster_meta:
		special_spawn_count += 1 if actors.monster_spawn_look(int(monster_id_value)) > 0 else 0
	if special_spawn_count != 1:
		_fail("monster meta v4 special spawn look mismatch: %d" % special_spawn_count)
		return
	var transform_count := 0
	var hidden_focusable_count := 0
	var reveal_on_hit_count := 0
	for monster_id_value in actors.monster_meta:
		var transform: Dictionary = actors.monster_transform(int(monster_id_value))
		if transform.is_empty():
			continue
		transform_count += 1
		hidden_focusable_count += 1 if transform.hidden_focusable else 0
		reveal_on_hit_count += 1 if transform.reveal_on_hit else 0
		if transform.hidden_stand[2] <= 0 or transform.active_transform[2] <= 0 or transform.hidden_transform[2] <= 0:
			_fail("monster meta v5 contains an empty transformation sequence")
			return
	if transform_count != 10 or hidden_focusable_count != 1 or reveal_on_hit_count != 1:
		_fail("monster meta v5 transformation rules mismatch: transform=%d hidden_focusable=%d reveal_on_hit=%d" % [transform_count, hidden_focusable_count, reveal_on_hit_count])
		return
	var death_magic_count := 0
	for monster_id_value in actors.monster_meta:
		var death_magic_id: int = actors.monster_death_magic_id(int(monster_id_value))
		if death_magic_id <= 0:
			continue
		death_magic_count += 1
		if actors.magic_layout(death_magic_id, 2).is_empty():
			_fail("monster meta v6 references missing death magic: monster=%d magic=%d" % [monster_id_value, death_magic_id])
			return
	if death_magic_count != 11:
		_fail("monster meta v6 death magic count mismatch: %d" % death_magic_count)
		return
	var attack_motion_magic_count := 0
	for monster_id_value in actors.monster_meta:
		var attack_motion_magic_id: int = actors.monster_attack_motion_magic_id(int(monster_id_value))
		if attack_motion_magic_id <= 0:
			continue
		attack_motion_magic_count += 1
		if actors.magic_names.get(attack_motion_magic_id, "") != "霸王教主_火刃" or actors.magic_layout(attack_motion_magic_id, 2).is_empty():
			_fail("monster meta v7 references invalid attack motion magic: monster=%d magic=%d" % [monster_id_value, attack_motion_magic_id])
			return
	if attack_motion_magic_count != 1:
		_fail("monster meta v7 attack motion magic count mismatch: %d" % attack_motion_magic_count)
		return
	var transform_effect_magic_count := 0
	for monster_id_value in actors.monster_meta:
		var transform_effect_magic_id: int = actors.monster_transform_effect_magic_id(int(monster_id_value))
		if transform_effect_magic_id <= 0:
			continue
		transform_effect_magic_count += 1
		if actors.magic_names.get(transform_effect_magic_id, "") != "祖玛教主_石像碎片" or actors.magic_layout(transform_effect_magic_id, 2).is_empty():
			_fail("monster meta v8 references invalid transform effect: monster=%d magic=%d" % [monster_id_value, transform_effect_magic_id])
			return
	if transform_effect_magic_count != 1:
		_fail("monster meta v8 transform effect count mismatch: %d" % transform_effect_magic_count)
		return
	var spawn_effect_names: Array[String] = []
	for monster_id_value in actors.monster_meta:
		var spawn_effect_magic_id: int = actors.monster_spawn_effect_magic_id(int(monster_id_value))
		if spawn_effect_magic_id > 0:
			spawn_effect_names.append(actors.magic_names.get(spawn_effect_magic_id, ""))
			var spawn_meta: PackedInt32Array = actors.magic_layout(spawn_effect_magic_id, 2)
			if spawn_meta.is_empty() or spawn_meta[2] != 1 or spawn_meta[6] <= 1:
				_fail("monster meta v9 references invalid directional spawn remnant: monster=%d magic=%d meta=%s" % [monster_id_value, spawn_effect_magic_id, spawn_meta])
				return
	spawn_effect_names.sort()
	if spawn_effect_names != ["僧侣僵尸_地洞", "沙漠石人_石坑"]:
		_fail("monster meta v9 special ground effects mismatch: %s" % spawn_effect_names)
		return
	var physical_magic_id: int = actors.magic_id("物理攻击")
	var savage_magic_id: int = actors.magic_id("霸王教主_野蛮冲撞")
	var stand_body_override_count := 0
	var attack_body_override_count := 0
	var fixed_body_direction_count := 0
	var tree_body_count := 0
	var spawn_direction_count := 0
	var alternate_attack_count := 0
	for monster_id_value in actors.monster_meta:
		var monster_id: int = monster_id_value
		var look_id: int = actors.monster_look(monster_id)
		var stand_sequence: PackedInt32Array = actors.monster_body_sequence(monster_id, 2)
		var attack_sequence: PackedInt32Array = actors.monster_body_sequence(monster_id, 7, physical_magic_id)
		var savage_sequence: PackedInt32Array = actors.monster_body_sequence(monster_id, 7, savage_magic_id)
		if stand_sequence != PackedInt32Array([0, 4, -1]):
			stand_body_override_count += 1
			var stand_direction := stand_sequence[2] if stand_sequence[2] >= 0 else 0
			var stand_key := (look_id << 12) | (stand_sequence[0] << 8) | (stand_direction << 5) | (stand_sequence[1] - 1)
			if stand_sequence[1] <= 0 or actors.frame("monster", stand_key).is_empty():
				_fail("monster meta v10 stand sequence references a missing frame: monster=%d sequence=%s" % [monster_id, stand_sequence])
				return
		if attack_sequence != PackedInt32Array([2, 6, -1]):
			attack_body_override_count += 1
			var attack_direction := attack_sequence[2] if attack_sequence[2] >= 0 else 0
			var attack_key := (look_id << 12) | (attack_sequence[0] << 8) | (attack_direction << 5) | (attack_sequence[1] - 1)
			if attack_sequence[1] <= 0 or actors.frame("monster", attack_key).is_empty():
				_fail("monster meta v10 attack sequence references a missing frame: monster=%d sequence=%s" % [monster_id, attack_sequence])
				return
		fixed_body_direction_count += 1 if stand_sequence[2] == 0 else 0
		tree_body_count += 1 if actors.monster_body_sequence(monster_id, 13) == PackedInt32Array([0, 4, 0]) else 0
		spawn_direction_count += 1 if actors.monster_spawn_direction(monster_id) == 6 else 0
		alternate_attack_count += 1 if attack_sequence == PackedInt32Array([2, 10, -1]) and savage_sequence == PackedInt32Array([6, 10, -1]) else 0
	if physical_magic_id <= 0 or savage_magic_id <= 0 or stand_body_override_count != 6 or attack_body_override_count != 7 or fixed_body_direction_count != 4 or tree_body_count != 3 or spawn_direction_count != 2 or alternate_attack_count != 1:
		_fail("monster meta v10 body profiles mismatch: stand=%d attack=%d fixed=%d tree=%d spawn_dir=%d alternate=%d" % [stand_body_override_count, attack_body_override_count, fixed_body_direction_count, tree_body_count, spawn_direction_count, alternate_attack_count])
		return
	var fade_monster_count := 0
	var persistent_corpse_count := 0
	for monster_id_value in actors.monster_meta:
		if actors.monster_dead_fade_out(int(monster_id_value)):
			fade_monster_count += 1
		else:
			persistent_corpse_count += 1
	if fade_monster_count == 0 or persistent_corpse_count == 0:
		_fail("monster meta v3 death lifecycle flags unavailable")
		return
	var magic_seff_count := 0
	var magic_target_offset_count := 0
	for meta_value in actors.magic_meta.values():
		var meta: PackedInt32Array = meta_value
		magic_seff_count += 1 if meta.size() >= 9 and meta[8] != 0xFFFFFFFF else 0
		if meta.size() >= 41:
			for offset_index in range(9, 41):
				magic_target_offset_count += 1 if meta[offset_index] != 0 else 0
	if magic_seff_count == 0:
		_fail("magic-stage SEFF metadata unavailable")
		return
	if magic_target_offset_count == 0:
		_fail("magic target-offset metadata v4 unavailable")
		return
	var weapon_sound_count := 0
	var mine_weapon_count := 0
	for attributes_value in actors.item_attributes.values():
		var attributes: Dictionary = attributes_value
		weapon_sound_count += 1 if attributes.get("weapon_sound", 7) < 7 else 0
		mine_weapon_count += 1 if attributes.get("mine", false) else 0
	if weapon_sound_count == 0:
		_fail("weapon sound metadata unavailable")
		return
	if mine_weapon_count == 0:
		_fail("item meta v5 did not export mine-capable weapons")
		return
	print("WORLD RESOURCE PASS: map=%d size=%dx%d tiles=%d actor_frames=%d magic_seff=%d magic_target_offsets=%d fade_monster=%d persistent_corpse=%d special_spawn=%d transform=%d death_magic=%d transform_effect=%d weapon_sound=%d mine_weapon=%d durable=%d described=%d buffs=%d" % [world.map_id, world.width, world.height, world.tiles.size(), actors.sprite_offset_count(), magic_seff_count, magic_target_offset_count, fade_monster_count, persistent_corpse_count, special_spawn_count, transform_count, death_magic_count, transform_effect_magic_count, weapon_sound_count, mine_weapon_count, durable_item_count, described_item_count, actors.buff_names.size()])
	get_tree().quit()


func _test_map_object_animation_gate() -> bool:
	var affected_world: RefCounted = WorldResourceScript.new()
	if not affected_world.load_map(95):
		_fail("unable to load affected map 95: %s" % affected_world.last_error)
		return false
	var key: int = 22 + 12 * int(affected_world.width)
	var affected_record := PackedInt32Array()
	for record_value in affected_world.objects[1].get(key, []):
		var record: PackedInt32Array = record_value
		if record[0] == 0x000C34AF and (record[1] & 1) != 0 and record[3] == 8:
			affected_record = record
			break
	if affected_record.is_empty() or affected_world.texture(0x000C34B0) != null:
		_fail("affected outside-whitelist map object fixture is unavailable")
		return false
	while floori(float(Time.get_ticks_msec()) / 200.0) % 8 in [0, 7]:
		await get_tree().process_frame
	var expected_frame := floori(float(Time.get_ticks_msec()) / 200.0) % 8
	var renderer: Control = WorldRendererScript.new()
	var probe := MapTextureProbe.new()
	probe.objects[1][0] = [affected_record]
	renderer.world_resource = probe
	renderer.map_width = 1
	renderer.call("_draw_object_row", 1, 0, 0, 0, 0, 0)
	if probe.requested_texture_id != affected_record[0]:
		renderer.free()
		_fail("outside-whitelist map object incorrectly animated to %08X" % probe.requested_texture_id)
		return false
	var whitelisted_record := PackedInt32Array([0x000B0100, 1, 1, 8])
	probe.objects[1][0] = [whitelisted_record]
	renderer.call("_draw_object_row", 1, 0, 0, 0, 0, 0)
	var whitelisted_texture_id: int = probe.requested_texture_id
	renderer.free()
	if whitelisted_texture_id != whitelisted_record[0] + expected_frame:
		_fail("whitelisted map object stopped animating: requested=%08X frame=%d" % [whitelisted_texture_id, expected_frame])
		return false
	return true


func _fail(message: String) -> void:
	push_error("WORLD_RESOURCE_SMOKE %s" % message)
	get_tree().quit(1)
