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

const FOLIAGE := [
	Color(0.31, 0.6, 0.22),
	Color(0.42, 0.68, 0.24),
	Color(0.24, 0.55, 0.34),
	Color(0.58, 0.7, 0.26),
]
const BLOOMS := [
	Color(0.96, 0.52, 0.62),
	Color(0.99, 0.84, 0.35),
	Color(0.78, 0.6, 0.95),
	Color(0.98, 0.95, 0.88),
	Color(0.98, 0.58, 0.32),
]
const ROCK := Color(0.62, 0.58, 0.52)
const BARK := Color(0.46, 0.31, 0.18)
const LOG_END := Color(0.82, 0.64, 0.38)
const TERRACOTTA := Color(0.78, 0.42, 0.27)
const STONE_PALE := Color(0.76, 0.71, 0.63)

const ICO_A := 0.5257311
const ICO_B := 0.8506508
const ICO_VERTS := [
	Vector3(-ICO_A, ICO_B, 0.0),
	Vector3(ICO_A, ICO_B, 0.0),
	Vector3(-ICO_A, -ICO_B, 0.0),
	Vector3(ICO_A, -ICO_B, 0.0),
	Vector3(0.0, -ICO_A, ICO_B),
	Vector3(0.0, ICO_A, ICO_B),
	Vector3(0.0, -ICO_A, -ICO_B),
	Vector3(0.0, ICO_A, -ICO_B),
	Vector3(ICO_B, 0.0, -ICO_A),
	Vector3(ICO_B, 0.0, ICO_A),
	Vector3(-ICO_B, 0.0, -ICO_A),
	Vector3(-ICO_B, 0.0, ICO_A),
]
const ICO_FACES := [
	0,
	11,
	5,
	0,
	5,
	1,
	0,
	1,
	7,
	0,
	7,
	10,
	0,
	10,
	11,
	1,
	5,
	9,
	5,
	11,
	4,
	11,
	10,
	2,
	10,
	7,
	6,
	7,
	1,
	8,
	3,
	9,
	4,
	3,
	4,
	2,
	3,
	2,
	6,
	3,
	6,
	8,
	3,
	8,
	9,
	4,
	9,
	5,
	2,
	4,
	11,
	6,
	2,
	10,
	8,
	6,
	7,
	9,
	8,
	1,
]

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
	var rng := _Rng.new(StructurePaint.mix(structure.seed_value, structure.id * 7919 + 101))
	var outward := _outward_sign(plan)
	var door := _door(plan, layout, outward)
	var ground := _Soup.new()
	var props := _Soup.new()
	var earth := _earth_of(family, rng)
	_skirt(ground, doc, plan, outward, door, family, earth, rng)
	_path(ground, props, doc, door, family, earth, rng)
	_plant(props, doc, plan, outward, door, family, rng)
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
	for i in count:
		var frame := _frame_at(plan, length * float(i) / count, outward)
		samples.append(WaterGeometry.ground_at(doc, frame.p + frame.n * KEY_REACH_M))
	var door := _door(plan, null, outward)
	for s in [1.0, 2.5, 4.0, 5.5]:
		samples.append(WaterGeometry.ground_at(doc, door.at + door.out * float(s)))
	return samples


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
static func _earth_of(family: String, rng: _Rng) -> Color:
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
	soup: _Soup,
	doc: MapDocument,
	plan: PackedVector2Array,
	outward: float,
	door: Dictionary,
	family: String,
	earth: Color,
	rng: _Rng
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
		var offsets := [-SKIRT_INSET_M, 0.25, reach * 0.72, reach]
		var alphas := [1.0, 0.97, 0.82, 0.0]
		var ring: Array = []
		for b in 4:
			var at: Vector2 = frame.p + normal * float(offsets[b])
			var tone := 1.0 + (rng.f() - 0.5) * 0.1
			var lighter := earth.lerp(Color(0.8, 0.72, 0.45), 0.25 * float(b) / 3.0)
			var color := Color(
				lighter.r * tone, lighter.g * tone, lighter.b * tone, float(alphas[b])
			)
			ring.append(soup.vertex(_on_ground(doc, at, GROUND_LIFT_M), Vector3.UP, color))
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
	ground: _Soup,
	props: _Soup,
	doc: MapDocument,
	door: Dictionary,
	family: String,
	earth: Color,
	rng: _Rng
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
			color = STONE_PALE.lerp(earth, 0.15)
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
		var mid_i := ground.vertex(_on_ground(doc, centre, GROUND_LIFT_M * 1.6), Vector3.UP, c_mid)
		var left_i := ground.vertex(
			_on_ground(doc, centre + side * half, GROUND_LIFT_M * 1.6), Vector3.UP, c_edge
		)
		var right_i := ground.vertex(
			_on_ground(doc, centre - side * half, GROUND_LIFT_M * 1.6), Vector3.UP, c_edge
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
			_stepping_stones(props, doc, at, out, side, length * 0.9, sway, sway_amp, rng)
		"townhouse":
			_slab(props, doc, at + out * 0.62, out, 1.5, 0.78, 0.07, STONE_PALE, rng)
		_:
			_slab(props, doc, at + out * 0.4, out, 1.0, 0.5, 0.06, ROCK.lerp(earth, 0.4), rng)


static func _stepping_stones(
	props: _Soup,
	doc: MapDocument,
	at: Vector2,
	out: Vector2,
	side: Vector2,
	length: float,
	sway: PackedFloat32Array,
	sway_amp: float,
	rng: _Rng
) -> void:
	var count := clampi(roundi(length / 0.62), 3, 7)
	for i in count:
		var u := float(i) / maxf(1.0, count - 1.0)
		var knot := u * 2.0
		var k0 := mini(int(knot), 1)
		var bend := lerpf(sway[k0], sway[k0 + 1], smoothstep(0.0, 1.0, knot - float(k0)))
		var s := 0.55 + (length - 0.4) * u
		var centre := at + out * s + side * (bend * sway_amp * u + rng.between(-0.1, 0.1))
		var tone := rng.between(0.9, 1.08)
		var color := Color(STONE_PALE.r * tone, STONE_PALE.g * tone, STONE_PALE.b * tone)
		_disc(props, doc, centre, rng.between(0.2, 0.28), 0.05, color, rng)


# --- props ------------------------------------------------------------------------------------


## Plants and objects along the walls, door side left open, drawn by family.
static func _plant(
	props: _Soup,
	doc: MapDocument,
	plan: PackedVector2Array,
	outward: float,
	door: Dictionary,
	family: String,
	rng: _Rng
) -> void:
	var length := _perimeter(plan)
	var s := rng.between(0.0, 1.2)
	var clusters := 0
	var made_woodpile := false
	var door_normal: Vector2 = door.out
	var gap: float = {"cottage": 0.95, "house": 1.25, "townhouse": 2.4}[family]
	if family == "townhouse":
		_planters(props, doc, door, rng)
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
		var on_front := normal.dot(door_normal) > 0.85
		var roll := rng.f()
		match family:
			"cottage":
				if not made_woodpile and not on_front and roll < 0.14 and step > 1.0:
					_woodpile(props, doc, frame, rng)
					made_woodpile = true
				elif on_front or roll < 0.5:
					_flower_shrub(props, doc, at, rng)
				elif roll < 0.8:
					_shrub(props, doc, at, rng)
				else:
					_tufts(props, doc, at, rng)
			"house":
				if roll < 0.42:
					_shrub(props, doc, at, rng)
				elif roll < 0.62:
					_rock(props, doc, at, rng)
				elif roll < 0.8 and on_front:
					_flower_shrub(props, doc, at, rng)
				else:
					_tufts(props, doc, at, rng)
			_:
				if roll < 0.5:
					_shrub(props, doc, at, rng)
				elif roll < 0.75:
					_tufts(props, doc, at, rng)
		clusters += 1


static func _shrub(props: _Soup, doc: MapDocument, at: Vector2, rng: _Rng) -> void:
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())]
	var count := 2 + rng.pick(2)
	for i in count:
		var offset := Vector2(rng.between(-0.22, 0.22), rng.between(-0.22, 0.22))
		var radius := rng.between(0.38, 0.62)
		_blob(
			props, doc, at + offset, radius, radius * rng.between(0.7, 0.95), _vary(green, rng), rng
		)


