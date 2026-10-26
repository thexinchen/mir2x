extends Node

class ProbeRenderer extends "res://scripts/game/world_renderer.gd":
	var probe: Dictionary = {}
	var probe_alpha := 1.0
	func _draw() -> void:
		_draw_creature(probe, 0, 0, probe_alpha)
	func _motion_frame(_action_type: int, frame_count: int, _started_ms: int, _speed: int) -> int:
		# Pin the actual final corpse texture while comparing rendered pixels.
		return maxi(0, frame_count - 1)


func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var renderer := ProbeRenderer.new()
	renderer.game_state = GameState
	renderer.set_process(false)
	if not renderer.actor_resource.configure_default():
		_fail("actual actor resources unavailable")
		return
	renderer.probe = {"uid": 606, "type": 2, "gender": 0, "x": 2, "y": 4,
		"direction": 5, "action_type": 13, "action_speed": 100, "action_started_ms": 1,
		"desp": {"wear": {3: {"itemID": 826}}, "hair": 1, "hairColor": 0xFFFFFFFF}}
	viewport.add_child(renderer)
	var totals: Array[float] = []
	var baseline_pixels := PackedByteArray()
	for alpha in [1.0, 0.5, 0.25, 0.0, 1.0]:
		renderer.probe_alpha = alpha
		renderer.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		if totals.is_empty(): baseline_pixels = pixels.get_data()
		elif totals.size() == 4 and pixels.get_data() != baseline_pixels:
			_fail("restoring full opacity changed actual sprite pixels")
			return
		var total := 0.0
		for y in range(pixels.get_height()):
			for x in range(pixels.get_width()):
				total += pixels.get_pixel(x, y).a
		totals.append(total)
		var output := OS.get_environment("MIR3_FADE_SCREENSHOT_DIR")
		if not output.is_empty():
			pixels.save_png(output + "/fade-%d.png" % totals.size())
	if totals[0] < 10.0 or totals[1] >= totals[0] * 0.9 or totals[1] <= totals[0] * 0.25 \
			or totals[2] >= totals[1] * 0.9 or totals[3] > 0.01 or absf(totals[4] - totals[0]) > 0.01:
		_fail("actual rendered player did not fade and restore: " + str(totals))
		return
	print("REMOTE PLAYER FADE VISUAL PASS: actual body/weapon/hair/shadow pixels alpha1/.5/.25/0/1 totals=" + str(totals))
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("REMOTE PLAYER FADE VISUAL: " + reason)
	get_tree().quit(1)
