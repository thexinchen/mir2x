extends RefCounted

const DIRECTIONS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func find_path(start: Vector2i, goals: Array[Vector2i], can_walk: Callable, occupied: Dictionary, max_nodes := 50000, max_step := 1) -> Array[Vector2i]:
	max_step = clampi(max_step, 1, 3)
	var goal_set := {}
	var valid_goals: Array[Vector2i] = []
	for goal in goals:
		if can_walk.call(goal.x, goal.y) and (not occupied.has(goal) or goal == start):
			goal_set[goal] = true
			valid_goals.append(goal)
	if goal_set.is_empty() or goal_set.has(start):
		return []

	# Bounding box of all goals. A hop that crosses the goal box on either axis
	# (i.e. lands on the far side of where every goal sits) is an "overshoot":
	# the path runs past the target on the shorter axis and then has to come
	# back, which visually traces a triangle instead of a straight line.
	# Penalise such hops so the search prefers paths that approach the goal
	# monotonically on each axis and only turn once they are aligned.
	var goal_box_min_x := valid_goals[0].x
	var goal_box_max_x := valid_goals[0].x
	var goal_box_min_y := valid_goals[0].y
	var goal_box_max_y := valid_goals[0].y
	for goal in valid_goals:
		goal_box_min_x = mini(goal_box_min_x, goal.x)
		goal_box_max_x = maxi(goal_box_max_x, goal.x)
		goal_box_min_y = mini(goal_box_min_y, goal.y)
		goal_box_max_y = maxi(goal_box_max_y, goal.y)

	var open: Array[Dictionary] = []
	var came_from := {}
	var start_state := Vector3i(start.x, start.y, -1)
	var best_cost := {start_state: 0}
	_push_heap(open, {"point": start, "direction": -1, "score": _heuristic(start, valid_goals, max_step)})
	var expanded := 0
	while not open.is_empty() and expanded < max_nodes:
		var entry := _pop_heap(open)
		var current: Vector2i = entry.point
		var current_direction: int = entry.direction
		var current_state := Vector3i(current.x, current.y, current_direction)
		var current_cost: int = best_cost.get(current_state, 0x7FFFFFFF)
		if int(entry.score) > current_cost + _heuristic(current, valid_goals, max_step):
			continue
		if goal_set.has(current):
			return _normalize_straight_segments(start, _reconstruct(came_from, start_state, current_state), max_step)
		expanded += 1
		for direction_index in range(DIRECTIONS.size()):
			var direction: Vector2i = DIRECTIONS[direction_index]
			for hop_size in range(max_step, 0, -1):
				var next: Vector2i = current + direction * hop_size
				var reachable := true
				for distance in range(1, hop_size + 1):
					var crossed := current + direction * distance
					if occupied.has(crossed) or not can_walk.call(crossed.x, crossed.y):
						reachable = false
						break
				if not reachable:
					continue
				var turn_cost := 0 if current_direction < 0 else _direction_distance(current_direction, direction_index)
				var hop_cost := 100 + hop_size * 10 + turn_cost
				hop_cost += _overshoot_penalty(current, next, goal_box_min_x, goal_box_max_x, goal_box_min_y, goal_box_max_y)
				var next_cost := current_cost + hop_cost
				var next_state := Vector3i(next.x, next.y, direction_index)
				if next_cost >= int(best_cost.get(next_state, 0x7FFFFFFF)):
					continue
				best_cost[next_state] = next_cost
				came_from[next_state] = current_state
				_push_heap(open, {"point": next, "direction": direction_index, "score": next_cost + _heuristic(next, valid_goals, max_step)})
	return []


# A hop overshoots when it leaves the goal box on an axis it was approaching
# from one side. Concretely: if current is on one side of the box and next is
# on the opposite side, the hop jumped straight across the target band and
# will have to reverse direction to land on a goal — the classic triangle leg.
func _overshoot_penalty(current: Vector2i, next: Vector2i, box_min_x: int, box_max_x: int, box_min_y: int, box_max_y: int) -> int:
	# Landing inside the box can never be an overshoot.
	if next.x >= box_min_x and next.x <= box_max_x and next.y >= box_min_y and next.y <= box_max_y:
		return 0
	var penalty := 0
	# X axis: crossed the box band (current outside-left, next outside-right or vice versa).
	var cur_left := current.x < box_min_x
	var cur_right := current.x > box_max_x
	var nxt_left := next.x < box_min_x
	var nxt_right := next.x > box_max_x
	if (cur_left and nxt_right) or (cur_right and nxt_left):
		penalty += 200
	# Y axis.
	var cur_above := current.y < box_min_y
	var cur_below := current.y > box_max_y
	var nxt_above := next.y < box_min_y
	var nxt_below := next.y > box_max_y
	if (cur_above and nxt_below) or (cur_below and nxt_above):
		penalty += 200
	return penalty


