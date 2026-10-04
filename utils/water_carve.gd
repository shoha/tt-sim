class_name WaterCarve
extends RefCounted

## The ground a river or pond carves (phase 4, P4-3), pure: per-sample goal heights the
## editor lowers the document toward (HeightStroke.lower_to: min(start, goal), so a carve
## never raises ground), plus the rule for which rocks a carve keeps. Summary:
## docs/ARCHITECTURE.md "Carving water".
##
## Cross-section. Every carved sample has an edge offset e: its distance to the river's
## course minus the half-width there (a pond: its signed distance to the edge of the painted
## area), negative in the water. The waterline is at e = 0: ground there is cut to the
## level. Into the water the ground falls at the depth class's shore slope (soft for wading
## water, steeper for deep) to the flat bed, level - depth; away from it the bank rises at
## the bank slope until it meets the ground as it was. Both creases are rounded (a smooth
## maximum at the toe, TOE_SOFT_M, and an eased cut at the top of the bank, TOP_SOFT_M,
## blend_with_ground), so the banks read as worn earth, never a trench; the steepest bank
## (deep, 31 degrees) is below the cliff rule's 44, so no bank turns to rock unless the
## ground was rock already. A narrow channel steepens its shore slope, up to
## MAX_SHORE_SLOPE (42 degrees), so at least the middle BED_SHARE of its width is flat bed,
## and no channel is narrower than min_half_width() (WaterEdit.plan_river widens it): a
## V-shaped gully never reached its depth class. Beyond BANK_REACH_M the goal
## fades back to the ground over the last BANK_FADE_M, so a river through a high bank cuts
## a slope, not a wall at the reach.
##
## Along the river. A stroke is carved as one course (its reaches' courses joined, exactly
## the lines WaterGeometry derives their areas from) with a level and a bed line along its
## arc length s (bed_line()): each flat reach at its own level, the bed at level - depth.
## Toward the next reach the bed rises over a pool tail (pool_tail()) to a crest just under
## the upper level (CREST_M), exactly at the shared point; below it, a riffle falls at
## RIFFLE_SLOPE (smoothstep, so about 1.5 times that at its steepest) to the lower reach's
## bed, and the bank level follows. The upper reach's area ends flush at the shared point
## (WaterGeometry), so its flat water runs shallow over the crest to that line; the riffle
## below is the channel's bed (WaterDressing) under a thin sheet of water that follows it
## down to the lower reach (WaterMeshBuilder.cascades(): shallow enough that the shader
## draws it as white water, and in the flow bake): a small rapid, not a rock lip. A river end
## inside the map tapers its depth from zero over a pool tail (a spring or a sink) and its
## width to a rounded head (head_width(), P4-4), so the water neither stops in a round hole
## nor in a straight shallow line across the channel. An end that runs into existing water
## (a confluence, WaterEdit.join_line) is left open: full depth and width into that water.
##
## Falls (phase 4c, P4c-2). A step WaterFalls.fall_flags() marks (the upper reach stands
## FALL_MIN_DROP_M or more over the lower) is a waterfall, not a riffle: the pool tail still
## rises to a full crest (CREST_M under the upper level, whatever the depth: a fall is never
## the small step's low bar), and below the lip the bed follows fall_profile() (fall_shape()):
## the tier profile upside down (HeightBrush.soft_tier_offset, the tier face angle and its
## TIER_SOFTEN_M tent, so the face reads as rock at the default spacing and does not saw on a
## diagonal) with a harder lip (FALL_LIP_M over FALL_LIP_WIDTH_M), from the crest down to the
## plunge bed, WaterFalls.plunge_depth() under the lower reach's bed, then back up to that
## bed over WaterFalls.plunge_length(): a plunge pool. The bank level steps from the upper
## level to the lower over the same profile, a crest's height above the bed, so the face
## runs straight across the whole cut. Its side walls are a tight rock notch, not the face
## swept out at the bank slope (P4c-2b: on a hillside that cut a rock wall 8 m wide for a
## 1 m stream): across the face stretch the bank rises at FALL_BANK_SLOPE (rock by the cliff
## rule) and is cut no further out than FALL_BANK_REACH_M, the rule fading in over the pool
## tail above the lip and out over the plunge pool below the foot (fall_gorge(), the `gorge`
## share section() and blend_with_ground() take; 0 everywhere else, so a riffle's banks are
## exactly as before). The plunge pool widens only below the foot (WaterFalls.shape_line pins
## the channel's width at fall_foot() and widens the point half a plunge length past it), so
## the face is as wide as the stroke. Over a Tier cliff the lip stands at the brink
## (WaterFalls), the profile lies along the tier's own face and the carve cuts a notch
## CREST_M under the upper pool across the channel, the face itself a hand's breadth deeper,
## then the plunge pool at its foot; outside the channel and its banks the face is left as it
## was. The riffle sheet the mesh still drapes over a fall's face is replaced by a curtain in
## P4c-3.
##
## Ponds. A basin in the painted area (pond_goals()): the cross-section on the signed
## distance to the edge of the area (DistanceField), with a gently shelving beach at the
## waterline (pond_section(), P4-4) and the bed a little deeper toward the middle
## (POND_CENTRE_EXTRA), so it reads as a bowl with a soft shore.

