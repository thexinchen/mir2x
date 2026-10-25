extends Node

var failures: Array[String] = []

func _ready() -> void:
	NetworkClient.disconnect_from_server()
	GameState.player_uid = 101
	GameState.player_x = 10
	GameState.player_y = 10
	GameState.creatures.clear()
	GameState.magic_effects.clear()
	var main: Control = load("res://scenes/game/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var renderer: Control = main.get_node("WorldRenderer")
	# Zero land flags: these targets are deliberately not walkable.
	renderer.world_resource.width = 30
	renderer.world_resource.height = 30
	renderer.world_resource.land.resize(30 * 30)
	renderer.world_resource.land.fill(0)
	var firewall: int = main.get("_resources").magic_id("火墙")
	var cases := [[Vector2i(4, 1), 3], [Vector2i(6, 2), 4], [Vector2i(2, 5), 4], [Vector2i(2, 6), 5], [Vector2i(-4, 1), 7], [Vector2i(-6, -2), 8], [Vector2i(2, -6), 1], [Vector2i(6, -2), 2], [Vector2i(-2, 6), 5], [Vector2i(-2, 5), 6]]
	for walkable in [false, true]:
		renderer.world_resource.land.fill(0x80 if walkable else 0)
		for sample in cases:
			GameState.player_action_type = 2
			GameState.player_direction = 1
			GameState.magic_cast_times.clear()
			var target: Vector2i = Vector2i(10, 10) + sample[0]
			_expect(renderer.can_walk(target.x, target.y) == walkable, "terrain fixture")
			main.call("_cast_magic", firewall, target)
			var effect: Dictionary = GameState.magic_effects.back()
			_expect(GameState.player_direction == sample[1] and int(effect.get("direction", 0)) == sample[1] and Vector2i(effect.aimX, effect.aimY) == target, "tile sector %s expected %d: %s" % [sample[0], sample[1], effect])
	GameState.player_action_type = 3
	GameState.player_action_speed = 100
	GameState.player_action_started_ms = Time.get_ticks_msec()
	main.call("_send_spell_action", 9, firewall, Vector2i(14, 11), 0)
	_expect(main.get("_pending_spell_action").get("direction_override", 0) == 3, "ground request captures sector before movement brake")
	GameState.player_x = 11
	GameState.player_direction = 5
	main.call("_release_pending_spell")
	_expect(GameState.player_direction == 3, "ground queue preserves captured sector after endpoint changes")
	if failures.is_empty(): print("MIR3 GROUND DIRECTION PASS: tile sectors/boundaries, terrain-independent turn, preserved queue direction")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
