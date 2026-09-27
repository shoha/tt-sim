class_name HeightBrush
extends RefCounted

## The pure rules behind authoring's sculpt operations on MapDocument.heights: how far one
## exposure raises or lowers a sample, how smoothing and flattening pull it toward a goal,
## and the steep profile a tier step uses. HeightStroke applies them over a brush capsule;
## the P3-5 Sculpt tool picks the operation and its target. Every function is pure.
##
## Weights. A sample's weight is MaskBrush.falloff(distance / radius), (1 - t^2)^2, the same
## soft profile the mask brushes use, so a raised hill has no crease at its rim.
##
## Tiers. TIER (up) and TIER_CUT (down) do not use a weight: they build a shape. Each sample
## remembers how far inside the brush the stroke has reached it (its inset, metres from the
## ring's edge, the largest over all dabs), and its goal is tier_goal() of its height when
## the stroke began, the stroke's target (a whole tier, k * tier_height_m) and that inset:
## the cliff profile the user chose, a near-vertical face at the ring's edge (TIER_FACE_DEG,
## steeper than TerrainRules' full-rock slope, so the automatic cliff rule turns it into the
## biome's rock), a rounded lip of TIER_LIP_M over TIER_LIP_WIDTH_M at its top (a convex
## shoulder the lip rule keeps grassy), then the flat top exactly at the target. The foot is
## left sharp and concave for the scree rule. A tier only ever raises (TIER) or only ever
## cuts (TIER_CUT), so strokes over an existing tier leave it and higher ground alone.
## The goal is geometry, not exposure: a held brush does not climb past the tier.
##
## Exposure. Like the mask brushes, a dab carries `seconds` of exposure (the frame's time
## times flow times BrushTool's dwell gain). Raise and lower are linear in it
## (raise_speed() metres per second at full weight), so a held brush keeps building. Smooth,
## flatten and tier approach their goal by MaskBrush.amount() = 1 - exp(-rate * weight *
## seconds) of the remaining way: frame-rate independent, and they never overshoot (a tier
## at full weight, so it rises in a fraction of a second and snaps onto its goal within
## TIER_SNAP_M; HeightStroke.complete() finishes it when the stroke ends).
##
## Limits. Every result is clamped to +-MapDocument.MAX_ABS_HEIGHT_M, the range the
## document reader accepts, so a sculpted map always saves and loads.

const RAISE := 0
const LOWER := 1
const SMOOTH := 2
const FLATTEN := 3
const TIER := 4
const TIER_CUT := 5

## Metres per second of exposure at full weight for raise and lower, per metre of brush
## radius (at least RAISE_MIN_M_PER_S): a hill keeps its proportions whatever the brush
## size, so a few seconds of dwell make a rounded hill about half as high as it is wide
## rather than a spire (P3-5 look pass: a flat 1.5 m/s turned a 5 m brush held for 3 s into
## a 7 m rock cone).
const RAISE_PER_RADIUS := 0.1
const RAISE_MIN_M_PER_S := 0.2
## Approach rates (per second at full weight) of smooth, flatten and tier.
const SMOOTH_RATE := 4.0
const FLATTEN_RATE := 4.0
const TIER_RATE := 10.0
## Smoothing averages over a square window whose half-width is this fraction of the brush
## radius (at least one sample): a big brush smooths broad shapes, a small one detail.
## 0.35: a few passes of a 2.5 m brush across a tier face lay it back into a walkable ramp
## (at 0.15 the window was one or two samples and a face barely softened).
const SMOOTH_KERNEL_FRACTION := 0.35
## The tier face's angle from horizontal. The shading normals are central differences over
## two sample steps, so a face this steep reads well past TerrainRules.CLIFF_END_DEG (full
## rock) at the 0.25 m spacing (test_tier_face_is_rock_at_the_default_spacing).
const TIER_FACE_DEG := 74.0
## The face is never narrower than this (metres): about 1.2 samples at the default spacing,
## so the face is interpolated across the grid rather than stair-stepping along it.
const TIER_MIN_FACE_M := 0.3
## The rounded lip: how far below the top the face ends, and over what width the shoulder
## rounds up to the top (an ease-out, flat at the top). At most TIER_LIP_SHARE of the rise.
const TIER_LIP_M := 0.25
const TIER_LIP_WIDTH_M := 0.8
const TIER_LIP_SHARE := 0.3
## A height within this of a whole tier stands on that tier (a tier top; a lip does not).
const TIER_ON_TOLERANCE_M := 0.05
## A tier sample this close to its goal takes the goal exactly, so tops end at k * tier_m.
const TIER_SNAP_M := 0.002


