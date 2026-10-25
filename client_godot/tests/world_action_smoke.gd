extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const WorldPathfinderScript = preload("res://scripts/game/world_pathfinder.gd")


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	var offline_action := PackedByteArray()
	offline_action.resize(43)
	if NetworkClient.send_action(offline_action) != ERR_UNCONFIGURED:
		_fail("offline action unexpectedly initiated a server connection")
		return
	if OS.has_environment("MIR2X_PATH_ONLY"):
		if not _test_path_decomposition():
			return
		print("WORLD PATH PASS")
		get_tree().quit(0)
		return
	var resources: RefCounted = ActorResourceScript.new()
	if not resources.configure_default():
		_fail("world resources unavailable")
		return
	if not resources.has_method("hero_weapon_order"):
		_fail("hero weapon draw-order metadata unavailable")
		return
	if resources.call("hero_weapon_order", 0, 1, 0) != 1 \
			or resources.call("hero_weapon_order", 0, 5, 0) != 0 \
			or resources.call("hero_weapon_order", 1, 1, 0) != 1 \
			or resources.call("hero_weapon_order", 32, 8, 9) != 0:
		_fail("hero weapon draw-order metadata mismatch")
		return
	var physical_id: int = resources.magic_id("物理攻击")
	var next_strike_id: int = resources.magic_id("攻杀剑术")
	if physical_id == 0 or next_strike_id == 0:
		_fail("attack magic metadata unavailable")
		return

	var encoded := Protocol.encode_action_node({"type": 7, "speed": 100, "magicID": physical_id, "modifierID": 9})
	var decoded := Protocol.decode_action_node(encoded)
	if decoded.get("magicID", 0) != physical_id or decoded.get("modifierID", 0) != 9:
		_fail("attack extParam encoding mismatch: %s" % decoded)
		return

	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameState.player_health_initialized = true
	GameState.player_hp = 1
	GameState.player_hp_max = maxi(GameState.player_hp_max, 1)
	if OS.has_environment("MIR2X_ACTION_SEFF_ONLY"):
		if not await _test_action_seff(main, resources):
			return
		print("WORLD ACTION SEFF PASS")
		get_tree().quit(0)
		return
	if OS.has_environment("MIR2X_REMOTE_PLAYER_CORRECTION_SCREENSHOT"):
		if not await _test_remote_player_motion_correction(main, resources):
			return
		print("REMOTE PLAYER CORRECTION VISUAL PASS")
		get_tree().quit(0)
		return
	var world_renderer: Control = main.get_node("WorldRenderer")
	if not _test_actor_status_overlay(world_renderer, resources):
		return
	var actor_draw_order: Array = world_renderer.call("_sorted_actor_row_entries", [
		{"x": 9, "sequence": 0, "uid": 101},
		{"x": 3, "sequence": 1, "uid": 102},
		{"x": 9, "sequence": 2, "uid": 103},
	])
	if actor_draw_order.map(func(entry: Dictionary) -> int: return entry.uid) != [102, 101, 103]:
		_fail("same-row actor draw order does not follow x coordinates: %s" % [actor_draw_order])
		return
	if not world_renderer.has_method("_hero_dress_mod_color") or not world_renderer.has_method("_hero_hair_mod_color"):
		_fail("hero dress/hair color modulation unavailable")
		return
	var dress_color: Color = world_renderer.call("_hero_dress_mod_color", {
		1: {"extAttrList": {41: PackedByteArray([1, 0x11, 0x22, 0x33, 0x44])}},
	})
	var hair_color: Color = world_renderer.call("_hero_hair_mod_color", {"hairColor": 0xDDCCBBAA})
	if not dress_color.is_equal_approx(Color(0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0, 0x44 / 255.0)) \
			or not hair_color.is_equal_approx(Color(0xAA / 255.0, 0xBB / 255.0, 0xCC / 255.0, 0xDD / 255.0)) \
			or not world_renderer.call("_hero_dress_mod_color", {}).is_equal_approx(Color.WHITE) \
			or not world_renderer.call("_hero_hair_mod_color", {}).is_equal_approx(Color.WHITE):
		_fail("hero dress/hair packed RGBA modulation mismatch")
		return
	var initial_inventory_panel := main.get_node("InventoryPanel") as Control
	if initial_inventory_panel.position != Vector2(259, 58) or initial_inventory_panel.size != Vector2(434, 542):
		_fail("inventory root geometry mismatch: position=%s size=%s" % [initial_inventory_panel.position, initial_inventory_panel.size])
		return
	var initial_player_state_panel := main.get_node("PlayerStatePanel") as Control
	var initial_skill_panel := main.get_node("SkillPanel") as Control
	if initial_player_state_panel.position != Vector2(236, 67) or initial_player_state_panel.size != Vector2(328, 466) or initial_skill_panel.position != Vector2(220, 76) or initial_skill_panel.size != Vector2(360, 448):
		_fail("main panel geometry mismatch: player=%s/%s skill=%s/%s" % [initial_player_state_panel.position, initial_player_state_panel.size, initial_skill_panel.position, initial_skill_panel.size])
		return
	var expected_extra_positions := {
		"res://scenes/game/panels/horse.tscn": Vector2(272, 139),
		"res://scenes/game/panels/guild.tscn": Vector2(103, 78),
		"res://scenes/game/panels/quest.tscn": Vector2(255, 77),
		"res://scenes/game/panels/team.tscn": Vector2(271, 178),
		"res://scenes/game/panels/secured_items.tscn": Vector2.ZERO,
		"res://scenes/game/panels/purchase.tscn": Vector2.ZERO,
		"res://scenes/game/panels/auction.tscn": Vector2(40, 80),
		"res://scenes/game/panels/friend_chat.tscn": Vector2(150, 50),
		"res://scenes/game/panels/runtime_config.tscn": Vector2(145, 66),
		"res://scenes/game/panels/npc_chat.tscn": Vector2.ZERO,
		"res://scenes/game/panels/minimap.tscn": Vector2(600, 0),
		"res://scenes/game/panels/input_string.tscn": Vector2(221, 166),
	}
	for scene_path: String in expected_extra_positions:
		var extra_panel := main.call("_ensure_extra_panel", scene_path) as Control
		if extra_panel == null or extra_panel.position != expected_extra_positions[scene_path]:
			_fail("extra panel initial position mismatch: scene=%s actual=%s expected=%s" % [scene_path, extra_panel.position if extra_panel != null else Vector2.INF, expected_extra_positions[scene_path]])
			return
	var resize_static_panels := {
		"inventory": initial_inventory_panel,
		"player_state": initial_player_state_panel,
		"skill": initial_skill_panel,
	}
	var extra_panel_nodes: Dictionary = main.get("_extra_panel_nodes")
	for scene_path: String in expected_extra_positions:
		if scene_path != "res://scenes/game/panels/minimap.tscn":
			resize_static_panels[scene_path] = extra_panel_nodes[scene_path]
	var resize_static_positions := {}
	for panel_name: String in resize_static_panels:
		resize_static_positions[panel_name] = (resize_static_panels[panel_name] as Control).position
	get_tree().root.size = Vector2i(1024, 768)
	await get_tree().process_frame
	if main.size != Vector2(800, 600):
		_fail("scaled window changed the 800x600 logical game viewport: main=%s root=%s" % [main.size, get_tree().root.size])
		return
	for panel_name: String in resize_static_panels:
		var resized_panel := resize_static_panels[panel_name] as Control
		if resized_panel.position != resize_static_positions[panel_name]:
			_fail("C++ board moved instead of preserving its clamped position after viewport growth: panel=%s actual=%s expected=%s" % [panel_name, resized_panel.position, resize_static_positions[panel_name]])
			return
	var resized_minimap := extra_panel_nodes["res://scenes/game/panels/minimap.tscn"] as Control
	if resized_minimap.position != Vector2(600, 0) or resized_minimap.size != Vector2(200, 200):
		_fail("scaled window changed the minimap's 800x600 logical geometry: position=%s size=%s" % [resized_minimap.position, resized_minimap.size])
		return
	get_tree().root.size = Vector2i(800, 600)
	await get_tree().process_frame
	if resized_minimap.position != Vector2(600, 0) or resized_minimap.size != Vector2(200, 200):
		_fail("minimap did not restore its C++ upper-right geometry with the viewport: position=%s size=%s" % [resized_minimap.position, resized_minimap.size])
		return
	var expected_direct_layers := {
		"SkillPanel": 9,
		"SkillBuffHUD": 5,
		"ControlPanel": 6,
		"Location": 7,
		"QuickBar": 7,
		"InventoryPanel": 18,
		"PlayerStatePanel": 19,
	}
	for node_path: String in expected_direct_layers:
		var direct_panel := main.get_node(node_path) as Control
		if direct_panel.z_index != expected_direct_layers[node_path]:
			_fail("direct panel draw layer does not match C++ order: node=%s actual=%d expected=%d" % [node_path, direct_panel.z_index, expected_direct_layers[node_path]])
			return
	var location_label := main.get_node("Location") as Label
	if location_label.anchor_top != 1.0 or location_label.anchor_bottom != 1.0 \
			or location_label.offset_top != -23.0 or location_label.offset_bottom != 0.0 \
			or location_label.position != Vector2(4, main.size.y - 23.0):
		_fail("location text did not follow the original bottom HUD anchor: anchors=%s/%s offsets=%s/%s position=%s main=%s" % [location_label.anchor_top, location_label.anchor_bottom, location_label.offset_top, location_label.offset_bottom, location_label.position, main.size])
		return
	var main_control_panel := main.get_node("ControlPanel") as Control
	if main_control_panel.anchor_top != 1.0 or main_control_panel.anchor_right != 1.0 or main_control_panel.anchor_bottom != 1.0 \
			or main_control_panel.offset_top != -152.0 or main_control_panel.offset_bottom != 0.0 \
			or main_control_panel.position != Vector2(0, main.size.y - 152.0) or main_control_panel.size != Vector2(main.size.x, 152):
		_fail("main HUD did not stay full-width at the viewport bottom: anchors=%s/%s/%s offsets=%s/%s position=%s size=%s main=%s" % [main_control_panel.anchor_top, main_control_panel.anchor_right, main_control_panel.anchor_bottom, main_control_panel.offset_top, main_control_panel.offset_bottom, main_control_panel.position, main_control_panel.size, main.size])
		return
	var expected_extra_layers := {
		"res://scenes/game/panels/minimap.tscn": 1,
		"res://scenes/game/panels/npc_chat.tscn": 2,
		"res://scenes/game/panels/friend_chat.tscn": 8,
		"res://scenes/game/panels/auction.tscn": 10,
		"res://scenes/game/panels/horse.tscn": 11,
		"res://scenes/game/panels/guild.tscn": 12,
		"res://scenes/game/panels/input_string.tscn": 13,
		"res://scenes/game/panels/runtime_config.tscn": 14,
		"res://scenes/game/panels/quest.tscn": 15,
		"res://scenes/game/panels/team.tscn": 16,
		"res://scenes/game/panels/secured_items.tscn": 17,
		"res://scenes/game/panels/purchase.tscn": 20,
	}
	var layered_extra_panels: Dictionary = main.get("_extra_panel_nodes")
	for scene_path: String in expected_extra_layers:
		var extra_panel := layered_extra_panels.get(scene_path) as Control
		if extra_panel == null or extra_panel.z_index != expected_extra_layers[scene_path]:
			_fail("extra panel draw layer does not match C++ order: scene=%s actual=%s expected=%d" % [scene_path, extra_panel.z_index if extra_panel != null else -1, expected_extra_layers[scene_path]])
			return
	var fixed_panels := {
		"skill": initial_skill_panel,
		"runtime_config": layered_extra_panels["res://scenes/game/panels/runtime_config.tscn"] as Control,
		"friend_chat": layered_extra_panels["res://scenes/game/panels/friend_chat.tscn"] as Control,
		"npc_chat": layered_extra_panels["res://scenes/game/panels/npc_chat.tscn"] as Control,
	}
	for panel_name: String in fixed_panels:
		var fixed_panel := fixed_panels[panel_name] as Control
		var original_position := fixed_panel.position
		var drag_press := InputEventMouseButton.new()
		drag_press.button_index = MOUSE_BUTTON_LEFT
		drag_press.pressed = true
		drag_press.position = Vector2(30, 20)
		fixed_panel.call("_gui_input", drag_press)
		var drag_motion := InputEventMouseMotion.new()
		drag_motion.position = Vector2(50, 40)
		drag_motion.relative = Vector2(20, 20)
		fixed_panel.call("_gui_input", drag_motion)
		var drag_release := InputEventMouseButton.new()
		drag_release.button_index = MOUSE_BUTTON_LEFT
		drag_release.position = Vector2(50, 40)
		fixed_panel.call("_gui_input", drag_release)
		if fixed_panel.position != original_position:
			_fail("fixed C++ panel remained draggable: panel=%s actual=%s expected=%s" % [panel_name, fixed_panel.position, original_position])
			return
	if OS.has_environment("MIR2X_EXTRA_PANEL_SCREENSHOT"):
		var visual_scene := OS.get_environment("MIR2X_EXTRA_PANEL_SCENE")
		if not expected_extra_positions.has(visual_scene):
			_fail("unsupported extra panel visual scene: %s" % visual_scene)
			return
		var extra_panels: Dictionary = main.get("_extra_panel_nodes")
		for panel_node: Control in extra_panels.values():
			panel_node.hide()
		var visual_panel := extra_panels[visual_scene] as Control
		visual_panel.show()
		visual_panel.move_to_front()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var screenshot_error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_EXTRA_PANEL_SCREENSHOT"))
		if screenshot_error != OK:
			_fail("unable to save extra panel screenshot: %s" % screenshot_error)
			return
		print("EXTRA PANEL VISUAL PASS: %s at %s" % [visual_scene, visual_panel.position])
		get_tree().quit()
		return
	if OS.has_environment("MIR2X_FPS_SCREENSHOT"):
		if not await _capture_fps_visual(main):
			return
		print("FPS OVERLAY VISUAL PASS: %s" % OS.get_environment("MIR2X_FPS_SCREENSHOT"))
		get_tree().quit()
		return
	if not _test_input_dialog_ownership(main):
		return
	if not await _test_panel_escape_precedence(main):
		return
	if not _test_context_panel_hotkeys(main):
		return
	if not _test_strike_grid_rendering(main):
		return
	if not _test_camera_centering(main):
		return
	if not _test_movement_timeline(main):
		return
	if not _test_missing_minimap_feedback(main):
		return
	if not _test_fps_overlay(main):
		return
	if not _test_team_flag_cursor(main):
		return
	main.call("_on_server_message", NetworkClient.SM_NEXTSTRIKE, PackedByteArray())
	if main.call("_consume_attack_magic_id") != next_strike_id or main.call("_consume_attack_magic_id") != physical_id:
		_fail("SM_NEXTSTRIKE was not consumed exactly once")
		return
	if not _test_player_say(main):
		return
	if not _test_system_chat_feedback(main):
		return
	if not _test_player_name_state(main):
		return
	if not _test_magic_actions(main, resources, physical_id):
		return
	if not _test_hero_spell_gestures(main, resources):
		return
	if not _test_monster_attack_magic_queue(main, resources, physical_id):
		return
	if not _test_magic_panel_hotkey_precedence(main, resources):
		return
	if not _test_async_combat_feedback(main, resources):
		return
	if not _test_health_feedback(main, resources):
		return
	if not _test_buff_transitions(main, resources):
		return
	if not _test_progression_feedback(main, resources):
		return
	if not _test_ping_feedback(main):
		return
	if not await _test_action_seff(main, resources):
		return
	if not _test_shield_hit_action(main, resources):
		return
	if not await _test_remote_player_motion_correction(main, resources):
		return
	if not _test_monster_motion_correction(main, resources):
		return
	if not _test_spinkick_direction(main):
		return
	if not await _test_action_created_monster_queries(main):
		return
	if not _test_actor_record_lifecycle(main):
		return
	if not _test_npc_actions(main):
		return
	if not _test_monster_spawn_actions(main, resources):
		return
	if not _test_monster_body_profiles(main, resources):
		return
	if not _test_monster_transform_actions(main, resources):
		return
	if not _test_monster_jump_stands(main):
		return
	if not await _test_self_action_map_transition(main):
		return

	if not _test_inventory_transaction_feedback(main, resources):
		return
	if not _test_death_correction_queue(main, resources):
		return
	if not _test_death_and_map_filter(main, resources):
		return
	if not _test_world_displacement(main, resources):
		return
	if not _test_path_decomposition():
		return
	if not _test_chase_retry(main):
		return
	if not _test_exact_frame_input(main):
		return
	if not _test_mining(main, resources):
		return
	if not _test_pickup_action(main, resources):
		return
	print("WORLD ACTION PASS: team flag, focus channels, mining, exact-frame focus, action SEFF, attack/chase, magic keys, pickup, off-horse pathing, operation feedback, death and map filtering")
	get_tree().quit()


func _test_panel_escape_precedence(main: Control) -> bool:
	var inventory := main.get_node("InventoryPanel") as Control
	var player_state := main.get_node("PlayerStatePanel") as Control
	var skill := main.get_node("SkillPanel") as Control
	var command := main.get_node("ControlPanel").get_node("%Command") as LineEdit
	var purchase := main.call("_ensure_extra_panel", "res://scenes/game/panels/purchase.tscn") as Control
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	inventory.show()
	purchase.show()
	command.grab_focus()
	await get_tree().process_frame
	Input.parse_input_event(escape)
	await get_tree().process_frame
	if command.has_focus() or not purchase.visible or not inventory.visible:
		_fail("focused command did not consume Escape before purchase/panels like the C++ IME board: focus=%s purchase=%s inventory=%s" % [command.has_focus(), purchase.visible, inventory.visible])
		return false
	purchase.hide()
	inventory.hide()
	inventory.show()
	player_state.show()
	skill.show()
	Input.parse_input_event(escape)
	await get_tree().process_frame
	if inventory.visible or not player_state.visible or not skill.visible:
		_fail("multi-panel Escape did not follow C++ inventory-before-player-before-skill priority: inventory=%s player=%s skill=%s" % [inventory.visible, player_state.visible, skill.visible])
		return false
	player_state.hide()
	skill.hide()
	var runtime := main.call("_ensure_extra_panel", "res://scenes/game/panels/runtime_config.tscn") as Control
	runtime.show()
	inventory.hide()
	var blocked_hotkey := InputEventKey.new()
	blocked_hotkey.keycode = KEY_B
	blocked_hotkey.pressed = true
	Input.parse_input_event(blocked_hotkey)
	await get_tree().process_frame
	if not runtime.visible or inventory.visible:
		_fail("runtime config did not consume non-Escape keys like C++: runtime=%s inventory=%s" % [runtime.visible, inventory.visible])
		return false
	inventory.show()
	Input.parse_input_event(escape)
	await get_tree().process_frame
	if runtime.visible or inventory.visible:
		_fail("runtime Escape did not close runtime and continue to inventory: runtime=%s inventory=%s" % [runtime.visible, inventory.visible])
		return false
	inventory.show()
	purchase.show()
	main.call("_center_hero")
	GameState.view_x += 37.0
	GameState.view_y += 29.0
	var purchase_view_before := Vector2(GameState.view_x, GameState.view_y)
	Input.parse_input_event(escape)
	await get_tree().process_frame
	if not purchase.visible or not inventory.visible or not Vector2(GameState.view_x, GameState.view_y).is_equal_approx(purchase_view_before):
		_fail("visible purchase panel did not consume Escape before later panels and HUD like C++: purchase=%s inventory=%s view=%s expected_view=%s" % [purchase.visible, inventory.visible, Vector2(GameState.view_x, GameState.view_y), purchase_view_before])
		return false
	purchase.hide()
	inventory.hide()
	return true


func _test_context_panel_hotkeys(main: Control) -> bool:
	var forbidden := {
		KEY_L: "res://scenes/game/panels/secured_items.tscn",
		KEY_P: "res://scenes/game/panels/purchase.tscn",
		KEY_A: "res://scenes/game/panels/auction.tscn",
		KEY_N: "res://scenes/game/panels/npc_chat.tscn",
	}
	for keycode: int in forbidden:
		var panel := main.call("_ensure_extra_panel", forbidden[keycode]) as Control
		panel.hide()
		if main.call("_try_panel_hotkey", keycode) or panel.visible:
			_fail("context-only panel was exposed by unsupported hotkey: key=%d scene=%s" % [keycode, forbidden[keycode]])
			return false
	return true


func _test_input_dialog_ownership(main: Control) -> bool:
	GameState.pending_input = {"uid": 11, "commitTag": "old-npc"}
	main.call("_on_purchase_quantity_requested", 22, 33, "测试商品")
	if not GameState.pending_input.is_empty() or main.get("_pending_purchase").get("npcUID", 0) != 22 or not main.get("_pending_chat_group").is_empty():
		_fail("purchase prompt did not replace the previous NPC input owner")
		return false
	GameState.pending_input = {"uid": 44, "commitTag": "old-npc-2"}
	main.call("_on_friend_group_name_requested", [55, 66])
	if not GameState.pending_input.is_empty() or not main.get("_pending_purchase").is_empty() or main.get("_pending_chat_group") != [55, 66]:
		_fail("friend-group prompt did not replace the previous input owner")
		return false
	main.call("_on_purchase_quantity_requested", 77, 88, "旧商品")
	main.call("_on_server_message", NetworkClient.SM_STARTINPUT, _start_input_payload(99, "新NPC输入", "new-npc", true))
	if GameState.pending_input.get("uid", 0) != 99 or GameState.pending_input.get("commitTag", "") != "new-npc" or not main.get("_pending_purchase").is_empty() or not main.get("_pending_chat_group").is_empty():
		_fail("server NPC prompt did not replace the previous local input owner")
		return false
	main.call("_on_input_cancelled")
	(main.call("_ensure_extra_panel", "res://scenes/game/panels/input_string.tscn") as Control).hide()
	return true


func _test_strike_grid_rendering(main: Control) -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	var expected := Color8(0xFF, 0x00, 0x00, 0x60)
	for age_ms in [0, 500, 1000]:
		if renderer.call("_strike_grid_color", age_ms) != expected:
			_fail("strike grid did not keep C++ pure-red alpha-96 color for one second")
			return false
	if renderer.call("_strike_grid_color", 1001) != Color.TRANSPARENT or renderer.call("_strike_grid_color", -1) != Color.TRANSPARENT:
		_fail("strike grid color escaped its original one-second lifecycle")
		return false
	return true


func _test_monster_attack_magic_queue(main: Control, resources: RefCounted, physical_id: int) -> bool:
	var attack_magic_ids := [
		resources.magic_id("神兽_喷火"), resources.magic_id("楔蛾_喷毒"), resources.magic_id("洞蛆_喷毒"),
		resources.magic_id("粪虫_喷毒"), resources.magic_id("雷电僵尸_雷电"), resources.magic_id("火焰沃玛_喷火"),
		resources.magic_id("沃玛教主_电光"), resources.magic_id("蚂蚁道士_治疗"), resources.magic_id("红衣法师_魔法"),
		resources.magic_id("沙漠风魔_扇风"), resources.magic_id("沃玛教主_雷电术"), resources.magic_id("潘夜右护卫_雷电术"),
		resources.magic_id("雷电术"), resources.magic_id("暗黑战士_喷刺"), resources.magic_id("爆毒蚂蚁_喷毒"),
		resources.magic_id("沙漠树魔_喷刺"), resources.magic_id("诺玛法老_火球术"), resources.magic_id("潘夜左护卫_火球术"),
		resources.magic_id("祖玛弓箭手_射箭"), resources.magic_id("掷斧骷髅_掷斧"), resources.magic_id("潘夜右护卫_电魔杖"),
		resources.magic_id("潘夜左护卫_火魔杖"), resources.magic_id("祖玛教主_火墙"), resources.magic_id("祖玛教主_地狱火"),
	]
	if attack_magic_ids.has(0):
		_fail("monster attack magic metadata unavailable: %s" % attack_magic_ids)
		return false
	GameState.player_map_uid = 24 << 35
	GameState.magic_effects.clear()
	for index in range(attack_magic_ids.size()):
		var uid: int = (4 << 59) | ((700 + index) << 35) | (900 + index)
		GameState.update_creature(uid, {"uid": uid, "type": 1, "monster_id": 700 + index, "x": 10, "y": 10, "direction": 3, "action_type": 2})
		main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, GameState.player_map_uid, {
			"type": 7, "speed": 100, "direction": 3, "x": 10, "y": 10,
			"aimX": 13, "aimY": 10, "aimUID": GameState.player_uid, "magicID": attack_magic_ids[index],
		}))
		var effect: Dictionary = GameState.magic_effects.back() if not GameState.magic_effects.is_empty() else {}
		if effect.get("magicID", 0) != attack_magic_ids[index] or effect.get("source", "") != "monster_attack" or effect.get("uid", 0) != uid:
			_fail("monster attack magic was not queued: id=%d effect=%s" % [attack_magic_ids[index], effect])
			return false
	var before_physical := GameState.magic_effects.size()
	var physical_uid: int = (4 << 59) | (799 << 35) | 999
	GameState.update_creature(physical_uid, {"uid": physical_uid, "type": 1, "monster_id": 799, "x": 10, "y": 10, "direction": 3, "action_type": 2})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(physical_uid, GameState.player_map_uid, {
		"type": 7, "speed": 100, "direction": 3, "x": 10, "y": 10,
		"aimUID": GameState.player_uid, "magicID": physical_id,
	}))
	if GameState.magic_effects.size() != before_physical:
		_fail("ordinary physical monster attack created a magic effect")
		return false
	GameState.magic_effects.clear()
	for uid in GameState.creatures.keys():
		if ((int(uid) >> 35) & 0xFFFFFF) in range(700, 724) or ((int(uid) >> 35) & 0xFFFFFF) == 799:
			GameState.remove_creature(uid)
	return true


