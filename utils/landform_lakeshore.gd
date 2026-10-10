class_name LandformLakeshore
extends RefCounted

## The Lakeshore starting landform (P5-2; see StartingLandform and LandformRecipes for the
## frame every recipe shares). A deep lake over one corner third of the map: a disc of
## LAKE_RADIUS_SHARE of the half extent centred LAKE_CENTRE_SHARE of it toward a seeded
## corner (never the camera's own: allowed_corners(); the far one most often, a side one
## smaller and inside the home frame: lakeshore_frame()), its shore warped by low-frequency
## noise up to LAKE_WARP of the radius, carved as a pond through the Water tool's pure path
## (StartingLandform.carve_pond: the level is the lowest rim ground less the freeboard).
## The ground rises away from the shore by LAKE_RISE_M over LAKE_RISE_RUN_SHARE of the half
## extent, so the lake sits in the map's low corner and a stream runs down to it.
## The seed draws: an islet (ISLET_CHANCE), a small hill shaped before the pond is stamped
## so the mask leaves it dry, its top ISLET_TOP_OVER_M above the water, on the far side of
## the stage's line from the stream; a feeding ankle stream (STREAM_CHANCE) from the far side
## of the map, approaching off the stage's line by STREAM_AZIMUTH_DEG, ending just inside the
## shore (plan_river joins it at the waterline); stepping stones over the stream
## (STONES_CHANCE). The stage is on the shore nearest the map's centre, STAGE_SHORE_M back
## from the waterline. The lake is the water: a dry draw has it too. On a wide or long map the
## lake sits at any corner or side of the map's own extent, sometimes larger (wide_frame;
## a long map since 2026-10-10, where the far corner kept it at the back on most seeds).
## Every size draws its wood and often a shore meadow (round 3; see WIDE_PLACES).

const LAKE_RADIUS_SHARE := 0.45
## 0.5 since P5-4 (0.55 sat the lake at the home view's edge): more water in the home view.
const LAKE_CENTRE_SHARE := 0.5
## A side corner's lake (one of the two beside the camera's own) sits inside the home frame
## (P5-7): its centre at most LAKE_SIDE_SCREEN_M across the view from the frame's centre (the
## home camera shows about 24.6 m of ground across, so 12.3 m either side; a share-based pull
## of 0.38 still left the centre 14.2 m out), LAKE_SIDE_DEPTH_SHARE of the half extent up the
## view (StartingLandform.VIEW), and a smaller lake, LAKE_SIDE_RADIUS_SHARE of the half extent,
## beside the stage.
const LAKE_SIDE_SCREEN_M := 6.0
const LAKE_SIDE_DEPTH_SHARE := 0.4
const LAKE_SIDE_RADIUS_SHARE := 0.3
## The direction across the home view, screen right (StartingLandform.VIEW turned a quarter).
const ACROSS := Vector2(-StartingLandform.VIEW.y, StartingLandform.VIEW.x)
## The corner draw's weights (P5-7): the far corner (opposite StartingLandform.NEAR), whose
## lake fills the view, most often; each side corner the rest between them.
const FAR_CORNER_WEIGHT := 0.6
const SIDE_CORNER_WEIGHT := 0.2
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
## On a big or long map the ground within this share of the lake's radius is open shore
## (a clearing easing back to the forest at its outline, NewMap.clearing_density).
const LAKE_OPEN_SHARE := 1.6
## The setting (StartingLandform.STREAM_SETTING; round 3, where every seed read as a lake at
## the back with forest everywhere else). On a wide or long map (LandformGrowth.is_wide or
## is_long: the whole map is what reads, not the home frame; a 320 x 160 ft map's shorter side
## is under the wide threshold) the lake takes any of WIDE_PLACES, the four corners and
## the four sides' middles, alike; with LARGE_LAKE_CHANCE it is LARGE_LAKE_SHARE of the half
## extent across instead of LAKE_RADIUS_SHARE; its centre stands its radius plus
## LAKE_EDGE_SHARE of the half extent in from each edge it lies toward (a corner lake as before).
## At every size: a shore meadow (SHORE_MEADOW_CHANCE), a clearing SHORE_MEADOW_SHARE of the
## lake's radius across on the shore, SHORE_MEADOW_AZIMUTH_DEG either side of the stage's line,
## and the wood (LandformPlacement.wood), the groves keeping a share drawn within WOOD_DENSITY
## and with WOOD_LEAN_CHANCE gathering toward one side.
const WIDE_PLACES: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]
const LARGE_LAKE_CHANCE := 0.35
const LARGE_LAKE_SHARE := 0.6
const LAKE_EDGE_SHARE := 0.05
const SHORE_MEADOW_CHANCE := 0.55
const SHORE_MEADOW_SHARE := 0.85
const SHORE_MEADOW_AZIMUTH_DEG := Vector2(20.0, 80.0)
const WOOD_DENSITY := Vector2(0.45, 1.0)
const WOOD_LEAN_CHANCE := 0.5


