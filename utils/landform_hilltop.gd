class_name LandformHilltop
extends RefCounted

## The Hilltop starting landform (P5-2; see StartingLandform and LandformRecipes for the
## frame every recipe shares). A rounded hill off centre: a cosine bump of HILL_RADIUS_SHARE
## of the half extent, its centre up to HILL_OFFSET_SHARE of the half extent from the map's
## along one of eight headings. The seed draws: a crown (CROWN_CHANCE), a flat terrace on the
## summit raised with HeightBrush.tier_goal over a warped disc of CROWN_RADIUS_SHARE of the
## hill's radius (at least a flat top CROWN_TOP_MIN_M across on a small map), so the top is a
## rock-lipped stage; the crown stands on the tier nearest HILL_HEIGHT_M and the hill beneath
## it is scaled so the crown's face is a full tier at its outline (without a crown the summit
## is HILL_HEIGHT_M itself). A second smaller hill (SECOND_HILL_CHANCE) of half the height on
## the far side. A spring stream (STREAM_CHANCE): with a crown, a pool on the crown (the
## line starts POOL_INSIDE_M inside the crown's outline, so its first reach is the pool:
## WaterFallPlan lets a spring's first lip stand two metres from the start) spilling over
## the crown's face in a fall (the phase 4c tier fall) and running on down the flank; without
## one, an ankle stream rising STREAM_SUMMIT_SHARE of the radius from the summit. It runs
## STREAM_AZIMUTH_DEG off the camera's direction (StartingLandform.NEAR), to the hill's
## side: the fall shows in profile to the camera (a face more than 90 degrees off NEAR is
## back-facing to it) and the stream never crosses the shoulder stage; off the map; the
## flank is steeper than the falls rule's drop slope at every map size, so it steps down in
## falls; stepping stones over it below the foot (STONES_CHANCE). A hill without a crown
## always draws at least one more feature: when the seed drew neither the second hill nor
## the stream, it gets the second hill (never a bare mound; P5-4). A hill without a crown
## carries a flank ledge (P5-4b): a step in the camera-facing flank, the ground above a line
## LEDGE_HEIGHT_SHARE of the way up the hill raised to the next tier with
## HeightBrush.tier_goal over an arc of LEDGE_ARC_DEG about NEAR, as the Sculpt tool's Tier
## steps a slope; only ever raising, so the flank above the bench is the hill's own. The
## stage is on the hill's shoulder toward the camera (NEAR): STAGE_SHOULDER_SHARE of the
## radius out, past the crown's toe when there is a crown (STAGE_CROWN_TOE_M), at the foot of
## the ledge's face when there is a ledge (STAGE_LEDGE_TOE_M), within half the half extent
## of the centre.