static func _flower_shrub(props: _Soup, doc: MapDocument, at: Vector2, rng: _Rng) -> void:
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())]
	var bloom: Color = BLOOMS[rng.pick(BLOOMS.size())]
	var second: Color = BLOOMS[rng.pick(BLOOMS.size())]
	var count := 2
	for i in count:
		var offset := Vector2(rng.between(-0.25, 0.25), rng.between(-0.25, 0.25))
		var radius := rng.between(0.26, 0.4)
		var centre := at + offset
		_blob(props, doc, centre, radius, radius * 0.8, _vary(green, rng), rng)
		var base := _height(doc, centre)
		var height := radius * 0.8
		for d in 4:
			var angle := rng.between(0.0, TAU)
			var up := rng.between(0.35, 0.9)
			var flat := sqrt(maxf(0.0, 1.0 - up * up))
			var dot := Vector3(
				centre.x + cos(angle) * flat * radius * 1.02,
				base + height * 0.55 + up * height * 1.02,
				centre.y + sin(angle) * flat * radius * 1.02
			)
			soup_dot(props, dot, 0.07, bloom if d % 2 == 0 else second)


## A small tetrahedron, a bloom.
static func soup_dot(soup: _Soup, centre: Vector3, radius: float, color: Color) -> void:
	var corners := [
		centre + Vector3(0.0, radius, 0.0),
		centre + Vector3(radius, -radius * 0.6, radius * 0.6),
		centre + Vector3(-radius, -radius * 0.6, radius * 0.6),
		centre + Vector3(0.0, -radius * 0.6, -radius),
	]
	var faces := [[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]]
	for face: Array in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot((a + b + c) / 3.0 - centre) < 0.0:
			normal = -normal
		var tint := Color(color.r, color.g, color.b)
		soup.tri(
			soup.vertex(a, normal, tint), soup.vertex(b, normal, tint), soup.vertex(c, normal, tint)
		)


