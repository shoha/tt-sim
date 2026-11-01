class_name StructureDressing
extends RefCounted

## What settles a building into its place (probe B, 2026-10-28): a soft patch of worn ground around
## the foundation, a path or step from the door, and a few bold painted shapes along the walls
## (shrubs, flower beds, tufts, rocks, planters, a woodpile). A pure function of the record, the
## recipe's door and the ground, built beside the building's meshes and carried in its parts, so
## every peer derives the same dressing and nothing is stored (docs/systems/structures.md
## "Dressing"). Two meshes come out, in the building's map frame:
##   "ground": an alpha-blended soft skirt and path draped on the terrain (vertex colour, alpha),
##   "props": opaque low-poly blobs, blades and slabs (vertex colour).
## Every random choice is an integer hash of the record's seed and id (StructurePaint.mix), never an
## engine RNG, so a re-roll draws a new yard and two buildings never share one. The kind of yard
## follows the recipe's family: a cottage gets stepping stones, flower beds and a woodpile, a house
## worn earth and a path with shrubs and boulders, a townhouse a paved apron, a step and planters.
## This file lays the yard out (skirt, path, where each cluster goes); the props are drawn by
## StructureDressingProps from the shape primitives of StructureDressingShapes.
## Pure and safe on any thread.

## Soft ground patch: how far past the walls it reaches before it fades out, per family, metres.
const SKIRT_REACH_M := {
	"cottage": Vector2(1.3, 2.0), "house": Vector2(1.2, 1.9), "townhouse": Vector2(0.7, 1.1)
}
## The skirt starts this far inside the wall line (the wall hides its inner edge).
const SKIRT_INSET_M := 0.15
## The skirt and path float this far above the terrain, metres.
const GROUND_LIFT_M := 0.05
## Samples of the outline are taken this far apart, metres.
const OUTLINE_STEP_M := 0.55
## Nothing is planted within this distance of the door, metres.
const DOOR_CLEAR_M := 1.5
## At most this many planted clusters per building.
const MAX_CLUSTERS := 11
## Ground under the dressing is sampled this far past the walls for the structure key, metres.
const KEY_REACH_M := 1.6
const KEY_STEP_M := 1.0
## Paths and aprons end when the ground is steeper than this (rise over run).
const PATH_MAX_SLOPE := 0.6
## Plants and rocks keep this far from another structure's footprint, metres.
const NEIGHBOUR_CLEAR_M := 1.0
## Other structures nearer than this to a building (their footprints' bounds) are considered. It
## must reach REACH_MAX_M + NEIGHBOUR_CLEAR_M (7.5 m), the farthest a yard tests another footprint;
## it was 14 m (perf3: an add rebuilt the 19 buildings round it, now the 8 round it; the pinned
## digests did not move).
const NEIGHBOUR_RANGE_M := 8.0
## The cell size of neighbour_grid.
const GRID_CELL_M := 8.0
## The farthest a yard's own parts reach from the walls (the widest skirt at the door and the
## path), metres: the area the water is asked about.
const REACH_MAX_M := 6.5

## False builds no dressing (the A/B switch of the perf probe and of tests).
static var enabled := true


## The family a recipe reference belongs to: "cottage", "townhouse" or "house" (anything else, the
## stone house included), read from the structure id the way the library index names it.
static func family_of(recipe: String) -> String:
	var id := recipe.get_slice(":", 1) if ":" in recipe else recipe
	if id.begins_with("cottage"):
		return "cottage"
	if id.begins_with("townhouse"):
		return "townhouse"
	return "house"


