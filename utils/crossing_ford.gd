class_name CrossingFord
extends RefCounted

## The ford's geometry (Crossing.Kind.FORD, phase 4d, P4d-2), pure and worker-safe like
## CrossingGeometry, whose build_one() calls build() with the meshes to fill and which keeps
## the shared pieces (point(), rng_for(), the mesh builder, the stone builder stone()).
## Summary: docs/systems/crossings.md.
##
## A ford is derived geometry over the document's own bed, no height edit: a gravel bar laid
## across the channel whose crest stands FORD_DEPTH_M (CrossingPlacement) under the water, so
## a token walks across ankle deep and is never hidden, with gravel landings on both banks
## and a few marker stones breaking the surface along the downstream edge. The P4d-0 probe
## showed what a bare submerged bar reads as: one uniform pale wash with no edges at 0.2 m
## down, nothing at 0.35 m, and the palette gravel at full albedo a smooth pale slab against
## the dark bed. So the cues are the stones (each one breaking the surface takes the water
## shader's edge foam by itself), the bar's own surface showing through the water (its vertex
## colour darkened as wet, WET_SHADE at the crest), and the landings leading into the water.
## Painterly: a few bold parts, no pebble detail.
##
## Frame as CrossingGeometry's: u along the span from the start anchor, v across it (left of
## the start-to-end direction), y up. The bar is a grid sampled every STEP_M along u from
## LANDING_M before the start anchor to LANDING_M past the end one, ACROSS rows across the
## width. At each sample the ground g (WaterGeometry.ground_at) and the water level w
## (WaterGeometry.level_at with the river courses; DRY on the banks) give the top:
##   wet (g < w): the crest c = w - FORD_DEPTH_M where the bed lies below it, with NOISE_M of
##     height noise, falling to the bed over the outer SHOULDER_M of each side (a smooth
##     shoulder); where the bed is already at or above the crest (a shallow edge) the gravel
##     is a PAD_M skin over it; never above w - SURFACE_CLEAR_M (nor under the bed, which the
##     clamp respects where the bed itself is that shallow);
##   dry (the landings): the ground plus PAD_M so the gravel shows on the bank, fading to the
##     ground over the last LANDING_FADE_M of the landing and over the shoulders.
## Only the outermost rim (the shoulders' feet and the landings' ends) is sunk RIM_SINK_M
## under the ground, so the terrain hides the seam: the probe found a coplanar strip on the
## grass draws as a pale rectangle, a raised pad with a feathered edge does not. Normals are
## smooth (summed from the faces), the winding is PlaneMesh's (clockwise seen from above; the
## probe's first build was wound the other way and culled from above). Vertex colour runs
## from DRY_SHADE on the landings to WET_SHADE at the crest by the depth of water over it,
## with a damp tide-line where a landing meets the water and END_SHADE at its far end.
##
## Marker stones: STONES_MIN..STONES_MAX by the width (one per STONE_PER_M), STONE_M across,
## standing STONE_EDGE_M inside the downstream edge of the bar (downstream: the side the
## river's course flows to at mid-span, flow_at(); the left side when no flow tells), centred
## on the wet run along that edge and STONE_END_GAP_M inside its ends, one stride (the
## document's cell) apart or closer on a narrow stream (never under STONE_MIN_PITCH_M, so a
## stone may stand on the bank's edge there), their tops STONE_ABOVE_M over the water (or
## STONE_ABOVE_GROUND_M over the ground where that is higher), built by
## CrossingGeometry.stone() so they match the stepping stones and take the palette's moss by
## the node's rule. Collision is the bar's and the stones' own triangles (build_one).

## Spacing of the bar's samples along the span and its vertex count across the width.
const STEP_M := 0.25
const ACROSS := 7
## The gravel landing reaches this far past each anchor, fading to the ground over the last
## LANDING_FADE_M of it.
const LANDING_M := 1.2
const LANDING_FADE_M := 0.4
## The bar's sides fall from the crest to the bed over this much of each side.
const SHOULDER_M := 0.6
## Height noise on the crest.
const NOISE_M := 0.03
## The gravel skin over ground it does not rise from (the landings, a shallow edge).
const PAD_M := 0.03
## The rim (shoulder feet, landing ends) is sunk this far under the ground.
const RIM_SINK_M := 0.02
## No gravel vertex rises above the water level minus this.
const SURFACE_CLEAR_M := 0.05
## Marker stones: count by width, size across, where they stand.
const STONES_MIN := 3
const STONES_MAX := 5
const STONE_PER_M := 0.8
const STONE_M := Vector2(0.52, 0.6)
const STONE_ABOVE_M := 0.12
const STONE_EDGE_M := 0.1
const STONE_END_GAP_M := 0.3
const STONE_MIN_PITCH_M := 0.55
## Spacing of the walk that finds the wet run along the stones' line.
const STONE_WALK_M := 0.1
## Vertex shades: the dry landing, the crest under the water, the landing's far end (toward
## the ground's tone, so the pad has no hard pale edge). Bank within DAMP_M over the water
## level shades DAMP_SHARE of the way to wet: the tide-line where the landing meets the water.
const DRY_SHADE := 1.0
const WET_SHADE := 0.5
const END_SHADE := 0.85
const DAMP_M := 0.12
const DAMP_SHARE := 0.7


