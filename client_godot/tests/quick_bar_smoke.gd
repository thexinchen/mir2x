extends Node

const ActorResourceScript = preload("res://scripts/game/actor_resource.gd")
const QuickBarScript = preload("res://scripts/game/quick_bar.gd")


func _ready() -> void:
	var resources: RefCounted = ActorResourceScript.new()
	if not resources.configure_default():
		_fail("world resources unavailable")
		return
	var potion_id := _find_type(resources, "恢复药水")
	var scroll_id := _find_type(resources, "传送卷轴")
	var non_belt_id := _find_non_belt(resources)
	if potion_id == 0 or scroll_id == 0 or non_belt_id == 0:
		_fail("required item types unavailable: %d %d %d" % [potion_id, scroll_id, non_belt_id])
		return

	GameState.inventory.clear()
	GameState.grabbed_item = {}
	GameState.belt.resize(6)
	GameState.belt.fill(null)
	GameState.belt[0] = {"itemID": potion_id, "seqID": 101, "count": 3}
	var expanded_main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(expanded_main)
	await get_tree().process_frame
	var expanded_control: Control = expanded_main.get_node("ControlPanel")
	var expanded_quick_bar: Control = expanded_main.get_node("%QuickBar")
	expanded_control.call("_on_expand_pressed")
	expanded_main.call("_on_control_panel_quick_bar_toggled")
	if not expanded_quick_bar.visible or expanded_quick_bar.position != Vector2(0, 131):
		_fail("expanded HUD first-open quick-bar placement mismatch: %s" % expanded_quick_bar.position)
		return
	if OS.has_environment("MIR2X_QUICK_BAR_EXPANDED_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_QUICK_BAR_EXPANDED_SCREENSHOT"))
	expanded_main.queue_free()
	await get_tree().process_frame

	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var quick_bar: Control = main.get_node("%QuickBar")
	quick_bar.show()
	GameState.state_changed.emit()
	await get_tree().process_frame

	if quick_bar.position != Vector2(0, 400):
		_fail("original quick-bar placement mismatch: %s" % quick_bar.position)
		return
	if quick_bar.size != Vector2(280, 48):
		_fail("native quick-bar size mismatch: %s" % quick_bar.size)
		return
	var close_button := quick_bar.get_node("CloseButton") as TextureButton
	if close_button.position != Vector2(263, 32) or close_button.size != Vector2(16, 16):
		_fail("original quick-bar close geometry mismatch")
		return
	var slot0 := quick_bar.get_node("Slots/Slot0")
	if not slot0.has_node("Icon") or not slot0.has_node("Count") or slot0.get_node("Count").text != "3":
		_fail("belt icon/count did not render")
		return
	var count_label := slot0.get_node("Count") as Label
	if count_label.position != Vector2.ZERO or count_label.size != Vector2(35, 36) or count_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT:
		_fail("belt count did not preserve the original x=35 right edge: position=%s size=%s" % [count_label.position, count_label.size])
		return
	if not count_label.get_theme_font("font").resource_path.ends_with("/01_Yahei.ttf") or count_label.get_theme_font_size("font_size") != 10 or count_label.get_theme_color("font_color") != Color.WHITE:
		_fail("belt count did not preserve original font-01/10 white text")
		return
	var bar_resources: RefCounted = quick_bar.get("_resources")
	var expected_icon: Dictionary = bar_resources.frame("item", bar_resources.item_package_gfx_id(potion_id) | 0x01000000)
	if expected_icon.is_empty() or slot0.get_node("Icon").texture != expected_icon.texture:
		_fail("quick-bar item did not use original package sprite bank")
		return
	quick_bar.call("_set_hovered_slot", 0)
	if not quick_bar.get_node("Hover").visible or quick_bar.get_node("Hover").position != Vector2(17, 6):
		_fail("original slot hover overlay mismatch")
		return
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	NetworkClient.set("_item_use_pending_token", 707)
	if quick_bar.call("activate_slot", 0, MOUSE_BUTTON_RIGHT) != QuickBarScript.ACTION_NONE or AudioService.last_seff_id != AudioService.INVALID_SEFF_ID:
		_fail("pending item use replayed quick-slot sound or accepted another use")
		return
	NetworkClient.set("_item_use_pending_token", 0)
	if quick_bar.call("activate_slot", 0, MOUSE_BUTTON_RIGHT) != QuickBarScript.ACTION_CONSUME or AudioService.last_seff_id != resources.item_sound_effect(potion_id):
		_fail("right-click consume route mismatch")
		return
	var key_actions: Array = []
	quick_bar.slot_action_requested.connect(func(action: int, slot: int): key_actions.append([action, slot]))
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_1
	key_event.unicode = 49
	key_event.pressed = true
	main.call("_unhandled_input", key_event)
	if key_actions.is_empty() or key_actions.back() != [QuickBarScript.ACTION_CONSUME, 0]:
		_fail("number-key consume route mismatch: %s" % [key_actions])
		return
	key_actions.clear()
	var runtime := main.call("_ensure_extra_panel", "res://scenes/game/panels/runtime_config.tscn") as Control
	runtime.show()
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	if key_actions != [[QuickBarScript.ACTION_CONSUME, 0]]:
		_fail("runtime config swallowed the HUD-first quick-slot key: %s" % [key_actions])
		return
	key_actions.clear()
	var shifted_key_event := InputEventKey.new()
	shifted_key_event.keycode = KEY_1
	shifted_key_event.unicode = 33
	shifted_key_event.shift_pressed = true
	shifted_key_event.pressed = true
	Input.parse_input_event(shifted_key_event)
	await get_tree().process_frame
	if key_actions != [[QuickBarScript.ACTION_CONSUME, 0]]:
		_fail("Shift changed the original getKeyChar(false) quick-slot route: %s" % [key_actions])
		return
	var command := main.get_node("ControlPanel").get_node("%Command") as LineEdit
	command.release_focus()
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_ENTER
	enter_event.pressed = true
	Input.parse_input_event(enter_event)
	await get_tree().process_frame
	if not command.has_focus():
		_fail("runtime config swallowed the HUD-first command focus key")
		return
	command.release_focus()
	runtime.hide()
	key_actions.clear()
	var active_magic_id := _find_active_magic(resources)
	if active_magic_id == 0:
		_fail("active magic shortcut fixture unavailable")
		return
	GameState.learned_magic = [{"magicID": active_magic_id, "exp": 0}]
	GameState.magic_keys = {}
	GameState.state_changed.emit()
	await get_tree().process_frame
	var skill_panel := main.get_node("SkillPanel") as Control
	skill_panel.show()
	skill_panel.call("_show_magic", active_magic_id)
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	if key_actions != [[QuickBarScript.ACTION_CONSUME, 0]] or GameState.magic_keys.has(active_magic_id):
		_fail("skill panel overrode the HUD-first 1-6 quick-slot key: actions=%s keys=%s" % [key_actions, GameState.magic_keys])
		return
	key_actions.clear()
	var seven_event := InputEventKey.new()
	seven_event.keycode = KEY_7
	seven_event.unicode = 55
	seven_event.pressed = true
	Input.parse_input_event(seven_event)
	await get_tree().process_frame
	if not key_actions.is_empty() or GameState.magic_keys.get(active_magic_id, 0) != 55:
		_fail("skill panel did not retain the HUD-unclaimed numeric binding: actions=%s keys=%s" % [key_actions, GameState.magic_keys])
		return
	GameState.magic_keys = {}
	var shifted_seven_event := InputEventKey.new()
	shifted_seven_event.keycode = KEY_7
	shifted_seven_event.unicode = 38
	shifted_seven_event.shift_pressed = true
	shifted_seven_event.pressed = true
	Input.parse_input_event(shifted_seven_event)
	await get_tree().process_frame
	if not key_actions.is_empty() or GameState.magic_keys.get(active_magic_id, 0) != 55:
		_fail("Shift changed the original getKeyChar(false) skill binding: actions=%s keys=%s" % [key_actions, GameState.magic_keys])
		return
	GameState.magic_keys = {}
	quick_bar.hide()
	Input.parse_input_event(key_event)
	await get_tree().process_frame
	if not key_actions.is_empty() or GameState.magic_keys.get(active_magic_id, 0) != 49:
		_fail("hidden quick bar still blocked the original skill key binding: actions=%s keys=%s" % [key_actions, GameState.magic_keys])
		return
	quick_bar.show()
	skill_panel.call("_hide_magic", active_magic_id)
	skill_panel.hide()
	GameState.magic_keys = {}
	GameState.player_action_type = 13
	main.call("_unhandled_input", key_event)
	if key_actions != [[QuickBarScript.ACTION_CONSUME, 0]]:
		_fail("dead-player gate swallowed the original quick-slot key: %s" % [key_actions])
		return
	GameState.player_action_type = 2
	(main.get("_player_forced_action_queue") as Array).append({"kind": "move"})
	key_actions.clear()
	main.call("_unhandled_input", key_event)
	if key_actions != [[QuickBarScript.ACTION_CONSUME, 0]]:
		_fail("forced-action gate swallowed the original quick-slot key: %s" % [key_actions])
		return
	(main.get("_player_forced_action_queue") as Array).clear()
	GameState.grabbed_item = {"itemID": scroll_id, "seqID": 202, "count": 1}
	if quick_bar.call("activate_slot", 1, MOUSE_BUTTON_LEFT) != QuickBarScript.ACTION_EQUIP:
		_fail("beltable grabbed item did not request equip")
		return
	GameState.grabbed_item = {"itemID": non_belt_id, "seqID": 303, "count": 1}
	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	if quick_bar.call("activate_slot", 1, MOUSE_BUTTON_LEFT) != QuickBarScript.ACTION_RETURN or not GameState.grabbed_item.is_empty() or GameState.inventory.is_empty() or AudioService.last_seff_id != resources.item_sound_effect(non_belt_id):
		_fail("non-belt item did not return to inventory")
		return
	GameState.grabbed_item = {}
	if quick_bar.call("activate_slot", 0, MOUSE_BUTTON_LEFT) != QuickBarScript.ACTION_GRAB:
		_fail("occupied belt slot did not request grab")
		return

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20, 10)
	quick_bar.call("_on_bar_input", press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(70, 0)
	motion.relative = Vector2(50, -10)
	quick_bar.call("_on_bar_input", motion)
	if quick_bar.position != Vector2(50, 390):
		_fail("quick-bar drag mismatch: %s" % quick_bar.position)
		return
	motion.position = Vector2(2000, 2000)
	motion.relative = Vector2(2000, 2000)
	quick_bar.call("_on_bar_input", motion)
	if quick_bar.position != Vector2(520, 552):
		_fail("quick-bar drag was not clamped: %s" % quick_bar.position)
		return

	AudioService.last_seff_id = AudioService.INVALID_SEFF_ID
	close_button.pressed.emit()
	if quick_bar.visible or AudioService.last_seff_id != AudioService.UI_CLICK_SEFF_ID:
		_fail("quick-bar close did not hide with original button feedback")
		return
	quick_bar.show()

	GameState.grabbed_item = {"itemID": potion_id, "seqID": 404, "count": 1}
	GameState.state_changed.emit()
	await get_tree().process_frame
	var grabbed_icon: TextureRect = main.get_node("GrabbedItemIcon")
	if not grabbed_icon.visible or grabbed_icon.texture == null or grabbed_icon.size.x <= 0 or grabbed_icon.size.y <= 0:
		_fail("grabbed item cursor icon did not get a drawable texture/size")
		return
	var main_resources: RefCounted = main.get("_resources")
	var expected_grabbed_icon: Dictionary = main_resources.frame("item", main_resources.item_package_gfx_id(potion_id) | 0x01000000)
	if expected_grabbed_icon.is_empty() or grabbed_icon.texture != expected_grabbed_icon.texture or grabbed_icon.size != expected_grabbed_icon.texture.get_size():
		_fail("grabbed item cursor did not use the original native package sprite")
		return
	quick_bar.position = Vector2(0, 400)
	if OS.has_environment("MIR2X_QUICK_BAR_SCREENSHOT"):
		quick_bar.call("_set_hovered_slot", 0)
		main.set_process(false)
		main.get_node("GrabbedItemIcon").position = Vector2(382, 232)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_QUICK_BAR_SCREENSHOT"))
	print("QUICK BAR PASS: six slots, icons, count, equip/grab/consume, non-belt return, drag and cursor feedback")
	get_tree().quit()


func _find_type(resources: RefCounted, wanted: String) -> int:
	for item_id in resources.item_types:
		if resources.item_type(item_id) == wanted:
			return item_id
	return 0


func _find_non_belt(resources: RefCounted) -> int:
	for item_id in resources.item_types:
		if resources.item_type(item_id) not in ["恢复药水", "传送卷轴"] and not resources.item_icon(item_id).is_empty():
			return item_id
	return 0


func _find_active_magic(resources: RefCounted) -> int:
	for magic_value in resources.skill_meta.keys():
		var magic_id := int(magic_value)
		var layout: PackedInt32Array = resources.skill_layout(magic_id)
		if layout.size() >= 5 and (layout[4] & 1) == 0:
			return magic_id
	return 0


func _fail(message: String) -> void:
	push_error("QUICK_BAR_SMOKE %s" % message)
	get_tree().quit(1)
