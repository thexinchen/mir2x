extends Node

const Movement = preload("res://scripts/game/mir3_movement.gd")
const Pathfinder = preload("res://scripts/game/world_pathfinder.gd")
var failures: Array[String] = []
var walls := {}


func _ready() -> void:
	var input := Movement.new()
	input.press(MOUSE_BUTTON_LEFT, Vector2i(12, 5), false)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("move") == Vector2i(6, 5), "single left step")
	input.advance(0.3, Vector2i(12, 5), false, true, false)
	_expect(not input.pending, "300 ms boundary must not repeat")
	input.advance(0.001, Vector2i(12, 5), false, true, false)
	_expect(input.pending, "held left repeats after 300 ms")
	input.release()
	_expect(not input.pending and input.button == 0, "release clears requests")
	input.press(MOUSE_BUTTON_RIGHT, Vector2i(6, 5), false)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("turn") == 3, "near right turns east")
	input.release()
	input.press(MOUSE_BUTTON_RIGHT, Vector2i(12, 5), false)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("move") == Vector2i(7, 5), "far right runs two tiles")
	input.target = Vector2i(6, 5)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("move") == Vector2i(7, 5), "active right run keeps its mode near cursor")
	input.target = Vector2i(12, 5)
	walls[Vector2i(6, 5)] = true
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).has("path"), "run checks intermediate tile")
	input.release()
	input.press(MOUSE_BUTTON_LEFT, Vector2i(12, 5), false)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("move") == Vector2i(6, 4), "walk sidesteps counterclockwise first")
	walls.clear()
	_expect(input.decide(Vector2i(5, 5), _walkable, {Vector2i(6, 5): true}).has("turn"), "actor collision does not sidestep")
	input.advance(1.0, Vector2i(12, 5), false, false, false)
	_expect(not input.pending, "hovered UI suppresses pending repeat")
	input.release()
	input.press(MOUSE_BUTTON_LEFT, Vector2i(12, 5), true)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("move") == Vector2i(7, 5), "Ctrl left runs")
	_expect(Movement.direction(Vector2i(5, 5), Vector2i(10, 6)) == 3, "direction lower strict bound")
	_expect(Movement.direction(Vector2i(5, 5), Vector2i(10, 4)) == 2, "direction upper inclusive bound")
	walls[Vector2i(6, 5)] = true
	var path: Array[Vector2i] = Pathfinder.new().find_mir3_path(Vector2i(5, 5), Vector2i(12, 5), _walkable, {})
	_expect(not path.is_empty() and path.back() == Vector2i(12, 5), "weighted path reaches goal")
	var previous := Vector2i(5, 5)
	for point in path:
		var distance := maxi(absi(point.x - previous.x), absi(point.y - previous.y))
		var offset := Vector2i(signi(point.x - previous.x), signi(point.y - previous.y))
		_expect(distance <= 2, "path hop at most two cells")
		for n in range(1, distance + 1):
			var crossed := previous + offset * n
			_expect(_walkable(crossed.x, crossed.y), "path hop cannot cross blocked tile")
		previous = point
	# 67849C only accepts the five neighbors in the requested forward half.
	for facing in range(8):
		walls.clear()
		for turn in range(-2, 3):
			walls[Vector2i(5, 5) + Movement.DIRECTIONS[posmod(facing + turn, 8)]] = true
		input.release()
		input.press(MOUSE_BUTTON_RIGHT, Vector2i(5, 5) + Movement.DIRECTIONS[facing] * 5, false)
		_expect(input.decide(Vector2i(5, 5), _walkable, {}).is_empty(), "rear exit must not pass five-neighbor entry check")
		var edge: Vector2i = Vector2i(5, 5) + Movement.DIRECTIONS[posmod(facing + 2, 8)]
		walls.erase(edge)
		_expect(Movement.can_approach(Vector2i(5, 5), facing, _walkable, {}), "90-degree boundary counts as forward entry")
	walls.clear()
	var finder := Pathfinder.new()
	var bounds := Rect2i(0, 0, 30, 30)
	var blocked_goal := Vector2i(12, 5)
	walls[blocked_goal] = true
	_expect(finder.resolve_mir3_goal(blocked_goal, _walkable, {}, bounds) == Vector2i(12, 4), "blocked goal chooses north first")
	path = finder.find_mir3_path(Vector2i(5, 5), blocked_goal, _walkable, {}, 50000, bounds)
	_expect(not path.is_empty() and path.back() == Vector2i(12, 4), "weighted fallback reaches adjusted blocked goal")
	var occupied := {Vector2i(12, 4): true}
	_expect(finder.resolve_mir3_goal(blocked_goal, _walkable, occupied, bounds) == Vector2i(13, 4), "occupied north candidate tries northeast next")
	for offset in Movement.DIRECTIONS:
		walls[blocked_goal + offset] = true
	_expect(finder.find_mir3_path(Vector2i(5, 5), blocked_goal, _walkable, {}, 50000, bounds).is_empty(), "blocked goal adjustment never expands beyond radius one")
	walls.clear()
	walls[Vector2i.ZERO] = true
	_expect(finder.resolve_mir3_goal(Vector2i.ZERO, _walkable, {}, bounds) == Vector2i(1, 0), "boundary adjustment skips outside-map candidates")
	_expect(finder.find_mir3_path(Vector2i(5, 5), Vector2i(-1, 0), _walkable, {}, 50000, bounds).is_empty(), "outside-map target is rejected before adjustment")
	walls.clear()
	for offset in Movement.DIRECTIONS:
		walls[Vector2i(5, 5) + offset] = true
	input.release()
	input.press(MOUSE_BUTTON_LEFT, Vector2i(12, 5), true, true)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("attack") == 3, "Shift overrides Ctrl run and blocked-ground pathfinding")
	input.advance(0.301, Vector2i(5, 5), false, true, false, true)
	_expect(input.decide(Vector2i(5, 5), _walkable, {}).get("attack") == 5, "held Shift can attack on the current cell")
	input.advance(0.1, Vector2i(12, 5), false, true, false, false)
	_expect(not input.force_attack, "releasing Shift updates held left intent")
	input.release()
	_expect(not input.force_attack, "mouse release clears forced attack")
	if failures.is_empty():
		print("MIR3 MOVEMENT RULES PASS: click/hold/release/turn/run/occupancy/weighted path/five-neighbor gate/bounded goal adjustment")
	get_tree().quit(0 if failures.is_empty() else 1)


func _walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < 30 and y < 30 and not walls.has(Vector2i(x, y))


func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