## Fills `gravel` (the bar and its landings, one smooth grid) and `stone` (the marker
## stones) for `crossing` over `doc`.
static func build(
	doc: MapDocument,
	crossing: Crossing,
	gravel: CrossingGeometry._Mesh,
	stone: CrossingGeometry._Mesh
) -> void:
	var span := crossing.span_m()
	var half := crossing.width_m * 0.5
	var courses := WaterGeometry.river_courses(
		doc, Rect2(crossing.start, Vector2.ZERO).expand(crossing.end).grow(half + LANDING_M + 2.0)
	)
	var rng := CrossingGeometry.rng_for(doc, crossing)
	_bar(doc, crossing, courses, rng, gravel)
	for spec in stone_layout(doc, crossing, courses):
		CrossingGeometry.stone(spec, stone)


## The unit direction the water flows at map point `p`: the course direction of the river
## whose area holds `p` (the highest level among them), Vector2.ZERO over a pond or dry
## ground. `courses` as WaterGeometry.level_at. Pure.
static func flow_at(doc: MapDocument, p: Vector2, courses: Dictionary = {}) -> Vector2:
	var best := WaterGeometry.DRY
	var flow := Vector2.ZERO
	for body in doc.water_bodies:
		if not body.is_river() or body.level_m <= best:
			continue
		var course: Array = (
			courses[body.id] if courses.has(body.id) else WaterGeometry.river_course(body)
		)
		if course.is_empty():
			continue
		var points: PackedVector2Array = course[0]
		var near := WaterGeometry.nearest_on_polyline(points, p)
		if near.y < 0:
			continue
		if (
			near.x
			<= WaterGeometry.width_at(course[1], int(near.y), near.z) + WaterGeometry.RIVER_BANK_M
		):
			best = body.level_m
			flow = (points[int(near.y) + 1] - points[int(near.y)]).normalized()
	return flow


## Where `crossing`'s marker stones stand, in CrossingGeometry.stone_layout()'s spec shape
## ({"at", "radius", "aspect", "yaw", "top", "bed", "seed"}; see the header). Pure and
## deterministic; `courses` as WaterGeometry.level_at (the rivers near the crossing).
static func stone_layout(
	doc: MapDocument, crossing: Crossing, courses: Dictionary = {}
) -> Array[Dictionary]:
	var stones: Array[Dictionary] = []
	var span := crossing.span_m()
	if span <= 0.0:
		return stones
	var half := crossing.width_m * 0.5
	# A generator of their own, so the stones never shift when the bar's sampling changes.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([doc.map_seed, crossing.id, crossing.kind, "stones"])
	var d := crossing.direction()
	var left := Vector2(-d.y, d.x)
	var mid := CrossingGeometry.point(crossing, span * 0.5, 0.0, 0.0)
	var flow := flow_at(doc, Vector2(mid.x, mid.z), courses)
	var side := -1.0 if left.dot(flow) < -0.2 else 1.0
	var v := side * (half - STONE_EDGE_M)
	# The wet run along the stones' line: they stand in the water, not on the landings.
	var wet := Vector2(INF, -INF)
	var walk := maxi(ceili(span / STONE_WALK_M), 1)
	for k in walk + 1:
		var u := span * k / walk
		var p := CrossingGeometry.point(crossing, u, v, 0.0)
		if WaterGeometry.is_wet_at(doc, Vector2(p.x, p.z), -1, courses):
			wet.x = minf(wet.x, u)
			wet.y = maxf(wet.y, u)
	if wet.x > wet.y:
		wet = Vector2(0.0, span)
	var count := clampi(roundi(crossing.width_m / STONE_PER_M), STONES_MIN, STONES_MAX)
	var room := maxf(wet.y - wet.x - 2.0 * STONE_END_GAP_M, 0.0)
	var pitch := clampf(room / maxf(count - 1, 1), STONE_MIN_PITCH_M, doc.cell_size_m)
	var centre := (wet.x + wet.y) * 0.5
	for k in count:
		var u := centre + (k - (count - 1) * 0.5) * pitch + rng.randf_range(-0.05, 0.05)
		var p := CrossingGeometry.point(crossing, u, v + rng.randf_range(-0.04, 0.04), 0.0)
		var at := Vector2(p.x, p.z)
		var bed := WaterGeometry.ground_at(doc, at)
		var water := WaterGeometry.level_at(doc, at, -1, courses)
		if water == WaterGeometry.DRY:
			water = crossing.levels.y + CrossingPlacement.FORD_DEPTH_M
		var top := maxf(water + STONE_ABOVE_M, bed + CrossingGeometry.STONE_ABOVE_GROUND_M)
		var across := rng.randf_range(STONE_M.x, STONE_M.y)
		(
			stones
			. append(
				{
					"at": at,
					"radius": across * 0.5,
					"aspect": rng.randf_range(1.0, 1.3),
					"yaw": atan2(flow.y, flow.x) + rng.randf_range(-0.5, 0.5),
					"top": top + rng.randf_range(-0.01, 0.01),
					"bed": bed,
					"seed": rng.randi(),
				}
			)
		)
	return stones