const HILL_HEIGHT_M := 4.5
const HILL_RADIUS_SHARE := 0.45
const HILL_OFFSET_SHARE := 0.3
## 0.38: at 0.3 the crown read as a rock knob from the home camera (P5-2 look), its flat top
## 4 m across; this gives a 5 m stage with the face still a tier high.
const CROWN_RADIUS_SHARE := 0.38
## The crown's flat top is at least this wide (metres across; the face, lip and soft toe
## take HeightBrush.tier_span outside it), so a small map's crown is still a stage.
const CROWN_TOP_MIN_M := 4.0
## The crown's outline warps by this share of its radius; the second hill's radius (a share
## of the half extent) and how far from the centre it sits on the far side.
const CROWN_WARP := 0.12
const SECOND_HILL_RADIUS_SHARE := 0.3
const SECOND_HILL_OFFSET_SHARE := 0.55
const SECOND_HILL_HEIGHT_SHARE := 0.5
## Feature chances (the no-sameness palette). The crown 0.85 since P5-4b: a crownless hill
## read plainer than a crowned one even with its ledge.
const CROWN_CHANCE := 0.85
const SECOND_HILL_CHANCE := 0.3
const STREAM_CHANCE := 0.5
const STONES_CHANCE := 0.4
## The stream: ankle half-width, control points, wobble, how far off the camera's direction
## it runs (to the hill's side: past 90 the fall would face away from the camera, under 60
## it would cross the shoulder stage), how far inside the crown's outline the pool starts
## (at least the two metres WaterFallPlan keeps before a spring's first lip, plus the lip's
## own width); without a crown it rises this share of the radius from the summit.
const STREAM_HALF_WIDTH_M := 0.55
const STREAM_SPACING_M := 3.0
const STREAM_WOBBLE_M := 0.6
const STREAM_AZIMUTH_DEG := Vector2(60.0, 90.0)
const POOL_INSIDE_M := 3.0
const STREAM_SUMMIT_SHARE := 0.25
## The stones: below the foot, this far past the hill's radius at the nearest, and this far
## inside the map edge.
const STONES_PAST_FOOT_M := 1.0
const STONES_EDGE_M := 4.0
## The stage: this share of the radius out on the shoulder, and with a crown at least this
## far past the crown's face and soft toe (flat ground, off the rock); within
## STAGE_REACH_SHARE of the half extent of the centre.
const STAGE_SHOULDER_SHARE := 0.55
const STAGE_CROWN_TOE_M := 1.0
const STAGE_REACH_SHARE := 0.5
## The flank ledge of a crownless hill: its line stands on the tier nearest this share of the
## hill's height (at least one), the bench a tier above; the arc's full span about NEAR (the
## seed draws within it; under the stream's STREAM_AZIMUTH_DEG.x either side, so a stream
## never crosses the bench); the stage this far out past the ledge's line.
const LEDGE_HEIGHT_SHARE := 0.33
const LEDGE_ARC_DEG := Vector2(60.0, 100.0)
const STAGE_LEDGE_TOE_M := 1.5
## A stream's end stops this far inside the map edge (within WaterCarve.EDGE_MARGIN_M, so it
## runs off the map instead of tapering to a head).
const EDGE_MARGIN_M := 0.5


