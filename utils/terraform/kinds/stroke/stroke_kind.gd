extends RefCounted
## The sculpt stroke (built-in kind 3): dabs [cx, cz, radius, strength, mode], mode 0 raise, 1
## lower, 2 smooth. Raise and lower add (1 - d^2 / r^2)^2 * strength (metres) to the composed
## height; smooth adds it (seconds of exposure) to the weight the smooth stage reads. A held stroke
## appends dabs, capsule_dabs() per frame. Kernel: native/src/kinds/terra_kind_stroke.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "stroke"
const ID := 3
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 0
const STRIDE := 5
const MIN_ITEMS := 1
const LABEL := "Sculpt"
const DEFAULTS := {"radius": 2.5, "strength": 0.12, "mode": 0}
## The largest mode (smooth).
const MAX_MODE := 2
## Raise, lower and smooth, the modes.
const RAISE := 0
const LOWER := 1
const SMOOTH := 2


## The dabs of one held frame, HeightStroke.dab's capsule from `from` to `to` (world XZ) of
## `radius` with `seconds` of exposure, as point dabs at most radius / 4 apart
## (Layout.capsule_points): raise and lower carry HeightBrush.raise_speed(radius) x seconds metres,
## smooth the seconds (the smooth stage approaches the local mean by 1 - exp(-4 x exposure), as
## HeightBrush SMOOTH), each times its share.
static func capsule_dabs(
	from: Vector2, to: Vector2, radius: float, seconds: float, mode: int
) -> PackedFloat32Array:
	var amount := seconds if mode == SMOOTH else HeightBrush.raise_speed(radius) * seconds
	var out := PackedFloat32Array()
	for p: Array in Layout.capsule_points(from, to, radius, radius * 0.25):
		var c: Vector2 = p[0]
		out.append_array(PackedFloat32Array([c.x, c.y, radius, amount * float(p[1]), mode]))
	return out


## True when `data` holds at least one dab, each with a positive radius and a mode of 0..2.
static func validate(data: PackedFloat32Array) -> bool:
	return (
		Layout.fits(data, HEADER, STRIDE, MIN_ITEMS)
		and Layout.item_positive(data, HEADER, STRIDE, 2)
		and Layout.item_enum(data, HEADER, STRIDE, 4, MAX_MODE)
	)


## The world box a stroke changes: its dabs' discs.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.dab_bounds(data, STRIDE)


static func describe() -> String:
	return "Raise, lower or smooth the ground under the brush."