# --- the bar ---------------------------------------------------------------------------------


## The bar and its landings as one grid (see the header).
static func _bar(
	doc: MapDocument,
	crossing: Crossing,
	courses: Dictionary,
	rng: RandomNumberGenerator,
	gravel: CrossingGeometry._Mesh
) -> void:
	var span := crossing.span_m()
	var half := crossing.width_m * 0.5
	var length := span + 2.0 * LANDING_M
	var rows := ceili(length / STEP_M) + 1
	var step := length / (rows - 1)
	var d := crossing.direction()
	var tangent := Vector3(d.x, 0.0, d.y)
	var base := gravel.vertices.size()
	for i in rows:
		var u := -LANDING_M + i * step
		var along := _smooth(
			clampf(minf(u + LANDING_M, span + LANDING_M - u) / LANDING_FADE_M, 0.0, 1.0)
		)
		for j in ACROSS:
			var v := (float(j) / (ACROSS - 1) - 0.5) * crossing.width_m
			var shoulder := _smooth(clampf((half - absf(v)) / SHOULDER_M, 0.0, 1.0))
			var p := CrossingGeometry.point(crossing, u, v, 0.0)
			var xz := Vector2(p.x, p.z)
			var g := WaterGeometry.ground_at(doc, xz)
			var w := WaterGeometry.level_at(doc, xz, -1, courses)
			var noise := rng.randf_range(-NOISE_M, NOISE_M)
			var sample := _top(g, w, shoulder, along, noise)
			var shade: float = sample.y
			gravel.vertices.append(Vector3(p.x, sample.x, p.z))
			gravel.normals.append(Vector3.UP)
			gravel.uvs.append(Vector2.ZERO)
			gravel.colors.append(Color(shade, shade, shade))
			gravel.tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, 1.0]))
	# Quads wound as PlaneMesh winds: (here, next along, next across) is clockwise from above.
	for i in rows - 1:
		for j in ACROSS - 1:
			var a := base + i * ACROSS + j
			var b := a + 1
			var c := a + ACROSS
			gravel.indices.append_array(PackedInt32Array([a, c, b, b, c, c + 1]))
	_smooth_normals(gravel, base)


## The top (x) and shade (y) of one sample over ground `g` under water level `w` (DRY on a
## bank), `shoulder` 0..1 from the bar's edge to its body, `along` 0..1 from the landing's end
## inward, `noise` the crest's height noise.
static func _top(g: float, w: float, shoulder: float, along: float, noise: float) -> Vector2:
	var wet := w != WaterGeometry.DRY and g < w
	var feather := shoulder * along
	if not wet:
		var damp := 0.0
		if w != WaterGeometry.DRY:
			damp = clampf(1.0 - (g - w) / DAMP_M, 0.0, 1.0) * DAMP_SHARE
		var shade := lerpf(END_SHADE, lerpf(DRY_SHADE, WET_SHADE, damp), along)
		return Vector2(g + lerpf(-RIM_SINK_M, PAD_M, feather), shade)
	if feather <= 0.0:
		return Vector2(g - RIM_SINK_M, lerpf(DRY_SHADE, WET_SHADE, 0.5))
	var crest := w - CrossingPlacement.FORD_DEPTH_M
	var raise := maxf(maxf(crest - g, 0.0) * shoulder + noise * shoulder, PAD_M * shoulder)
	var top := minf(g + raise, maxf(g, w - SURFACE_CLEAR_M))
	var wetness := clampf((w - top) / CrossingPlacement.FORD_DEPTH_M, 0.0, 1.0)
	return Vector2(top, lerpf(DRY_SHADE, WET_SHADE, wetness))


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Replaces the normals of the vertices from `base` on with the sum of their faces' normals.
static func _smooth_normals(mesh: CrossingGeometry._Mesh, base: int) -> void:
	var sums := PackedVector3Array()
	sums.resize(mesh.vertices.size() - base)
	sums.fill(Vector3.ZERO)
	var indices := mesh.indices
	var first := 0
	while first < indices.size() and indices[first] < base:
		first += 3
	for t in range(first, indices.size(), 3):
		var a := mesh.vertices[indices[t]]
		var b := mesh.vertices[indices[t + 1]]
		var c := mesh.vertices[indices[t + 2]]
		# The up-pointing normal of a clockwise face: cross(C - A, B - A).
		var n := (c - a).cross(b - a)
		for k in 3:
			sums[indices[t + k] - base] += n
	for k in sums.size():
		var n := sums[k]
		mesh.normals[base + k] = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
