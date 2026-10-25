extends Node

var failures: Array[String] = []


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 0
	GameState.creatures.clear()
	var main := load("res://scenes/game/main.tscn").instantiate() as Control
	add_child(main)
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	renderer.set_process(false)
	_expect(main.call("_request_npc_dialogue", 101, 0), "first NPC click can dispatch at application startup")
	_expect(not main.call("_request_npc_dialogue", 101, 1499), "NPC request is blocked before 1500 ms")
	_expect(not main.call("_request_npc_dialogue", 102, 1500), "1500 ms boundary is strict and shared across NPCs")
	_expect(main.get("_last_npc_dialogue_ms") == 0, "rejected clicks do not extend the cooldown")
	_expect(main.call("_request_npc_dialogue", 102, 1501), "next NPC click dispatches after the strict boundary")
	main.set("_last_npc_dialogue_ms", -1501)
	var npc_uid := 123
	GameState.creatures[npc_uid] = {"uid": npc_uid, "type": 3, "x": 2, "y": 3, "action_type": 2}
	renderer.set("_actor_target_rects", {npc_uid: {"rect": Rect2(100, 100, 40, 40), "map_y": 3}})
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(120, 120)
	main.get("_ground_input").press(MOUSE_BUTTON_RIGHT, Vector2i(10, 10), false)
	main.set("_move_step_timer", 0.4)
	main.call("_handle_mouse_click", click)
	var first: int = main.get("_last_npc_dialogue_ms")
	_expect(first >= 0, "actual NPC click enters the dialogue request gate")
	main.call("_handle_mouse_click", click)
	_expect(main.get("_last_npc_dialogue_ms") == first, "rapid actual NPC clicks do not redispatch")
	_expect(main.get("_ground_input").button == 0, "NPC click does not start held ground-repeat input")
	_expect(is_equal_approx(main.get("_move_step_timer"), 0.4), "NPC click preserves already committed movement cooldown")
	_expect(main.get("_move_path").is_empty(), "NPC dialogue does not start a ground path")
	_expect(not NetworkClient.is_connected_to_server(), "offline NPC click does not initiate a connection")
	GameState.creatures.clear()
	if failures.is_empty():
		print("MIR3 NPC INTERACTION PASS: strict 1500 ms boundary, shared throttle, actual click routing, no held-repeat movement")
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