func _test_camera_centering(main: Control) -> bool:
	var scroll_camera_arg_count := 0
	for method_info in GameState.get_method_list():
		if String(method_info.get("name", "")) == "scroll_camera_to":
			scroll_camera_arg_count = (method_info.get("args", []) as Array).size()
			break
	if scroll_camera_arg_count < 2:
		_fail("camera scrolling is tied to render-frame count instead of elapsed time")
		return false
	var camera_distances: Array[Vector2] = []
	for fps in [30, 60, 120]:
		GameState.view_x = 1000.0
		GameState.view_y = 1000.0
		GameState.set("_camera_scrolling", true)
		for frame_index in range(fps):
			GameState.scroll_camera_to(Vector2(100, 100), 1.0 / float(fps))
		camera_distances.append(Vector2(GameState.view_x - 1000.0, GameState.view_y - 1000.0))
	for distance in camera_distances:
		if not distance.is_equal_approx(Vector2(210.0, 140.0)):
			_fail("one-second camera distance depends on render FPS: %s" % [camera_distances])
			return false
	GameState.view_x = 1000.0
	GameState.view_y = 1000.0
	GameState.set("_camera_scrolling", true)
	GameState.scroll_camera_to(Vector2(100, 100), 0.5)
	var hitch_distance := Vector2(GameState.view_x - 1000.0, GameState.view_y - 1000.0)
	if not hitch_distance.is_equal_approx(Vector2(7.0, 14.0 / 3.0)):
		_fail("camera caught up an entire long frame in one draw: %s" % hitch_distance)
		return false
	GameState.set("_camera_scrolling", false)
	GameState.player_x = 371
	GameState.player_y = 132
	GameState.hud_minimized = false
	GameState.center_camera_on_player()
	if GameState.camera_center_y() != 234 or not is_equal_approx(GameState.view_y, float(132 * 32 - 234)):
		_fail("normal HUD camera does not use C++ 469px world viewport")
		return false
	var centered_view_x := GameState.view_x
	GameState.player_x += 1
	GameState.scroll_camera()
	if not is_equal_approx(GameState.view_x, centered_view_x):
		_fail("camera moved inside the original one-sixth-screen horizontal dead zone")
		return false
	GameState.player_x += 2
	GameState.scroll_camera()
	if not is_equal_approx(GameState.view_x, centered_view_x + 3.0):
		_fail("camera did not start scrolling after leaving the original horizontal dead zone")
		return false
	var scrolling_view_x := GameState.view_x
	GameState.player_x -= 2
	GameState.scroll_camera()
	if not is_equal_approx(GameState.view_x, scrolling_view_x + 3.0):
		_fail("camera did not keep converging after scrolling started")
		return false
	GameState.player_x = 0
	GameState.player_y = 0
	GameState.view_x = 1.0
	GameState.view_y = 1.0
	GameState.scroll_camera()
	if not is_zero_approx(GameState.view_x) or not is_zero_approx(GameState.view_y):
		_fail("camera scrolling crossed the original zero lower bound: %s,%s" % [GameState.view_x, GameState.view_y])
		return false
	GameState.player_x = 371
	GameState.player_y = 132
	GameState.center_camera_on_player()
	var control_panel: Control = main.get_node("ControlPanel")
	control_panel.call("_on_minimize_pressed")
	if not GameState.hud_minimized or GameState.camera_center_y() != 300:
		_fail("minimized HUD did not expose the full 600px world viewport")
		return false
	var previous_view_y := GameState.view_y
	GameState.scroll_camera()
	if not is_equal_approx(GameState.view_y, previous_view_y):
		_fail("minimized HUD incorrectly moved the camera inside the original vertical dead zone")
		return false
	control_panel.call("_on_minimize_pressed")
	main.call("_center_hero")
	if GameState.hud_minimized or not is_equal_approx(GameState.view_y, float(132 * 32 - 234)):
		_fail("restored HUD or ESC centering did not return to the 469px viewport")
		return false
	GameState.player_action_from_x = 371
	GameState.player_action_from_y = 132
	GameState.player_x = 373
	GameState.player_y = 134
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec() - 300
	var world_renderer: Node = main.get_node("WorldRenderer")
	var visual_grid: Vector2 = world_renderer.call("player_draw_grid")
	main.call("_center_hero")
	var expected_visual_x := visual_grid.x * 48.0 - 400.0
	var expected_visual_y := visual_grid.y * 32.0 - 234.0
	if absf(GameState.view_x - expected_visual_x) > 2.0 or absf(GameState.view_y - expected_visual_y) > 2.0:
		_fail("ESC centered on the movement destination instead of the current visual position")
		return false
	GameState.player_action_type = 2
	GameState.player_action_started_ms = 0
	GameState.center_camera_on_grid(Vector2(371, 132))
	GameState.player_action_from_x = 371
	GameState.player_action_from_y = 132
	GameState.player_x = 375
	GameState.player_y = 132
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec() - 60
	main.call("_cancel_movement")
	main.set("_move_step_timer", 1.0)
	(main.get("_player_forced_action_queue") as Array).clear()
	main.set("_pickup_action_timer", -1.0)
	main.set("_player_action_timer", -1.0)
	var pre_scroll_view_x := GameState.view_x
	var scroll_visual_grid: Vector2 = world_renderer.call("player_draw_grid")
	if bool(GameState.get("_camera_scrolling")):
		_fail("camera scrolling state was not reset before the visual-position check")
		return false
	GameState.scroll_camera_to(scroll_visual_grid)
	var expected_follow_x := scroll_visual_grid.x * 48.0 - 400.0
	var expected_follow_y := scroll_visual_grid.y * 32.0 - 234.0
	if absf(GameState.view_x - expected_follow_x) > 0.01 or absf(GameState.view_y - expected_follow_y) > 0.01:
		_fail("walking camera did not follow the current visual motion position: before=%s after=%s expected=(%s,%s)" % [pre_scroll_view_x, GameState.view_x, expected_follow_x, expected_follow_y])
		return false
	main.call("_process", 0.0)
	var process_visual_grid: Vector2 = world_renderer.call("player_draw_grid")
	if absf(GameState.view_x - (process_visual_grid.x * 48.0 - 400.0)) > 0.01 or absf(GameState.view_y - (process_visual_grid.y * 32.0 - 234.0)) > 0.01:
		_fail("process camera did not keep following the current visual motion position")
		return false
	GameState.player_action_type = 2
	GameState.player_action_started_ms = 0
	GameState.center_camera_on_player()
	return true


func _test_movement_timeline(main: Control) -> bool:
	var world_renderer: Node = main.get_node("WorldRenderer")
	if not world_renderer.has_method("advance_movement_clocks"):
		_fail("movement interpolation catches up the full elapsed wall-clock time after a long frame")
		return false
	var started_ms := 1000
	var samples: Array[float] = []
	for now_ms in [1000, 1100, 1200, 1300, 1400, 1500, 1600]:
		samples.append(world_renderer.call("_action_draw_grid", 11, 10, 10, 10, 3, started_ms, 100, now_ms).x)
	for index in range(samples.size()):
		var expected := 10.0 + float(index) / 6.0
		if absf(samples[index] - expected) > 0.001:
			_fail("movement interpolation is not uniform: samples=%s index=%d expected=%f" % [samples, index, expected])
			return false
	var constants: Dictionary = main.get_script().get_script_constant_map()
	if absf(float(constants.get("MOVE_STEP_SECONDS", 0.0)) - 0.6) > 0.001:
		_fail("right-click path cadence does not match the six-frame movement duration: %s" % constants.get("MOVE_STEP_SECONDS", null))
		return false

	var saved_player := {
		"uid": GameState.player_uid,
		"map_uid": GameState.player_map_uid,
		"x": GameState.player_x,
		"y": GameState.player_y,
		"from_x": GameState.player_action_from_x,
		"from_y": GameState.player_action_from_y,
		"type": GameState.player_action_type,
		"speed": GameState.player_action_speed,
		"started_ms": GameState.player_action_started_ms,
	}
	if int(world_renderer.get("map_width")) <= 0 and not world_renderer.call("load_map", 24):
		_fail("active movement replan fixture could not load map 24")
		return false
	var replan_start := Vector2i(-1, -1)
	for y in range(int(world_renderer.get("map_height"))):
		for x in range(int(world_renderer.get("map_width")) - 4):
			var clear_line := true
			for offset in range(5):
				if not world_renderer.call("can_walk", x + offset, y):
					clear_line = false
					break
			if clear_line:
				replan_start = Vector2i(x, y)
				break
		if replan_start.x >= 0:
			break
	if replan_start.x < 0:
		_fail("active movement replan fixture could not find five clear grids")
		return false
	GameState.player_action_from_x = replan_start.x
	GameState.player_action_from_y = replan_start.y
	GameState.player_x = replan_start.x + 2
	GameState.player_y = replan_start.y
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_step = 2
	GameState.player_action_started_ms = Time.get_ticks_msec() - 200
	main.set("_move_step_timer", 0.4)
	main.call("_start_move_to", Vector2i(replan_start.x + 4, replan_start.y))
	if absf(float(main.get("_move_step_timer")) - 0.4) > 0.001:
		_fail("right-click replan interrupted the active C++ six-frame movement: %f" % float(main.get("_move_step_timer")))
		return false
	if (main.get("_move_path") as Array).is_empty():
		_fail("right-click replan did not retain a path after the active movement")
		return false
	main.call("_cancel_movement")
	GameState.player_action_from_x = 10
	GameState.player_action_from_y = 10
	GameState.player_x = 11
	GameState.player_y = 10
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec()
	var hitch_monster_uid: int = (4 << 59) | (1 << 35) | 986
	GameState.update_creature(hitch_monster_uid, {
		"uid": hitch_monster_uid, "type": 1, "monster_id": 1,
		"x": 21, "y": 20, "action_from_x": 20, "action_from_y": 20,
		"direction": 3, "action_type": 3, "action_speed": 100,
		"action_started_ms": GameState.player_action_started_ms,
	})
	world_renderer.call("reset_movement_clocks")
	world_renderer.call("advance_movement_clocks", 1.0 / 60.0)
	world_renderer.call("advance_movement_clocks", 0.5)
	var post_hitch_grid: Vector2 = world_renderer.call("player_draw_grid")
	if post_hitch_grid.x < 10.07 or post_hitch_grid.x > 10.09:
		_fail("movement caught up an entire 500ms hitch: %s" % post_hitch_grid)
		return false
	var monster_post_hitch: float = world_renderer.call("creature_movement_elapsed_seconds", hitch_monster_uid, GameState.player_action_started_ms)
	if monster_post_hitch < 0.049 or monster_post_hitch > 0.051:
		_fail("monster movement caught up an entire 500ms hitch: %f" % monster_post_hitch)
		return false
	for frame_index in range(33):
		world_renderer.call("advance_movement_clocks", 1.0 / 60.0)
	var completed_grid: Vector2 = world_renderer.call("player_draw_grid")
	if not completed_grid.is_equal_approx(Vector2(11, 10)):
		_fail("limited movement clock changed the normal total action duration: %s" % completed_grid)
		return false
	var monster_completed: float = world_renderer.call("creature_movement_elapsed_seconds", hitch_monster_uid, GameState.player_action_started_ms)
	if absf(monster_completed - 0.6) > 0.001:
		_fail("limited monster clock changed the normal total action duration: %f" % monster_completed)
		return false
	GameState.remove_creature(hitch_monster_uid)
	world_renderer.call("reset_movement_clocks")
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_action_from_x = 10
	GameState.player_action_from_y = 10
	GameState.player_x = 11
	GameState.player_y = 10
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec() - 200
	var predicted_started_ms: int = GameState.player_action_started_ms
	main.call("_handle_action_data", {
		"uid": 101,
		"mapUID": 202,
		"action": {"type": 3, "speed": 100, "x": 10, "y": 10, "aimX": 11, "aimY": 10},
	})
	if GameState.player_action_started_ms != predicted_started_ms:
		_fail("authoritative echo restarted the predicted player movement timeline")
		return false

	var monster_uid: int = (4 << 59) | (1 << 35) | 987
	GameState.update_creature(monster_uid, {
		"uid": monster_uid, "type": 1, "monster_id": 1,
		"x": 21, "y": 20, "action_from_x": 20, "action_from_y": 20,
		"direction": 3, "action_type": 3, "action_speed": 100,
		"action_started_ms": Time.get_ticks_msec() - 200,
	})
	var monster_before: Dictionary = GameState.get_creature(monster_uid).duplicate(true)
	main.call("_handle_action_data", {
		"uid": monster_uid,
		"mapUID": 202,
		"action": {"type": 3, "speed": 100, "direction": 3, "x": 20, "y": 20, "aimX": 21, "aimY": 20},
	})
	var monster_after: Dictionary = GameState.get_creature(monster_uid)
	if monster_after.get("action_started_ms", 0) != monster_before.action_started_ms \
			or monster_after.get("action_from_x", 0) != 20 or monster_after.get("x", 0) != 21 \
			or monster_after.has("motion_action_queue"):
		_fail("duplicate monster movement rewound or restarted its active timeline: before=%s after=%s" % [monster_before, monster_after])
		return false
	GameState.remove_creature(monster_uid)
	GameState.player_uid = saved_player.uid
	GameState.player_map_uid = saved_player.map_uid
	GameState.player_x = saved_player.x
	GameState.player_y = saved_player.y
	GameState.player_action_from_x = saved_player.from_x
	GameState.player_action_from_y = saved_player.from_y
	GameState.player_action_type = saved_player.type
	GameState.player_action_speed = saved_player.speed
	GameState.player_action_started_ms = saved_player.started_ms
	return true


func _test_missing_minimap_feedback(main: Control) -> bool:
	var panels: Dictionary = main.get("_extra_panel_nodes")
	var minimap := panels.get("res://scenes/game/panels/minimap.tscn") as Control
	if minimap == null or minimap.call("has_map_texture"):
		_fail("missing-map feedback fixture unexpectedly has a minimap texture")
		return false
	var requested_before: bool = minimap.call("requested_visible")
	GameState.chat_log.clear()
	main.call("_on_control_panel_panel_requested", "res://scenes/game/panels/minimap.tscn")
	if GameState.chat_log.size() != 1 or GameState.chat_log[0].text != "没有可用的地图":
		_fail("missing minimap control did not provide the original error feedback")
		return false
	if minimap.call("requested_visible") != requested_before:
		_fail("missing minimap control changed the requested visibility state")
		return false
	return true


