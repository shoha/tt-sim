class_name LandformRecipes
extends RefCounted

## The starting landform recipes StartingLandform.apply runs (phase 5): each a shape written
## into the heights plus the features the seed draws, composed from StartingLandform's shared
## steps. Metres are written for a 150 ft map and scaled by StartingLandform.size_scale();
## shares are of the map's half extent so the stage keeps its proportions at every size.
##
## Valley (P5-1). A broad trough across the whole map: its axis is one of eight headings
## through a point offset from the centre, bent once by VALLEY_BEND_DEG downstream of the
## centre, and the ground follows the polyline's distance field (so the bend is smooth):
## flat on the floor, a cosine rise to the rim, the base height from the rim to the map edge,
## so the trough reads as ground falling away. The floor tilts VALLEY_FALL_M along the axis
## so a river down it has reaches and riffles. The seed then draws: a waist river down the
## floor (VALLEY_RIVER_CHANCE) wobbling within a tenth of the floor's width; given the
## river, an ankle tributary off the outer slope (VALLEY_TRIBUTARY_CHANCE) and a crossing
## where the river runs straightest (VALLEY_CROSSING_CHANCE; a ford, or stepping stones at
## VALLEY_STONES_CHANCE); without one, a dry wash of the biome's scree surface along the
## floor (VALLEY_WASH_CHANCE); and a bluff (VALLEY_BLUFF_CHANCE, P5-4): one bank stands one
## tier over the slope behind a rock face cut with HeightBrush.tier_goal along the rim line,
## wobbled by the seed (BLUFF_WOBBLE_M), its toe on the rim so the slope below keeps its
## width; the other bank keeps the cosine slope, so the valley reads as a place without
## becoming a gorge. The bluff stands where its face shows to the camera: on the far bank
## (the StartingLandform.VIEW side) when the valley crosses the view, on the outer bank
## (away from the stage) when it runs along the view (bluff_side_of). The stage is on the
## inner bank of
## the bend, within a quarter of the map of the centre, the bend's own bank when that fits
## and otherwise as near the bend as fits.

## Valley: the trough's depth and its floor's fall along the axis at 150 ft; the floor's
## half-width and the rim's distance from the axis as shares of the half extent (a floor a
## third of the map wide); how far the axis may sit from the centre (an eighth of the map,
## which keeps the stage within a quarter of it); the bend's range and how far downstream
## of the centre's foot it may lie. P5-2 deepened the trough from 2.5 m to 3.5 m and moved
## the rim in from 0.72 to 0.6 (a 6 m slope in place of 8.8 m): the P5-1 look found the
## shallower trough read only as a sunken channel from the home camera.
const VALLEY_DEPTH_M := 3.5
const VALLEY_FALL_M := 1.0
const VALLEY_FLOOR_SHARE := 1.0 / 3.0
const VALLEY_RIM_SHARE := 0.6
const VALLEY_OFFSET_SHARE := 0.25
const VALLEY_BEND_DEG := Vector2(8.0, 25.0)
const VALLEY_BEND_REACH_SHARE := 1.0 / 3.0
## Valley feature chances (the no-sameness palette).
const VALLEY_RIVER_CHANCE := 0.7
const VALLEY_TRIBUTARY_CHANCE := 0.4
const VALLEY_CROSSING_CHANCE := 0.5
const VALLEY_STONES_CHANCE := 0.4
const VALLEY_WASH_CHANCE := 0.5
const VALLEY_BLUFF_CHANCE := 0.5
## The bluff's outline wanders this far either side of the rim line, one wave per
## BLUFF_WOBBLE_WAVE_M (read over the map, as the terraces' edges are).
const BLUFF_WOBBLE_M := 2.0
const BLUFF_WOBBLE_WAVE_M := 12.0
## A valley whose heading lies within this of the camera's diagonal (StartingLandform.VIEW)
## runs along the view; any other crosses it and puts its bluff on the far bank
## (bluff_side_of).
const BLUFF_ALONG_DEG := 30.0
## The river: control points every RIVER_SPACING_M, a wobble up to RIVER_WOBBLE_SHARE of the
## floor's width, the waist half-width; the tributary's ankle half-width, where it rises on
## the side slope (a share of the slope's width above the floor) and how far upstream of its
## mouth, and its spacing.
const RIVER_SPACING_M := 5.0
const RIVER_WOBBLE_SHARE := 0.1
const RIVER_HALF_WIDTH_M := 1.5
const TRIBUTARY_HALF_WIDTH_M := 0.55
const TRIBUTARY_SLOPE_SHARE := 0.6
const TRIBUTARY_RUN_SHARE := 0.3
const TRIBUTARY_SPACING_M := 3.0
## The stage: this share of the floor's half-width from the axis on the inner bank, within
## STAGE_REACH_SHARE of the half extent from the centre (a quarter of the map).
const STAGE_BANK_SHARE := 0.7
const STAGE_REACH_SHARE := 0.5
## A crossing is looked for within this share of the half extent of the stage (the whole
## river when that leaves nothing) and this far inside the map edge.
const CROSSING_NEAR_SHARE := 0.6
const CROSSING_EDGE_M := 4.0
## The dry wash's width as a share of the floor's width and its soft edge.
const WASH_WIDTH_SHARE := 0.35
const WASH_SOFT_M := 1.5
## A river's ends stop this far inside the map edge: within WaterCarve.EDGE_MARGIN_M, so
## they stay open (the river runs off the map) instead of tapering to a head.
const EDGE_MARGIN_M := 0.5


