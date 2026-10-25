extends Node

const PreviewScript = preload("res://scripts/account/account_character_preview.gd")

var _transition_heads: Array[int] = []


func _ready() -> void:
	var local_map_uid := (1 << 59) | (1 << 35) | 13
	if GameState.call("_map_id_from_uid", local_map_uid) != 1 or GameState.uid_record_id(local_map_uid) != 1:
		_fail("local server UID layout did not decode map 1 from bits 58..35")
		return
	var select := load("res://scenes/account/select_character.tscn").instantiate() as Control
	add_child(select)
	await get_tree().process_frame
	if select.get("_query_complete") or select.get("has_character") or select.get_node("CharacterSprite").visible or select.get_node("InfoPanel").visible or select.get_node("InfoPanel/CharacterInfo").visible:
		_fail("selection screen exposed a fake character before query completion")
		return
	if select.get_node("StartButton").visible or select.get_node("CreateButton").visible or select.get_node("DeleteButton").visible:
		_fail("selection actions were available while the character query was pending")
		return
	if AudioService.current_bgm_id != 0x00040002 or AudioService.current_bgm_path.is_empty():
		_fail("selection BGM mismatch: %08X %s" % [AudioService.current_bgm_id, AudioService.current_bgm_path])
		return
	if not NetworkClient.has_method("pause_message_dispatch") or not NetworkClient.has_method("resume_message_dispatch") or not NetworkClient.has_method("_dispatch_message"):
		_fail("online scene transition cannot preserve coalesced world messages")
		return
	NetworkClient.message_received.connect(_record_transition_message)
	NetworkClient.pause_message_dispatch()
	NetworkClient.call("_dispatch_message", NetworkClient.SM_STARTGAMESCENE, PackedByteArray([1]))
	NetworkClient.call("_dispatch_message", NetworkClient.SM_HEALTH, PackedByteArray([2]))
	if not _transition_heads.is_empty():
		_fail("world messages leaked into the character-selection scene")
		return
	NetworkClient.resume_message_dispatch()
	if _transition_heads != [NetworkClient.SM_STARTGAMESCENE, NetworkClient.SM_HEALTH]:
		_fail("deferred world messages were not replayed once in wire order: %s" % [_transition_heads])
		return
	NetworkClient.resume_message_dispatch()
	if _transition_heads.size() != 2:
		_fail("resuming message dispatch replayed transition messages twice")
		return
	NetworkClient.message_received.disconnect(_record_transition_message)

	select.call("_on_server_message", NetworkClient.SM_QUERYCHARERROR, PackedByteArray([2]))
	if not select.get("_query_complete") or select.get("has_character") or select.get_node("InfoPanel").visible or select.get_node("StartButton").visible or not select.get_node("CreateButton").visible or select.get_node("DeleteButton").visible:
		_fail("confirmed empty account did not expose only character creation")
		return
	select.call("_on_server_message", NetworkClient.SM_ONLINEERROR, PackedByteArray([3]))
	var no_character_entries: Array = select.get_node("Notice").get("_entries")
	if no_character_entries.size() != 1 or String(no_character_entries[0].text) != "先创建角色以运行游戏":
		_fail("no-character online error text diverged from C++: %s" % [no_character_entries])
		return
	if OS.has_environment("MIR2X_ACCOUNT_FLOW_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_ACCOUNT_FLOW_SCREENSHOT"))

	select.call("_on_server_message", NetworkClient.SM_QUERYCHAROK, _character_payload("账号流程测试", 1, 1, 1100))
	if not select.get("has_character") or not select.get_node("StartButton").visible or not select.get_node("CreateButton").visible or not select.get_node("DeleteButton").visible:
		_fail("existing character actions were not restored")
		return
	if "账号流程测试" not in select.get_node("InfoPanel/CharacterInfo").text or not select.get_node("InfoPanel").visible or not select.get_node("CharacterSprite").visible:
		_fail("queried character preview was not applied")
		return
	var info_panel := select.get_node("InfoPanel") as Control
	var character_info := select.get_node("InfoPanel/CharacterInfo") as RichTextLabel
	var info_font := character_info.get_theme_font("normal_font")
	var info_font_size := character_info.get_theme_font_size("normal_font_size")
	var expected_info_width := info_font.get_string_size("角色：账号流程测试", HORIZONTAL_ALIGNMENT_LEFT, -1, info_font_size).x + 30.0
	if info_panel.position != Vector2(105, 200) or info_panel.size.y != 75.0 or not is_equal_approx(info_panel.size.x, expected_info_width) or character_info.position != Vector2(15, 15):
		_fail("dynamic character-info board geometry mismatch: pos=%s size=%s text_pos=%s expected_width=%s" % [info_panel.position, info_panel.size, character_info.position, expected_info_width])
		return
	var expected_line_separation := maxi(0, roundi(15.0 - info_font.get_height(info_font_size)))
	if "[color=#ede2c8]角色：账号流程测试[/color]" not in character_info.text or "[color=#afc4af]等级：1[/color]" not in character_info.text or "[color=#e7e7bd]职业：战士[/color]" not in character_info.text or character_info.get_theme_constant("line_separation") != expected_line_separation:
		_fail("character-info line colors/spacing mismatch: %s" % character_info.text)
		return
	select.set_process(false)
	select.set("_animation_time_ms", 400.0)
	select.set("_character_motion", 0)
	select.call("_update_character_preview")
	var select_preview := select.get_node("CharacterSprite") as Control
	if select_preview.get("_frame_id") != 514 or select_preview.get("_anchor") != Vector2(430, 300) or select_preview.get("_tint") != Color.WHITE:
		_fail("selection preview frame/anchor/tint diverged from C++: %s %s %s" % [select_preview.get("_frame_id"), select_preview.get("_anchor"), select_preview.get("_tint")])
		return
	if PreviewScript.SHADOW_MASK != 0x4000 or PreviewScript.MAGIC_MASK != 0x2000:
		_fail("preview shadow/magic layer masks diverged from C++")
		return
	var select_resources: RefCounted = select.get("_resources")
	if (select_resources.call("frame", "selectchar", 514) as Dictionary).is_empty() or (select_resources.call("frame", "selectchar", 514 | PreviewScript.SHADOW_MASK) as Dictionary).is_empty():
		_fail("selection body/shadow selectchar frames were not decoded")
		return
	select_resources = null
	if not _verify_frame_table():
		return
	select.set("_character_motion", 1)
	select.set("_animation_time_ms", 4000.0)
	select.set("_last_motion_switch_frame", -1)
	select.call("_switch_character_motion")
	if select.get("_character_motion") != 2:
		_fail("deterministic selection motion transition 1 -> 2 was not preserved")
		return
	if OS.has_environment("MIR2X_SELECT_CHARACTER_SCREENSHOT"):
		select.call("_on_server_message", NetworkClient.SM_QUERYCHAROK, _character_payload("亚当", 1, 2, 10000))
		select.set("_character_motion", 0)
		select.set("_animation_time_ms", 400.0)
		select.call("_update_character_preview")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_SELECT_CHARACTER_SCREENSHOT"))
	select.call("_on_server_message", NetworkClient.SM_DELETECHAROK, PackedByteArray())
	if select.get_node("StartButton").visible or not select.get_node("CreateButton").visible or select.get_node("DeleteButton").visible:
		_fail("deleted character did not return to the playable creation state")
		return

	select.queue_free()
	await get_tree().process_frame
	var login := load("res://scenes/account/login.tscn").instantiate() as Control
	add_child(login)
	await get_tree().process_frame
	if AudioService.current_bgm_id != 0x00040007 or AudioService.current_bgm_path.is_empty():
		_fail("login BGM mismatch: %08X %s" % [AudioService.current_bgm_id, AudioService.current_bgm_path])
		return
	if not (AudioService.get_node("BGMPlayer").stream is AudioStreamWAV):
		_fail("original WAV opening music did not use the WAV decoder")
		return
	login.queue_free()
	await get_tree().process_frame
	var create := load("res://scenes/account/create_character.tscn").instantiate() as Control
	add_child(create)
	await get_tree().process_frame
	if AudioService.current_bgm_id != 0x00040001 or AudioService.current_bgm_path.is_empty():
		_fail("character-creation BGM mismatch: %08X %s" % [AudioService.current_bgm_id, AudioService.current_bgm_path])
		return
	create.set_process(false)
	var name_field := create.get_node_or_null("NameField") as Panel
	var name_input := create.get_node_or_null("NameField/NameInput") as LineEdit
	if name_field == null or name_input == null:
		_fail("character-name field did not separate the original 90x15 frame from the native input")
		return
	if name_field.position != Vector2(355, 520) or name_field.size != Vector2(90, 15) or not name_field.clip_contents or name_input.position != Vector2.ZERO or name_input.size.x != 85.0:
		_fail("character-name field diverged from C++ frame/input geometry: field=%s/%s/%s input=%s/%s" % [name_field.position, name_field.size, name_field.clip_contents, name_input.position, name_input.size])
		return
	if name_input.get_theme_font("font").resource_path != "res://assets/font/01_Yahei.ttf" or name_input.get_theme_font_size("font_size") != 12:
		_fail("character-name field did not preserve the replacement font-1/12 input")
		return
	create.set("_animation_time_ms", 0.0)
	create.call("_update_characters")
	var male_preview := create.get_node("MaleSprite") as Control
	var female_preview := create.get_node("FemaleSprite") as Control
	if male_preview.get("_frame_id") != 640 or male_preview.get("_anchor") != Vector2(193, 215) or male_preview.get("_tint") != Color.WHITE:
		_fail("active male creation preview diverged from C++")
		return
	if female_preview.get("_frame_id") != 128 or female_preview.get("_anchor") != Vector2(495, 260) or female_preview.get("_tint") != Color(0.5, 0.5, 0.5, 1.0):
		_fail("inactive warrior-female creation preview diverged from C++")
		return
	create.set("_animation_time_ms", 600.0)
	create.call("_on_wizard_pressed")
	if create.get("selected_job") != 4 or create.get("_animation_time_ms") != 600.0:
		_fail("job selection restarted character animation instead of preserving the C++ absolute frame")
		return
	create.set("selected_job", 4)
	create.set("selected_male", false)
	create.call("_restart_animation")
	create.set("_animation_time_ms", 400.0)
	create.call("_update_characters")
	if female_preview.get("_frame_id") != 2178 or female_preview.get("_anchor") != Vector2(495, 220) or female_preview.get("_tint") != Color.WHITE:
		_fail("active wizard-female creation preview frame/anchor/tint diverged from C++")
		return
	if male_preview.get("_frame_id") != 2688 or male_preview.get("_tint") != Color(0.5, 0.5, 0.5, 1.0):
		_fail("inactive wizard-male creation preview did not stay on tinted frame zero")
		return
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	create.set("_animation_time_ms", 0.0)
	create.set("_last_sound_frame", -1)
	create.call("_play_cycle_sound")
	if AudioService.last_seff_id != 0x00010200:
		_fail("creation cycle job/gender SEFF mismatch: %08X" % AudioService.last_seff_id)
		return
	if OS.has_environment("MIR2X_CREATE_CHARACTER_SCREENSHOT"):
		name_input.text = "亚当"
		name_input.caret_column = name_input.text.length()
		create.set("_animation_time_ms", 400.0)
		create.call("_update_characters")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_CREATE_CHARACTER_SCREENSHOT"))
	AudioService.stop_bgm()
	AudioService.stop_seff()
	for child in AudioService.get_children():
		if child is AudioStreamPlayer:
			child.stream = null
	AudioService.set("_seff_cache", {})
	await get_tree().process_frame
	create.queue_free()
	await get_tree().process_frame
	var transition_select := load("res://scenes/account/select_character.tscn").instantiate() as Control
	get_tree().root.add_child(transition_select)
	await get_tree().process_frame
	if not transition_select.has_method("_switch_to_game_scene"):
		_fail("online transition still relies on an empty SceneTree change frame")
		return
	get_tree().current_scene = transition_select
	GameState.set_player_online({"uid": 1, "name": "transition", "map_uid": 0, "x": 0, "y": 0, "direction": 5})
	NetworkClient.pause_message_dispatch()
	transition_select.call("_switch_to_game_scene")
	var mounted_game := get_tree().current_scene as Control
	if mounted_game == null or mounted_game == transition_select or mounted_game.get_node_or_null("MapLoadingOverlay") == null or not mounted_game.get_node("MapLoadingOverlay").visible:
		_fail("game loading scene was not mounted with its progress overlay in the same frame")
		return
	if not NetworkClient.get("_message_dispatch_paused"):
		_fail("queued map messages resumed before the loading page rendered its first frame")
		return
	await get_tree().process_frame
	if NetworkClient.get("_message_dispatch_paused"):
		_fail("game scene did not resume queued map messages after its first visible frame")
		return
	get_tree().current_scene = self
	mounted_game.queue_free()
	await get_tree().process_frame
	print("ACCOUNT FLOW PASS: account states, original BGM, decoded layered previews, motion cycles, creation SEFF and clean audio shutdown")
	get_tree().quit()


