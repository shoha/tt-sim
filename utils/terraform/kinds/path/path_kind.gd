extends RefCounted
## The path (built-in kind 6): [width, x0, z0, ...], a line of the paths stage. It is benched into
## the carved ground, graded to a walkable slope, with stairs where a bench would cut or fill too
## far and a ford where it meets water. Kernel: native/src/kinds/terra_kind_path.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "path"
const ID := 6
const STAGE := "paths"
const SHAPE := "line"
const HEADER := 1
const STRIDE := 2
const MIN_ITEMS := 2
const LABEL := "Path"
const DEFAULTS := {"width": 1.6}


## True when `data` is a path of at least two points with a positive width.
static func validate(data: PackedFloat32Array) -> bool:
	return Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) and Layout.positive(data, [0])


## The world box a path changes: its points grown by the half width and the bench's reach.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.line_bounds(data, HEADER, data[0] * 0.5 + Layout.PATH_REACH_M)


static func describe() -> String:
	return "A walkable way benched into the slope, with steps where it climbs."