## The Lakeshore on `doc` with `seed_value` (see the header). {"stage", "report"}.
static func lakeshore(doc: MapDocument, seed_value: int, biome_id: String) -> Dictionary:
	var half := StartingLandform.half_extent(doc)
	var scale := StartingLandform.size_scale(doc)
	var setting := StartingLandform.stream(seed_value, StartingLandform.STREAM_SETTING)
	var wood := LandformPlacement.wood(setting, WOOD_DENSITY, WOOD_LEAN_CHANCE)
	var wants_meadow := setting.randf() < SHORE_MEADOW_CHANCE
	var meadow_turn := (
		(1.0 if setting.randf() < 0.5 else -1.0)
		* deg_to_rad(setting.randf_range(SHORE_MEADOW_AZIMUTH_DEG.x, SHORE_MEADOW_AZIMUTH_DEG.y))
	)
	var frame := (
		wide_frame(doc, half, setting)
		if LandformGrowth.is_wide(doc) or LandformGrowth.is_long(doc)
		else lakeshore_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME), doc
		)
	)
	var centre: Vector2 = frame.centre
	var radius: float = frame.radius
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
	# A side corner's smaller lake carries a proportionally smaller islet.
	var islet_radius := ISLET_RADIUS_M * scale * radius / (half * LAKE_RADIUS_SHARE)
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
	var clearings: Array = []
	if wants_meadow:
		# On the shore beside the stage's line, reaching back from the water.
		var meadow_radius := radius * SHORE_MEADOW_SHARE
		var at := centre + toward.rotated(meadow_turn) * (radius + meadow_radius * 0.5)
		clearings.append({"at": at, "radius": meadow_radius})
		report.append("shore meadow at (%.1f, %.1f)" % [at.x, at.y])
	report.append(LandformPlacement.wood_report(wood))
	return {
		"stage": stage,
		"report": "; ".join(report),
		"keepout": [{"at": centre, "radius": radius * (1.0 + LAKE_WARP)}],
		# A big or long map's shore is open ground (LandformGrowth.grow, only with room).
		"open": [{"at": centre, "radius": radius * LAKE_OPEN_SHARE}],
		"clearings": clearings,
		"wood": wood,
	}


## The Lakeshore's frame from the seed, for a map of half extent `half`: the corner (each
## axis +1 or -1; one of the three that are not the camera's own, the corner
## StartingLandform.NEAR points to, where the lake would lie at the bottom of the view cut by
## the foreground; P5-4b), drawn by corner_weights() (the far corner most often, P5-7); the
## lake's centre and radius: for the far corner LAKE_CENTRE_SHARE of `half` toward it on each
## axis and LAKE_RADIUS_SHARE, for a side corner inside the home frame (LAKE_SIDE_SCREEN_M
## across the view toward the corner's side, LAKE_SIDE_DEPTH_SHARE up it,
## LAKE_SIDE_RADIUS_SHARE); and the unit direction from the centre toward the map's middle
## (the stage's line). On `doc` (when given) a long map's far-corner lake sits in the map's
## own corner, as far from its two edges as on a square map, not in the corner of the square
## of its shorter side (LandformGrowth).
static func lakeshore_frame(
	half: float, rng: RandomNumberGenerator, doc: MapDocument = null
) -> Dictionary:
	var corners := allowed_corners()
	var weights := corner_weights(corners)
	# Two draws as before (the frame stream's count stays): the corner from the first by its
	# weight, the second drawn and left unused.
	var pick := rng.randf()
	rng.randf()
	var index := corners.size() - 1
	var sum := 0.0
	for n in corners.size():
		sum += weights[n]
		if pick < sum:
			index = n
			break
	var corner := corners[index]
	var centre := Vector2(corner) * half * LAKE_CENTRE_SHARE
	var radius := half * LAKE_RADIUS_SHARE
	if doc != null and LandformGrowth.is_long(doc) and _is_far(corner):
		var inward := half * (1.0 - LAKE_CENTRE_SHARE)
		centre = Vector2(corner) * (doc.extent_m() * 0.5 - Vector2(inward, inward))
	if not _is_far(corner):
		# Across the view toward the corner's side, capped; up the view.
		var lateral := centre.dot(ACROSS)
		centre = (
			ACROSS * signf(lateral) * minf(absf(lateral), LAKE_SIDE_SCREEN_M)
			+ StartingLandform.VIEW * half * LAKE_SIDE_DEPTH_SHARE
		)
		radius = half * LAKE_SIDE_RADIUS_SHARE
	return {
		"corner": corner,
		"centre": centre,
		"radius": radius,
		"toward": (-centre).normalized(),
	}


