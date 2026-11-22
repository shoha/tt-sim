extends RefCounted
## The hill (built-in kind 1): [cx, cz, height, radius, profile], a round rise added to the composed
## height, height * (1 - d^2 / r^2)^profile inside the radius (a negative height is a hollow).
## Kernel: native/src/kinds/terra_kind_hill.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "hill"
const ID := 1
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 5
const STRIDE := 0
const MIN_ITEMS := 0
const LABEL := "Hill"
const DEFAULTS := {"height": 3.0, "radius": 8.0, "profile": 2.0}


## True when `data` is a hill with a positive radius.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) and Layout.positive(data, [3])


## The world box a hill changes: its disc.
static func bounds(data: PackedFloat32Array) -> Rect2:
	var r := data[3]
	return Rect2(data[0] - r, data[1] - r, 2.0 * r, 2.0 * r)


static func describe() -> String:
	return "A round rise (or, below zero, a hollow) with a soft shoulder."