static func _rock(props: _Soup, doc: MapDocument, at: Vector2, rng: _Rng) -> void:
	var count := 1 + rng.pick(2)
	for i in count:
		var radius := rng.between(0.22, 0.42)
		var offset := Vector2(rng.between(-0.35, 0.35), rng.between(-0.35, 0.35)) * float(i)
		var tone := rng.between(0.88, 1.1)
		var color := Color(ROCK.r * tone, ROCK.g * tone * 0.98, ROCK.b * tone * 0.94)
		_blob(props, doc, at + offset, radius, radius * rng.between(0.5, 0.7), color, rng, 0.3)


## A handful of crossed grass blades, light at the tip.
static func _tufts(props: _Soup, doc: MapDocument, at: Vector2, rng: _Rng) -> void:
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())].lerp(Color(0.72, 0.78, 0.3), 0.35)
	var clumps := 2 + rng.pick(2)
	for c in clumps:
		var base := at + Vector2(rng.between(-0.35, 0.35), rng.between(-0.35, 0.35))
		var y := _height(doc, base) - 0.02
		for b in 5:
			var angle := rng.between(0.0, TAU)
			var lean := Vector2(cos(angle), sin(angle)) * rng.between(0.05, 0.2)
			var half := Vector2(-sin(angle), cos(angle)) * 0.045
			var height := rng.between(0.35, 0.65)
			var left := soup_vertex(
				props, Vector3(base.x - half.x, y, base.y - half.y), green.darkened(0.25)
			)
			var right := soup_vertex(
				props, Vector3(base.x + half.x, y, base.y + half.y), green.darkened(0.25)
			)
			var tip := soup_vertex(
				props, Vector3(base.x + lean.x, y + height, base.y + lean.y), green.lightened(0.18)
			)
			props.tri(left, right, tip)


static func soup_vertex(soup: _Soup, position: Vector3, color: Color) -> int:
	return soup.vertex(position, Vector3.UP, color)


## Terracotta planters either side of the door with a green dome and blooms.
static func _planters(props: _Soup, doc: MapDocument, door: Dictionary, rng: _Rng) -> void:
	var out: Vector2 = door.out
	var side := out.orthogonal()
	var bloom: Color = BLOOMS[rng.pick(BLOOMS.size())]
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())]
	for sign_value in [-1.0, 1.0]:
		if rng.chance(0.12):
			continue
		var at: Vector2 = door.at + out * 0.38 + side * 1.0 * float(sign_value)
		_slab(props, doc, at, out, 0.36, 0.36, 0.34, TERRACOTTA, rng)
		var top := _height(doc, at) + 0.3
		_blob_at(props, Vector3(at.x, top + 0.08, at.y), 0.26, 0.2, _vary(green, rng), rng)
		for d in 3:
			var jitter := Vector3(rng.between(-0.15, 0.15), 0.0, rng.between(-0.15, 0.15))
			soup_dot(props, Vector3(at.x, top + 0.26, at.y) + jitter, 0.06, bloom)


