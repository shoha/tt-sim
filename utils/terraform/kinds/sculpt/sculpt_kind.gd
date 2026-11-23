extends RefCounted
## The consolidated sculpt raster (kind 9, the id phase 1 reserved for it): old sculpt strokes
## folded into data by TerraDerive.consolidate. A header [x0, z0, sx, sz, nx, nz, layers], the world
## position of its first derive sample, the grid's steps, its size in samples (at most a 64-sample
## tile) and 1 or 2 layers; then nx * nz height deltas, row-major, and with 2 layers as many
## smoothing-weight deltas. Compose adds them where the folded run stood in document order, so
## the ground derives as the run did; peers receive the rasters and never recompute them. A
## raster made on another grid is ignored. No tool draws one. Kernel:
## native/src/kinds/terra_kind_sculpt.cpp.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

const NAME := "sculpt"
const ID := 9
const STAGE := "compose"
const SHAPE := "stamp"
const HEADER := 7
const STRIDE := 1
const MIN_ITEMS := 1
const LABEL := "Folded sculpt"
const DEFAULTS := {}
## The largest raster edge: one derive tile.
const MAX_EDGE := 64


## True when the header's positive steps, whole sizes of 1..MAX_EDGE and 1 or 2 layers describe
## exactly the floats after it.
static func validate(data: PackedFloat32Array) -> bool:
	if not Layout.fits(data, HEADER, STRIDE, MIN_ITEMS) or not Layout.positive(data, [2, 3]):
		return false
	for k in [4, 5, 6]:
		if data[k] != floorf(data[k]) or data[k] < 1.0:
			return false
	if data[4] > MAX_EDGE or data[5] > MAX_EDGE or data[6] > 2.0:
		return false
	return data.size() == HEADER + int(data[4]) * int(data[5]) * int(data[6])


## The world box of the raster's samples.
static func bounds(data: PackedFloat32Array) -> Rect2:
	if not validate(data):
		var at := Vector2(data[0], data[1]) if data.size() >= 2 else Vector2.ZERO
		return Rect2(at, Vector2.ZERO)
	var size := Vector2(data[2] * (data[4] - 1.0), data[3] * (data[5] - 1.0))
	return Rect2(Vector2(data[0], data[1]), size)


static func describe() -> String:
	return "Old sculpt strokes, folded into the ground they made."