## Weight of a sample at `t` = distance / radius for operation `op`. Tiers are at full
## weight everywhere inside the ring (their shape is tier_goal()'s, not a falloff's).
static func weight(op: int, t: float) -> float:
	if op == TIER or op == TIER_CUT:
		return 1.0 if t < 1.0 else 0.0
	return MaskBrush.falloff(t)


## True for the two tier operations.
static func is_tier(op: int) -> bool:
	return op == TIER or op == TIER_CUT


## Horizontal width (metres) of a tier face that rises `rise` metres: TIER_FACE_DEG, never
## narrower than TIER_MIN_FACE_M.
static func tier_face_width(rise: float) -> float:
	return maxf(TIER_MIN_FACE_M, absf(rise) / tan(deg_to_rad(TIER_FACE_DEG)))


## The height a tier stroke gives a sample that stood at `start` when the stroke began, for
## a stroke toward `target`, the stroke having reached `inset` metres inside the ring's edge
## (<= 0: not reached). Raising (target above start): the face rises from the ring's edge to
## TIER_LIP_M below the target, the lip rounds up to the target, then the top is flat.
## Cutting (target below start): mirrored, so the rounded lip is the rim of the cut, on the
## ground the cut goes into: the rim rounds down, the face drops, then the floor is flat.
## Returns exactly `target` on the flat part.
static func tier_goal(start: float, target: float, inset: float) -> float:
	if inset <= 0.0 or start == target:
		return start
	var rise := absf(target - start)
	var lip := minf(TIER_LIP_M, rise * TIER_LIP_SHARE)
	var face := tier_face_width(rise - lip)
	var offset := rise
	if target > start:
		if inset < face:
			offset = (rise - lip) * inset / face
		elif inset < face + TIER_LIP_WIDTH_M:
			var u := 1.0 - (inset - face) / TIER_LIP_WIDTH_M
			offset = rise - lip * u * u
		else:
			return target
		return start + offset
	if inset < TIER_LIP_WIDTH_M:
		var u := inset / TIER_LIP_WIDTH_M
		offset = lip * u * u
	elif inset < TIER_LIP_WIDTH_M + face:
		offset = lip + (rise - lip) * (inset - TIER_LIP_WIDTH_M) / face
	else:
		return target
	return start - offset


## True when `height` stands on a whole tier (within TIER_ON_TOLERANCE_M).
static func on_tier(height: float, tier_m: float) -> bool:
	if tier_m <= 0.0:
		return false
	return absf(height - tier_level(height, tier_m) * tier_m) <= TIER_ON_TOLERANCE_M


## The tier level a Tier stroke pressed at ground height `press` builds toward. Up (`down`
## false): from a tier top, that same tier when the brush reaches lower ground
## (`lower_near`, so a stroke from a tier's edge extends it) and else the tier above (a
## stroke inside a top steps up); from anywhere between tiers, the next tier up. Down
## mirrors it with `higher_near`: the tier below from inside a top, that tier when higher
## ground is in reach (cutting it down to the press level), the tier below from between.
## Flat ground is tier 0, so the first stroke raises tier 1 and a Ctrl stroke sinks tier -1.
static func tier_target_level(
	press: float, tier_m: float, down: bool, lower_near: bool, higher_near: bool
) -> int:
	if tier_m <= 0.0:
		return 0
	if on_tier(press, tier_m):
		var level := tier_level(press, tier_m)
		if down:
			return level if higher_near else level - 1
		return level if lower_near else level + 1
	if down:
		return floori(press / tier_m)
	return ceili(press / tier_m)


## Whether any sample of `doc` within `radius` metres of document XZ `centre` lies clearly
## below (x = 1) or above (y = 1) `level_height`: more than half a tier (`tier_m`) away, so
## a tier's own lip and slight unevenness do not count.
static func tier_neighbours(
	doc: MapDocument, centre: Vector2, radius: float, level_height: float, tier_m: float
) -> Vector2i:
	var found := Vector2i.ZERO
	if doc.heights.size() != doc.sample_count():
		return found
	var rect := MaskBrush.capsule_rect(doc, centre, centre, radius)
	var low := level_height - tier_m * 0.5
	var high := level_height + tier_m * 0.5
	var origin := -doc.extent_m() * 0.5
	var step := doc.sample_step()
	var width := doc.samples_x()
	var radius_sq := radius * radius
	for z in range(rect.position.y, rect.end.y):
		var dz := origin.y + z * step.y - centre.y
		for x in range(rect.position.x, rect.end.x):
			var dx := origin.x + x * step.x - centre.x
			if dx * dx + dz * dz >= radius_sq:
				continue
			var h := doc.heights[z * width + x]
			if h < low:
				found.x = 1
			elif h > high:
				found.y = 1
			if found == Vector2i.ONE:
				return found
	return found


