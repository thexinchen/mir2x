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
	var resources: RefCounted = main.get("_resources")
	var fireball: int = resources.magic_id("火球术")
	var revive: int = resources.magic_id("回生术")
	var heal: int = resources.magic_id("治愈术")
	var cases := [[Vector2i(1, 4), 5], [Vector2i(-1, 4), 5], [Vector2i(1, -4), 1], [Vector2i(-1, -4), 1], [Vector2i(4, -1), 3], [Vector2i(4, 1), 4], [Vector2i(-4, -1), 7], [Vector2i(-4, 1), 6], [Vector2i(2, -1), 2], [Vector2i(1, 2), 4], [Vector2i(2, 6), 4], [Vector2i.ZERO, 5]]
	for magic in [fireball, heal, revive]:
		for sample in cases:
			GameState.player_action_type = 2
			GameState.player_direction = 7
			GameState.update_creature(606, {"uid": 606, "type": 2, "x": 10 + sample[0].x, "y": 10 + sample[0].y, "action_type": 13 if magic == revive else 2})
			# Deliberately stale aim coordinates: the selected UID must supply its current grid.
			main.call("_send_spell_action", 9, magic, Vector2i(1, 1), 606)
			var effect: Dictionary = GameState.magic_effects.back()
			_expect(GameState.player_direction == sample[1] and int(effect.get("direction", 0)) == sample[1] and int(effect.get("aimUID", 0)) == 606 and Vector2i(effect.aimX, effect.aimY) == Vector2i(10, 10) + sample[0], "actor spell %d delta %s expected %d: %s" % [magic, sample[0], sample[1], effect])
	# The same offset has different original rules with and without a UID.
	GameState.player_action_type = 2
	main.call("_send_spell_action", 9, fireball, Vector2i(12, 16), 0)
	_expect(GameState.player_direction == 5, "unowned spell keeps sector direction instead of actor near-axis rule")
	GameState.remove_creature(606)
	GameState.player_direction = 7
	main.call("_send_spell_action", 9, fireball, Vector2i(12, 16), 606)
	_expect(GameState.player_direction == 7 and int(GameState.magic_effects.back().get("aimUID", -1)) == 0, "removed actor does not supply a direction")
	if failures.is_empty(): print("MIR3 ACTOR SPELL DIRECTION PASS: axis attraction, asymmetric row rule, short-range diagonals, same-cell down, live/heal/corpse UID, ground-rule separation and stale target")
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
