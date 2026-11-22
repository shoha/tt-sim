extends RefCounted
## The ridge (built-in kind 2): [height, width, profile, x0, z0, x1, z1, ...], a rise along a
## polyline (a valley below zero), added to the composed height as height * (1 - d^2 / w^2)^profile
## within the width of the nearest segment. Kernel: native/src/kinds/terra_kind_ridge.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "ridge"
const ID := 2
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 3
const STRIDE := 2
const MIN_ITEMS := 2
const LABEL := "Ridge or valley"
const DEFAULTS := {"height": 2.0, "width": 6.0, "profile": 1.5}


## True when `data` is a ridge of at least two points with a positive width.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) and Layout.positive(data, [1])


## The world box a ridge changes: its points grown by the width.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.line_bounds(data, HEADER, data[1])


static func describe() -> String:
	return "A rise along a line, or below zero a valley: a range of hills or a river's vale."
