extends RefCounted
## The pond (built-in kind 5): [depth, x0, z0, ...], an outline of at least three points, a body of
## the water stage. Its level is set from its rim and the carve cuts its basin. Water is one graph
## solve, so its code is native/src/terra_water.cpp, not a kind file.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "pond"
const ID := 5
const STAGE := "water_solve"
const SHAPE := "water"
const HEADER := 1
const STRIDE := 2
const MIN_ITEMS := 3
const LABEL := "Pond"
const DEFAULTS := {"depth": 0.6}


## True when `data` is a pond outline of at least three points.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS)


## The world box a pond changes: its outline grown by the basin's reach.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.line_bounds(data, HEADER, Layout.POND_REACH_M)


static func describe() -> String:
	return "Still water filling the outline up to its lowest rim."