## The Valley on `doc` with `seed_value` (see the header). {"stage", "report"}.
static func valley(doc: MapDocument, seed_value: int, biome_id: String, root: String) -> Dictionary:
	var half := StartingLandform.half_extent(doc)
	var scale := StartingLandform.size_scale(doc)
	var frame := valley_frame(
		half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
	)
	var axis: PackedVector2Array = frame.axis
	var floor_half := half * VALLEY_FLOOR_SHARE
	var rim := half * VALLEY_RIM_SHARE
	var centreline := StartingLandform.map_line(doc, axis, EDGE_MARGIN_M, RIVER_SPACING_M)
	if centreline.size() < 2:
		return {"stage": Vector2.ZERO, "report": "valley: the axis misses the map; flat"}
	var s0 := StartingLandform.nearest_on(axis, centreline[0]).y
	var s1 := StartingLandform.nearest_on(axis, centreline[-1]).y
	var depth := VALLEY_DEPTH_M * scale
	var fall := VALLEY_FALL_M * scale
	var tier := doc.tier_height_m
	var turn: float = frame.turn
	# Every chance is drawn from one stream whatever the earlier draws, so the features stay
	# put when a chance is tuned; the bluff (P5-4) was appended last for the same reason.
	var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
	var wants_river := draws.randf() < VALLEY_RIVER_CHANCE
	var wants_tributary := draws.randf() < VALLEY_TRIBUTARY_CHANCE
	var wants_crossing := draws.randf() < VALLEY_CROSSING_CHANCE
	var wants_stones := draws.randf() < VALLEY_STONES_CHANCE
	var wants_wash := draws.randf() < VALLEY_WASH_CHANCE
	var wants_bluff := draws.randf() < VALLEY_BLUFF_CHANCE
	var bluff_noise := StartingLandform.warp_noise(draws, BLUFF_WOBBLE_WAVE_M)
	# The bluff's outline stands a cut's span outside the rim, so its toe lands on the rim
	# and the cosine slope below it keeps its full width for the depth that remains.
	var bluff_rim := rim + HeightBrush.tier_span(tier) - HeightBrush.TIER_SOFTEN_M
	var bluff_side := bluff_side_of(frame)
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var near := StartingLandform.nearest_on(axis, p)
			var along := clampf((near.y - s0) / maxf(s1 - s0, 1e-3), 0.0, 1.0)
			var drop := depth + fall * along
			var slope := StartingLandform.trough_shape(near.x, floor_half, rim)
			if wants_bluff and _on_bank(axis, near, p, turn * bluff_side):
				var wobble := BLUFF_WOBBLE_M * bluff_noise.get_noise_2d(p.x, p.y)
				var inset := StartingLandform.tier_inset(bluff_rim + wobble - near.x)
				return HeightBrush.tier_goal(h, h - tier, inset) - (drop - tier) * slope
			return h - drop * slope
	)
	var stage := valley_stage(frame, floor_half, half)
	var report := PackedStringArray(
		[
			(
				"valley heading %d deg, axis %.1f m off centre, bend %.0f deg %.1f m downstream%s"
				% [
					frame.heading_deg,
					frame.offset,
					frame.bend_deg,
					frame.bend_downstream,
					(
						(
							", bluff on the far bank"
							if bluff_side > 0.0
							else ", bluff on the outer bank"
						)
						if wants_bluff
						else ""
					)
				]
			)
		]
	)
	var course := StartingLandform.wobbled(
		doc,
		centreline,
		RIVER_WOBBLE_SHARE * 2.0 * floor_half,
		StartingLandform.stream(seed_value, StartingLandform.STREAM_RIVER)
	)
	if wants_river:
		var river := StartingLandform.carve_river(
			doc, course, RIVER_HALF_WIDTH_M, WaterBody.Depth.WAIST
		)
		if river.is_empty():
			report.append("river: nothing could be planned")
		else:
			report.append("river: %d reaches" % river.size())
			if wants_tributary:
				report.append(
					_valley_tributary(
						doc,
						frame,
						river,
						floor_half,
						rim,
						half,
						StartingLandform.stream(seed_value, StartingLandform.STREAM_TRIBUTARY)
					)
				)
			if wants_crossing:
				var kind := Crossing.Kind.STONES if wants_stones else Crossing.Kind.FORD
				report.append(_valley_crossing(doc, river, stage, half, kind, biome_id))
		if not doc.water_bodies.is_empty():
			doc.water_dressing = WaterDressing.refresh(doc)
	elif wants_wash:
		var surface := wash_surface(biome_id, root)
		if surface == "":
			report.append("dry wash: no scree surface for the biome, none painted")
		else:
			var painted := StartingLandform.paint_line(
				doc, surface, course, floor_half * 2.0 * WASH_WIDTH_SHARE, WASH_SOFT_M
			)
			report.append("dry wash of %s: %d samples" % [surface, painted])
	else:
		report.append("dry")
	report.append("stage (%.1f, %.1f)" % [stage.x, stage.y])
	return {"stage": stage, "report": "; ".join(report)}


