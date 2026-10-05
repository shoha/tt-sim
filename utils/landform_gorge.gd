class_name LandformGorge
extends RefCounted

## The Gorge starting landform (P5-2; see StartingLandform and LandformRecipes for the frame
## every recipe shares). A ravine one or two tiers deep (TWO_TIERS_CHANCE; two only on a map
## TWO_TIERS_MIN_EXTENT_M wide, 150 ft and up) winding across the map: its axis is one of the
## six headings within 45 degrees of the x axis (HEADINGS: the ravine crosses the view, so
## its far wall and its floor face the camera, which looks along -z pitched 21.6 degrees
## down and sees only the near rim of a ravine running along the view) through a point off
## the centre, bent once by BEND_DEG and, half the time, bent back further on
## (SECOND_BEND_CHANCE), and the ground follows the polyline's distance field cut downward
## with HeightBrush.tier_goal from the rim at the base height (the Sculpt tool's own tier
## cut: the rim rounds down with the lip rule's grass on top, a 66 degree rock face drops,
## the floor is flat). The flat floor is FLOOR_M wide by the seed, TWO_TIER_FLOOR_EXTRA_M
## wider when two tiers deep (the rims stand a face further out); the floor tilts FALL_M
## along its length so a stream down it steps in riffles. The seed draws: an ankle stream
## along the floor (STREAM_CHANCE; hugging the far wall where the ravine crosses the view,
## STREAM_FAR_SHARE, so the near rim does not hide it; the walls are put back where its bank
## reach would have slumped them, StartingLandform.restore_outside), else a dry wash of the
## biome's scree surface along it; given a stream, a stone arch over the ravine near its
## middle (ARCH_CHANCE), standing on the rims ARCH_FOOT_M back from the lip
## (StartingLandform.span_crossing: the Bridge tool's waterline anchors would stand on the
## floor beside the stream). The stage is on the rim on the camera-facing side (+z) by the
## arch, or by the middle of the ravine.

const TWO_TIERS_CHANCE := 0.5
## Two tiers only on a map at least this wide (150 ft; P5-4): on a 100 ft map a two-tier
## ravine's walls and floor took half the ground.
const TWO_TIERS_MIN_EXTENT_M := 45.0
## The heading indices (45 degree steps from +x) the frame draws from: within 45 degrees of
## the x axis (P5-4; see the header).
const HEADINGS: Array[int] = [0, 1, 3, 4, 5, 7]
const SECOND_BEND_CHANCE := 0.5
const STREAM_CHANCE := 0.7
const ARCH_CHANCE := 0.4
## The ravine's rim-to-rim width range, its floor's fall along the map at 150 ft, how far
## the axis may sit off the centre (a share of the half extent), the bend's turn, where the
## first bend lies along the axis from the centre's foot and how far on the second (shares
## of the half extent).
const FLOOR_M := Vector2(6.0, 9.0)
## A two-tier ravine's floor is this much wider: the camera's 21.6 degree pitch hides
## 7.6 m of floor behind the near rim of a 3 m wall (P5-2 look: a 6 m floor never showed).
const TWO_TIER_FLOOR_EXTRA_M := 3.0
const FALL_M := 1.5
const OFFSET_SHARE := 0.15
const BEND_DEG := Vector2(15.0, 35.0)
const FIRST_BEND_SHARE := Vector2(-0.25, 0.1)
const SECOND_BEND_SHARE := Vector2(0.3, 0.5)
## The stream: ankle half-width, control points, wobble as a share of the floor's flat
## half-width.
const STREAM_HALF_WIDTH_M := 0.55
const STREAM_SPACING_M := 3.0
const STREAM_WOBBLE_SHARE := 0.2
## The stream runs this share of the floor's half-width toward the far wall (-z) where the
## ravine runs across the view, so the near rim does not hide it (see above); along the
## view it stays in the middle. 0.7 since P5-4 (0.45 left it under the near rim's shadow
## in a two-tier ravine); the wobble share keeps it off the wall's toe.
const STREAM_FAR_SHARE := 0.7
## The walls are put back (StartingLandform.restore_outside) beyond the stream's half-width,
## its bank and this much more.
const WALL_KEEP_M := 0.5
## The arch's feet stand this far back from the rims; it is looked for this far inside the
## map edge.
const ARCH_FOOT_M := 1.5
const ARCH_EDGE_M := 6.0
## The dry wash's soft edge.
const WASH_SOFT_M := 1.0
## The stage stands this far back from the rim (the cut's soft toe ends 0.5 m outside the
## outline, so this is flat ground; farther and a wide two-tier gorge on a 100 ft map has no
## rim within reach), within STAGE_REACH_SHARE of the half extent of the centre.
const STAGE_RIM_M := 1.5
const STAGE_REACH_SHARE := 0.5
const EDGE_MARGIN_M := 0.5


