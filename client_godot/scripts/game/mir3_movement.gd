extends RefCounted

# Reconstructed from Mir3.dat: 65F7B8, 67B398, 67C3DC, 6FEC28.
# Decisions use native mir2x action IDs/projection in main.gd, not Mir3 packets.
const HOLD_DELAY := 0.300
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

var button := 0
var held_seconds := 0.0
var pending := false
var target := Vector2i.ZERO
var running := false
var run_latched := false


func press(which: int, destination: Vector2i, ctrl: bool) -> void:
	if button == 0:
		held_seconds = 0.0
	# Left has priority when both buttons are pressed.
	if button != MOUSE_BUTTON_LEFT:
		button = which
	target = destination
	running = button == MOUSE_BUTTON_RIGHT or ctrl
	pending = true


func release() -> void:
	button = 0
	pending = false
	running = false
	run_latched = false
	held_seconds = 0.0


func advance(delta: float, destination: Vector2i, ctrl: bool, over_world: bool, path_active: bool) -> void:
	if button == 0:
		return
	held_seconds += delta
	if not over_world:
		pending = false
		return
	if not path_active and held_seconds > HOLD_DELAY:
		target = destination
		running = button == MOUSE_BUTTON_RIGHT or ctrl
		pending = true


static func direction(from: Vector2i, to: Vector2i) -> int:
	var dx := signi(to.x - from.x)
	var dy := signi(to.y - from.y)
	if absi(from.y - to.y) > 2 and from.x >= to.x - 1 and from.x <= to.x + 1:
		dx = 0
	if absi(from.x - to.x) > 2 and from.y > to.y - 1 and from.y <= to.y + 1:
		dy = 0
	var index := DIRECTIONS.find(Vector2i(dx, dy))
	return 4 if index < 0 else index


func decide(from: Vector2i, can_walk: Callable, occupied: Dictionary) -> Dictionary:
	pending = false
	if from == target:
		return {}
	var d := direction(from, target)
	var offset: Vector2i = DIRECTIONS[d]
	if button == MOUSE_BUTTON_RIGHT and not run_latched and maxi(absi(target.x - from.x), absi(target.y - from.y)) < 2:
		return {"turn": d + 1}
	run_latched = running
	var front := from + offset
	if running:
		var end := from + offset * 2
		if _free(front, can_walk, occupied) and _free(end, can_walk, occupied):
			return {"move": end}
		return {"path": target}
	if _free(front, can_walk, occupied):
		return {"move": front}
	if not occupied.has(front):
		for side in [posmod(d - 1, 8), (d + 1) % 8]:
			var next: Vector2i = from + DIRECTIONS[side]
			if can_walk.call(next.x, next.y):
				# Action-layer revalidation rejects an occupied side tile.
				return {"move": next} if not occupied.has(next) else {}
	return {"turn": d + 1}


static func _free(point: Vector2i, can_walk: Callable, occupied: Dictionary) -> bool:
	return not occupied.has(point) and can_walk.call(point.x, point.y)