## The dressing of `structure` on ground `doc` as {"ground": mesh arrays or {}, "props": mesh arrays
## or {}, "triangles": int, "family": name}. `layout` is the building's final layout (its door), or
## null, which puts the door in the middle of edge 0.
static func build(doc: MapDocument, structure: Structure, layout: Variant) -> Dictionary:
	var out := {"ground": {}, "props": {}, "triangles": 0, "family": ""}
	var plan := structure.footprint
	if not enabled or plan.size() < 3:
		return out
	var family := family_of(structure.recipe)
	out.family = family
	var rng := StructureDressingShapes.Rng.new(
		StructurePaint.mix(structure.seed_value, structure.id * 7919 + 101)
	)
	var outward := _outward_sign(plan)
	var door := _door(plan, layout, outward)
	var ground := StructureDressingShapes.Soup.new()
	var props := StructureDressingShapes.Soup.new()
	var earth := _earth_of(family, rng)
	var clear := _Clear.new(doc, structure)
	_skirt(ground, doc, plan, outward, door, family, earth, rng, clear)
	# Paint already running out of the door (a Dress's door path) takes the ribbon's place.
	var painted := StructureDoorPaint.joined(doc, door.at, door.out) > 0.5
	var ribbon := StructureDressingShapes.Soup.new() if painted else ground
	_path(ribbon, props, doc, door, family, earth, rng, clear)
	_plant(props, doc, plan, outward, door, family, rng, clear)
	out.ground = ground.arrays()
	out.props = props.arrays()
	out.triangles = ground.triangles() + props.triangles()
	return out


## The ground under the dressing's reach for the structure key: a ring KEY_REACH_M past the walls
## and the door's path, every KEY_STEP_M, so a sculpt beside a building redraws its yard.
static func ground_samples(doc: MapDocument, plan: PackedVector2Array) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	if plan.size() < 3 or not enabled:
		return samples
	var outward := _outward_sign(plan)
	var length := _perimeter(plan)
	var count := clampi(ceili(length / KEY_STEP_M), 8, 256)
	var courses := WaterGeometry.river_courses(doc, bounds_of(plan).grow(REACH_MAX_M))
	for i in count:
		var frame := _frame_at(plan, length * float(i) / count, outward)
		var ring_point: Vector2 = frame.p + frame.n * KEY_REACH_M
		samples.append(WaterGeometry.ground_at(doc, ring_point))
		# Water decides how far the yard reaches, so a pond raised or dug beside it redraws it.
		samples.append(1.0 if WaterGeometry.is_wet_at(doc, ring_point, -1, courses) else 0.0)
	var door := _door(plan, null, outward)
	for s in [1.0, 2.5, 4.0, 5.5]:
		samples.append(WaterGeometry.ground_at(doc, door.at + door.out * float(s)))
	samples.append(StructureDoorPaint.joined(doc, door.at, door.out))
	return samples


## The footprints of the other structures of `doc` whose bounds come within NEIGHBOUR_RANGE_M of
## `structure`'s own.
## `boxes` (structure id -> bounds_of its footprint) saves measuring every footprint again for every
## structure when a caller asks about all of them (StructureGeometry.keys_of); empty: measured here.
## `grid` (neighbour_grid) limits the test to the structures in the cells the range reaches
## (perf3: the all-pairs loop was 90 ms for 126 structures, and every add, edit and removal ran it
## again); the result is the same list in the same (document) order.
static func neighbours(
	doc: MapDocument, structure: Structure, boxes: Dictionary = {}, grid: Dictionary = {}
) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var mine := bounds_of(structure.footprint).grow(NEIGHBOUR_RANGE_M)
	if not grid.is_empty():
		for index in _grid_candidates(grid, mine):
			var other: Structure = doc.structures[index]
			if other.id != structure.id and mine.intersects(grid.rects[index]):
				out.append(other.footprint)
		return out
	for other in doc.structures:
		if other.id == structure.id or other.footprint.size() < 3:
			continue
		var box: Rect2 = boxes[other.id] if boxes.has(other.id) else bounds_of(other.footprint)
		if mine.intersects(box):
			out.append(other.footprint)
	return out