## A stack of logs against a wall: a dark block with pale log ends on its face.
static func _woodpile(props: _Soup, doc: MapDocument, frame: Dictionary, rng: _Rng) -> void:
	var n: Vector2 = frame.n
	var t: Vector2 = frame.t
	var at: Vector2 = frame.p + n * 0.38
	_slab(props, doc, at, n, 1.0, 0.4, 0.62, BARK, rng)
	var base := _height(doc, at)
	var face := at + n * 0.2 + n * 0.005
	for row in 2:
		for col in 3:
			var centre := face + t * (float(col) - 1.0) * 0.28
			var y := base + 0.15 + float(row) * 0.3
			_end_disc(
				props,
				Vector3(centre.x, y, centre.y),
				Vector3(n.x, 0.0, n.y),
				t,
				0.115,
				LOG_END,
				rng
			)


# --- shapes ------------------------------------------------------------------------------------


static func _on_ground(doc: MapDocument, at: Vector2, lift: float) -> Vector3:
	return Vector3(at.x, _height(doc, at) + lift, at.y)


## The ground's height at `at` on the triangles the terrain mesh is drawn with (the bilinear
## WaterGeometry.ground_at can sit a few centimetres off them on bumpy ground, which would bury a
## patch laid a hand's breadth above it).
static func _height(doc: MapDocument, at: Vector2) -> float:
	return ScatterGenerator.triangle_height(
		doc.heights, doc.samples_x(), doc.samples_z(), doc.world_to_sample(at)
	)


static func _vary(color: Color, rng: _Rng) -> Color:
	var tone := rng.between(0.9, 1.1)
	return Color(color.r * tone, color.g * tone, color.b * tone * rng.between(0.95, 1.05))


## A squashed, jittered icosahedron part sunk in the ground: a painted bush or boulder. Vertex
## colour darkens toward the ground and warms toward the top; `sink` is the share of its height
## below the ground (0.3 for a bush, 0.3 for a rock).
static func _blob(
	soup: _Soup,
	doc: MapDocument,
	at: Vector2,
	rx: float,
	ry: float,
	color: Color,
	rng: _Rng,
	sink: float = 0.3
) -> void:
	var ground := _height(doc, at)
	_blob_at(soup, Vector3(at.x, ground + ry * (1.0 - 2.0 * sink), at.y), rx, ry, color, rng)


static func _blob_at(
	soup: _Soup, centre: Vector3, rx: float, ry: float, color: Color, rng: _Rng
) -> void:
	var spin := rng.between(0.0, TAU)
	var cs := cos(spin)
	var sn := sin(spin)
	var indices := PackedInt32Array()
	for v: Vector3 in ICO_VERTS:
		var d := Vector3(v.x * cs - v.z * sn, v.y, v.x * sn + v.z * cs)
		var wobble := rng.between(0.88, 1.12)
		var position := centre + Vector3(d.x * rx, d.y * ry, d.z * rx) * wobble
		var normal := Vector3(d.x / rx, d.y / ry, d.z / rx).normalized()
		var up := d.y * 0.5 + 0.5
		var shade := lerpf(0.8, 1.2, up)
		var tint := Color(
			color.r * shade * (0.96 + 0.1 * up), color.g * shade, color.b * shade * (1.0 - 0.1 * up)
		)
		indices.append(soup.vertex(position, normal, tint))
	for f in range(0, ICO_FACES.size(), 3):
		soup.tri(indices[ICO_FACES[f]], indices[ICO_FACES[f + 1]], indices[ICO_FACES[f + 2]])


## A flat hexagon `lift` above the ground, following it (a stepping stone).
static func _disc(
	soup: _Soup, doc: MapDocument, at: Vector2, radius: float, lift: float, color: Color, rng: _Rng
) -> void:
	var spin := rng.between(0.0, TAU)
	var middle := soup.vertex(_on_ground(doc, at, lift), Vector3.UP, color.lightened(0.05))
	var ring := PackedInt32Array()
	for k in 6:
		var angle := spin + TAU * float(k) / 6.0
		var p := at + Vector2(cos(angle), sin(angle)) * radius * rng.between(0.88, 1.08)
		ring.append(soup.vertex(_on_ground(doc, p, lift), Vector3.UP, color.darkened(0.06)))
	for k in 6:
		soup.tri(middle, ring[k], ring[(k + 1) % 6])