func _test_fps_overlay(main: Control) -> bool:
	GameState.runtime_config[6] = PackedByteArray([1, 1, 0])
	main.call("_update_fps_overlay")
	var fps := main.get_node("FPS") as Label
	if not fps.visible or fps.text.is_empty() or fps.get_theme_font_size("font_size") != 15:
		_fail("runtime FPS option did not restore the original top-right overlay")
		return false
	var one_digit: Vector2i = main.call("_layout_fps_overlay", "9")
	var three_digits: Vector2i = main.call("_layout_fps_overlay", "120")
	var font := fps.get_theme_font("font")
	if font == null or not font.resource_path.ends_with("0B_WenQuanYi_Bitmap_Song_15_px.ttf"):
		_fail("runtime FPS overlay did not use the packed font-11 resource")
		return false
	var measured := font.get_string_size("120", HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var style := fps.get_theme_stylebox("normal") as StyleBoxFlat
	if one_digit.x >= three_digits.x or three_digits != Vector2i(ceili(measured.x) + 1, ceili(measured.y)) or Vector2i(fps.size) != three_digits:
		_fail("runtime FPS overlay did not follow the original content-sized geometry")
		return false
	if not is_equal_approx(fps.position.x + fps.size.x, main.size.x) or style == null or not is_equal_approx(style.content_margin_left, 1.0) or not is_equal_approx(style.content_margin_top, 0.0) or not is_equal_approx(style.content_margin_right, 0.0) or not is_equal_approx(style.content_margin_bottom, 0.0):
		_fail("runtime FPS overlay did not preserve the original right anchor and one-pixel left margin")
		return false
	GameState.runtime_config[6] = PackedByteArray([1, 0, 0])
	main.call("_update_fps_overlay")
	if fps.visible:
		_fail("runtime FPS overlay did not hide")
		return false
	return true


func _capture_fps_visual(main: Control) -> bool:
	GameState.player_uid = 999
	GameState.player_x = 371
	GameState.player_y = 132
	GameState.view_x = float(371 * 48 - 304)
	GameState.view_y = float(132 * 32 - 234)
	var renderer := main.get_node("WorldRenderer")
	if not renderer.load_map(24):
		_fail("unable to load FPS visual map")
		return false
	main.set_process(false)
	renderer.set_process(false)
	var fps := main.get_node("FPS") as Label
	fps.visible = true
	main.call("_layout_fps_overlay", "120")
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_FPS_SCREENSHOT"))
	if error != OK:
		_fail("unable to save FPS overlay screenshot: %s" % error)
		return false
	return true


func _test_team_flag_cursor(main: Control) -> bool:
	var previous_uid := GameState.player_uid
	var previous_members := GameState.team_members.duplicate(true)
	var target_uid := (5 << 59) | 202
	var monster_uid := (1 << 59) | 203
	GameState.player_uid = (5 << 59) | 1
	GameState.team_members = []
	GameState.creatures[target_uid] = {"uid": target_uid, "type": 2, "name": "队旗目标"}
	GameState.creatures[monster_uid] = {"uid": monster_uid, "type": 1, "name": "队旗非玩家"}
	main.call("_on_control_panel_panel_requested", "res://scenes/game/panels/team.tscn")
	main.call("_update_team_flag_cursor")
	var cursor := main.get_node("TeamFlagCursor") as TextureRect
	if not main.get("_team_flag_active") or not cursor.visible or cursor.texture == null:
		_fail("no-team HUD request did not enable the original team-flag cursor")
		return false
	if main.call("_team_flag_frame_index", 0) != 0 or main.call("_team_flag_frame_index", 199) != 0 or main.call("_team_flag_frame_index", 200) != 1 or main.call("_team_flag_frame_index", 2600) != 0:
		_fail("team-flag animation does not run through 13 frames at 5 FPS")
		return false
	if main.call("_request_team_flag_target", target_uid) != ERR_UNCONFIGURED:
		_fail("team-flag player target did not issue the join-team request")
		return false
	if main.call("_request_team_flag_target", GameState.player_uid) != ERR_UNCONFIGURED:
		_fail("team-flag self target did not issue the original team-creation request")
		return false
	if main.call("_request_team_flag_target", monster_uid) != ERR_INVALID_PARAMETER:
		_fail("team-flag accepted a non-player target")
		return false
	var move_path: Array = main.get("_move_path")
	move_path.append(Vector2i(10, 10))
	var cancel_event := InputEventMouseButton.new()
	cancel_event.button_index = MOUSE_BUTTON_RIGHT
	cancel_event.pressed = true
	cancel_event.position = Vector2(400, 300)
	main.call("_handle_mouse_click", cancel_event)
	if main.get("_team_flag_active") or cursor.visible or move_path.size() != 1:
		_fail("team-flag right-click did not cancel without changing movement")
		return false
	move_path.clear()
	var panels: Dictionary = main.get("_extra_panel_nodes")
	var team_panel := panels.get("res://scenes/game/panels/team.tscn") as Control
	if team_panel != null:
		team_panel.hide()
	if not main.call("_try_panel_hotkey", KEY_T) or not main.get("_team_flag_active") or (team_panel != null and team_panel.visible):
		_fail("no-team T shortcut bypassed the original team-flag selection")
		return false
	main.call("_set_team_flag_cursor", false)
	GameState.team_members = [{"uid": GameState.player_uid, "name": "自己"}]
	main.call("_try_panel_hotkey", KEY_T)
	if team_panel == null or not team_panel.visible or main.get("_team_flag_active"):
		_fail("in-team T shortcut did not open the team panel")
		return false
	team_panel.hide()
	GameState.creatures.erase(target_uid)
	GameState.creatures.erase(monster_uid)
	GameState.player_uid = previous_uid
	GameState.team_members = previous_members
	return true


func _test_player_say(main: Control) -> bool:
	GameState.chat_log.clear()
	GameState.player_say_messages.clear()
	GameState.player_uid = (5 << 59) | 1
	var remote_uid: int = (5 << 59) | 2
	var monster_uid: int = (4 << 59) | 3
	GameState.creatures = {
		remote_uid: {"uid": remote_uid, "type": 2, "name": "远端玩家"},
		monster_uid: {"uid": monster_uid, "type": 1},
	}
	main.call("_on_server_message", NetworkClient.SM_PLAYERSAY, _player_say_payload(GameState.player_uid, "自己的头顶消息"))
	if GameState.player_say_messages.get(GameState.player_uid, []).size() != 1 or not GameState.chat_log.is_empty():
		_fail("self player say did not remain bubble-only")
		return false
	main.call("_on_server_message", NetworkClient.SM_PLAYERSAY, _player_say_payload(remote_uid, "远端原文"))
	if GameState.player_say_messages.get(remote_uid, []).size() != 1 or GameState.chat_log.size() != 1 or GameState.chat_log[0].text != "远端原文":
		_fail("remote player say bubble/chat semantics mismatch: %s" % GameState.chat_log)
		return false
	main.call("_on_server_message", NetworkClient.SM_PLAYERSAY, _player_say_payload(monster_uid, "无效气泡"))
	if GameState.player_say_messages.has(monster_uid) or GameState.chat_log.size() != 2 or GameState.chat_log[1].text != "无效气泡":
		_fail("non-hero player say filtering mismatch")
		return false
	GameState.player_say_messages.clear()
	GameState.creatures.clear()
	return true


func _test_system_chat_feedback(main: Control) -> bool:
	var saved_uid: int = GameState.player_uid
	var saved_name: String = GameState.player_name
	var saved_creatures := GameState.creatures.duplicate(true)
	var local_uid: int = (5 << 59) | 11
	var remote_uid: int = (5 << 59) | 12
	var monster_uid: int = (4 << 59) | 13
	GameState.player_uid = local_uid
	GameState.player_name = "本地角色"
	GameState.creatures = {
		remote_uid: {"uid": remote_uid, "type": 2, "name": "远端角色"},
		monster_uid: {"uid": monster_uid, "type": 1, "name": "怪物名"},
	}
	GameState.chat_log.clear()
	main.call("_on_server_message", NetworkClient.SM_TEXT, "服务器正文".to_utf8_buffer())
	main.call("_on_server_message", NetworkClient.SM_PLAYERBROADCAST, _player_say_payload(local_uid, "本地广播"))
	main.call("_on_server_message", NetworkClient.SM_PLAYERBROADCAST, _player_say_payload(remote_uid, "远端广播"))
	main.call("_on_server_message", NetworkClient.SM_PLAYERBROADCAST, _player_say_payload(monster_uid, "非角色广播"))
	main.call("_on_server_message", NetworkClient.SM_PLAYERBROADCAST, _player_say_payload((5 << 59) | 99, "未知广播"))
	var expected := ["服务器正文", "本地角色: 本地广播", "远端角色: 远端广播", "非角色广播", "未知广播"]
	if GameState.chat_log.size() != expected.size():
		_fail("system chat feedback count mismatch: %s" % GameState.chat_log)
		return false
	for index in expected.size():
		if GameState.chat_log[index].text != expected[index] or GameState.chat_log[index].type != 1:
			_fail("system chat routing mismatch at %d: %s" % [index, GameState.chat_log[index]])
			return false
	GameState.player_uid = saved_uid
	GameState.player_name = saved_name
	GameState.creatures = saved_creatures
	GameState.chat_log.clear()
	return true


func _test_player_name_state(main: Control) -> bool:
	var saved_uid: int = GameState.player_uid
	var saved_name: String = GameState.player_name
	var saved_color: int = GameState.player_name_color
	var saved_creatures := GameState.creatures.duplicate(true)
	var local_uid: int = (5 << 59) | 21
	var remote_uid: int = (5 << 59) | 22
	var monster_uid: int = (4 << 59) | 23
	GameState.player_uid = local_uid
	GameState.player_name = "旧本地名"
	GameState.player_name_color = 0xFFFFFFFF
	GameState.creatures = {
		remote_uid: {"uid": remote_uid, "type": 2, "name": "旧远端名"},
		monster_uid: {"uid": monster_uid, "type": 1, "name": "怪物名"},
	}
	main.call("_on_server_message", NetworkClient.SM_PLAYERNAME, _player_name_payload(local_uid, "新本地名", 0))
	var name_label := main.get_node("PlayerStatePanel/Name") as Label
	if GameState.player_name != "新本地名" or GameState.player_name_color != 0xFFFFFFFF or name_label.text != "新本地名" or name_label.get_theme_color("font_color") != Color.WHITE:
		_fail("local player-name state/white fallback mismatch: name=%s color=%X label=%s/%s" % [GameState.player_name, GameState.player_name_color, name_label.text, name_label.get_theme_color("font_color")])
		return false
	main.call("_on_server_message", NetworkClient.SM_PLAYERNAME, _player_name_payload(remote_uid, "新远端名", 0x00332211))
	var remote: Dictionary = GameState.get_creature(remote_uid)
	if remote.get("name", "") != "新远端名" or remote.get("name_color", 0) != 0xFF332211:
		_fail("remote player-name state/color normalization mismatch: %s" % remote)
		return false
	main.call("_on_server_message", NetworkClient.SM_PLAYERNAME, _player_name_payload(monster_uid, "伪角色名", 0x00010203))
	if GameState.get_creature(monster_uid).get("name", "") != "怪物名":
		_fail("SM_PLAYERNAME incorrectly renamed a non-player creature")
		return false
	GameState.player_uid = saved_uid
	GameState.player_name = saved_name
	GameState.player_name_color = saved_color
	GameState.creatures = saved_creatures
	return true


func _test_inventory_transaction_feedback(main: Control, resources: RefCounted) -> bool:
	var known_item_id: int = resources.item_names.keys()[0]
	var packable_id := 0
	var non_packable_id := 0
	var weapon_id := 0
	var belt_item_id := 0
	for item_id_value in resources.item_meta:
		var item_id: int = item_id_value
		var item_type: String = resources.item_type(item_id)
		if resources.item_is_packable(item_id) and packable_id == 0:
			packable_id = item_id
		elif not resources.item_is_packable(item_id) and item_type != "金币" and non_packable_id == 0:
			non_packable_id = item_id
		if item_type == "武器" and weapon_id == 0:
			weapon_id = item_id
		if item_type in ["恢复药水", "传送卷轴"] and belt_item_id == 0:
			belt_item_id = item_id
		if packable_id != 0 and non_packable_id != 0 and weapon_id != 0 and belt_item_id != 0:
			break
	if packable_id == 0 or non_packable_id == 0 or weapon_id == 0 or belt_item_id == 0:
		_fail("inventory transaction fixtures unavailable")
		return false
	var saved_chat := GameState.chat_log.duplicate(true)
	var saved_sell := GameState.npc_sell.duplicate(true)
	var saved_detail := GameState.npc_sell_detail.duplicate(true)
	var saved_inventory := GameState.inventory.duplicate(true)
	var saved_wear := GameState.wear.duplicate(true)
	var saved_belt := GameState.belt.duplicate(true)
	var saved_grabbed := GameState.grabbed_item.duplicate(true)
	var saved_uid := GameState.player_uid
	GameState.chat_log.clear()
	main.call("_on_server_message", NetworkClient.SM_PICKUPERROR, _u32_payload(known_item_id))
	main.call("_on_server_message", NetworkClient.SM_PICKUPERROR, _u32_payload(0xFFFFFFFE))
	main.call("_on_server_message", NetworkClient.SM_PICKUPERROR, _u32_payload(0))
	var pickup_expected := [
		"无法捡起%s" % resources.item_name(known_item_id),
		"无法捡起物品ID = 4294967294",
		"当前无法捡起物品，请稍后再试",
	]
	for index in pickup_expected.size():
		if GameState.chat_log[index].text != pickup_expected[index] or GameState.chat_log[index].type != 1:
			_fail("pickup error feedback mismatch at %d: %s" % [index, GameState.chat_log])
			return false
	GameState.chat_log.clear()
	for error in [1, 2, 3, 4]:
		main.call("_on_server_message", NetworkClient.SM_EQUIPWEARERROR, _item_error_payload(known_item_id, 1, error))
	main.call("_on_server_message", NetworkClient.SM_GRABWEARERROR, _u16_payload(1))
	main.call("_on_server_message", NetworkClient.SM_GRABWEARERROR, _u16_payload(2))
	for error in [1, 2, 3, 4]:
		main.call("_on_server_message", NetworkClient.SM_EQUIPBELTERROR, _item_error_payload(known_item_id, 1, error))
	main.call("_on_server_message", NetworkClient.SM_GRABBELTERROR, _u16_payload(1))
	var equipment_expected := [
		"无效的物品", "无效的物品", "无法放置：%s" % resources.item_name(known_item_id),
		"无法取下装备",
		"无效的物品", "无效的物品", "无法装备：%s" % resources.item_name(known_item_id),
	]
	if GameState.chat_log.size() != equipment_expected.size():
		_fail("silent equipment error branches created feedback: %s" % GameState.chat_log)
		return false
	for index in equipment_expected.size():
		if GameState.chat_log[index].text != equipment_expected[index] or GameState.chat_log[index].type != 3:
			_fail("equipment error feedback mismatch at %d: %s" % [index, GameState.chat_log])
			return false
	GameState.chat_log.clear()
	main.call("_on_server_message", NetworkClient.SM_BUYERROR, _buy_error_payload(77, known_item_id, 1, 4))
	main.call("_on_server_message", NetworkClient.SM_BUYERROR, _buy_error_payload(77, known_item_id, 1, 2))
	if GameState.chat_log.size() != 2 or GameState.chat_log[0].text != "金币不够" or GameState.chat_log[1].text != "购买失败" or GameState.chat_log[0].type != 3 or GameState.chat_log[1].type != 3:
		_fail("buy error feedback mismatch: %s" % GameState.chat_log)
		return false
	GameState.chat_log.clear()
	GameState.npc_sell = {"npcUID": 88, "itemList": [packable_id, non_packable_id]}
	GameState.npc_sell_detail = {"npcUID": 77, "list": [
		{"item": {"itemID": packable_id, "seqID": 0}},
		{"item": {"itemID": non_packable_id, "seqID": 9}},
		{"item": {"itemID": non_packable_id, "seqID": 10}},
	]}
	main.call("_on_server_message", NetworkClient.SM_BUYSUCCEED, _buy_succeed_payload(77, non_packable_id, 9))
	if GameState.npc_sell_detail.list.size() != 3:
		_fail("stale shop buy success changed detail list")
		return false
	GameState.npc_sell["npcUID"] = 77
	main.call("_on_server_message", NetworkClient.SM_BUYSUCCEED, _buy_succeed_payload(77, packable_id, 0))
	main.call("_on_server_message", NetworkClient.SM_BUYSUCCEED, _buy_succeed_payload(77, non_packable_id, 9))
	if GameState.npc_sell_detail.list.size() != 2 or GameState.npc_sell_detail.list[0].item.itemID != packable_id or GameState.npc_sell_detail.list[1].item.seqID != 10 or not GameState.chat_log.is_empty():
		_fail("buy success mutation/feedback mismatch: detail=%s log=%s" % [GameState.npc_sell_detail, GameState.chat_log])
		return false
	GameState.player_uid = (5 << 59) | 901
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_on_server_message", NetworkClient.SM_EQUIPWEAR, _equip_wear_payload(GameState.player_uid, 3, weapon_id, 80, 1))
	if AudioService.last_seff_id != resources.item_sound_effect(weapon_id):
		_fail("wear acknowledgement omitted original equip sound: actual=%08X expected=%08X" % [AudioService.last_seff_id, resources.item_sound_effect(weapon_id)])
		return false
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_on_server_message", NetworkClient.SM_EQUIPBELT, _grab_item_payload(1, belt_item_id, 84, 1))
	if AudioService.last_seff_id != resources.item_sound_effect(belt_item_id):
		_fail("belt acknowledgement omitted original item sound: actual=%08X expected=%08X" % [AudioService.last_seff_id, resources.item_sound_effect(belt_item_id)])
		return false
	GameState.wear[3] = _item_record(non_packable_id, 81, 1)
	GameState.grabbed_item = {}
	main.call("_on_server_message", NetworkClient.SM_GRABWEAR, _grab_item_payload(3, non_packable_id, 81, 1))
	if GameState.wear.has(3) or GameState.grabbed_item.get("itemID", 0) != non_packable_id or GameState.grabbed_item.get("seqID", 0) != 81:
		_fail("empty-hand wear grab acknowledgement did not set the returned item: wear=%s grabbed=%s" % [GameState.wear, GameState.grabbed_item])
		return false
	GameState.belt[2] = _item_record(packable_id, 83, 1)
	GameState.grabbed_item = _item_record(non_packable_id, 82, 1)
	var inventory_before_belt_grab := GameState.inventory.size()
	main.call("_on_server_message", NetworkClient.SM_GRABBELT, _grab_item_payload(2, packable_id, 83, 1))
	if not GameState.belt[2].is_empty() or GameState.grabbed_item.get("itemID", 0) != packable_id or GameState.grabbed_item.get("seqID", 0) != 83 or GameState.inventory.size() != inventory_before_belt_grab + 1 or GameState.inventory.back().get("seqID", 0) != 82:
		_fail("occupied-hand belt grab acknowledgement did not swap through inventory: belt=%s grabbed=%s inventory=%s" % [GameState.belt[2], GameState.grabbed_item, GameState.inventory])
		return false
	GameState.chat_log = saved_chat
	GameState.npc_sell = saved_sell
	GameState.npc_sell_detail = saved_detail
	GameState.inventory = saved_inventory
	GameState.wear = saved_wear
	GameState.belt = saved_belt
	GameState.grabbed_item = saved_grabbed
	GameState.player_uid = saved_uid
	return true


func _player_say_payload(uid: int, text: String) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(136)
	payload.encode_u64(0, uid)
	var encoded := text.to_utf8_buffer()
	for index in mini(encoded.size(), 127):
		payload[8 + index] = encoded[index]
	return payload


func _player_name_payload(uid: int, text: String, color: int) -> PackedByteArray:
	var payload := PackedByteArray([1])
	_append_u64(payload, uid)
	var encoded := text.to_utf8_buffer()
	_append_u64(payload, encoded.size())
	payload.append_array(encoded)
	_append_u32(payload, color)
	payload.append(0)
	return payload


func _test_action_seff(main: Control, resources: RefCounted) -> bool:
	AudioService.set_seff_enabled(true)
	AudioService.set_seff_volume(0.5)
	GameState.player_uid = (5 << 59) | 1
	GameState.player_x = 10
	GameState.player_y = 10
	var world_renderer: Node = main.get_node("WorldRenderer")
	if int(world_renderer.get("map_width")) <= 0 and not world_renderer.call("load_map", 24):
		_fail("local movement SEFF fixture could not load map 24")
		return false
	var walk_target := Vector2i(-1, -1)
	for target_y in range(int(world_renderer.get("map_height"))):
		for target_x in range(1, int(world_renderer.get("map_width"))):
			if world_renderer.call("can_walk", target_x, target_y):
				walk_target = Vector2i(target_x, target_y)
				break
		if walk_target.x >= 0:
			break
	if walk_target.x < 0:
		_fail("local movement SEFF fixture could not find a walkable target")
		return false
	GameState.player_x = walk_target.x - 1
	GameState.player_y = walk_target.y
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_send_move_action", walk_target.x, walk_target.y)
	main.set("_move_step_timer", 0.6)
	await get_tree().create_timer(0.15).timeout
	if AudioService.last_seff_id != 0x01000001:
		_fail("real local movement entry did not start the C++ frame-1 step sound")
		return false
	main.call("_set_player_action", 2)
	GameState.player_x = 10
	GameState.player_y = 10
	var weapon_id := 0
	var weapon_sound := 7
	for item_id_value in resources.item_attributes:
		var sound_class: int = resources.item_weapon_sound(item_id_value)
		if sound_class < 7:
			weapon_id = int(item_id_value)
			weapon_sound = sound_class
			break
	if weapon_id == 0:
		_fail("weapon SEFF test item unavailable")
		return false
	main.call("_play_action_seff", GameState.player_uid, {"type": 7, "x": 10, "y": 10}, {
		"uid": GameState.player_uid, "type": 2, "gender": 0,
		"desp": {"wear": {3: {"itemID": weapon_id}}},
	})
	if AudioService.last_seff_id != 0x01010032 + weapon_sound:
		_fail("Hero weapon SEFF route mismatch")
		return false
	var monster_id := 224
	var monster_attack: int = resources.monster_seff(monster_id, 7)
	main.call("_play_action_seff", (4 << 59) | (monster_id << 35) | 1, {"type": 7, "x": 13, "y": 10}, {
		"type": 1, "monster_id": monster_id,
	})
	if AudioService.last_seff_id != monster_attack or AudioService.last_seff_distance != 3:
		_fail("monster attack SEFF route mismatch")
		return false
	var monster_die: int = resources.monster_seff(monster_id, 13)
	main.call("_play_action_seff", (4 << 59) | (monster_id << 35) | 1, {"type": 13, "x": 13, "y": 10}, {
		"type": 1, "monster_id": monster_id,
	})
	if AudioService.last_seff_id != monster_die:
		_fail("monster die SEFF route mismatch")
		return false
	main.call("_play_action_seff", GameState.player_uid, {"type": 11, "x": 10, "y": 10, "aimUID": 0}, {
		"uid": GameState.player_uid, "type": 2, "gender": 0, "desp": {"wear": {}},
	})
	if AudioService.last_seff_id != 0x01010049:
		_fail("Hero hitted impact SEFF route mismatch")
		return false
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	GameState.player_action_type = 3
	GameState.player_action_started_ms = Time.get_ticks_msec()
	main.set("_player_action_timer", 1.0)
	main.call("_play_action_seff", GameState.player_uid, {
		"type": 3, "speed": 100, "x": 10, "y": 10, "aimX": 11, "aimY": 10,
	}, {
		"uid": GameState.player_uid, "type": 2, "action_started_ms": GameState.player_action_started_ms,
	})
	await get_tree().create_timer(0.15).timeout
	if AudioService.last_seff_id != 0x01000001:
		_fail("Hero first movement step did not trigger at frame 1")
		return false
	await get_tree().create_timer(0.3).timeout
	if AudioService.last_seff_id != 0x01000002:
		_fail("Hero second movement step did not trigger at frame 4")
		return false
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	GameState.player_action_started_ms = Time.get_ticks_msec()
	main.set("_player_action_timer", 1.0)
	main.call("_play_action_seff", GameState.player_uid, {
		"type": 3, "speed": 100, "x": 10, "y": 10, "aimX": 12, "aimY": 10,
	}, {
		"uid": GameState.player_uid, "type": 2, "action_started_ms": GameState.player_action_started_ms,
	})
	await get_tree().create_timer(0.15).timeout
	if AudioService.last_seff_id != 0x01000003:
		_fail("Hero two-grid run did not use the original first running step sound")
		return false
	await get_tree().create_timer(0.3).timeout
	if AudioService.last_seff_id != 0x01000004:
		_fail("Hero two-grid run did not use the original second running step sound")
		return false
	AudioService.stop_seff()
	return true


func _test_magic_actions(main: Control, resources: RefCounted, physical_id: int) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_direction = 5
	GameState.magic_effects.clear()
	var firewall_id: int = resources.magic_id("火墙")
	var shield_id: int = resources.magic_id("魔法盾")
	var fireball_id: int = resources.magic_id("火球术")
	var flame_sword_id: int = resources.magic_id("烈火剑法")
	var half_moon_id: int = resources.magic_id("半月弯刀")
	var spin_kick_id: int = resources.magic_id("空拳刀法")
	if 0 in [firewall_id, shield_id, fireball_id, flame_sword_id, half_moon_id, spin_kick_id]:
		_fail("spell metadata unavailable")
		return false
	GameState.player_action_from_x = 9
	GameState.player_action_from_y = 10
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec() - 100
	var remaining_path: Array[Vector2i] = [Vector2i(11, 10)]
	main.set("_move_path", remaining_path)
	var brake_effect_count := GameState.magic_effects.size()
	if not main.call("_cast_magic", firewall_id, Vector2i(12, 10)) \
			or GameState.player_action_type != 3 or GameState.player_action_speed != 200 \
			or (main.get("_pending_spell_action") as Dictionary).is_empty() \
			or GameState.magic_effects.size() != brake_effect_count:
		_fail("moving spell did not preserve the original speed-200 half-step brake")
		return false
	main.call("_process_movement", 0.16)
	if GameState.player_action_type != 9 or not (main.get("_pending_spell_action") as Dictionary).is_empty() \
			or GameState.magic_effects.size() != brake_effect_count + 1:
		_fail("braked movement did not release the deferred spell at the endpoint")
		return false
	GameState.magic_cast_times.erase(firewall_id)
	GameState.player_action_from_x = 9
	GameState.player_action_from_y = 10
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec() - 400
	var late_effect_count := GameState.magic_effects.size()
	if not main.call("_cast_magic", firewall_id, Vector2i(12, 10)) \
			or GameState.player_action_type != 9 or not (main.get("_pending_spell_action") as Dictionary).is_empty() \
			or GameState.magic_effects.size() != late_effect_count + 1:
		_fail("spell after the movement midpoint did not execute immediately")
		return false
	GameState.magic_cast_times.erase(firewall_id)
	GameState.learned_magic = [{"magicID": firewall_id, "exp": 0}]
	GameState.magic_keys = {firewall_id: 120}
	var key_event := InputEventKey.new()
	key_event.unicode = 120
	key_event.keycode = KEY_X
	if not main.call("_try_magic_key", key_event) or GameState.player_action_type != 9:
		_fail("configured magic key did not enter ACTION_SPELL")
		return false
	if GameState.magic_effects.is_empty() or GameState.magic_effects.back().get("magicID", 0) != firewall_id:
		_fail("ground spell did not create local magic effect")
		return false
	GameState.magic_cast_times.erase(firewall_id)
	GameState.player_direction = 5
	var invalid_ground_effect_count := GameState.magic_effects.size()
	if not main.call("_cast_magic", firewall_id, Vector2i(-1, -1)) \
			or GameState.magic_effects.size() != invalid_ground_effect_count + 1:
		_fail("ground spell rejected an invalid mouse grid instead of casting in the current direction")
		return false
	var invalid_ground_effect: Dictionary = GameState.magic_effects.back()
	if GameState.player_direction != 5 or int(invalid_ground_effect.get("direction", -1)) != 5:
		_fail("ground spell turned toward an invalid mouse grid: player=%d effect=%s" % [GameState.player_direction, invalid_ground_effect])
		return false
	if not main.call("_cast_magic", shield_id, Vector2i(12, 12)) or GameState.magic_effects.back().get("aimUID", 0) != GameState.player_uid:
		_fail("self spell did not target player UID")
		return false
	GameState.update_creature(606, {"uid": 606, "x": 11, "y": 10, "type": 1, "action_type": 2})
	GameState.player_direction = 5
	if not main.call("_execute_spell_action", 12, spin_kick_id, Vector2i(11, 10), 606) \
			or GameState.player_action_type != 12 or GameState.player_direction != 7:
		_fail("local spin-kick did not face away from its adjacent target like C++")
		return false
	GameState.remove_creature(606)
	GameState.player_direction = 5
	if not main.call("_execute_spell_action", 12, spin_kick_id, Vector2i(12, 10), 0) or GameState.player_direction != 5:
		_fail("ground-only spin-kick did not preserve its current C++ direction")
		return false
	GameState.update_creature(404, {"uid": 404, "x": 9, "y": 10, "type": 1, "action_type": 2})
	GameState.update_creature(505, {"uid": 505, "x": 12, "y": 10, "type": 1, "action_type": 2})
	var mouse_position := get_viewport().get_mouse_position()
	main.get_node("WorldRenderer")._actor_target_rects = {505: {"rect": Rect2(mouse_position - Vector2.ONE, Vector2.ONE * 2.0), "map_y": 10}}
	main.set("_magic_focus_uid", 404)
	GameState.magic_cast_times[fireball_id] = Time.get_ticks_msec()
	var effect_count := GameState.magic_effects.size()
	var cooldown_log_count := GameState.chat_log.size()
	if main.call("_cast_magic", fireball_id, Vector2i(12, 10)) or main.get("_magic_focus_uid") != 505 or GameState.magic_effects.size() != effect_count:
		_fail("cooldown-blocked spell did not refresh magic focus without casting")
		return false
	var cooldown_log: Dictionary = GameState.chat_log.back() if not GameState.chat_log.is_empty() else {}
	if GameState.chat_log.size() != cooldown_log_count + 1 \
			or cooldown_log.get("text", "") != "%s尚未冷却" % resources.magic_names.get(fireball_id, "") \
			or cooldown_log.get("type", -1) != 3 \
			or cooldown_log.get("color", Color.TRANSPARENT) != Color8(255, 64, 64, 255):
		_fail("cooldown feedback diverged from original error log: %s" % [cooldown_log])
		return false
	GameState.magic_cast_times.erase(fireball_id)
	if not main.call("_cast_magic", fireball_id, Vector2i(12, 10)) or GameState.magic_effects.back().get("aimUID", 0) != 505:
		_fail("target spell did not retain focused creature UID")
		return false
	if not main.call("_cast_magic", flame_sword_id, Vector2i.ZERO) or main.call("_consume_attack_magic_id") != flame_sword_id or main.call("_consume_attack_magic_id") != physical_id:
		_fail("single-use swing magic was not consumed once")
		return false
	if not main.call("_cast_magic", half_moon_id, Vector2i.ZERO) or main.call("_consume_attack_magic_id") != half_moon_id or main.call("_consume_attack_magic_id") != half_moon_id:
		_fail("persistent swing magic was not retained")
		return false
	main.set("_swing_magic", {})
	main.call("_cancel_movement")
	main.get_node("WorldRenderer")._actor_target_rects.clear()
	return true


func _test_hero_spell_gestures(main: Control, resources: RefCounted) -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	var spell0_id: int = resources.magic_id("火球术")
	var spell1_id: int = resources.magic_id("治愈术")
	var attack_mode_id: int = resources.magic_id("铁布衫")
	if 0 in [spell0_id, spell1_id, attack_mode_id]:
		_fail("spell-gesture metadata unavailable")
		return false
	if renderer.call("_hero_motion", 9, spell0_id) != PackedInt32Array([2, 5]) or renderer.call("_hero_motion", 9, spell1_id) != PackedInt32Array([3, 5]) or renderer.call("_hero_motion", 9, attack_mode_id) != PackedInt32Array([7, 3]):
		_fail("spell body motion did not follow magic metadata")
		return false
	for magic_id in [spell0_id, spell1_id, attack_mode_id]:
		var startup_meta: PackedInt32Array = resources.magic_layout(magic_id, 1)
		var cast_motion: int = resources.magic_cast_motion(magic_id)
		var primary_duration := float(maxi(startup_meta[2], 8 if cast_motion == 2 else 10)) * 0.1 * 100.0 / float(clampi(startup_meta[4], 20, 500))
		var expected_duration := primary_duration + (0.6 if cast_motion == 2 else 0.0)
		if not is_equal_approx(float(main.call("_action_duration", 9, 250, 2, magic_id)), expected_duration):
			_fail("spell action duration did not follow synchronized startup: id=%d" % magic_id)
			return false
	var spell0_meta: PackedInt32Array = resources.magic_layout(spell0_id, 1)
	var spell0_primary_ms := float(maxi(spell0_meta[2], 8)) * 10000.0 / float(clampi(spell0_meta[4], 20, 500))
	var spell0_tail_start: PackedInt32Array = renderer.call("_hero_spell_motion_state", spell0_id, 1000, 1000 + ceili(spell0_primary_ms) + 1)
	var spell0_tail_end: PackedInt32Array = renderer.call("_hero_spell_motion_state", spell0_id, 1000, 1000 + ceili(spell0_primary_ms) + 250)
	var spell0_tail_repeat: PackedInt32Array = renderer.call("_hero_spell_motion_state", spell0_id, 1000, 1000 + ceili(spell0_primary_ms) + 350)
	if spell0_tail_start != PackedInt32Array([7, 0, 0]) or spell0_tail_end != PackedInt32Array([7, 2, 0]) or spell0_tail_repeat != PackedInt32Array([7, 0, 0]):
		_fail("SPELL0 did not append two C++ attack-mode holds: %s %s %s" % [spell0_tail_start, spell0_tail_end, spell0_tail_repeat])
		return false
	var spell1_release_ms: int = renderer.call("_hero_spell_trigger_delay", spell1_id, 4)
	var spell1_freeze: PackedInt32Array = renderer.call("_hero_spell_motion_state", spell1_id, 1000, 1000 + spell1_release_ms - 1)
	var spell1_release: PackedInt32Array = renderer.call("_hero_spell_motion_state", spell1_id, 1000, 1000 + spell1_release_ms)
	var attack_mode_start: PackedInt32Array = renderer.call("_hero_spell_motion_state", attack_mode_id, 1000, 1000)
	if spell1_freeze != PackedInt32Array([3, 3, 0]) or spell1_release != PackedInt32Array([3, 4, 0]) or attack_mode_start != PackedInt32Array([7, 0, 5]):
		_fail("spell startup freeze/release or attack-mode direction mismatch: freeze=%s release=%s attack=%s" % [spell1_freeze, spell1_release, attack_mode_start])
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_direction = 3
	GameState.magic_effects.clear()
	var cast_action := {"type": 9, "speed": 100, "direction": 3, "x": 10, "y": 10, "aimX": 10, "aimY": 10, "aimUID": 101, "magicID": attack_mode_id}
	main.call("_handle_action", _sm_action(101, 202, cast_action))
	if GameState.player_direction != 5 or GameState.magic_effects.is_empty() or GameState.magic_effects.back().get("direction", 0) != 5:
		_fail("player attack-mode spell did not force C++ down-facing body/effect")
		return false
	var remote_uid := 778
	GameState.update_creature(remote_uid, {"uid": remote_uid, "x": 10, "y": 10, "type": 2, "gender": 0, "desp": {}, "direction": 3, "action_type": 2})
	main.call("_handle_action", _sm_action(remote_uid, 202, cast_action))
	var remote: Dictionary = GameState.get_creature(remote_uid)
	if remote.get("action_type", 0) != 9 or remote.get("direction", 0) != 5 or GameState.magic_effects.back().get("direction", 0) != 5:
		_fail("remote attack-mode spell did not force C++ down-facing body/effect: %s" % remote)
		return false
	remote["x"] = 10
	remote["y"] = 10
	remote["direction"] = 1
	GameState.update_creature(remote_uid, remote)
	main.call("_handle_action", _sm_action(remote_uid, 202, {
		"type": 9, "speed": 100, "direction": 0, "x": 10, "y": 10,
		"aimX": 12, "aimY": 10, "aimUID": 0, "magicID": spell0_id,
	}))
	remote = GameState.get_creature(remote_uid)
	if remote.get("direction", 0) != 3 or GameState.magic_effects.back().get("direction", 0) != 3:
		_fail("server-normalized remote coordinate spell did not face its aim grid: %s effect=%s" % [remote, GameState.magic_effects.back()])
		return false
	remote["x"] = 11
	remote["y"] = 10
	remote["direction"] = 1
	GameState.update_creature(remote_uid, remote)
	main.call("_handle_action", _sm_action(remote_uid, 202, {
		"type": 9, "speed": 100, "direction": 0, "x": 11, "y": 10,
		"aimX": 10, "aimY": 10, "aimUID": 101, "magicID": spell1_id,
	}))
	remote = GameState.get_creature(remote_uid)
	if remote.get("direction", 0) != 7 or GameState.magic_effects.back().get("direction", 0) != 7:
		_fail("server-normalized remote UID spell did not face the local hero: %s effect=%s" % [remote, GameState.magic_effects.back()])
		return false
	GameState.remove_creature(remote_uid)
	GameState.magic_effects.clear()
	main.call("_set_player_action", 2)
	main.set("_player_action_timer", -1.0)
	return true


func _test_magic_panel_hotkey_precedence(main: Control, resources: RefCounted) -> bool:
	var firewall_id: int = resources.magic_id("火墙")
	var previous_learned: Array = GameState.learned_magic.duplicate(true)
	var previous_keys: Dictionary = GameState.magic_keys.duplicate(true)
	var previous_cast_times: Dictionary = GameState.magic_cast_times.duplicate(true)
	var inventory := main.get_node("InventoryPanel") as Control
	inventory.hide()
	GameState.learned_magic = [{"magicID": firewall_id, "exp": 0}]
	GameState.magic_keys = {firewall_id: 98}
	GameState.magic_cast_times.erase(firewall_id)
	var b_key := InputEventKey.new()
	b_key.keycode = KEY_B
	b_key.unicode = 98
	b_key.pressed = true
	var effect_count := GameState.magic_effects.size()
	main.call("_unhandled_input", b_key)
	if inventory.visible or GameState.magic_effects.size() != effect_count + 1 or GameState.player_action_type != 9:
		_fail("learned B-bound magic was swallowed by the inventory shortcut")
		return false
	effect_count = GameState.magic_effects.size()
	main.call("_unhandled_input", b_key)
	if inventory.visible or GameState.magic_effects.size() != effect_count:
		_fail("cooldown-blocked B-bound magic leaked through to the inventory shortcut")
		return false
	GameState.learned_magic = []
	main.call("_unhandled_input", b_key)
	if not inventory.visible:
		_fail("unlearned B binding did not fall back to the Godot inventory shortcut")
		return false
	inventory.hide()
	var horse_path := "res://scenes/game/panels/horse.tscn"
	var panels: Dictionary = main.get("_extra_panel_nodes")
	if panels.has(horse_path):
		(panels[horse_path] as Control).hide()
	GameState.learned_magic = [{"magicID": firewall_id, "exp": 0}]
	GameState.magic_keys = {firewall_id: 104}
	GameState.magic_cast_times.erase(firewall_id)
	var h_key := InputEventKey.new()
	h_key.keycode = KEY_H
	h_key.unicode = 104
	h_key.pressed = true
	effect_count = GameState.magic_effects.size()
	main.call("_unhandled_input", h_key)
	panels = main.get("_extra_panel_nodes")
	if GameState.magic_effects.size() != effect_count + 1 or (panels.has(horse_path) and (panels[horse_path] as Control).visible):
		_fail("learned H-bound magic was swallowed by the horse-panel shortcut")
		return false
	GameState.learned_magic = []
	main.call("_unhandled_input", h_key)
	panels = main.get("_extra_panel_nodes")
	if not panels.has(horse_path) or not (panels[horse_path] as Control).visible:
		_fail("unlearned H binding did not fall back to the Godot horse-panel shortcut")
		return false
	(panels[horse_path] as Control).hide()
	var quick_bar := main.get_node("%QuickBar") as Control
	quick_bar.show()
	GameState.learned_magic = [{"magicID": firewall_id, "exp": 0}]
	GameState.magic_keys = {firewall_id: 49}
	GameState.magic_cast_times.erase(firewall_id)
	var shifted_digit := InputEventKey.new()
	shifted_digit.keycode = KEY_1
	shifted_digit.unicode = 33
	shifted_digit.shift_pressed = true
	shifted_digit.pressed = true
	effect_count = GameState.magic_effects.size()
	main.call("_unhandled_input", shifted_digit)
	if GameState.magic_effects.size() != effect_count:
		_fail("shifted digit bypassed the original HUD-first quick-bar route")
		return false
	quick_bar.hide()
	main.call("_unhandled_input", shifted_digit)
	if GameState.magic_effects.size() != effect_count + 1:
		_fail("hidden quick bar did not restore the original getKeyChar(false) shifted-digit magic route")
		return false
	GameState.learned_magic = previous_learned
	GameState.magic_keys = previous_keys
	GameState.magic_cast_times = previous_cast_times
	return true


func _test_death_correction_queue(main: Control, resources: RefCounted) -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	var previous_hp := GameState.player_hp
	var line := _find_walkable_line(renderer, 5)
	if line.size() != 5:
		_fail("unable to find a straight walkable death-correction fixture")
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = line[0].x
	GameState.player_y = line[0].y
	GameState.player_direction = 1
	GameState.player_hp = 0
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 13, "x": line[4].x, "y": line[4].y,
	}))
	if GameState.player_action_type != 3 or GameState.player_action_step != 2 or Vector2i(GameState.player_x, GameState.player_y) != line[2] or (main.get("_player_forced_action_queue") as Array).size() != 2:
		_fail("local Hero death did not start with a two-grid forced correction segment")
		return false
	GameState.chat_log.clear()
	main.get_node("ControlPanel").call("_on_command_submitted", "@revive")
	if GameState.chat_log.is_empty() or GameState.chat_log.back().get("text", "") != "复活":
		_fail("health-dead Hero could not request revive during forced correction")
		return false
	GameState.player_hp = 1
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 2, "speed": 100, "direction": 5,
		"x": line[4].x, "y": line[4].y,
		"aimX": line[4].x, "aimY": line[4].y,
	}))
	if GameState.player_action_type != 3 or (main.get("_player_post_forced_action") as Dictionary).is_empty():
		_fail("early revive stand did not wait behind forced death correction")
		return false
	main.call("_on_server_message", NetworkClient.SM_NOTIFYDEAD, _u64_payload(101))
	if GameState.player_action_type != 3:
		_fail("SM_NOTIFYDEAD interrupted the local Hero forced death correction")
		return false
	main.call("_process_player_action", 1.0)
	if GameState.player_action_type != 3 or Vector2i(GameState.player_x, GameState.player_y) != line[4] or (main.get("_player_forced_action_queue") as Array).size() != 1:
		_fail("local Hero death did not advance the second forced correction segment")
		return false
	main.call("_process_player_action", 1.0)
	if GameState.player_action_type != 13 or Vector2i(GameState.player_x, GameState.player_y) != line[4] or not (main.get("_player_forced_action_queue") as Array).is_empty() or float(main.get("_player_action_timer")) <= 0.0:
		_fail("local Hero death did not start at the authoritative correction endpoint")
		return false
	main.call("_process_player_action", 0.5)
	if GameState.player_action_type != 13:
		_fail("early revive skipped the original death motion")
		return false
	main.call("_process_player_action", 1.0)
	if GameState.player_action_type != 2 or Vector2i(GameState.player_x, GameState.player_y) != line[4] or not (main.get("_player_post_forced_action") as Dictionary).is_empty():
		_fail("early revive stand did not run after the forced death motion")
		return false

	var remote_uid: int = (5 << 59) | 801
	GameState.update_creature(remote_uid, {
		"uid": remote_uid, "type": 2, "x": line[0].x, "y": line[0].y,
		"direction": 1, "action_type": 2, "action_started_ms": Time.get_ticks_msec(),
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(remote_uid, 202, {
		"type": 13, "x": line[4].x, "y": line[4].y,
	}))
	var remote: Dictionary = GameState.get_creature(remote_uid)
	if remote.get("action_type", 0) != 3 or remote.get("action_step", 0) != 2 or Vector2i(remote.x, remote.y) != line[2] or remote.get("forced_action_queue", []).size() != 2:
		_fail("remote Hero death did not start with a two-grid forced correction segment: %s" % remote)
		return false
	main.call("_finish_creature_action", remote_uid, 3, remote.action_started_ms)
	remote = GameState.get_creature(remote_uid)
	main.call("_finish_creature_action", remote_uid, 3, remote.action_started_ms)
	remote = GameState.get_creature(remote_uid)
	if remote.get("action_type", 0) != 13 or Vector2i(remote.x, remote.y) != line[4] or remote.has("forced_action_queue"):
		_fail("remote Hero death did not start at the authoritative correction endpoint: %s" % remote)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(remote_uid, 202, {
		"type": 2, "direction": 1, "x": line[0].x, "y": line[0].y,
	}))
	if GameState.get_creature(remote_uid).get("action_type", 0) != 13:
		_fail("action received after remote Hero death interrupted the forced terminal motion")
		return false

	var monster_id := 0
	for monster_id_value in resources.monster_meta:
		if resources.monster_transform(int(monster_id_value)).is_empty():
			monster_id = int(monster_id_value)
			break
	if monster_id == 0:
		_fail("plain monster death-correction fixture unavailable")
		return false
	var monster_uid: int = (4 << 59) | (monster_id << 35) | 802
	GameState.update_creature(monster_uid, {
		"uid": monster_uid, "type": 1, "monster_id": monster_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(),
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 13, "x": line[2].x, "y": line[2].y,
	}))
	var monster: Dictionary = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 3 or monster.get("action_step", 0) != 1 or Vector2i(monster.x, monster.y) != line[1] or monster.get("forced_action_queue", []).size() != 2:
		_fail("Monster death correction was not decomposed into one-grid segments: %s" % monster)
		return false
	main.call("_finish_creature_action", monster_uid, 3, monster.action_started_ms)
	monster = GameState.get_creature(monster_uid)
	main.call("_finish_creature_action", monster_uid, 3, monster.action_started_ms)
	monster = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 13 or Vector2i(monster.x, monster.y) != line[2] or monster.has("forced_action_queue"):
		_fail("Monster death did not start after all one-grid correction segments: %s" % monster)
		return false
	var transform_monster_id := 0
	for monster_id_value in resources.monster_meta:
		if not resources.monster_transform(int(monster_id_value)).is_empty():
			transform_monster_id = int(monster_id_value)
			break
	if transform_monster_id == 0:
		_fail("transforming monster death-correction fixture unavailable")
		return false
	var transform_uid: int = (4 << 59) | (transform_monster_id << 35) | 803
	GameState.update_creature(transform_uid, {
		"uid": transform_uid, "type": 1, "monster_id": transform_monster_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 10,
		"action_speed": 100, "action_magic_id": 0, "action_started_ms": Time.get_ticks_msec(),
		"monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(transform_uid, 202, {
		"type": 13, "x": line[2].x, "y": line[2].y,
	}))
	var transforming: Dictionary = GameState.get_creature(transform_uid)
	if transforming.get("action_type", 0) != 10 or Vector2i(transforming.x, transforming.y) != line[0] or transforming.get("monster_pending_forced_action", {}).get("type", 0) != 13:
		_fail("transforming Monster did not retain its motion before forced death: %s" % transforming)
		return false
	main.call("_finish_creature_action", transform_uid, 10, transforming.action_started_ms)
	transforming = GameState.get_creature(transform_uid)
	if transforming.get("action_type", 0) != 3 or Vector2i(transforming.x, transforming.y) != line[1] or transforming.get("forced_action_queue", []).size() != 2:
		_fail("transforming Monster did not start correction after its transform: %s" % transforming)
		return false
	main.call("_finish_creature_action", transform_uid, 3, transforming.action_started_ms)
	transforming = GameState.get_creature(transform_uid)
	main.call("_finish_creature_action", transform_uid, 3, transforming.action_started_ms)
	transforming = GameState.get_creature(transform_uid)
	if transforming.get("action_type", 0) != 13 or Vector2i(transforming.x, transforming.y) != line[2]:
		_fail("transforming Monster death did not wait for its correction endpoint: %s" % transforming)
		return false
	GameState.remove_creature(remote_uid)
	GameState.remove_creature(monster_uid)
	GameState.remove_creature(transform_uid)
	GameState.player_hp = previous_hp
	return true


