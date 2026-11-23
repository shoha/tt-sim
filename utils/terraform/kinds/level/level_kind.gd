extends RefCounted
## The level brush (kind 17): Flatten and Tier. Dabs [ax, az, bx, bz, radius, target_y, strength,
## edge], each one held frame's capsule from a to b (a press: a == b), as HeightStroke.dab sweeps
## it. Like the terrace it reads the height composed so far, so a level drawn after a hill levels
## it. Edge 0 flattens: each dab moves the height toward target_y by 1 - exp(-4 w strength) of the
## remaining way (HeightBrush FLATTEN; strength is seconds of exposure, w the (1 - t^2)^2 falloff of
## the distance to the segment). Edge 1 (Tier) and 2 (Tier cut): a run of tier dabs at one target
## is one tier stroke, completed: each sample takes HeightBrush.tier_goal of its height before the
## run, the target and its deepest inset (from TIER_SOFTEN_M outside the ring), Tier raising only
## lower ground, Tier cut cutting only higher; strength is ignored. Kernel:
## native/src/kinds/terra_kind_level.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "level"
const ID := 17
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 0
const STRIDE := 8
const MIN_ITEMS := 1
const LABEL := "Flatten"
const DEFAULTS := {"radius": 2.5, "edge": 0}
## The edges: flatten, tier up, tier cut.
const FLATTEN := 0
const TIER := 1
const TIER_CUT := 2


## True when `data` holds at least one dab, each with a positive radius, a strength of 0 or more
## and an edge of 0..2.
static func validate(data: PackedFloat32Array) -> bool:
	if not (
		Layout.fits(data, HEADER, STRIDE, MIN_ITEMS)
		and Layout.item_positive(data, HEADER, STRIDE, 4)
		and Layout.item_enum(data, HEADER, STRIDE, 7, TIER_CUT)
	):
		return false
	for i in Layout.items(data, HEADER, STRIDE):
		if data[i * STRIDE + 6] < 0.0:
			return false
	return true


## The world box a level changes: its capsules, a tier dab's grown by the soft toe.
static func bounds(data: PackedFloat32Array) -> Rect2:
	var lo := Vector2(1e30, 1e30)
	var hi := Vector2(-1e30, -1e30)
	var k := 0
	while k + STRIDE <= data.size():
		var r := data[k + 4] + (HeightBrush.TIER_SOFTEN_M if data[k + 7] != 0.0 else 0.0)
		lo = lo.min(Vector2(minf(data[k], data[k + 2]) - r, minf(data[k + 1], data[k + 3]) - r))
		hi = hi.max(Vector2(maxf(data[k], data[k + 2]) + r, maxf(data[k + 1], data[k + 3]) + r))
		k += STRIDE
	return Rect2(lo, hi - lo)


## The flatten dab of one held frame: HeightStroke.dab's capsule from `from` to `to` (world XZ) of
## `radius`, `seconds` of exposure, toward `target`.
static func flatten_dab(
	from: Vector2, to: Vector2, radius: float, seconds: float, target: float
) -> PackedFloat32Array:
	return PackedFloat32Array([from.x, from.y, to.x, to.y, radius, target, seconds, FLATTEN])


## The tier dab of one held frame toward `target` (a whole tier, HeightBrush.tier_height), `cut`
## for Tier cut.
static func tier_dab(
	from: Vector2, to: Vector2, radius: float, target: float, cut: bool
) -> PackedFloat32Array:
	return PackedFloat32Array(
		[from.x, from.y, to.x, to.y, radius, target, 0.0, TIER_CUT if cut else TIER]
	)


static func describe() -> String:
	return "Flatten the ground toward a height, or build a tier with a rocky riser."
