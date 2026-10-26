extends Node


func _ready() -> void:
	var main = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(main.size == Vector2(1024, 768))
	assert(main.get_node("InventoryPanel").size == Vector2(434, 542))
	assert(main.get_node("ControlPanel").get_global_rect().end.y == 768)
	var renderer = main.get_node("WorldRenderer")
	renderer.map_width = 1000
	renderer.map_height = 1000
	for viewport_size in [Vector2(1024, 768), Vector2(1920, 1080)]:
		renderer.size = viewport_size
		for camera in [Vector2i(0, 0), Vector2i(1511, 903), Vector2i(1570, 947)]:
			var bounds: Rect2i = renderer.visible_grid_rect(camera.x, camera.y)
			var right_bottom := Vector2i(floori((camera.x + viewport_size.x - 1) / 48.0), floori((camera.y + viewport_size.y - 1) / 32.0))
			assert(bounds.has_point(right_bottom), "map drawing misses the viewport edge")
	GameState.center_camera_on_grid(Vector2(100, 100))
	assert(is_equal_approx(100 * 48 - GameState.view_x, 512.0))
	assert(is_equal_approx(100 * 32 - GameState.view_y, GameState.camera_center_y()))
	print("VIEWPORT LAYOUT PASS: 1024x768 layout, native panels, moving camera edge coverage and centering")
	get_tree().quit()
