class_name LandformLakeshore
extends RefCounted

## The Lakeshore starting landform (P5-2; see StartingLandform and LandformRecipes for the
## frame every recipe shares). A deep lake over one corner third of the map: a disc of
## LAKE_RADIUS_SHARE of the half extent centred LAKE_CENTRE_SHARE of it toward a seeded
## corner, its shore warped by low-frequency noise up to LAKE_WARP of the radius, carved as a
## pond through the Water tool's pure path (StartingLandform.carve_pond: the level is the
## lowest rim ground less the freeboard). The ground rises away from the shore by
## LAKE_RISE_M over LAKE_RISE_RUN_SHARE of the half extent, so the lake sits in the map's low
## corner and a stream runs down to it. The seed draws: an islet (ISLET_CHANCE), a small
## hill shaped before the pond is stamped so the mask leaves it dry, its top ISLET_TOP_OVER_M
## above the water, on the far side of the stage's line from the stream; a feeding ankle
## stream (STREAM_CHANCE) from the far side of the map, approaching off the stage's line by
## STREAM_AZIMUTH_DEG, ending just inside the shore (plan_river joins it at the waterline);
## stepping stones over the stream (STONES_CHANCE). The stage is on the shore
## nearest the map's centre, STAGE_SHORE_M back from the waterline. The lake is the water:
## a dry draw has it too.

const LAKE_RADIUS_SHARE := 0.45
const LAKE_CENTRE_SHARE := 0.55
const LAKE_WARP := 0.15
const LAKE_RISE_M := 1.5
const LAKE_RISE_RUN_SHARE := 0.9
## Feature chances (the no-sameness palette).
const ISLET_CHANCE := 0.3
const STREAM_CHANCE := 0.5
const STONES_CHANCE := 0.4
## The islet: its bump's radius (at 150 ft; scaled), how far its top stands over the water,
## the gap of water between it and the shore, how far either side of the stage's line it may
## sit (so it is seen from the stage), and the height of its bump below which the mask covers
## it (the pond's shore profile then shapes its beach).
const ISLET_RADIUS_M := 5.0
const ISLET_TOP_OVER_M := 0.5
const ISLET_GAP_M := 2.0
const ISLET_AZIMUTH_DEG := 60.0
const ISLET_WET_M := 0.1
## The stream: ankle half-width, control points, wobble, how far off the stage's line it
## comes in.
const STREAM_HALF_WIDTH_M := 0.55
const STREAM_SPACING_M := 3.0
const STREAM_WOBBLE_M := 1.0
const STREAM_AZIMUTH_DEG := Vector2(35.0, 70.0)
## The stream's line ends this far inside the shore (plan_river joins it at the waterline).
const STREAM_IN_M := 1.0
## The stones: at least this far back from the shore and this far inside the map.
const STONES_SHORE_M := 5.0
const STONES_EDGE_M := 4.0
const STAGE_SHORE_M := 4.0
const EDGE_MARGIN_M := 0.5


