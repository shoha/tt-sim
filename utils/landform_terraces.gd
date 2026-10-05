class_name LandformTerraces
extends RefCounted

## The Terraces starting landform (P5-2; see StartingLandform and LandformRecipes for the
## frame every recipe shares). Two or three tiers (THREE_CHANCE) stepping down across the map
## along one of eight headings: the lowest terrace is the base ground, each higher one a
## rounded-corner plateau (corners CORNER_M, its edge wobbled by the seed up to WOBBLE_M)
## raised one 5 ft tier over the one below with HeightBrush.tier_goal, the Sculpt tool's own
## terrace: a 66 degree rock face, a grassy lip, a flat top exactly on the tier. The top
## terrace's edge lies TOP_EDGE_SHARE of the way across, the next STEP_SHARE further on.
## The plateaus narrow across the heading as they rise (WIDTH_SHARE, WIDTH_STEP_M), so a
## corner or two shows on the map. The seed draws: a waist river (RIVER_CHANCE) crossing the
## terraces square to the steps (it falls at each one by the falls rule) and, given a river,
## a plank bridge on the top terrace (BRIDGE_CHANCE). The stage is on the middle terrace,
## or the lower when there are two, away from the river.

const THREE_CHANCE := 0.5
const RIVER_CHANCE := 0.6
const BRIDGE_CHANCE := 0.5
## Where the steps lie along the heading, as shares of the half extent from the uphill edge
## (-1): the top terrace's edge a third of the way across, the next two thirds further.
const TOP_EDGE_SHARE := -1.0 / 3.0
const STEP_SHARE := 2.0 / 3.0
## The plateaus' corners, their edge wobble, how wide across the heading the lowest raised
## one is (a share of the half extent) and how much narrower each higher one, and how far the
## whole set may sit off the axis.
const CORNER_M := Vector2(4.0, 8.0)
const WOBBLE_M := 1.5
const WOBBLE_WAVE_M := 9.0
const WIDTH_SHARE := 1.15
const WIDTH_STEP_M := 3.0
const SET_OFFSET_SHARE := 0.25
const DRIFT_M := 1.2
## The river: waist half-width, control points, wobble, how far off the axis it may run.
const RIVER_HALF_WIDTH_M := 1.5
const RIVER_SPACING_M := 5.0
const RIVER_WOBBLE_M := 1.2
const RIVER_OFFSET_SHARE := 0.3
## The bridge stands on the top terrace at least this far back from its edge and this far
## inside the map.
const BRIDGE_BACK_M := 5.0
const BRIDGE_EDGE_M := 4.0
## The stage: this far from the river across the heading (toward the centre), else this
## share of the half extent off the axis; this far down the lower terrace when there are two.
const STAGE_RIVER_M := 6.0
const STAGE_OFFSET_SHARE := 0.2
const STAGE_DOWN_SHARE := 0.3
const STAGE_REACH_SHARE := 0.5
const EDGE_MARGIN_M := 0.5


## The Terraces on `doc` with `seed_value` (see the header). {"stage", "report"}.
static func terraces(doc: MapDocument, seed_value: int, biome_id: String) -> Dictionary:
	var half := StartingLandform.half_extent(doc)
	var tier := doc.tier_height_m
	var frame := terraces_frame(
		half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
	)
	var dir: Vector2 = frame.dir
	var normal: Vector2 = frame.normal
	var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
	var wants_three := draws.randf() < THREE_CHANCE
	var wants_river := draws.randf() < RIVER_CHANCE
	var wants_bridge := draws.randf() < BRIDGE_CHANCE
	var river_v := draws.randf_range(-1.0, 1.0) * half * RIVER_OFFSET_SHARE
	var stage_v := draws.randf_range(-1.0, 1.0) * half * STAGE_OFFSET_SHARE
	var plateaus := plateaus_of(frame, wants_three, half, draws)
	var noise := StartingLandform.warp_noise(draws, WOBBLE_WAVE_M)
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var wobble := WOBBLE_M * noise.get_noise_2d(p.x, p.y)
			var height := h
			# Lowest raised plateau first: each higher one starts from the one below.
			for k in range(plateaus.size() - 1, -1, -1):
				var plateau: Dictionary = plateaus[k]
				var distance := (
					StartingLandform.box_distance(
						p, plateau.centre, plateau.half_size, plateau.corner, dir
					)
					+ wobble
				)
				height = HeightBrush.tier_goal(
					height, float(plateau.level) * tier, StartingLandform.tier_inset(distance)
				)
			return height
	)
	var stage := terraces_stage(frame, plateaus, half, river_v if wants_river else NAN, stage_v)
	var report := PackedStringArray(
		[
			(
				"terraces heading %d deg, %d tiers, set %.1f m off the axis"
				% [frame.heading_deg, plateaus.size() + 1, frame.offset]
			)
		]
	)
	if wants_river:
		var foot := normal * river_v
		var line := StartingLandform.map_line(
			doc,
			PackedVector2Array([foot - dir * 4.0 * half, foot + dir * 4.0 * half]),
			EDGE_MARGIN_M,
			RIVER_SPACING_M
		)
		var course := StartingLandform.wobbled(
			doc,
			line,
			RIVER_WOBBLE_M,
			StartingLandform.stream(seed_value, StartingLandform.STREAM_RIVER)
		)
		var river := StartingLandform.carve_river(
			doc, course, RIVER_HALF_WIDTH_M, WaterBody.Depth.WAIST
		)
		if river.is_empty():
			report.append("river: nothing could be planned")
		else:
			report.append(
				"river: %d reaches, %d falls" % [river.size(), WaterFalls.falls(doc).size()]
			)
			if wants_bridge:
				report.append(_bridge(doc, river, plateaus[0], dir, biome_id))
		if not doc.water_bodies.is_empty():
			doc.water_dressing = WaterDressing.refresh(doc)
	else:
		report.append("dry")
	report.append("stage (%.1f, %.1f)" % [stage.x, stage.y])
	return {"stage": stage, "report": "; ".join(report)}


