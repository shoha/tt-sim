extends RefCounted
## The sculpt stroke (built-in kind 3): dabs [cx, cz, radius, strength, mode], mode 0 raise, 1
## lower, 2 smooth. Raise and lower add (1 - d^2 / r^2)^2 * strength to the composed height;
## smooth adds it to the weight the smooth stage reads. A held stroke appends dabs. Kernel:
## native/src/kinds/terra_kind_stroke.cpp.

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