## One cross-section per WaterBody.Depth: shore slope under the water, bank slope above it
## (rise over run). Ankle water wades in over a 1:4 shore; deep water shelves at 1:1.5.
const SHORE_SLOPE: Array[float] = [0.25, 0.4, 0.65]
const BANK_SLOPE: Array[float] = [0.33, 0.45, 0.6]
## Rounding of the crease at the toe of the shore (metres of height over which the two sides
## blend) and the cut over which the top of the bank eases in (blend_with_ground).
const TOE_SOFT_M := 0.25
const TOP_SOFT_M := 0.3
## The middle share of a channel's width that is flat bed at the least, and the steepest a
## narrow channel's shore gets to keep it (42 degrees, under the cliff rule's 44: a narrow
## channel is never a rock trench). Channels are at least min_half_width() wide.
const BED_SHARE := 0.25
const MAX_SHORE_SLOPE := 0.9
## How far past the waterline a bank may be cut, and the fade back to the ground before it.
const BANK_REACH_M := 6.0
const BANK_FADE_M := 2.0
## Reach steps: the crest's height over the upper level (just under it: the upper pool runs
## to the shared point, where its area stops flush and the cascade sheet takes over), and
## the riffle's mean slope.
const CREST_M := -0.05
const RIFFLE_SLOPE := 0.3
## A fall's lip (fall_profile()): how far below the crest the face begins and over what
## width the brink rounds, harder than a tier's (HeightBrush.TIER_LIP_M 0.25 over 0.5).
const FALL_LIP_M := 0.1
const FALL_LIP_WIDTH_M := 0.25
## A fall's side walls (fall_gorge(), P4c-2b): the bank slope across the face and the rock
## bowl at its foot (rise over run; 54 degrees, past the cliff rule's start, where the
## ordinary banks are 18 to 31) and how far out the cut may reach there (the fade before it
## is still BANK_FADE_M). An ankle stream falling 3.5 m down a 35 degree hill then cuts
## about a channel width and a half of rock either side at the foot, none at the lip.
const FALL_BANK_SLOPE := 1.4
const FALL_BANK_REACH_M := 4.0
## How high a small step's crest rises over the bed per metre of drop (step_shape()), the
## pool tail's mean slope up to the crest, and the taper at a river's ends per metre of depth;
## lengths clamped.
const CREST_RISE_PER_DROP := 3.0
const POOL_TAIL_SLOPE := 0.25
const POOL_TAIL_PER_DEPTH := 3.0
const POOL_TAIL_MIN_M := 1.5
const POOL_TAIL_MAX_M := 5.0
## A river end within this of the map edge runs off the map untapered.
const EDGE_MARGIN_M := 1.0
## A tapered river end's rounded head is at least this many half-widths long (head_width()),
## and holds at least this much water toward its tip (_end_depth()).
const HEAD_PER_WIDTH := 2.2
const HEAD_DEPTH_M := 0.14
## A pond's beach (pond_section()): the ground's slope at the waterline, how far it runs
## above and below it before the bank and shore slopes take over, and the rounding of the
## underwater brink (metres of height, smooth_min()).
const BEACH_SLOPE := 0.12
const BEACH_UP_M := 1.0
const BEACH_DOWN_M := 0.6
const BEACH_BRINK_M := 0.12
## A pond's bed deepens by this share of its depth toward the middle, over 4 m past the
## shore's toe.
const POND_CENTRE_EXTRA := 0.25
const POND_CENTRE_RUN_M := 4.0
## The half-width of the box mean (two passes) that rounds a pond's shoreline, and how far
## above the level the ground outside the painted area stays at the least.
const POND_EDGE_SMOOTH_M := 0.5
const POND_RIM_M := 0.02
## Under a pond's water the top-of-bank easing (blend_with_ground) fades out over this far
## from the waterline (P4-5): a small cut there is a basin being carved again (a stroke
## extending the pond), not the top of a bank, and eased it left the old basin's shore as a
## ledge under the new water.
const POND_UNDER_EASE_M := 1.2
## Rocks: a rock whose top stands less than this above the water is submerged; one wider
## than this share of the channel's width blocks it.
const SUBMERGED_MARGIN_M := 0.05
const BLOCKING_SHARE := 0.5


