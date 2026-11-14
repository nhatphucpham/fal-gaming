class_name OutlineGeometry
extends RefCounted
## Outline geometry for FormationOutlines: closed loops around a set of
## board cells, their length, and a point at a distance along one.

## Closed loops around global `cells`, clockwise, in board-local pixels,
## pulled in by `inset_px`. At a corner two loops share the walk turns
## right, so diagonal neighbours stay separate loops.
static func loops(cells: Array[Vector2i], inset_px: float) -> Array[PackedVector2Array]:
	var inside: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		inside[Vector2i(cell.x, BoardView.ROWS - 1 - cell.y)] = true
	var edges: Dictionary[Vector2i, Array] = {}
	for grid: Vector2i in inside:
		for side: Array in [[Vector2i.UP, Vector2i(0, 0), Vector2i(1, 0)], [Vector2i.RIGHT, Vector2i(1, 0), Vector2i(1, 1)],
				[Vector2i.DOWN, Vector2i(1, 1), Vector2i(0, 1)], [Vector2i.LEFT, Vector2i(0, 1), Vector2i(0, 0)]]:
			if inside.has(grid + side[0]):
				continue
			var start: Vector2i = grid + side[1]
			if not edges.has(start):
				edges[start] = []
			edges[start].append(grid + side[2])
	var loops: Array[PackedVector2Array] = []
	while not edges.is_empty():
		var start: Vector2i = edges.keys()[0]
		var corners: Array[Vector2i] = [start]
		var at := start
		var direction := Vector2i.ZERO
		while true:
			var next := _take_edge(edges, at, direction)
			direction = next - at
			at = next
			if at == start:
				break
			corners.append(at)
		loops.append(_inset(corners, inset_px))
	return loops


# The edge leaving `at`, preferring a right turn, then straight, then left.
static func _take_edge(edges: Dictionary[Vector2i, Array], at: Vector2i, direction: Vector2i) -> Vector2i:
	var ends: Array = edges[at]
	var pick := 0
	if ends.size() > 1:
		var right := Vector2i(-direction.y, direction.x)
		for index: int in ends.size():
			if ends[index] - at == right:
				pick = index
	var end: Vector2i = ends[pick]
	ends.remove_at(pick)
	if ends.is_empty():
		edges.erase(at)
	return end


static func _inset(corners: Array[Vector2i], inset_px: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := corners.size()
	for index: int in count:
		var incoming := Vector2(corners[index] - corners[(index + count - 1) % count]).normalized()
		var outgoing := Vector2(corners[(index + 1) % count] - corners[index]).normalized()
		# The inside is on the right of a clockwise walk (y grows downward).
		var shift := Vector2(-incoming.y, incoming.x)
		if not outgoing.is_equal_approx(incoming):
			shift += Vector2(-outgoing.y, outgoing.x)
		points.append(Vector2(corners[index]) * BoardView.CELL_PX + shift * inset_px)
	points.append(points[0])
	return points


## The loop's length in pixels (at least 1).
static func length_of(loop: PackedVector2Array) -> float:
	var length := 0.0
	for index: int in loop.size() - 1:
		length += loop[index].distance_to(loop[index + 1])
	return maxf(length, 1.0)


## The point `distance` pixels along the loop.
static func point_at(loop: PackedVector2Array, distance: float) -> Vector2:
	var left := distance
	for index: int in loop.size() - 1:
		var piece := loop[index].distance_to(loop[index + 1])
		if left <= piece:
			return loop[index].lerp(loop[index + 1], left / maxf(piece, 0.001))
		left -= piece
	return loop[loop.size() - 1]