## The Hilltop on `doc` with `seed_value` (see the header). {"stage", "report"}.
static func hilltop(doc: MapDocument, seed_value: int, biome_id: String) -> Dictionary:
	var half := StartingLandform.half_extent(doc)
	var scale := StartingLandform.size_scale(doc)
	var tier := doc.tier_height_m
	var frame := hilltop_frame(
		half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
	)
	var centre: Vector2 = frame.centre
	var radius := half * HILL_RADIUS_SHARE
	var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
	var wants_crown := draws.randf() < CROWN_CHANCE
	var wants_second := draws.randf() < SECOND_HILL_CHANCE
	var wants_stream := draws.randf() < STREAM_CHANCE
	var wants_stones := draws.randf() < STONES_CHANCE
	if not wants_crown and not wants_second and not wants_stream:
		# Never a bare mound: a hill without a crown carries at least one more feature.
		wants_second = true
	var azimuth_sign := 1.0 if draws.randf() < 0.5 else -1.0
	var azimuth := StartingLandform.NEAR.rotated(
		azimuth_sign * deg_to_rad(draws.randf_range(STREAM_AZIMUTH_DEG.x, STREAM_AZIMUTH_DEG.y))
	)
	var summit := HILL_HEIGHT_M * scale
	var crown_radius := crown_radius_of(radius, tier)
	var crown := crown_of(summit, tier, crown_radius / radius)
	var height := summit if not wants_crown else float(crown.hill_height)
	var crown_noise := StartingLandform.warp_noise(draws, crown_radius)
	var ledge_arc := deg_to_rad(draws.randf_range(LEDGE_ARC_DEG.x, LEDGE_ARC_DEG.y))
	var ledge := ledge_of(height, tier, radius)
	var wants_ledge := not wants_crown and bool(ledge.fits)
	var ledge_r: float = ledge.line_r
	var ledge_target: float = ledge.target
	var second_centre: Vector2 = centre - frame.dir * half * SECOND_HILL_OFFSET_SHARE
	var second_radius := half * SECOND_HILL_RADIUS_SHARE
	var second_height := height * SECOND_HILL_HEIGHT_SHARE if wants_second else 0.0
	var target: float = crown.target
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var natural := height * StartingLandform.bump(p.distance_to(centre) / radius)
			if second_height > 0.0:
				natural += (
					second_height
					* StartingLandform.bump(p.distance_to(second_centre) / second_radius)
				)
			if wants_ledge:
				# Inside the band: above the ledge's line and within the arc (metres along the
				# line from the arc's nearer end). Only raising: uphill the hill stands above
				# the bench and keeps its own slope.
				var offset := p - centre
				var inside := minf(
					ledge_r - offset.length(),
					(ledge_arc * 0.5 - absf(StartingLandform.NEAR.angle_to(offset))) * ledge_r
				)
				var goal := HeightBrush.tier_goal(
					natural, ledge_target, StartingLandform.tier_inset(inside)
				)
				return h + maxf(natural, goal)
			if not wants_crown:
				return h + natural
			var distance := StartingLandform.disc_distance(
				p, centre, crown_radius, crown_noise, CROWN_WARP
			)
			return h + HeightBrush.tier_goal(natural, target, StartingLandform.tier_inset(distance))
	)
	var shoulder_out := radius * STAGE_SHOULDER_SHARE
	if wants_crown:
		shoulder_out = maxf(
			shoulder_out,
			crown_radius * (1.0 + CROWN_WARP) + HeightBrush.tier_span(tier) + STAGE_CROWN_TOE_M
		)
	if wants_ledge:
		shoulder_out = maxf(shoulder_out, ledge_r + STAGE_LEDGE_TOE_M)
	var stage := shoulder_stage(centre, shoulder_out, half)
	var report := PackedStringArray(
		[
			(
				"hilltop heading %d deg, %.1f m off centre, radius %.1f m"
				% [frame.heading_deg, frame.offset, radius]
			),
			(
				"crown at %.2f m (tier %d) over a %.2f m hill" % [target, crown.level, height]
				if wants_crown
				else "no crown, summit %.2f m" % height
			),
		]
	)
	if wants_ledge:
		report.append(
			(
				"flank ledge at %.2f m (tier %d) from %.1f m out over a %d deg arc"
				% [ledge_target, int(ledge.level), ledge_r, roundi(rad_to_deg(ledge_arc))]
			)
		)
	if wants_second:
		report.append(
			"second hill %.2f m at (%.1f, %.1f)" % [second_height, second_centre.x, second_centre.y]
		)
	if wants_stream:
		# With a crown the line starts on the crown, POOL_INSIDE_M inside its warped outline
		# along the azimuth (never past the centre), so the first reach is a pool on the top.
		var start_r := (
			maxf(
				(
					StartingLandform.disc_distance(
						centre + azimuth * crown_radius,
						centre,
						crown_radius,
						crown_noise,
						CROWN_WARP
					)
					+ crown_radius
					- POOL_INSIDE_M
				),
				0.0
			)
			if wants_crown
			else radius * STREAM_SUMMIT_SHARE
		)
		var start := centre + azimuth * start_r
		var line := StartingLandform.map_line(
			doc,
			PackedVector2Array([start, start + azimuth * 4.0 * half]),
			EDGE_MARGIN_M,
			STREAM_SPACING_M
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
			report.append(
				(
					"%sstream: %d reaches, %d falls"
					% [
						"crown pool, " if wants_crown else "",
						stream.size(),
						WaterFalls.falls(doc).size()
					]
				)
			)
			if wants_stones:
				report.append(_stones(doc, stream, centre, radius, biome_id))
		if not doc.water_bodies.is_empty():
			doc.water_dressing = WaterDressing.refresh(doc)
	else:
		report.append("dry")
	report.append("stage (%.1f, %.1f)" % [stage.x, stage.y])
	return {"stage": stage, "report": "; ".join(report)}


## The Hilltop's frame from the seed, for a map of half extent `half`: the hill's centre
## (offset along one of eight headings), the heading and the numbers the report quotes.
static func hilltop_frame(half: float, rng: RandomNumberGenerator) -> Dictionary:
	var heading_index := rng.randi_range(0, 7)
	var dir := Vector2(cos(heading_index * PI / 4.0), sin(heading_index * PI / 4.0))
	var offset := rng.randf_range(0.0, 1.0) * half * HILL_OFFSET_SHARE
	return {
		"centre": dir * offset,
		"dir": dir,
		"heading_deg": heading_index * 45,
		"offset": offset,
	}


## The crown's radius for a hill of `radius`: CROWN_RADIUS_SHARE of it, or enough for a flat
## top CROWN_TOP_MIN_M across inside the tier's face, lip and soft toe.
static func crown_radius_of(radius: float, tier: float) -> float:
	return maxf(
		radius * CROWN_RADIUS_SHARE,
		CROWN_TOP_MIN_M * 0.5 + HeightBrush.tier_span(tier) - HeightBrush.TIER_SOFTEN_M
	)


## The crown for a hill whose natural summit would be `summit`: the tier level nearest it
## (at least one), the crown's target height, and the height of the hill beneath, scaled so
## its natural profile stands one full tier below the target at the crown's nominal outline
## (`share` of the hill's radius): the face is a tier high all round. The hill never rises
## above the target (a wide crown on a low hill would ask for more), so the plateau only
## ever raises; the face is then still at least the target's share outside the outline.
static func crown_of(summit: float, tier: float, share: float) -> Dictionary:
	var level := maxi(1, roundi(summit / tier))
	var target := level * tier
	var at_outline := StartingLandform.bump(share)
	return {
		"level": level,
		"target": target,
		"hill_height": minf((target - tier) / at_outline, target),
	}


## The flank ledge of a crownless hill of `height` and `radius`: its line is where the hill's
## profile crosses the tier nearest LEDGE_HEIGHT_SHARE of the height (at least one), so the
## face is a full tier there; the bench stands on the next tier (`level`, `target`), and
## `line_r` is the line's distance from the centre. `fits` is false when the bench would
## reach the summit (a tier too tall for the hill), and the hill then has no ledge.
static func ledge_of(height: float, tier: float, radius: float) -> Dictionary:
	var below := maxi(1, roundi(height * LEDGE_HEIGHT_SHARE / tier))
	var line_height := below * tier
	var t := acos(clampf(2.0 * line_height / maxf(height, 1e-6) - 1.0, -1.0, 1.0)) / PI
	return {
		"level": below + 1,
		"target": (below + 1) * tier,
		"line_r": radius * t,
		"fits": (below + 1) * tier < height,
	}


## The shoulder stage: `out` metres from `centre` toward the camera (StartingLandform.NEAR),
## turned step by step toward the map centre until it lies within STAGE_REACH_SHARE of
## `half` of the centre (the azimuth toward the centre always does: `out` never exceeds the
## hill's radius).
static func shoulder_stage(centre: Vector2, out: float, half: float) -> Vector2:
	var reach := half * STAGE_REACH_SHARE
	var toward := (-centre).normalized() if centre.length() > 1e-3 else StartingLandform.NEAR
	var start := StartingLandform.NEAR
	var turn := start.angle_to(toward)
	for n in 10:
		var candidate := centre + start.rotated(turn * n / 9.0) * out
		if candidate.length() <= reach:
			return candidate
	return centre + toward * out


## Stepping stones over `stream` below the hill's foot: at the course point past
## `radius` + STONES_PAST_FOOT_M from `centre` nearest the foot, STONES_EDGE_M inside the
## map; else the lowest point on the flank that fits. The report line.
static func _stones(
	doc: MapDocument, stream: Array[WaterBody], centre: Vector2, radius: float, biome_id: String
) -> String:
	var course: PackedVector2Array = WaterCarve.joined_course(stream).points
	var best := -1
	var best_r := INF
	var fallback := -1
	var fallback_r := -INF
	var courses := WaterGeometry.river_courses(doc)
	for i in range(1, course.size() - 1):
		if not StartingLandform.inside(doc, course[i], STONES_EDGE_M):
			continue
		# Over water only (P5-7, as StartingLandform.straightest_wet for the other recipes).
		if not WaterGeometry.is_wet_at(doc, course[i], -1, courses):
			continue
		var r := course[i].distance_to(centre)
		if r >= radius + STONES_PAST_FOOT_M and r < best_r:
			best_r = r
			best = i
		if r > fallback_r:
			fallback_r = r
			fallback = i
	var at := best if best >= 0 else fallback
	if at < 0:
		return "stones: no room on the stream"
	var dir := (course[at + 1] - course[at - 1]).normalized()
	var placed := StartingLandform.place_crossing(
		doc, course[at], dir, Crossing.Kind.STONES, biome_id
	)
	if placed.crossing == null:
		return "stones refused (%s) at (%.1f, %.1f)" % [placed.refusal, course[at].x, course[at].y]
	return "stones at (%.1f, %.1f)" % [course[at].x, course[at].y]
