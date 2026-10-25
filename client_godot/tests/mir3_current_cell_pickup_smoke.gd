extends Node

class PickupMain:
	extends "res://scripts/game/main.gd"
	var pickup_requests := 0

	func _request_pickup() -> void:
		pickup_requests += 1

var failures: Array[String] = []


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.player_health_initialized = true
	GameState.player_hp = 100
	GameState.player_hp_max = 100
	GameState.player_action_type = 2
	GameState.ground_items.clear()
	GameState.creatures.clear()
	GameState.grabbed_item = {}
	var main := load("res://scenes/game/main.tscn").instantiate() as Control
	main.set_script(PickupMain)
	add_child(main)
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	renderer.set_process(false)
	GameState.view_x = 0.0
	GameState.view_y = 0.0
	var point := Vector2(10 * 48 + 10, 10 * 32 + 10)
	renderer.set("_actor_target_rects", {101: {"rect": Rect2(point - Vector2(10, 20), Vector2(30, 40)), "map_y": 10}})
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	main.call("_handle_mouse_click", click)
	_expect(main.get("pickup_requests") == 1, "idle current-cell click requests pickup without cached items even through hero hitbox")
	_expect(main.get("_move_path").is_empty() and GameState.player_action_type == 2, "current-cell pickup request does not add a path or restart an animation")
	_expect(main.get("_ground_input").button == MOUSE_BUTTON_LEFT, "current-cell click retains held input for later redirection")
	_expect(not main.get("_ground_input").pending, "current-cell click does not leave a duplicate immediate pickup request")
	main.call("_release_ground_input")
	main.set("_move_step_timer", 0.4)
	main.call("_handle_mouse_click", click)
	_expect(main.get("pickup_requests") == 1, "in-flight movement cannot prematurely pick up at its logical endpoint")
	main.call("_release_ground_input")
	main.set("_move_step_timer", 0.0)
	main.set("_player_action_timer", 0.5)
	main.call("_handle_mouse_click", click)
	_expect(main.get("pickup_requests") == 1, "active attack or spell animation blocks current-cell pickup")
	main.call("_release_ground_input")
	main.set("_player_action_timer", -1.0)
	GameState.grabbed_item = {"itemID": 1, "seqID": 1, "count": 1}
	main.call("_handle_mouse_click", click)
	_expect(main.get("pickup_requests") == 1, "dragged-item drop retains priority over current-cell pickup")
	GameState.grabbed_item = {}
	click.button_index = MOUSE_BUTTON_RIGHT
	main.call("_handle_mouse_click", click)
	_expect(main.get("pickup_requests") == 1, "right current-cell click never requests pickup")
	main.call("_release_ground_input")
	if failures.is_empty():
		print("MIR3 CURRENT CELL PICKUP PASS: self-hitbox routing, no cache dependency, action readiness, drop priority, held-state preservation")
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