## A uniform grid over the footprint bounds of `doc`'s structures with three or more corners:
## {"cells": Vector2i -> PackedInt32Array of indices into doc.structures, "rects": Array[Rect2] by
## index}. Built once per refresh, it makes "who is near" proportional to the neighbours, not to
## every structure on the map.
static func neighbour_grid(doc: MapDocument, boxes: Dictionary = {}) -> Dictionary:
	var cells := {}
	var rects: Array[Rect2] = []
	for index in doc.structures.size():
		var structure: Structure = doc.structures[index]
		var box := Rect2()
		if structure.footprint.size() >= 3:
			box = boxes[structure.id] if boxes.has(structure.id) else bounds_of(structure.footprint)
			var low := _cell_of(box.position)
			var high := _cell_of(box.end)
			for cx in range(low.x, high.x + 1):
				for cy in range(low.y, high.y + 1):
					var key := Vector2i(cx, cy)
					var held: PackedInt32Array = cells.get(key, PackedInt32Array())
					held.append(index)
					cells[key] = held
		rects.append(box)
	return {"cells": cells, "rects": rects}


static func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / GRID_CELL_M), floori(point.y / GRID_CELL_M))


## The indices (ascending, once each) of the structures with a cell the rectangle `area` touches.
static func _grid_candidates(grid: Dictionary, area: Rect2) -> PackedInt32Array:
	var seen := {}
	var low := _cell_of(area.position)
	var high := _cell_of(area.end)
	for cx in range(low.x, high.x + 1):
		for cy in range(low.y, high.y + 1):
			var held: Variant = (grid.cells as Dictionary).get(Vector2i(cx, cy))
			if held != null:
				for index in held as PackedInt32Array:
					seen[index] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## The bounding rectangle of `plan` (empty at the origin for no points).
static func bounds_of(plan: PackedVector2Array) -> Rect2:
	var rect := Rect2(plan[0], Vector2.ZERO) if not plan.is_empty() else Rect2()
	for p in plan:
		rect = rect.expand(p)
	return rect


# --- layout -------------------------------------------------------------------------------


## The sign that turns an edge's orthogonal into its outward normal (the same for every edge of a
## simple polygon).
static func _outward_sign(plan: PackedVector2Array) -> float:
	var a := plan[0]
	var b := plan[1]
	var side := (b - a).orthogonal().normalized()
	return -1.0 if Geometry2D.is_point_in_polygon((a + b) * 0.5 + side * 0.05, plan) else 1.0


static func _perimeter(plan: PackedVector2Array) -> float:
	var total := 0.0
	for k in plan.size():
		total += plan[k].distance_to(plan[(k + 1) % plan.size()])
	return total


## The point at arc length `s` along the closed outline and the outward normal of the edge it is on:
## {"p": Vector2, "n": Vector2, "t": Vector2, "edge": int}.
static func _frame_at(plan: PackedVector2Array, s: float, outward: float) -> Dictionary:
	var length := _perimeter(plan)
	var rest := fposmod(s, length)
	for k in plan.size():
		var a := plan[k]
		var b := plan[(k + 1) % plan.size()]
		var edge_length := a.distance_to(b)
		if rest <= edge_length or k == plan.size() - 1:
			var t := (b - a).normalized()
			return {
				"p": a.lerp(b, clampf(rest / maxf(edge_length, 0.0001), 0.0, 1.0)),
				"n": t.orthogonal() * outward,
				"t": t,
				"edge": k,
			}
		rest -= edge_length
	return {"p": plan[0], "n": Vector2.UP, "t": Vector2.RIGHT, "edge": 0}


## The door: {"at": its map XZ, "out": the outward normal of the wall it is in}. The recipe's door
## when its layout is known, else the middle of edge 0.
static func _door(plan: PackedVector2Array, layout: Variant, outward: float) -> Dictionary:
	var at := (plan[0] + plan[1]) * 0.5
	if layout is ProcgenBuildingLayout:
		var box: Dictionary = (layout as ProcgenBuildingLayout).door_opening()
		if not box.is_empty() and box.has("centre"):
			var centre: Vector3 = box.centre
			at = Vector2(centre.x, centre.z)
	var best := INF
	var out_normal := (plan[1] - plan[0]).orthogonal().normalized() * outward
	for k in plan.size():
		var a := plan[k]
		var b := plan[(k + 1) % plan.size()]
		var closest := Geometry2D.get_closest_point_to_segment(at, a, b)
		var d := at.distance_to(closest)
		if d < best:
			best = d
			out_normal = (b - a).orthogonal().normalized() * outward
	return {"at": at, "out": out_normal}