func _find_walkable_line(renderer: Control, count: int) -> Array[Vector2i]:
	for y in range(renderer.map_height):
		for x in range(renderer.map_width - count + 1):
			var line: Array[Vector2i] = []
			for offset in range(count):
				if not renderer.call("can_walk", x + offset, y):
					line.clear()
					break
				line.append(Vector2i(x + offset, y))
			if line.size() == count:
				return line
	return []


func _test_death_and_map_filter(main: Control, resources: RefCounted) -> bool:
	var fade_monster_id := 0
	var persistent_monster_id := 0
	var death_magic_monster_id := 0
	var plain_death_monster_id := 0
	for monster_id_value in resources.monster_meta:
		var monster_id: int = monster_id_value
		if resources.monster_dead_fade_out(monster_id) and fade_monster_id == 0:
			fade_monster_id = monster_id
		elif not resources.monster_dead_fade_out(monster_id) and persistent_monster_id == 0:
			persistent_monster_id = monster_id
		if resources.monster_death_magic_id(monster_id) > 0 and death_magic_monster_id == 0:
			death_magic_monster_id = monster_id
		elif resources.monster_death_magic_id(monster_id) == 0 and plain_death_monster_id == 0:
			plain_death_monster_id = monster_id
	if fade_monster_id == 0 or persistent_monster_id == 0 or death_magic_monster_id == 0 or plain_death_monster_id == 0:
		_fail("death lifecycle monster metadata unavailable")
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	(main.get("_player_forced_action_queue") as Array).clear()
	var health_gate_click := InputEventMouseButton.new()
	health_gate_click.button_index = MOUSE_BUTTON_RIGHT
	health_gate_click.pressed = true
	health_gate_click.position = Vector2(500, 300)
	var death_overlay := main.get_node("DeathOverlay") as ColorRect
	GameState.player_health_initialized = false
	GameState.player_hp = 0
	GameState.player_action_type = 2
	main.set("_follow_focus_uid", 777)
	main.call("_update_death_overlay")
	main.call("_unhandled_input", health_gate_click)
	if death_overlay.visible or main.get("_follow_focus_uid") != 777:
		_fail("uninitialized C++ health semantics did not hide the veil and block world input")
		return false
	GameState.player_health_initialized = true
	main.set("_follow_focus_uid", 777)
	main.call("_update_death_overlay")
	main.call("_unhandled_input", health_gate_click)
	if not death_overlay.visible or main.get("_follow_focus_uid") != 777:
		_fail("authoritative HP=0 did not immediately show the veil and block world input before ACTION_DIE")
		return false
	GameState.player_hp = 1
	GameState.player_action_type = 13
	main.call("_update_death_overlay")
	main.call("_unhandled_input", health_gate_click)
	if death_overlay.visible or main.get("_follow_focus_uid") == 777:
		_fail("authoritative HP recovery did not immediately clear the C++ death gate before ACTION_STAND")
		return false
	main.call("_cancel_movement")
	GameState.player_hp = 0
	GameState.player_action_type = 2
	GameState.update_creature(303, {
		"uid": 303, "type": 1, "monster_id": fade_monster_id,
		"x": 5, "y": 5, "direction": 5, "action_type": 2, "action_speed": 100,
	})
	main.call("_on_server_message", NetworkClient.SM_NOTIFYDEAD, _u64_payload(303))
	if GameState.get_creature(303).get("action_type", 0) != 13:
		_fail("creature death action was not applied")
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	if not renderer.call("_is_dead_actor", GameState.get_creature(303)):
		_fail("dead creature was not assigned to the pre-item draw pass")
		return false
	GameState.attached_magic_effects.clear()
	GameState.update_creature(305, {
		"uid": 305, "type": 1, "monster_id": death_magic_monster_id,
		"x": 7, "y": 5, "direction": 5, "action_type": 2, "action_speed": 100,
	})
	main.call("_on_server_message", NetworkClient.SM_NOTIFYDEAD, _u64_payload(305))
	var queued_death_effect: Dictionary = GameState.attached_magic_effects.back() if not GameState.attached_magic_effects.is_empty() else {}
	if queued_death_effect.get("kind", "") != "monster_death" or queued_death_effect.get("target_uid", 0) != 305 or queued_death_effect.get("stage", 0) != 2 or queued_death_effect.get("magicID", 0) != resources.monster_death_magic_id(death_magic_monster_id):
		_fail("death notification did not queue the monster's metadata effect: %s" % queued_death_effect)
		return false
	var death_effect_count := GameState.attached_magic_effects.size()
	main.call("_queue_monster_death_effect", 305, GameState.get_creature(305))
	if GameState.attached_magic_effects.size() != death_effect_count:
		_fail("same death action queued duplicate monster effects")
		return false
	GameState.update_creature(306, {
		"uid": 306, "type": 1, "monster_id": plain_death_monster_id,
		"x": 8, "y": 5, "direction": 5, "action_type": 2, "action_speed": 100,
	})
	main.call("_on_server_message", NetworkClient.SM_NOTIFYDEAD, _u64_payload(306))
	if GameState.attached_magic_effects.size() != death_effect_count:
		_fail("monster without death magic queued an attachment effect")
		return false
	GameState.chat_log.clear()
	main.call("_on_server_message", NetworkClient.SM_NOTIFYDEAD, _u64_payload(101))
	if GameState.player_action_type != 13:
		_fail("player death action was not applied")
		return false
	if not GameState.chat_log.is_empty():
		_fail("player death notification invented a non-original chat entry: %s" % GameState.chat_log)
		return false
	main.call("_update_death_overlay")
	if not death_overlay.visible or not death_overlay.color.is_equal_approx(Color(128.0 / 255.0, 0, 0, 64.0 / 255.0)):
		_fail("player death veil color or visibility mismatch: %s" % death_overlay.color)
		return false
	var command := main.get_node("ControlPanel").get_node("%Command") as LineEdit
	command.release_focus()
	var enter_key := InputEventKey.new()
	enter_key.keycode = KEY_ENTER
	enter_key.pressed = true
	main.call("_unhandled_input", enter_key)
	if not command.has_focus():
		_fail("dead-player gate blocked the original Enter chat focus")
		return false
	main.get_node("ControlPanel").call("_on_command_submitted", "")
	if command.has_focus():
		_fail("submitted HUD command retained input focus")
		return false
	var inventory_panel := main.get_node("InventoryPanel") as Control
	inventory_panel.hide()
	var panel_key := InputEventKey.new()
	panel_key.keycode = KEY_B
	panel_key.pressed = true
	main.call("_unhandled_input", panel_key)
	if not inventory_panel.visible:
		_fail("dead-player gate blocked UI panel interaction")
		return false
	inventory_panel.hide()
	main.set("_follow_focus_uid", 777)
	var blocked_click := InputEventMouseButton.new()
	blocked_click.button_index = MOUSE_BUTTON_RIGHT
	blocked_click.pressed = true
	blocked_click.position = Vector2(500, 300)
	main.call("_unhandled_input", blocked_click)
	if main.get("_follow_focus_uid") != 777:
		_fail("dead player still processed a world mouse command")
		return false
	main.call("_center_hero")
	var centered_view := Vector2(GameState.view_x, GameState.view_y)
	GameState.view_x += 123.0
	GameState.view_y += 77.0
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	main.call("_unhandled_input", escape_key)
	if not Vector2(GameState.view_x, GameState.view_y).is_equal_approx(centered_view):
		_fail("dead-player gate swallowed the original Escape camera recenter")
		return false
	GameState.player_hp = 1
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 2, "speed": 100, "direction": 5,
		"x": GameState.player_x, "y": GameState.player_y,
		"aimX": GameState.player_x, "aimY": GameState.player_y,
	}))
	if GameState.player_action_type != 13 or (main.get("_player_post_forced_action") as Dictionary).is_empty():
		_fail("authoritative revive stand did not wait behind local Hero death motion")
		return false
	main.call("_process_player_action", 2.0)
	if GameState.player_action_type != 2:
		_fail("authoritative revive stand did not clear local Hero death after its motion")
		return false
	main.call("_update_death_overlay")
	main.call("_unhandled_input", blocked_click)
	if death_overlay.visible or main.get("_follow_focus_uid") != 0:
		_fail("living action did not clear the death veil and restore mouse input")
		return false
	main.call("_on_server_message", NetworkClient.SM_OFFLINE, _map_message(303, 999, 16))
	if GameState.get_creature(303).is_empty():
		_fail("stale-map offline message removed current creature")
		return false
	main.call("_on_server_message", NetworkClient.SM_DEADFADEOUT, _map_message(303, 202, 24))
	var fading: Dictionary = GameState.get_creature(303)
	var requested_ms: int = fading.get("dead_fade_requested_ms", 0)
	if requested_ms <= 0:
		_fail("current-map dead fade did not retain and mark the corpse")
		return false
	var early_alpha: float = renderer.call("_dead_actor_alpha", fading, requested_ms + 500)
	var first_fade_alpha: float = renderer.call("_dead_actor_alpha", fading, requested_ms + 1100)
	if not is_equal_approx(early_alpha, 254.0 / 255.0) or not is_equal_approx(first_fade_alpha, 244.0 / 255.0):
		_fail("death animation gate or fade step mismatch: %s %s" % [early_alpha, first_fade_alpha])
		return false
	GameState.update_creature(304, {
		"uid": 304, "type": 1, "monster_id": persistent_monster_id,
		"x": 6, "y": 5, "direction": 5, "action_type": 13, "action_speed": 100,
		"action_started_ms": requested_ms - 2000,
	})
	main.call("_on_server_message", NetworkClient.SM_DEADFADEOUT, _map_message(304, 202, 24))
	if GameState.get_creature(304).has("dead_fade_requested_ms"):
		_fail("persistent corpse incorrectly started fading")
		return false
	GameState.update_creature(307, {
		"uid": 307, "type": 2, "gender": 0, "job": 0,
		"x": 9, "y": 5, "direction": 5, "action_type": 13, "action_speed": 100,
		"action_started_ms": requested_ms - 2000,
	})
	main.call("_on_server_message", NetworkClient.SM_DEADFADEOUT, _map_message(307, 202, 24))
	if GameState.get_creature(307).get("dead_fade_requested_ms", 0) <= 0:
		_fail("dead remote player did not start the original Hero fade-out")
		return false
	renderer.call("_update_dead_fades", requested_ms + 3600)
	if not GameState.get_creature(303).is_empty() or GameState.get_creature(304).is_empty() or not GameState.get_creature(307).is_empty():
		_fail("faded/persistent/player corpse cleanup mismatch")
		return false
	GameState.remove_creature(304)
	GameState.remove_creature(305)
	GameState.remove_creature(306)
	GameState.attached_magic_effects.clear()
	return true


func _u64_payload(value: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(8)
	payload.encode_u64(0, value)
	return payload


func _sm_cast_magic(uid: int, map_uid: int, magic_id: int, aim_uid: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(36)
	payload.encode_u64(0, uid)
	payload.encode_u64(8, map_uid)
	payload[16] = magic_id
	payload[18] = 100
	payload[19] = 1
	payload.encode_u16(20, 3)
	payload.encode_u16(22, 4)
	payload.encode_u16(24, 3)
	payload.encode_u16(26, 4)
	payload.encode_u64(28, aim_uid)
	return payload


func _test_async_combat_feedback(main: Control, resources: RefCounted) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = 3
	GameState.player_y = 4
	GameState.ascend_strings.clear()
	main.call("_on_server_message", NetworkClient.SM_MISS, _u64_payload(999))
	if not GameState.ascend_strings.is_empty():
		_fail("stale SM_MISS created false local-player feedback: %s" % GameState.ascend_strings)
		return false
	main.call("_on_server_message", NetworkClient.SM_MISS, _u64_payload(101))
	if GameState.ascend_strings.size() != 1 or GameState.ascend_strings[0].x != 3 * 48 + 24 - 20 or GameState.ascend_strings[0].y != 3 * 32 or GameState.ascend_strings[0].type != 0:
		_fail("local-player SM_MISS did not use the existing actor position: %s" % GameState.ascend_strings)
		return false
	var target_uid := 303
	GameState.update_creature(target_uid, {"uid": target_uid, "type": 1, "x": 8, "y": 9})
	main.call("_on_server_message", NetworkClient.SM_MISS, _u64_payload(target_uid))
	if GameState.ascend_strings.size() != 2 or GameState.ascend_strings[1].x != 8 * 48 + 24 - 20 or GameState.ascend_strings[1].y != 8 * 32 or GameState.ascend_strings[1].type != 0:
		_fail("creature SM_MISS did not use the existing actor position: %s" % GameState.ascend_strings)
		return false
	GameState.chat_log.clear()
	GameState.attached_magic_effects.clear()
	main.call("_on_server_message", NetworkClient.SM_CASTMAGIC, _sm_cast_magic(101, 202, 0, 101))
	if not GameState.chat_log.is_empty() or not GameState.attached_magic_effects.is_empty():
		_fail("invalid magic record created feedback: log=%s effects=%s" % [GameState.chat_log, GameState.attached_magic_effects])
		return false
	var shield_id: int = resources.magic_id("魔法盾")
	main.call("_on_server_message", NetworkClient.SM_CASTMAGIC, _sm_cast_magic(999, 202, shield_id, 0))
	if GameState.chat_log.size() != 1 or GameState.chat_log[0].text != "使用魔法: 魔法盾" or GameState.chat_log[0].type != 1 or not GameState.attached_magic_effects.is_empty():
		_fail("valid missing-caster magic did not keep log while rejecting attachment: log=%s effects=%s" % [GameState.chat_log, GameState.attached_magic_effects])
		return false
	main.call("_on_server_message", NetworkClient.SM_CASTMAGIC, _sm_cast_magic(101, 202, shield_id, 0))
	if GameState.chat_log.size() != 2 or GameState.attached_magic_effects.size() != 1 or GameState.attached_magic_effects[0].target_uid != 101:
		_fail("valid existing-caster magic feedback was suppressed: log=%s effects=%s" % [GameState.chat_log, GameState.attached_magic_effects])
		return false
	GameState.ascend_strings.clear()
	GameState.chat_log.clear()
	GameState.attached_magic_effects.clear()
	GameState.remove_creature(target_uid)
	return true


func _sd_health_payload(uid: int, hp: int, mp: int, max_hp: int, max_mp: int) -> PackedByteArray:
	var payload := PackedByteArray([1])
	_append_u64(payload, uid)
	for value in [hp, mp, max_hp, max_mp, 0, 0]:
		var offset := payload.size()
		payload.resize(offset + 4)
		payload.encode_s32(offset, value)
	for _index in range(4):
		_append_u64(payload, 0)
	payload.append(0)
	return payload


func _test_health_feedback(main: Control, resources: RefCounted) -> bool:
	for key in [0x03000000, 0x0300000A, 0x0300000B, 0x03000010, 0x0300001A, 0x0300001B, 0x03000020, 0x0300002A, 0x0300002B, 0x03000030]:
		if resources.frame("proguse", key).is_empty():
			_fail("health feedback sprite is unavailable: %08X" % key)
			return false
	GameState.player_uid = 101
	GameState.player_x = 3
	GameState.player_y = 4
	GameState.player_health_initialized = false
	GameState.ascend_strings.clear()
	main.call("_on_server_message", NetworkClient.SM_HEALTH, _sd_health_payload(101, 100, 40, 120, 60))
	if not GameState.ascend_strings.is_empty() or not GameState.player_health_initialized:
		_fail("first local health snapshot was not silent")
		return false
	main.call("_on_server_message", NetworkClient.SM_HEALTH, _sd_health_payload(101, 75, 47, 120, 60))
	if GameState.ascend_strings.size() != 2:
		_fail("combined HP/MP change did not create two feedback entries: %s" % GameState.ascend_strings)
		return false
	var hp_entry: Dictionary = GameState.ascend_strings[0]
	var mp_entry: Dictionary = GameState.ascend_strings[1]
	if hp_entry.type != 1 or hp_entry.value != -25 or hp_entry.x != 3 * 48 + 24 or hp_entry.y != 3 * 32:
		_fail("HP loss feedback mismatched C++: %s" % hp_entry)
		return false
	if mp_entry.type != 2 or mp_entry.value != 7 or mp_entry.x != hp_entry.x or mp_entry.y != hp_entry.y - 32:
		_fail("simultaneous MP gain feedback did not stack above HP: %s" % mp_entry)
		return false
	GameState.ascend_strings.clear()
	main.call("_on_server_message", NetworkClient.SM_HEALTH, _sd_health_payload(101, 85, 42, 120, 60))
	if GameState.ascend_strings.size() != 1 or GameState.ascend_strings[0].type != 3 or GameState.ascend_strings[0].value != 10:
		_fail("HP gain or silent MP loss feedback mismatched C++: %s" % GameState.ascend_strings)
		return false
	var target_uid := 303
	GameState.update_creature(target_uid, {"uid": target_uid, "type": 1, "x": 8, "y": 9, "hp": 999, "mp": 999})
	GameState.ascend_strings.clear()
	main.call("_on_server_message", NetworkClient.SM_HEALTH, _sd_health_payload(target_uid, 50, 10, 50, 20))
	if not GameState.ascend_strings.is_empty():
		_fail("first creature health snapshot was not silent")
		return false
	main.call("_on_server_message", NetworkClient.SM_HEALTH, _sd_health_payload(target_uid, 45, 10, 50, 20))
	if GameState.ascend_strings.size() != 1 or GameState.ascend_strings[0].type != 1 or GameState.ascend_strings[0].value != -5 or GameState.ascend_strings[0].y != 8 * 32:
		_fail("creature health delta feedback mismatch: %s" % GameState.ascend_strings)
		return false
	GameState.ascend_strings.clear()
	main.call("_on_server_message", NetworkClient.SM_HEALTH, _sd_health_payload(999, 1, 1, 1, 1))
	if not GameState.ascend_strings.is_empty():
		_fail("unknown health target created feedback")
		return false
	for value in range(1, 52):
		GameState.add_ascend_value(100, 100, 1, -value)
	if GameState.ascend_strings.size() != 51 or GameState.ascend_strings[0].value != -1:
		_fail("active combat feedback was capped before its C++ lifetime expired: %s" % GameState.ascend_strings.size())
		return false
	GameState.remove_creature(target_uid)
	GameState.ascend_strings.clear()
	return true


func _test_actor_status_overlay(renderer: Control, resources: RefCounted) -> bool:
	if not renderer.has_method("_actor_status_layout") or not renderer.has_method("_should_draw_actor_status") or not renderer.has_method("_should_draw_monster_name"):
		_fail("actor status overlay helpers unavailable")
		return false
	if renderer.get("draw_hp_bar") != false or renderer.call("_should_draw_actor_status", 2):
		_fail("actor status overlay ignored the original default-off --draw-hp-bar option")
		return false
	renderer.set("draw_hp_bar", true)
	if not renderer.call("_should_draw_actor_status", 2) or renderer.call("_should_draw_actor_status", 13):
		_fail("actor status overlay opt-in or dead-motion policy mismatch")
		return false
	renderer.set("draw_hp_bar", false)
	if resources.monster_name(224).is_empty():
		_fail("monster name metadata unavailable")
		return false
	if renderer.call("_monster_display_name", {"monster_id": 224, "name": ""}) != resources.monster_name(224) \
			or renderer.call("_monster_display_name", {"monster_id": 224, "name": "fixture"}) != "fixture":
		_fail("monster display name did not use metadata fallback")
		return false
	if renderer.call("_buff_favor_color", 1) != Color.GREEN \
			or renderer.call("_buff_favor_color", 0) != Color.YELLOW \
			or renderer.call("_buff_favor_color", -1) != Color.RED:
		_fail("actor buff favor colors mismatch")
		return false
	var buff_ids: Array[int] = []
	for value in resources.buff_meta:
		var buff_id := int(value)
		var layout: PackedInt32Array = resources.buff_layout(buff_id)
		if layout.size() >= 2 and not resources.frame("proguse", layout[0]).is_empty():
			buff_ids.append(buff_id)
			if buff_ids.size() == 4:
				break
	if buff_ids.size() < 4:
		_fail("actor status fixture has fewer than four drawable buffs")
		return false
	var layout: Dictionary = renderer.call("_actor_status_layout", 100, 200, 25, 100, buff_ids)
	if layout.get("bar_position") != Vector2i(107, 147) or layout.get("bar_size") != Vector2i(32, 4) or layout.get("fill_width") != 8:
		_fail("actor HP bar layout mismatch: %s" % [layout])
		return false
	var icons: Array = layout.get("icons", [])
	var expected_positions := [Vector2i(108, 137), Vector2i(118, 137), Vector2i(128, 137), Vector2i(108, 127)]
	if icons.size() != 4 or icons.map(func(icon: Dictionary): return icon.position) != expected_positions:
		_fail("actor buff layout mismatch: %s" % [icons])
		return false
	var unknown_max: Dictionary = renderer.call("_actor_status_layout", 5, 7, 0, 0, [])
	if unknown_max.get("fill_width") != 32:
		_fail("unknown max HP was not rendered as full: %s" % [unknown_max])
		return false
	renderer.set("_mouse_focus_uid", 0)
	if renderer.call("_should_draw_monster_name", 303):
		_fail("monster name was shown without mouse focus")
		return false
	renderer.set("_mouse_focus_uid", 303)
	if renderer.call("_should_draw_monster_name", 303):
		_fail("monster name ignored the original draw-HP-bar gate")
		return false
	renderer.set("draw_hp_bar", true)
	if not renderer.call("_should_draw_monster_name", 303) or renderer.call("_should_draw_monster_name", 304):
		_fail("monster name mouse-focus policy mismatch")
		return false
	renderer.set("always_draw_name", true)
	if not renderer.call("_should_draw_monster_name", 304):
		_fail("monster name ignored the original always-draw-name option")
		return false
	return true


func _test_buff_transitions(main: Control, resources: RefCounted) -> bool:
	var shield_id: int = resources.magic_id("魔法盾")
	var buff_id: int = resources.buff_meta.keys()[0]
	var saved_uid: int = GameState.player_uid
	var saved_buffs := GameState.buff_list.duplicate(true)
	var saved_creatures := GameState.creatures.duplicate(true)
	var saved_effects := GameState.attached_magic_effects.duplicate(true)
	var local_uid: int = (5 << 59) | 21
	var remote_uid: int = (5 << 59) | 22
	var monster_uid: int = (4 << 59) | 23
	GameState.player_uid = local_uid
	GameState.buff_list = [buff_id]
	GameState.creatures = {
		remote_uid: {"uid": remote_uid, "type": 2, "buffs": [buff_id]},
		monster_uid: {"uid": monster_uid, "type": 1, "buffs": [buff_id]},
	}
	GameState.attached_magic_effects = [
		{"target_uid": local_uid, "magicID": shield_id, "kind": "shield_hit"},
		{"target_uid": local_uid, "magicID": shield_id + 1, "kind": "yin_yang_ring"},
		{"target_uid": remote_uid, "magicID": shield_id, "kind": "shield"},
		{"target_uid": monster_uid, "magicID": shield_id, "kind": "shield"},
	]
	main.call("_on_server_message", NetworkClient.SM_BUFF, _sm_buff_payload(local_uid, 1, 1))
	main.call("_on_server_message", NetworkClient.SM_BUFF, _sm_buff_payload(local_uid, 2, 2))
	main.call("_on_server_message", NetworkClient.SM_BUFF, _sm_buff_payload(monster_uid, 1, 2))
	main.call("_on_server_message", NetworkClient.SM_BUFF, _sm_buff_payload((5 << 59) | 99, 1, 2))
	main.call("_on_server_message", NetworkClient.SM_BUFF, PackedByteArray([1, 2]))
	if GameState.attached_magic_effects.size() != 4 or GameState.buff_list != [buff_id] or GameState.creatures[remote_uid].buffs != [buff_id] or GameState.creatures[monster_uid].buffs != [buff_id]:
		_fail("non-shield-off SM_BUFF changed attachments or buff IDs")
		return false
	main.call("_on_server_message", NetworkClient.SM_BUFF, _sm_buff_payload(local_uid, 1, 2))
	if GameState.attached_magic_effects.size() != 3 or GameState.attached_magic_effects[0].magicID != shield_id + 1 or GameState.buff_list != [buff_id]:
		_fail("local shield OFF did not remove only the shield attachment: %s" % GameState.attached_magic_effects)
		return false
	main.call("_on_server_message", NetworkClient.SM_BUFF, _sm_buff_payload(remote_uid, 1, 2))
	if GameState.attached_magic_effects.size() != 2 or GameState.attached_magic_effects.any(func(effect): return effect.get("target_uid", 0) == remote_uid) or GameState.creatures[remote_uid].buffs != [buff_id]:
		_fail("remote Hero shield OFF did not preserve list ownership: %s" % GameState.attached_magic_effects)
		return false
	main.call("_on_server_message", NetworkClient.SM_BUFFIDLIST, _buff_id_list_payload(local_uid, [buff_id, buff_id + 1]))
	main.call("_on_server_message", NetworkClient.SM_BUFFIDLIST, _buff_id_list_payload(remote_uid, []))
	if GameState.buff_list != [buff_id, buff_id + 1] or not GameState.creatures[remote_uid].buffs.is_empty() or GameState.creatures[monster_uid].buffs != [buff_id]:
		_fail("SM_BUFFIDLIST did not exclusively own displayed buff IDs")
		return false
	GameState.player_uid = saved_uid
	GameState.buff_list = saved_buffs
	GameState.creatures = saved_creatures
	GameState.attached_magic_effects = saved_effects
	return true


func _test_progression_feedback(main: Control, resources: RefCounted) -> bool:
	var saved_exp := GameState.player_exp
	var saved_gold := GameState.player_gold
	var saved_inventory := GameState.inventory.duplicate(true)
	var saved_chat := GameState.chat_log.duplicate(true)
	var control_panel: Control = main.get_node("ControlPanel")
	var saved_blinks: Dictionary = control_panel.get("_button_blinks").duplicate(true)
	GameState.chat_log.clear()
	GameState.player_exp = 0
	main.call("_on_server_message", NetworkClient.SM_EXP, _u32_payload(100))
	if GameState.player_exp != 100 or not GameState.chat_log.is_empty():
		_fail("initial experience sync produced feedback: exp=%d log=%s" % [GameState.player_exp, GameState.chat_log])
		return false
	main.call("_on_server_message", NetworkClient.SM_EXP, _u32_payload(145))
	main.call("_on_server_message", NetworkClient.SM_EXP, _u32_payload(120))
	if GameState.player_exp != 120 or GameState.chat_log.size() != 1 or GameState.chat_log[0].text != "你获得了经验值45" or GameState.chat_log[0].type != 1:
		_fail("experience feedback did not match C++ gain-only semantics: %s" % GameState.chat_log)
		return false
	GameState.chat_log.clear()
	GameState.player_gold = 0
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_on_server_message", NetworkClient.SM_GOLD, _u32_payload(80))
	if AudioService.last_seff_id != 0x0102006A:
		_fail("gold gain omitted original coin sound")
		return false
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_on_server_message", NetworkClient.SM_GOLD, _u32_payload(80))
	main.call("_on_server_message", NetworkClient.SM_GOLD, _u32_payload(30))
	if AudioService.last_seff_id != AudioService.INVALID_SEFF_ID:
		_fail("unchanged or reduced gold incorrectly played the gain sound")
		return false
	if GameState.player_gold != 30 or GameState.chat_log.size() != 2 or GameState.chat_log[0].text != "你获得了80金币" or GameState.chat_log[1].text != "你失去了50金币":
		_fail("gold feedback did not match C++ change semantics: %s" % GameState.chat_log)
		return false
	var packable_id := 0
	var non_packable_id := 0
	for item_id_value in resources.item_meta:
		var candidate_id: int = item_id_value
		if resources.item_is_packable(candidate_id) and packable_id == 0:
			packable_id = candidate_id
		elif not resources.item_is_packable(candidate_id) and resources.item_type(candidate_id) != "金币" and non_packable_id == 0:
			non_packable_id = candidate_id
		if packable_id != 0 and non_packable_id != 0:
			break
	if packable_id == 0 or non_packable_id == 0:
		_fail("item feedback fixtures unavailable")
		return false
	GameState.chat_log.clear()
	GameState.inventory = [_item_record(packable_id, 71, 2)]
	control_panel.set("_button_blinks", {})
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, _sd_item_payload(packable_id, 71, 5))
	if GameState.inventory[0].count != 5 or GameState.chat_log.size() != 1 or GameState.chat_log[0].text != "你获得了3个%s" % resources.item_name(packable_id):
		_fail("packable item gain feedback mismatch: inventory=%s log=%s" % [GameState.inventory, GameState.chat_log])
		return false
	if not control_panel.get("_button_blinks").has("Inventory") or AudioService.last_seff_id != resources.item_sound_effect(packable_id):
		_fail("item gain did not start original blink/sound: blink=%s seff=%08X" % [control_panel.get("_button_blinks"), AudioService.last_seff_id])
		return false
	control_panel.set("_button_blinks", {})
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, _sd_item_payload(packable_id, 71, 4))
	if GameState.chat_log.size() != 2 or GameState.chat_log[1].text != "你失去了1个%s" % resources.item_name(packable_id) or not control_panel.get("_button_blinks").is_empty() or AudioService.last_seff_id != AudioService.INVALID_SEFF_ID:
		_fail("item loss incorrectly used gain-only notification: log=%s blink=%s seff=%08X" % [GameState.chat_log, control_panel.get("_button_blinks"), AudioService.last_seff_id])
		return false
	main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, _sd_item_payload(non_packable_id, 72, 1))
	if GameState.chat_log.size() != 3 or GameState.chat_log[2].text != "你获得了%s" % resources.item_name(non_packable_id):
		_fail("non-packable item wording mismatch: %s" % GameState.chat_log)
		return false
	var item_count := GameState.inventory.size()
	var log_count := GameState.chat_log.size()
	main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, _sd_item_payload(0xFFFFFFFE, 73, 1))
	main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, _sd_item_payload(packable_id, 71, 100))
	main.call("_on_server_message", NetworkClient.SM_UPDATEITEM, _sd_item_payload(non_packable_id, 72, 2))
	if GameState.inventory.size() != item_count or GameState.inventory[0].count != 4 or GameState.inventory[1].count != 1 or GameState.chat_log.size() != log_count:
		_fail("invalid item update changed visible state")
		return false
	GameState.player_exp = saved_exp
	GameState.player_gold = saved_gold
	GameState.inventory = saved_inventory
	GameState.chat_log = saved_chat
	control_panel.set("_button_blinks", saved_blinks)
	AudioService.stop_seff()
	return true


