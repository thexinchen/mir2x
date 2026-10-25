extends "res://tests/network_current_cell_pickup_smoke.gd"

var _pressed_ms := -1
var _held_verified := false

func _send_tab_pickup() -> void:
	GameState.ground_items.erase("%d,%d" % [GameState.player_x, GameState.player_y])
	# The initial click is deliberately not ready. Only a later held poll can
	# send pickup, after the idle retry delay and strict 300 ms hold threshold.
	_main.set("_move_step_timer", 0.15)
	var point := Vector2(
		GameState.player_x * GameState.GRID_XP + GameState.GRID_XP / 2 - int(GameState.view_x),
		GameState.player_y * GameState.GRID_YP + GameState.GRID_YP / 2 - int(GameState.view_y))
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	_pressed_ms = Time.get_ticks_msec()
	Input.parse_input_event(click)

func _process(delta: float) -> void:
	if not _held_verified and _stage == Stage.WAIT_PICKED and int(_inventory_item().get("count", 0)) == ITEM_COUNT:
		var elapsed := Time.get_ticks_msec() - _pressed_ms
		if _pressed_ms < 0 or elapsed <= 300:
			_fail("held pickup bypassed initial readiness or hold delay", 12)
			return
		_main.call("_release_ground_input")
		_held_verified = true
		print("NETWORK HELD PICKUP PASS: stale cache, initially busy click, held retry after %d ms, inventory restored" % elapsed)
	super._process(delta)
