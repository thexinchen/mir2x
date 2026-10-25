extends Node

const Movement = preload("res://scripts/game/mir3_movement.gd")
class WireMain extends "res://scripts/game/main.gd":
	var actions: Array[Dictionary] = []
	func _send_player_action(payload: PackedByteArray) -> Error:
		actions.append(Protocol.decode_action_node(payload, 16))
		return OK

var main: Control
var renderer: Node
var resources: RefCounted
var rect: Rect2

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_map_uid = 24 << 35
	GameState.player_map_id = 24
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.runtime_config = {49: PackedByteArray([1, 1, 0])}
	main = load("res://scenes/game/main.tscn").instantiate()
	main.set_script(WireMain)
	add_child(main)
	main.set_process(false)
	renderer = main.get_node("WorldRenderer")
	resources = main.get("_resources")
	renderer.world_resource.width = 40
	renderer.world_resource.height = 40
	GameState.update_creature(606, {"uid": 606, "type": 2, "x": 12, "y": 16, "action_type": 2})
	GameState.update_creature(707, {"uid": 707, "type": 2, "x": 14, "y": 11, "action_type": 2})
	rect = Rect2(get_viewport().get_mouse_position() - Vector2(10, 10), Vector2(20, 20))
	renderer.set("_actor_target_rects", {606: {"rect": rect, "map_y": 16}})
	# Keep initial screen-facing west, distinct from the actor-facing result.
	var draw: Vector2 = renderer.call("player_draw_grid")
	GameState.view_x = roundi(draw.x * 48) - int(get_viewport().get_mouse_position().x) - 100
	GameState.view_y = roundi(draw.y * 32) - int(get_viewport().get_mouse_position().y)
	if not _cast("火墙") or not _wire(Vector2i(12, 16), 606, 4):
		_fail("enabled setting without explicit lock did not route ground spell through hovered actor")
		return
	if not _cast("抗拒火环") or not _wire(Vector2i(9, 10), 606, 4):
		_fail("front projection did not precede actor-facing adjustment")
		return
	main.set("_locked_magic_target_uid", 707)
	if not _cast("抗拒火环") or not _wire(Vector2i(9, 10), 707, 4):
		_fail("explicit lock lost projected coordinates or target UID")
		return
	GameState.runtime_config[49] = PackedByteArray([1, 0, 0])
	if not _cast("抗拒火环") or int(main.get("actions").back().aimUID) != 101 or Vector2i(main.get("actions").back().aimX, main.get("actions").back().aimY) != Vector2i(10, 10):
		_fail("disabled setting changed existing self spell routing")
		return
	GameState.runtime_config[49] = PackedByteArray([1, 1, 0])
	main.set("_locked_magic_target_uid", 0)
	main.set("_magic_focus_uid", 0)
	renderer.set("_actor_target_rects", {})
	if not _cast("抗拒火环") or not _wire(Vector2i(11, 10), 0, 3):
		_fail("unowned projection did not use normalized ground sector")
		return
	# Resolution is a snapshot, carried through the existing walking brake.
	renderer.set("_actor_target_rects", {606: {"rect": rect, "map_y": 16}})
	_reset()
	GameState.player_action_type = 3
	GameState.player_action_from_x = 9
	GameState.player_action_from_y = 10
	GameState.player_action_started_ms = Time.get_ticks_msec()
	GameState.player_action_speed = 100
	draw = renderer.call("player_draw_grid")
	GameState.view_x = roundi(draw.x * 48) - int(get_viewport().get_mouse_position().x) - 100
	GameState.view_y = roundi(draw.y * 32) - int(get_viewport().get_mouse_position().y)
	if not main.call("_cast_magic", resources.magic_id("抗拒火环"), Vector2i(15, 10)) or main.get("_pending_spell_action").is_empty():
		_fail("walking cast did not retain pending resolver snapshot")
		return
	GameState.update_creature(606, {"x": 25, "y": 25})
	GameState.view_x += 200
	main.call("_release_pending_spell")
	if not _wire(Vector2i(9, 10), 606, 4):
		_fail("movement braking recomputed projected grid or direction")
		return
	GameState.runtime_config.clear()
	GameState.magic_effects.clear()
	print("MIR3 GENERAL TARGET PASS: enabled/no lock, actor ground aim, front projection before actor direction, explicit lock, disabled self routing, unowned sector and braking snapshot; decoded actual CM_ACTION")
	get_tree().quit()

func _reset() -> void:
	main.call("_process_player_action", 10.0)
	main.set("_last_magic_request_ms", -10000)
	GameState.magic_cast_times.clear()
	GameState.player_action_type = 2
	main.get("actions").clear()

func _cast(name: String) -> bool:
	_reset()
	return main.call("_cast_magic", resources.magic_id(name), Vector2i(15, 10))

func _wire(grid: Vector2i, uid: int, direction: int) -> bool:
	var actions: Array = main.get("actions")
	if actions.is_empty():
		return false
	var action: Dictionary = actions.back()
	return action.type == 9 and action.aimX == grid.x and action.aimY == grid.y and action.aimUID == uid and action.direction == direction

func _fail(message: String) -> void:
	push_error("GENERAL TARGET: " + message + " actions=" + str(main.get("actions")))
	get_tree().quit(1)
