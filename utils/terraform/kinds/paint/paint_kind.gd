extends RefCounted
## The paint coat (built-in kind 8): dabs [cx, cz, radius, surface_id], a stamp of the paint stage.
## Per sample the newest strong coat wins; the ground rules read it as the painted surface. Kernel:
## native/src/kinds/terra_kind_paint.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "paint"
const ID := 8
const STAGE := "paint"
const SHAPE := "stamp"
const HEADER := 0
const STRIDE := 4
const MIN_ITEMS := 1
const LABEL := "Paint"
const DEFAULTS := {"radius": 2.0, "surface": 0}
## The largest surface id (a byte).
const MAX_SURFACE := 255


## True when `data` holds at least one dab, each with a positive radius and a surface of 0..255.
static func validate(data: PackedFloat32Array) -> bool:
	return (
		Layout.fits(data, HEADER, STRIDE, MIN_ITEMS)
		and Layout.item_positive(data, HEADER, STRIDE, 2)
		and Layout.item_enum(data, HEADER, STRIDE, 3, MAX_SURFACE)
	)


## The world box a coat changes: its dabs' discs.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.dab_bounds(data, STRIDE)


static func describe() -> String:
	return "Paint a ground surface by hand, over what the rules chose."
