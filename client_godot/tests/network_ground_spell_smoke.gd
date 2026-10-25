extends "res://tests/network_thrust_smoke.gd"

var observed_fire: Dictionary = {}

func _ready() -> void:
	NetworkClient.connection_changed.connect(func(connected, _message):
		if connected: NetworkClient.login("good", "123456"))
	NetworkClient.message_received.connect(_message)
	NetworkClient.connect_to_server()
	get_tree().create_timer(60.0).timeout.connect(func(): _fail("timeout at " + stage))

func _message(head: int, payload: PackedByteArray) -> void:
	super._message(head, payload)
	if head == NetworkClient.SM_GROUNDFIREWALLLIST:
		var reader := Reader.new(payload)
		var data: Dictionary = reader.read_sd_ground_firewall_list()
		if reader.valid and int(data.get("mapUID", 0)) == GameState.player_map_uid:
			for grid in data.get("firewalls", []):
				if int(grid.get("count", 0)) > 0:
					observed_fire[Vector2i(grid.x, grid.y)] = true

func _run() -> void:
	stage = "prepare wizard ground spell"
	await get_tree().create_timer(3.0).timeout
	original_map = GameState.player_map_uid
	original_position = Vector2i(GameState.player_x, GameState.player_y)
	if GameState.player_hp <= 0 or main.get_node("MapLoadingOverlay").visible:
		_fail("living fixture and loaded map are required")
		return
	if (GameState.player_job & 4) == 0:
		_fail("fixture requires wizard job")
		return
	if GameState.player_level < 24:
		NetworkClient.send_request_add_exp(maxi(0, 1272900 - GameState.player_exp))
		await get_tree().create_timer(0.5).timeout
	if GameState.player_level < 24:
		_fail("could not prepare level24 wizard")
		return
	var resources: RefCounted = main.get("_resources")
	for name in ["火球术", "大火球", "地狱火", "火墙"]:
		var magic: int = resources.magic_id(name)
		if main.call("_has_learned_magic", magic): continue
		var book := 0
		for id in resources.item_names:
			if resources.item_names[id] == name: book = int(id)
		if book == 0:
			_fail("missing spell book: " + name)
			return
		NetworkClient.send_make_item(book)
		await get_tree().create_timer(0.3).timeout
		var item: Dictionary = {}
		for value in GameState.inventory:
			if int(value.get("itemID", 0)) == book: item = value
		if item.is_empty():
			_fail("could not prepare spell book: " + name)
			return
		NetworkClient.send_consume_item(book, int(item.seqID), 1)
		await get_tree().create_timer(0.4).timeout
		if not main.call("_has_learned_magic", magic):
			_fail("server did not confirm spell learning: " + name)
			return
	stage = "prepare empty casting area"
	var renderer: Control = main.get_node("WorldRenderer")
	var occupied: Dictionary = main.call("_ground_occupied")
	var goal := Vector2i(-1, -1)
	for distance in range(6, 13):
		for offset in Move.DIRECTIONS:
			var candidate: Vector2i = original_position + offset * distance
			var clear := true
			for y in range(-2, 3):
				for x in range(-2, 3):
					var point: Vector2i = candidate + Vector2i(x, y)
					if occupied.has(point) or not renderer.can_walk(point.x, point.y): clear = false
			for fire in GameState.firewalls:
				if (Vector2i(fire.x, fire.y) - candidate).length_squared() <= 16: clear = false
			if clear:
				goal = candidate
				break
		if goal.x >= 0: break
	if goal.x < 0 or not await _relocate(original_map, goal):
		_fail("could not prepare clear casting area")
		return
	GameState.player_direction = 3
	var expected := goal + Vector2i.RIGHT
	observed_fire.clear()
	stage = "cast at own tile"
	if not main.call("_cast_magic", resources.magic_id("火墙"), goal):
		_fail("same-cell ground cast was rejected")
		return
	var cross: Array[Vector2i] = [expected, expected + Vector2i.UP, expected + Vector2i.DOWN, expected + Vector2i.LEFT, expected + Vector2i.RIGHT]
	for _i in range(80):
		await get_tree().create_timer(0.05).timeout
		var complete := true
		for point in cross:
			if not observed_fire.has(point): complete = false
		if complete: break
	for point in cross:
		if not observed_fire.has(point):
			_fail("server firewall did not use forward center: expected=%s missing=%s observed=%s" % [expected, point, observed_fire.keys()])
			return
	if observed_fire.has(goal + Vector2i.LEFT):
		_fail("server firewall still centered on the hero tile")
		return
	if not await _restore_position():
		_fail("could not restore original casting position")
		return
	print("NETWORK GROUND SPELL PASS: learned wizard, own-tile input creates authoritative five-cell firewall centered one tile ahead: hero=%s center=%s" % [goal, expected])
	finished = true
	NetworkClient.disconnect_from_server()
	get_tree().quit()

func _fail(message: String) -> void:
	if finished: return
	finished = true
	if main != null and not await _restore_position(): push_error("GROUND SPELL FIXTURE: original position restoration failed")
	push_error("NETWORK GROUND SPELL: " + message)
	NetworkClient.disconnect_from_server()
	get_tree().quit(1)
