class_name HeightBrush
extends RefCounted

## The pure rules behind authoring's sculpt operations on MapDocument.heights: how far one
## exposure raises or lowers a sample, how smoothing and flattening pull it toward a goal,
## and the steep profile a tier step uses. HeightStroke applies them over a brush capsule;
## the P3-5 Sculpt tool picks the operation and its target. Every function is pure.
##
## Weights. A sample's weight is MaskBrush.falloff(distance / radius), (1 - t^2)^2, the same
## soft profile the mask brushes use, so a raised hill has no crease at its rim. The tier
## operation uses tier_weight() instead: flat at full weight over the core of the brush and
## falling to zero over a short rim, which is what makes its edge a steep face rather than
## a mound. P3-5 finalises the cliff profile (rounded lip, foot left for the scree rule).
##
## Exposure. Like the mask brushes, a dab carries `seconds` of exposure (the frame's time
## times flow times BrushTool's dwell gain). Raise and lower are linear in it
## (RAISE_M_PER_S metres per second at full weight), so a held brush keeps building. Smooth,
## flatten and tier approach their goal by MaskBrush.amount() = 1 - exp(-rate * weight *
## seconds) of the remaining way: frame-rate independent, and they never overshoot.
##
## Limits. Every result is clamped to +-MapDocument.MAX_ABS_HEIGHT_M, the range the
## document reader accepts, so a sculpted map always saves and loads.

const RAISE := 0
const LOWER := 1
const SMOOTH := 2
const FLATTEN := 3
const TIER := 4

## Metres per second of exposure at full weight for raise and lower. A 6 m hill is about four
## seconds of dwell at the centre (P3-5 tunes this with the dwell gain).
const RAISE_M_PER_S := 1.5
## Approach rates (per second at full weight) of smooth, flatten and tier.
const SMOOTH_RATE := 4.0
const FLATTEN_RATE := 4.0
const TIER_RATE := 10.0
## Smoothing averages over a square window whose half-width is this fraction of the brush
## radius (at least one sample): a big brush smooths broad shapes, a small one detail.
const SMOOTH_KERNEL_FRACTION := 0.15
## Fraction of the radius the tier profile holds at full weight; it falls to zero over the
## rest (see tier_weight).
const TIER_CORE := 0.75


## Weight of a sample at `t` = distance / radius for operation `op`.
static func weight(op: int, t: float) -> float:
	if op == TIER:
		return tier_weight(t)
	return MaskBrush.falloff(t)


## The tier profile: 1 out to TIER_CORE of the radius, then a smoothstep down to 0 at the
## rim. Steep but C1, so the face has no kink at its foot or lip.
static func tier_weight(t: float) -> float:
	if t >= 1.0:
		return 0.0
	if t <= TIER_CORE:
		return 1.0
	return 1.0 - smoothstep(TIER_CORE, 1.0, t)


## `height` clamped to the document's accepted range.
static func clamp_height(height: float) -> float:
	return clampf(height, -MapDocument.MAX_ABS_HEIGHT_M, MapDocument.MAX_ABS_HEIGHT_M)


## Raise (`direction` 1) or lower (-1) by RAISE_M_PER_S x `w` x `seconds`.
static func raise(height: float, w: float, seconds: float, direction: float = 1.0) -> float:
	return clamp_height(height + direction * RAISE_M_PER_S * w * seconds)


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
		TIER:
			return approach(height, goal, w, seconds, TIER_RATE)
	return height


## The approach rate of an operation (0 for raise and lower, which do not approach).
static func rate(op: int) -> float:
	match op:
		SMOOTH:
			return SMOOTH_RATE
		FLATTEN:
			return FLATTEN_RATE
		TIER:
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
