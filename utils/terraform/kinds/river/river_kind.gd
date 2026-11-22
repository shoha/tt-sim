extends RefCounted
## The river (built-in kind 4): [width, depth, x0, z0, ...], a body of the water stage. Its levels
## fall monotone downstream (falls where it drops sharply), it joins the body its end flows into,
## and the carve cuts its channel and banks. Water is one graph solve, so its code is
## native/src/terra_water.cpp, not a kind file.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "river"
const ID := 4
const STAGE := "water_solve"
const SHAPE := "water"
const HEADER := 2
const STRIDE := 2
const MIN_ITEMS := 2
const LABEL := "River"
const DEFAULTS := {"width": 2.5, "depth": 0.5}


## True when `data` is a river of at least two points with a positive width.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) and Layout.positive(data, [0])


## The world box a river changes: its points grown by the half width and the carve's reach.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.line_bounds(data, HEADER, data[0] * 0.5 + Layout.CARVE_REACH_M)


static func describe() -> String:
	return "Water that runs downhill along the line, cutting its own bed and falls."
