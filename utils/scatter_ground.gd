class_name ScatterGround
extends RefCounted

## What the ground of an authored map lets grow, for ScatterGenerator.document_fields (phase
## 3, P3-4 and P3-6): plants respect the automatic dressing and the painted surfaces the
## ground shader draws, through the same formulas (TerrainRules, the shader's CPU twin).
##   - On automatic rock nothing grows: density times (1 - the rock's share).
##   - Under a painted built surface (role "built": a road, a courtyard) nothing grows, nor
##     on painted rock (role "cliff"): the paved share (the painted weights shaped as the
##     shader shapes them) clears plants through a steep response (PAVED_CLEAR_*).
##   - On scree, rock species gather (density times 1 + SCREE_ROCK_BOOST * scree share,
##     capped at full) and everything else thins (times 1 - SCREE_THIN * scree share), so
##     boulders collect at a cliff's foot, per the user's cliff decision.
## The shares are those the shader draws (TerrainRules.compose_paint): painted ground and
## built surfaces cover walkable ground only and yield to the automatic rock on faces (the
## user's 2026-09-27 cliff-face decision), so plants stay off a face even where a path was
## painted across it, and a road painted over flat ground clears it. Painted cliff-role rock
## keeps its weight anywhere. What grows is 1 minus the rock's share minus the paved
## response, at least 0.
##
## Legibility (P3-7). Terraces under forest: trees (ROLE_TREE) keep back from tier faces and
## lips, and shrubs (ROLE_SHRUB) a little, so a GM sees the rock step and the edge of each
## top instead of an unbroken canopy (the rock rule already keeps plants off the face itself,
## but a trunk a metre from the lip spreads its crown over the whole step). The measure is
## face proximity: the steepness nearby (TerrainRules' 1.5 m box mean of the slope tail)
## box-averaged again over FACE_NEAR_RADIUS_M, so it fades out smoothly about 3.5 m from a
## face and grows where faces gather (a corner, a stack of tiers). Callers pass the species'
## role (role_of) with each point. Pure statics.

## Species rule kind that gathers at cliff feet.
const ROCK_KIND := "rock"
## What a species is to the ground rules (role_of): ground cover, a rock, a tree or a shrub.
const ROLE_COVER := 0
const ROLE_ROCK := 1
const ROLE_TREE := 2
const ROLE_SHRUB := 3
## Face proximity: half-width (metres) of the second box mean over the steepness nearby, and
## the smoothstep over which it clears trees and shrubs. Along a straight tier face the
## proximity is about 0.14 at the face, 0.08 two metres out and 0 by 3.7 m: trees are gone
## within about two metres of a face and thin out to three; shrubs only within about one.
## Judged at the game camera on forest terraces (P3-7 renders).
const FACE_NEAR_RADIUS_M := 2.0
const TREE_FACE_START := 0.02
const TREE_FACE_FULL := 0.08
const SHRUB_FACE_START := 0.08
const SHRUB_FACE_FULL := 0.13
## Judged by eye at the game camera (P3-4 renders): a stronger boost lines every tier foot
## with a row of boulders.
const SCREE_ROCK_BOOST := 0.8
const SCREE_THIN := 0.5
## How plants answer paving (built paint and painted rock): cleared by
## smoothstep(PAVED_CLEAR_START, PAVED_CLEAR_FULL, paved share), not in proportion. The
## ground shader height-blends a 0.75 road so it reads as road with a few grass blades, and
## a linear response left a quarter of the tall grass standing in its middle (P3-6 look
## pass), and tall grass rooted on the shoulder (0.1..0.5 kept most of it) hid a metre-wide
## path from the game camera; the faintest fringe of a stroke still keeps its plants, so a
## path's edge stays soft.
const PAVED_CLEAR_START := 0.05
const PAVED_CLEAR_FULL := 0.4


## The role (ROLE_*) of a species rule for the ground rules: rock kind, then by size class
## (large: tree, medium: shrub), else ground cover.
static func role_of(rule: Dictionary) -> int:
	if rule.get("kind", "") == ROCK_KIND:
		return ROLE_ROCK
	match rule.get("size_class", ""):
		"large":
			return ROLE_TREE
		"medium":
			return ROLE_SHRUB
	return ROLE_COVER