func _test_ping_feedback(main: Control) -> bool:
	var saved_chat := GameState.chat_log.duplicate(true)
	var saved_pending: bool = main.get("_ping_pending")
	var saved_tick: int = main.get("_ping_tick")
	var saved_last_sent: int = main.get("_last_ping_sent_ms")
	GameState.chat_log.clear()
	main.set("_ping_pending", false)
	main.call("_handle_ping", _u32_payload(123))
	if not GameState.chat_log.is_empty():
		_fail("unsolicited ping echo created feedback")
		return false
	var current_tick: int = Time.get_ticks_msec() & 0xFFFFFFFF
	var sent_tick: int = (current_tick - 20) & 0xFFFFFFFF
	main.set("_ping_pending", true)
	main.set("_ping_tick", sent_tick)
	main.call("_handle_ping", _u32_payload(sent_tick))
	if main.get("_ping_pending") or GameState.chat_log.size() != 1 or GameState.chat_log[0].type != 1 or not GameState.chat_log[0].text.begins_with("延迟") or not GameState.chat_log[0].text.ends_with("ms"):
		_fail("matching ping echo did not complete with original feedback: %s" % GameState.chat_log)
		return false
	var elapsed: int = GameState.chat_log[0].text.trim_prefix("延迟").trim_suffix("ms").to_int()
	if elapsed < 20 or elapsed > 1000:
		_fail("ping latency was not derived from the wire timestamp: %d" % elapsed)
		return false
	main.call("_handle_ping", _u32_payload(sent_tick))
	if GameState.chat_log.size() != 1:
		_fail("duplicate ping echo created repeated feedback")
		return false
	main.set("_ping_pending", true)
	main.set("_ping_tick", 123)
	main.call("_handle_ping", _u32_payload(124))
	main.call("_handle_ping", PackedByteArray([1, 2]))
	if not main.get("_ping_pending") or GameState.chat_log.size() != 1:
		_fail("mismatched or malformed ping echo changed pending state")
		return false
	main.set("_ping_pending", saved_pending)
	main.set("_ping_tick", saved_tick)
	main.set("_last_ping_sent_ms", saved_last_sent)
	GameState.chat_log = saved_chat
	return true


func _u32_payload(value: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, value)
	return payload


func _u16_payload(value: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(2)
	payload.encode_u16(0, value)
	return payload


func _item_error_payload(item_id: int, seq_id: int, error: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u32(0, item_id)
	payload.encode_u32(4, seq_id)
	payload.encode_u16(8, error)
	return payload


func _buy_succeed_payload(npc_uid: int, item_id: int, seq_id: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(16)
	payload.encode_u64(0, npc_uid)
	payload.encode_u32(8, item_id)
	payload.encode_u32(12, seq_id)
	return payload


func _buy_error_payload(npc_uid: int, item_id: int, seq_id: int, error: int) -> PackedByteArray:
	var payload := _buy_succeed_payload(npc_uid, item_id, seq_id)
	payload.resize(18)
	payload.encode_u16(16, error)
	return payload


func _sm_buff_payload(uid: int, type: int, state: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(16)
	payload.encode_u64(0, uid)
	payload.encode_u32(8, type)
	payload.encode_u32(12, state)
	return payload


func _buff_id_list_payload(uid: int, ids: Array) -> PackedByteArray:
	var payload := PackedByteArray([1])
	_append_u64(payload, uid)
	_append_u64(payload, ids.size())
	for id_value in ids:
		_append_u32(payload, id_value)
	payload.append(0)
	return payload


func _item_record(item_id: int, seq_id: int, count: int) -> Dictionary:
	return {"itemID": item_id, "seqID": seq_id, "count": count, "duration": [0, 0], "extAttrList": {}}


func _sd_item_payload(item_id: int, seq_id: int, count: int) -> PackedByteArray:
	var payload := PackedByteArray([1])
	_append_u32(payload, item_id)
	_append_u32(payload, seq_id)
	_append_u64(payload, count)
	_append_u64(payload, 0)
	_append_u64(payload, 0)
	_append_u64(payload, 0)
	payload.append(0)
	return payload


func _grab_item_payload(slot: int, item_id: int, seq_id: int, count: int) -> PackedByteArray:
	var payload := PackedByteArray([1])
	_append_u32(payload, slot)
	_append_u32(payload, item_id)
	_append_u32(payload, seq_id)
	_append_u64(payload, count)
	_append_u64(payload, 0)
	_append_u64(payload, 0)
	_append_u64(payload, 0)
	payload.append(0)
	return payload


func _equip_wear_payload(uid: int, slot: int, item_id: int, seq_id: int, count: int) -> PackedByteArray:
	var payload := PackedByteArray([1])
	_append_u64(payload, uid)
	_append_u32(payload, slot)
	_append_u32(payload, item_id)
	_append_u32(payload, seq_id)
	_append_u64(payload, count)
	_append_u64(payload, 0)
	_append_u64(payload, 0)
	_append_u64(payload, 0)
	payload.append(0)
	return payload


func _append_u32(payload: PackedByteArray, value: int) -> void:
	var offset := payload.size()
	payload.resize(offset + 4)
	payload.encode_u32(offset, value)


func _append_u64(payload: PackedByteArray, value: int) -> void:
	var offset := payload.size()
	payload.resize(offset + 8)
	payload.encode_u64(offset, value)


func _test_shield_hit_action(main: Control, resources: RefCounted) -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	if renderer.map_width <= 0 and not renderer.load_map(24):
		_fail("unable to load hit-correction map fixture")
		return false
	var line := _find_walkable_line(renderer, 3)
	if line.size() != 3:
		_fail("unable to find a straight walkable hit-correction fixture")
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = 3
	GameState.player_y = 4
	GameState.player_direction = 3
	GameState.attached_magic_effects.clear()
	var shield_id: int = resources.magic_id("魔法盾")
	if not GameState.add_cast_magic_attachment({"magic": shield_id, "uid": 101}, "魔法盾"):
		_fail("shield action fixture could not attach shield")
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 11, "speed": 100, "direction": 5, "x": 30, "y": 40, "fromUID": 303,
	}))
	var shield: Dictionary = GameState.attached_magic_effects[0]
	if GameState.player_action_type != 11 or shield.get("kind", "") != "shield_hit" or shield.get("stage", 0) != 5:
		_fail("SM_ACTION ACTION_HITTED did not switch the shield stage: %s" % shield)
		return false
	if GameState.player_x != 3 or GameState.player_y != 4 or GameState.player_action_from_x != 3 or GameState.player_action_from_y != 4 or GameState.player_direction != 3:
		_fail("local Hero ACTION_HITTED did not retain the current endpoint and direction")
		return false
	var remote_uid: int = (5 << 59) | 302
	GameState.update_creature(remote_uid, {
		"uid": remote_uid, "type": 2, "x": 6, "y": 7, "direction": 1, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(remote_uid, 202, {
		"type": 11, "speed": 100, "direction": 7, "x": 60, "y": 70, "fromUID": 303,
	}))
	var remote_hero: Dictionary = GameState.get_creature(remote_uid)
	if remote_hero.get("action_type", 0) != 11 or remote_hero.get("x", 0) != 6 or remote_hero.get("y", 0) != 7 or remote_hero.get("action_from_x", 0) != 6 or remote_hero.get("action_from_y", 0) != 7 or remote_hero.get("direction", 0) != 1:
		_fail("remote Hero ACTION_HITTED did not retain the current endpoint and direction: %s" % remote_hero)
		return false
	var monster_uid: int = (4 << 59) | 304
	GameState.update_creature(monster_uid, {
		"uid": monster_uid, "type": 1, "x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 11, "speed": 100, "direction": 7, "x": line[2].x, "y": line[2].y, "fromUID": 303,
	}))
	var monster: Dictionary = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 3 or Vector2i(monster.x, monster.y) != line[1] or monster.get("motion_action_queue", []).size() != 2:
		_fail("Monster ACTION_HITTED did not start with one-grid correction: %s" % monster)
		return false
	main.call("_finish_creature_action", monster_uid, 3, monster.action_started_ms)
	monster = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 3 or Vector2i(monster.x, monster.y) != line[2] or monster.get("motion_action_queue", []).size() != 1:
		_fail("Monster ACTION_HITTED did not finish its correction segments: %s" % monster)
		return false
	main.call("_finish_creature_action", monster_uid, 3, monster.action_started_ms)
	monster = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 11 or Vector2i(monster.x, monster.y) != line[2] or monster.get("direction", 0) != 7 or monster.has("motion_action_queue"):
		_fail("Monster ACTION_HITTED did not start at the authoritative endpoint: %s" % monster)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 11, "speed": 100, "direction": 5, "x": line[0].x, "y": line[0].y, "fromUID": 303,
	}))
	monster = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 3 or not monster.has("motion_action_queue"):
		_fail("Monster replacement hit did not start a new ordinary correction queue: %s" % monster)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 4, "speed": 100, "direction": 3, "x": line[2].x, "y": line[2].y,
	}))
	monster = GameState.get_creature(monster_uid)
	if monster.get("action_type", 0) != 2 or Vector2i(monster.x, monster.y) != line[2] or monster.has("motion_action_queue"):
		_fail("later Monster action did not replace the ordinary hit-correction queue: %s" % monster)
		return false

	var reveal_monster_id := 0
	for monster_id_value in resources.monster_meta:
		if resources.monster_transform(int(monster_id_value)).get("reveal_on_hit", false):
			reveal_monster_id = int(monster_id_value)
			break
	if reveal_monster_id == 0:
		_fail("reveal-on-hit monster correction fixture unavailable")
		return false
	var reveal_uid: int = (4 << 59) | (reveal_monster_id << 35) | 305
	GameState.update_creature(reveal_uid, {
		"uid": reveal_uid, "type": 1, "monster_id": reveal_monster_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(reveal_uid, 202, {
		"type": 11, "speed": 100, "direction": 7, "x": line[2].x, "y": line[2].y, "fromUID": 303,
	}))
	var revealing: Dictionary = GameState.get_creature(reveal_uid)
	if revealing.get("action_type", 0) != 10 or Vector2i(revealing.x, revealing.y) != line[0] or revealing.get("monster_pending_action", {}).get("type", 0) != 11:
		_fail("hidden Monster did not transform before hit correction: %s" % revealing)
		return false
	main.call("_finish_creature_action", reveal_uid, 10, revealing.action_started_ms)
	revealing = GameState.get_creature(reveal_uid)
	if revealing.get("action_type", 0) != 11 or Vector2i(revealing.x, revealing.y) != line[0] or revealing.get("direction", 0) != 1 or revealing.has("motion_action_queue"):
		_fail("EvilCentipede hit did not stay at its current grid after transformation: %s" % revealing)
		return false
	GameState.remove_creature(monster_uid)
	GameState.remove_creature(reveal_uid)
	GameState.attached_magic_effects.clear()
	main.set("_player_action_timer", -1.0)
	GameState.player_action_type = 2
	return true


func _test_monster_motion_correction(main: Control, resources: RefCounted) -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	var line := _find_walkable_line(renderer, 5)
	if line.size() != 5:
		_fail("unable to find a straight walkable Monster action fixture")
		return false
	if not resources.has_method("monster_motion_correction"):
		_fail("Monster subclass motion-correction metadata unavailable")
		return false
	var transformed_ids: Array[int] = []
	var stand_correction_ids: Array[int] = []
	var attack_correction_ids: Array[int] = []
	var reveal_on_hit_id := 0
	for monster_id_value in resources.monster_meta:
		var candidate_id := int(monster_id_value)
		var candidate_transform: Dictionary = resources.monster_transform(candidate_id)
		if candidate_transform.is_empty():
			continue
		transformed_ids.append(candidate_id)
		if resources.monster_motion_correction(candidate_id, 2):
			stand_correction_ids.append(candidate_id)
		if resources.monster_motion_correction(candidate_id, 7):
			attack_correction_ids.append(candidate_id)
		if candidate_transform.reveal_on_hit:
			reveal_on_hit_id = candidate_id
	if transformed_ids.size() != 10 or stand_correction_ids.size() != 1 or attack_correction_ids.size() != 4 or reveal_on_hit_id == 0:
		_fail("Monster subclass correction classification mismatch: all=%s stand=%s attack=%s reveal=%d" % [transformed_ids, stand_correction_ids, attack_correction_ids, reveal_on_hit_id])
		return false
	for index in range(transformed_ids.size()):
		var move_id: int = transformed_ids[index]
		var move_uid: int = (4 << 59) | (move_id << 35) | (320 + index)
		GameState.update_creature(move_uid, {
			"uid": move_uid, "type": 1, "monster_id": move_id,
			"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
			"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": true,
		})
		main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(move_uid, 202, {
			"type": 3, "speed": 100, "direction": 0,
			"x": line[2].x, "y": line[2].y, "aimX": line[3].x, "aimY": line[3].y,
		}))
		var moving_transform: Dictionary = GameState.get_creature(move_uid)
		if moving_transform.get("action_type", 0) != 3 or Vector2i(moving_transform.x, moving_transform.y) != line[1] or moving_transform.get("action_speed", 0) != 500:
			_fail("transformed Monster ACTION_MOVE skipped base correction: id=%d creature=%s" % [move_id, moving_transform])
			return false
		GameState.remove_creature(move_uid)

	var active_ext := PackedByteArray()
	active_ext.resize(8)
	active_ext[0] = 1
	var stand_id: int = stand_correction_ids[0]
	var stand_uid: int = (4 << 59) | (stand_id << 35) | 340
	GameState.update_creature(stand_uid, {
		"uid": stand_uid, "type": 1, "monster_id": stand_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(stand_uid, 202, {
		"type": 2, "speed": 100, "direction": 7, "x": line[2].x, "y": line[2].y, "extParam": active_ext,
	}))
	var standing_transform: Dictionary = GameState.get_creature(stand_uid)
	if standing_transform.get("action_type", 0) != 10 or standing_transform.get("monster_pending_action", {}).get("type", 0) != 2 or Vector2i(standing_transform.x, standing_transform.y) != line[0]:
		_fail("TaoDog stand correction did not wait behind transformation: %s" % standing_transform)
		return false
	main.call("_finish_creature_action", stand_uid, 10, standing_transform.action_started_ms)
	standing_transform = GameState.get_creature(stand_uid)
	if standing_transform.get("action_type", 0) != 3 or Vector2i(standing_transform.x, standing_transform.y) != line[1] or standing_transform.get("motion_action_queue", []).size() != 2:
		_fail("TaoDog stand correction did not start after transformation: %s" % standing_transform)
		return false
	GameState.remove_creature(stand_uid)

	var static_stand_id: int = transformed_ids.filter(func(id: int) -> bool: return not resources.monster_motion_correction(id, 2))[0]
	var static_stand_uid: int = (4 << 59) | (static_stand_id << 35) | 341
	GameState.update_creature(static_stand_uid, {
		"uid": static_stand_uid, "type": 1, "monster_id": static_stand_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": true,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(static_stand_uid, 202, {
		"type": 2, "speed": 100, "direction": 7, "x": line[2].x, "y": line[2].y, "extParam": active_ext,
	}))
	var static_stand: Dictionary = GameState.get_creature(static_stand_uid)
	if Vector2i(static_stand.x, static_stand.y) != line[0] or static_stand.get("direction", 0) != 1:
		_fail("stationary subclass ACTION_STAND incorrectly applied the message endpoint: %s" % static_stand)
		return false
	GameState.remove_creature(static_stand_uid)

	for index in range(attack_correction_ids.size()):
		var attack_id: int = attack_correction_ids[index]
		var attack_uid: int = (4 << 59) | (attack_id << 35) | (350 + index)
		GameState.update_creature(attack_uid, {
			"uid": attack_uid, "type": 1, "monster_id": attack_id,
			"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
			"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": true,
		})
		main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(attack_uid, 202, {
			"type": 7, "speed": 100, "direction": 5, "x": line[2].x, "y": line[2].y,
		}))
		var attacking_transform: Dictionary = GameState.get_creature(attack_uid)
		if attacking_transform.get("action_type", 0) != 3 or Vector2i(attacking_transform.x, attacking_transform.y) != line[1]:
			_fail("transform subclass ACTION_ATTACK skipped required correction: id=%d creature=%s" % [attack_id, attacking_transform])
			return false
		GameState.remove_creature(attack_uid)
	var direct_attack_id: int = transformed_ids.filter(func(id: int) -> bool: return not resources.monster_motion_correction(id, 7))[0]
	var direct_attack_uid: int = (4 << 59) | (direct_attack_id << 35) | 359
	GameState.update_creature(direct_attack_uid, {
		"uid": direct_attack_uid, "type": 1, "monster_id": direct_attack_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": true,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(direct_attack_uid, 202, {
		"type": 7, "speed": 100, "direction": 5, "x": line[2].x, "y": line[2].y,
	}))
	var direct_attack: Dictionary = GameState.get_creature(direct_attack_uid)
	if direct_attack.get("action_type", 0) != 7 or Vector2i(direct_attack.x, direct_attack.y) != line[2] or direct_attack.has("motion_action_queue"):
		_fail("stationary subclass ACTION_ATTACK incorrectly inserted base correction: %s" % direct_attack)
		return false
	GameState.remove_creature(direct_attack_uid)

	var reveal_uid: int = (4 << 59) | (reveal_on_hit_id << 35) | 360
	GameState.update_creature(reveal_uid, {
		"uid": reveal_uid, "type": 1, "monster_id": reveal_on_hit_id,
		"x": line[0].x, "y": line[0].y, "direction": 7, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": true,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(reveal_uid, 202, {
		"type": 11, "speed": 100, "direction": 5, "x": line[2].x, "y": line[2].y,
	}))
	var reveal_hit: Dictionary = GameState.get_creature(reveal_uid)
	if reveal_hit.get("action_type", 0) != 11 or Vector2i(reveal_hit.x, reveal_hit.y) != line[0] or reveal_hit.get("direction", 0) != 1:
		_fail("EvilCentipede ACTION_HITTED did not retain its current grid and fixed direction: %s" % reveal_hit)
		return false
	GameState.remove_creature(reveal_uid)

	var transforming_hit_id: int = transformed_ids.filter(func(id: int) -> bool: return id != reveal_on_hit_id)[0]
	var transforming_hit_uid: int = (4 << 59) | (transforming_hit_id << 35) | 361
	GameState.update_creature(transforming_hit_uid, {
		"uid": transforming_hit_uid, "type": 1, "monster_id": transforming_hit_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 10,
		"action_started_ms": Time.get_ticks_msec(), "action_speed": 100,
		"monster_stand_mode": true,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(transforming_hit_uid, 202, {
		"type": 11, "speed": 100, "direction": 5, "x": line[2].x, "y": line[2].y,
	}))
	var transforming_hit: Dictionary = GameState.get_creature(transforming_hit_uid)
	if transforming_hit.get("action_type", 0) != 10 or transforming_hit.get("monster_pending_action", {}).get("type", 0) != 11:
		_fail("transforming Monster did not defer ACTION_HITTED until transformation completion: %s" % transforming_hit)
		return false
	main.call("_finish_creature_action", transforming_hit_uid, 10, transforming_hit.action_started_ms)
	transforming_hit = GameState.get_creature(transforming_hit_uid)
	if transforming_hit.get("action_type", 0) != 3 or Vector2i(transforming_hit.x, transforming_hit.y) != line[1] or transforming_hit.get("motion_action_queue", []).size() != 2:
		_fail("deferred Monster ACTION_HITTED did not start correction after transformation: %s" % transforming_hit)
		return false
	GameState.remove_creature(transforming_hit_uid)

	var monster_id := 0
	for monster_id_value in resources.monster_meta:
		if resources.monster_transform(int(monster_id_value)).is_empty():
			monster_id = int(monster_id_value)
			break
	if monster_id == 0:
		_fail("plain Monster action fixture unavailable")
		return false
	var uid: int = (4 << 59) | (monster_id << 35) | 306
	GameState.update_creature(uid, {
		"uid": uid, "type": 1, "monster_id": monster_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(),
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 2, "speed": 100, "direction": 7, "x": line[2].x, "y": line[2].y,
	}))
	var creature: Dictionary = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[1] or creature.get("motion_action_queue", []).size() != 2:
		_fail("Monster ACTION_STAND did not start its correction queue: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 2 or Vector2i(creature.x, creature.y) != line[2] or creature.get("direction", 0) != 7:
		_fail("Monster ACTION_STAND did not start at its corrected endpoint: %s" % creature)
		return false

	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 3, "speed": 100, "direction": 0,
		"x": line[0].x, "y": line[0].y, "aimX": line[1].x, "aimY": line[1].y,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[1] or creature.get("action_speed", 0) != 500 or creature.get("motion_action_queue", []).size() != 2:
		_fail("Monster ACTION_MOVE did not correct to its server start one grid at a time: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.action_from_x, creature.action_from_y) != line[0] or Vector2i(creature.x, creature.y) != line[1] or creature.get("action_speed", 0) != 100:
		_fail("Monster ACTION_MOVE did not play its requested move after correction: %s" % creature)
		return false

	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 7, "speed": 100, "direction": 4, "x": line[3].x, "y": line[3].y,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[2] or creature.get("motion_action_queue", []).size() != 2:
		_fail("Monster ACTION_ATTACK did not start its correction queue: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 7 or Vector2i(creature.x, creature.y) != line[3]:
		_fail("Monster ACTION_ATTACK did not start at its corrected endpoint: %s" % creature)
		return false

	var transform_id := 0
	for monster_id_value in resources.monster_meta:
		if not resources.monster_transform(int(monster_id_value)).is_empty() and resources.monster_motion_correction(int(monster_id_value), 7):
			transform_id = int(monster_id_value)
			break
	if transform_id == 0:
		_fail("transforming Monster attack fixture unavailable")
		return false
	var transform_uid: int = (4 << 59) | (transform_id << 35) | 307
	GameState.update_creature(transform_uid, {
		"uid": transform_uid, "type": 1, "monster_id": transform_id,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(transform_uid, 202, {
		"type": 7, "speed": 100, "direction": 5, "x": line[2].x, "y": line[2].y,
	}))
	var transforming: Dictionary = GameState.get_creature(transform_uid)
	if transforming.get("action_type", 0) != 10 or Vector2i(transforming.x, transforming.y) != line[0] or transforming.get("monster_pending_action", {}).get("type", 0) != 7:
		_fail("hidden Monster did not transform before attack correction: %s" % transforming)
		return false
	main.call("_finish_creature_action", transform_uid, 10, transforming.action_started_ms)
	transforming = GameState.get_creature(transform_uid)
	if transforming.get("action_type", 0) != 3 or Vector2i(transforming.x, transforming.y) != line[1] or transforming.get("motion_action_queue", []).size() != 2:
		_fail("revealed Monster did not start attack correction: %s" % transforming)
		return false
	main.call("_finish_creature_action", transform_uid, 3, transforming.action_started_ms)
	transforming = GameState.get_creature(transform_uid)
	main.call("_finish_creature_action", transform_uid, 3, transforming.action_started_ms)
	transforming = GameState.get_creature(transform_uid)
	if transforming.get("action_type", 0) != 7 or Vector2i(transforming.x, transforming.y) != line[2]:
		_fail("revealed Monster attack did not wait for its correction endpoint: %s" % transforming)
		return false
	GameState.remove_creature(uid)
	GameState.remove_creature(transform_uid)
	return true


func _test_remote_player_motion_correction(main: Control, resources: RefCounted) -> bool:
	var renderer: Control = main.get_node("WorldRenderer")
	if renderer.map_width <= 0 and not renderer.load_map(24):
		_fail("unable to load remote-player correction map fixture")
		return false
	var line := _find_walkable_line(renderer, 4)
	if line.size() != 4:
		_fail("unable to find a straight walkable remote-player correction fixture")
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var uid: int = (5 << 59) | 811
	var base_creature := {
		"uid": uid, "type": 2, "gender": 0, "job": 1, "level": 20,
		"x": line[0].x, "y": line[0].y, "direction": 1, "action_type": 2,
		"action_started_ms": Time.get_ticks_msec(),
	}
	GameState.update_creature(uid, base_creature.duplicate(true))
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 2, "speed": 100, "direction": 7, "x": line[2].x, "y": line[2].y,
	}))
	var creature: Dictionary = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[1] or creature.get("action_speed", 0) != 500 or creature.get("motion_action_queue", []).size() != 2:
		_fail("remote Hero ACTION_STAND did not start one-grid correction: %s" % creature)
		return false
	if OS.has_environment("MIR2X_REMOTE_PLAYER_CORRECTION_SCREENSHOT"):
		GameState.player_x = line[0].x
		GameState.player_y = line[0].y + 3
		GameState.center_camera_on_player()
		await get_tree().create_timer(0.06).timeout
		await RenderingServer.frame_post_draw
		var screenshot_error := get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_REMOTE_PLAYER_CORRECTION_SCREENSHOT"))
		if screenshot_error != OK:
			_fail("failed to save remote-player correction screenshot: %s" % error_string(screenshot_error))
			return false
		return true
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if Vector2i(creature.x, creature.y) != line[2] or creature.get("motion_action_queue", []).size() != 1:
		_fail("remote Hero ACTION_STAND did not finish its correction segments: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 2 or Vector2i(creature.x, creature.y) != line[2] or creature.get("direction", 0) != 7 or creature.has("motion_action_queue"):
		_fail("remote Hero ACTION_STAND did not start at the authoritative endpoint: %s" % creature)
		return false

	GameState.update_creature(uid, base_creature.merged({"x": line[2].x, "y": line[2].y}, true))
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 3, "speed": 100, "direction": 0,
		"x": line[0].x, "y": line[0].y, "aimX": line[1].x, "aimY": line[1].y,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[1] or creature.get("action_speed", 0) != 500 or creature.get("motion_action_queue", []).size() != 2:
		_fail("remote Hero ACTION_MOVE did not correct to its server start first: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.action_from_x, creature.action_from_y) != line[0] or Vector2i(creature.x, creature.y) != line[1] or creature.get("action_speed", 0) != 100 or creature.has("motion_action_queue"):
		_fail("remote Hero ACTION_MOVE did not run after correction: %s" % creature)
		return false

	var spell_id := 0
	for magic_id_value in resources.magic_meta:
		var candidate_id: int = magic_id_value
		if not resources.magic_layout(candidate_id, 1).is_empty():
			spell_id = candidate_id
			break
	if spell_id == 0:
		_fail("remote Hero spell correction fixture unavailable")
		return false
	for action_type in [7, 8, 9, 12]:
		GameState.magic_effects.clear()
		GameState.update_creature(uid, base_creature.duplicate(true))
		var action := {
			"type": action_type, "speed": 100, "direction": 4,
			"x": line[2].x, "y": line[2].y,
			"magicID": spell_id if action_type == 9 else 0,
		}
		main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, action))
		creature = GameState.get_creature(uid)
		if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[1] or creature.get("motion_action_queue", []).size() != 2:
			_fail("remote Hero action %d skipped its correction queue: %s" % [action_type, creature])
			return false
		main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
		creature = GameState.get_creature(uid)
		main.call("_finish_creature_action", uid, 3, creature.action_started_ms)
		creature = GameState.get_creature(uid)
		if creature.get("action_type", 0) != action_type or Vector2i(creature.x, creature.y) != line[2] or creature.has("motion_action_queue"):
			_fail("remote Hero action %d did not start after correction: %s" % [action_type, creature])
			return false
		if action_type == 9 and not GameState.magic_effects.any(func(effect: Dictionary) -> bool: return effect.get("source", "") == "action" and effect.get("uid", 0) == uid and effect.get("magicID", 0) == spell_id):
			_fail("remote Hero spell effect was not deferred until correction completion")
			return false

	GameState.update_creature(uid, base_creature.duplicate(true))
	var union_data := PackedByteArray([7, 99, 0, 0, 0])
	main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(uid, 202, {
		"type": 2, "speed": 100, "direction": 6, "x": line[2].x, "y": line[2].y,
	}, union_data))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 3 or Vector2i(creature.x, creature.y) != line[1] or creature.get("motion_action_queue", []).size() != 2 or creature.get("gender", -1) != 0 or creature.get("job", -1) != 1 or creature.get("level", -1) != 20:
		_fail("existing remote Hero SM_CORECORD did not reuse action correction or overwrote constructor metadata: %s" % creature)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 11, "speed": 100, "direction": 5, "x": line[3].x, "y": line[3].y,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 11 or Vector2i(creature.x, creature.y) != line[1] or creature.has("motion_action_queue"):
		_fail("new remote Hero action did not replace the pending correction queue: %s" % creature)
		return false
	GameState.remove_creature(uid)
	return true