## A mid-tone of the worn ground this family's yard wears, with a per-building shift.
static func _earth_of(family: String, rng: StructureDressingShapes.Rng) -> Color:
	var base := Color(0.66, 0.53, 0.34)
	match family:
		"cottage":
			base = Color(0.69, 0.58, 0.34)
		"townhouse":
			base = Color(0.73, 0.67, 0.58)
	var shift := rng.between(-0.05, 0.05)
	return Color(base.r + shift, base.g + shift * 0.6, base.b - shift * 0.8)


# --- ground: skirt and path ------------------------------------------------------------------


## The soft patch around the foundation: bands from just inside the wall line to a wobbling reach,
## alpha 0.9 at the wall and 0 at the edge, wider around the door.
static func _skirt(
	soup: StructureDressingShapes.Soup,
	doc: MapDocument,
	plan: PackedVector2Array,
	outward: float,
	door: Dictionary,
	family: String,
	earth: Color,
	rng: StructureDressingShapes.Rng,
	clear: _Clear
) -> void:
	var reach_range: Vector2 = SKIRT_REACH_M[family]
	var length := _perimeter(plan)
	var count := clampi(ceili(length / OUTLINE_STEP_M), 8, 160)
	var knots := PackedFloat32Array()
	var knot_count := maxi(3, count / 4)
	for k in knot_count:
		knots.append(rng.between(reach_range.x, reach_range.y))
	var rings: Array = []
	for i in count:
		var s := length * float(i) / count
		var before := _frame_at(plan, s - 0.45, outward)
		var after := _frame_at(plan, s + 0.45, outward)
		var frame := _frame_at(plan, s, outward)
		var tangent: Vector2 = (after.p - before.p).normalized()
		var normal := tangent.orthogonal() * outward
		var u := float(i) / count * knot_count
		var k0 := int(u) % knot_count
		var reach := lerpf(
			knots[k0], knots[(k0 + 1) % knot_count], smoothstep(0.0, 1.0, u - floorf(u))
		)
		var near_door := smoothstep(2.4, 0.0, (frame.p as Vector2).distance_to(door.at))
		reach *= 1.0 + near_door * 0.55
		# The yard never runs into water or a neighbour's walls: the reach is pulled in until its
		# edge is clear (a drawn-in yard beside a pond or a terrace's next house).
		for _try in 4:
			if clear.is_open(frame.p + normal * reach, 0.35):
				break
			reach = maxf(reach * 0.6, 0.35)
		var offsets := [-SKIRT_INSET_M, 0.25, reach * 0.72, reach]
		var alphas := [1.0, 1.0, 0.9, 0.0]
		var ring: Array = []
		for b in 4:
			var at: Vector2 = frame.p + normal * float(offsets[b])
			# A deeper drip line at the wall and a lighter, warmer wash outward: the patch reads
			# against green ground in sun and in shade alike.
			var tone := (1.0 + (rng.f() - 0.5) * 0.1) * (0.8 if b == 0 else 1.0)
			var lighter := earth.lerp(Color(0.86, 0.76, 0.46), 0.35 * float(b) / 3.0)
			var color := Color(
				lighter.r * tone, lighter.g * tone, lighter.b * tone, float(alphas[b])
			)
			ring.append(
				soup.vertex(
					StructureDressingShapes.on_ground(doc, at, GROUND_LIFT_M), Vector3.UP, color
				)
			)
		rings.append(ring)
	for i in count:
		var ring_a: Array = rings[i]
		var ring_b: Array = rings[(i + 1) % count]
		for b in 3:
			soup.tri(ring_a[b], ring_a[b + 1], ring_b[b + 1])
			soup.tri(ring_a[b], ring_b[b + 1], ring_b[b])


