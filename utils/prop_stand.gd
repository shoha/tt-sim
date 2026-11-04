class_name PropStand
extends RefCounted

## `blocks: stand` for the bulky village props (docs/systems/villages.md 3f): the standing
## surface of a prop as a few upward-facing boxes, so a token dropped on a crate stack, a hay
## stack or a cart bed lands on its top (WaterSurface.landing_below, terrain layer) instead of
## inside it. Pure of the scene tree; AuthoredSettlements builds a StaticBody3D per cell from these.
##
## The boxes are measured from the prop variant's own mesh, not tabulated per prop, because a
## variant draw changes the shape (a crate stack is one to three crates tall, a hay stack a
## mound, a rick or bales). The upward faces of the variant are sampled on a lattice (CELL_M),
## each cell takes the LOWEST top found at its corners and centre (a token sinks a little into
## hay rather than float over a slope), heights are floored to QUANT_M, and runs of equal height
## merge into boxes. The result is in the variant's local frame (default size, scale 1, origin at
## the prop's centre on the ground); `shapes_of` places it with the same transform the mesh gets
## (SettlementBake.transform_of: tilt, yaw, scale), so the box sizes carry the placement scale (a
## physics shape cannot be scaled).

## The kinds of `blocks` (villages.md 3f). `solid` is designed, not built.
const NONE := "none"
const STAND := "stand"

## Props that carry a standing surface. The rest are walk-through (lamp post, signpost, laundry,
## the well: its roof and curb stay a drawing). A map of prop name to its own "cell" (lattice
## step), "quant" (height quantum) and "max" (boxes) where the defaults do not suit.
const STANDING := {
	"crate_stack": {},
	"haystack": {"quant": 0.12, "max": 72},
	"barrel": {},
	"woodpile": {},
	"hand_cart": {},
	"farm_wagon": {},
}

## Lattice step of the height field, metres at default size. A little over five cells across a
## barrel; a cell is lost where a yawed edge cuts it, so the box sits about a cell inside a crate.
const CELL_M := 0.12
## Heights are floored to a multiple of this.
const QUANT_M := 0.06
## A cell lower than this is left to the ground: a token walks over a plank.
const MIN_TOP_M := 0.25
## The most boxes a prop keeps (a prop's "max" overrides); a stepped mound is coarsened (the
## height quantum grows by COARSEN_GROWTH, COARSEN_STEPS times at most) until it fits. No small
## box is dropped: a hole in a mound would let a token fall to the ground inside it.
const MAX_BOXES := 24
const COARSEN_STEPS := 8
const COARSEN_GROWTH := 1.5
## A face counts as upward at |normal.y| above this (the highest face over a point is always
## one of a closed solid's upward faces, so the winding does not matter).
const UP_MIN := 0.5
## A box reaches this far below the prop's origin, into the ground, so no crack shows at its foot.
const FOOT_M := 0.1
## No surface found at a lattice point.
const NONE_Y := -1.0e9


## `blocks` of prop `prop`: STAND or NONE.
static func kind_of(prop: String) -> String:
	return STAND if STANDING.has(prop) else NONE