## The Valley's frame from the seed, for a map of half extent `half`: the axis polyline
## (upstream end, bend, downstream end, each run long enough to leave the map), the
## downstream directions of its two runs, the turn's sign (+1: the second run turns toward
## the first's rotated(PI / 2) side, the inner bank), the arc positions of the centre's foot
## and the bend along the axis, and the numbers the report quotes.
static func valley_frame(half: float, rng: RandomNumberGenerator) -> Dictionary:
	var heading_index := rng.randi_range(0, 7)
	var dir := Vector2(cos(heading_index * PI / 4.0), sin(heading_index * PI / 4.0))
	var normal := Vector2(-dir.y, dir.x)
	var offset := rng.randf_range(-1.0, 1.0) * half * VALLEY_OFFSET_SHARE
	var turn := 1.0 if rng.randf() < 0.5 else -1.0
	var bend_deg := rng.randf_range(VALLEY_BEND_DEG.x, VALLEY_BEND_DEG.y)
	var bend_downstream := rng.randf_range(0.0, half * VALLEY_BEND_REACH_SHARE)
	var run := 2.5 * half
	var foot := normal * offset
	var bend := foot + dir * bend_downstream
	var dir2 := dir.rotated(turn * deg_to_rad(bend_deg))
	return {
		"axis": PackedVector2Array([bend - dir * run, bend, bend + dir2 * run]),
		"dir": dir,
		"dir2": dir2,
		"turn": turn,
		"foot_arc": run - bend_downstream,
		"bend_arc": run,
		"heading_deg": heading_index * 45,
		"offset": offset,
		"bend_deg": turn * bend_deg,
		"bend_downstream": bend_downstream,
	}


## The stage: the point of the inner-bank strip (STAGE_BANK_SHARE of `floor_half` from the
## axis on the turn's side) nearest the bend among those within STAGE_REACH_SHARE of `half`
## from the centre. The strip's point at the centre's foot always qualifies (the axis offset
## and the bank share are bounded for it), so there is always a stage.
static func valley_stage(frame: Dictionary, floor_half: float, half: float) -> Vector2:
	var axis: PackedVector2Array = frame.axis
	var bank := floor_half * STAGE_BANK_SHARE
	var reach := half * STAGE_REACH_SHARE
	var foot_arc: float = frame.foot_arc
	var bend_arc: float = frame.bend_arc
	var turn: float = frame.turn
	var fallback := _bank_point(axis, foot_arc, turn, bank)
	var best := fallback
	var nearest := INF
	var steps := ceili((bend_arc - foot_arc + 2.0 * half / 3.0) / 0.5)
	for n in steps + 1:
		var s := foot_arc - half / 3.0 + 0.5 * n
		var q := _bank_point(axis, s, turn, bank)
		if q.length() > reach:
			continue
		if absf(s - bend_arc) < nearest:
			nearest = absf(s - bend_arc)
			best = q
	return best


## The biome's scree surface (gravel in most biomes), the dry wash's surface, or "".
static func wash_surface(biome_id: String, root: String) -> String:
	if biome_id == "":
		return ""
	return String(PaletteLibrary.biome(biome_id, root).get("scree_surface", ""))


static func _bank_point(axis: PackedVector2Array, s: float, turn: float, bank: float) -> Vector2:
	var at := StartingLandform.along(axis, s)
	var dir: Vector2 = at.dir
	return at.point + dir.rotated(turn * PI / 2.0) * bank