## The Gorge on `doc` with `seed_value` (see the header). {"stage", "report"}.
static func gorge(doc: MapDocument, seed_value: int, biome_id: String, root: String) -> Dictionary:
	var half := StartingLandform.half_extent(doc)
	var scale := StartingLandform.size_scale(doc)
	var tier := doc.tier_height_m
	var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
	var wants_two := draws.randf() < TWO_TIERS_CHANCE and doc.extent_m().x >= TWO_TIERS_MIN_EXTENT_M
	var wants_second_bend := draws.randf() < SECOND_BEND_CHANCE
	var wants_stream := draws.randf() < STREAM_CHANCE
	var wants_arch := draws.randf() < ARCH_CHANCE
	var floor_half := (
		(draws.randf_range(FLOOR_M.x, FLOOR_M.y) + (TWO_TIER_FLOOR_EXTRA_M if wants_two else 0.0))
		* 0.5
		* scale
	)
	var frame := gorge_frame(
		half, wants_second_bend, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
	)
	var axis: PackedVector2Array = frame.axis
	var centreline := StartingLandform.map_line(doc, axis, EDGE_MARGIN_M, STREAM_SPACING_M)
	if centreline.size() < 2:
		return {"stage": Vector2.ZERO, "report": "gorge: the axis misses the map; flat"}
	var s0 := StartingLandform.nearest_on(axis, centreline[0]).y
	var s1 := StartingLandform.nearest_on(axis, centreline[-1]).y
	var depth := tier * (2 if wants_two else 1)
	var fall := FALL_M * scale
	# The flat floor is floor_half wide either side of the axis; the cut's face, lip and soft
	# toe (HeightBrush.tier_span, less the toe the inset already allows for) stand outside it.
	# The floor is capped so a rim stage fits within STAGE_REACH_SHARE of the centre even when
	# the axis passes through it (binds on a 100 ft map two tiers deep).
	var face := HeightBrush.tier_span(depth + fall) - HeightBrush.TIER_SOFTEN_M
	floor_half = minf(floor_half, half * STAGE_REACH_SHARE - STAGE_RIM_M - face)
	var rim_half := floor_half + face
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var near := StartingLandform.nearest_on(axis, p)
			var along := clampf((near.y - s0) / maxf(s1 - s0, 1e-3), 0.0, 1.0)
			return HeightBrush.tier_goal(
				h, h - depth - fall * along, StartingLandform.tier_inset(rim_half - near.x)
			)
	)
	var shape := doc.heights.duplicate()
	var report := PackedStringArray(
		[
			(
				(
					"gorge heading %d deg, %.1f m off centre, %d bend(s), %.2f m deep, "
					+ "floor %.1f m, %.1f m rim to rim"
				)
				% [
					frame.heading_deg,
					frame.offset,
					frame.bends,
					depth,
					floor_half * 2.0,
					rim_half * 2.0
				]
			)
		]
	)
	var course := StartingLandform.wobbled(
		doc,
		_far_side(centreline, floor_half),
		floor_half * STREAM_WOBBLE_SHARE,
		StartingLandform.stream(seed_value, StartingLandform.STREAM_RIVER)
	)
	var middle := _middle(centreline, frame)
	var stage_at := middle
	if wants_stream:
		var stream := StartingLandform.carve_river(
			doc, course, STREAM_HALF_WIDTH_M, WaterBody.Depth.ANKLE
		)
		if stream.is_empty():
			report.append("stream: nothing could be planned")
		else:
			# The stream's bank reach would slump the walls into a slope: put them back
			# outside the channel and its bank.
			StartingLandform.restore_outside(
				doc,
				shape,
				WaterCarve.joined_course(stream).points,
				STREAM_HALF_WIDTH_M + WaterGeometry.RIVER_BANK_M + WALL_KEEP_M
			)
			report.append("stream: %d reaches" % stream.size())
			if wants_arch:
				var arch := _arch(doc, axis, course, middle, rim_half, biome_id)
				report.append(arch.line)
				if arch.has("at"):
					stage_at = arch.at
		if not doc.water_bodies.is_empty():
			doc.water_dressing = WaterDressing.refresh(doc)
	else:
		var surface := LandformRecipes.wash_surface(biome_id, root)
		if surface == "":
			report.append("dry wash: no scree surface for the biome, none painted")
		else:
			var painted := StartingLandform.paint_line(
				doc, surface, course, floor_half * 2.0, WASH_SOFT_M
			)
			report.append("dry wash of %s: %d samples" % [surface, painted])
	var stage := gorge_stage(centreline, stage_at, rim_half, half)
	report.append("stage (%.1f, %.1f)" % [stage.x, stage.y])
	return {"stage": stage, "report": "; ".join(report)}