## The path or step out of the door, by family: a cottage's stepping stones over a faint worn
## ribbon, a house's dirt path, a townhouse's pale paved apron and a slab for a step.
static func _path(
	ground: StructureDressingShapes.Soup,
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	door: Dictionary,
	family: String,
	earth: Color,
	rng: StructureDressingShapes.Rng,
	clear: _Clear
) -> void:
	var out: Vector2 = door.out
	var at: Vector2 = door.at
	var side := out.orthogonal()
	var length := rng.between(3.0, 5.0)
	var width := 1.05
	var color := earth.lerp(Color(0.9, 0.78, 0.52), 0.5)
	var alpha := 0.97
	match family:
		"cottage":
			length = rng.between(3.0, 4.5)
			width = 0.8
			alpha = 0.7
		"townhouse":
			length = rng.between(1.3, 1.9)
			width = 1.05
			color = StructureDressingProps.STONE_PALE.lerp(earth, 0.15)
			alpha = 0.95
	var sway_amp := rng.between(0.25, 0.6) * (0.0 if family == "townhouse" else 1.0)
	var sway := PackedFloat32Array(
		[rng.between(-1.0, 1.0), rng.between(-1.0, 1.0), rng.between(-1.0, 1.0)]
	)
	var steps := maxi(3, ceili(length / 0.45))
	var previous := -1
	var left_prev := -1
	var right_prev := -1
	var stopped := false
	var centre_prev := Vector2.ZERO
	for i in steps + 1:
		var u := float(i) / steps
		var s := 0.15 + length * u
		var knot := u * 2.0
		var k0 := mini(int(knot), 1)
		var bend := lerpf(sway[k0], sway[k0 + 1], smoothstep(0.0, 1.0, knot - float(k0)))
		var centre := at + out * s + side * bend * sway_amp * u
		if not clear.is_open(centre, 0.4):
			length = s - 0.15
			stopped = true
		if (
			i > 0
			and (
				(
					absf(
						(
							WaterGeometry.ground_at(doc, centre)
							- WaterGeometry.ground_at(doc, centre_prev)
						)
					)
					/ 0.45
				)
				> PATH_MAX_SLOPE
			)
		):
			stopped = true
		if stopped:
			break
		centre_prev = centre
		var half := width * 0.5 * (1.0 if family == "townhouse" else lerpf(1.1, 0.7, u))
		var fade := 1.0 - smoothstep(0.65, 1.0, u)
		var shade := 1.0 + (rng.f() - 0.5) * 0.08
		var rgb := Color(color.r * shade, color.g * shade, color.b * shade)
		var edge_alpha := 0.0 if family != "townhouse" else 0.35 * fade
		var c_mid := Color(rgb.r, rgb.g, rgb.b, alpha * fade)
		var c_edge := Color(rgb.r, rgb.g, rgb.b, edge_alpha)
		var lift := GROUND_LIFT_M * 1.6
		var mid_i := ground.vertex(
			StructureDressingShapes.on_ground(doc, centre, lift), Vector3.UP, c_mid
		)
		var left_i := ground.vertex(
			StructureDressingShapes.on_ground(doc, centre + side * half, lift), Vector3.UP, c_edge
		)
		var right_i := ground.vertex(
			StructureDressingShapes.on_ground(doc, centre - side * half, lift), Vector3.UP, c_edge
		)
		if previous >= 0:
			ground.tri(left_prev, left_i, previous)
			ground.tri(previous, left_i, mid_i)
			ground.tri(previous, mid_i, right_prev)
			ground.tri(right_prev, mid_i, right_i)
		previous = mid_i
		left_prev = left_i
		right_prev = right_i
	match family:
		"cottage":
			StructureDressingProps.stepping_stones(
				props, doc, at, out, side, length * 0.9, sway, sway_amp, rng
			)
		"townhouse":
			StructureDressingShapes.slab(
				props,
				doc,
				at + out * 0.62,
				out,
				1.5,
				0.78,
				0.07,
				StructureDressingProps.STONE_PALE,
				rng
			)
		_:
			StructureDressingShapes.slab(
				props,
				doc,
				at + out * 0.4,
				out,
				1.0,
				0.5,
				0.06,
				StructureDressingProps.ROCK.lerp(earth, 0.4),
				rng
			)