## Soft minimum of a and b over a blend of k (polynomial; never above min(a, b)).
static func smooth_min(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


## Soft maximum of a and b over a blend of k (never below max(a, b)).
static func smooth_max(a: float, b: float, k: float) -> float:
	return -smooth_min(-a, -b, k)


## The end taper length for `depth` metres of water.
static func pool_tail(depth: float) -> float:
	return clampf(depth * POOL_TAIL_PER_DEPTH, POOL_TAIL_MIN_M, POOL_TAIL_MAX_M)


## The share of its half-width `half_width` a channel keeps `s` metres from a tapered end
## (P4-4, a rounded head): a quarter ellipse, sqrt(t (2 - t)) for t = s / length, so the
## waterline closes round the end instead of stopping in a straight line across the channel
## where the bed taper (pool_tail()) brings the bed up to the level. The head is as long as
## the depth taper or HEAD_PER_WIDTH half-widths, whichever is longer; past the end (s <= 0)
## the channel has no width left, so the water's edge there is the end point itself.
static func head_width(s: float, half_width: float, depth: float) -> float:
	return head_shape(s, maxf(pool_tail(depth), half_width * HEAD_PER_WIDTH))


## The quarter ellipse sqrt(t (2 - t)), t = s / length clamped to 0..1: 0 at a river's end,
## 1 from `length` on.
static func head_shape(s: float, length: float) -> float:
	var t := clampf(s / maxf(length, 1e-4), 0.0, 1.0)
	return sqrt(t * (2.0 - t))


## The cross-section of a pond basin at edge offset `e` (a soft beach, P4-4): like section()
## with no narrowing, except that within BEACH_UP_M above the waterline and BEACH_DOWN_M
## below it the ground runs at BEACH_SLOPE, so the water meets its shore over a metre or so
## of gently shelving ground (the shader's shallows and foam draw a soft line there) instead
## of at a crisp bank the freeboard left standing over the water. Past the underwater beach
## the class's shore slope takes over through a rounded brink (BEACH_BRINK_M): a kink there,
## or a steeper shore, faces away from the camera on the far side of the pond, where the
## water shader's depth-slope foam drew it as a white line across the water.
static func pond_section(e: float, level: float, bed: float, depth: int) -> float:
	var line := level
	if e >= 0.0:
		line += BEACH_SLOPE * minf(e, BEACH_UP_M) + BANK_SLOPE[depth] * maxf(e - BEACH_UP_M, 0.0)
	else:
		var beach := level + BEACH_SLOPE * e
		var shore := level - BEACH_SLOPE * BEACH_DOWN_M + SHORE_SLOPE[depth] * (e + BEACH_DOWN_M)
		line = smooth_min(beach, shore, BEACH_BRINK_M)
	return smooth_max(bed, line, TOE_SOFT_M)


## The shape of a reach step from level `upper` to `lower` at `depth` (see the header):
## Vector3(crest height, pool tail length above it, riffle length below it). The crest
## rises as far as the step needs: to just under the upper level (CREST_M) for a full step,
## but only CREST_RISE_PER_DROP times the drop over the bed for a small one, so a 10 cm step
## in a deep river is a low bar, not a weir across it. `full` (a fall) skips that rule: the
## crest is always the full one.
static func step_shape(upper: float, lower: float, depth: float, full: bool = false) -> Vector3:
	var below := -CREST_M
	if not full:
		below = maxf(-CREST_M, depth - CREST_RISE_PER_DROP * maxf(upper - lower, 0.0))
	var crest := upper - below
	var tail := clampf(
		(crest - (upper - depth)) / POOL_TAIL_SLOPE, POOL_TAIL_MIN_M, POOL_TAIL_MAX_M
	)
	var riffle := maxf((crest - (lower - depth)) / RIFFLE_SLOPE, 1.0)
	return Vector3(crest, tail, riffle)


## The riffle length below a reach step from level `upper` to `lower` at `depth`.
static func riffle_length(upper: float, lower: float, depth: float) -> float:
	return step_shape(upper, lower, depth).z


## The horizontal run of a fall's face profile (fall_profile()) losing `drop` metres: the
## soft profile's tent on both sides, the lip's width and the face at the tier angle.
static func fall_run(drop: float) -> float:
	var lip := minf(FALL_LIP_M, drop * HeightBrush.TIER_LIP_SHARE)
	return (
		HeightBrush.tier_face_width(drop - lip) + FALL_LIP_WIDTH_M + 2.0 * HeightBrush.TIER_SOFTEN_M
	)


## How far a fall's face has dropped `x` metres past its lip, of `drop` in all (see the
## header): HeightBrush.soft_tier_offset upside down, with the harder lip FALL_LIP_M over
## FALL_LIP_WIDTH_M, the tier face angle (HeightBrush.TIER_FACE_DEG) and the same
## TIER_SOFTEN_M tent. Exactly 0 at and before the lip (x <= 0: the crest), exactly `drop`
## from fall_run(drop) on, monotonic and C1 between; the brink rounds over the first
## TIER_SOFTEN_M + FALL_LIP_WIDTH_M, the face stands below it.
static func fall_profile(x: float, drop: float) -> float:
	if drop <= 0.0 or x <= 0.0:
		return 0.0
	var lip := minf(FALL_LIP_M, drop * HeightBrush.TIER_LIP_SHARE)
	var face := HeightBrush.tier_face_width(drop - lip)
	var top := face + FALL_LIP_WIDTH_M + HeightBrush.TIER_SOFTEN_M
	return drop - HeightBrush.soft_tier_offset(top - x, drop, lip, face, FALL_LIP_WIDTH_M)


## How far past its lip the carved face of a fall of `drop` metres into water `depth` deep
## runs before the plunge bed (fall_shape()): fall_run() of the rise from the crest (CREST_M
## over the upper level) to the plunge bed (WaterFalls.plunge_depth() under the lower bed).
## The plunge pool's widening (WaterFalls.shape_line) and the side-wall rule (fall_gorge())
## start here.
static func fall_foot(drop: float, depth: float) -> float:
	return fall_run(drop + CREST_M + depth + WaterFalls.plunge_depth(drop))


## How much of a fall's side-wall rule (FALL_BANK_SLOPE, FALL_BANK_REACH_M; see the header)
## applies `x` metres past the lip of a fall of `drop` metres into water `depth` deep: 1 down
## the face to its foot (fall_foot()), then fading to 0 over WaterFalls.plunge_length() with
## the plunge pool's basin, so the rock bowl at the foot opens into the pool's ordinary banks.
## The fade in over the pool tail above the lip is bed_line()'s.
static func fall_gorge(x: float, drop: float, depth: float) -> float:
	var foot := fall_foot(drop, depth)
	return 1.0 - smoothstep(foot, foot + WaterFalls.plunge_length(drop), x)


## Vector2(bank level, bed height) `x` metres past the lip of a fall from level `upper` into
## level `lower` at `depth` (see the header). The bed follows fall_profile() from the crest
## (upper + CREST_M) down to the plunge bed (the lower bed less WaterFalls.plunge_depth()) at
## the profile's foot (fall_foot()), then rises back to the lower bed over
## WaterFalls.plunge_length(): the plunge pool is deepest at the foot of the face. The bank
## level follows the same profile a crest's height above the bed, from the upper level down
## to the lower, where it stays: so the face runs straight across the whole cut (section()
## shelves only the crest's height at the waterline; a bank following a shorter profile of
## the drop alone left a V down the face), its side walls are the face raised by the gorge's
## bank slope (fall_gorge(): rock, a tight notch), and under the lower level the face runs
## on down to the plunge bed through the channel's steepened shore.
static func fall_shape(x: float, upper: float, lower: float, depth: float) -> Vector2:
	var drop := upper - lower
	var crest := upper + CREST_M
	var plunge := WaterFalls.plunge_depth(drop)
	var rise := drop + CREST_M + depth + plunge
	var foot := fall_run(rise)
	var face := crest - fall_profile(x, rise)
	var basin := plunge * (1.0 - smoothstep(foot, foot + WaterFalls.plunge_length(drop), x))
	var bed := maxf(face, lower - depth - basin)
	var bank := maxf(lower, face - CREST_M)
	return Vector2(bank, bed)


## The cross-section's goal at edge offset `e` (see the header) for water at `level` over a
## bed at `bed`, `depth` class Depth, half-width `half_width` (0 for a pond: no narrowing).
## `gorge` (0..1, fall_gorge()) moves the bank slope from the class's to FALL_BANK_SLOPE
## across a fall's face; at 0 the section is exactly the ordinary one.
static func section(
	e: float, level: float, bed: float, depth: int, half_width: float, gorge: float = 0.0
) -> float:
	var shore := SHORE_SLOPE[depth]
	var full := level - bed
	if half_width > 0.0 and full > 0.0:
		shore = clampf(full / (half_width * (1.0 - BED_SHARE)), shore, MAX_SHORE_SLOPE)
	var bank := lerpf(BANK_SLOPE[depth], FALL_BANK_SLOPE, gorge)
	var line := level + e * (shore if e < 0.0 else bank)
	return smooth_max(bed, line, TOE_SOFT_M)


## The final goal of a sample whose ground is `start`: the cross-section goal `goal` met
## with the ground, faded back to the ground past the bank reach at edge offset `e` (the
## reach moving from BANK_REACH_M to FALL_BANK_REACH_M with `gorge`, fall_gorge(); the fade
## before it stays BANK_FADE_M). Where the goal is within TOP_SOFT_M below the ground the cut
## eases in (lowered by d^2 (2 - d / k) / k for a wanted cut d, k = TOP_SOFT_M: no cut at 0,
## the full cut from k, smooth at both), so the top of a bank is rounded and the carve meets
## the untouched ground without a crease. The easing only ever cuts less than asked, never
## more, so a crest or a waterline is never dug below its goal. Never above `start`.
static func blend_with_ground(goal: float, start: float, e: float, gorge: float = 0.0) -> float:
	var cut := start - goal
	if cut <= 0.0:
		return start
	if cut < TOP_SOFT_M:
		cut = cut * cut * (2.0 - cut / TOP_SOFT_M) / TOP_SOFT_M
	var reach := lerpf(BANK_REACH_M, FALL_BANK_REACH_M, gorge)
	var fade := smoothstep(reach - BANK_FADE_M, reach, e)
	return start - cut * (1.0 - fade)


## The narrowest half-width a channel of `depth` class keeps: at MAX_SHORE_SLOPE, its bed is
## still flat over BED_SHARE of the width (a deep river is at least about 6 m wide).
static func min_half_width(depth: int) -> float:
	return WaterBody.depth_for(depth) / (MAX_SHORE_SLOPE * (1.0 - BED_SHARE))


## Vector3(bank level, bed height, gorge share) at arc length `s` of a carved course (see the
## header): `bounds` holds the arc lengths of the n - 1 shared points between its n reaches,
## `levels` the reaches' levels, `total` the course length; `taper` Vector2i(start, end) says
## which ends taper (inside the map); `falls` (WaterFalls.fall_flags, one byte per shared
## point) marks the steps that are waterfalls (fall_shape()) rather than riffles. The gorge
## share (section() and blend_with_ground()) is fall_gorge() below a fall's lip, rises over
## the pool tail above one (with the bed, to 1 at the lip) and is 0 everywhere else.
static func bed_line(
	s: float,
	bounds: PackedFloat32Array,
	levels: PackedFloat32Array,
	depth: float,
	total: float,
	taper: Vector2i,
	falls: PackedByteArray
) -> Vector3:
	var n := levels.size()
	var k := 0
	while k < n - 1 and s > bounds[k]:
		k += 1
	var level := levels[k]
	var bed := level - depth
	var bank := level
	var gorge := 0.0
	var tail := pool_tail(depth)
	var fall_above := k > 0 and k - 1 < falls.size() and falls[k - 1] != 0
	if fall_above:
		# The fall's face and plunge pool shape the whole bed from the lip; the next pool tail
		# then rises from whatever they left.
		var shaped := fall_shape(s - bounds[k - 1], levels[k - 1], level, depth)
		bank = shaped.x
		bed = shaped.y
		gorge = fall_gorge(s - bounds[k - 1], levels[k - 1] - level, depth)
	if k < n - 1:
		var full := k < falls.size() and falls[k] != 0
		var next := step_shape(level, levels[k + 1], depth, full)
		var rising := smoothstep(bounds[k] - next.y, bounds[k], s)
		bed = lerpf(bed, next.x, rising)
		if full:
			gorge = maxf(gorge, rising)
	if k > 0 and not fall_above:
		var upper := levels[k - 1]
		var step := step_shape(upper, level, depth)
		var t := smoothstep(bounds[k - 1], bounds[k - 1] + step.z, s)
		bed = maxf(bed, lerpf(step.x, level - depth, t))
		bank = lerpf(upper, level, t)
	# A tapered end lifts the bed toward the level over its pool tail. A plunge pool (the only
	# bed under the flat bed) is carried past that lift and fades with the depth it leaves, so
	# the taper's max never fills it in.
	var flat := level - depth
	var plunge := maxf(flat - bed, 0.0)
	bed = maxf(bed, flat)
	if taper.x != 0:
		var left := _end_depth(depth, tail, s)
		bed = maxf(bed, level - left)
		plunge *= left / depth
	if taper.y != 0:
		var left := _end_depth(depth, tail, total - s)
		bed = maxf(bed, level - left)
		plunge *= left / depth
	return Vector3(bank, bed - plunge, gorge)


## The depth left `s` metres from a tapered end: the depth tapered from zero over the pool
## tail, but never shallower than a HEAD_DEPTH_M film shaped like the rounded head
## (head_shape()), so the water reaches round the head instead of stopping where the taper
## runs out.
static func _end_depth(depth: float, tail: float, s: float) -> float:
	var film := minf(HEAD_DEPTH_M, depth) * head_shape(s, tail)
	return maxf(depth * smoothstep(0.0, tail, s), film)


## The joined course of one stroke's reaches `bodies` (rivers, in order, each starting where
## the previous ends): {"points", "widths" (per point), "arc" (arc length per point),
## "bounds" (arc length of each shared point), "levels" (per reach)}, the lines
## WaterGeometry.river_course() derives each reach's area from.
static func joined_course(bodies: Array[WaterBody]) -> Dictionary:
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var arc := PackedFloat32Array()
	var bounds := PackedFloat32Array()
	var levels := PackedFloat32Array()
	for b in bodies.size():
		var course := WaterGeometry.river_course(bodies[b])
		var line: PackedVector2Array = course[0]
		var sizes: PackedFloat32Array = course[1]
		levels.append(bodies[b].level_m)
		for i in line.size():
			if b > 0 and i == 0:
				continue
			var at := 0.0 if points.is_empty() else arc[-1] + points[-1].distance_to(line[i])
			points.append(line[i])
			widths.append(sizes[i])
			arc.append(at)
		if b < bodies.size() - 1:
			bounds.append(arc[-1])
	return {"points": points, "widths": widths, "arc": arc, "bounds": bounds, "levels": levels}


## Goal heights of a river stroke's carve over `doc`'s sample grid, from ground `start`
## (the heights before the carve): {"rect": Rect2i of the samples reached, "goals":
## PackedFloat32Array over the rect, row-major, INF where the carve leaves the ground}.
## `bodies` are the stroke's reaches (joined_course()), all of one depth class.
static func river_goals(
	doc: MapDocument, bodies: Array[WaterBody], start: PackedFloat32Array
) -> Dictionary:
	if bodies.is_empty():
		return {"rect": Rect2i(), "goals": PackedFloat32Array()}
	var joined := joined_course(bodies)
	var points: PackedVector2Array = joined.points
	var widths: PackedFloat32Array = joined.widths
	var arc: PackedFloat32Array = joined.arc
	var depth_class := int(bodies[0].depth)
	var depth := WaterBody.depth_for(depth_class)
	var total: float = arc[-1] if not arc.is_empty() else 0.0
	var half := doc.extent_m() * 0.5
	var inside := func(p: Vector2) -> int:
		var margin := half - Vector2(EDGE_MARGIN_M, EDGE_MARGIN_M)
		return 1 if absf(p.x) < margin.x and absf(p.y) < margin.y else 0
	# An end that runs into existing water (a confluence, WaterEdit.join_line) stays open.
	var open_end := func(p: Vector2) -> int: return 0 if WaterGeometry.is_wet_at(doc, p) else 1
	var taper := Vector2i(
		inside.call(points[0]) * open_end.call(points[0]),
		inside.call(points[-1]) * open_end.call(points[-1])
	)
	var widest := 0.0
	for w in widths:
		widest = maxf(widest, w)
	var reach := widest + BANK_REACH_M
	var origin := -half
	var step := doc.sample_step()
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	var rect := _cells_in(WaterGeometry.bounds(points, reach), origin, step, grid)
	var count := rect.size.x * rect.size.y
	var distance := PackedFloat32Array()
	var along := PackedFloat32Array()
	var half_width := PackedFloat32Array()
	distance.resize(count)
	distance.fill(INF)
	along.resize(count)
	half_width.resize(count)
	for s in points.size() - 1:
		var a := points[s]
		var segment := points[s + 1] - a
		var length_sq := segment.length_squared()
		if length_sq <= 1e-12:
			continue
		var length := sqrt(length_sq)
		var box := Rect2(a, Vector2.ZERO).expand(points[s + 1]).grow(reach)
		var cells := _cells_in(box, origin, step, grid).intersection(rect)
		for j in range(cells.position.y, cells.end.y):
			var z := origin.y + j * step.y
			var row := (j - rect.position.y) * rect.size.x - rect.position.x
			for i in range(cells.position.x, cells.end.x):
				var p := Vector2(origin.x + i * step.x, z)
				var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
				var d := p.distance_to(a + segment * t)
				var k := row + i
				if d < distance[k]:
					distance[k] = d
					along[k] = arc[s] + t * length
					half_width[k] = lerpf(widths[s], widths[s + 1], t)
	var goals := PackedFloat32Array()
	goals.resize(count)
	goals.fill(INF)
	var columns := doc.samples_x()
	var bounds: PackedFloat32Array = joined.bounds
	var levels: PackedFloat32Array = joined.levels
	var falls := WaterFalls.fall_flags(bodies)
	for j in rect.size.y:
		for i in rect.size.x:
			var k := j * rect.size.x + i
			var hw := half_width[k]
			# A tapered end narrows to a rounded head (head_width()).
			if taper.x != 0:
				hw *= head_width(along[k], hw, depth)
			if taper.y != 0:
				hw *= head_width(total - along[k], hw, depth)
			var e := distance[k] - hw
			if e >= BANK_REACH_M:
				continue
			var line := bed_line(along[k], bounds, levels, depth, total, taper, falls)
			var ground := start[(rect.position.y + j) * columns + rect.position.x + i]
			var goal := section(e, line.x, line.y, depth_class, hw, line.z)
			goal = blend_with_ground(goal, ground, e, line.z)
			if goal < ground:
				goals[k] = goal
	return {"rect": rect, "goals": goals}


## Goal heights of the basin of pond `body` over `doc`'s sample grid (its area is the
## pond_mask samples holding its id), from ground `start`; as river_goals(). Empty when the
## pond has no area.
static func pond_goals(doc: MapDocument, body: WaterBody, start: PackedFloat32Array) -> Dictionary:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var mask := doc.pond_mask
	var empty := {"rect": Rect2i(), "goals": PackedFloat32Array()}
	if mask.size() != doc.sample_count():
		return empty
	var area := Rect2i()
	for z in rows:
		for x in columns:
			if mask[z * columns + x] == body.id:
				area = MaskBrush.merge_rect(area, Rect2i(x, z, 1, 1))
	if not area.has_area():
		return empty
	var step := doc.sample_step()
	var pad := ceili(BANK_REACH_M / minf(step.x, step.y)) + 1
	var rect := area.grow(pad).intersection(Rect2i(0, 0, columns, rows))
	var count := rect.size.x * rect.size.y
	var in_pond := PackedByteArray()
	var out_pond := PackedByteArray()
	in_pond.resize(count)
	out_pond.resize(count)
	for j in rect.size.y:
		for i in rect.size.x:
			var k := j * rect.size.x + i
			var mine := mask[(rect.position.y + j) * columns + rect.position.x + i] == body.id
			in_pond[k] = 1 if mine else 0
			out_pond[k] = 0 if mine else 1
	# Inside: distance to the nearest sample outside; outside: to the nearest sample inside.
	# The edge lies half a step from each.
	var to_outside: PackedFloat32Array = (
		DistanceField.transform(out_pond, rect.size.x, rect.size.y, step).distance_sq
	)
	var to_inside: PackedFloat32Array = (
		DistanceField.transform(in_pond, rect.size.x, rect.size.y, step).distance_sq
	)
	var half_step := 0.5 * minf(step.x, step.y)
	var depth := body.depth_m()
	var level := body.level_m
	var shore := SHORE_SLOPE[body.depth]
	var toe := depth / shore
	# The signed distance to the edge, smoothed so the shoreline follows the painted area's
	# outline, not the staircase of its samples.
	var edge := PackedFloat32Array()
	edge.resize(count)
	for k in count:
		var d := sqrt(to_outside[k] if in_pond[k] == 1 else to_inside[k]) - half_step
		edge[k] = -d if in_pond[k] == 1 else d
	var radius := maxi(1, roundi(POND_EDGE_SMOOTH_M / minf(step.x, step.y)))
	for _pass in 2:
		edge = _box_blur(edge, rect.size, radius)
	var goals := PackedFloat32Array()
	goals.resize(count)
	goals.fill(INF)
	for j in rect.size.y:
		for i in rect.size.x:
			var k := j * rect.size.x + i
			var e := edge[k]
			if e >= BANK_REACH_M:
				continue
			var centre := smoothstep(toe, toe + POND_CENTRE_RUN_M, -e)
			var bed := level - depth * (1.0 + POND_CENTRE_EXTRA * centre)
			var ground := start[(rect.position.y + j) * columns + rect.position.x + i]
			var section := pond_section(e, level, bed, body.depth)
			var goal := blend_with_ground(section, ground, e)
			if e < 0.0:
				var eased := smoothstep(-POND_UNDER_EASE_M, 0.0, e)
				goal = lerpf(minf(section, ground), goal, eased)
			# Outside the painted area nothing sinks under the level: water there would end in
			# the air (it is not the pond's).
			if in_pond[k] == 0:
				goal = maxf(goal, minf(ground, level + POND_RIM_M))
			if goal < ground:
				goals[k] = goal
	return {"rect": rect, "goals": goals}


## The rock policy of a carve (see docs/ARCHITECTURE.md "Carving water"): true when a rock
## row (ScatterRows layout) of an asset `height_m` tall and `footprint_m` in footprint radius
## (both at scale 1) stays after the carve. `level` is the water level at the rock (DRY
## where it is out of the water) and `channel_m` the width of the channel there (0 in a
## pond). A rock out of the water stays (rocks survive terrain changes); one whose top is
## under the surface is gone; one wider than BLOCKING_SHARE of the channel is gone; a rock
## breaking the surface stays (the water's edge foam wraps it).
static func keeps_rock(
	row: PackedFloat32Array, height_m: float, footprint_m: float, level: float, channel_m: float
) -> bool:
	if is_inf(level) or level == WaterGeometry.DRY:
		return true
	var scale := absf(row[7])
	var base := row[1]
	if base >= level:
		return true
	if base + height_m * scale <= level + SUBMERGED_MARGIN_M:
		return false
	if channel_m > 0.0 and 2.0 * footprint_m * scale > BLOCKING_SHARE * channel_m:
		return false
	return true


## A box mean of `values` (row-major, `size` cells) over (2 radius + 1)^2 cells, edges
## replicated, as a horizontal then a vertical running sum.
static func _box_blur(
	values: PackedFloat32Array, size: Vector2i, radius: int
) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(values.size())
	var window := float(2 * radius + 1)
	for j in size.y:
		var base := j * size.x
		var sum := 0.0
		for d in range(-radius, radius + 1):
			sum += values[base + clampi(d, 0, size.x - 1)]
		for i in size.x:
			rows[base + i] = sum / window
			sum += values[base + mini(i + radius + 1, size.x - 1)]
			sum -= values[base + maxi(i - radius, 0)]
	var out := PackedFloat32Array()
	out.resize(values.size())
	for i in size.x:
		var sum := 0.0
		for d in range(-radius, radius + 1):
			sum += rows[clampi(d, 0, size.y - 1) * size.x + i]
		for j in size.y:
			out[j * size.x + i] = sum / window
			sum += rows[mini(j + radius + 1, size.y - 1) * size.x + i]
			sum -= rows[maxi(j - radius, 0) * size.x + i]
	return out


## The grid cells whose positions fall inside `box` (WaterGeometry's rule).
static func _cells_in(box: Rect2, origin: Vector2, step: Vector2, size: Vector2i) -> Rect2i:
	var low := ((box.position - origin) / step).ceil()
	var high := ((box.end - origin) / step).floor()
	var first := Vector2i(maxi(0, int(low.x)), maxi(0, int(low.y)))
	var last := Vector2i(mini(size.x - 1, int(high.x)), mini(size.y - 1, int(high.y)))
	if last.x < first.x or last.y < first.y:
		return Rect2i(first, Vector2i.ZERO)
	return Rect2i(first, last - first + Vector2i.ONE)