## `height` clamped to the document's accepted range.
static func clamp_height(height: float) -> float:
	return clampf(height, -MapDocument.MAX_ABS_HEIGHT_M, MapDocument.MAX_ABS_HEIGHT_M)


## Metres per second a raise or lower of brush radius `radius` (metres) moves the ground at
## full weight: RAISE_PER_RADIUS x radius, at least RAISE_MIN_M_PER_S.
static func raise_speed(radius: float) -> float:
	return maxf(RAISE_MIN_M_PER_S, RAISE_PER_RADIUS * radius)


## Raise (`direction` 1) or lower (-1) by `speed` (raise_speed()) x `w` x `seconds`.
static func raise(
	height: float, w: float, seconds: float, direction: float = 1.0, speed: float = 1.0
) -> float:
	return clamp_height(height + direction * speed * w * seconds)


## `height` moved toward `goal` by amount(w, seconds, rate): the step smooth (goal = the
## local mean), flatten (goal = the target) and tier (goal = the tier height) share.
static func approach(height: float, goal: float, w: float, seconds: float, rate: float) -> float:
	return clamp_height(height + (goal - height) * MaskBrush.amount(w, seconds, rate))


## One step of operation `op` at a sample of height `height` and weight `w`, for `seconds`
## of exposure. `goal` is the local mean for SMOOTH and the target height for FLATTEN and
## TIER (ignored by RAISE and LOWER).
static func apply(op: int, height: float, w: float, seconds: float, goal: float) -> float:
	match op:
		RAISE:
			return raise(height, w, seconds, 1.0)
		LOWER:
			return raise(height, w, seconds, -1.0)
		SMOOTH:
			return approach(height, goal, w, seconds, SMOOTH_RATE)
		FLATTEN:
			return approach(height, goal, w, seconds, FLATTEN_RATE)
		TIER, TIER_CUT:
			return approach(height, goal, w, seconds, TIER_RATE)
	return height


## The approach rate of an operation (0 for raise and lower, which do not approach).
static func rate(op: int) -> float:
	match op:
		SMOOTH:
			return SMOOTH_RATE
		FLATTEN:
			return FLATTEN_RATE
		TIER, TIER_CUT:
			return TIER_RATE
	return 0.0


## Half-width in samples of the smoothing window for a brush of `radius_m` on a grid of
## `step_m`: SMOOTH_KERNEL_FRACTION of the radius, at least one sample.
static func smooth_kernel(radius_m: float, step_m: float) -> int:
	if step_m <= 0.0:
		return 1
	return maxi(1, roundi(radius_m * SMOOTH_KERNEL_FRACTION / step_m))


## The mean of the (2k + 1)^2 window around every sample of `rect` (grid coordinates) of
## the row-major `heights` grid `width` x `depth`, the window clamped at the map edge (edge
## samples repeat). Returns rect.size.x * rect.size.y means, row by row. Separable running
## sums, so the cost does not grow with k.
static func box_mean(
	heights: PackedFloat32Array, width: int, depth: int, rect: Rect2i, k: int
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not rect.has_area():
		return out
	var rows_low := rect.position.y - k
	var rows_high := rect.end.y - 1 + k
	var band_rows := rows_high - rows_low + 1
	var columns := rect.size.x
	var inv := 1.0 / float(2 * k + 1)
	# Horizontal pass: for each needed row, the window mean around each column of rect.
	var horizontal := PackedFloat32Array()
	horizontal.resize(band_rows * columns)
	for r in band_rows:
		var z := clampi(rows_low + r, 0, depth - 1)
		var row := z * width
		var sum := 0.0
		for dx in range(-k, k + 1):
			sum += heights[row + clampi(rect.position.x + dx, 0, width - 1)]
		horizontal[r * columns] = sum * inv
		for c in range(1, columns):
			var x := rect.position.x + c
			sum += heights[row + clampi(x + k, 0, width - 1)]
			sum -= heights[row + clampi(x - k - 1, 0, width - 1)]
			horizontal[r * columns + c] = sum * inv
	# Vertical pass over the horizontal means.
	out.resize(rect.size.y * columns)
	for c in columns:
		var sum := 0.0
		for r in range(0, 2 * k + 1):
			sum += horizontal[r * columns + c]
		out[c] = sum * inv
		for z in range(1, rect.size.y):
			sum += horizontal[(z + 2 * k) * columns + c]
			sum -= horizontal[(z - 1) * columns + c]
			out[z * columns + c] = sum * inv
	return out


## The height of tier `level` for tiers of `tier_m` (level 0 is the ground at 0).
static func tier_height(level: int, tier_m: float) -> float:
	return level * tier_m


## The tier a height stands on (rounded to the nearest), for tiers of `tier_m`.
static func tier_level(height: float, tier_m: float) -> int:
	if tier_m <= 0.0:
		return 0
	return roundi(height / tier_m)