func _verify_frame_table() -> bool:
	var rows: Array[PackedInt32Array] = [
		PackedInt32Array([1, 0, 11, 11, 11, 12, 16]), PackedInt32Array([1, 1, 11, 20, 12, 8, 18]),
		PackedInt32Array([2, 0, 11, 17, 11, 10, 15]), PackedInt32Array([2, 1, 11, 17, 20, 12, 17]),
		PackedInt32Array([4, 0, 11, 18, 11, 9, 17]), PackedInt32Array([4, 1, 11, 12, 11, 11, 15]),
	]
	for row in rows:
		for motion in range(5):
			if PreviewScript.frame_count(row[0], bool(row[1]), motion) != row[motion + 2]:
				_fail("original frame-count table mismatch for job=%d male=%s motion=%d" % [row[0], bool(row[1]), motion])
				return false
	if PreviewScript.select_base_id(4, true, 3) != 2656 or PreviewScript.create_base_id(2, false) != 1152:
		_fail("original selection/creation proguse base-ID formulas diverged")
		return false
	return true


func _character_payload(name: String, gender: int, job: int, experience: int) -> PackedByteArray:
	var encoded := name.to_utf8_buffer()
	var payload := PackedByteArray()
	payload.resize(74)
	payload.encode_u16(0, encoded.size())
	for index in range(mini(encoded.size(), 64)):
		payload[2 + index] = encoded[index]
	payload[68] = gender
	payload[69] = job
	payload.encode_u32(70, experience)
	return payload


func _record_transition_message(head_code: int, _payload: PackedByteArray) -> void:
	_transition_heads.append(head_code)


func _fail(message: String) -> void:
	push_error("ACCOUNT_FLOW_SMOKE %s" % message)
	get_tree().quit(1)
