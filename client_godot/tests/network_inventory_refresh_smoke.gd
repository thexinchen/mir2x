extends "res://tests/network_item_use_receipt_smoke.gd"

const CONFIG := "user://network_inventory_refresh_smoke.cfg"
const LOCATION_PROBE := """import json, sqlite3, sys
from pathlib import Path
with sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=ro', uri=True) as connection:
    row = connection.execute('select fld_map, fld_mapx, fld_mapy from tbl_char where fld_name = ?', (sys.argv[2],)).fetchone()
    print(json.dumps(row))
"""
var origin := Vector2i.ZERO
var origin_map := 0
var grid: Control
var created := 0
var probe_log := ""

func _ready() -> void:
	OS.set_environment("MIR3_PROTECTION_CONFIG", CONFIG)
	if FileAccess.file_exists(CONFIG): DirAccess.remove_absolute(CONFIG)
	super._ready()

func _run() -> void:
	if not OS.has_environment("MIR3_TEST_SERVER_DB"):
		_fail("set MIR3_TEST_SERVER_DB to the local test server database for read-only endpoint checks")
		return
	if not await _wait(func(): return _inventory_received and _belt_received and GameState.player_health_initialized and not _main.get_node("MapLoadingOverlay").visible, "inventory refresh world"): return
	if GameState.player_hp <= 0:
		_submit_command("@revive")
		if not await _wait(func(): return GameState.player_hp > 0, "live inventory walker"): return
	origin = Vector2i(GameState.player_x, GameState.player_y)
	origin_map = GameState.player_map_uid
	var destination := origin
	var occupied: Dictionary = _main.call("_ground_occupied")
	var renderer: Control = _main.get_node("WorldRenderer")
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var candidate: Vector2i = origin + offset
		if not occupied.has(candidate) and renderer.can_walk(candidate.x, candidate.y):
			destination = candidate
			break
	if destination == origin:
		_fail("no free adjacent walking destination")
		return
	var panel: Control = _main.get_node("InventoryPanel")
	panel.show()
	grid = panel.get_node("ItemGrid")
	if grid.get_child_count() == 0:
		_fail("fixture requires a visible inventory item")
		return
	var before_items: Array = GameState.inventory.duplicate(true)
	var first_id := grid.get_child(0).get_instance_id()
	get_tree().node_added.connect(_count_created)
	for step in 4:
		var target: Vector2i = destination if step % 2 == 0 else origin
		_main.call("_start_move_to", target)
		if not await _wait(func(): return Vector2i(GameState.player_x, GameState.player_y) == target and _main.get("_move_step_timer") <= 0.0 and _main.get("_move_path").is_empty(), "inventory open walk%d" % step): return
		if not await _wait(func(): return _server_position(target), "server database walking endpoint%d" % step): return
		if GameState.inventory != before_items or grid.get_child(0).get_instance_id() != first_id or created != 0:
			_fail("walking recreated unchanged inventory controls or changed items")
			return
	var baseline := _count()
	NetworkClient.send_make_item(ITEM_ID)
	if not await _wait(func(): return _count() == baseline + 1 and created > 0, "live inventory item update"): return
	var request_id: int = NetworkClient.get("_next_response_id")
	if panel.call("_use_inventory_item", _item()) != OK:
		_fail("actual inventory use failed")
		return
	if not await _wait(func(): return _wire_receipts.has(request_id) and _count() == baseline, "inventory consumption receipt and refresh"): return
	if _wire_receipts[request_id] != NetworkClient.SM_OK:
		_fail("inventory use was rejected")
		return
	if OS.has_environment("MIR3_INVENTORY_REFRESH_SCREENSHOT"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR3_INVENTORY_REFRESH_SCREENSHOT"))
	print("NETWORK INVENTORY REFRESH PASS: four real walks with read-only server DB endpoint checks, unchanged controls during movement, live inventory update and GUI item-use SM_OK, original potion quantity/location restored")
	_finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _count_created(node: Node) -> void:
	if node.get_parent() == grid: created += 1

func _server_position(target: Vector2i) -> bool:
	var output: Array = []
	var result := OS.execute("python3", PackedStringArray(["-c", LOCATION_PROBE, OS.get_environment("MIR3_TEST_SERVER_DB"), GameState.player_name]), output, true)
	if result != 0:
		_fail("read-only server location probe failed: %s" % output)
		return false
	var observed: Variant = JSON.parse_string("".join(output))
	var detail := "name=%s observed=%s expected=%s" % [GameState.player_name, observed, [GameState.player_map_id, target.x, target.y]]
	if detail != probe_log:
		probe_log = detail
		print("INVENTORY WALK DB CHECK: " + detail)
	# Godot JSON numbers are floats; Array equality preserves element types.
	return observed is Array and observed.size() == 3 and observed[0] == float(GameState.player_map_id) and observed[1] == float(target.x) and observed[2] == float(target.y)

func _fail(message: String) -> void:
	if _finished: return
	_finished = true
	push_error("NETWORK INVENTORY REFRESH: " + message)
	if origin_map > 0 and NetworkClient.is_connected_to_server() and Vector2i(GameState.player_x, GameState.player_y) != origin:
		_main.call("_cancel_movement")
		NetworkClient.send_request_space_move(origin_map, origin.x, origin.y)
		for _attempt in 200:
			if Vector2i(GameState.player_x, GameState.player_y) == origin: break
			await get_tree().create_timer(0.01).timeout
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