# --- props ------------------------------------------------------------------------------------


## Plants and objects along the walls, door side left open, drawn by family.
static func _plant(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	plan: PackedVector2Array,
	outward: float,
	door: Dictionary,
	family: String,
	rng: StructureDressingShapes.Rng,
	clear: _Clear
) -> void:
	var length := _perimeter(plan)
	var s := rng.between(0.0, 1.2)
	var clusters := 0
	var made_woodpile := false
	var door_normal: Vector2 = door.out
	var gap: float = {"cottage": 0.95, "house": 1.25, "townhouse": 2.4}[family]
	if family == "townhouse" and clear.is_open(door.at + door_normal * 0.4, NEIGHBOUR_CLEAR_M):
		StructureDressingProps.planters(props, doc, door, rng)
	while s < length and clusters < MAX_CLUSTERS:
		var frame := _frame_at(plan, s, outward)
		var step := rng.between(gap, gap + 1.1)
		s += step
		var normal: Vector2 = frame.n
		var depth := rng.between(0.5, 0.85)
		var at: Vector2 = frame.p + normal * depth
		if at.distance_to(door.at) < DOOR_CLEAR_M + 0.3 * float(normal.dot(door_normal) > 0.7):
			continue
		if Geometry2D.is_point_in_polygon(at, plan):
			continue
		# Nothing is planted within a metre of another house, or in water.
		if not clear.is_open(at, NEIGHBOUR_CLEAR_M):
			continue
		var on_front := normal.dot(door_normal) > 0.85
		var roll := rng.f()
		match family:
			"cottage":
				if not made_woodpile and not on_front and roll < 0.14 and step > 1.0:
					StructureDressingProps.woodpile(props, doc, frame, rng)
					made_woodpile = true
				elif on_front or roll < 0.5:
					StructureDressingProps.flower_shrub(props, doc, at, rng)
				elif roll < 0.8:
					StructureDressingProps.shrub(props, doc, at, rng)
				else:
					StructureDressingProps.tufts(props, doc, at, rng)
			"house":
				if roll < 0.42:
					StructureDressingProps.shrub(props, doc, at, rng)
				elif roll < 0.62:
					StructureDressingProps.rock(props, doc, at, rng)
				elif roll < 0.8 and on_front:
					StructureDressingProps.flower_shrub(props, doc, at, rng)
				else:
					StructureDressingProps.tufts(props, doc, at, rng)
			_:
				if roll < 0.5:
					StructureDressingProps.shrub(props, doc, at, rng)
				elif roll < 0.75:
					StructureDressingProps.tufts(props, doc, at, rng)
		clusters += 1


## The footprints of the other structures near a building (NEIGHBOUR_RANGE_M) and the document's
## water, to ask whether a point of its yard is free: not under water and not near another house.
class _Clear:
	extends RefCounted
	var _doc: MapDocument
	var _others: Array[PackedVector2Array] = []
	var _courses: Dictionary = {}

	func _init(doc: MapDocument, structure: Structure) -> void:
		_doc = doc
		_others = StructureDressing.neighbours(doc, structure)
		_courses = WaterGeometry.river_courses(
			doc,
			StructureDressing.bounds_of(structure.footprint).grow(StructureDressing.REACH_MAX_M)
		)

	## True when `at` is dry and farther than `margin` from every neighbouring footprint.
	func is_open(at: Vector2, margin: float) -> bool:
		for plan in _others:
			if Geometry2D.is_point_in_polygon(at, plan):
				return false
			for k in plan.size():
				var edge_end := plan[(k + 1) % plan.size()]
				var closest := Geometry2D.get_closest_point_to_segment(at, plan[k], edge_end)
				if at.distance_to(closest) < margin:
					return false
		return not WaterGeometry.is_wet_at(_doc, at, -1, _courses)