func _normalize_straight_segments(start: Vector2i, path: Array[Vector2i], max_step: int) -> Array[Vector2i]:
	if max_step <= 1 or path.size() < 2:
		return path
	var normalized: Array[Vector2i] = []
	var normalized_cursor := start
	var index := 0
	while index < path.size():
		var original_previous: Vector2i = start if index == 0 else path[index - 1]
		var first_delta: Vector2i = path[index] - original_previous
		var direction := Vector2i(signi(first_delta.x), signi(first_delta.y))
		var segment_distance := 0
		var segment_end := index
		var scan_previous := original_previous
		while segment_end < path.size():
			var delta: Vector2i = path[segment_end] - scan_previous
			if Vector2i(signi(delta.x), signi(delta.y)) != direction:
				break
			segment_distance += maxi(absi(delta.x), absi(delta.y))
			scan_previous = path[segment_end]
			segment_end += 1
		while segment_distance >= max_step:
			normalized_cursor += direction * max_step
			normalized.append(normalized_cursor)
			segment_distance -= max_step
		if segment_distance > 0:
			normalized_cursor += direction * segment_distance
			normalized.append(normalized_cursor)
		index = segment_end
	return normalized


func _heuristic(point: Vector2i, goals: Array[Vector2i], max_step: int) -> int:
	var best := 0x7FFFFFFF
	for goal in goals:
		var dx := absi(point.x - goal.x)
		var dy := absi(point.y - goal.y)
		var distance := maxi(dx, dy)
		best = mini(best, (distance / max_step) * (100 + max_step * 10) + (100 + distance % max_step * 10 if distance % max_step else 0))
	return best


func _direction_distance(from_direction: int, to_direction: int) -> int:
	var difference := absi(from_direction - to_direction)
	return mini(difference, DIRECTIONS.size() - difference)


func _reconstruct(came_from: Dictionary, start: Vector3i, goal: Vector3i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Vector3i = goal
	while current != start:
		path.push_front(Vector2i(current.x, current.y))
		current = came_from[current]
	return path


func _push_heap(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) >> 1
		if int(heap[parent].score) <= int(entry.score):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


# Mir3 4AB72C/4AAF14: weighted wavefront without a target heuristic.
# Existing chase/pickup search stays unchanged; this is for ground run fallback.
func find_mir3_path(start: Vector2i, goal: Vector2i, can_walk: Callable, occupied: Dictionary, max_nodes := 50000, bounds := Rect2i()) -> Array[Vector2i]:
	# 4AB72C rejects out-of-map endpoints before its blocked-goal adjustment.
	if bounds.has_area() and (not bounds.has_point(start) or not bounds.has_point(goal)):
		return []
	goal = resolve_mir3_goal(goal, can_walk, occupied, bounds)
	if goal == Vector2i(-1, -1) or goal == start:
		return []
	var open: Array[Dictionary] = [{"point": start, "score": 0}]
	var costs := {start: 0}
	var parents := {}
	var expanded := 0
	while not open.is_empty() and expanded < max_nodes:
		var entry := _pop_heap(open)
		var point: Vector2i = entry.point
		var cost: int = entry.score
		if cost != int(costs[point]):
			continue
		if point == goal:
			var result: Array[Vector2i] = []
			while point != start:
				result.push_front(point)
				point = parents[point]
			return _normalize_straight_segments(start, result, 2)
		expanded += 1
		for d in range(8):
			var next: Vector2i = point + DIRECTIONS[d]
			if occupied.has(next) or not can_walk.call(next.x, next.y):
				continue
			var weight := 4
			for neighbor in DIRECTIONS:
				var adjacent: Vector2i = next + neighbor
				if not can_walk.call(adjacent.x, adjacent.y):
					weight += 1
			if d % 2 == 1:
				weight += weight >> 1
			var candidate := cost + weight
			if candidate >= int(costs.get(next, 0x7FFFFFFF)):
				continue
			costs[next] = candidate
			parents[next] = point
			_push_heap(open, {"point": next, "score": candidate})
	return []


func resolve_mir3_goal(goal: Vector2i, can_walk: Callable, occupied: Dictionary, bounds := Rect2i()) -> Vector2i:
	if bounds.has_area() and not bounds.has_point(goal):
		return Vector2i(-1, -1)
	if can_walk.call(goal.x, goal.y) and not occupied.has(goal):
		return goal
	# 4AB2A8 receives its parent's Delphi stack frame. Parent +0x10 is
	# target X and +0x0C is target Y: N, NE, E, SE, S, SW, W, NW. Radius
	# starts at 1 and the loop exits on 2; it never searches another ring.
	for offset in DIRECTIONS:
		var candidate: Vector2i = goal + offset
		if bounds.has_area() and not bounds.has_point(candidate):
			continue
		if can_walk.call(candidate.x, candidate.y) and not occupied.has(candidate):
			return candidate
	return Vector2i(-1, -1)


func _pop_heap(heap: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while true:
		var left: int = index * 2 + 1
		if left >= heap.size():
			break
		var right: int = left + 1
		var child: int = right if right < heap.size() and int(heap[right].score) < int(heap[left].score) else left
		if int(heap[child].score) >= int(tail.score):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = tail
	return result