## The Terraces' frame from the seed, for a map of half extent `half`: the downhill heading
## `dir`, its `normal`, how far the set of plateaus sits off the axis, and the heading the
## report quotes.
static func terraces_frame(half: float, rng: RandomNumberGenerator) -> Dictionary:
	var heading_index := rng.randi_range(0, 7)
	var dir := Vector2(cos(heading_index * PI / 4.0), sin(heading_index * PI / 4.0))
	var offset := rng.randf_range(-1.0, 1.0) * half * SET_OFFSET_SHARE
	return {
		"dir": dir,
		"normal": Vector2(-dir.y, dir.x),
		"heading_deg": heading_index * 45,
		"offset": offset,
	}


## The raised plateaus, highest first: each {"level" (tiers over the base), "edge" (the
## step's position along the heading, metres from the centre), "centre", "half_size" (along
## the heading and across it), "corner"}. The top terrace's edge is at TOP_EDGE_SHARE of
## `half`, the next STEP_SHARE further; each plateau runs from far uphill to its edge and is
## WIDTH_STEP_M narrower across than the one below, drifting DRIFT_M off the set's offset.
static func plateaus_of(
	frame: Dictionary, three: bool, half: float, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var dir: Vector2 = frame.dir
	var normal: Vector2 = frame.normal
	var count := 2 if three else 1
	var out: Array[Dictionary] = []
	var far := 4.0 * half
	for j in count:
		var edge := half * (TOP_EDGE_SHARE + STEP_SHARE * j)
		var width := half * WIDTH_SHARE - WIDTH_STEP_M * (count - 1 - j)
		var drift := rng.randf_range(-1.0, 1.0) * DRIFT_M
		var corner := rng.randf_range(CORNER_M.x, CORNER_M.y)
		var along := (edge - far) * 0.5
		(
			out
			. append(
				{
					"level": count - j,
					"edge": edge,
					"centre": dir * along + normal * (float(frame.offset) + drift),
					"half_size": Vector2((edge + far) * 0.5, width),
					"corner": corner,
				}
			)
		)
	return out


## The stage: on the middle terrace (between the two steps) with three tiers, else
## STAGE_DOWN_SHARE of `half` down the lower terrace from the step; across the heading,
## STAGE_RIVER_M from the river (`river_v`, NAN when dry) toward the axis, else `stage_v`;
## pulled toward the centre until within STAGE_REACH_SHARE of `half`.
static func terraces_stage(
	frame: Dictionary, plateaus: Array[Dictionary], half: float, river_v: float, stage_v: float
) -> Vector2:
	var dir: Vector2 = frame.dir
	var normal: Vector2 = frame.normal
	var top_edge: float = plateaus[0].edge
	var u := (
		(top_edge + float(plateaus[1].edge)) * 0.5
		if plateaus.size() > 1
		else top_edge + half * STAGE_DOWN_SHARE
	)
	var v := stage_v
	if not is_nan(river_v):
		v = river_v - signf(river_v if river_v != 0.0 else 1.0) * STAGE_RIVER_M
	var stage := dir * u + normal * v
	var reach := half * STAGE_REACH_SHARE
	if stage.length() > reach:
		stage = stage.normalized() * reach
	return stage


## A plank bridge where the river runs straightest over water (StartingLandform.straightest_wet)
## on the top terrace (`top`), BRIDGE_BACK_M
## uphill of its edge and BRIDGE_EDGE_M inside the map. The report line, naming a refusal.
static func _bridge(
	doc: MapDocument, river: Array[WaterBody], top: Dictionary, dir: Vector2, biome_id: String
) -> String:
	var course: PackedVector2Array = WaterCarve.joined_course(river).points
	var candidates := PackedInt32Array()
	var limit: float = top.edge - BRIDGE_BACK_M
	for i in range(2, course.size() - 2):
		if course[i].dot(dir) <= limit and StartingLandform.inside(doc, course[i], BRIDGE_EDGE_M):
			candidates.append(i)
	if candidates.is_empty():
		return "bridge: no room on the top terrace"
	var at := StartingLandform.straightest_wet(doc, course, candidates)
	if at < 0:
		return "bridge: no water on the top terrace"
	var along := (course[at + 1] - course[at - 1]).normalized()
	var placed := StartingLandform.place_crossing(
		doc, course[at], along, Crossing.Kind.PLANK, biome_id
	)
	if placed.crossing == null:
		return "bridge refused (%s) at (%.1f, %.1f)" % [placed.refusal, course[at].x, course[at].y]
	return "bridge at (%.1f, %.1f)" % [course[at].x, course[at].y]