## The triangles of the built surfaces `surfaces` ({"arrays": [...]} as a prop variant holds
## them) as one flat list, three points a triangle.
static func triangles_of(surfaces: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for surface: Dictionary in surfaces:
		var arrays: Array = surface["arrays"]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		if index is PackedInt32Array and not (index as PackedInt32Array).is_empty():
			for i: int in index:
				out.append(verts[i])
		else:
			out.append_array(verts)
	return out


## The standing boxes of prop `prop` from its variant's triangles `tris` (triangles_of):
## [{"min": Vector2, "max": Vector2, "top": float}] in the variant's local frame (x, z extents;
## the top height above the origin). [] for a prop that does not stand, or no usable surface.
static func boxes_of(prop: String, tris: PackedVector3Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not STANDING.has(prop) or tris.size() < 3:
		return out
	var params: Dictionary = STANDING[prop]
	var field := height_field(tris, float(params.get("cell", CELL_M)))
	if field.is_empty():
		return out
	var quant := float(params.get("quant", QUANT_M))
	var limit := int(params.get("max", MAX_BOXES))
	for attempt in COARSEN_STEPS:
		out = merge(field, quant)
		if out.size() <= limit:
			return out
		quant *= COARSEN_GROWTH
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _area(a) > _area(b))
	out.resize(limit)
	return out


## The highest upward surface over each point of a lattice of step cell/2 laid over the triangles'
## plan extent: {"origin": Vector2, "nx", "nz": cells across, "cell": float, "lattice":
## PackedFloat32Array of (2nx+1) x (2nz+1) heights, NONE_Y where no surface}. {} for no triangles.
static func height_field(tris: PackedVector3Array, cell: float) -> Dictionary:
	if tris.size() < 3:
		return {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in tris:
		lo = lo.min(Vector2(v.x, v.z))
		hi = hi.max(Vector2(v.x, v.z))
	var nx := maxi(ceili((hi.x - lo.x) / cell), 1)
	var nz := maxi(ceili((hi.y - lo.y) / cell), 1)
	var cols := 2 * nx + 1
	var rows := 2 * nz + 1
	var step := cell * 0.5
	var lattice := PackedFloat32Array()
	lattice.resize(cols * rows)
	lattice.fill(NONE_Y)
	for t in tris.size() / 3:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var normal := (b - a).cross(c - a)
		var length := normal.length()
		if length < 1.0e-9 or absf(normal.y) / length < UP_MIN:
			continue
		_raster(lattice, cols, rows, lo, step, a, b, c)
	return {"origin": lo, "nx": nx, "nz": nz, "cell": cell, "lattice": lattice}


## Boxes from a height field: one height per cell (the lowest of its four corners and its
## centre, all but one of which must have a surface, floored to `quant`), runs of equal height
## along x merged across z. Order is by row then column, so the same prop gives the same boxes.
static func merge(field: Dictionary, quant: float) -> Array[Dictionary]:
	var nx: int = field["nx"]
	var nz: int = field["nz"]
	var cell: float = field["cell"]
	var origin: Vector2 = field["origin"]
	var cols := 2 * nx + 1
	var lattice: PackedFloat32Array = field["lattice"]
	var out: Array[Dictionary] = []
	var open := {}
	for j in nz:
		var next_open := {}
		var i := 0
		while i < nx:
			var h := _cell_top(lattice, cols, i, j, quant)
			if h < MIN_TOP_M:
				i += 1
				continue
			var k := i
			while k + 1 < nx and is_equal_approx(_cell_top(lattice, cols, k + 1, j, quant), h):
				k += 1
			var key := Vector3i(i, k, roundi(h * 1000.0))
			if open.has(key):
				var box: Dictionary = open[key]
				box["max"] = Vector2(box["max"].x, origin.y + (j + 1) * cell)
				next_open[key] = box
			else:
				var made := {
					"min": Vector2(origin.x + i * cell, origin.y + j * cell),
					"max": Vector2(origin.x + (k + 1) * cell, origin.y + (j + 1) * cell),
					"top": h,
				}
				out.append(made)
				next_open[key] = made
			i = k + 1
		open = next_open
	return out


## `boxes` (boxes_of) placed by `placement` (SettlementBake.transform_of: rotation and a uniform
## scale at the prop's origin): [{"transform": Transform3D, "size": Vector3}], one per box, a box
## shape's own transform and full size in the parent frame. The scale is folded into the size.
static func shapes_of(boxes: Array[Dictionary], placement: Transform3D) -> Array[Dictionary]:
	var scale := placement.basis.get_scale().x
	var turn := placement.basis.orthonormalized()
	var out: Array[Dictionary] = []
	for box: Dictionary in boxes:
		var low: Vector2 = box["min"]
		var high: Vector2 = box["max"]
		var top: float = box["top"]
		var local := Vector3((low.x + high.x) * 0.5, (top - FOOT_M) * 0.5, (low.y + high.y) * 0.5)
		(
			out
			. append(
				{
					"transform": Transform3D(turn, placement.origin + turn * (local * scale)),
					"size":
					Vector3(
						(high.x - low.x) * scale, (top + FOOT_M) * scale, (high.y - low.y) * scale
					),
				}
			)
		)
	return out


## The top of cell (i, j): the lowest of its corner and centre samples floored to `quant`, 0
## when the centre or more than one of the five has no surface.
static func _cell_top(
	lattice: PackedFloat32Array, cols: int, i: int, j: int, quant: float
) -> float:
	var low := INF
	var missing := 0
	for at: Vector2i in [
		Vector2i(2 * i, 2 * j),
		Vector2i(2 * i + 2, 2 * j),
		Vector2i(2 * i, 2 * j + 2),
		Vector2i(2 * i + 2, 2 * j + 2),
		Vector2i(2 * i + 1, 2 * j + 1)
	]:
		var y := lattice[at.y * cols + at.x]
		if y <= NONE_Y * 0.5:
			if at.x == 2 * i + 1:
				return 0.0
			missing += 1
		else:
			low = minf(low, y)
	if missing > 1 or low == INF:
		return 0.0
	return floorf(low / quant + 1.0e-4) * quant


static func _area(box: Dictionary) -> float:
	var size: Vector2 = box["max"] - box["min"]
	return size.x * size.y


## Writes the height of triangle (a, b, c) into every lattice point it covers (the larger height
## wins).
static func _raster(
	lattice: PackedFloat32Array,
	cols: int,
	rows: int,
	origin: Vector2,
	step: float,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> void:
	var low_x := minf(a.x, minf(b.x, c.x))
	var high_x := maxf(a.x, maxf(b.x, c.x))
	var low_z := minf(a.z, minf(b.z, c.z))
	var high_z := maxf(a.z, maxf(b.z, c.z))
	var i0 := maxi(ceili((low_x - origin.x) / step - 1.0e-4), 0)
	var i1 := mini(floori((high_x - origin.x) / step + 1.0e-4), cols - 1)
	var j0 := maxi(ceili((low_z - origin.y) / step - 1.0e-4), 0)
	var j1 := mini(floori((high_z - origin.y) / step + 1.0e-4), rows - 1)
	var area := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
	if absf(area) < 1.0e-12:
		return
	var eps := -1.0e-4
	for j in range(j0, j1 + 1):
		var z := origin.y + j * step
		for i in range(i0, i1 + 1):
			var x := origin.x + i * step
			var w0 := ((b.x - x) * (c.z - z) - (c.x - x) * (b.z - z)) / area
			var w1 := ((c.x - x) * (a.z - z) - (a.x - x) * (c.z - z)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < eps or w1 < eps or w2 < eps:
				continue
			var y := w0 * a.y + w1 * b.y + w2 * c.y
			var at := j * cols + i
			if y > lattice[at]:
				lattice[at] = y