## A sampler for `doc`: Callable(Vector2 map XZ, int role) -> Vector3(open, cliff share,
## scree share), open = 1 - automatic rock - the paved response (clamped at 0), times what
## the role's legibility rule leaves (see the header; ROLE_COVER and ROLE_ROCK have none).
## The rule fields (curvature, steepness nearby, face proximity) and the painted weights are
## decoded for the samples of `samples` (grid rect, plus one sample around it) only;
## `built_surfaces` and `cliff_surfaces` name the palette surfaces with role "built" and
## "cliff". `heights` is the document's heights (or a flat field of the grid's size).
static func sampler(
	doc: MapDocument,
	heights: PackedFloat32Array,
	samples: Rect2i,
	built_surfaces: PackedStringArray,
	cliff_surfaces: PackedStringArray = PackedStringArray()
) -> Callable:
	var count := doc.sample_count()
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var seed_value := doc.map_seed & 0x7FFFFFFF
	var curvature := PackedFloat32Array()
	var steep := PackedFloat32Array()
	curvature.resize(count)
	steep.resize(count)
	# One more sample around the rect: a point near its edge interpolates across it.
	var rect := samples.grow(1).intersection(Rect2i(0, 0, columns, rows))
	TerrainRules.store_fields(
		TerrainRules.sample_fields(heights, columns, rows, step, rect), columns, curvature, steep
	)
	var near_face := face_proximity(heights, columns, rows, step, rect)
	var painted := _painted_fields(doc, rect, built_surfaces, cliff_surfaces)
	var painted_total: PackedFloat32Array = painted.total
	var built: PackedFloat32Array = painted.built
	var rock: PackedFloat32Array = painted.rock
	var paints := not painted_total.is_empty()
	return func(p: Vector2, role: int) -> Vector3:
		var s := (p + half) / step
		var n := ScatterGenerator.triangle_normal(heights, columns, rows, s, step)
		var fields := TerrainRules.field_at(curvature, steep, columns, rows, s)
		var y := ScatterGenerator.triangle_height(heights, columns, rows, s)
		var rule := TerrainRules.weights(n.y, fields, p, y, seed_value)
		var built_weight := 0.0
		var held := 0.0
		var yielding := 0.0
		if paints:
			var lookup := (TerrainRules.painted_lookup(p, seed_value) + half) / step
			var total := ScatterGenerator.bilinear(painted_total, columns, rows, lookup)
			if total > 0.0:
				var shaped := TerrainRules.shape_painted(total, p, seed_value)
				var scale := shaped / total
				built_weight = ScatterGenerator.bilinear(built, columns, rows, lookup) * scale
				held = ScatterGenerator.bilinear(rock, columns, rows, lookup) * scale
				yielding = maxf(shaped - held, 0.0)
		var shares := TerrainRules.compose_paint(yielding, held, rule)
		var paved := built_weight * shares.w + held
		var open := 1.0 - shares.y - smoothstep(PAVED_CLEAR_START, PAVED_CLEAR_FULL, paved)
		if role == ROLE_TREE or role == ROLE_SHRUB:
			var face := ScatterGenerator.bilinear(near_face, columns, rows, s)
			if role == ROLE_TREE:
				open *= 1.0 - smoothstep(TREE_FACE_START, TREE_FACE_FULL, face)
			else:
				open *= 1.0 - smoothstep(SHRUB_FACE_START, SHRUB_FACE_FULL, face)
		return Vector3(maxf(open, 0.0), shares.y, shares.z)


## Face proximity for the samples of `rect` (grid coordinates) as a whole-grid array (zero
## outside `rect`): the steepness nearby (TerrainRules.sample_fields) box-averaged again over
## FACE_NEAR_RADIUS_M, edges replicated. See the header.
static func face_proximity(
	heights: PackedFloat32Array, columns: int, rows: int, step: Vector2, rect: Rect2i
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(columns * rows)
	var grid := Rect2i(0, 0, columns, rows)
	var inner := rect.intersection(grid)
	if not inner.has_area() or heights.size() < columns * rows:
		return out
	var k := maxi(1, roundi(FACE_NEAR_RADIUS_M / maxf(minf(step.x, step.y), 1e-4)))
	# The steepness nearby over the rect grown by the second window (box_mean reads it there).
	var steep := PackedFloat32Array()
	steep.resize(columns * rows)
	var scratch := PackedFloat32Array()
	scratch.resize(columns * rows)
	TerrainRules.store_fields(
		TerrainRules.sample_fields(heights, columns, rows, step, inner.grow(k).intersection(grid)),
		columns,
		scratch,
		steep
	)
	var means := HeightBrush.box_mean(steep, columns, rows, inner, k)
	for z in inner.size.y:
		var row := (inner.position.y + z) * columns + inner.position.x
		for x in inner.size.x:
			out[row + x] = means[z * inner.size.x + x]
	return out


## The painted total, the built weight and the painted rock weight (0..1) per sample of
## `rect` (whole-grid arrays, empty when the document has no painted surfaces).
static func _painted_fields(
	doc: MapDocument,
	rect: Rect2i,
	built_surfaces: PackedStringArray,
	cliff_surfaces: PackedStringArray
) -> Dictionary:
	var count := doc.sample_count()
	var total_field := PackedFloat32Array()
	var built := PackedFloat32Array()
	var rock := PackedFloat32Array()
	if doc.surface_ids.is_empty() or doc.surface_weights.size() != count * MapDocument.MAX_SURFACES:
		return {"total": total_field, "built": built, "rock": rock}
	total_field.resize(count)
	built.resize(count)
	rock.resize(count)
	var built_slots := PackedInt32Array()
	var rock_slots := PackedInt32Array()
	for s in doc.surface_ids.size():
		if built_surfaces.has(doc.surface_ids[s]):
			built_slots.append(s)
		elif cliff_surfaces.has(doc.surface_ids[s]):
			rock_slots.append(s)
	var weights := doc.surface_weights
	var columns := doc.samples_x()
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * columns + x
			var total := 0
			for s in doc.surface_ids.size():
				total += weights[MapDocument.surface_offset(i, s, count)]
			if total == 0:
				continue
			total_field[i] = total / 255.0
			var b := 0
			for s in built_slots:
				b += weights[MapDocument.surface_offset(i, s, count)]
			built[i] = b / 255.0
			var r := 0
			for s in rock_slots:
				r += weights[MapDocument.surface_offset(i, s, count)]
			rock[i] = r / 255.0
	return {"total": total_field, "built": built, "rock": rock}


## Painted density `value` as a species of ground role `role` reads it, given the sampler's
## value `g` for that role: rock_density for ROLE_ROCK, density otherwise.
static func species_density(value: float, g: Vector3, role: int) -> float:
	return rock_density(value, g) if role == ROLE_ROCK else density(value, g)


## Painted density `density` as every species but rock reads it, given a sampler value `g`.
static func density(value: float, g: Vector3) -> float:
	return value * g.x * (1.0 - SCREE_THIN * g.z)


## Painted density as rock species read it, given a sampler value `g`.
static func rock_density(value: float, g: Vector3) -> float:
	return minf(value * (1.0 + SCREE_ROCK_BOOST * g.z), 1.0) * g.x
