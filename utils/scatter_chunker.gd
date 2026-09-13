class_name ScatterChunker
extends RefCounted

## Splits a scatter species' instance transforms into a uniform world-space grid so each
## cell can become its own MultiMeshInstance3D. Pure statics only -- no node access and no
## side effects -- so the whole of the cell arithmetic is unit-testable without a renderer.
##
## Why this exists: a MultiMeshInstance3D is frustum-culled as a SINGLE AABB, and scattered
## foliage was built as one MultiMesh per species spanning the entire map, so every instance
## was vertex-processed whenever any part of that species was on screen. Measured on the
## Sandy Clearing map, the scatter footprint is 50 x 50 world units, every one of its 57
## species covers 45-65% of it, and at ordinary play zoom the camera sees single-digit
## percentages of the map while the renderer processes all 52,154 instances. Chunking is what
## lets frustum culling discard the rest. See docs/PERFORMANCE.md.

## Edge length in world units of one chunk cell, on both X and Z.
##
## Chosen by sweeping unchunked / 25 / 15 / 10 / 8 / 5 against the real 50 x 50 reference
## map, replaying the actual pipeline (FoliageBudget.plan, select_indices, bucket_by_cell)
## and counting, per camera zoom, which chunk AABBs intersect the view. Unchunked is 57
## nodes and 7,957,006 primitives at EVERY zoom, since one AABB per species is always drawn.
##
##   chunk | nodes | zoom 10 (typical play) | zoom 20 (fully zoomed out)
##      25 |   199 |  174 draws / 7,610,722 |  176 draws / 7,843,338
##      15 |   656 |   14 draws / 1,151,794 |  284 draws / 6,222,732
##      10 |  1335 |   17 draws /   431,868 |  731 draws / 5,932,752
##       5 |  2747 |    4 draws /   147,376 | 1193 draws / 5,310,072
##
## 25 is dominated: barely better than unchunked while tripling node count. 5 adds 1,136
## draw calls over baseline at full zoom-out to save 33% of primitives, which is the trade
## most likely to cost more than it buys. Between 15 and 10, 10 saves 62% more primitives at
## typical play zoom for three more draw calls, and that is where players spend their time;
## 15 is the better of the two only at full zoom-out, where both are large and the primitive
## budget rather than chunking is the binding constraint.
##
## NOT VALIDATED AGAINST FRAME TIME. The validator bridge cannot activate the title screen's
## buttons, so no rendered before/after was captured. The figures above are geometric --
## exact about what culling can discard, silent about what it costs. The open risk is the
## 731 draw calls at full zoom-out. See docs/PERFORMANCE.md for the measurement procedure.
const CHUNK_SIZE_WORLD_UNITS: float = 10.0


## The grid cell a world position falls in, on X and Z only.
##
## Y is ignored deliberately: the scatter footprint measures 2.05 units tall against 50 on
## each horizontal axis, so a third axis would multiply node count without adding culling.
##
## Uses floori(), NOT int(). int() truncates toward zero -- int(-0.5) is 0 while
## floori(-0.5) is -1 -- and half the reference map has negative coordinates, so truncation
## would collapse everything between -chunk_size and +chunk_size into cell 0 on each axis,
## making the origin cell four times the size of every other and leaving a quarter of the map
## uncullable.
##
## A position exactly on a cell boundary belongs to the HIGHER cell, the one whose lower edge
## it sits on: at chunk_size 10, x = 10.0 gives cell 1, x = 0.0 gives cell 0, and x = -10.0
## gives cell -1.
static func cell_for(origin: Vector3, chunk_size: float) -> Vector2i:
	if chunk_size <= 0.0:
		return Vector2i.ZERO
	return Vector2i(floori(origin.x / chunk_size), floori(origin.z / chunk_size))


## Node-name suffix for a cell, e.g. "_c-1_2". Negative values appear because half the
## reference map has negative coordinates; a minus sign is legal in a Godot node name.
##
## Callers omit this suffix entirely when a species occupies exactly one cell, so an
## unchunked species keeps its original `<Species>_MultiMesh` name and the suffix reads as a
## signal that the species was split -- see ScatterGlbUtils.process_scatter_instances.
static func cell_suffix(cell: Vector2i) -> String:
	return "_c%d_%d" % [cell.x, cell.y]


## Groups transforms by grid cell. Returns Vector2i cell -> Array[Transform3D], holding only
## occupied cells, with every input transform appearing in exactly one bucket.
##
## A non-positive chunk_size would divide by zero, so it falls back to a single bucket at the
## origin cell -- which reproduces the pre-chunking one-MultiMesh-per-species behaviour and is
## safe rather than corrupt.
static func bucket_by_cell(
	transforms: Array[Transform3D], chunk_size: float = CHUNK_SIZE_WORLD_UNITS
) -> Dictionary:
	var buckets := {}
	for xform in transforms:
		var cell := cell_for(xform.origin, chunk_size)
		if not buckets.has(cell):
			var fresh: Array[Transform3D] = []
			buckets[cell] = fresh
		buckets[cell].append(xform)
	return buckets