## The Gorge's frame from the seed, for a map of half extent `half`: the axis polyline (the
## upstream end, one or two bends, the downstream end, each run long enough to leave the
## map), the arc position of the centre's foot along it, and the numbers the report quotes.
## `two_bends` adds the second bend, turning back the other way. The heading is one of
## HEADINGS (one draw, so the later draws stand whatever the list holds).
static func gorge_frame(half: float, two_bends: bool, rng: RandomNumberGenerator) -> Dictionary:
	var heading_index: int = HEADINGS[rng.randi_range(0, HEADINGS.size() - 1)]
	var dir := Vector2(cos(heading_index * PI / 4.0), sin(heading_index * PI / 4.0))
	var normal := Vector2(-dir.y, dir.x)
	var offset := rng.randf_range(-1.0, 1.0) * half * OFFSET_SHARE
	var turn := 1.0 if rng.randf() < 0.5 else -1.0
	var first_deg := rng.randf_range(BEND_DEG.x, BEND_DEG.y)
	var first_at := rng.randf_range(FIRST_BEND_SHARE.x, FIRST_BEND_SHARE.y) * half
	var second_deg := rng.randf_range(BEND_DEG.x, BEND_DEG.y)
	var second_on := rng.randf_range(SECOND_BEND_SHARE.x, SECOND_BEND_SHARE.y) * half
	var run := 3.0 * half
	var foot := normal * offset
	var first := foot + dir * first_at
	var dir2 := dir.rotated(turn * deg_to_rad(first_deg))
	var points := PackedVector2Array([first - dir * run, first])
	if two_bends:
		var second := first + dir2 * second_on
		var dir3 := dir2.rotated(-turn * deg_to_rad(second_deg))
		points.append(second)
		points.append(second + dir3 * run)
	else:
		points.append(first + dir2 * run)
	return {
		"axis": points,
		"foot_arc": run - first_at,
		"heading_deg": heading_index * 45,
		"offset": offset,
		"bends": 2 if two_bends else 1,
	}


