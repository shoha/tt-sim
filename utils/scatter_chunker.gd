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
## PROVISIONAL until the sweep in this sub-project replaces it with a measured value. 10.0 on
## the 50 x 50 reference map gives a 5 x 5 grid, so up to about 1,400 nodes across 57 species
## against 57 today, with visible draw calls at mid zoom estimated near today's 251. Smaller
## cells cull better but cost draw calls; larger cells cull poorly when zoomed in, which is
## where the waste is worst (0.3% of the map visible at maximum zoom in).
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