func _test_spinkick_direction(main: Control) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = 3
	GameState.player_y = 4
	GameState.player_direction = 5
	GameState.update_creature(303, {
		"uid": 303, "type": 1, "x": 4, "y": 4, "direction": 5, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 12, "speed": 100, "x": 3, "y": 4, "aimUID": 303,
	}))
	if GameState.player_action_type != 12 or GameState.player_direction != 7:
		_fail("ACTION_SPINKICK did not face away from its adjacent target like C++")
		return false
	GameState.player_direction = 5
	GameState.update_creature(303, {
		"uid": 303, "type": 1, "x": 8, "y": 4, "direction": 5, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 12, "speed": 100, "x": 3, "y": 4, "aimUID": 303,
	}))
	if GameState.player_direction != 5:
		_fail("non-adjacent ACTION_SPINKICK incorrectly replaced the retained direction")
		return false
	var remote_uid: int = (5 << 59) | 304
	GameState.update_creature(remote_uid, {
		"uid": remote_uid, "type": 2, "x": 4, "y": 4, "direction": 1, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(remote_uid, 202, {
		"type": 7, "speed": 100, "direction": 0, "x": 4, "y": 4, "aimUID": 101,
	}))
	if GameState.get_creature(remote_uid).get("direction", 0) != 7:
		_fail("server-normalized remote ACTION_ATTACK did not face its adjacent target: %s" % GameState.get_creature(remote_uid))
		return false
	var monster_uid: int = (4 << 59) | (224 << 35) | 305
	GameState.update_creature(monster_uid, {
		"uid": monster_uid, "type": 1, "monster_id": 224, "x": 2, "y": 4, "direction": 1, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 7, "speed": 100, "direction": 0, "x": 2, "y": 4, "aimUID": 101,
	}))
	if GameState.get_creature(monster_uid).get("direction", 0) != 3:
		_fail("server-normalized monster ACTION_ATTACK did not face the local hero: %s" % GameState.get_creature(monster_uid))
		return false
	GameState.remove_creature(303)
	GameState.remove_creature(remote_uid)
	GameState.remove_creature(monster_uid)
	main.set("_player_action_timer", -1.0)
	GameState.player_action_type = 2
	return true


func _test_actor_record_lifecycle(main: Control) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var monster_uid: int = (4 << 59) | (224 << 35) | 303
	var remote_player_uid: int = (5 << 59) | 404
	var npc_uid: int = (3 << 59) | (7 << 35) | 407
	if not main.has_method("_query_initial_creature_state"):
		_fail("new actors do not expose the C++ initial state queries")
		return false
	var monster_queries: Dictionary = main.call("_query_initial_creature_state", monster_uid, true)
	if monster_queries.keys() != ["buff"] or monster_queries.buff != ERR_UNCONFIGURED:
		_fail("new monster initial query mismatch: %s" % monster_queries)
		return false
	var player_queries: Dictionary = main.call("_query_initial_creature_state", remote_player_uid, true)
	for expected: String in ["buff", "name", "appearance"]:
		if not player_queries.has(expected) or player_queries[expected] != ERR_UNCONFIGURED:
			_fail("new player omitted initial %s query: %s" % [expected, player_queries])
			return false
	if not (main.call("_query_initial_creature_state", npc_uid, true) as Dictionary).is_empty():
		_fail("NPC incorrectly attempted initial state queries")
		return false
	if not (main.call("_query_initial_creature_state", monster_uid, false) as Dictionary).is_empty():
		_fail("existing actor incorrectly repeated initial state queries")
		return false
	GameState.update_creature(monster_uid, {
		"uid": monster_uid, "type": 1, "monster_id": 224,
		"x": 5, "y": 6, "direction": 3, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 1, "speed": 100, "direction": 7, "x": 20, "y": 21,
	}))
	var retained: Dictionary = GameState.get_creature(monster_uid)
	if retained.get("x", 0) != 5 or retained.get("y", 0) != 6 or retained.get("direction", 0) != 3 or retained.get("action_type", 0) != 2:
		_fail("late ACTION_SPAWN reset an existing actor: %s" % retained)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(monster_uid, 202, {
		"type": 3, "speed": 100, "direction": 0, "x": 5, "y": 6, "aimX": 6, "aimY": 5,
	}))
	var moving_monster: Dictionary = GameState.get_creature(monster_uid)
	if moving_monster.get("direction", 0) != 2:
		_fail("direction-less ACTION_MOVE did not face an existing actor along its path: %s" % moving_monster)
		return false

	var player_uid := remote_player_uid
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(player_uid, 202, {
		"type": 3, "speed": 100, "direction": 5, "x": 8, "y": 9, "aimX": 9, "aimY": 9,
	}))
	if not GameState.get_creature(player_uid).is_empty():
		_fail("unknown player action created a blank phantom before SM_CORECORD")
		return false
	var player_union := PackedByteArray([5, 18, 0, 0, 0])
	main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(player_uid, 202, {
		"type": 3, "speed": 100, "direction": 0, "x": 9, "y": 9, "aimX": 8, "aimY": 10,
	}, player_union))
	var resolved: Dictionary = GameState.get_creature(player_uid)
	if resolved.get("type", 0) != 2 or resolved.get("gender", 0) != 1 or resolved.get("job", 0) != 2 or resolved.get("level", 0) != 18 or resolved.get("direction", 0) != 6:
		_fail("matching SM_CORECORD did not create the queried player: %s" % resolved)
		return false

	var stale_uid: int = (5 << 59) | 405
	main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(stale_uid, 999, {
		"type": 2, "speed": 100, "direction": 5, "x": 30, "y": 31,
	}, player_union))
	if not GameState.get_creature(stale_uid).is_empty():
		_fail("stale-map SM_CORECORD inserted an actor into the current world")
		return false
	var new_monster_uid: int = (4 << 59) | (225 << 35) | 406
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(new_monster_uid, 202, {
		"type": 2, "speed": 100, "direction": 4, "x": 11, "y": 12,
	}))
	var new_npc_uid := npc_uid
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(new_npc_uid, 202, {
		"type": 1, "speed": 100, "direction": 1, "x": 13, "y": 14,
	}))
	if GameState.get_creature(new_monster_uid).get("monster_id", 0) != 225 or GameState.get_creature(new_monster_uid).get("action_type", 0) != 2 or GameState.get_creature(new_npc_uid).get("npc_id", 0) != 7:
		_fail("player-specific record query suppressed unknown monster or NPC creation")
		return false
	GameState.remove_creature(monster_uid)
	GameState.remove_creature(player_uid)
	GameState.remove_creature(new_monster_uid)
	GameState.remove_creature(new_npc_uid)
	return true


func _test_action_created_monster_queries(main: Control) -> bool:
	var listener := TCPServer.new()
	if listener.listen(0, "127.0.0.1") != OK:
		_fail("unable to open action-created monster query capture")
		return false
	var client_peer := StreamPeerTCP.new()
	if client_peer.connect_to_host("127.0.0.1", listener.get_local_port()) != OK:
		listener.stop()
		_fail("unable to connect action-created monster query capture")
		return false
	var capture_peer: StreamPeerTCP = null
	for _attempt in 120:
		client_peer.poll()
		if listener.is_connection_available():
			capture_peer = listener.take_connection()
			break
		await get_tree().process_frame
	if capture_peer == null or client_peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		listener.stop()
		_fail("action-created monster query capture did not connect")
		return false
	NetworkClient.disconnect_from_server()
	NetworkClient.set("_peer", client_peer)
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var monster_id := 224
	var action_uid: int = (4 << 59) | (monster_id << 35) | 661
	main.call("_handle_action_data", {
		"uid": action_uid,
		"mapUID": 202,
		"action": {"type": 2, "speed": 100, "direction": 3, "x": 20, "y": 21},
	})
	var runtime_resources: RefCounted = main.get("_resources")
	var spawn_meta: PackedInt32Array = runtime_resources.monster_meta[monster_id]
	var spawn_seff: int = spawn_meta[2]
	spawn_meta[2] = 0xFFFFFFFF
	runtime_resources.monster_meta[monster_id] = spawn_meta
	var spawn_uid: int = (4 << 59) | (monster_id << 35) | 662
	main.call("_handle_action_data", {
		"uid": spawn_uid,
		"mapUID": 202,
		"action": {"type": 1, "speed": 100, "direction": 3, "x": 22, "y": 21},
	})
	spawn_meta[2] = spawn_seff
	runtime_resources.monster_meta[monster_id] = spawn_meta
	for _attempt in 5:
		capture_peer.poll()
		await get_tree().process_frame
	var packet_data := PackedByteArray()
	var available := capture_peer.get_available_bytes()
	if available > 0:
		var capture_result: Array = capture_peer.get_data(available)
		if capture_result[0] == OK:
			packet_data = capture_result[1]
	var query_heads := _fixed_u64_packet_heads(packet_data)
	NetworkClient.disconnect_from_server()
	listener.stop()
	for uid in [action_uid, spawn_uid]:
		GameState.remove_creature(uid)
	var expected_heads := [
		NetworkClient.CM_QUERYUIDBUFF,
		NetworkClient.CM_QUERYUIDBUFF, NetworkClient.CM_QUERYCORECORD,
	]
	if query_heads != expected_heads:
		_fail("action-created monster initial query sequence mismatch: actual=%s expected=%s bytes=%s" % [query_heads, expected_heads, packet_data])
		return false
	return true


func _fixed_u64_packet_heads(packet_data: PackedByteArray) -> Array[int]:
	var heads: Array[int] = []
	var cursor := 0
	while cursor < packet_data.size():
		heads.append(packet_data[cursor] & 0x7F)
		cursor += 1
		var body_size := 0
		var shift := 0
		while cursor < packet_data.size():
			var byte := packet_data[cursor]
			cursor += 1
			body_size |= (byte & 0x7F) << shift
			if not byte & 0x80:
				break
			shift += 7
		if cursor >= packet_data.size():
			return []
		cursor += 1 + body_size # one mask byte for the fixed eight-byte UID payload
		if cursor > packet_data.size():
			return []
	return heads


func _test_npc_actions(main: Control) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var renderer: Control = main.get_node("WorldRenderer")
	var npc_uid: int = (3 << 59) | (7 << 35) | 408
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(npc_uid, 202, {
		"type": 1, "speed": 100, "direction": 8, "x": 13, "y": 14,
	}))
	var npc: Dictionary = GameState.get_creature(npc_uid)
	var sequence: Dictionary = renderer.call("_npc_render_sequence", npc)
	if npc.get("npc_motion", -1) != 0 or sequence != {"motion": 0, "direction": 7, "count": 4}:
		_fail("NPC spawn did not select the exact stand motion/view: npc=%s sequence=%s" % [npc, sequence])
		return false
	var ext_act := PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0])
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(npc_uid, 202, {
		"type": 2, "speed": 150, "direction": 4, "x": 13, "y": 14, "extParam": ext_act,
	}))
	npc = GameState.get_creature(npc_uid)
	sequence = renderer.call("_npc_render_sequence", npc)
	if npc.get("npc_motion", -1) != 1 or npc.get("action_speed", 0) != 100 or sequence != {"motion": 1, "direction": 3, "count": 4}:
		_fail("NPC stand act did not preserve motion/view metadata: npc=%s sequence=%s" % [npc, sequence])
		return false
	var ext_act_ext := PackedByteArray([2, 0, 0, 0, 0, 0, 0, 0])
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(npc_uid, 202, {
		"type": 2, "speed": 100, "direction": 1, "x": 13, "y": 14, "extParam": ext_act_ext,
	}))
	npc = GameState.get_creature(npc_uid)
	sequence = renderer.call("_npc_render_sequence", npc)
	if npc.get("npc_motion", -1) != 2 or sequence.count != 0 or main.call("_creature_action_duration", 2, 100, npc) >= 0.0:
		_fail("normal NPC ACTEXT did not preserve the original empty sequence: npc=%s sequence=%s" % [npc, sequence])
		return false
	var special_uid: int = (3 << 59) | (56 << 35) | 409
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(special_uid, 202, {
		"type": 1, "speed": 100, "direction": 1, "x": 15, "y": 16,
	}))
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(special_uid, 202, {
		"type": 2, "speed": 100, "direction": 1, "x": 15, "y": 16, "extParam": ext_act_ext,
	}))
	var special: Dictionary = GameState.get_creature(special_uid)
	sequence = renderer.call("_npc_render_sequence", special)
	if sequence.count != 12 or not is_equal_approx(float(main.call("_creature_action_duration", 2, 100, special)), 1.2):
		_fail("six-face-stone NPC did not use its original twelve-frame sequence: npc=%s sequence=%s" % [special, sequence])
		return false
	main.call("_finish_creature_action", special_uid, 2, special.action_started_ms)
	if GameState.get_creature(special_uid).get("npc_motion", -1) != 1:
		_fail("completed NPC ACTEXT did not enter the original ACT idle motion")
		return false
	for special_id in [59, 64, 65]:
		sequence = renderer.call("_npc_render_sequence", {"npc_id": special_id, "npc_motion": 0, "direction": 1})
		if sequence.count != 1:
			_fail("single-frame NPC %d did not retain its exact count: %s" % [special_id, sequence])
			return false
	GameState.remove_creature(npc_uid)
	GameState.remove_creature(special_uid)
	return true


func _test_monster_spawn_actions(main: Control, resources: RefCounted) -> bool:
	var summon_monsters := {
		"变异骷髅": "召唤骷髅",
		"超强骷髅": "超强召唤骷髅",
		"神兽": "召唤神兽",
	}
	var summon_ids := {}
	for monster_id_value in resources.monster_names:
		var summon_monster_id: int = monster_id_value
		var summon_monster_name: String = resources.monster_name(summon_monster_id)
		if summon_monsters.has(summon_monster_name):
			summon_ids[summon_monster_name] = summon_monster_id
	if summon_ids.size() != summon_monsters.size():
		_fail("summon monster metadata unavailable: %s" % [summon_ids])
		return false
	GameState.chat_log.clear()
	GameState.magic_effects.clear()
	var summon_uids: Array[int] = []
	var summon_index := 0
	for summon_monster_name in summon_monsters:
		var summon_monster_id: int = summon_ids[summon_monster_name]
		var summon_uid: int = (4 << 59) | (summon_monster_id << 35) | (690 + summon_index)
		summon_uids.append(summon_uid)
		var spawn_payload := _sm_action(summon_uid, 202, {
			"type": 1, "speed": 100, "direction": 5, "x": 24 + summon_index * 2, "y": 25,
		})
		main.call("_on_server_message", NetworkClient.SM_ACTION, spawn_payload)
		main.call("_on_server_message", NetworkClient.SM_ACTION, spawn_payload)
		if summon_monster_name in ["变异骷髅", "超强骷髅"]:
			if not GameState.get_creature(summon_uid).is_empty():
				_fail("summoned skeleton appeared before the original frame-10 barrier completed")
				return false
			var blockers: Dictionary = main.get("_summon_spawn_blockers")
			if not blockers.has(summon_uid):
				_fail("summoned skeleton did not install its original action blocker")
				return false
			var matching_effects := GameState.magic_effects.filter(func(effect: Dictionary) -> bool:
				return effect.get("source", "") == "summon_spawn" and effect.get("summon_uid", 0) == summon_uid
			)
			if matching_effects.size() != 1 or matching_effects[0].get("magicID", 0) != resources.magic_id(summon_monsters[summon_monster_name]):
				_fail("summoned skeleton did not retain one matching run-stage effect: %s" % [matching_effects])
				return false
		else:
			if GameState.get_creature(summon_uid).is_empty() or main.get("_summon_spawn_blockers").has(summon_uid):
				_fail("TaoDog did not retain its original immediate spawn semantics")
				return false
		summon_index += 1
	if GameState.chat_log.size() != summon_monsters.size():
		_fail("summon ACTION_SPAWN feedback count mismatch: %s" % [GameState.chat_log])
		return false
	for index in summon_monsters.size():
		var summon_monster_name: String = summon_monsters.keys()[index]
		var expected_log := "使用魔法: %s" % summon_monsters[summon_monster_name]
		if GameState.chat_log[index].text != expected_log or GameState.chat_log[index].type != 1:
			_fail("summon ACTION_SPAWN feedback mismatch at %d: %s" % [index, GameState.chat_log])
			return false
	for summon_uid in summon_uids:
		var blockers: Dictionary = main.get("_summon_spawn_blockers")
		if blockers.has(summon_uid):
			main.call("_finish_summon_spawn", summon_uid, blockers[summon_uid].token)
			var skeleton: Dictionary = GameState.get_creature(summon_uid)
			if skeleton.get("action_type", 0) != 2 or skeleton.get("direction", 0) != resources.monster_spawn_direction(skeleton.get("monster_id", 0)):
				_fail("summoned skeleton did not finish in its original stand/down-left state: %s" % skeleton)
				return false
			if main.get("_summon_spawn_blockers").has(summon_uid):
				_fail("summoned skeleton action blocker survived completion")
				return false
		GameState.remove_creature(summon_uid)
	if GameState.magic_effects.any(func(effect: Dictionary) -> bool: return effect.get("source", "") == "summon_spawn"):
		_fail("completed summon run-stage effects were not removed")
		return false
	GameState.chat_log.clear()
	var special_id := 0
	for monster_id_value in resources.monster_meta:
		if resources.monster_spawn_look(int(monster_id_value)) > 0:
			special_id = int(monster_id_value)
			break
	if special_id == 0:
		_fail("special monster spawn metadata unavailable")
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var special_uid: int = (4 << 59) | (special_id << 35) | 703
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(special_uid, 202, {
		"type": 1, "speed": 100, "direction": 5, "x": 32, "y": 33,
	}))
	var special: Dictionary = GameState.get_creature(special_uid)
	if special.get("action_type", 0) != 1 or special.get("monster_stand_look", 0) != resources.monster_spawn_look(special_id):
		_fail("TaoDog spawn did not retain its redirected special motion/look: %s" % special)
		return false
	if not is_equal_approx(float(main.call("_action_duration", 1, 100, 1)), 1.0):
		_fail("special monster spawn did not use the C++ ten-frame duration")
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	if renderer.call("_monster_motion", special.get("action_type", 0)) != PackedInt32Array([8, 10]):
		_fail("special monster spawn did not select MOTION_MON_SPAWN graphics")
		return false
	GameState.magic_effects.clear()
	var ground_spawn_ids: Array[int] = []
	for monster_id_value in resources.monster_meta:
		if resources.monster_spawn_effect_magic_id(int(monster_id_value)) > 0:
			ground_spawn_ids.append(int(monster_id_value))
	if ground_spawn_ids.size() != 2:
		_fail("monster ground-spawn metadata unavailable: %s" % ground_spawn_ids)
		return false
	for index in range(ground_spawn_ids.size()):
		var ground_id: int = ground_spawn_ids[index]
		var ground_uid: int = (4 << 59) | (ground_id << 35) | (710 + index)
		var ground_union := PackedByteArray()
		ground_union.resize(4)
		ground_union.encode_u32(0, ground_id)
		main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(ground_uid, 202, {
			"type": 1, "speed": 100, "direction": 3 + index, "x": 36 + index * 2, "y": 37,
		}, ground_union))
		var ground_creature: Dictionary = GameState.get_creature(ground_uid)
		var ground_effect: Dictionary = GameState.magic_effects.back() if not GameState.magic_effects.is_empty() else {}
		if ground_creature.get("action_type", 0) != 1 or ground_creature.has("monster_stand_look") or ground_effect.get("source", "") != "monster_spawn_ground" or ground_effect.get("magicID", 0) != resources.monster_spawn_effect_magic_id(ground_id) or ground_effect.get("direction", 0) != 3 + index or ground_effect.get("start_time", 0) != ground_creature.action_started_ms + 900:
			_fail("monster ground spawn action/effect mismatch: monster=%s effect=%s" % [ground_creature, ground_effect])
			return false
		GameState.remove_creature(ground_uid)
	var ordinary_id := 0
	for monster_id_value in resources.monster_meta:
		var candidate_id: int = monster_id_value
		if resources.monster_spawn_look(candidate_id) == 0 and resources.monster_spawn_effect_magic_id(candidate_id) == 0:
			ordinary_id = candidate_id
			break
	if ordinary_id == 0:
		_fail("ordinary monster spawn fixture unavailable")
		return false
	var runtime_resources: RefCounted = main.get("_resources")
	var ordinary_meta: PackedInt32Array = runtime_resources.monster_meta[ordinary_id]
	var ordinary_spawn_seff: int = ordinary_meta[2]
	ordinary_meta[2] = 0xFFFFFFFF
	runtime_resources.monster_meta[ordinary_id] = ordinary_meta
	var ordinary_uid: int = (4 << 59) | (ordinary_id << 35) | 704
	var ordinary_union := PackedByteArray()
	ordinary_union.resize(4)
	ordinary_union.encode_u32(0, ordinary_id)
	main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(ordinary_uid, 202, {
		"type": 1, "speed": 100, "direction": 3, "x": 34, "y": 35,
	}, ordinary_union))
	var ordinary: Dictionary = GameState.get_creature(ordinary_uid)
	ordinary_meta[2] = ordinary_spawn_seff
	runtime_resources.monster_meta[ordinary_id] = ordinary_meta
	if ordinary.get("monster_id", 0) != ordinary_id or ordinary.get("action_type", 0) != 2:
		_fail("ordinary SM_CORECORD spawn did not create a standing monster: %s" % ordinary)
		return false
	GameState.remove_creature(special_uid)
	GameState.remove_creature(ordinary_uid)
	GameState.magic_effects.clear()
	return true


