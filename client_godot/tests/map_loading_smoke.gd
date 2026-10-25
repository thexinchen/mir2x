extends Node

const WorldResourceScript = preload("res://scripts/game/world_resource.gd")

var _progress: Array[int] = []
var _map_names: Array[String] = []


func _ready() -> void:
	var world: RefCounted = WorldResourceScript.new()
	if not world.load_map(24, _record_progress):
		_fail("map resource failed to load: %s" % world.last_error)
		return
	if _progress.is_empty() or _progress.front() != 0 or not _progress.has(40) or _progress.back() != 100:
		_fail("C++ progress milestones missing: %s" % _progress)
		return
	for index in range(1, _progress.size()):
		if _progress[index] < _progress[index - 1]:
			_fail("progress is not monotonic: %s" % _progress)
			return
	for expected in range(40, 101):
		if not _progress.has(expected):
			_fail("C++ integer progress update missing: %d in %s" % [expected, _progress])
			return
	if _map_names[0].is_empty():
		_fail("map name was unavailable at first visible progress")
		return
	GameState.set_player_online({"uid": 1, "name": "loading", "map_uid": 0, "x": 0, "y": 0, "direction": 5})
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var overlay := main.get_node("MapLoadingOverlay") as Control
	var backdrop := overlay.get_node("Backdrop") as ColorRect
	var panel := overlay.get_node("Panel") as Control
	var loading_text := overlay.get_node("Panel/Text") as RichTextLabel
	if not overlay.visible:
		_fail("world scene exposed before SM_STARTGAMESCENE map loading")
		return
	if ProjectSettings.get_setting("display/window/stretch/mode", "disabled") != "canvas_items" \
			or ProjectSettings.get_setting("display/window/stretch/aspect", "ignore") != "keep":
		_fail("800x600 logical viewport does not scale with the window")
		return
	if panel.size != Vector2(358, 260) or overlay.mouse_filter != Control.MOUSE_FILTER_STOP or backdrop.color != Color.BLACK:
		_fail("modal geometry/background/input mismatch: panel=%s background=%s filter=%d" % [panel.size, backdrop.color, overlay.mouse_filter])
		return
	if loading_text.get_theme_font("normal_font").resource_path != "res://assets/font/01_Yahei.ttf" or loading_text.get_theme_font_size("normal_font_size") != 12:
		_fail("map-loading text did not use original font-1/12px replacement: font=%s size=%d" % [loading_text.get_theme_font("normal_font").resource_path, loading_text.get_theme_font_size("normal_font_size")])
		return
	if loading_text.position.y != 84.0 or loading_text.size.y != 136.0 or loading_text.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
		_fail("map-loading text did not center within the original 84..220px content region: position=%s size=%s alignment=%d" % [loading_text.position, loading_text.size, loading_text.vertical_alignment])
		return
	overlay.show()
	main.call("_on_map_load_progress", 40, _map_names[0])
	var text: String = loading_text.text
	if not text.contains("加载地图") or not text.contains("[color=red]") or not text.contains("%40"):
		_fail("modal text/style mismatch: %s" % text)
		return
	if OS.has_environment("MIR2X_MAP_LOADING_SCREENSHOT"):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("MIR2X_MAP_LOADING_SCREENSHOT"))
	if not main.call("_load_world_map", 24):
		_fail("focused map load failed")
		return
	if not overlay.visible or not loading_text.text.contains("%0"):
		_fail("progress presentation did not start from visible 0%%: visible=%s text=%s" % [overlay.visible, loading_text.text])
		return
	var saw_intermediate := false
	var saw_visible_complete := false
	for _index in range(120):
		await get_tree().create_timer(0.02).timeout
		var presented_text: String = loading_text.text
		if overlay.visible and not presented_text.contains("%0") and not presented_text.contains("%100"):
			saw_intermediate = true
		if overlay.visible and presented_text.contains("%100"):
			saw_visible_complete = true
			break
	if not saw_intermediate or not saw_visible_complete:
		_fail("progress did not render intermediate and completed states: intermediate=%s complete=%s text=%s" % [saw_intermediate, saw_visible_complete, loading_text.text])
		return
	if main.get_node("WorldRenderer").world_resource.get("_texture_cache").is_empty():
		_fail("C++-style visible map texture preload did not populate the texture cache")
		return
	await get_tree().create_timer(0.25).timeout
	if overlay.visible:
		_fail("completed map loading overlay did not close after the visible 100%% hold")
		return
	print("MAP LOADING PASS: milestones, modal geometry, replacement font and input blocking")
	get_tree().quit()


func _record_progress(value: int, map_name: String) -> void:
	_progress.append(value)
	_map_names.append(map_name)


func _fail(message: String) -> void:
	push_error("MAP_LOADING_SMOKE %s" % message)
	get_tree().quit(1)