## The Lakeshore on `doc` with `seed_value` (see the header). {"stage", "report"}.
static func lakeshore(doc: MapDocument, seed_value: int, biome_id: String) -> Dictionary:
	var half := StartingLandform.half_extent(doc)
	var scale := StartingLandform.size_scale(doc)
	var frame := lakeshore_frame(
		half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
	)
	var centre: Vector2 = frame.centre
	var radius := half * LAKE_RADIUS_SHARE
	var toward: Vector2 = frame.toward
	var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
	var wants_islet := draws.randf() < ISLET_CHANCE
	var wants_stream := draws.randf() < STREAM_CHANCE
	var wants_stones := draws.randf() < STONES_CHANCE
	var stream_sign := 1.0 if draws.randf() < 0.5 else -1.0
	var stream_azimuth := toward.rotated(
		stream_sign * deg_to_rad(draws.randf_range(STREAM_AZIMUTH_DEG.x, STREAM_AZIMUTH_DEG.y))
	)
	# The islet sits on the other side of the stage's line from the stream, so the stream's
	# mouth never carves it.
	var islet_azimuth := toward.rotated(
		-stream_sign * deg_to_rad(draws.randf_range(0.0, ISLET_AZIMUTH_DEG))
	)
	var shore_noise := StartingLandform.warp_noise(draws, radius)
	var rise := LAKE_RISE_M * scale
	var run := half * LAKE_RISE_RUN_SHARE
	var islet_radius := ISLET_RADIUS_M * scale
	var islet_centre := centre + islet_azimuth * maxf(radius - islet_radius - ISLET_GAP_M, 0.0)
	# The rim is the flat shore at the base height, so the level is the freeboard below it;
	# the islet's top stands ISLET_TOP_OVER_M over that.
	var islet_height := ISLET_TOP_OVER_M - WaterGeometry.FREEBOARD_M if wants_islet else 0.0
	var shore := func(p: Vector2) -> float:
		return StartingLandform.disc_distance(p, centre, radius, shore_noise, LAKE_WARP)
	var islet := func(p: Vector2) -> float:
		return islet_height * StartingLandform.bump(p.distance_to(islet_centre) / islet_radius)
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var outside: float = -shore.call(p)
			return h + rise * smoothstep(0.0, run, outside) + islet.call(p)
	)
	var lake := StartingLandform.carve_pond(
		doc,
		func(p: Vector2) -> bool: return shore.call(p) > 0.0 and islet.call(p) <= ISLET_WET_M,
		WaterBody.Depth.DEEP
	)
	var stage: Vector2 = (
		centre + toward * (radius + shore.call(centre + toward * radius) + STAGE_SHORE_M)
	)
	var report := PackedStringArray(
		[
			(
				"lakeshore corner (%d, %d), centre (%.1f, %.1f), radius %.1f m"
				% [frame.corner.x, frame.corner.y, centre.x, centre.y, radius]
			),
			(
				"lake level %.2f m, %d samples" % [lake.level_m, doc.pond_mask.count(lake.id)]
				if lake != null
				else "lake: no room, none carved"
			),
		]
	)
	if wants_islet:
		report.append("islet at (%.1f, %.1f)" % [islet_centre.x, islet_centre.y])
	if wants_stream and lake != null:
		var far := StartingLandform.clamped(
			doc, centre + stream_azimuth * 4.0 * half, EDGE_MARGIN_M
		)
		# The line ends just inside the shore, not at the lake's centre: a line that runs on
		# across the water to a dry islet would end there (WaterEdit.join_line keeps the
		# first wet point only after the last dry one) and carve through the lake and it.
		var mouth := far
		var steps := ceili(far.distance_to(centre) / StartingLandform.CLIP_STEP_M)
		for n in steps + 1:
			mouth = far.lerp(centre, float(n) / steps)
			if float(shore.call(mouth)) >= STREAM_IN_M:
				break
		var line := StartingLandform.map_line(
			doc, PackedVector2Array([far, mouth]), EDGE_MARGIN_M, STREAM_SPACING_M
		)
		var course := StartingLandform.wobbled(
			doc,
			line,
			STREAM_WOBBLE_M,
			StartingLandform.stream(seed_value, StartingLandform.STREAM_RIVER)
		)
		var stream := StartingLandform.carve_river(
			doc, course, STREAM_HALF_WIDTH_M, WaterBody.Depth.ANKLE
		)
		if stream.is_empty():
			report.append("stream: nothing could be planned")
		else:
			report.append("stream: %d reaches" % stream.size())
			if wants_stones:
				report.append(_stones(doc, stream, shore, biome_id))
	else:
		report.append("no stream")
	if not doc.water_bodies.is_empty():
		doc.water_dressing = WaterDressing.refresh(doc)
	report.append("stage (%.1f, %.1f)" % [stage.x, stage.y])
	return {"stage": stage, "report": "; ".join(report)}


## The Lakeshore's frame from the seed, for a map of half extent `half`: the corner (each
## axis +1 or -1), the lake's centre LAKE_CENTRE_SHARE of `half` toward it on both axes, and
## the unit direction from the centre toward the map's middle (the stage's line).
static func lakeshore_frame(half: float, rng: RandomNumberGenerator) -> Dictionary:
	var corner := Vector2i(
		1 if rng.randf() < 0.5 else -1,
		1 if rng.randf() < 0.5 else -1,
	)
	var centre := Vector2(corner) * half * LAKE_CENTRE_SHARE
	return {"corner": corner, "centre": centre, "toward": (-centre).normalized()}


## Stepping stones where `stream` runs straightest at least STONES_SHORE_M back from the
## shore (`shore`: the lake's signed inside distance) and STONES_EDGE_M inside the map. The
## report line, naming a refusal.
static func _stones(
	doc: MapDocument, stream: Array[WaterBody], shore: Callable, biome_id: String
) -> String:
	var course: PackedVector2Array = WaterCarve.joined_course(stream).points
	var candidates := PackedInt32Array()
	for i in range(2, course.size() - 2):
		if (
			float(shore.call(course[i])) <= -STONES_SHORE_M
			and StartingLandform.inside(doc, course[i], STONES_EDGE_M)
		):
			candidates.append(i)
	var at := StartingLandform.straightest(course, candidates)
	if at < 0:
		return "stones: no room on the stream"
	var dir := (course[at + 1] - course[at - 1]).normalized()
	var placed := StartingLandform.place_crossing(
		doc, course[at], dir, Crossing.Kind.STONES, biome_id
	)
	if placed.crossing == null:
		return "stones refused (%s) at (%.1f, %.1f)" % [placed.refusal, course[at].x, course[at].y]
	return "stones at (%.1f, %.1f)" % [course[at].x, course[at].y]
