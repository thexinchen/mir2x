extends Node

class QueryMain extends "res://scripts/game/main.gd":
	var queries: Array[int] = []
	func _send_actor_inspection_queries(uid: int) -> void:
		queries.append(uid)

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = (5 << 59) | 1
	GameState.player_map_uid = 24 << 35
	GameState.player_map_id = 24
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_hp = 100
	GameState.player_health_initialized = true
	GameState.wear = {4: {"itemID": 2, "seqID": 999, "count": 1}}
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(QueryMain)
	add_child(main)
	main.set_process(false)
	main.get_node("MapLoadingOverlay").hide()
	if not main.has_method("_request_actor_inspection"):
		_fail("inspection request missing")
		return
	var a := (5 << 59) | 606
	var b := (5 << 59) | 707
	for uid in [a, b]:
		GameState.update_creature(uid, {"uid": uid, "type": 2, "name": "查看目标%d" % (uid & 1023), "gender": true, "action_type": 2, "x": 12, "y": 10,
			"desp": {"wear": {}, "hair": 1, "hairColor": 0}})
	main.set("_last_actor_inspection_ms", 0)
	if main.call("_request_actor_inspection", a, 1499) or not main.call("_request_actor_inspection", a, 1500) or main.call("_request_actor_inspection", b, 2999):
		_fail("inspection global 1500ms inclusive gate differs from original")
		return
	main.call("_refresh_player_inspection", b, true)
	if not main.get("_extra_panel_nodes").is_empty() and main.get("_extra_panel_nodes").has(main.PLAYER_INSPECTION_PANEL_PATH):
		_fail("unrelated response opened inspection")
		return
	main.call("_refresh_player_inspection", a, true)
	var panel: Control = main.get("_extra_panel_nodes")[main.PLAYER_INSPECTION_PANEL_PATH]
	if not panel.visible or panel.get("inspected_uid") != a or panel.get_node("Name").text != "查看目标606":
		_fail("matching response did not show selected player")
		return
	if panel.get_node("EquipmentSlots").get_child_count() != 11 or panel.get_node("EquipmentSlots/Slot4") is BaseButton:
		_fail("inspection slots are missing or allow equipment mutations")
		return
	if panel.get_node("CharacterLayers").get("_appearance").gender != true or GameState.wear[4].seqID != 999:
		_fail("inspection appearance mutated local equipment or used local gender")
		return
	panel.hide()
	main.call("_refresh_player_inspection", a, true)
	if panel.visible:
		_fail("late response reopened a closed panel")
		return
	if not main.call("_request_actor_inspection", b, 3000):
		_fail("global inspection gate did not reopen at boundary")
		return
	panel.show() # An older view can remain visible while the next reply is pending.
	main.call("_refresh_player_inspection", b, false)
	if panel.get("inspected_uid") != a or not main.get("_inspection_waiting"):
		_fail("name-only refresh substituted cached equipment for pending reply")
		return
	main.call("_refresh_player_inspection", a, true)
	if panel.get("inspected_uid") != a or not main.get("_inspection_waiting"):
		_fail("previous player response replaced pending selection")
		return
	main.call("_refresh_player_inspection", b, true)
	GameState.remove_creature(b)
	if panel.visible or main.get("_inspection_uid") != 0:
		_fail("removed actor retained inspection")
		return
	GameState.update_creature(a, {"action_type": 13})
	if main.call("_request_actor_inspection", a, 4500):
		_fail("dead target accepted inspection request")
		return
	if main.get("queries") != [a, b]:
		_fail("query dispatch count differs from consumed live requests")
		return
	GameState.update_creature(a, {"action_type": 2})
	var renderer: Control = main.get_node("WorldRenderer")
	var point := Vector2(120, 120)
	renderer.set("_actor_target_rects", {a: {"rect": Rect2(point - Vector2(10, 10), Vector2(20, 20)), "map_y": 10}})
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = point
	click.ctrl_pressed = true
	click.pressed = true
	main.set("_last_actor_inspection_ms", Time.get_ticks_msec())
	main.call("_handle_mouse_click", click)
	if not main.get("_ground_input").pending or main.get("queries") != [a, b]:
		_fail("rejected initial Ctrl request did not fall through to ground input")
		return
	main.call("_release_ground_input")
	main.call("_request_actor_inspection", a, 6000)
	await get_tree().create_timer(2.1).timeout
	main.call("_refresh_player_inspection", a, true)
	if panel.visible or main.get("_inspection_waiting") or main.get("_inspection_uid") != 0:
		_fail("expired response revived inspection")
		return
	main.call("_request_actor_inspection", a, 9000)
	main.call("_refresh_player_inspection", a, true)
	main.call("_on_action_connection_changed", false, "test disconnect")
	if panel.visible or main.get("_inspection_uid") != 0:
		_fail("disconnect retained remote inspection")
		return
	main.call("_request_actor_inspection", a, 12000)
	main.call("_refresh_player_inspection", a, true)
	main.call("_switch_player_map", 1 << 35, {"x": 10, "y": 10})
	if panel.visible or main.get("_inspection_uid") != 0:
		_fail("map switch retained remote inspection")
		return
	print("PLAYER INSPECTION PASS: global inclusive gate, matching responses, readonly slots, isolated appearance, close/stale replies, actor removal/death, cooldown ground fallback, expiry, disconnect and map reset")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error("INSPECTION: " + message)
	get_tree().quit(1)