## A wide or long map's lake frame (see WIDE_PLACES) from `rng` (the setting stream, after the wood
## and the shore meadow): the place ("corner": each axis -1, 0 or +1), the centre on the map's
## own extent, the radius and the direction toward the map's middle. Always draws two numbers.
static func wide_frame(doc: MapDocument, half: float, rng: RandomNumberGenerator) -> Dictionary:
	var place: Vector2i = WIDE_PLACES[rng.randi_range(0, WIDE_PLACES.size() - 1)]
	var large := rng.randf() < LARGE_LAKE_CHANCE
	var radius := half * (LARGE_LAKE_SHARE if large else LAKE_RADIUS_SHARE)
	var inward := radius + half * LAKE_EDGE_SHARE
	var extent := doc.extent_m() * 0.5
	var centre := Vector2(place) * (extent - Vector2(inward, inward))
	return {
		"corner": place,
		"centre": centre,
		"radius": radius,
		"toward": (-centre).normalized(),
	}


## The draw weight of each of `corners` (allowed_corners()): FAR_CORNER_WEIGHT for the corner
## opposite StartingLandform.NEAR, SIDE_CORNER_WEIGHT for each other; they sum to 1.
static func corner_weights(corners: Array[Vector2i]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for corner in corners:
		out.append(FAR_CORNER_WEIGHT if _is_far(corner) else SIDE_CORNER_WEIGHT)
	return out


## True for the corner opposite StartingLandform.NEAR.
static func _is_far(corner: Vector2i) -> bool:
	return (
		signf(corner.x) == -signf(StartingLandform.NEAR.x)
		and signf(corner.y) == -signf(StartingLandform.NEAR.y)
	)


## The corners a lake may take: the four (+-1, +-1) less the camera's own (the signs of
## StartingLandform.NEAR), in a fixed order.
static func allowed_corners() -> Array[Vector2i]:
	var near := Vector2i(
		roundi(signf(StartingLandform.NEAR.x)), roundi(signf(StartingLandform.NEAR.y))
	)
	var out: Array[Vector2i] = []
	for corner in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		if corner != near:
			out.append(corner)
	return out


## Stepping stones where `stream` runs straightest over water (StartingLandform.straightest_wet,
## P5-7) at least STONES_SHORE_M back from the shore (`shore`: the lake's signed inside
## distance) and STONES_EDGE_M inside the map. The report line, naming a refusal.
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
	if candidates.is_empty():
		return "stones: no room on the stream"
	var at := StartingLandform.straightest_wet(doc, course, candidates)
	if at < 0:
		return "stones: no water on the stream where they fit"
	var dir := (course[at + 1] - course[at - 1]).normalized()
	var placed := StartingLandform.place_crossing(
		doc, course[at], dir, Crossing.Kind.STONES, biome_id
	)
	if placed.crossing == null:
		return "stones refused (%s) at (%.1f, %.1f)" % [placed.refusal, course[at].x, course[at].y]
	return "stones at (%.1f, %.1f)" % [course[at].x, course[at].y]
