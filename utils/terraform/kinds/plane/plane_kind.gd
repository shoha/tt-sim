extends RefCounted
## The plane (built-in kind 0): [base, slope_x, slope_z], a tilted plane under the whole map, added
## to the composed height. Its base is its height at the map centre. Kernel:
## native/src/kinds/terra_kind_plane.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "plane"
const ID := 0
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 3
const STRIDE := 0
const MIN_ITEMS := 0
const LABEL := "Ground plane"
const DEFAULTS := {"base": 0.0, "slope_x": 0.0, "slope_z": 0.0}


## True when `data` is a plane: three finite floats.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS)


## The world box a plane changes: an empty Rect2, the whole map.
static func bounds(_data: PackedFloat32Array) -> Rect2:
	return Rect2()


static func describe() -> String:
	return "A tilted plane under the whole map: the ground every other landform adds to."