func _test_monster_body_profiles(main: Control, resources: RefCounted) -> bool:
	var physical_id: int = resources.magic_id("物理攻击")
	var savage_id: int = resources.magic_id("霸王教主_野蛮冲撞")
	var shipwreck_id := 0
	var pharaoh_id := 0
	var fixed_direction_ids: Array[int] = []
	var tree_ids: Array[int] = []
	var spawn_direction_ids: Array[int] = []
	var guard_ids: Array[int] = []
	for monster_id_value in resources.monster_meta:
		var monster_id: int = monster_id_value
		var physical_sequence: PackedInt32Array = resources.monster_body_sequence(monster_id, 7, physical_id)
		var savage_sequence: PackedInt32Array = resources.monster_body_sequence(monster_id, 7, savage_id)
		if physical_sequence == PackedInt32Array([2, 10, -1]) and savage_sequence == PackedInt32Array([6, 10, -1]):
			shipwreck_id = monster_id
		if physical_sequence == PackedInt32Array([6, 6, -1]):
			pharaoh_id = monster_id
		if resources.monster_body_sequence(monster_id, 2)[2] == 0:
			fixed_direction_ids.append(monster_id)
		if resources.monster_body_sequence(monster_id, 13) == PackedInt32Array([0, 4, 0]):
			tree_ids.append(monster_id)
		if resources.monster_spawn_direction(monster_id) == 6:
			spawn_direction_ids.append(monster_id)
		if resources.monster_behave_mode(monster_id) == 2:
			guard_ids.append(monster_id)
	if physical_id <= 0 or savage_id <= 0 or shipwreck_id == 0 or pharaoh_id == 0 or fixed_direction_ids.size() != 4 or tree_ids.size() != 3 or spawn_direction_ids.size() != 2 or guard_ids.size() != 4:
		_fail("special monster body fixtures unavailable: ship=%d pharaoh=%d fixed=%s tree=%s spawn=%s" % [shipwreck_id, pharaoh_id, fixed_direction_ids, tree_ids, spawn_direction_ids])
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	var guard_id: int = guard_ids[0]
	var guard_resources: RefCounted = main.get("_resources")
	var guard_meta: PackedInt32Array = guard_resources.monster_meta[guard_id]
	var guard_attack_seff: int = guard_meta[3]
	guard_meta[3] = 0xFFFFFFFF
	guard_resources.monster_meta[guard_id] = guard_meta
	var guard_uid: int = (4 << 59) | (guard_id << 35) | 729
	GameState.update_creature(guard_uid, {
		"uid": guard_uid, "type": 1, "monster_id": guard_id, "x": 40, "y": 41,
		"direction": 3, "action_type": 7, "action_started_ms": 12345,
		"motion_action_queue": [{"type": 3}],
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(guard_uid, 202, {"type": 2, "speed": 100, "direction": 7, "x": 40, "y": 41}))
	var guard: Dictionary = GameState.get_creature(guard_uid)
	if guard.get("action_type", 0) != 7 or guard.get("action_started_ms", 0) != 12345 or guard.get("direction", 0) != 3 or guard.has("motion_action_queue"):
		_fail("same-grid Guard stand did not preserve current motion while clearing its queue: %s" % guard)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(guard_uid, 202, {"type": 2, "speed": 100, "direction": 7, "x": 42, "y": 43}))
	guard = GameState.get_creature(guard_uid)
	if guard.get("action_type", 0) != 2 or Vector2i(guard.x, guard.y) != Vector2i(42, 43) or guard.get("direction", 0) != 7:
		_fail("moved Guard stand did not synchronize immediately: %s" % guard)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(guard_uid, 202, {"type": 7, "speed": 100, "direction": 5, "x": 45, "y": 46}))
	guard = GameState.get_creature(guard_uid)
	if guard.get("action_type", 0) != 7 or Vector2i(guard.x, guard.y) != Vector2i(45, 46) or guard.has("motion_action_queue"):
		_fail("Guard attack incorrectly used ordinary Monster position correction: %s" % guard)
		return false
	GameState.remove_creature(guard_uid)
	guard_meta[3] = guard_attack_seff
	guard_resources.monster_meta[guard_id] = guard_meta
	var shipwreck_creature := {"type": 1, "monster_id": shipwreck_id, "action_type": 7, "action_magic_id": physical_id, "direction": 7}
	var physical_render: Dictionary = renderer.call("_monster_render_sequence", shipwreck_creature)
	shipwreck_creature["action_magic_id"] = savage_id
	var savage_render: Dictionary = renderer.call("_monster_render_sequence", shipwreck_creature)
	if physical_render.motion != 2 or physical_render.count != 10 or savage_render.motion != 6 or savage_render.count != 10:
		_fail("ShipwreckLord body branch mismatch: physical=%s savage=%s" % [physical_render, savage_render])
		return false
	if not is_equal_approx(float(main.call("_creature_action_duration", 7, 100, shipwreck_creature, savage_id)), 1.0):
		_fail("ShipwreckLord ten-frame body duration was not shared with action scheduling")
		return false
	var pharaoh_render: Dictionary = renderer.call("_monster_render_sequence", {"type": 1, "monster_id": pharaoh_id, "action_type": 7, "action_magic_id": savage_id, "direction": 5})
	if pharaoh_render.motion != 6 or pharaoh_render.count != 6 or not is_equal_approx(float(main.call("_creature_action_duration", 7, 100, {"type": 1, "monster_id": pharaoh_id}, savage_id)), 0.6):
		_fail("Numa Grand Pharaoh spell-body redirect mismatch: %s" % pharaoh_render)
		return false
	for tree_id in tree_ids:
		var tree_render: Dictionary = renderer.call("_monster_render_sequence", {"type": 1, "monster_id": tree_id, "action_type": 13, "direction": 8})
		if tree_render.motion != 0 or tree_render.count != 4 or tree_render.direction != 0:
			_fail("tree body did not stay on fixed-direction stand graphics: id=%d render=%s" % [tree_id, tree_render])
			return false
	var fixed_non_tree_id: int = fixed_direction_ids.filter(func(id: int) -> bool: return id not in tree_ids)[0]
	var fixed_attack: Dictionary = renderer.call("_monster_render_sequence", {"type": 1, "monster_id": fixed_non_tree_id, "action_type": 7, "direction": 8})
	if fixed_attack.motion != 2 or fixed_attack.count != 6 or fixed_attack.direction != 0:
		_fail("BugbatMaggot body direction was not fixed: %s" % fixed_attack)
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var runtime_resources: RefCounted = main.get("_resources")
	for index in range(spawn_direction_ids.size()):
		var monster_id: int = spawn_direction_ids[index]
		var monster_meta: PackedInt32Array = runtime_resources.monster_meta[monster_id]
		var spawn_seff: int = monster_meta[2]
		monster_meta[2] = 0xFFFFFFFF
		runtime_resources.monster_meta[monster_id] = monster_meta
		var uid: int = (4 << 59) | (monster_id << 35) | (730 + index)
		if index == 0:
			main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {"type": 1, "speed": 100, "direction": 2, "x": 42, "y": 43}))
			var blockers: Dictionary = main.get("_summon_spawn_blockers")
			if not blockers.has(uid):
				_fail("Tao skeleton initial spawn did not enter its original frame-10 barrier")
				return false
			main.call("_finish_summon_spawn", uid, blockers[uid].token)
		else:
			var union_data := PackedByteArray()
			union_data.resize(4)
			union_data.encode_u32(0, monster_id)
			main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(uid, 202, {"type": 1, "speed": 100, "direction": 2, "x": 44, "y": 43}, union_data))
		var spawned: Dictionary = GameState.get_creature(uid)
		monster_meta[2] = spawn_seff
		runtime_resources.monster_meta[monster_id] = monster_meta
		if spawned.get("action_type", 0) != 2 or spawned.get("direction", 0) != 6:
			_fail("Tao skeleton initial spawn direction mismatch: %s" % spawned)
			return false
		GameState.remove_creature(uid)
	return true


func _test_monster_transform_actions(main: Control, resources: RefCounted) -> bool:
	var monster_id := 0
	var hidden_focusable_id := 0
	for monster_id_value in resources.monster_meta:
		var candidate_id: int = monster_id_value
		var candidate: Dictionary = resources.monster_transform(candidate_id)
		if not candidate.is_empty() and candidate.hidden_focusable:
			hidden_focusable_id = candidate_id
		if not candidate.is_empty() and not candidate.hidden_focusable and (monster_id == 0 or resources.monster_transform_effect_magic_id(candidate_id) > 0):
			monster_id = candidate_id
	if monster_id == 0 or hidden_focusable_id == 0:
		_fail("transformed monster focus fixtures unavailable")
		return false
	var transform: Dictionary = resources.monster_transform(monster_id)
	var runtime_resources: RefCounted = main.get("_resources")
	var meta: PackedInt32Array = runtime_resources.monster_meta[monster_id]
	var spawn_seff: int = meta[2]
	meta[2] = 0xFFFFFFFF
	runtime_resources.monster_meta[monster_id] = meta
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var uid: int = (4 << 59) | (monster_id << 35) | 705
	var union_data := PackedByteArray()
	union_data.resize(4)
	union_data.encode_u32(0, monster_id)
	main.call("_on_server_message", NetworkClient.SM_CORECORD, _sm_corecord(uid, 202, {
		"type": 1, "speed": 100, "direction": 5, "x": 40, "y": 41,
	}, union_data))
	var creature: Dictionary = GameState.get_creature(uid)
	var renderer: Control = main.get_node("WorldRenderer")
	var sequence: Dictionary = renderer.call("_monster_render_sequence", creature)
	if creature.get("action_type", 0) != 2 or creature.get("monster_stand_mode", true) or sequence.focusable or sequence.motion != transform.hidden_stand[0] or sequence.begin != transform.hidden_stand[1]:
		_fail("monster spawn did not enter the C++ hidden form: creature=%s sequence=%s" % [creature, sequence])
		return false
	var tao_sequence: Dictionary = renderer.call("_monster_render_sequence", {
		"monster_id": hidden_focusable_id, "action_type": 2, "monster_stand_mode": false, "direction": 5,
	})
	var tao_transform: Dictionary = resources.monster_transform(hidden_focusable_id)
	if not tao_sequence.focusable or tao_sequence.look != tao_transform.hidden_look or tao_sequence.count != 4:
		_fail("TaoDog hidden form lost its redirected look or focusability: %s" % tao_sequence)
		return false
	var ext_active := PackedByteArray()
	ext_active.resize(8)
	ext_active[0] = 1
	GameState.magic_effects.clear()
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 2, "speed": 100, "direction": 5, "x": 40, "y": 41, "extParam": ext_active,
	}))
	creature = GameState.get_creature(uid)
	sequence = renderer.call("_monster_render_sequence", creature)
	if creature.get("action_type", 0) != 10 or not creature.get("monster_stand_mode", false) or sequence.motion != transform.active_transform[0] or sequence.begin != transform.active_transform[1] or sequence.reverse != transform.active_reverse or not sequence.focusable:
		_fail("ACTION_STAND did not queue the active-form transformation: creature=%s sequence=%s" % [creature, sequence])
		return false
	var transform_effect_magic_id: int = resources.monster_transform_effect_magic_id(monster_id)
	var transform_effect: Dictionary = GameState.magic_effects.back() if not GameState.magic_effects.is_empty() else {}
	if transform_effect_magic_id <= 0 or transform_effect.get("magicID", 0) != transform_effect_magic_id or transform_effect.get("source", "") != "monster_transform" or transform_effect.get("uid", 0) != uid or transform_effect.get("start_time", 0) != creature.action_started_ms + 900:
		_fail("ZumaTaurus transform did not queue its frame-9 fragment: %s" % transform_effect)
		return false
	var expected_duration := float(transform.active_transform[2]) * 0.1
	if not is_equal_approx(float(main.call("_creature_action_duration", 10, 100, creature)), expected_duration):
		_fail("active transformation duration mismatch")
		return false
	var started_ms: int = creature.action_started_ms
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 10, "speed": 100, "direction": 5, "x": 40, "y": 41, "extParam": ext_active,
	}))
	if GameState.get_creature(uid).get("action_started_ms", 0) != started_ms:
		_fail("redundant ACTION_TRANSF restarted an existing form")
		return false
	if GameState.magic_effects.size() != 1:
		_fail("redundant ACTION_TRANSF duplicated the frame-9 fragment")
		return false
	var ext_hidden := PackedByteArray()
	ext_hidden.resize(8)
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 10, "speed": 100, "direction": 5, "x": 40, "y": 41, "extParam": ext_hidden,
	}))
	creature = GameState.get_creature(uid)
	sequence = renderer.call("_monster_render_sequence", creature)
	if creature.get("action_type", 0) != 10 or not creature.get("monster_stand_mode", false) or creature.get("monster_pending_form_modes", []) != [false] or sequence.motion != transform.active_transform[0]:
		_fail("ACTION_TRANSF did not queue behind the active transformation: creature=%s sequence=%s" % [creature, sequence])
		return false
	main.call("_finish_creature_action", uid, 10, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	sequence = renderer.call("_monster_render_sequence", creature)
	if creature.get("action_type", 0) != 10 or creature.get("monster_stand_mode", true) or sequence.motion != transform.hidden_transform[0] or sequence.begin != transform.hidden_transform[1] or sequence.reverse != transform.hidden_reverse or sequence.focusable:
		_fail("queued hidden transformation did not start after active transformation: creature=%s sequence=%s" % [creature, sequence])
		return false
	if GameState.magic_effects.size() != 2 or GameState.magic_effects.back().get("action_started_ms", -1) != creature.action_started_ms:
		_fail("queued hidden transformation did not create a distinct frame-9 fragment: %s" % GameState.magic_effects)
		return false
	main.call("_finish_creature_action", uid, 10, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	var idle_started_ms: int = creature.action_started_ms
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 10, "speed": 100, "direction": 3, "x": 99, "y": 98, "extParam": ext_hidden,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 2 or creature.action_started_ms != idle_started_ms or creature.x != 40 or creature.y != 41:
		_fail("redundant idle ACTION_TRANSF changed the current motion or position: %s" % creature)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 7, "speed": 100, "direction": 5, "x": 40, "y": 41,
	}))
	creature = GameState.get_creature(uid)
	sequence = renderer.call("_monster_render_sequence", creature)
	if creature.get("action_type", 0) != 10 or not creature.get("monster_stand_mode", false) or creature.get("monster_pending_action", {}).get("type", 0) != 7 or sequence.motion != transform.active_transform[0]:
		_fail("hidden monster attack did not queue transformation before attack: %s" % creature)
		return false
	var reveal_started_ms: int = creature.action_started_ms
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 7, "speed": 150, "direction": 6, "x": 44, "y": 45,
	}))
	creature = GameState.get_creature(uid)
	var replaced_pending: Dictionary = creature.get("monster_pending_action", {})
	if creature.get("action_type", 0) != 10 or creature.action_started_ms != reveal_started_ms or creature.x != 40 or creature.y != 41 or replaced_pending.get("speed", 0) != 150 or replaced_pending.get("state", {}).get("x", 0) != 44:
		_fail("new attack did not replace the pending action while preserving the active transformation: %s" % creature)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 2, "speed": 100, "direction": 5, "x": 40, "y": 41, "extParam": ext_hidden,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 10 or not creature.get("monster_stand_mode", false) or creature.get("monster_pending_form_modes", []) != [false] or creature.has("monster_pending_action"):
		_fail("new stand request did not cancel the queued monster attack: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 10, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	main.call("_finish_creature_action", uid, 10, creature.action_started_ms)
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 7, "speed": 100, "direction": 5, "x": 40, "y": 41,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("monster_pending_action", {}).get("type", 0) != 7:
		_fail("hidden monster attack was not queued after interruption recovery: %s" % creature)
		return false
	main.call("_finish_creature_action", uid, 10, creature.action_started_ms)
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 7 or creature.has("monster_pending_action"):
		_fail("queued monster attack did not start after transformation: %s" % creature)
		return false
	var attack_started_ms: int = creature.action_started_ms
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(uid, 202, {
		"type": 10, "speed": 100, "direction": 2, "x": 91, "y": 92, "extParam": ext_active,
	}))
	creature = GameState.get_creature(uid)
	if creature.get("action_type", 0) != 7 or creature.action_started_ms != attack_started_ms or creature.x != 40 or creature.y != 41:
		_fail("redundant transform interrupted or restarted the current attack: %s" % creature)
		return false
	var reveal_on_hit_id := 0
	for monster_id_value in resources.monster_meta:
		if resources.monster_transform(int(monster_id_value)).get("reveal_on_hit", false):
			reveal_on_hit_id = int(monster_id_value)
			break
	if reveal_on_hit_id == 0:
		_fail("reveal-on-hit monster fixture unavailable")
		return false
	var hit_meta: PackedInt32Array = runtime_resources.monster_meta[reveal_on_hit_id]
	var hit_spawn_seff: int = hit_meta[2]
	hit_meta[2] = 0xFFFFFFFF
	runtime_resources.monster_meta[reveal_on_hit_id] = hit_meta
	var hit_uid: int = (4 << 59) | (reveal_on_hit_id << 35) | 706
	GameState.update_creature(hit_uid, {
		"uid": hit_uid, "type": 1, "monster_id": reveal_on_hit_id, "x": 42, "y": 43,
		"direction": 1, "action_type": 2, "action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(hit_uid, 202, {
		"type": 11, "speed": 100, "direction": 1, "x": 42, "y": 43,
	}))
	var hit_creature: Dictionary = GameState.get_creature(hit_uid)
	if hit_creature.get("action_type", 0) != 10 or hit_creature.get("monster_pending_action", {}).get("type", 0) != 11:
		_fail("EvilCentipede hit did not queue transformation before reaction: %s" % hit_creature)
		return false
	var die_seff: int = meta[5]
	meta[5] = 0xFFFFFFFF
	runtime_resources.monster_meta[monster_id] = meta
	var death_uid: int = (4 << 59) | (monster_id << 35) | 707
	GameState.update_creature(death_uid, {
		"uid": death_uid, "type": 1, "monster_id": monster_id, "x": 50, "y": 51,
		"direction": 1, "action_type": 2, "action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(death_uid, 202, {
		"type": 7, "speed": 100, "direction": 1, "x": 52, "y": 53,
	}))
	main.call("_on_server_message", NetworkClient.SM_NOTIFYDEAD, _u64_payload(death_uid))
	var death_creature: Dictionary = GameState.get_creature(death_uid)
	if death_creature.get("action_type", 0) != 10 or death_creature.x != 50 or death_creature.y != 51 or death_creature.has("monster_pending_action") or death_creature.get("monster_pending_forced_action", {}).get("type", 0) != 13:
		_fail("death did not wait behind the forced transformation: %s" % death_creature)
		return false
	var forced_started_ms: int = death_creature.action_started_ms
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(death_uid, 202, {
		"type": 2, "speed": 100, "direction": 1, "x": 10, "y": 10, "extParam": ext_active,
	}))
	if GameState.get_creature(death_uid).action_started_ms != forced_started_ms:
		_fail("action received behind a queued death was not ignored")
		return false
	main.call("_finish_creature_action", death_uid, 10, death_creature.action_started_ms)
	death_creature = GameState.get_creature(death_uid)
	if death_creature.get("action_type", 0) != 13 or death_creature.x != 50 or death_creature.y != 51 or death_creature.has("monster_pending_forced_action"):
		_fail("queued death did not start after the forced transformation: %s" % death_creature)
		return false
	var flush_uid: int = (4 << 59) | (monster_id << 35) | 708
	GameState.update_creature(flush_uid, {
		"uid": flush_uid, "type": 1, "monster_id": monster_id, "x": 60, "y": 61,
		"direction": 1, "action_type": 2, "action_started_ms": Time.get_ticks_msec(), "monster_stand_mode": false,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(flush_uid, 202, {
		"type": 7, "speed": 100, "direction": 1, "x": 60, "y": 61,
	}))
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(flush_uid, 202, {
		"type": 4, "speed": 100, "direction": 3, "x": 62, "y": 63,
	}))
	var flush_creature: Dictionary = GameState.get_creature(flush_uid)
	if flush_creature.get("action_type", 0) != 2 or flush_creature.x != 62 or flush_creature.y != 63 or not flush_creature.get("monster_stand_mode", false) or flush_creature.has("monster_pending_action") or flush_creature.has("monster_pending_form_modes"):
		_fail("ACTION_JUMP did not flush the forced transformation queue: %s" % flush_creature)
		return false
	flush_creature["x"] = 70
	flush_creature["y"] = 71
	flush_creature["action_type"] = 2
	flush_creature["monster_stand_mode"] = false
	GameState.update_creature(flush_uid, flush_creature)
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(flush_uid, 202, {
		"type": 7, "speed": 100, "direction": 1, "x": 70, "y": 71,
	}))
	var effect_count := GameState.magic_effects.size()
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(flush_uid, 202, {
		"type": 6, "speed": 100, "direction": 4, "x": 70, "y": 71, "aimX": 75, "aimY": 76,
	}))
	flush_creature = GameState.get_creature(flush_uid)
	if flush_creature.get("action_type", 0) != 6 or flush_creature.x != 75 or flush_creature.y != 76 or not flush_creature.get("monster_stand_mode", false) or flush_creature.has("monster_pending_action"):
		_fail("ACTION_SPACEMOVE did not flush the forced transformation queue: %s" % flush_creature)
		return false
	GameState.magic_effects.resize(effect_count)
	meta[2] = spawn_seff
	meta[5] = die_seff
	runtime_resources.monster_meta[monster_id] = meta
	hit_meta[2] = hit_spawn_seff
	runtime_resources.monster_meta[reveal_on_hit_id] = hit_meta
	GameState.remove_creature(uid)
	GameState.remove_creature(hit_uid)
	GameState.remove_creature(death_uid)
	GameState.remove_creature(flush_uid)
	return true


func _test_monster_jump_stands(main: Control) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	var known_uid: int = (4 << 59) | (224 << 35) | 701
	GameState.update_creature(known_uid, {
		"uid": known_uid, "type": 1, "monster_id": 224,
		"x": 5, "y": 6, "direction": 3, "action_type": 7,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(known_uid, 202, {
		"type": 4, "speed": 100, "direction": 7, "x": 20, "y": 21,
	}))
	var known: Dictionary = GameState.get_creature(known_uid)
	if known.get("x", 0) != 20 or known.get("y", 0) != 21 or known.get("direction", 0) != 7 or known.get("action_type", 0) != 2:
		_fail("known monster ACTION_JUMP did not become stand at action position: %s" % known)
		return false

	var new_uid: int = (4 << 59) | (225 << 35) | 702
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(new_uid, 202, {
		"type": 4, "speed": 100, "direction": 5, "x": 30, "y": 31,
	}))
	var created: Dictionary = GameState.get_creature(new_uid)
	if created.get("monster_id", 0) != 225 or created.get("x", 0) != 30 or created.get("y", 0) != 31 or created.get("direction", 0) != 5 or created.get("action_type", 0) != 2:
		_fail("new monster ACTION_JUMP did not create a standing actor: %s" % created)
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	var now := Time.get_ticks_msec()
	if renderer.call("_motion_frame", created.get("action_type", 0), 4, now - 500, 100) != 1:
		_fail("monster jump stand motion did not remain cyclic")
		return false
	GameState.remove_creature(known_uid)
	GameState.remove_creature(new_uid)
	return true


