extends "res://tests/game_runtime_smoke.gd"


# Reuse the existing local test-account login; verify readiness rather than
# inventory/gold fixtures that can change during normal play.
func _verify() -> void:
	if GameState.player_name.is_empty() or GameState.player_name.contains("�"):
		_fail("invalid online character name", 20)
		return
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and _main.get_node("MapLoadingOverlay").visible:
		await get_tree().process_frame
	var renderer := _main.get_node("WorldRenderer")
	if _main.get_node("MapLoadingOverlay").visible or renderer.world_resource.width <= 0:
		_fail("map loading did not complete", 21)
		return
	if not NetworkClient.is_connected_to_server() or GameState.player_hp_max <= 0:
		_fail("initial server state missing or connection lost", 22)
		return
	if GameState.player_x < 0 or GameState.player_x >= renderer.world_resource.width or GameState.player_y < 0 or GameState.player_y >= renderer.world_resource.height:
		_fail("online coordinates outside decoded map; check UID layout", 23)
		return
	var output := OS.get_environment("MIR2X_ONLINE_MAP_SCREENSHOT")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(output)
	print("ONLINE MAP LOADING PASS: name=%s map=%d size=%dx%d hp=%d/%d overlay=hidden connected=true" % [GameState.player_name, GameState.player_map_id, renderer.world_resource.width, renderer.world_resource.height, GameState.player_hp, GameState.player_hp_max])
	NetworkClient.disconnect_from_server()
	get_tree().quit(0)