## A log end on a vertical face: a hexagon at `centre` facing `normal`, spanned by `across`.
static func _end_disc(
	soup: _Soup,
	centre: Vector3,
	normal: Vector3,
	across: Vector2,
	radius: float,
	color: Color,
	rng: _Rng
) -> void:
	var u := Vector3(across.x, 0.0, across.y)
	var middle := soup.vertex(centre, normal, color.lightened(0.08))
	var ring := PackedInt32Array()
	for k in 6:
		var angle := TAU * float(k) / 6.0
		var p := centre + (u * cos(angle) + Vector3.UP * sin(angle)) * radius
		ring.append(soup.vertex(p, normal, _vary(color, rng).darkened(0.05)))
	for k in 6:
		soup.tri(middle, ring[k], ring[(k + 1) % 6])


## A box standing on the ground at `at`, `size_along` wide across `facing`'s orthogonal and
## `size_out` deep along `facing`, `height` tall, flat shaded: a step, a planter, a woodpile.
static func _slab(
	soup: _Soup,
	doc: MapDocument,
	at: Vector2,
	facing: Vector2,
	size_along: float,
	size_out: float,
	height: float,
	color: Color,
	rng: _Rng
) -> void:
	var f := facing.normalized()
	var s := f.orthogonal()
	var hs := size_along * 0.5
	var hf := size_out * 0.5
	var corners := [
		at - s * hs - f * hf, at + s * hs - f * hf, at + s * hs + f * hf, at - s * hs + f * hf
	]
	var low := INF
	for c: Vector2 in corners:
		low = minf(low, _height(doc, c))
	var bottom := low - 0.06
	var top := low + height
	var tone := rng.between(0.94, 1.06)
	var base := Color(color.r * tone, color.g * tone, color.b * tone)
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var normal2 := (b - a).orthogonal().normalized()
		var normal := Vector3(normal2.x, 0.0, normal2.y)
		if normal2.dot(a - at) < 0.0:
			normal = -normal
		var shade := 0.82 + 0.12 * float(k % 2)
		var side_color := Color(base.r * shade, base.g * shade, base.b * shade)
		var i0 := soup.vertex(Vector3(a.x, bottom, a.y), normal, side_color)
		var i1 := soup.vertex(Vector3(b.x, bottom, b.y), normal, side_color)
		var i2 := soup.vertex(Vector3(b.x, top, b.y), normal, side_color)
		var i3 := soup.vertex(Vector3(a.x, top, a.y), normal, side_color)
		soup.tri(i0, i1, i2)
		soup.tri(i0, i2, i3)
	var lid := Color(base.r * 1.08, base.g * 1.08, base.b * 1.08)
	var t0 := soup.vertex(Vector3(corners[0].x, top, corners[0].y), Vector3.UP, lid)
	var t1 := soup.vertex(Vector3(corners[1].x, top, corners[1].y), Vector3.UP, lid)
	var t2 := soup.vertex(Vector3(corners[2].x, top, corners[2].y), Vector3.UP, lid)
	var t3 := soup.vertex(Vector3(corners[3].x, top, corners[3].y), Vector3.UP, lid)
	soup.tri(t0, t1, t2)
	soup.tri(t0, t2, t3)


## The mesh arrays pieces are added to (vertex, normal, colour, index).
class _Soup:
	extends RefCounted
	var _vertices := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()

	func vertex(position: Vector3, normal: Vector3, color: Color) -> int:
		_vertices.append(
			Vector3(
				snappedf(position.x, 0.005),
				snappedf(position.y, 0.005),
				snappedf(position.z, 0.005)
			)
		)
		_normals.append(normal)
		_colors.append(color)
		return _vertices.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		_indices.append_array(PackedInt32Array([a, b, c]))

	func triangles() -> int:
		return _indices.size() / 3

	## {} when nothing was added.
	func arrays() -> Dictionary:
		if _indices.is_empty():
			return {}
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		return {"arrays": arrays}


## An integer-hash random stream (StructurePaint.mix): the same on every platform.
class _Rng:
	extends RefCounted
	var _seed := 0
	var _count := 0

	func _init(seed_value: int) -> void:
		_seed = seed_value

	func f() -> float:
		_count += 1
		return StructurePaint.unit(StructurePaint.mix(_seed, _count))

	func between(low: float, high: float) -> float:
		return lerpf(low, high, f())

	func chance(p: float) -> bool:
		return f() < p

	func pick(count: int) -> int:
		return mini(int(f() * count), count - 1)
