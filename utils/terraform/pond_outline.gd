class_name PondOutline
extends RefCounted
## A pond stroke's painted area as an outline (card terraform-p2-water; docs/systems/terraform.md
## "Tools"): the Pond tool's dabs are capsules in a scratch mask, traced on release into the pond
## primitive's outline. Pure: no Node, safe on any thread.
##
## The mask is a field, not bits: at each corner of a CELL_M grid over the dabs, the largest
## `radius - distance` to any dab's capsule (clamped a few cells out), so the contour at zero is the
## union of the capsules' edges, interpolated between corners rather than stepped. Marching squares
## (saddles split by the centre's value) gives closed loops; the loop of largest area is the outer
## edge (a ring painted round dry ground fills: a pond has no islands), simplified by
## Douglas-Peucker to SIMPLIFY_M. Extending and shrinking are Geometry2D's clipping on outlines:
## merged() and clipped() keep the largest outer piece, so a pond stays one body.

## The scratch mask's cell (map metres), and the largest grid side (the cell grows past it).
const CELL_M := 0.25
const MAX_SIDE := 512
## Douglas-Peucker tolerance of the traced outline (map metres).
const SIMPLIFY_M := 0.05
## An outline smaller than this (square metres) is no pond: a shrink to less removes it.
const MIN_AREA_M2 := 1.0
## Floats a dab takes in a capsule list: ax, az, bx, bz, radius.
const DAB := 5


## The outline of the union of `capsules` (DAB floats each, map XZ), counter-clockwise in XZ, or
## empty when they cover less than MIN_AREA_M2.
static func trace(capsules: PackedFloat32Array) -> PackedVector2Array:
	if capsules.size() < DAB:
		return PackedVector2Array()
	var box := Rect2()
	for k in range(0, capsules.size() - DAB + 1, DAB):
		var a := Vector2(capsules[k], capsules[k + 1])
		var dab := Rect2(a, Vector2.ZERO).expand(Vector2(capsules[k + 2], capsules[k + 3]))
		dab = dab.grow(capsules[k + 4])
		box = dab if k == 0 else box.merge(dab)
	var cell := maxf(CELL_M, maxf(box.size.x, box.size.y) / float(MAX_SIDE - 4))
	box = box.grow(2.0 * cell)
	var nx := ceili(box.size.x / cell) + 1
	var nz := ceili(box.size.y / cell) + 1
	var field := _field(capsules, box.position, cell, nx, nz)
	var loops := _contours(field, box.position, cell, nx, nz)
	var best := largest(loops)
	if best.is_empty() or absf(area(best)) < MIN_AREA_M2:
		return PackedVector2Array()
	if area(best) < 0.0:
		best.reverse()
	return simplify(best, SIMPLIFY_M)


## The signed area of the closed polygon `poly` (positive counter-clockwise in XZ).
static func area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## The polygon of largest absolute area in `polys`, or empty.
static func largest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := 0.0
	for poly: PackedVector2Array in polys:
		var a := absf(area(poly))
		if a > best_area:
			best_area = a
			best = poly
	return best