## The stage: STAGE_RIM_M back from the rim (`rim_half` from the axis) on the +z side of
## `course` at `at`; when that lies outside STAGE_REACH_SHARE of `half` from the centre, the
## other side, then the nearest point along the course (either side) that fits, else the
## nearest to the centre of all of them (the axis passes within OFFSET_SHARE of the centre,
## so one always fits on a 100 ft map or larger).
static func gorge_stage(
	course: PackedVector2Array, at: Vector2, rim_half: float, half: float
) -> Vector2:
	var reach := half * STAGE_REACH_SHARE
	var out := rim_half + STAGE_RIM_M
	var start := StartingLandform.nearest_on(course, at).y
	var best := Vector2.ZERO
	var nearest := INF
	var steps := ceili(half / 0.5)
	for n in steps + 1:
		for sign in [0.0] if n == 0 else [1.0, -1.0]:
			var here := StartingLandform.along(course, start + sign * 0.5 * n)
			var dir: Vector2 = here.dir
			var side := Vector2(-dir.y, dir.x)
			if side.y < 0.0 or (absf(side.y) < 1e-3 and side.dot(-at) < 0.0):
				side = -side
			for facing in [1.0, -1.0]:
				var candidate: Vector2 = here.point + side * facing * out
				if candidate.length() <= reach:
					return candidate
				if candidate.length() < nearest:
					nearest = candidate.length()
					best = candidate
	return best


## The point of `course` nearest the axis's centre foot (the middle of the ravine).
static func _middle(course: PackedVector2Array, frame: Dictionary) -> Vector2:
	var at := StartingLandform.along(frame.axis, float(frame.foot_arc))
	var near := StartingLandform.nearest_on(course, at.point)
	return StartingLandform.along(course, near.y).point


## The stream's line: `points` (the ravine's axis on the map) pushed STREAM_FAR_SHARE of
## `floor_half` toward the far wall (-z) in proportion to how squarely the ravine crosses the
## view there (the normal's -z share), so a stream across the view runs where the camera sees
## it and one along the view stays in the middle.
static func _far_side(points: PackedVector2Array, floor_half: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var dir := (next - prev).normalized()
		var normal := Vector2(-dir.y, dir.x)
		if normal.y > 0.0:
			normal = -normal
		out.append(points[i] + normal * (STREAM_FAR_SHARE * floor_half * -normal.y))
	return out


## A stone arch across the ravine over the point of `course` nearest `middle` that lies
## ARCH_EDGE_M inside the map, its feet `rim_half` + ARCH_FOOT_M either side of `axis` there
## (the stream may run off the axis; the arch stands square on both rims). {"line": the
## report line, "at": the point (when placed)}.
static func _arch(
	doc: MapDocument,
	axis: PackedVector2Array,
	course: PackedVector2Array,
	middle: Vector2,
	rim_half: float,
	biome_id: String
) -> Dictionary:
	var best := -1
	var nearest := INF
	for i in range(1, course.size() - 1):
		if not StartingLandform.inside(doc, course[i], ARCH_EDGE_M):
			continue
		var d := course[i].distance_to(middle)
		if d < nearest:
			nearest = d
			best = i
	if best < 0:
		return {"line": "arch: no room on the ravine"}
	var on_axis := StartingLandform.along(axis, StartingLandform.nearest_on(axis, course[best]).y)
	var at: Vector2 = on_axis.point
	var dir: Vector2 = on_axis.dir
	var side := Vector2(-dir.y, dir.x) * (rim_half + ARCH_FOOT_M)
	var placed := StartingLandform.span_crossing(
		doc, at - side, at + side, Crossing.Kind.ARCH, biome_id
	)
	if placed.crossing == null:
		return {"line": "arch refused (%s) at (%.1f, %.1f)" % [placed.refusal, at.x, at.y]}
	return {"line": "arch at (%.1f, %.1f)" % [at.x, at.y], "at": at}
