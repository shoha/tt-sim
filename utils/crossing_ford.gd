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
##     clamp respects where the bed itself is that shallow). Across the bar the crest holds
##     over the downstream CREST_SHARE of the width and dips CROSS_DROP_M more toward the
##     upstream edge (P4d-4): the water shader's foam is a band of depth a few tenths of a
##     metre deep (the P4d-0 probe: a bar 0.2 m down foamed uniformly, 0.35 m down not at
##     all), so the lip makes a bright line along the downstream edge fading upstream, a
##     riffle with an edge, where a flat bar made one even wash;
##   dry (the landings): the ground plus PAD_M so the gravel shows on the bank, fading to the
##     ground over the last LANDING_FADE_M of the landing and over the shoulders.
## Only the outermost rim (the shoulders' feet and the landings' ends) is sunk RIM_SINK_M
## under the ground, so the terrain hides the seam: the probe found a coplanar strip on the
## grass draws as a pale rectangle, a raised pad with a feathered edge does not. The outline
## is not a rectangle either (P4d-4, the first look's hard-edged pads): past each anchor the
## landing narrows as a rounded tongue to END_WIDTH_SHARE of the bar's width, and each edge
## wanders EDGE_WOBBLE_M along a slow wave, so the pad reads trodden. Normals are smooth
## (summed from the faces), the winding is PlaneMesh's (clockwise seen from above; the
## probe's first build was wound the other way and culled from above). Vertex colour runs
## from DRY_SHADE on the landings to WET_SHADE at the crest by the depth of water over it,
## with a damp tide-line where a landing meets the water, END_SHADE at its far end and
## SIDE_SHADE at its edges.
##
## Marker stones: STONES_MIN..STONES_MAX by the width (one per STONE_PER_M), fewer on a
## stream whose wet run has no room for them STONE_MIN_PITCH_M apart (never under two),
## STONE_M across, standing STONE_EDGE_M inside the downstream edge of the bar (downstream:
## the side the river's course flows to at mid-span, downstream_side(); the left side when
## no flow tells), centred on the wet run along that edge and STONE_END_GAP_M inside its
## ends, one stride (the document's cell) apart or closer on a narrow stream (never under
## STONE_MIN_PITCH_M, so a stone may stand on the bank's edge there), their tops
## STONE_ABOVE_M over the water (or STONE_ABOVE_GROUND_M over the ground where that is
## higher), built by CrossingGeometry.stone() so they match the stepping stones and take the
## palette's moss by the node's rule. Collision is the bar's and the stones' own triangles
## (build_one).

## Spacing of the bar's samples along the span and its vertex count across the width.
const STEP_M := 0.25
const ACROSS := 7
## The gravel landing reaches this far past each anchor, fading to the ground over the last
## LANDING_FADE_M of it, its half-width down to END_WIDTH_SHARE of the bar's at the end.
const LANDING_M := 1.2
const LANDING_FADE_M := 0.4
const END_WIDTH_SHARE := 0.3
## Each edge of the bar wanders this far either way along a wave of this many radians per
## metre (a random phase per edge).
const EDGE_WOBBLE_M := 0.09
const EDGE_WOBBLE_FREQ := 2.7
## The bar's sides fall from the crest to the bed over this much of each side.
const SHOULDER_M := 0.6
## The crest's share of the width from the downstream edge, and how much deeper the bar lies
## at the upstream edge.
const CREST_SHARE := 0.4
const CROSS_DROP_M := 0.12
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
const STONES_NARROW := 2
const STONE_PER_M := 0.8
## Across: 0.52-0.6 read small beside a token and lost on an ankle stream (P4d-4).
const STONE_M := Vector2(0.62, 0.78)
const STONE_ABOVE_M := 0.12
const STONE_EDGE_M := 0.1
const STONE_END_GAP_M := 0.3
const STONE_MIN_PITCH_M := 0.7
## Spacing of the walk that finds the wet run along the stones' line.
const STONE_WALK_M := 0.1
## Vertex shades: the dry landing, the crest under the water, the landing's far end and its
## edges (toward the ground's tone, so the pad has no hard pale edge). Bank within DAMP_M
## over the water level shades DAMP_SHARE of the way to wet: the tide-line where the landing
## meets the water.
const DRY_SHADE := 1.0
const WET_SHADE := 0.58
const END_SHADE := 0.85
const SIDE_SHADE := 0.8
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