## `a` and `b` as one outline (Geometry2D.merge_polygons, its largest outer piece, holes filled),
## counter-clockwise.
static func merged(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	return _outer(Geometry2D.merge_polygons(a, b))


## `a` with `b` cut out (Geometry2D.clip_polygons), its largest piece, or empty when less than
## MIN_AREA_M2 is left.
static func clipped(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := _outer(Geometry2D.clip_polygons(a, b))
	return out if absf(area(out)) >= MIN_AREA_M2 else PackedVector2Array()


## True when `a` and `b` overlap.
static func overlaps(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()


## The closed loop `loop` simplified to `eps` (Douglas-Peucker on its two halves, split at the
## point farthest from the first, so both are open lines).
static func simplify(loop: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := loop.size()
	if n < 4:
		return loop
	var far := 0
	for i in n:
		if loop[i].distance_squared_to(loop[0]) > loop[far].distance_squared_to(loop[0]):
			far = i
	var first := loop.slice(0, far + 1)
	var second := loop.slice(far)
	second.append(loop[0])
	var out := PackedVector2Array()
	for k in WaterCourseFit.douglas_peucker(first, eps):
		out.append(first[k])
	var tail := WaterCourseFit.douglas_peucker(second, eps)
	for j in range(1, tail.size() - 1):
		out.append(second[tail[j]])
	return out


## The outline floats a pond primitive keeps after its depth (x, z per point).
static func floats(outline: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in outline:
		out.append_array([p.x, p.y])
	return out


## The outline of pond primitive data `data` ([depth, x, z, ...]).
static func of_data(data: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(1, data.size() - 1, 2):
		out.append(Vector2(data[k], data[k + 1]))
	return out


static func _outer(polys: Array) -> PackedVector2Array:
	var best := largest(polys)
	if not best.is_empty() and area(best) < 0.0:
		best.reverse()
	return best


## The mask field (see the header) at the nx x nz corners from `origin`, `cell` apart.
static func _field(
	capsules: PackedFloat32Array, origin: Vector2, cell: float, nx: int, nz: int
) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(nx * nz)
	field.fill(-2.0 * cell)
	for k in range(0, capsules.size() - DAB + 1, DAB):
		var a := Vector2(capsules[k], capsules[k + 1])
		var b := Vector2(capsules[k + 2], capsules[k + 3])
		var r := capsules[k + 4]
		var reach := Rect2(a, Vector2.ZERO).expand(b).grow(r + 2.0 * cell)
		var i0 := clampi(floori((reach.position.x - origin.x) / cell), 0, nx - 1)
		var i1 := clampi(ceili((reach.end.x - origin.x) / cell), 0, nx - 1)
		var j0 := clampi(floori((reach.position.y - origin.y) / cell), 0, nz - 1)
		var j1 := clampi(ceili((reach.end.y - origin.y) / cell), 0, nz - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := origin + Vector2(i, j) * cell
				var d := r - p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				var at := j * nx + i
				if d > field[at]:
					field[at] = d
	return field


## Marching squares on `field` at zero: closed loops of world points.
static func _contours(
	field: PackedFloat32Array, origin: Vector2, cell: float, nx: int, nz: int
) -> Array:
	# Edge keys: 2 * corner for the edge to its right, 2 * corner + 1 for the edge below it.
	var links := {}
	var points := {}
	for j in nz - 1:
		for i in nx - 1:
			var c := j * nx + i
			var v := [field[c], field[c + 1], field[c + nx + 1], field[c + nx]]
			var case_id := 0
			for k in 4:
				if v[k] > 0.0:
					case_id |= 1 << k
			if case_id == 0 or case_id == 15:
				continue
			# Edges: 0 top (c to c+1), 1 right (c+1 down), 2 bottom (c+nx to c+nx+1), 3 left.
			var keys := [2 * c, 2 * (c + 1) + 1, 2 * (c + nx), 2 * c + 1]
			var pairs := _case_pairs(case_id, (v[0] + v[1] + v[2] + v[3]) * 0.25 > 0.0)
			for pair: Vector2i in pairs:
				for e in [pair.x, pair.y]:
					if not points.has(keys[e]):
						points[keys[e]] = _edge_point(e, i, j, v, origin, cell)
				_link(links, keys[pair.x], keys[pair.y])
				_link(links, keys[pair.y], keys[pair.x])
	var loops: Array = []
	var seen := {}
	for start: int in links:
		if seen.has(start):
			continue
		var loop := PackedVector2Array()
		var prev := -1
		var at := start
		while not seen.has(at):
			seen[at] = true
			loop.append(points[at])
			var next := -1
			for n: int in links[at]:
				if n != prev and not seen.has(n):
					next = n
					break
			if next < 0:
				break
			prev = at
			at = next
		if loop.size() >= 3:
			loops.append(loop)
	return loops


static func _link(links: Dictionary, a: int, b: int) -> void:
	if not links.has(a):
		links[a] = []
	(links[a] as Array).append(b)


## The edge pairs a cell of case `case_id` joins (corner bits 0 top-left, 1 top-right, 2
## bottom-right, 3 bottom-left); `centre_in` splits the two saddles.
static func _case_pairs(case_id: int, centre_in: bool) -> Array[Vector2i]:
	match case_id:
		1, 14:
			return [Vector2i(3, 0)]
		2, 13:
			return [Vector2i(0, 1)]
		3, 12:
			return [Vector2i(3, 1)]
		4, 11:
			return [Vector2i(1, 2)]
		6, 9:
			return [Vector2i(0, 2)]
		7, 8:
			return [Vector2i(3, 2)]
		5:
			if centre_in:
				return [Vector2i(3, 2), Vector2i(0, 1)]
			return [Vector2i(3, 0), Vector2i(1, 2)]
		10:
			if centre_in:
				return [Vector2i(3, 0), Vector2i(1, 2)]
			return [Vector2i(0, 1), Vector2i(3, 2)]
	return []


## Where the zero crossing lies on edge `e` of cell (i, j) with corner values `v`.
static func _edge_point(
	e: int, i: int, j: int, v: Array, origin: Vector2, cell: float
) -> Vector2:
	var corners := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
	var ends := [[0, 1], [1, 2], [3, 2], [0, 3]]
	var a: int = ends[e][0]
	var b: int = ends[e][1]
	var fa: float = v[a]
	var fb: float = v[b]
	var t := clampf(fa / (fa - fb), 0.0, 1.0) if absf(fa - fb) > 1e-9 else 0.5
	var p: Vector2 = (corners[a] as Vector2).lerp(corners[b], t)
	return origin + p * cell
