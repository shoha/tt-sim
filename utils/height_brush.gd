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
## the cliff profile the user chose, a steep face at the ring's edge (TIER_FACE_DEG, steeper
## than TerrainRules' full-rock slope, so the automatic cliff rule turns it into the biome's
## rock), a rounded lip of TIER_LIP_M over TIER_LIP_WIDTH_M at its top (a convex shoulder the
## lip rule keeps grassy), then the flat top exactly at the target. The foot stays concave
## for the scree rule. A tier only ever raises (TIER) or only ever cuts (TIER_CUT), so
## strokes over an existing tier leave it and higher ground alone. The goal is geometry, not
## exposure: a held brush does not climb past the tier.
##
## Soft profile (P3-7). That sharp profile (face, lip, top: TIER_FACE_DEG's 0.37 m face is
## narrower than two samples) is averaged over a tent TIER_SOFTEN_M wide on either side before
## it is sampled, i.e. band-limited to what the 0.25 m grid and its fixed quad diagonal can
## draw. Sampled sharp, a face running at any angle but the two grid axes and the drawn
## diagonal broke into a sawtooth of teeth up to 0.25 m deep along its length (the triangles
## straddling the foot and the lip kinks tilt along the face), which read as stair-stepped
## rock and a zigzag grid tint on every curved or diagonal tier. The tent keeps the teeth under
## 0.075 m at every angle (test_diagonal_tier_faces_do_not_saw) for a face of
## 66 degrees at its steepest (63 read by the shading normals, still past full rock); an
## adaptive quad diagonal was measured too and only fixes the exact 45 degree faces. The
## profile is exact (closed form, second antiderivatives) and ends exactly on the target, so
## tops stay exact. HeightStroke measures the inset from TIER_SOFTEN_M outside the ring, so
## the face stands where the sharp one did (centred half a face inside the ring), its toe
## eases out up to TIER_SOFTEN_M past the ring, and the flat top starts TIER_SOFTEN_M further
## in than the sharp profile's.
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
## The sharp profile's face angle from horizontal. After the soft profile's tent the face is
## 66 degrees at its steepest, and the shading normals (central differences over two sample
## steps) read 63 at the 0.25 m spacing, past TerrainRules.CLIFF_END_DEG (full rock)
## (test_tier_face_is_rock_at_the_default_spacing).
const TIER_FACE_DEG := 74.0
## The sharp face is never narrower than this (metres), for small rises.
const TIER_MIN_FACE_M := 0.3
## The rounded lip: how far below the top the face ends, and over what width the shoulder
## rounds up to the top (an ease-out, flat at the top). At most TIER_LIP_SHARE of the rise.
## 0.5 m since the soft profile rounds the shoulder too (0.8 before it made the flat top of a
## small tier 0.3 m narrower for the same look).
const TIER_LIP_M := 0.25
const TIER_LIP_WIDTH_M := 0.5
const TIER_LIP_SHARE := 0.3
## Half-width (metres) of the tent the sharp profile is averaged over (see the header): two
## sample steps at the default spacing. Wider lowers the teeth further (0.6: 0.057 m) at the
## cost of the face's steepness (63 degrees) and 0.2 m of top.
const TIER_SOFTEN_M := 0.5
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


## How far from the profile's start (TIER_SOFTEN_M outside the ring, see HeightStroke) a
## tier of `rise` metres reaches its flat top: the sharp profile's face and lip plus the
## soft profile's tent on both sides.
static func tier_span(rise: float) -> float:
	var lip := minf(TIER_LIP_M, absf(rise) * TIER_LIP_SHARE)
	return tier_face_width(absf(rise) - lip) + TIER_LIP_WIDTH_M + 2.0 * TIER_SOFTEN_M


## The height a tier stroke gives a sample that stood at `start` when the stroke began, for
## a stroke toward `target`, the stroke having reached `inset` metres inside the profile's
## start (<= 0: not reached; HeightStroke starts it TIER_SOFTEN_M outside the ring). Raising
## (target above start): the face rises from the start to
## TIER_LIP_M below the target, the lip rounds up to the target, then the top is flat.
## Cutting (target below start): mirrored, so the rounded lip is the rim of the cut, on the
## ground the cut goes into: the rim rounds down, the face drops, then the floor is flat.
## Both are the soft profile (see the header). Returns exactly `start` at and outside the
## profile's start and exactly `target` from tier_span() in.
static func tier_goal(start: float, target: float, inset: float) -> float:
	if inset <= 0.0 or start == target:
		return start
	var rise := absf(target - start)
	var lip := minf(TIER_LIP_M, rise * TIER_LIP_SHARE)
	var face := tier_face_width(rise - lip)
	var span := face + TIER_LIP_WIDTH_M + 2.0 * TIER_SOFTEN_M
	if inset >= span:
		return target
	if target > start:
		return start + soft_tier_offset(inset - TIER_SOFTEN_M, rise, lip, face)
	return start - (rise - soft_tier_offset(span - TIER_SOFTEN_M - inset, rise, lip, face))


## The sharp raising profile (0 up to the foot at x = 0, a linear face of width `face` up
## to rise - lip, the lip's ease-out over `lip_width` (a tier's TIER_LIP_WIDTH_M; a
## waterfall's harder lip, WaterCarve.fall_profile, passes its own), then `rise`) averaged
## over the tent of half-width TIER_SOFTEN_M centred on `x`: the second difference of its
## second antiderivative (_tier_g2) over the tent's half-width. 0 left of -TIER_SOFTEN_M,
## exactly `rise` right of the sharp top plus TIER_SOFTEN_M, monotonic and C1 between.
static func soft_tier_offset(
	x: float, rise: float, lip: float, face: float, lip_width: float = TIER_LIP_WIDTH_M
) -> float:
	var b := TIER_SOFTEN_M
	if x + b <= 0.0:
		return 0.0
	if x - b >= face + lip_width:
		return rise
	var g := (
		_tier_g2(x + b, rise, lip, face, lip_width)
		- 2.0 * _tier_g2(x, rise, lip, face, lip_width)
		+ _tier_g2(x - b, rise, lip, face, lip_width)
	)
	return clampf(g / (b * b), 0.0, rise)


## Second antiderivative (from 0) of the sharp raising profile soft_tier_offset() describes,
## its lip easing out over `w`.
static func _tier_g2(x: float, rise: float, lip: float, face: float, w: float) -> float:
	if x <= 0.0:
		return 0.0
	var slope := (rise - lip) / face
	if x < face:
		return slope * x * x * x / 6.0
	var g1_face := slope * face * face * 0.5
	var g2_face := slope * face * face * face / 6.0
	if x < face + w:
		var d := x - face
		var q := 1.0 - d / w
		return (
			g2_face
			+ g1_face * d
			+ rise * d * d * 0.5
			- lip * w / 3.0 * (d - w * (1.0 - q * q * q * q) * 0.25)
		)
	var e := x - face - w
	var g1_top := g1_face + rise * w - lip * w / 3.0
	var g2_top := g2_face + g1_face * w + rise * w * w * 0.5 - lip * w * w * 0.25
	return g2_top + g1_top * e + rise * e * e * 0.5


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