## Which bank the bluff stands on, as a sign on the turn's inner side: +1 the inner bank (the
## stage's), -1 the outer. A valley crossing the view (its heading more than BLUFF_ALONG_DEG
## off the camera's diagonal, StartingLandform.VIEW) puts the bluff on the far bank,
## whichever that is, so its face looks at the camera (a face on the near bank is
## back-facing to it and shows only as a lip line, P5-4 look); a valley running along the
## view puts it on the outer bank, away from the stage, where both faces show in profile.
static func bluff_side_of(frame: Dictionary) -> float:
	var dir: Vector2 = frame.dir
	var turn: float = frame.turn
	if absf(dir.dot(StartingLandform.VIEW)) > cos(deg_to_rad(BLUFF_ALONG_DEG)):
		return -1.0
	var inner := dir.rotated(turn * PI / 2.0)
	return 1.0 if inner.dot(StartingLandform.VIEW) > 0.0 else -1.0


## True when `p` lies on the bank of `axis` on the side `dir.rotated(side * PI / 2)` of its
## nearest segment (`near` is StartingLandform.nearest_on(axis, p)): +turn the inner bank,
## -turn the outer. Decided per segment with one sign, so the bend keeps the bank whole.
static func _on_bank(axis: PackedVector2Array, near: Vector3, p: Vector2, side: float) -> bool:
	var k := int(near.z)
	var dir := (axis[k + 1] - axis[k]).normalized()
	var q := Geometry2D.get_closest_point_to_segment(p, axis[k], axis[k + 1])
	return (p - q).dot(dir.rotated(side * PI / 2.0)) > 0.0


## An ankle tributary off the outer slope: it rises TRIBUTARY_SLOPE_SHARE of the way up the
## slope, TRIBUTARY_RUN_SHARE of the half extent upstream of its mouth, bows outward a
## little and ends on the river's course (plan_river joins it). The report line.
static func _valley_tributary(
	doc: MapDocument,
	frame: Dictionary,
	river: Array[WaterBody],
	floor_half: float,
	rim: float,
	half: float,
	rng: RandomNumberGenerator
) -> String:
	var axis: PackedVector2Array = frame.axis
	var course: PackedVector2Array = WaterCarve.joined_course(river).points
	var mouth_index := rng.randi_range(int(course.size() * 0.35), int(course.size() * 0.85))
	var mouth := course[mouth_index]
	var mouth_arc := StartingLandform.nearest_on(axis, mouth).y
	var start_at := StartingLandform.along(axis, mouth_arc - half * TRIBUTARY_RUN_SHARE)
	var dir: Vector2 = start_at.dir
	var outer := dir.rotated(-float(frame.turn) * PI / 2.0)
	var start: Vector2 = (
		start_at.point + outer * (floor_half + (rim - floor_half) * TRIBUTARY_SLOPE_SHARE)
	)
	start = StartingLandform.clamped(doc, start, 1.0)
	var bow := rng.randf_range(0.0, 0.1) * half
	var mid := start.lerp(mouth, 0.5) + outer * bow
	var widths := PackedFloat32Array([1.0, 1.0, 1.0])
	var line: PackedVector2Array = (
		WaterEdit.resample(PackedVector2Array([start, mid, mouth]), widths, TRIBUTARY_SPACING_M)[0]
	)
	var bodies := StartingLandform.carve_river(
		doc, line, TRIBUTARY_HALF_WIDTH_M, WaterBody.Depth.ANKLE
	)
	if bodies.is_empty():
		return "tributary: nothing could be planned"
	return "tributary: %d reaches from (%.1f, %.1f)" % [bodies.size(), start.x, start.y]


## A crossing of `kind` where the river runs straightest near the stage (see the header).
## The report line, naming a refusal.
static func _valley_crossing(
	doc: MapDocument,
	river: Array[WaterBody],
	stage: Vector2,
	half: float,
	kind: Crossing.Kind,
	biome_id: String
) -> String:
	var course: PackedVector2Array = WaterCarve.joined_course(river).points
	var near := PackedInt32Array()
	var anywhere := PackedInt32Array()
	for i in range(2, course.size() - 2):
		if not StartingLandform.inside(doc, course[i], CROSSING_EDGE_M):
			continue
		anywhere.append(i)
		if course[i].distance_to(stage) <= half * CROSSING_NEAR_SHARE:
			near.append(i)
	var at := StartingLandform.straightest(course, near if not near.is_empty() else anywhere)
	var name: String = Crossing.KIND_NAMES[kind]
	if at < 0:
		return "%s: no room on the river" % name
	var dir := (course[at + 1] - course[at - 1]).normalized()
	var placed := StartingLandform.place_crossing(doc, course[at], dir, kind, biome_id)
	if placed.crossing == null:
		return (
			"%s refused (%s) at (%.1f, %.1f)" % [name, placed.refusal, course[at].x, course[at].y]
		)
	return "%s at (%.1f, %.1f)" % [name, course[at].x, course[at].y]
