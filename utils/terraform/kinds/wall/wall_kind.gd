extends RefCounted
## The wall (built-in kind 7): [height, thickness, x0, z0, ...], a line of the pads stage. The
## ground under it is padded level along the line, and it opens where solved water crosses it.
## Kernel: native/src/kinds/terra_kind_wall.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "wall"
const ID := 7
const STAGE := "pads"
const SHAPE := "line"
const HEADER := 2
const STRIDE := 2
const MIN_ITEMS := 2
const LABEL := "Wall"
const DEFAULTS := {"height": 1.2, "thickness": 0.5}


## True when `data` is a wall of at least two points with a positive height and thickness.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) and Layout.positive(data, [0, 1])


## The world box a wall changes: its points grown by the thickness and the pad's reach.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.line_bounds(data, HEADER, data[1] + Layout.PAD_REACH_M)


static func describe() -> String:
	return "A wall on a levelled footing, open where water runs through."
