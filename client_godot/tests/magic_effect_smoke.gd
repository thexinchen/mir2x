extends Control

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const Protocol = preload("res://scripts/network/protocol.gd")


func _ready() -> void:
	var resources: RefCounted = ActorResourceScript.new()
	if not resources.configure_default():
		_fail("world resources unavailable")
		return
	var fireball_id: int = resources.magic_id("火球术")
	var thunder_id: int = resources.magic_id("雷电术")
	var firewall_id: int = resources.magic_id("火墙")
	var shield_id: int = resources.magic_id("魔法盾")
	var ring_id: int = resources.magic_id("阴阳法环")
	var hellfire_id: int = resources.magic_id("地狱火")
	var ice_thrust_id: int = resources.magic_id("冰沙掌")
	var fire_ash_id: int = resources.magic_id("魔法特效_火焰灰烬")
	var ice_thorn_id: int = resources.magic_id("魔法特效_冰刺")
	var wind_chain_id: int = resources.magic_id("风震天")
	var laser_id: int = resources.magic_id("疾光电影")
	var healing_id: int = resources.magic_id("治愈术")
	var soul_talisman_id: int = resources.magic_id("灵魂火符")
	var flame_sword_id: int = resources.magic_id("烈火剑法")
	var tao_dog_fire_id: int = resources.magic_id("神兽_喷火")
	var wedge_poison_id: int = resources.magic_id("楔蛾_喷毒")
	var fixed_monster_attacks := [
		{"id": tao_dog_fire_id, "frame": 5},
		{"id": wedge_poison_id, "frame": 5},
		{"id": resources.magic_id("洞蛆_喷毒"), "frame": 5},
		{"id": resources.magic_id("粪虫_喷毒"), "frame": 3},
		{"id": resources.magic_id("雷电僵尸_雷电"), "frame": 3},
		{"id": resources.magic_id("火焰沃玛_喷火"), "frame": 3},
		{"id": resources.magic_id("沃玛教主_电光"), "frame": 1},
	]
	var target_monster_attacks := [
		{"id": resources.magic_id("蚂蚁道士_治疗"), "frame": 3, "kind": "ant_healing"},
		{"id": resources.magic_id("红衣法师_魔法"), "frame": 3, "kind": "attachment"},
		{"id": resources.magic_id("沙漠风魔_扇风"), "frame": 3, "kind": "attachment"},
		{"id": resources.magic_id("沃玛教主_雷电术"), "frame": 3, "kind": "thunderbolt"},
		{"id": resources.magic_id("潘夜右护卫_雷电术"), "frame": 4, "kind": "thunderbolt"},
		{"id": thunder_id, "frame": 5, "kind": "thunderbolt"},
	]
	var monster_projectile_attacks := [
		{"id": resources.magic_id("暗黑战士_喷刺"), "frame": 5, "gfx_direction": 0},
		{"id": resources.magic_id("爆毒蚂蚁_喷毒"), "frame": 2, "gfx_direction": 0},
		{"id": resources.magic_id("沙漠树魔_喷刺"), "frame": 5, "gfx_direction": 0},
		{"id": resources.magic_id("诺玛法老_火球术"), "frame": 4, "gfx_direction": 4},
		{"id": resources.magic_id("潘夜左护卫_火球术"), "frame": 4, "gfx_direction": 4},
		{"id": resources.magic_id("祖玛弓箭手_射箭"), "frame": 5, "gfx_direction": 4},
	]
	var monster_motion_attacks := [
		resources.magic_id("潘夜右护卫_电魔杖"),
		resources.magic_id("潘夜左护卫_火魔杖"),
	]
	var shipwreck_blade_id: int = resources.magic_id("霸王教主_火刃")
	var zuma_firewall_id: int = resources.magic_id("祖玛教主_火墙")
	var zuma_hellfire_id: int = resources.magic_id("祖玛教主_地狱火")
	var zuma_fragment_id: int = resources.magic_id("祖玛教主_石像碎片")
	var monk_spawn_ground_id: int = resources.magic_id("僧侣僵尸_地洞")
	var stone_spawn_ground_id: int = resources.magic_id("沙漠石人_石坑")
	var dual_axe_id: int = resources.magic_id("掷斧骷髅_掷斧")
	var space_move_id: int = resources.magic_id("瞬息移动")
	var monster_death_magic_id := 0
	var monster_death_monster_id := 0
	for monster_id_value in resources.monster_meta:
		monster_death_magic_id = resources.monster_death_magic_id(int(monster_id_value))
		if monster_death_magic_id > 0:
			monster_death_monster_id = int(monster_id_value)
			break
	var target_attachment_ids := [
		resources.magic_id("乾坤大挪移"), healing_id, resources.magic_id("圣言术"), resources.magic_id("云寂术"),
		resources.magic_id("回生术"), resources.magic_id("施毒术"), resources.magic_id("诱惑之光"), resources.magic_id("移花接玉"),
	]
	var hit_wind_id: int = resources.magic_id("击风")
	var fixed_action_ids := [
		hit_wind_id, resources.magic_id("冰咆哮"), resources.magic_id("龙卷风"), resources.magic_id("爆裂火焰"),
		resources.magic_id("地狱雷光"), resources.magic_id("怒神霹雳"), resources.magic_id("群体治愈术"),
	]
	var fixed_projectile_ids := [resources.magic_id("月魂断玉"), resources.magic_id("月魂灵波"), resources.magic_id("冰月震天")]
	var projectile_ids := [
		fireball_id, resources.magic_id("大火球"), resources.magic_id("霹雳掌"), resources.magic_id("风掌"),
		fixed_projectile_ids[0], fixed_projectile_ids[1], soul_talisman_id, resources.magic_id("冰月神掌"),
		fixed_projectile_ids[2], resources.magic_id("幽灵盾"), resources.magic_id("神圣战甲术"), resources.magic_id("强魔震法"),
		resources.magic_id("猛虎强势"), resources.magic_id("集体隐身术"),
	]
	if fireball_id == 0 or thunder_id == 0 or firewall_id == 0 or shield_id == 0 or ring_id == 0 or hellfire_id == 0 or ice_thrust_id == 0 or fire_ash_id == 0 or ice_thorn_id == 0 or wind_chain_id == 0 or laser_id == 0 or flame_sword_id == 0 or fixed_monster_attacks.any(func(entry: Dictionary) -> bool: return entry.id == 0) or target_monster_attacks.any(func(entry: Dictionary) -> bool: return entry.id == 0) or monster_projectile_attacks.any(func(entry: Dictionary) -> bool: return entry.id == 0) or monster_motion_attacks.has(0) or shipwreck_blade_id == 0 or zuma_firewall_id == 0 or zuma_hellfire_id == 0 or zuma_fragment_id == 0 or monk_spawn_ground_id == 0 or stone_spawn_ground_id == 0 or dual_axe_id == 0 or space_move_id == 0 or monster_death_magic_id == 0 or target_attachment_ids.has(0) or fixed_action_ids.has(0) or projectile_ids.has(0):
		_fail("magic name metadata incomplete")
		return
	for magic_id in target_attachment_ids:
		var attachment_meta: PackedInt32Array = resources.magic_layout(magic_id, 2)
		if attachment_meta.is_empty() or attachment_meta[2] <= 0 or attachment_meta[5] != 2:
			_fail("target attachment metadata mismatch: id=%d meta=%s" % [magic_id, attachment_meta])
			return
	for magic_id in fixed_action_ids:
		var fixed_meta: PackedInt32Array = resources.magic_layout(magic_id, 2)
		if fixed_meta.is_empty() or fixed_meta[2] <= 0 or fixed_meta[5] != 1:
			_fail("fixed action metadata mismatch: id=%d meta=%s" % [magic_id, fixed_meta])
			return
	for magic_id in projectile_ids:
		var projectile_meta: PackedInt32Array = resources.magic_layout(magic_id, 2)
		if projectile_meta.size() < 41 or projectile_meta[2] <= 0 or projectile_meta[5] != 3:
			_fail("follow projectile metadata mismatch: id=%d meta=%s" % [magic_id, projectile_meta])
			return
	var fireball_run: PackedInt32Array = resources.magic_layout(fireball_id, 2)
	var thunder_run: PackedInt32Array = resources.magic_layout(thunder_id, 2)
	var firewall_run: PackedInt32Array = resources.magic_layout(firewall_id, 2)
	if fireball_run.is_empty() or fireball_run[5] != 3 or thunder_run.is_empty() or thunder_run[5] != 2 or firewall_run.is_empty() or not bool(firewall_run[7] & 3):
		_fail("fixed/bound/follow metadata mismatch")
		return
	if resources.frame("magic", fireball_run[0]).is_empty() or resources.frame("magic", thunder_run[0]).is_empty() or resources.frame("magic", firewall_run[0]).is_empty():
		_fail("original magic frame missing")
		return

	var ext := PackedByteArray()
	ext.resize(8)
	ext.encode_u32(0, fireball_id)
	var encoded := Protocol.encode_action_node({"type": 9, "extParam": ext})
	var decoded := Protocol.decode_action_node(encoded)
	if decoded.get("magicID", 0) != fireball_id:
		_fail("ACTION_SPELL magicID decode mismatch")
		return

	GameState.player_map_id = 24
	GameState.player_map_uid = 24 << 35
	GameState.player_uid = (5 << 59) | (1 << 35) | 1
	GameState.player_x = 405
	GameState.player_y = 120
	GameState.player_gender = 1
	GameState.player_job = 1
	GameState.view_x = 405 * 48 - 400
	GameState.view_y = 120 * 32 - 300
	var target_uid: int = (4 << 59) | (1 << 35) | 2
	GameState.creatures = {target_uid: {"uid": target_uid, "x": 409, "y": 120, "type": 1, "monster_id": 1, "direction": 7}}
	$WorldRenderer.game_state = GameState
	if not $WorldRenderer.load_map(24):
		_fail("map 24 failed to load")
		return
	GameState.firewalls.clear()
	GameState.magic_effects.clear()
	var firewall_now := Time.get_ticks_msec()
	var firewall_added := GameState.reconcile_firewalls([
		{"x": 407, "y": 122, "count": 2},
		{"x": 411, "y": 122, "count": 1},
	], firewall_now, fire_ash_id)
	if firewall_added.get("added", []).size() != 3 or GameState.firewalls.size() != 3:
		_fail("firewall snapshot did not create per-instance state: %s" % firewall_added)
		return
	GameState.reconcile_firewalls([{"x": 407, "y": 122, "count": 2}], firewall_now + 10, fire_ash_id)
	if GameState.firewalls.filter(func(wall: Dictionary) -> bool: return wall.x == 411 and wall.y == 122).size() != 1:
		_fail("incremental firewall snapshot removed an unlisted grid")
		return
	var firewall_removed := GameState.reconcile_firewalls([{"x": 407, "y": 122, "count": 1}], firewall_now + 100, fire_ash_id)
	if firewall_removed.get("fading", []).size() != 1 or GameState.magic_effects.size() != 1:
		_fail("firewall decrement did not queue fade and ash: changes=%s effects=%s" % [firewall_removed, GameState.magic_effects])
		return
	var fading_firewall: Dictionary = firewall_removed.get("fading", [])[0]
	if not is_equal_approx(float($WorldRenderer.call("_firewall_alpha", fading_firewall, firewall_now + 1600)), 0.5) or float($WorldRenderer.call("_firewall_alpha", fading_firewall, firewall_now + 3100)) != 0.0:
		_fail("firewall 3s fade-out envelope mismatch: %s" % fading_firewall)
		return
	var firewall_ash: Dictionary = GameState.magic_effects[0]
	var half_ash: Dictionary = $WorldRenderer.call("_resolve_firewall_ash", firewall_ash, fire_ash_id, 1500)
	if half_ash.get("components", []).size() != 1 or half_ash.get("underlays", []).size() != 1 or not is_equal_approx(float(half_ash.components[0].alpha_mod), 0.5):
		_fail("firewall ash 3s fade-in mismatch: %s" % half_ash)
		return
	if $WorldRenderer.call("_resolve_firewall_ash", firewall_ash, fire_ash_id, 10999).get("components", []).size() != 1 or not $WorldRenderer.call("_resolve_firewall_ash", firewall_ash, fire_ash_id, 11000).is_empty():
		_fail("firewall ash 3s/5s/3s lifetime mismatch")
		return
	GameState.reconcile_firewalls([{"x": 407, "y": 122, "count": 2}], firewall_now + 200, fire_ash_id)
	var active_firewalls := GameState.firewalls.filter(func(wall: Dictionary) -> bool: return wall.x == 407 and wall.y == 122 and wall.fade_start_time < 0)
	if active_firewalls.size() != 2 or GameState.firewalls.filter(func(wall: Dictionary) -> bool: return wall.x == 407 and wall.y == 122).size() != 3:
		_fail("firewall rebound did not coexist with fading instance: %s" % GameState.firewalls)
		return
	$WorldRenderer.call("_prune_firewalls", firewall_now + 3100)
	if GameState.firewalls.filter(func(wall: Dictionary) -> bool: return wall.x == 407 and wall.y == 122).size() != 2:
		_fail("expired firewall fade was not pruned: %s" % GameState.firewalls)
		return
	if resources.frame("magic", 0x0F0000DC).is_empty() or resources.frame("magic", 0x0F000104).is_empty() or resources.frame("magic", 0x0F000105).is_empty():
		_fail("special ground textures missing")
		return
	var special_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
	if special_source.x < 0:
		_fail("no open eight-grid line for special magic fixture")
		return
	var ice_source := _find_open_wave_source($WorldRenderer, special_source.y + 2, mini($WorldRenderer.map_height - 8, special_source.y + 12))
	if ice_source.x < 0:
		ice_source = special_source + Vector2i(8, 0)
	var variants: Array = []
	for index in 8:
		variants.append({
			"ash_direction": index % 5,
			"frame_offset": index % 10,
			"rotation": index * 31,
			"slag_indices": [index % 2, (index + 1) % 2],
			"ice_rotations": [index * 23, index * 29],
		})
	var hellfire_meta: PackedInt32Array = resources.magic_layout(hellfire_id, 2)
	var ice_thrust_meta: PackedInt32Array = resources.magic_layout(ice_thrust_id, 2)
	var ice_thorn_meta: PackedInt32Array = resources.magic_layout(ice_thorn_id, 2)
	if hellfire_meta.is_empty() or ice_thrust_meta.is_empty() or ice_thorn_meta.is_empty() or not bool(ice_thrust_meta[7] & 4):
		_fail("special composite run metadata missing: hell=%d ice_parent=%s ice_child=%d" % [hellfire_meta.size(), ice_thrust_meta, ice_thorn_meta.size()])
		return
	var special_effect := {
		"source": "action", "magicID": hellfire_id, "x": special_source.x, "y": special_source.y,
		"aimX": special_source.x + 8, "aimY": special_source.y, "direction": 3, "speed": 100,
		"_special_variants": variants, "_special_seff_mask": 0xFF,
	}
	var pending_special: Dictionary = $WorldRenderer.call("_resolve_special_magic", special_effect, hellfire_id, "hellfire", hellfire_meta, 0)
	if pending_special.is_empty() or not pending_special.get("components", []).is_empty():
		_fail("special wave was not retained before its first 100ms delay")
		return
	var hellfire_trigger: int = $WorldRenderer.call("_magic_frame_reach_duration", hellfire_meta, 10)
	var hellfire_state: Dictionary = $WorldRenderer.call("_resolve_special_magic", special_effect, hellfire_id, "hellfire", hellfire_meta, 100 + hellfire_trigger + 500)
	if hellfire_state.get("underlays", []).is_empty() or hellfire_state.get("components", []).is_empty():
		_fail("hellfire ash composite missing: %s" % hellfire_state)
		return
	var first_ash: Dictionary = hellfire_state.get("underlays", [])[0]
	if first_ash.get("texture_id", 0) != 0x0F0000DC or first_ash.get("crop", Vector2i.ZERO) != Vector2i(102, 72):
		_fail("hellfire ash texture/crop mismatch: %s" % first_ash)
		return
	var ice_effect := special_effect.duplicate(true)
	ice_effect["magicID"] = ice_thrust_id
	var ice_state: Dictionary = $WorldRenderer.call("_resolve_special_magic", ice_effect, ice_thrust_id, "ice_thrust", ice_thrust_meta, 1100)
	if ice_state.get("components", []).size() < 2 or ice_state.get("underlays", []).size() < 2:
		_fail("ice thrust child/slag composite missing: %s" % ice_state)
		return
	var ice_underlay: Dictionary = ice_state.get("underlays", [])[0]
	if int(ice_underlay.get("texture_id", 0)) not in [0x0F000104, 0x0F000105]:
		_fail("ice slag texture mismatch: %s" % ice_underlay)
		return
	if $WorldRenderer.call("_direction_step", 3) != Vector2i(1, 0):
		_fail("special wave direction mapping mismatch")
		return
	var ice_lifetime: int = $WorldRenderer.call("_magic_frame_reach_duration", ice_thorn_meta, 55)
	if not $WorldRenderer.call("_resolve_special_magic", ice_effect, ice_thrust_id, "ice_thrust", ice_thrust_meta, 800 + ice_lifetime).is_empty():
		_fail("ice thrust composite did not expire after the eighth slag lifetime")
		return
	if resources.magic_seff(ice_thrust_id, 2) < 0:
		_fail("invisible ice thrust parent lost its run SEFF metadata")
		return
	var wind_run: PackedInt32Array = resources.magic_layout(wind_chain_id, 2)
	var wind_explode: PackedInt32Array = resources.magic_layout(wind_chain_id, 3)
	var laser_run: PackedInt32Array = resources.magic_layout(laser_id, 2)
	if wind_run.is_empty() or wind_explode.is_empty() or laser_run.is_empty():
		_fail("propagated spell metadata missing")
		return
	var propagated_effect := {
		"source": "action", "x": special_source.x, "y": special_source.y,
		"aimX": special_source.x + 8, "aimY": special_source.y, "direction": 3, "speed": 100,
		"_propagated_seff_mask": 0xFF,
	}
	var wind_effect := propagated_effect.duplicate(true)
	wind_effect["magicID"] = wind_chain_id
	var first_wind: Dictionary = $WorldRenderer.call("_resolve_wind_chain", wind_effect, wind_chain_id, wind_run, 0)
	var first_wind_components: Array = first_wind.get("components", [])
	if first_wind_components.size() != 1 or first_wind_components[0].position != Vector2(special_source + Vector2i(1, 0)):
		_fail("wind chain did not begin one grid forward: %s" % first_wind)
		return
	var wind_run_duration: int = $WorldRenderer.call("_magic_frame_duration", wind_run)
	var wind_explode_state: Dictionary = $WorldRenderer.call("_resolve_wind_chain", wind_effect, wind_chain_id, wind_run, 7 * wind_run_duration)
	var wind_explode_components: Array = wind_explode_state.get("components", [])
	if wind_explode_components.size() != 1 or wind_explode_components[0].meta != wind_explode or wind_explode_components[0].position != Vector2(special_source + Vector2i(8, 0)):
		_fail("wind chain eighth-grid explode mismatch: %s" % wind_explode_state)
		return
	var laser_effect := propagated_effect.duplicate(true)
	laser_effect["magicID"] = laser_id
	var laser_state: Dictionary = $WorldRenderer.call("_resolve_caster_laser", laser_effect, laser_id, laser_run, 100)
	var laser_components: Array = laser_state.get("components", [])
	if laser_components.size() != 1 or laser_components[0].position != Vector2(special_source) or laser_components[0].direction != 2:
		_fail("laser did not stay on caster grid/direction: %s" % laser_state)
		return
	var special_action_cases := [
		{"effect": special_effect, "id": hellfire_id, "kind": "hellfire", "frame": 3, "run_delay": 100, "visible_meta": hellfire_meta},
		{"effect": ice_effect, "id": ice_thrust_id, "kind": "ice_thrust", "frame": 3, "run_delay": 100, "visible_meta": ice_thorn_meta},
		{"effect": wind_effect, "id": wind_chain_id, "kind": "wind_chain", "frame": 4, "run_delay": 0, "visible_meta": wind_run},
		{"effect": laser_effect, "id": laser_id, "kind": "laser", "frame": 3, "run_delay": 0, "visible_meta": laser_run},
	]
	for special_case in special_action_cases:
		var action_special: Dictionary = special_case.effect.duplicate(true)
		var special_id: int = special_case.id
		var special_frame: int = special_case.frame
		var special_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", special_id, special_frame)
		var before_special: Dictionary = $WorldRenderer.call("_resolve_special_action_magic", action_special, special_id, special_case.kind, special_trigger - 1)
		var special_run: PackedInt32Array = special_case.visible_meta
		if before_special.get("components", []).any(func(component: Dictionary) -> bool: return component.meta == special_run):
			_fail("special action triggered before synchronized hero frame: id=%d frame=%d" % [special_id, special_frame])
			return
		var running_special: Dictionary = $WorldRenderer.call("_resolve_special_action_magic", action_special, special_id, special_case.kind, special_trigger + int(special_case.run_delay))
		if not running_special.get("components", []).any(func(component: Dictionary) -> bool: return component.meta == special_run):
			_fail("special action missing after synchronized hero frame: id=%d delay=%d state=%s" % [special_id, special_trigger, running_special])
			return
	var fixed_effect := propagated_effect.duplicate(true)
	fixed_effect["aimUID"] = target_uid
	fixed_effect["aimX"] = 409
	fixed_effect["aimY"] = 120
	fixed_effect["_seff_stage_mask"] = 0xFFFF
	for fixed_id in fixed_action_ids:
		var action_fixed := fixed_effect.duplicate(true)
		action_fixed["magicID"] = fixed_id
		var fixed_run: PackedInt32Array = resources.magic_layout(fixed_id, 2)
		var fixed_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", fixed_id, 3)
		var before_fixed: Dictionary = $WorldRenderer.call("_resolve_fixed_action_magic", action_fixed, fixed_id, "run_explode" if fixed_id == hit_wind_id else "run", fixed_trigger - 1)
		for component in before_fixed.get("components", []):
			if component.meta == fixed_run:
				_fail("fixed action triggered before spell frame 3: id=%d" % fixed_id)
				return
		var running_fixed: Dictionary = $WorldRenderer.call("_resolve_fixed_action_magic", action_fixed, fixed_id, "run_explode" if fixed_id == hit_wind_id else "run", fixed_trigger)
		var run_components: Array = running_fixed.get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == fixed_run)
		if run_components.size() != 1 or run_components[0].position != Vector2(409, 120):
			_fail("fixed action frame-3 placement mismatch: id=%d state=%s" % [fixed_id, running_fixed])
			return
		GameState.creatures[target_uid]["x"] = 410
		var moved_fixed: Dictionary = $WorldRenderer.call("_resolve_fixed_action_magic", action_fixed, fixed_id, "run_explode" if fixed_id == hit_wind_id else "run", fixed_trigger + 100)
		for component in moved_fixed.get("components", []):
			if component.meta == fixed_run and component.position != Vector2(409, 120):
				_fail("fixed action followed target after trigger: id=%d state=%s" % [fixed_id, moved_fixed])
				return
		GameState.creatures[target_uid]["x"] = 409
	var hit_run: PackedInt32Array = resources.magic_layout(hit_wind_id, 2)
	var hit_explode: PackedInt32Array = resources.magic_layout(hit_wind_id, 3)
	var hit_effect := fixed_effect.duplicate(true)
	hit_effect["magicID"] = hit_wind_id
	var hit_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", hit_wind_id, 3)
	$WorldRenderer.call("_resolve_fixed_action_magic", hit_effect, hit_wind_id, "run_explode", hit_trigger)
	var hit_explode_state: Dictionary = $WorldRenderer.call("_resolve_fixed_action_magic", hit_effect, hit_wind_id, "run_explode", hit_trigger + int($WorldRenderer.call("_magic_frame_duration", hit_run)))
	var hit_components: Array = hit_explode_state.get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == hit_explode)
	if hit_components.size() != 1 or hit_components[0].position != Vector2(409, 120):
		_fail("hit-wind explode chain mismatch: %s" % hit_explode_state)
		return
	if not is_equal_approx(float($WorldRenderer.call("_fire_ash_alpha", 500)), 0.5) or not is_equal_approx(float($WorldRenderer.call("_ice_slag_alpha", 5)), 0.5):
		_fail("special ground alpha envelope mismatch")
		return

	var now := Time.get_ticks_msec()
	var fireball := {
		"source": "action", "magicID": fireball_id, "uid": GameState.player_uid,
		"x": 405, "y": 120, "aimX": 409, "aimY": 120, "aimUID": target_uid,
		"direction": 3, "start_time": now,
	}
	var chain_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", fireball_id, 4)
	fireball.start_time -= chain_trigger
	GameState.magic_effects = [fireball]
	var active: Array = $WorldRenderer.call("_resolve_magic_effects", now)
	var active_fireball_components: Array = active[0].get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == fireball_run) if active.size() == 1 else []
	if active.size() != 1 or active_fireball_components.size() != 1:
		_fail("magic stage chain resolution mismatch: %s" % [active])
		return

	GameState.attached_magic_effects.clear()
	var attachment_action := {
		"source": "action", "uid": GameState.player_uid,
		"x": 405, "y": 120, "aimX": 409, "aimY": 120, "aimUID": target_uid,
		"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
	}
	for attachment_id in target_attachment_ids:
		var action_effect := attachment_action.duplicate(true)
		action_effect["magicID"] = attachment_id
		var attachment_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", attachment_id, 3)
		$WorldRenderer.call("_resolve_magic_effect", action_effect, now + attachment_trigger - 1)
		if not GameState.attached_magic_effects.is_empty():
			_fail("target attachment triggered before spell frame 3: id=%d" % attachment_id)
			return
		$WorldRenderer.call("_resolve_magic_effect", action_effect, now + attachment_trigger)
		if GameState.attached_magic_effects.size() != 1 or GameState.attached_magic_effects[0].get("target_uid", 0) != target_uid:
			_fail("target attachment did not bind aimed creature: id=%d effects=%s" % [attachment_id, GameState.attached_magic_effects])
			return
		$WorldRenderer.call("_resolve_magic_effect", action_effect, now + attachment_trigger + 100)
		if GameState.attached_magic_effects.size() != 1:
			_fail("target attachment duplicated during redraw: id=%d" % attachment_id)
			return
		GameState.attached_magic_effects.clear()
	var moving_effect := attachment_action.duplicate(true)
	moving_effect["magicID"] = healing_id
	var healing_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", healing_id, 3)
	$WorldRenderer.call("_resolve_magic_effect", moving_effect, now + healing_trigger)
	GameState.creatures[target_uid]["x"] = 411
	GameState.creatures[target_uid]["y"] = 121
	if $WorldRenderer.call("_attached_target_grid", target_uid) != Vector2(411, 121):
		_fail("target attachment did not follow creature movement")
		return
	GameState.creatures.erase(target_uid)
	if not $WorldRenderer.call("_resolve_attached_magic", now + 301).is_empty() or not GameState.attached_magic_effects.is_empty():
		_fail("target attachment survived missing creature")
		return
	var healing_fallback := attachment_action.duplicate(true)
	healing_fallback["magicID"] = healing_id
	healing_fallback["aimUID"] = target_uid
	$WorldRenderer.call("_resolve_magic_effect", healing_fallback, now + healing_trigger)
	if GameState.attached_magic_effects.size() != 1 or GameState.attached_magic_effects[0].get("target_uid", 0) != GameState.player_uid:
		_fail("healing attachment did not fall back to caster: %s" % GameState.attached_magic_effects)
		return
	GameState.attached_magic_effects.clear()
	var strict_missing := attachment_action.duplicate(true)
	strict_missing["magicID"] = target_attachment_ids[0]
	strict_missing["aimUID"] = target_uid
	$WorldRenderer.call("_resolve_magic_effect", strict_missing, now + int($WorldRenderer.call("_hero_spell_trigger_delay", target_attachment_ids[0], 3)))
	if not GameState.attached_magic_effects.is_empty():
		_fail("strict target attachment incorrectly fell back to caster")
		return
	GameState.creatures[target_uid] = {"uid": target_uid, "x": 409, "y": 120, "type": 1, "monster_id": 1, "direction": 7}

	GameState.attached_magic_effects.clear()
	var projectile_effect := {
		"source": "action", "magicID": fireball_id, "uid": GameState.player_uid,
		"x": 405, "y": 120, "aimX": 409, "aimY": 120, "aimUID": target_uid,
		"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
	}
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(409 * 48, 120 * 32)}})
	var projectile_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", fireball_id, 4)
	if projectile_trigger <= 400:
		_fail("SPELL0 projectile trigger was not delayed by startup synchronization: %d" % projectile_trigger)
		return
	var before_motion: PackedInt32Array = $WorldRenderer.call("_hero_spell_motion_state", fireball_id, now, now + projectile_trigger - 1)
	var trigger_motion: PackedInt32Array = $WorldRenderer.call("_hero_spell_motion_state", fireball_id, now, now + projectile_trigger)
	if before_motion[1] >= 4 or trigger_motion[1] < 4:
		_fail("projectile trigger and hero frame 4 diverged: before=%s trigger=%s delay=%d" % [before_motion, trigger_motion, projectile_trigger])
		return
	var before_projectile: Dictionary = $WorldRenderer.call("_resolve_magic_effect", projectile_effect, now + projectile_trigger - 1)
	for component in before_projectile.get("components", []):
		if component.meta == fireball_run:
			_fail("follow projectile launched before spell frame 4")
			return
	var launched_projectile: Dictionary = $WorldRenderer.call("_resolve_magic_effect", projectile_effect, now + projectile_trigger)
	var launched_components: Array = launched_projectile.get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == fireball_run)
	var first_position: Vector2 = projectile_effect.get("_projectile_position", Vector2.ZERO)
	var source_position := Vector2(405 * 48, 120 * 32)
	if launched_components.size() != 1 or first_position == source_position or absf(first_position.distance_to(source_position) - 20.0) > 1.0:
		_fail("follow projectile did not advance 20px on launch: %s pos=%s" % [launched_projectile, first_position])
		return
	$WorldRenderer.call("_resolve_magic_effect", projectile_effect, now + projectile_trigger)
	if projectile_effect.get("_projectile_position", Vector2.ZERO) != first_position or projectile_effect.get("_projectile_step_count", 0) != 1:
		_fail("same-time redraw advanced follow projectile: %s" % projectile_effect)
		return
	var sparse_projectile := projectile_effect.duplicate(true)
	for key in ["_projectile_position", "_projectile_start", "_projectile_fly_direction", "_projectile_gfx_direction", "_projectile_last_fly_offset", "_projectile_step_count", "_projectile_impact_spawned", "_projectile_done"]:
		sparse_projectile.erase(key)
	var dense_projectile := sparse_projectile.duplicate(true)
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(430 * 48, 120 * 32)}})
	$WorldRenderer.call("_resolve_magic_effect", sparse_projectile, now + projectile_trigger + 100)
	for sample_offset in [0, 17, 34, 50, 67, 84, 100]:
		$WorldRenderer.call("_resolve_magic_effect", dense_projectile, now + projectile_trigger + sample_offset)
	if sparse_projectile.get("_projectile_step_count", 0) != 7 or dense_projectile.get("_projectile_step_count", 0) != 7 or sparse_projectile.get("_projectile_position", Vector2.ZERO) != dense_projectile.get("_projectile_position", Vector2.ZERO):
		_fail("60Hz projectile state depended on render sampling: sparse=%s dense=%s" % [sparse_projectile, dense_projectile])
		return
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(first_position.x, first_position.y - 160)}})
	var prior_position := first_position
	$WorldRenderer.call("_resolve_magic_effect", projectile_effect, now + projectile_trigger + 17)
	var turned_position: Vector2 = projectile_effect.get("_projectile_position", Vector2.ZERO)
	if turned_position.y >= prior_position.y:
		_fail("follow projectile did not home toward moved target: before=%s after=%s" % [prior_position, turned_position])
		return
	var fireball_offset := Vector2(resources.magic_target_offset(fireball_id, 2, projectile_effect.get("_projectile_gfx_direction", 0)))
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": turned_position + fireball_offset + Vector2(1, 1)}})
	var hit_state: Dictionary = $WorldRenderer.call("_resolve_magic_effect", projectile_effect, now + projectile_trigger + 34)
	var hit_run_components: Array = hit_state.get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == fireball_run)
	if not hit_run_components.is_empty() or GameState.attached_magic_effects.size() != 1:
		_fail("follow projectile hit did not replace flight with one impact: state=%s effects=%s" % [hit_state, GameState.attached_magic_effects])
		return
	var impact: Dictionary = GameState.attached_magic_effects[0]
	if impact.get("target_uid", 0) != target_uid or impact.get("stage", 0) != 3 or impact.get("kind", "") != "projectile_impact" or impact.get("start_time", 0) != now + projectile_trigger + 34:
		_fail("follow projectile impact metadata mismatch: %s" % impact)
		return
	var impact_active: Dictionary = $WorldRenderer.call("_resolve_attached_magic", now + projectile_trigger + 34)
	if impact_active.get(target_uid, []).is_empty() or impact_active[target_uid][0].meta != resources.magic_layout(fireball_id, 3):
		_fail("follow projectile impact did not use explode-stage graphics: %s" % impact_active)
		return

	GameState.attached_magic_effects.clear()
	var space_effect := {
		"source": "space_move", "magicID": space_move_id, "uid": target_uid,
		"x": 405, "y": 120, "aimX": 409, "aimY": 120,
		"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
	}
	var active_space: Dictionary = $WorldRenderer.call("_resolve_magic_effect", space_effect, now + 100)
	var space_components: Array = active_space.get("components", [])
	if active_space.get("special_kind", "") != "space_move" or space_components.size() != 1 or space_components[0].meta != resources.magic_layout(space_move_id, 2) or space_components[0].position != Vector2(405, 120) or space_components[0].direction != 0:
		_fail("space move did not keep its run effect at the old grid: %s" % active_space)
		return
	if GameState.attached_magic_effects.size() != 1:
		_fail("space move did not create one destination attachment: %s" % GameState.attached_magic_effects)
		return
	var space_attachment: Dictionary = GameState.attached_magic_effects[0]
	if space_attachment.get("target_uid", 0) != target_uid or space_attachment.get("stage", 0) != 3 or space_attachment.get("kind", "") != "space_move" or space_attachment.get("start_time", -1) != now:
		_fail("space move destination attachment metadata mismatch: %s" % space_attachment)
		return
	$WorldRenderer.call("_resolve_magic_effect", space_effect, now + 120)
	if GameState.attached_magic_effects.size() != 1:
		_fail("space move created a duplicate destination attachment")
		return
	var space_attached_active: Dictionary = $WorldRenderer.call("_resolve_attached_magic", now + 120)
	if space_attached_active.get(target_uid, []).size() != 1 or space_attached_active[target_uid][0].meta != resources.magic_layout(space_move_id, 3) or $WorldRenderer.call("_attached_target_grid", target_uid) != Vector2(409, 120):
		_fail("space move explode stage was not attached at the destination actor: %s" % space_attached_active)
		return
	GameState.attached_magic_effects.clear()

	GameState.attached_magic_effects = [{
		"magicID": monster_death_magic_id, "target_uid": target_uid,
		"start_time": now, "action_started_ms": now,
		"cycles": 1, "kind": "monster_death", "stage": 2,
	}]
	var death_attached_active: Dictionary = $WorldRenderer.call("_resolve_attached_magic", now + 1)
	if death_attached_active.get(target_uid, []).size() != 1 or death_attached_active[target_uid][0].meta != resources.magic_layout(monster_death_magic_id, 2):
		_fail("monster death attachment did not use its run-stage graphics: %s" % death_attached_active)
		return
	GameState.attached_magic_effects.clear()

	for zuma_magic_id in [zuma_firewall_id, zuma_hellfire_id]:
		if not $WorldRenderer.supports_monster_attack_magic(zuma_magic_id):
			_fail("ZumaTaurus aligned magic was not recognized: %d" % zuma_magic_id)
			return
		var aligned_frame: Dictionary = $WorldRenderer.call("_monster_attack_motion_effect_state", zuma_magic_id, 3, now, 100, 6, now + 200)
		var aligned_done: Dictionary = $WorldRenderer.call("_monster_attack_motion_effect_state", zuma_magic_id, 3, now, 100, 6, now + 600)
		if not aligned_frame.get("visible", false) or aligned_frame.get("frame", -1) != 3 or aligned_frame.get("direction", -1) != 2 or aligned_frame.get("meta", PackedInt32Array()) != resources.magic_layout(zuma_magic_id, 1) or not aligned_done.is_empty():
			_fail("ZumaTaurus 8-frame spell was not aligned to its 6-frame attack: id=%d active=%s done=%s" % [zuma_magic_id, aligned_frame, aligned_done])
			return
	var zuma_firewall := {
		"source": "monster_attack", "magicID": zuma_firewall_id, "uid": target_uid,
		"x": special_source.x, "y": special_source.y, "aimX": special_source.x + 8, "aimY": special_source.y,
		"direction": 7, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
	}
	var firewall_wait: Dictionary = $WorldRenderer.call("_resolve_magic_effect", zuma_firewall, now + 599)
	var firewall_done: Dictionary = $WorldRenderer.call("_resolve_magic_effect", zuma_firewall, now + 600)
	if firewall_wait.is_empty() or not firewall_wait.get("components", []).is_empty() or not firewall_done.is_empty():
		_fail("ZumaTaurus firewall action fabricated a client-side wall or escaped its attack lifetime: wait=%s done=%s" % [firewall_wait, firewall_done])
		return
	var zuma_hellfire := zuma_firewall.duplicate(true)
	zuma_hellfire["magicID"] = zuma_hellfire_id
	zuma_hellfire["_special_seff_mask"] = 0xFF
	var hellfire_wait: Dictionary = $WorldRenderer.call("_resolve_magic_effect", zuma_hellfire, now + 499)
	var hellfire_first: Dictionary = $WorldRenderer.call("_resolve_magic_effect", zuma_hellfire, now + 500)
	var hellfire_components: Array = hellfire_first.get("components", [])
	if not hellfire_wait.get("components", []).is_empty() or zuma_hellfire.get("_zuma_hellfire_direction", 0) != 3 or hellfire_components.size() != 2 or hellfire_components[0].position != Vector2(special_source + Vector2i(1, 0)) or hellfire_components[0].meta != resources.magic_layout(hellfire_id, 2):
		_fail("ZumaTaurus frame-4 hellfire propagation mismatch: wait=%s first=%s effect=%s" % [hellfire_wait, hellfire_first, zuma_hellfire])
		return
	var fragment_effect := {"source": "monster_transform", "magicID": zuma_fragment_id, "x": special_source.x, "y": special_source.y, "start_time": now}
	var fragment_future: Dictionary = $WorldRenderer.call("_resolve_magic_effect", fragment_effect, now - 1)
	var fragment_hold: Dictionary = $WorldRenderer.call("_resolve_magic_effect", fragment_effect, now + 4999)
	var fragment_fade: Dictionary = $WorldRenderer.call("_resolve_magic_effect", fragment_effect, now + 6500)
	var fragment_done: Dictionary = $WorldRenderer.call("_resolve_magic_effect", fragment_effect, now + 8000)
	if fragment_future.is_empty() or not fragment_future.get("components", []).is_empty() or fragment_hold.get("components", []).size() != 1 or not is_equal_approx(fragment_hold.components[0].alpha_mod, 1.0) or not is_equal_approx(fragment_fade.components[0].alpha_mod, 0.5) or not fragment_done.is_empty():
		_fail("ZumaTaurus fragment hold/fade lifecycle mismatch: future=%s hold=%s fade=%s done=%s" % [fragment_future, fragment_hold, fragment_fade, fragment_done])
		return
	for spawn_ground_id in [monk_spawn_ground_id, stone_spawn_ground_id]:
		var spawn_ground_effect := {"source": "monster_spawn_ground", "magicID": spawn_ground_id, "x": special_source.x, "y": special_source.y, "direction": 4, "start_time": now}
		var spawn_future: Dictionary = $WorldRenderer.call("_resolve_magic_effect", spawn_ground_effect, now - 1)
		var spawn_first: Dictionary = $WorldRenderer.call("_resolve_magic_effect", spawn_ground_effect, now)
		var spawn_fade: Dictionary = $WorldRenderer.call("_resolve_magic_effect", spawn_ground_effect, now + 6500)
		var spawn_done: Dictionary = $WorldRenderer.call("_resolve_magic_effect", spawn_ground_effect, now + 8000)
		if spawn_future.is_empty() or not spawn_future.get("components", []).is_empty() or spawn_first.get("components", []).size() != 1 or spawn_first.components[0].frame != 0 or spawn_first.components[0].direction != 3 or not is_equal_approx(spawn_fade.components[0].alpha_mod, 0.5) or not spawn_done.is_empty():
			_fail("monster spawn remnant lifecycle mismatch: id=%d future=%s first=%s fade=%s done=%s" % [spawn_ground_id, spawn_future, spawn_first, spawn_fade, spawn_done])
			return

	for fixed_monster_entry in fixed_monster_attacks:
		var fixed_monster_id: int = fixed_monster_entry.id
		var trigger_frame: int = fixed_monster_entry.frame
		if not $WorldRenderer.supports_monster_attack_magic(fixed_monster_id):
			_fail("fixed monster attack magic was not recognized: %d" % fixed_monster_id)
			return
		var monster_fixed := {
			"source": "monster_attack", "magicID": fixed_monster_id, "uid": target_uid,
			"x": 405, "y": 120, "aimUID": GameState.player_uid,
			"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
		}
		var trigger_ms := trigger_frame * 100
		var before_monster_fixed: Dictionary = $WorldRenderer.call("_resolve_magic_effect", monster_fixed, now + trigger_ms - 1)
		if before_monster_fixed.is_empty() or not before_monster_fixed.get("components", []).is_empty():
			_fail("fixed monster attack triggered before frame %d: id=%d state=%s" % [trigger_frame, fixed_monster_id, before_monster_fixed])
			return
		var active_monster_fixed: Dictionary = $WorldRenderer.call("_resolve_magic_effect", monster_fixed, now + trigger_ms)
		var fixed_components: Array = active_monster_fixed.get("components", [])
		if fixed_components.size() != 1 or fixed_components[0].meta != resources.magic_layout(fixed_monster_id, 2) or fixed_components[0].position != Vector2(405, 120) or fixed_components[0].direction != 2:
			_fail("fixed monster attack frame-%d placement/direction mismatch: id=%d state=%s" % [trigger_frame, fixed_monster_id, active_monster_fixed])
			return

	for target_monster_entry in target_monster_attacks:
		var target_monster_id: int = target_monster_entry.id
		var target_trigger_frame: int = target_monster_entry.frame
		var target_kind: String = target_monster_entry.kind
		if not $WorldRenderer.supports_monster_attack_magic(target_monster_id):
			_fail("target monster attack magic was not recognized: %d" % target_monster_id)
			return
		GameState.attached_magic_effects.clear()
		var target_monster_effect := {
			"source": "monster_attack", "magicID": target_monster_id, "uid": GameState.player_uid,
			"x": 405, "y": 120, "aimUID": target_uid,
			"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
		}
		var target_trigger_ms := target_trigger_frame * 100
		var before_target_attack: Dictionary = $WorldRenderer.call("_resolve_magic_effect", target_monster_effect, now + target_trigger_ms - 1)
		if before_target_attack.is_empty() or not GameState.attached_magic_effects.is_empty():
			_fail("target monster attack triggered before frame %d: id=%d" % [target_trigger_frame, target_monster_id])
			return
		$WorldRenderer.call("_resolve_magic_effect", target_monster_effect, now + target_trigger_ms)
		var spawned_target_effect: Dictionary = GameState.attached_magic_effects.back() if not GameState.attached_magic_effects.is_empty() else {}
		if spawned_target_effect.get("magicID", 0) != target_monster_id or spawned_target_effect.get("target_uid", 0) != target_uid or spawned_target_effect.get("kind", "") != target_kind or spawned_target_effect.get("stage", 0) != 2:
			_fail("target monster attack attachment mismatch: %s" % spawned_target_effect)
			return
		var target_active: Dictionary = $WorldRenderer.call("_resolve_attached_magic", now + target_trigger_ms + 100)
		var target_resolved: Dictionary = target_active.get(target_uid, [{}])[0]
		if target_resolved.get("meta", PackedInt32Array()) != resources.magic_layout(target_monster_id, 2):
			_fail("target monster attack run metadata mismatch: %s" % target_resolved)
			return
		if target_kind == "ant_healing" and target_resolved.get("shift_y", 0) != -3:
			_fail("ant healing frame lift mismatch: %s" % target_resolved)
			return
		if target_kind == "thunderbolt" and not target_resolved.get("mirror_vertical", false):
			_fail("monster thunderbolt did not extend its first frames: %s" % target_resolved)
			return
	GameState.attached_magic_effects.clear()

	for monster_motion_id in monster_motion_attacks:
		if not $WorldRenderer.supports_monster_attack_magic(monster_motion_id):
			_fail("monster motion-sync magic was not recognized: %d" % monster_motion_id)
			return
		GameState.attached_magic_effects.clear()
		var monster_motion_effect := {
			"source": "monster_attack", "magicID": monster_motion_id, "uid": GameState.player_uid,
			"x": 405, "y": 120, "aimUID": target_uid,
			"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
		}
		$WorldRenderer.call("_resolve_magic_effect", monster_motion_effect, now + 399)
		if not GameState.attached_magic_effects.is_empty():
			_fail("monster motion-sync impact triggered before frame 4: %d" % monster_motion_id)
			return
		$WorldRenderer.call("_resolve_magic_effect", monster_motion_effect, now + 400)
		var motion_impact: Dictionary = GameState.attached_magic_effects.back() if not GameState.attached_magic_effects.is_empty() else {}
		if motion_impact.get("magicID", 0) != monster_motion_id or motion_impact.get("target_uid", 0) != target_uid or motion_impact.get("stage", 0) != 3 or motion_impact.get("play_seff", false):
			_fail("monster motion-sync impact mismatch: %s" % motion_impact)
			return
		var before_motion_run: Dictionary = $WorldRenderer.call("_monster_attack_motion_effect_state", monster_motion_id, 3, now, 100, 6, now + 299)
		var first_motion_run: Dictionary = $WorldRenderer.call("_monster_attack_motion_effect_state", monster_motion_id, 3, now, 100, 6, now + 300)
		if before_motion_run.get("visible", false) or not first_motion_run.get("visible", false) or first_motion_run.get("frame", -1) != 0 or first_motion_run.get("direction", -1) != 2 or first_motion_run.get("meta", PackedInt32Array()) != resources.magic_layout(monster_motion_id, 2):
			_fail("monster wand motion-sync run mismatch: before=%s first=%s" % [before_motion_run, first_motion_run])
			return
	GameState.attached_magic_effects.clear()
	var shipwreck_motion: Dictionary = $WorldRenderer.call("_monster_attack_motion_effect_state", shipwreck_blade_id, 5, now, 100, 6, now + 500)
	var shipwreck_done: Dictionary = $WorldRenderer.call("_monster_attack_motion_effect_state", shipwreck_blade_id, 5, now, 100, 6, now + 600)
	if not shipwreck_motion.get("visible", false) or shipwreck_motion.get("frame", -1) != 5 or shipwreck_motion.get("direction", -1) != 4 or shipwreck_motion.get("meta", PackedInt32Array()) != resources.magic_layout(shipwreck_blade_id, 2) or not shipwreck_done.is_empty():
		_fail("shipwreck blade motion-sync mismatch: active=%s done=%s" % [shipwreck_motion, shipwreck_done])
		return

	for monster_projectile_entry in monster_projectile_attacks:
		var monster_projectile_id: int = monster_projectile_entry.id
		var projectile_trigger_frame: int = monster_projectile_entry.frame
		var expected_gfx_direction: int = monster_projectile_entry.gfx_direction
		if not $WorldRenderer.supports_monster_attack_magic(monster_projectile_id):
			_fail("monster projectile magic was not recognized: %d" % monster_projectile_id)
			return
		GameState.attached_magic_effects.clear()
		var monster_projectile := {
			"source": "monster_attack", "magicID": monster_projectile_id, "uid": GameState.player_uid,
			"x": 405, "y": 120, "aimUID": target_uid,
			"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
		}
		$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(409 * 48, 120 * 32)}})
		var projectile_trigger_ms := projectile_trigger_frame * 100
		var before_monster_projectile: Dictionary = $WorldRenderer.call("_resolve_magic_effect", monster_projectile, now + projectile_trigger_ms - 1)
		if before_monster_projectile.is_empty() or not before_monster_projectile.get("components", []).is_empty() or monster_projectile.has("_projectile_position"):
			_fail("monster projectile launched before frame %d: id=%d state=%s" % [projectile_trigger_frame, monster_projectile_id, before_monster_projectile])
			return
		var active_monster_projectile: Dictionary = $WorldRenderer.call("_resolve_magic_effect", monster_projectile, now + projectile_trigger_ms)
		var monster_projectile_components: Array = active_monster_projectile.get("components", [])
		var monster_projectile_position: Vector2 = monster_projectile.get("_projectile_position", Vector2.ZERO)
		var monster_projectile_source := Vector2(405 * 48, 120 * 32)
		if monster_projectile_components.size() != 1 or monster_projectile_components[0].meta != resources.magic_layout(monster_projectile_id, 2) or monster_projectile_components[0].direction != expected_gfx_direction or monster_projectile.get("_projectile_fly_direction", -1) != 4 or monster_projectile_position.distance_to(monster_projectile_source) < 19.0:
			_fail("monster projectile launch mismatch: id=%d state=%s effect=%s" % [monster_projectile_id, active_monster_projectile, monster_projectile])
			return
		var monster_target_offset := Vector2(resources.magic_target_offset(monster_projectile_id, 2, expected_gfx_direction))
		$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": monster_projectile_position + monster_target_offset + Vector2(1, 1)}})
		$WorldRenderer.call("_resolve_magic_effect", monster_projectile, now + projectile_trigger_ms + 17)
		var expects_impact: bool = not resources.magic_layout(monster_projectile_id, 3).is_empty()
		if expects_impact:
			var monster_impact: Dictionary = GameState.attached_magic_effects.back() if not GameState.attached_magic_effects.is_empty() else {}
			if monster_impact.get("magicID", 0) != monster_projectile_id or monster_impact.get("stage", 0) != 3 or monster_impact.get("target_uid", 0) != target_uid or monster_impact.get("play_seff", false):
				_fail("monster projectile impact mismatch: id=%d effect=%s" % [monster_projectile_id, monster_impact])
				return
		elif not GameState.attached_magic_effects.is_empty():
			_fail("monster projectile without explode stage created impact: id=%d" % monster_projectile_id)
			return
	GameState.attached_magic_effects.clear()

	if not $WorldRenderer.supports_monster_attack_magic(dual_axe_id):
		_fail("dual-axe monster attack magic was not recognized")
		return
	GameState.attached_magic_effects.clear()
	var axe_effect := {
		"source": "monster_attack", "magicID": dual_axe_id, "uid": target_uid,
		"x": 405, "y": 120, "aimUID": target_uid,
		"direction": 3, "speed": 100, "start_time": now, "_seff_stage_mask": 0xFFFF,
	}
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(409 * 48, 120 * 32)}})
	var before_axe: Dictionary = $WorldRenderer.call("_resolve_magic_effect", axe_effect, now + 399)
	if before_axe.is_empty() or not before_axe.get("components", []).is_empty():
		_fail("dual axe launched before attack frame 4: %s" % before_axe)
		return
	var active_axe: Dictionary = $WorldRenderer.call("_resolve_magic_effect", axe_effect, now + 400)
	var axe_components: Array = active_axe.get("components", [])
	var axe_source := Vector2(405 * 48, 120 * 32)
	var axe_position: Vector2 = axe_effect.get("_projectile_position", Vector2.ZERO)
	if axe_components.size() != 1 or axe_components[0].meta != resources.magic_layout(dual_axe_id, 2) or axe_components[0].direction != 2 or axe_effect.get("_projectile_fly_direction", -1) != 4 or axe_position.distance_to(axe_source) < 19.0:
		_fail("dual axe frame-4 direction/movement mismatch: state=%s effect=%s" % [active_axe, axe_effect])
		return
	var axe_offset := Vector2(resources.magic_target_offset(dual_axe_id, 2, 2))
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": axe_position + axe_offset + Vector2(1, 1)}})
	$WorldRenderer.call("_resolve_magic_effect", axe_effect, now + 417)
	if GameState.attached_magic_effects.size() != 1 or GameState.attached_magic_effects[0].get("magicID", 0) != dual_axe_id or GameState.attached_magic_effects[0].get("stage", 0) != 3:
		_fail("dual axe impact did not create its split attachment: %s" % GameState.attached_magic_effects)
		return
	GameState.attached_magic_effects.clear()

	for fixed_projectile_id in fixed_projectile_ids:
		var fixed_projectile := projectile_effect.duplicate(true)
		fixed_projectile["magicID"] = fixed_projectile_id
		fixed_projectile.erase("_projectile_position")
		fixed_projectile.erase("_projectile_start")
		fixed_projectile.erase("_projectile_fly_direction")
		fixed_projectile.erase("_projectile_gfx_direction")
		fixed_projectile.erase("_projectile_last_fly_offset")
		fixed_projectile.erase("_projectile_step_count")
		fixed_projectile.erase("_projectile_done")
		fixed_projectile.erase("_projectile_impact_spawned")
		$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(409 * 48, 120 * 32)}})
		var fixed_projectile_trigger: int = $WorldRenderer.call("_hero_spell_trigger_delay", fixed_projectile_id, 4)
		var fixed_projectile_state: Dictionary = $WorldRenderer.call("_resolve_magic_effect", fixed_projectile, now + fixed_projectile_trigger)
		var fixed_run_meta: PackedInt32Array = resources.magic_layout(fixed_projectile_id, 2)
		var fixed_components: Array = fixed_projectile_state.get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == fixed_run_meta)
		if fixed_components.size() != 1 or fixed_components[0].direction != 0:
			_fail("fixed-gfx projectile direction mismatch: id=%d state=%s" % [fixed_projectile_id, fixed_projectile_state])
			return

	GameState.attached_magic_effects.clear()
	var missing_projectile := projectile_effect.duplicate(true)
	for key in ["_projectile_position", "_projectile_start", "_projectile_fly_direction", "_projectile_gfx_direction", "_projectile_last_fly_offset", "_projectile_step_count", "_projectile_impact_spawned", "_projectile_done"]:
		missing_projectile.erase(key)
	$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(409 * 48, 120 * 32)}})
	$WorldRenderer.call("_resolve_magic_effect", missing_projectile, now + projectile_trigger)
	var last_offset: Vector2 = missing_projectile.get("_projectile_last_fly_offset", Vector2.ZERO)
	GameState.creatures.erase(target_uid)
	$WorldRenderer.set("_actor_target_rects", {})
	var missing_before: Vector2 = missing_projectile.get("_projectile_position", Vector2.ZERO)
	$WorldRenderer.call("_resolve_magic_effect", missing_projectile, now + projectile_trigger + 17)
	if missing_projectile.get("_projectile_position", Vector2.ZERO) != missing_before + last_offset:
		_fail("missing-target projectile did not continue its last direction")
		return
	missing_projectile["_projectile_position"] = Vector2(missing_projectile.get("_projectile_start", Vector2.ZERO)) + Vector2(256 * 48, 0)
	var expired_projectile: Dictionary = $WorldRenderer.call("_resolve_magic_effect", missing_projectile, now + projectile_trigger + 34)
	var expired_run_components: Array = expired_projectile.get("components", []).filter(func(component: Dictionary) -> bool: return component.meta == fireball_run)
	if not expired_run_components.is_empty() or not GameState.attached_magic_effects.is_empty():
		_fail("missing-target projectile did not expire silently after 255 grids")
		return
	GameState.creatures[target_uid] = {"uid": target_uid, "x": 409, "y": 120, "type": 1, "monster_id": 1, "direction": 7}

	var cast_data := {
		"uid": GameState.player_uid, "mapUID": GameState.player_map_uid,
		"x": 405, "y": 120, "aimX": 409, "aimY": 120, "aimUID": target_uid,
	}
	cast_data["magic"] = fireball_id
	if GameState.add_cast_magic_attachment(cast_data, "火球术") or not GameState.attached_magic_effects.is_empty():
		_fail("ordinary cast unexpectedly created an attached effect")
		return
	cast_data["magic"] = shield_id
	if not GameState.add_cast_magic_attachment(cast_data, "魔法盾"):
		_fail("magic shield attachment rejected")
		return
	var shield: Dictionary = GameState.attached_magic_effects.back()
	if shield.get("target_uid", 0) != GameState.player_uid or shield.get("cycles", 0) != -1 or shield.get("kind", "") != "shield":
		_fail("magic shield attachment metadata mismatch: %s" % shield)
		return
	shield.start_time = now
	var attached: Dictionary = $WorldRenderer.call("_resolve_attached_magic", now)
	var player_attached: Array = attached.get(GameState.player_uid, [])
	if player_attached.size() != 1 or player_attached[0].get("magic_id", 0) != shield_id or player_attached[0].get("kind", "") != "shield" or not is_equal_approx(player_attached[0].get("alpha_mod", 0.0), 240.0 / 255.0):
		_fail("magic shield alpha/layer resolution mismatch: %s" % attached)
		return
	var shield_under: Dictionary = $WorldRenderer.call("_hero_attached_magic_draw_policy", shield_id, "shield", 2, false, 240.0 / 255.0)
	var shield_over: Dictionary = $WorldRenderer.call("_hero_attached_magic_draw_policy", shield_id, "shield", 2, true, 240.0 / 255.0)
	var ordinary_under: Dictionary = $WorldRenderer.call("_hero_attached_magic_draw_policy", healing_id, "action_attachment", 2, false, 1.0)
	var ordinary_over: Dictionary = $WorldRenderer.call("_hero_attached_magic_draw_policy", healing_id, "action_attachment", 2, true, 1.0)
	var talisman_up: Dictionary = $WorldRenderer.call("_hero_attached_magic_draw_policy", soul_talisman_id, "projectile_impact", 2, true, 1.0)
	var talisman_down: Dictionary = $WorldRenderer.call("_hero_attached_magic_draw_policy", soul_talisman_id, "projectile_impact", 5, true, 1.0)
	if not shield_under.draw or not shield_over.draw or not is_equal_approx(shield_under.alpha_mod, 240.0 / 255.0) or not is_equal_approx(shield_over.alpha_mod, 240.0 / 255.0):
		_fail("shield under/overlay alpha policy mismatch: under=%s over=%s" % [shield_under, shield_over])
		return
	if not ordinary_under.draw or not is_equal_approx(ordinary_under.alpha_mod, 1.0) or not ordinary_over.draw or not is_equal_approx(ordinary_over.alpha_mod, 240.0 / 255.0):
		_fail("ordinary attachment under/overlay policy mismatch: under=%s over=%s" % [ordinary_under, ordinary_over])
		return
	if talisman_up.draw or not talisman_down.draw or not is_equal_approx(talisman_down.alpha_mod, 1.0):
		_fail("soul talisman direction-layer policy mismatch: up=%s down=%s" % [talisman_up, talisman_down])
		return
	var shield_meta: PackedInt32Array = resources.magic_layout(shield_id, 2)
	var shield_hit_meta: PackedInt32Array = resources.magic_layout(shield_id, 5)
	if shield_hit_meta.is_empty() or shield_hit_meta[2] != 3 or not GameState.trigger_shield_hit(GameState.player_uid):
		_fail("magic shield hit stage unavailable")
		return
	var shield_hit_start: int = shield.get("start_time", 0)
	var shield_hit_active: Dictionary = $WorldRenderer.call("_resolve_attached_magic", shield_hit_start)
	if shield.get("stage", 0) != 5 or shield.get("kind", "") != "shield_hit" or shield_hit_active.get(GameState.player_uid, [])[0].meta != shield_hit_meta:
		_fail("magic shield did not switch to the hit graphics: %s active=%s" % [shield, shield_hit_active])
		return
	if not GameState.trigger_shield_hit(GameState.player_uid) or GameState.trigger_shield_hit(target_uid):
		_fail("magic shield repeated/missing-target hit handling mismatch")
		return
	shield_hit_start = shield.get("start_time", 0)
	var shield_hit_duration := maxi(100, roundi(shield_hit_meta[2] * 1000.0 / (10.0 * shield_hit_meta[4] / 100.0)))
	var shield_resumed: Dictionary = $WorldRenderer.call("_resolve_attached_magic", shield_hit_start + shield_hit_duration)
	if shield.get("stage", 0) != 2 or shield.get("kind", "") != "shield" or shield_resumed.get(GameState.player_uid, []).is_empty() or shield_resumed[GameState.player_uid][0].meta != resources.magic_loop_layout(shield_id, 2):
		_fail("magic shield did not resume its run cycle after hit: %s active=%s" % [shield, shield_resumed])
		return
	var shield_duration: int = maxi(100, roundi(shield_meta[2] * 1000.0 / (10.0 * shield_meta[4] / 100.0)))
	shield.start_time = now - shield_duration
	attached = $WorldRenderer.call("_resolve_attached_magic", now)
	if attached.get(GameState.player_uid, []).size() != 1:
		_fail("magic shield second cycle missing")
		return
	shield.start_time = now - shield_duration * 100
	attached = $WorldRenderer.call("_resolve_attached_magic", now)
	if not attached.has(GameState.player_uid) or attached[GameState.player_uid][0].meta != resources.magic_loop_layout(shield_id, 2):
		_fail("magic shield expired or lost loop range after sustained playback")
		return
	if not GameState.add_cast_magic_attachment(cast_data, "魔法盾") or GameState.attached_magic_effects.size() != 1:
		_fail("shield recast stacked attachments")
		return

	cast_data["magic"] = ring_id
	GameState.add_cast_magic_attachment(cast_data, "阴阳法环")
	var ring: Dictionary = GameState.attached_magic_effects.back()
	var ring_meta: PackedInt32Array = resources.magic_layout(ring_id, 2)
	var ring_duration: int = maxi(100, roundi(ring_meta[2] * 1000.0 / (10.0 * ring_meta[4] / 100.0)))
	var ring_elapsed := mini(100, ring_duration - 1)
	ring.start_time = now - ring_duration - ring_elapsed
	attached = $WorldRenderer.call("_resolve_attached_magic", now)
	var ring_alpha: float = attached.get(GameState.player_uid, [])[-1].get("alpha_mod", 0.0)
	var expected_ring_alpha := maxf(absf(cos(float(ring_elapsed) / 800.0)), 32.0 / 255.0)
	if not is_equal_approx(ring_alpha, expected_ring_alpha):
		_fail("yin-yang ring second-cycle alpha mismatch: %f" % ring_alpha)
		return
	ring.start_time = now - ring_duration - 12345
	attached = $WorldRenderer.call("_resolve_attached_magic", now)
	if attached.get(GameState.player_uid, []).size() != 2 or attached[GameState.player_uid][-1].meta != resources.magic_loop_layout(ring_id, 2):
		_fail("ring did not persist on its final loop frame alongside shield")
		return

	GameState.attached_magic_effects.clear()
	cast_data["magic"] = thunder_id
	GameState.add_cast_magic_attachment(cast_data, "雷电术")
	var thunder: Dictionary = GameState.attached_magic_effects.back()
	thunder.start_time = now
	thunder["play_seff"] = false
	attached = $WorldRenderer.call("_resolve_attached_magic", now)
	var target_attached: Array = attached.get(target_uid, [])
	if target_attached.size() != 1 or not target_attached[0].get("mirror_vertical", false):
		_fail("thunderbolt target/mirror resolution mismatch: %s" % attached)
		return

	# Restore effects because the render pass consumes expired source records.
	var visual_now := Time.get_ticks_msec()
	var hellfire_visual := special_effect.duplicate(true)
	hellfire_visual["start_time"] = visual_now - 300 - 100 - hellfire_trigger - 700
	var ice_visual := ice_effect.duplicate(true)
	ice_visual["x"] = ice_source.x
	ice_visual["y"] = ice_source.y
	ice_visual["aimX"] = ice_source.x + 8
	ice_visual["aimY"] = ice_source.y
	ice_visual["direction"] = 7 if ice_source.y == special_source.y else 3
	ice_visual["start_time"] = visual_now - 300 - 100 - 500
	var visual_ice_state: Dictionary = $WorldRenderer.call("_resolve_magic_effect", ice_visual, visual_now)
	if visual_ice_state.get("components", []).is_empty() or visual_ice_state.get("underlays", []).is_empty():
		_fail("ice visual phase resolved empty: state=%s kind=%s source=%s id=%d run=%d elapsed=%d" % [visual_ice_state, $WorldRenderer.call("_special_magic_kind", int(ice_visual.get("magicID", 0))), ice_visual.get("source", ""), ice_visual.get("magicID", 0), resources.magic_layout(int(ice_visual.get("magicID", 0)), 2).size(), visual_now - int(ice_visual.get("start_time", visual_now))])
		return
	var on_ground_component_count := 0
	for component_value in visual_ice_state.get("components", []):
		var component: Dictionary = component_value
		if component.get("on_ground", false):
			on_ground_component_count += 1
		var component_meta: PackedInt32Array = component.meta
		var texture_id: int = component_meta[0] + int(component.direction) * component_meta[3] + int(component.frame)
		if resources.frame("magic", texture_id).is_empty():
			_fail("ice visual component texture missing: %08X" % texture_id)
			return
	if on_ground_component_count < 2:
		_fail("ice thorn components lost original on-ground row depth")
		return
	GameState.player_x = special_source.x
	GameState.player_y = special_source.y
	GameState.view_x = special_source.x * 48 - 240
	GameState.view_y = roundi(float(special_source.y + ice_source.y) * 16.0) - 260
	GameState.magic_effects = [hellfire_visual, ice_visual, fireball]
	GameState.attached_magic_effects = [shield, thunder]
	shield.start_time = now
	thunder.start_time = now
	$WorldRenderer.queue_redraw()
	await get_tree().process_frame
	if OS.has_environment("MIR2X_MAGIC_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MAGIC_SCREENSHOT"))
	if OS.has_environment("MIR2X_ICE_SCREENSHOT"):
		GameState.magic_effects = [ice_visual]
		GameState.view_x = ice_source.x * 48 - 240
		GameState.view_y = ice_source.y * 32 - 260
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_ICE_SCREENSHOT"))
	if OS.has_environment("MIR2X_PROPAGATED_SCREENSHOT"):
		var propagated_now := Time.get_ticks_msec()
		var wind_visual := wind_effect.duplicate(true)
		wind_visual["start_time"] = propagated_now - int($WorldRenderer.call("_hero_spell_trigger_delay", wind_chain_id, 4)) - 3 * wind_run_duration - 200
		var laser_visual := laser_effect.duplicate(true)
		laser_visual["x"] = ice_source.x
		laser_visual["y"] = ice_source.y
		laser_visual["start_time"] = propagated_now - int($WorldRenderer.call("_hero_spell_trigger_delay", laser_id, 3)) - 200
		GameState.magic_effects = [wind_visual, laser_visual]
		GameState.view_x = special_source.x * 48 - 240
		GameState.view_y = roundi(float(special_source.y + ice_source.y) * 16.0) - 260
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_PROPAGATED_SCREENSHOT"))
	if OS.has_environment("MIR2X_LASER_SCREENSHOT"):
		var laser_now := Time.get_ticks_msec()
		var laser_capture := laser_effect.duplicate(true)
		laser_capture["x"] = ice_source.x
		laser_capture["y"] = ice_source.y
		laser_capture["start_time"] = laser_now - int($WorldRenderer.call("_hero_spell_trigger_delay", laser_id, 3)) - 200
		GameState.magic_effects = [laser_capture]
		GameState.view_x = ice_source.x * 48 - 240
		GameState.view_y = ice_source.y * 32 - 260
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_LASER_SCREENSHOT"))
	if OS.has_environment("MIR2X_ATTACHMENT_SCREENSHOT"):
		var attachment_now := Time.get_ticks_msec()
		GameState.magic_effects.clear()
		GameState.firewalls.clear()
		GameState.player_action_type = 2
		GameState.player_action_started_ms = attachment_now
		GameState.creatures[target_uid] = {"uid": target_uid, "x": 409, "y": 120, "type": 1, "monster_id": 1, "direction": 7}
		GameState.attached_magic_effects = [
			{"magicID": healing_id, "target_uid": target_uid, "start_time": attachment_now - 300, "cycles": 1, "kind": "action_attachment"},
			{"magicID": healing_id, "target_uid": GameState.player_uid, "start_time": attachment_now - 300, "cycles": 1, "kind": "action_attachment"},
		]
		GameState.view_x = 409 * 48 - 400
		GameState.view_y = 120 * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_ATTACHMENT_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_TARGET_ATTACK_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("target monster-attack visual map failed to load")
			return
		var target_attack_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if target_attack_source.x < 0:
			_fail("no open target monster-attack visual fixture")
			return
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var target_attack_now := Time.get_ticks_msec()
		var target_attack_uids := [target_uid, target_uid + 1, target_uid + 2, target_uid + 3]
		GameState.creatures = {
			target_attack_uids[0]: {"uid": target_attack_uids[0], "x": target_attack_source.x - 2, "y": target_attack_source.y - 3, "type": 1, "monster_id": 1, "direction": 3, "action_type": 2},
			target_attack_uids[1]: {"uid": target_attack_uids[1], "x": target_attack_source.x + 2, "y": target_attack_source.y - 3, "type": 1, "monster_id": 1, "direction": 5, "action_type": 2},
			target_attack_uids[2]: {"uid": target_attack_uids[2], "x": target_attack_source.x - 2, "y": target_attack_source.y, "type": 1, "monster_id": 1, "direction": 7, "action_type": 2},
			target_attack_uids[3]: {"uid": target_attack_uids[3], "x": target_attack_source.x + 2, "y": target_attack_source.y, "type": 1, "monster_id": 1, "direction": 1, "action_type": 2},
		}
		GameState.magic_effects.clear()
		GameState.firewalls.clear()
		GameState.attached_magic_effects = [
			{"magicID": target_monster_attacks[0].id, "target_uid": target_attack_uids[0], "start_time": target_attack_now - 100, "cycles": 1, "kind": "ant_healing", "stage": 2},
			{"magicID": target_monster_attacks[1].id, "target_uid": target_attack_uids[1], "start_time": target_attack_now - 100, "cycles": 1, "kind": "attachment", "stage": 2},
			{"magicID": target_monster_attacks[2].id, "target_uid": target_attack_uids[2], "start_time": target_attack_now - 100, "cycles": 1, "kind": "attachment", "stage": 2},
			{"magicID": target_monster_attacks[3].id, "target_uid": target_attack_uids[3], "start_time": target_attack_now - 100, "cycles": 1, "kind": "thunderbolt", "stage": 2},
		]
		GameState.view_x = target_attack_source.x * 48 - 400
		GameState.view_y = (target_attack_source.y - 2) * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_TARGET_ATTACK_SCREENSHOT"))
	if OS.has_environment("MIR2X_FIXED_ACTION_SCREENSHOT"):
		var fixed_now := Time.get_ticks_msec()
		var ice_roar_visual := fixed_effect.duplicate(true)
		ice_roar_visual["magicID"] = fixed_action_ids[1]
		ice_roar_visual["aimUID"] = 0
		ice_roar_visual["aimX"] = special_source.x
		ice_roar_visual["aimY"] = special_source.y
		ice_roar_visual["start_time"] = fixed_now - 600
		var hit_visual := fixed_effect.duplicate(true)
		hit_visual["magicID"] = hit_wind_id
		hit_visual["aimUID"] = 0
		hit_visual["aimX"] = special_source.x + 5
		hit_visual["aimY"] = special_source.y
		hit_visual["start_time"] = fixed_now - hit_trigger - int($WorldRenderer.call("_magic_frame_duration", hit_run)) - 200
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects = [ice_roar_visual, hit_visual]
		GameState.view_x = (special_source.x + 2) * 48 - 400
		GameState.view_y = special_source.y * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_FIXED_ACTION_SCREENSHOT"))
	if OS.has_environment("MIR2X_PROJECTILE_SCREENSHOT"):
		var projectile_now := Time.get_ticks_msec()
		GameState.creatures[target_uid] = {"uid": target_uid, "x": 413, "y": 120, "type": 1, "monster_id": 1, "direction": 7}
		var projectile_caster_uid := target_uid + 100
		GameState.creatures[projectile_caster_uid] = {
			"uid": projectile_caster_uid, "x": 405, "y": 120, "type": 2, "gender": 1, "desp": {},
			"direction": 3, "action_type": 9, "action_magic_id": fireball_id,
			"action_speed": 100, "action_started_ms": projectile_now - projectile_trigger,
		}
		GameState.player_action_type = 9
		GameState.player_action_magic_id = fireball_id
		GameState.player_action_speed = 100
		GameState.player_action_started_ms = projectile_now - projectile_trigger
		GameState.player_direction = 3
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		var projectile_visual := {
			"source": "action", "magicID": fireball_id, "uid": GameState.player_uid,
			"x": 405, "y": 120, "aimX": 413, "aimY": 120, "aimUID": target_uid,
			"direction": 3, "speed": 100, "start_time": projectile_now - projectile_trigger - 100,
		}
		$WorldRenderer.set("_actor_target_rects", {target_uid: {"world_center": Vector2(413 * 48, 120 * 32)}})
		$WorldRenderer.call("_resolve_magic_effect", projectile_visual, projectile_now)
		if projectile_visual.get("_projectile_step_count", 0) != 7:
			_fail("projectile visual did not pre-roll seven 60Hz steps: %s" % projectile_visual)
			return
		# Map rendering can take longer than one projectile step on CI. Preserve the
		# pre-rolled C++ state while the real display frame is captured.
		projectile_visual["_projectile_step_count"] = 1 << 30
		$WorldRenderer.set("_actor_target_rects", {})
		GameState.magic_effects = [projectile_visual]
		GameState.view_x = 409 * 48 - 400
		GameState.view_y = 120 * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_PROJECTILE_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_ATTACK_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("fixed monster-attack visual map failed to load")
			return
		var monster_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if monster_source.x < 0:
			_fail("no open fixed monster-attack visual fixture")
			return
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var monster_attack_now := Time.get_ticks_msec()
		var monster_target := monster_source + Vector2i(3, 0)
		GameState.creatures[target_uid] = {"uid": target_uid, "x": monster_target.x, "y": monster_target.y, "type": 1, "monster_id": 1, "direction": 7, "action_type": 2}
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects = [
			{"source": "monster_attack", "magicID": tao_dog_fire_id, "uid": target_uid, "x": monster_source.x - 3, "y": monster_source.y - 6, "direction": 3, "speed": 100, "start_time": monster_attack_now - 500},
			{"source": "monster_attack", "magicID": wedge_poison_id, "uid": target_uid, "x": monster_source.x, "y": monster_source.y - 6, "direction": 5, "speed": 100, "start_time": monster_attack_now - 500},
			{"source": "monster_attack", "magicID": fixed_monster_attacks[2].id, "uid": target_uid, "x": monster_source.x + 3, "y": monster_source.y - 6, "direction": 7, "speed": 100, "start_time": monster_attack_now - 500},
			{"source": "monster_attack", "magicID": fixed_monster_attacks[3].id, "uid": target_uid, "x": monster_source.x - 3, "y": monster_source.y - 3, "direction": 2, "speed": 100, "start_time": monster_attack_now - 300},
			{"source": "monster_attack", "magicID": fixed_monster_attacks[4].id, "uid": target_uid, "x": monster_source.x, "y": monster_source.y - 3, "direction": 4, "speed": 100, "start_time": monster_attack_now - 300},
			{"source": "monster_attack", "magicID": fixed_monster_attacks[5].id, "uid": target_uid, "x": monster_source.x + 3, "y": monster_source.y - 3, "direction": 6, "speed": 100, "start_time": monster_attack_now - 300},
			{"source": "monster_attack", "magicID": fixed_monster_attacks[6].id, "uid": target_uid, "x": monster_source.x, "y": monster_source.y, "direction": 8, "speed": 100, "start_time": monster_attack_now - 100},
			{"source": "monster_attack", "magicID": dual_axe_id, "uid": target_uid, "x": monster_source.x - 3, "y": monster_source.y, "aimUID": target_uid, "direction": 3, "speed": 100, "start_time": monster_attack_now - 400},
		]
		GameState.view_x = monster_source.x * 48 - 400
		GameState.view_y = (monster_source.y - 3) * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_ATTACK_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_PROJECTILE_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("monster projectile visual map failed to load")
			return
		var monster_projectile_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if monster_projectile_source.x < 0:
			_fail("no open monster projectile visual fixture")
			return
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var monster_projectile_now := Time.get_ticks_msec()
		var projectile_source_offsets := [
			Vector2i(-4, -4), Vector2i(0, -4), Vector2i(4, -4),
			Vector2i(-4, -1), Vector2i(0, -1), Vector2i(4, -1),
		]
		GameState.creatures.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects.clear()
		for projectile_index in range(monster_projectile_attacks.size()):
			var projectile_entry: Dictionary = monster_projectile_attacks[projectile_index]
			var projectile_source_grid: Vector2i = monster_projectile_source + projectile_source_offsets[projectile_index]
			var projectile_target_grid := projectile_source_grid + Vector2i(0, 3)
			var projectile_target_uid: int = target_uid + 20 + projectile_index
			GameState.creatures[projectile_target_uid] = {
				"uid": projectile_target_uid, "x": projectile_target_grid.x, "y": projectile_target_grid.y,
				"type": 1, "monster_id": 1, "direction": 1, "action_type": 2,
			}
			GameState.magic_effects.append({
				"source": "monster_attack", "magicID": projectile_entry.id, "uid": GameState.player_uid,
				"x": projectile_source_grid.x, "y": projectile_source_grid.y, "aimUID": projectile_target_uid,
				"direction": 5, "speed": 100,
				"start_time": monster_projectile_now - int(projectile_entry.frame) * 100,
			})
		GameState.view_x = monster_projectile_source.x * 48 - 400
		GameState.view_y = (monster_projectile_source.y - 1) * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_PROJECTILE_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_MOTION_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("monster motion-sync visual map failed to load")
			return
		var motion_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if motion_source.x < 0:
			_fail("no open monster motion-sync visual fixture")
			return
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var motion_now := Time.get_ticks_msec()
		var physical_id: int = resources.magic_id("物理攻击")
		var motion_visuals := [
			{"monster_id": 223, "magic_id": physical_id, "offset": Vector2i(-4, 1)},
			{"monster_id": 237, "magic_id": monster_motion_attacks[0], "offset": Vector2i(0, 1)},
			{"monster_id": 242, "magic_id": monster_motion_attacks[1], "offset": Vector2i(4, 1)},
		]
		GameState.creatures.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects.clear()
		for motion_index in range(motion_visuals.size()):
			var motion_visual: Dictionary = motion_visuals[motion_index]
			var motion_grid: Vector2i = motion_source + motion_visual.offset
			var motion_uid: int = (int(motion_visual.monster_id) << 35) | (850 + motion_index)
			GameState.creatures[motion_uid] = {
				"uid": motion_uid, "x": motion_grid.x, "y": motion_grid.y,
				"type": 1, "monster_id": motion_visual.monster_id,
				"direction": 5, "action_type": 7, "action_speed": 100,
				"action_started_ms": motion_now - 400, "action_magic_id": motion_visual.magic_id,
			}
		GameState.view_x = motion_source.x * 48 - 400
		GameState.view_y = (motion_source.y + 1) * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_MOTION_SCREENSHOT"))
	if OS.has_environment("MIR2X_ZUMA_MAGIC_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("ZumaTaurus magic visual map failed to load")
			return
		var zuma_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if zuma_source.x < 0:
			_fail("no open ZumaTaurus magic visual fixture")
			return
		var zuma_monster_id := 0
		for monster_id_value in resources.monster_meta:
			if resources.monster_transform_effect_magic_id(int(monster_id_value)) == zuma_fragment_id:
				zuma_monster_id = int(monster_id_value)
				break
		if zuma_monster_id == 0:
			_fail("ZumaTaurus visual monster metadata unavailable")
			return
		var zuma_now := Time.get_ticks_msec()
		var zuma_uid: int = (zuma_monster_id << 35) | 880
		GameState.creatures = {zuma_uid: {
			"uid": zuma_uid, "x": zuma_source.x, "y": zuma_source.y,
			"type": 1, "monster_id": zuma_monster_id, "direction": 3,
			"action_type": 7, "action_speed": 100,
			"action_started_ms": zuma_now - 500, "action_magic_id": zuma_hellfire_id,
		}}
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects = [
			{
				"source": "monster_attack", "magicID": zuma_hellfire_id, "uid": zuma_uid,
				"x": zuma_source.x, "y": zuma_source.y, "aimX": zuma_source.x + 8, "aimY": zuma_source.y,
				"direction": 7, "speed": 100, "start_time": zuma_now - 500,
				"_special_seff_mask": 0xFF,
			},
			{
				"source": "monster_transform", "magicID": zuma_fragment_id,
				"x": zuma_source.x + 4, "y": zuma_source.y,
				"start_time": zuma_now - 4000,
			},
		]
		GameState.view_x = zuma_source.x * 48 - 400
		GameState.view_y = zuma_source.y * 32 - 360
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_ZUMA_MAGIC_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_SPAWN_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("monster-spawn visual map failed to load")
			return
		var spawn_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if spawn_source.x < 0:
			_fail("no open monster-spawn visual fixture")
			return
		var spawn_visuals: Array[Dictionary] = []
		for monster_id_value in resources.monster_meta:
			var spawn_magic_id: int = resources.monster_spawn_effect_magic_id(int(monster_id_value))
			if spawn_magic_id > 0:
				spawn_visuals.append({"monster_id": int(monster_id_value), "magic_id": spawn_magic_id})
		if spawn_visuals.size() != 2:
			_fail("monster-spawn visual metadata mismatch: %s" % spawn_visuals)
			return
		var spawn_now := Time.get_ticks_msec()
		GameState.creatures.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects.clear()
		for spawn_index in range(spawn_visuals.size()):
			var spawn_visual: Dictionary = spawn_visuals[spawn_index]
			var spawn_grid := spawn_source + Vector2i(spawn_index * 4 - 2, 0)
			var spawn_uid: int = (int(spawn_visual.monster_id) << 35) | (890 + spawn_index)
			GameState.creatures[spawn_uid] = {
				"uid": spawn_uid, "x": spawn_grid.x, "y": spawn_grid.y,
				"type": 1, "monster_id": spawn_visual.monster_id, "direction": 3 + spawn_index * 2,
				"action_type": 1, "action_speed": 100, "action_started_ms": spawn_now - 900,
			}
			GameState.magic_effects.append({
				"source": "monster_spawn_ground", "magicID": spawn_visual.magic_id,
				"uid": spawn_uid, "x": spawn_grid.x, "y": spawn_grid.y,
				"direction": 3 + spawn_index * 2, "start_time": spawn_now - 100,
			})
		GameState.view_x = spawn_source.x * 48 - 400
		GameState.view_y = spawn_source.y * 32 - 400
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_SPAWN_SCREENSHOT"))
		if OS.has_environment("MIR2X_MONSTER_SPAWN_BASELINE_SCREENSHOT"):
			GameState.magic_effects.clear()
			$WorldRenderer.queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_SPAWN_BASELINE_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_BODY_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("monster-body visual map failed to load")
			return
		var body_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if body_source.x < 0:
			_fail("no open monster-body visual fixture")
			return
		var physical_magic_id: int = resources.magic_id("物理攻击")
		var savage_magic_id: int = resources.magic_id("霸王教主_野蛮冲撞")
		var body_visuals: Array[Dictionary] = []
		var tree_added := false
		for monster_id_value in resources.monster_meta:
			var monster_id: int = monster_id_value
			var stand_sequence: PackedInt32Array = resources.monster_body_sequence(monster_id, 2)
			var attack_sequence: PackedInt32Array = resources.monster_body_sequence(monster_id, 7, physical_magic_id)
			var savage_sequence: PackedInt32Array = resources.monster_body_sequence(monster_id, 7, savage_magic_id)
			var death_sequence: PackedInt32Array = resources.monster_body_sequence(monster_id, 13)
			if stand_sequence == PackedInt32Array([1, 1, -1]):
				body_visuals.append({"monster_id": monster_id, "action": 2, "magic": 0, "offset": Vector2i(-6, 2), "elapsed": 0})
			elif stand_sequence == PackedInt32Array([0, 1, -1]):
				body_visuals.append({"monster_id": monster_id, "action": 7, "magic": physical_magic_id, "offset": Vector2i(-5, -1), "elapsed": 900})
			elif attack_sequence == PackedInt32Array([6, 6, -1]):
				body_visuals.append({"monster_id": monster_id, "action": 7, "magic": resources.magic_id("诺玛大法老_雷电术"), "offset": Vector2i(-2, -1), "elapsed": 500})
			elif attack_sequence == PackedInt32Array([2, 10, -1]) and savage_sequence == PackedInt32Array([6, 10, -1]):
				body_visuals.append({"monster_id": monster_id, "action": 7, "magic": savage_magic_id, "offset": Vector2i(2, -1), "elapsed": 900})
			elif death_sequence == PackedInt32Array([0, 4, 0]) and not tree_added:
				tree_added = true
				body_visuals.append({"monster_id": monster_id, "action": 13, "magic": 0, "offset": Vector2i(6, 1), "elapsed": 300})
			elif stand_sequence == PackedInt32Array([0, 4, 0]) and death_sequence != PackedInt32Array([0, 4, 0]):
				body_visuals.append({"monster_id": monster_id, "action": 7, "magic": 0, "offset": Vector2i(-2, 3), "elapsed": 500})
			elif resources.monster_spawn_direction(monster_id) == 6 and not body_visuals.any(func(entry: Dictionary) -> bool: return entry.get("spawn_direction", false)):
				body_visuals.append({"monster_id": monster_id, "action": 2, "magic": 0, "offset": Vector2i(2, 3), "elapsed": 0, "spawn_direction": true})
		if body_visuals.size() != 7:
			_fail("monster-body visual metadata mismatch: %s" % body_visuals)
			return
		var body_now := Time.get_ticks_msec()
		GameState.creatures.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects.clear()
		for body_index in range(body_visuals.size()):
			var visual: Dictionary = body_visuals[body_index]
			var body_grid: Vector2i = body_source + visual.offset
			var body_uid: int = (int(visual.monster_id) << 35) | (910 + body_index)
			GameState.creatures[body_uid] = {
				"uid": body_uid, "x": body_grid.x, "y": body_grid.y,
				"type": 1, "monster_id": visual.monster_id,
				"direction": 6 if visual.get("spawn_direction", false) else 8,
				"action_type": visual.action, "action_magic_id": visual.magic,
				"action_speed": 100, "action_started_ms": body_now - int(visual.elapsed),
			}
		GameState.view_x = body_source.x * 48 - 400
		GameState.view_y = (body_source.y + 1) * 32 - 350
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_BODY_SCREENSHOT"))
	if OS.has_environment("MIR2X_SPELL_GESTURE_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("spell-gesture visual map failed to load")
			return
		var spell_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if spell_source.x < 0:
			_fail("no open spell-gesture visual fixture")
			return
		var spell0_id: int = resources.magic_id("火球术")
		var spell1_id: int = resources.magic_id("治愈术")
		var attack_mode_id: int = resources.magic_id("铁布衫")
		var spell0_meta: PackedInt32Array = resources.magic_layout(spell0_id, 1)
		var spell1_meta: PackedInt32Array = resources.magic_layout(spell1_id, 1)
		var spell0_primary_ms := float(maxi(spell0_meta[2], 8)) * 10000.0 / float(clampi(spell0_meta[4], 20, 500))
		var spell1_primary_ms := float(maxi(spell1_meta[2], 10)) * 10000.0 / float(clampi(spell1_meta[4], 20, 500))
		var spell_now := Time.get_ticks_msec()
		GameState.creatures.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects.clear()
		GameState.player_uid = 920
		GameState.player_x = spell_source.x - 4
		GameState.player_y = spell_source.y
		GameState.player_gender = 0
		GameState.player_direction = 3
		GameState.player_desp = {}
		GameState.player_action_type = 9
		GameState.player_action_magic_id = spell0_id
		GameState.player_action_speed = 100
		GameState.player_action_started_ms = spell_now - ceili(spell0_primary_ms) - 250
		GameState.creatures[921] = {
			"uid": 921, "x": spell_source.x, "y": spell_source.y, "type": 2,
			"gender": 1, "desp": {}, "direction": 7, "action_type": 9,
			"action_magic_id": spell1_id, "action_speed": 100,
			"action_started_ms": spell_now - maxi(300, floori(spell1_primary_ms) - 150),
		}
		GameState.creatures[922] = {
			"uid": 922, "x": spell_source.x + 4, "y": spell_source.y, "type": 2,
			"gender": 0, "desp": {}, "direction": 3, "action_type": 9,
			"action_magic_id": attack_mode_id, "action_speed": 100,
			"action_started_ms": spell_now - 100,
		}
		GameState.view_x = spell_source.x * 48 - 400
		GameState.view_y = spell_source.y * 32 - 350
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_SPELL_GESTURE_SCREENSHOT"))
	if OS.has_environment("MIR2X_SPACE_MOVE_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("space-move visual map failed to load")
			return
		var space_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if space_source.x < 0:
			_fail("no open space-move visual fixture")
			return
		var space_target := space_source + Vector2i(5, 0)
		# The first real draw decodes the room's native textures synchronously.
		# Keep the deterministic fixture at frame zero while that cache warms up.
		var space_now := Time.get_ticks_msec() + 5000
		GameState.creatures[target_uid] = {"uid": target_uid, "x": space_target.x, "y": space_target.y, "type": 1, "monster_id": 1, "direction": 7, "action_type": 2}
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.magic_effects = [{
			"source": "space_move", "magicID": space_move_id, "uid": target_uid,
			"x": space_source.x, "y": space_source.y, "aimX": space_target.x, "aimY": space_target.y,
			"direction": 3, "speed": 100, "start_time": space_now,
		}]
		GameState.view_x = (space_source.x + 2) * 48 - 400
		# Teleport frames rise 140-179px above the actor anchor. Keep the feet low
		# enough for both the old-grid RUN and destination EXPLODE to stay visible.
		GameState.view_y = space_source.y * 32 - 470
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_SPACE_MOVE_SCREENSHOT"))
		if OS.has_environment("MIR2X_SPACE_MOVE_BASELINE_SCREENSHOT"):
			GameState.magic_effects.clear()
			GameState.attached_magic_effects.clear()
			$WorldRenderer.queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_SPACE_MOVE_BASELINE_SCREENSHOT"))
	if OS.has_environment("MIR2X_MONSTER_DEATH_SCREENSHOT"):
		if not $WorldRenderer.load_map(6):
			_fail("monster-death visual map failed to load")
			return
		var death_source := _find_open_wave_source($WorldRenderer, 8, $WorldRenderer.map_height - 8)
		if death_source.x < 0:
			_fail("no open monster-death visual fixture")
			return
		var death_visual_now := Time.get_ticks_msec()
		GameState.creatures = {target_uid: {
			"uid": target_uid, "x": death_source.x, "y": death_source.y,
			"type": 1, "monster_id": monster_death_monster_id, "direction": 5,
			"action_type": 13, "action_speed": 100, "action_started_ms": death_visual_now - 2000,
		}}
		GameState.magic_effects.clear()
		GameState.firewalls.clear()
		GameState.attached_magic_effects = [{
			"magicID": monster_death_magic_id, "target_uid": target_uid,
			"stage": 2, "kind": "monster_death", "cycles": 1,
			"start_time": death_visual_now + 5000,
		}]
		GameState.view_x = death_source.x * 48 - 400
		GameState.view_y = death_source.y * 32 - 440
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_DEATH_SCREENSHOT"))
		if OS.has_environment("MIR2X_MONSTER_DEATH_BASELINE_SCREENSHOT"):
			GameState.attached_magic_effects.clear()
			$WorldRenderer.queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MONSTER_DEATH_BASELINE_SCREENSHOT"))
	if OS.has_environment("MIR2X_ATTACK_MAGIC_SCREENSHOT"):
		var attack_now := Time.get_ticks_msec()
		GameState.player_x = 405
		GameState.player_y = 120
		GameState.player_action_type = 7
		GameState.player_action_magic_id = flame_sword_id
		GameState.player_action_speed = 100
		GameState.player_action_started_ms = attack_now - 200
		GameState.player_direction = 3
		GameState.magic_effects.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.strike_grids.clear()
		GameState.view_x = GameState.player_x * 48 - 400
		GameState.view_y = GameState.player_y * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_ATTACK_MAGIC_SCREENSHOT"))
	if OS.has_environment("MIR2X_SHIELD_HIT_SCREENSHOT"):
		var shield_visual_now := Time.get_ticks_msec()
		GameState.player_x = 405
		GameState.player_y = 120
		GameState.player_action_type = 11
		GameState.player_action_started_ms = shield_visual_now
		GameState.player_direction = 5
		GameState.magic_effects.clear()
		GameState.firewalls.clear()
		GameState.strike_grids.clear()
		GameState.attached_magic_effects = [{
			"magicID": shield_id, "target_uid": GameState.player_uid,
			"stage": 5, "kind": "shield_hit", "cycles": 1,
			"start_time": shield_visual_now,
		}]
		GameState.view_x = GameState.player_x * 48 - 400
		GameState.view_y = GameState.player_y * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_SHIELD_HIT_SCREENSHOT"))
	if OS.has_environment("MIR2X_ATTACHMENT_LAYER_SCREENSHOT"):
		var layer_visual_now := Time.get_ticks_msec()
		var up_uid: int = (5 << 59) | 801
		var down_uid: int = (5 << 59) | 802
		GameState.player_x = 409
		GameState.player_y = 126
		GameState.player_action_type = 2
		GameState.creatures = {
			up_uid: {"uid": up_uid, "x": 407, "y": 120, "type": 2, "gender": 1, "direction": 2, "action_type": 2},
			down_uid: {"uid": down_uid, "x": 411, "y": 120, "type": 2, "gender": 1, "direction": 5, "action_type": 2},
		}
		GameState.magic_effects.clear()
		GameState.firewalls.clear()
		GameState.strike_grids.clear()
		GameState.attached_magic_effects = [
			{"magicID": soul_talisman_id, "target_uid": up_uid, "stage": 3, "kind": "projectile_impact", "cycles": 1, "start_time": layer_visual_now},
			{"magicID": soul_talisman_id, "target_uid": down_uid, "stage": 3, "kind": "projectile_impact", "cycles": 1, "start_time": layer_visual_now},
		]
		GameState.view_x = 409 * 48 - 400
		GameState.view_y = 120 * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_ATTACHMENT_LAYER_SCREENSHOT"))
	if OS.has_environment("MIR2X_FIREWALL_FADE_SCREENSHOT"):
		var firewall_visual_now := Time.get_ticks_msec()
		GameState.player_x = 405
		GameState.player_y = 120
		GameState.player_action_type = 2
		GameState.creatures.clear()
		GameState.magic_effects.clear()
		GameState.attached_magic_effects.clear()
		GameState.firewalls.clear()
		GameState.strike_grids.clear()
		GameState.reconcile_firewalls([{"x": 407, "y": 122, "count": 2}], firewall_visual_now - 2000, fire_ash_id)
		GameState.reconcile_firewalls([{"x": 407, "y": 122, "count": 1}], firewall_visual_now - 1500, fire_ash_id)
		GameState.view_x = 405 * 48 - 400
		GameState.view_y = 120 * 32 - 300
		$WorldRenderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_FIREWALL_FADE_SCREENSHOT"))
		if OS.has_environment("MIR2X_FIREWALL_BASELINE_SCREENSHOT"):
			GameState.firewalls = GameState.firewalls.filter(func(wall: Dictionary) -> bool: return wall.get("fade_start_time", -1) < 0)
			GameState.magic_effects.clear()
			$WorldRenderer.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_FIREWALL_BASELINE_SCREENSHOT"))
	print("MAGIC EFFECT PASS: target/server attachments, follow/fixed/composite/propagated magic and caster-grid laser")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("MAGIC_EFFECT_SMOKE %s" % message)
	get_tree().quit(1)


func _find_open_wave_source(renderer, start_y: int, end_y: int) -> Vector2i:
	for y in range(start_y, end_y):
		for x in range(8, renderer.map_width - 16):
			var open := true
			for distance in range(0, 9):
				if not renderer.can_walk(x + distance, y):
					open = false
					break
			if open:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
