extends "res://tests/network_ground_item_smoke.gd"


func _send_tab_pickup() -> void:
	# The server has acknowledged the drop; simulate a stale item cache before
	# exercising the actual mouse entry rather than using the keyboard shortcut.
	GameState.ground_items.erase("%d,%d" % [GameState.player_x, GameState.player_y])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(
		GameState.player_x * GameState.GRID_XP + GameState.GRID_XP / 2 - int(GameState.view_x),
		GameState.player_y * GameState.GRID_YP + GameState.GRID_YP / 2 - int(GameState.view_y),
	)
	_main.call("_unhandled_input", click)
	print("NETWORK CURRENT CELL PICKUP: actual left click with empty client ground cache")


func _on_timeout() -> void:
	# A missing client cache must not prevent cleanup of the real dropped item.
	if not _finished and _stage == Stage.WAIT_PICKED:
		_begin_cleanup("current-cell mouse pickup timed out with stale client cache")
		return
	super._on_timeout()