func _test_self_action_map_transition(main: Control) -> bool:
	AudioService.set_seff_enabled(true)
	if not AudioService.play_seff_at(AudioService.UI_CLICK_SEFF_ID, 0, 0, 0, 0, 0) or AudioService.active_seff_count() == 0:
		_fail("looping map-load SEFF fixture did not start")
		return false
	if not main.call("_load_world_map", 25):
		_fail("map-load SEFF cleanup fixture could not reload map 25")
		return false
	if AudioService.active_seff_count() != 0:
		_fail("shared world load did not stop active C++ sound effects")
		return false
	GameState.player_uid = 101
	GameState.player_map_uid = 25 << 35
	GameState.player_map_id = 25
	GameState.player_x = 10
	GameState.player_y = 11
	GameState.update_creature(303, {"uid": 303, "type": 1, "x": 11, "y": 11, "action_type": 2})
	GameState.ground_items["10,11"] = [1]
	GameState.firewalls = [{"x": 10, "y": 11}]
	GameState.magic_effects = [{"uid": 303}]
	GameState.attached_magic_effects = [{"uid": 303}, {"uid": 101, "kind": "self"}]
	GameState.strike_grids["10,11"] = 1
	GameState.ascend_strings = [{"x": 10, "y": 11, "text": "1"}]
	GameState.player_say_messages[303] = [{"text": "old"}]
	GameState.player_say_messages[101] = [{"text": "self"}]
	var next_map_uid: int = 24 << 35
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(303, next_map_uid, {
		"type": 2, "speed": 100, "direction": 5, "x": 30, "y": 31,
	}))
	if GameState.player_map_id != 25 or GameState.get_creature(303).is_empty():
		_fail("foreign stale-map action changed the local world")
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, next_map_uid, {
		"type": 2, "speed": 100, "direction": 6, "x": 30, "y": 31,
	}))
	if GameState.player_map_uid != next_map_uid or GameState.player_map_id != 24 or GameState.player_x != 30 or GameState.player_y != 31 or GameState.player_direction != 6:
		_fail("local different-map action did not switch and continue: %s %s %s" % [GameState.player_map_id, GameState.player_x, GameState.player_y])
		return false
	if not GameState.creatures.is_empty() or not GameState.ground_items.is_empty() or not GameState.firewalls.is_empty() or not GameState.magic_effects.is_empty() or GameState.attached_magic_effects.size() != 1 or GameState.attached_magic_effects[0].get("uid", 0) != 101 or not GameState.strike_grids.is_empty() or not GameState.ascend_strings.is_empty() or GameState.player_say_messages.keys() != [101]:
		_fail("map transition retained old-world transient state")
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	if renderer.world_resource.map_id != 24 or renderer.map_width <= 0 or AudioService.current_bgm_id != renderer.world_resource.bgm_id:
		_fail("map transition did not reload map resources and BGM")
		return false
	# Resource data is synchronous, but visible texture preload/overlay completion
	# is asynchronous. Later input tests must not run through the loading modal.
	var deadline := Time.get_ticks_msec() + 5000
	while main.get_node("MapLoadingOverlay").visible and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if main.get_node("MapLoadingOverlay").visible:
		_fail("map transition did not finish visible preload before input tests")
		return false
	return true


func _test_world_displacement(main: Control, resources: RefCounted) -> bool:
	GameState.player_uid = 101
	GameState.player_map_uid = 202
	GameState.player_x = 3
	GameState.player_y = 4
	GameState.magic_effects.clear()
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 6, "speed": 100, "direction": 5, "x": 3, "y": 4, "aimX": 20, "aimY": 21,
	}))
	if GameState.player_x != 20 or GameState.player_y != 21 or GameState.player_action_type != 6:
		_fail("space move did not jump immediately to aim grid")
		return false
	var stale_uid: int = (4 << 59) | (224 << 35) | 605
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(stale_uid, 24 << 35, {
		"type": 6, "speed": 100, "direction": 5, "x": 20, "y": 21, "aimX": 30, "aimY": 31,
	}))
	if GameState.player_x != 20 or GameState.player_y != 21:
		_fail("foreign stale-map world action changed current player position")
		return false
	if GameState.magic_effects.is_empty() or GameState.magic_effects.back().get("magicID", 0) != resources.magic_id("瞬息移动") or GameState.magic_effects.back().get("source", "") != "space_move" or GameState.magic_effects.back().get("uid", 0) != 101:
		_fail("space move did not create original teleport effect")
		return false
	var remote_uid: int = (5 << 59) | 606
	GameState.update_creature(remote_uid, {
		"uid": remote_uid, "type": 2, "gender": 0, "job": 0,
		"x": 6, "y": 7, "direction": 3, "action_type": 2,
	})
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(remote_uid, 202, {
		"type": 5, "speed": 100, "direction": 3, "x": 6, "y": 7, "aimX": 8, "aimY": 7,
	}))
	var remote: Dictionary = GameState.get_creature(remote_uid)
	if remote.get("x", 0) != 8 or remote.get("y", 0) != 7 or remote.get("action_step", 0) != 2:
		_fail("push move did not retain its two-grid Hero movement state: %s" % remote)
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 3, "speed": 100, "direction": 3, "x": 20, "y": 21, "aimX": 22, "aimY": 21,
	}))
	if GameState.player_x != 22 or GameState.player_y != 21 or GameState.player_action_step != 2:
		_fail("local ACTION_MOVE did not retain its two-grid Hero movement state")
		return false
	GameState.player_x = 20
	GameState.player_y = 21
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(101, 202, {
		"type": 14, "speed": 100, "direction": 0, "x": 20, "y": 22,
	}))
	if GameState.player_x != 20 or GameState.player_y != 21 or GameState.player_direction != 5:
		_fail("server-normalized local ACTION_MINE moved the hero into the mine target or lost its derived facing: pos=%s,%s direction=%s" % [GameState.player_x, GameState.player_y, GameState.player_direction])
		return false
	main.call("_on_server_message", NetworkClient.SM_ACTION, _sm_action(remote_uid, 202, {
		"type": 14, "speed": 100, "direction": 0, "x": 8, "y": 8,
	}))
	remote = GameState.get_creature(remote_uid)
	if remote.get("x", 0) != 8 or remote.get("y", 0) != 7 or remote.get("direction", 0) != 5:
		_fail("server-normalized remote ACTION_MINE moved the hero into the mine target or lost its derived facing: %s" % remote)
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	var pushed: Vector2 = renderer.call("_action_draw_grid", 8, 7, 6, 7, 5, Time.get_ticks_msec() - 1000, 100)
	if not is_equal_approx(pushed.x, 8.0):
		_fail("push move rendering did not interpolate to aim grid")
		return false
	if renderer.call("_hero_motion", 3, 0, {}, 1) != PackedInt32Array([21, 6]) or renderer.call("_hero_motion", 3, 0, {}, 2) != PackedInt32Array([22, 6]):
		_fail("Hero movement did not select C++ walk/run graphics from its step count")
		return false
	if renderer.call("_hero_motion", 14) != PackedInt32Array([10, 6]) or not is_equal_approx(float(main.call("_action_duration", 14, 100, 2)), 0.9):
		_fail("mine action did not use C++ two-handed swing and attack-mode timing")
		return false
	main.call("_set_player_action", 2)
	main.set("_player_action_timer", -1.0)
	GameState.remove_creature(remote_uid)
	main.call("_cancel_movement")
	return true


func _sm_action(uid: int, map_uid: int, action: Dictionary) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(43)
	payload.encode_u64(0, uid)
	payload.encode_u64(8, map_uid)
	var encoded_action := Protocol.encode_action_node(action)
	for index in range(encoded_action.size()):
		payload[16 + index] = encoded_action[index]
	return payload


func _sm_corecord(uid: int, map_uid: int, action: Dictionary, union_data: PackedByteArray) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(48)
	payload.encode_u64(0, uid)
	payload.encode_u64(8, map_uid)
	var action_data := Protocol.encode_action_node(action)
	for index in action_data.size():
		payload[16 + index] = action_data[index]
	for index in mini(5, union_data.size()):
		payload[43 + index] = union_data[index]
	return payload


func _map_message(uid: int, map_uid: int, size: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(size)
	payload.encode_u64(0, uid)
	payload.encode_u64(8, map_uid)
	return payload


func _test_path_decomposition() -> bool:
	var pathfinder: RefCounted = WorldPathfinderScript.new()
	var open_goals: Array[Vector2i] = [Vector2i(4, 0)]
	var open_path: Array[Vector2i] = pathfinder.find_path(Vector2i(0, 0), open_goals, _test_open_walkable, {}, 50000, 2)
	if open_path != [Vector2i(2, 0), Vector2i(4, 0)]:
		_fail("off-horse pathfinder did not prefer the original two-grid run hops: %s" % [open_path])
		return false
	var odd_goals: Array[Vector2i] = [Vector2i(5, 0)]
	var odd_path: Array[Vector2i] = pathfinder.find_path(Vector2i(0, 0), odd_goals, _test_open_odd_walkable, {}, 50000, 2)
	if odd_path != [Vector2i(2, 0), Vector2i(4, 0), Vector2i(5, 0)]:
		_fail("odd straight path inserted a slow walk between run hops: %s" % [odd_path])
		return false
	var diagonal_goals: Array[Vector2i] = [Vector2i(4, 4)]
	var diagonal_path: Array[Vector2i] = pathfinder.find_path(Vector2i(0, 0), diagonal_goals, _test_open_diagonal_walkable, {}, 50000, 2)
	if diagonal_path != [Vector2i(2, 2), Vector2i(4, 4)]:
		_fail("off-horse pathfinder did not prefer diagonal two-grid run hops: %s" % [diagonal_path])
		return false
	var sloped_targets: Array[Vector2i] = [
		Vector2i(5, 3), Vector2i(3, 5), Vector2i(-3, 5), Vector2i(-5, 3),
		Vector2i(-5, -3), Vector2i(-3, -5), Vector2i(3, -5), Vector2i(5, -3),
	]
	for sloped_target in sloped_targets:
		var min_x := mini(0, sloped_target.x)
		var max_x := maxi(0, sloped_target.x)
		var min_y := mini(0, sloped_target.y)
		var max_y := maxi(0, sloped_target.y)
		var sloped_goals: Array[Vector2i] = [sloped_target]
		var sloped_path: Array[Vector2i] = pathfinder.find_path(Vector2i.ZERO, sloped_goals, func(x: int, y: int): return x >= min_x and x <= max_x and y >= min_y and y <= max_y, {}, 50000, 2)
		var sloped_previous := Vector2i.ZERO
		var sloped_direction := Vector2i.ZERO
		var sloped_turns := 0
		for point in sloped_path:
			if point.x < min_x or point.x > max_x or point.y < min_y or point.y > max_y:
				_fail("open sloped path overshot an axis and folded back: target=%s path=%s" % [sloped_target, sloped_path])
				return false
			var next_direction := Vector2i(signi(point.x - sloped_previous.x), signi(point.y - sloped_previous.y))
			if sloped_direction != Vector2i.ZERO and next_direction != sloped_direction:
				sloped_turns += 1
			sloped_direction = next_direction
			sloped_previous = point
		if sloped_path.is_empty() or sloped_path.back() != sloped_target or sloped_turns > 1:
			_fail("open sloped path did not retain the C++ turn-smoothed route: target=%s path=%s turns=%d" % [sloped_target, sloped_path, sloped_turns])
			return false
	var short_goals: Array[Vector2i] = [Vector2i(2, 0)]
	var blocked_path: Array[Vector2i] = pathfinder.find_path(Vector2i(0, 0), short_goals, _test_blocked_middle_walkable, {}, 50000, 2)
	if not blocked_path.is_empty():
		_fail("two-grid run skipped a blocked intermediate grid: %s" % [blocked_path])
		return false
	var occupied_path: Array[Vector2i] = pathfinder.find_path(Vector2i(0, 0), short_goals, _test_open_line_walkable, {Vector2i(1, 0): true}, 50000, 2)
	if not occupied_path.is_empty():
		_fail("two-grid run skipped an occupied intermediate grid: %s" % [occupied_path])
		return false
	var goals: Array[Vector2i] = [Vector2i(4, 2)]
	var path: Array[Vector2i] = pathfinder.find_path(Vector2i(0, 2), goals, _test_walkable, {}, 50000, 2)
	if path.is_empty() or path.back() != goals[0]:
		_fail("pathfinder did not reach destination: %s" % path)
		return false
	var previous := Vector2i(0, 2)
	for point in path:
		var step := maxi(absi(point.x - previous.x), absi(point.y - previous.y))
		if step < 1 or step > 2:
			_fail("path contains a movement outside the original off-horse step range: %s" % path)
			return false
		var direction := Vector2i(signi(point.x - previous.x), signi(point.y - previous.y))
		for distance in range(1, step + 1):
			var crossed := previous + direction * distance
			if not _test_walkable(crossed.x, crossed.y):
				_fail("path skipped a blocked intermediate grid: %s" % path)
				return false
		previous = point
	return true


func _test_open_walkable(x: int, y: int) -> bool:
	return y == 0 and x >= 0 and x <= 4


func _test_open_odd_walkable(x: int, y: int) -> bool:
	return y == 0 and x >= 0 and x <= 5


func _test_open_diagonal_walkable(x: int, y: int) -> bool:
	return x == y and x >= 0 and x <= 4


func _test_open_line_walkable(x: int, y: int) -> bool:
	return y == 0 and x >= 0 and x <= 2


func _test_blocked_middle_walkable(x: int, y: int) -> bool:
	return _test_open_line_walkable(x, y) and x != 1


func _test_walkable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x > 4 or y > 4:
		return false
	return not (x == 2 and y in [1, 2, 3])


func _test_chase_retry(main: Control) -> bool:
	GameState.player_x = 0
	GameState.player_y = 0
	GameState.update_creature(404, {"uid": 404, "x": 5, "y": 5, "type": 1})
	main.set("_next_strike", true)
	main.call("_start_chase", 404)
	main.call("_process_movement", 1.0)
	if main.get("_chase_target_uid") != 404 or not main.get("_next_strike"):
		_fail("blocked chase did not retain target/next strike")
		return false
	GameState.update_creature(404, {"uid": 404, "x": 1, "y": 0, "type": 1})
	main.call("_process_movement", 1.0)
	if main.get("_chase_target_uid") != 404 or main.get("_next_strike") or GameState.player_action_type != 7 or float(main.get("_player_action_timer")) < 0.89:
		_fail("adjacent chase did not attack and consume next strike")
		return false
	main.call("_process_player_action", 1.0)
	if GameState.player_action_type != 2:
		_fail("local attack did not return to stand")
		return false
	main.call("_cancel_movement")
	return true


func _test_exact_frame_input(main: Control) -> bool:
	GameState.player_uid = 101
	GameState.player_x = 0
	GameState.player_y = 0
	GameState.grabbed_item = {"itemID": 1, "seqID": 2, "count": 1}
	GameState.update_creature(707, {"uid": 707, "x": 5, "y": 5, "type": 1, "action_type": 2})
	var renderer: Control = main.get_node("WorldRenderer")
	renderer._actor_target_rects = {
		707: {"rect": Rect2(90, 90, 20, 20), "map_y": 5},
		808: {"rect": Rect2(95, 90, 20, 20), "map_y": 6},
	}
	renderer._mouse_focus_uid = 707
	if renderer.focus_uid_at_screen(Vector2(100, 100)) != 707:
		_fail("overlapping actors did not retain the C++ sticky mouse focus")
		return false
	if renderer.focus_uid_at_screen(Vector2(112, 100)) != 808:
		_fail("mouse focus did not switch after leaving the retained target box")
		return false
	renderer._actor_target_rects.erase(808)
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.position = Vector2(100, 100)
	left_click.pressed = true
	main.call("_handle_mouse_click", left_click)
	if main.get("_chase_target_uid") != 707 or main.get("_attack_focus_uid") != 707 or GameState.grabbed_item.is_empty():
		_fail("exact-frame monster click did not outrank grabbed-item drop")
		return false
	main.call("_cancel_movement")
	var retained_path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	main.set("_move_path", retained_path)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.position = Vector2(100, 100)
	right_click.pressed = true
	main.call("_handle_mouse_click", right_click)
	var path_after_right_click: Array[Vector2i] = main.get("_move_path")
	if main.get("_attack_focus_uid") != 0 or main.get("_follow_focus_uid") != 707 \
			or not path_after_right_click.is_empty() or main.get("_ground_input").button != MOUSE_BUTTON_RIGHT:
		_fail("right-click focused creature did not keep focus while replacing the old route: attack=%s follow=%s path=%s" % [main.get("_attack_focus_uid"), main.get("_follow_focus_uid"), main.get("_move_path")])
		return false
	main.call("_cancel_movement")
	if main.get("_follow_focus_uid") != 707:
		_fail("generic movement cancellation erased persistent follow focus")
		return false
	GameState.update_creature(909, {"uid": 909, "x": 4, "y": 4, "type": 3, "action_type": 2})
	renderer._actor_target_rects = {909: {"rect": Rect2(90, 90, 20, 20), "map_y": 4}}
	renderer._mouse_focus_uid = 909
	var npc_retained_path: Array[Vector2i] = [Vector2i(1, 0)]
	main.set("_move_path", npc_retained_path)
	left_click.position = Vector2(100, 100)
	main.call("_handle_mouse_click", left_click)
	var path_after_npc_click: Array[Vector2i] = main.get("_move_path")
	if path_after_npc_click.size() != 1 or path_after_npc_click[0] != Vector2i(1, 0):
		_fail("left-click NPC event changed the existing action path")
		return false
	main.call("_cancel_movement")
	GameState.remove_creature(909)
	if renderer.focus_color(1) != Color8(0xFF, 0x86, 0x00) or renderer.focus_color(2) != Color8(0x92, 0xC6, 0x20) or renderer.focus_color(3) != Color8(0x00, 0xC6, 0xF0) or renderer.focus_color(4) != Color8(0xD0, 0x2C, 0x70):
		_fail("focus channel colors do not match C++")
		return false
	renderer._actor_target_rects.clear()
	GameState.grabbed_item = {"itemID": 1, "seqID": 2, "count": 3}
	left_click.position = Vector2(300, 200)
	main.call("_handle_mouse_click", left_click)
	if GameState.grabbed_item.get("count", 0) != 3:
		_fail("drop request optimistically cleared the grabbed item before server acknowledgement")
		return false
	main.call("_on_server_message", NetworkClient.SM_REMOVEITEM, _remove_item_payload(1, 2, 1))
	if GameState.grabbed_item.get("count", 0) != 2:
		_fail("partial SM_REMOVEITEM did not decrement the grabbed item")
		return false
	main.call("_on_server_message", NetworkClient.SM_REMOVEITEM, _remove_item_payload(1, 2, 2))
	if not GameState.grabbed_item.is_empty():
		_fail("final SM_REMOVEITEM did not clear the grabbed item")
		return false
	GameState.grabbed_item = {}
	GameState.creatures.erase(707)
	return true


func _remove_item_payload(item_id: int, seq_id: int, count: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(10)
	payload.encode_u32(0, item_id)
	payload.encode_u32(4, seq_id)
	payload.encode_u16(8, count)
	return payload


func _test_mining(main: Control, resources: RefCounted) -> bool:
	var mine_weapon := 0
	for item_id_value in resources.item_attributes:
		if resources.item_can_mine(int(item_id_value)):
			mine_weapon = int(item_id_value)
			break
	if mine_weapon == 0:
		_fail("mine-capable weapon metadata unavailable")
		return false
	GameState.wear = {3: {"itemID": mine_weapon}}
	GameState.grabbed_item = {}
	GameState.ground_items.clear()
	var renderer: Control = main.get_node("WorldRenderer")
	renderer._actor_target_rects.clear()
	GameState.view_x = 0.0
	GameState.view_y = 0.0
	var click_position := Vector2(96, 32)
	var mine_grid: Vector2i = renderer.grid_from_screen(int(click_position.x), int(click_position.y))
	var encoded_mine := Protocol.encode_action_node({"type": 14, "speed": 100, "x": mine_grid.x, "y": mine_grid.y})
	var decoded_mine := Protocol.decode_action_node(encoded_mine)
	if int(decoded_mine.get("type", 0)) != 14 or int(decoded_mine.get("x", -1)) != mine_grid.x or int(decoded_mine.get("y", -1)) != mine_grid.y:
		_fail("ACTION_MINE target is not encoded in ActionNode x/y")
		return false
	GameState.player_x = mine_grid.x - 1
	GameState.player_y = mine_grid.y
	main.set("_player_action_timer", -1.0)
	main.set("_move_step_timer", 0.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = click_position
	click.pressed = true
	main.call("_handle_mouse_click", click)
	if main.get("_mine_target") != mine_grid or GameState.player_action_type != 14 or float(main.get("_player_action_timer")) < 0.89:
		_fail("mine click did not enter repeating ACTION_MINE at the target grid")
		return false
	main.call("_process_player_action", 1.0)
	main.call("_process_movement", 0.01)
	if GameState.player_action_type != 14 or float(main.get("_player_action_timer")) < 0.89:
		_fail("mine action did not repeat after attack-mode timing")
		return false
	var same_grid_click := InputEventMouseButton.new()
	same_grid_click.button_index = MOUSE_BUTTON_RIGHT
	same_grid_click.position = Vector2(GameState.player_x * 48 + 1, GameState.player_y * 32 + 1)
	same_grid_click.pressed = true
	main.call("_handle_mouse_click", same_grid_click)
	if main.get("_mine_target") != mine_grid:
		_fail("right-clicking the current motion endpoint cancelled the original no-op mining action")
		return false
	main.call("_cancel_movement")
	if main.get("_mine_target") != Vector2i(-1, -1):
		_fail("new operation did not cancel mining")
		return false
	return true


func _test_pickup_action(main: Control, resources: RefCounted) -> bool:
	GameState.player_action_type = 2
	main.call("_begin_pickup_action")
	if GameState.player_action_type != 8 or float(main.get("_pickup_action_timer")) <= 0.0:
		_fail("pickup did not enter delayed action state")
		return false
	var pickup_motion: PackedInt32Array = main.get_node("WorldRenderer").call("_hero_motion", 8)
	if pickup_motion != PackedInt32Array([8, 2]):
		_fail("pickup did not use C++ cut/stand combined timing")
		return false
	var renderer: Control = main.get_node("WorldRenderer")
	if renderer.call("_hero_motion", 7) != PackedInt32Array([9, 6]):
		_fail("physical attack does not use the C++ one-handed vertical swing")
		return false
	var sky_sword_id: int = resources.magic_id("翔空剑法")
	var flame_sword_id: int = resources.magic_id("烈火剑法")
	var lotus_sword_id: int = resources.magic_id("莲月剑法")
	var half_moon_id: int = resources.magic_id("半月弯刀")
	var wheel_id: int = resources.magic_id("十方斩")
	var attack_magic_ids := [
		flame_sword_id, sky_sword_id, lotus_sword_id, half_moon_id, wheel_id,
		resources.magic_id("攻杀剑术"), resources.magic_id("刺杀剑术"),
	]
	if attack_magic_ids.has(0):
		_fail("attack magic name metadata incomplete")
		return false
	for attack_magic_id in attack_magic_ids:
		var attack_meta: PackedInt32Array = resources.magic_layout(attack_magic_id, 2)
		if attack_meta.is_empty() or attack_meta[2] <= 0 or attack_meta[5] != 2:
			_fail("motion-synced attack metadata mismatch: id=%d meta=%s" % [attack_magic_id, attack_meta])
			return false
	if renderer.call("_hero_motion", 7, sky_sword_id, {}) != PackedInt32Array([17, 10]):
		_fail("sky sword attack does not use C++ random swing motion")
		return false
	if renderer.call("_hero_motion", 7, half_moon_id, {}) != PackedInt32Array([11, 6]):
		_fail("half moon attack does not use C++ one-handed horizontal swing")
		return false
	if renderer.call("_hero_motion", 7, wheel_id, {}) != PackedInt32Array([16, 10]):
		_fail("wheel attack does not use C++ whirlwind motion")
		return false
	var double_hand_weapon := 0
	for item_id_value in resources.item_attributes:
		if resources.item_attribute(item_id_value).get("double_hand", false):
			double_hand_weapon = int(item_id_value)
			break
	if double_hand_weapon == 0:
		_fail("item meta v3 did not export any double-handed weapon")
		return false
	var double_hand_desp := {"wear": {3: {"itemID": double_hand_weapon}}}
	if renderer.call("_hero_motion", 7, 0, double_hand_desp) != PackedInt32Array([10, 6]) or renderer.call("_hero_motion", 7, half_moon_id, double_hand_desp) != PackedInt32Array([12, 6]):
		_fail("double-handed weapon did not select C++ vertical/horizontal swing motions")
		return false
	if not is_equal_approx(float(main.call("_action_duration", 7, 100, 2, sky_sword_id)), 1.3) or not is_equal_approx(float(main.call("_action_duration", 7, 100, 2, wheel_id)), 0.9666667):
		_fail("special attack action timing mismatch")
		return false
	var now := Time.get_ticks_msec()
	var flame_effect: Dictionary = renderer.call("_attack_motion_effect_state", flame_sword_id, 3, now - 100)
	if flame_effect.is_empty() or not flame_effect.visible or flame_effect.frame != 1 or flame_effect.direction != (2 if flame_effect.meta[6] > 1 else 0):
		_fail("ordinary sword effect did not sync to the attack motion: %s" % flame_effect)
		return false
	var wheel_lag: Dictionary = renderer.call("_attack_motion_effect_state", wheel_id, 3, now)
	var wheel_visible: Dictionary = renderer.call("_attack_motion_effect_state", wheel_id, 3, now - 200)
	if wheel_lag.is_empty() or wheel_lag.visible or wheel_visible.is_empty() or not wheel_visible.visible or wheel_visible.frame != 0:
		_fail("wheel sword effect did not preserve the C++ three-frame lag: early=%s visible=%s" % [wheel_lag, wheel_visible])
		return false
	if not renderer.call("_attack_motion_effect_state", flame_sword_id, 3, now - 600).is_empty():
		_fail("motion-synced sword effect outlived its six-frame attack")
		return false
	if not is_equal_approx(float(main.call("_action_duration", 7, 250, 2, flame_sword_id)), 0.9):
		_fail("ordinary sword action incorrectly inherited network speed")
		return false
	if renderer.call("_motion_frame", 8, 2, now, 100) != 0 or renderer.call("_motion_frame", 8, 2, now - 1000, 100) != 1:
		_fail("transient motion does not start at frame zero and clamp at the last frame")
		return false
	var move_start: Vector2 = renderer.call("_action_draw_grid", 5, 0, 0, 0, 3, now, 100)
	var move_end: Vector2 = renderer.call("_action_draw_grid", 5, 0, 0, 0, 3, now - 1000, 100)
	if move_start.x > 0.2 or not is_equal_approx(move_end.x, 5.0):
		_fail("move rendering does not interpolate from action origin to destination")
		return false
	main.call("_process_pickup_action", 0.21)
	if GameState.player_action_type != 2 or float(main.get("_pickup_action_timer")) >= 0.0:
		_fail("pickup action did not finish and return to stand")
		return false
	return true


func _start_input_payload(uid: int, title: String, commit_tag: String, show: bool) -> PackedByteArray:
	var payload := PackedByteArray([1])
	var uid_offset := payload.size()
	payload.resize(uid_offset + 8)
	payload.encode_u64(uid_offset, uid)
	_append_cereal_string(payload, title)
	_append_cereal_string(payload, commit_tag)
	payload.append(1 if show else 0)
	payload.append(0)
	return payload


func _append_cereal_string(payload: PackedByteArray, value: String) -> void:
	var encoded := value.to_utf8_buffer()
	var size_offset := payload.size()
	payload.resize(size_offset + 8)
	payload.encode_u64(size_offset, encoded.size())
	payload.append_array(encoded)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