## The side of `crossing` (+1: left of its direction, -1: right) the water flows to at
## mid-span, by flow_at(); the left when no flow tells (a pond). Pure.
static func downstream_side(
	doc: MapDocument, crossing: Crossing, courses: Dictionary = {}
) -> float:
	var d := crossing.direction()
	var left := Vector2(-d.y, d.x)
	var mid := CrossingGeometry.point(crossing, crossing.span_m() * 0.5, 0.0, 0.0)
	return -1.0 if left.dot(flow_at(doc, Vector2(mid.x, mid.z), courses)) < -0.2 else 1.0


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
	var mid := CrossingGeometry.point(crossing, span * 0.5, 0.0, 0.0)
	var flow := flow_at(doc, Vector2(mid.x, mid.z), courses)
	var side := downstream_side(doc, crossing, courses)
	var v := side * (half - STONE_EDGE_M)
	# The wet run along the stones' line: they stand in the water, not on the landings.
	var wet := Vector2(INF, -INF)
	var walk := maxi(ceili(span / STONE_WALK_M), 1)
	# WaterGeometry.is_wet_at per point of the walk, in two batches.
	var line := PackedVector2Array()
	line.resize(walk + 1)
	for k in walk + 1:
		var p := CrossingGeometry.point(crossing, span * k / walk, v, 0.0)
		line[k] = Vector2(p.x, p.z)
	if doc.heights.size() == doc.sample_count():
		var all_courses := courses
		if all_courses.is_empty():
			all_courses = WaterGeometry.river_courses(doc)
		var grounds := WaterGeometry.grounds_at(doc, line)
		var levels := WaterGeometry.levels_along(doc, line, all_courses, 8)
		for k in walk + 1:
			if levels[k] != WaterGeometry.DRY and grounds[k] < levels[k]:
				var u := span * k / walk
				wet.x = minf(wet.x, u)
				wet.y = maxf(wet.y, u)
	if wet.x > wet.y:
		wet = Vector2(0.0, span)
	var count := clampi(roundi(crossing.width_m / STONE_PER_M), STONES_MIN, STONES_MAX)
	var room := maxf(wet.y - wet.x - 2.0 * STONE_END_GAP_M, 0.0)
	# A narrow stream takes only the stones its wet run has room for, two at the least.
	count = mini(count, maxi(floori(room / STONE_MIN_PITCH_M) + 1, STONES_NARROW))
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
	var downstream := downstream_side(doc, crossing, courses)
	var phases := Vector2(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	# The samples first (row by row), so the ground and the water under them are read in two
	# batches (WaterGeometry.grounds_at, levels_along: the same values as ground_at and
	# level_at per point, at a fraction of the cost; P4d follow-up, the ford's 5 ms build).
	var count := rows * ACROSS
	var points := PackedVector2Array()
	points.resize(count)
	# Per sample: shoulder, along, cross (64-bit, as the values themselves).
	var shoulders := PackedFloat64Array()
	shoulders.resize(count)
	var alongs := PackedFloat64Array()
	alongs.resize(count)
	var crosses := PackedFloat64Array()
	crosses.resize(count)
	var left := Vector2(-d.y, d.x)
	for i in rows:
		var u := -LANDING_M + i * step
		var along := _smooth(
			clampf(minf(u + LANDING_M, span + LANDING_M - u) / LANDING_FADE_M, 0.0, 1.0)
		)
		# The row's edges: the tongue past an anchor, and each edge's wander.
		var tongue := _tongue(u, span) * half
		var edges := Vector2(
			tongue + EDGE_WOBBLE_M * sin(u * EDGE_WOBBLE_FREQ + phases.x),
			tongue + EDGE_WOBBLE_M * sin(u * EDGE_WOBBLE_FREQ + phases.y)
		)
		for j in ACROSS:
			var v := lerpf(-edges.x, edges.y, float(j) / (ACROSS - 1))
			var edge := edges.x if v < 0.0 else edges.y
			var shoulder := _smooth(clampf((edge - absf(v)) / SHOULDER_M, 0.0, 1.0))
			var cross := clampf((1.0 - downstream * v / maxf(edge, 1e-3)) * 0.5, 0.0, 1.0)
			# CrossingGeometry.point(crossing, u, v, 0.0), inline.
			var k := i * ACROSS + j
			points[k] = crossing.start + d * u + left * v
			shoulders[k] = shoulder
			alongs[k] = along
			crosses[k] = cross
	var grounds := WaterGeometry.grounds_at(doc, points)
	var levels := WaterGeometry.levels_along(doc, points, courses, ACROSS * 4)
	var vertices := PackedVector3Array()
	vertices.resize(count)
	var colors := PackedColorArray()
	colors.resize(count)
	var normals := PackedVector3Array()
	normals.resize(count)
	normals.fill(Vector3.UP)
	var uvs := PackedVector2Array()
	uvs.resize(count)
	uvs.fill(Vector2.ZERO)
	var tangents := PackedFloat32Array()
	tangents.resize(count * 4)
	for k in count:
		var noise := rng.randf_range(-NOISE_M, NOISE_M)
		var sample := _top(grounds[k], levels[k], shoulders[k], alongs[k], noise, crosses[k])
		var shade: float = sample.y
		var xz := points[k]
		vertices[k] = Vector3(xz.x, sample.x, xz.y)
		colors[k] = Color(shade, shade, shade)
		tangents[k * 4] = tangent.x
		tangents[k * 4 + 1] = tangent.y
		tangents[k * 4 + 2] = tangent.z
		tangents[k * 4 + 3] = 1.0
	gravel.vertices.append_array(vertices)
	gravel.normals.append_array(normals)
	gravel.uvs.append_array(uvs)
	gravel.colors.append_array(colors)
	gravel.tangents.append_array(tangents)
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
## inward, `noise` the crest's height noise, `cross` 0..1 from the downstream edge to the
## upstream one.
static func _top(
	g: float, w: float, shoulder: float, along: float, noise: float, cross: float = 0.0
) -> Vector2:
	var wet := w != WaterGeometry.DRY and g < w
	var feather := shoulder * along
	if not wet:
		var damp := 0.0
		if w != WaterGeometry.DRY:
			damp = clampf(1.0 - (g - w) / DAMP_M, 0.0, 1.0) * DAMP_SHARE
		var shade := lerpf(END_SHADE, lerpf(DRY_SHADE, WET_SHADE, damp), along)
		shade *= lerpf(SIDE_SHADE, 1.0, shoulder)
		return Vector2(g + lerpf(-RIM_SINK_M, PAD_M, feather), shade)
	if feather <= 0.0:
		return Vector2(g - RIM_SINK_M, lerpf(DRY_SHADE, WET_SHADE, 0.5))
	var dip := _smooth(clampf((cross - CREST_SHARE) / (1.0 - CREST_SHARE), 0.0, 1.0))
	var crest := w - CrossingPlacement.FORD_DEPTH_M - CROSS_DROP_M * dip
	var raise := maxf(maxf(crest - g, 0.0) * shoulder + noise * shoulder, PAD_M * shoulder)
	var top := minf(g + raise, maxf(g, w - SURFACE_CLEAR_M))
	var wetness := clampf((w - top) / CrossingPlacement.FORD_DEPTH_M, 0.0, 1.0)
	return Vector2(top, lerpf(DRY_SHADE, WET_SHADE, wetness))


## The bar's half-width at `u` as a share of its own: 1 between the anchors, falling as a
## rounded tongue to END_WIDTH_SHARE at the landing's end.
static func _tongue(u: float, span: float) -> float:
	var past := maxf(-u, u - span)
	if past <= 0.0:
		return 1.0
	var t := clampf(past / LANDING_M, 0.0, 1.0)
	return lerpf(END_WIDTH_SHARE, 1.0, sqrt(maxf(1.0 - t * t, 0.0)))


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Replaces the normals of the vertices from `base` on with the sum of their faces' normals.
static func _smooth_normals(mesh: CrossingGeometry._Mesh, base: int) -> void:
	var vertices := mesh.vertices
	var sums := PackedVector3Array()
	sums.resize(vertices.size() - base)
	sums.fill(Vector3.ZERO)
	var indices := mesh.indices
	var first := 0
	while first < indices.size() and indices[first] < base:
		first += 3
	for t in range(first, indices.size(), 3):
		var ia := indices[t]
		var ib := indices[t + 1]
		var ic := indices[t + 2]
		var a := vertices[ia]
		# The up-pointing normal of a clockwise face: cross(C - A, B - A).
		var n := (vertices[ic] - a).cross(vertices[ib] - a)
		sums[ia - base] += n
		sums[ib - base] += n
		sums[ic - base] += n
	var normals := mesh.normals.duplicate()
	for k in sums.size():
		var n := sums[k]
		normals[base + k] = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
	mesh.normals = normals
