extends RefCounted
## The paint coat (built-in kind 8; card terraform-p2-paint-path): [surface, then per dab ax, az,
## bx, bz, radius, seconds], one Paint stroke as a stamp of the paint stage. `surface` indexes the
## document's surface table (TerraDoc.surfaces); ERASE_SURFACE is an erase coat. The rule is
## SurfaceStroke.dab's (four entries a sample, the newest wins, a fifth surface drops the weakest),
## so a coat's planes equal that stroke's bytes at the document samples. Kernel:
## native/src/kinds/terra_kind_paint.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "paint"
const ID := 8
const STAGE := "paint"
const SHAPE := "stamp"
const HEADER := 1
const STRIDE := 6
const MIN_ITEMS := 1
const LABEL := "Paint"
const DEFAULTS := {"radius": 2.0, "surface": 0}
## The header value of an erase coat.
const ERASE_SURFACE := 255
## The largest surface index a coat may name (TerraDoc.MAX_SURFACES - 1) or ERASE_SURFACE.
const MAX_SURFACE := 255


## True when `data` holds a surface (an integer of 0..255) and at least one dab, each with a
## positive radius and positive seconds.
static func validate(data: PackedFloat32Array) -> bool:
	if not Layout.fits(data, HEADER, STRIDE, MIN_ITEMS):
		return false
	var surface := data[0]
	if surface < 0.0 or surface > MAX_SURFACE or surface != floorf(surface):
		return false
	return (
		Layout.item_positive(data, HEADER, STRIDE, 4)
		and Layout.item_positive(data, HEADER, STRIDE, 5)
	)


## One frame's dab: the capsule `from`-`to` (map XZ) of `radius`, exposed `seconds`.
static func dab(from: Vector2, to: Vector2, radius: float, seconds: float) -> PackedFloat32Array:
	return PackedFloat32Array([from.x, from.y, to.x, to.y, radius, seconds])


## The world box a coat changes: its dabs' capsules.
static func bounds(data: PackedFloat32Array) -> Rect2:
	var out := Rect2()
	var first := true
	for k in range(HEADER, data.size() - STRIDE + 1, STRIDE):
		var r := data[k + 4]
		var low := Vector2(minf(data[k], data[k + 2]) - r, minf(data[k + 1], data[k + 3]) - r)
		var high := Vector2(maxf(data[k], data[k + 2]) + r, maxf(data[k + 1], data[k + 3]) + r)
		var box := Rect2(low, high - low)
		out = box if first else out.merge(box)
		first = false
	return out


static func describe() -> String:
	return "Paint a ground surface by hand, over what the rules chose."
