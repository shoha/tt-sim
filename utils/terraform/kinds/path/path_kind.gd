extends RefCounted
## The path (built-in kind 6): [width, surface, x0, z0, ...], a line of the paths stage. It is
## benched into the carved ground, graded to a walkable slope, with stairs where a bench would cut
## or fill too far and a ford where it meets water. Its surface (an index of TerraDoc.surfaces, or
## NO_SURFACE) is a paint coat at the path's place in document order (card terraform-p2-paint-path).
## Kernel: native/src/kinds/terra_kind_path.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "path"
const ID := 6
const STAGE := "paths"
const SHAPE := "line"
const HEADER := 2
const STRIDE := 2
const MIN_ITEMS := 2
const LABEL := "Path"
const DEFAULTS := {"width": 1.6, "surface": 255}
## The surface value of a path that paints nothing.
const NO_SURFACE := 255


## True when `data` is a path of at least two points with a positive width and a surface of
## 0..255 (an integer).
static func validate(data: PackedFloat32Array) -> bool:
	if not (Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) and Layout.positive(data, [0])):
		return false
	var surface := data[1]
	return surface >= 0.0 and surface <= NO_SURFACE and surface == floorf(surface)


## The floats of a path of `width` and surface index `surface` along `points` (map XZ).
static func make(width: float, surface: int, points: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([width, float(surface)])
	for p in points:
		out.append_array([p.x, p.y])
	return out


## The world box a path changes: its points grown by the half width and the bench's reach.
static func bounds(data: PackedFloat32Array) -> Rect2:
	return Layout.line_bounds(data, HEADER, data[0] * 0.5 + Layout.PATH_REACH_M)


static func describe() -> String:
	return "A walkable way benched into the slope, with steps where it climbs."
