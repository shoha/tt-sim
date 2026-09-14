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
## Abridged below to the two zooms the decision turns on, to stay under this file's line
## length limit -- docs/PERFORMANCE.md's "Spatial foliage chunking" section has the
## complete sweep, all six chunk sizes across all four zooms swept (2, 5, 10 and 20).
##
##   chunk | nodes | zoom 10 (typical play) | zoom 20 (fully zoomed out)
##      25 |   199 |  174 draws / 7,610,722 |  176 draws / 7,843,338
##      15 |   656 |   14 draws / 1,151,794 |  284 draws / 6,222,732
##      10 |  1335 |   17 draws /   431,868 |  731 draws / 5,932,752
##       8 |  1885 |    3 draws /   586,032 |  831 draws / 6,143,696
##       5 |  2747 |    4 draws /   147,376 | 1193 draws / 5,310,072
##
## 25 is dominated: barely better than unchunked while tripling node count. Between 15 and
## 10, 10 saves 62% more primitives at typical play zoom for three more draw calls, and that
## is where players spend their time; 15 is better only at full zoom-out, where both are
## large and the primitive budget rather than chunking is the binding constraint.
##
## 5 was passed over on the grounds that it adds 1,136 draw calls over baseline at full
## zoom-out, which looked like the trade most likely to cost more than it bought. Chunk
## size 5 has since been rendered too (see below): that specific fear was wrong, the draw
## calls did not cost what was feared, but 10 is still confirmed as the right value --
## size 5's primitive saving simply does not convert into frame time.
##
## VALIDATED AGAINST FRAME TIME on a real render (Sandy Clearing, 1920x1080, vsync off,
## RTX 3080, via the validator bridge). Chunked at 10 beats unchunked (chunk size 0, one
## bucket per species) at both poses tried: Home 9.62 -> 8.41 ms (+12.6% FPS), full
## zoom-out 13.42 -> 11.12 ms (+17.1% FPS) -- the larger win at the pose with more draw
## calls. The feared draw-call cost did not materialise: full zoom-out goes 89 -> 1,145
## visible draw calls and is still faster, not slower. Shadow-pass primitives fall 33% at
## Home (6,591,594 -> 4,421,617) from chunking's frustum culling of chunk AABBs out of the
## shadow cascades -- a separate mechanism from `directional_shadow_max_distance`, which
## was re-tested against this chunked build and remains inert (byte-identical shadow
## primitives at 30 and 100 units; see docs/PERFORMANCE.md's "Known dead ends" section).
##
## Chunk 5 was also rendered against chunk 10, same Home pose, each with its own
## foliage-hidden reference: chunk 10's foliage cost is 2.80 ms against chunk 5's 2.77 ms,
## a ~1% difference within noise, even though chunk 5 cuts visible primitives 11% (its
## 77% more draw calls cancel the saving, exactly as chunk 10's own extra draw calls cost
## nothing above). Combined with chunk 5 costing more nodes (2,747 vs. 1,335) and more
## time at load (see below), 10 is confirmed as the right value on measured grounds. See
## docs/PERFORMANCE.md's "Spatial foliage chunking" section for the full rendered tables
## and the geometric sweep that chose this value. Chunk sizes 10 and 5 have been
## rendered; 25/15/8 remain geometric-only.
##
## One more risk the design named that the tree does not yet record a fix for: node count
## is now bounded by surviving instance count, not species count. Before this branch every
## map built exactly 57 nodes; the reference map now builds about 1,335, and a sparse
## enough large map is unbounded in principle. Maps are untrusted network input.
##
## Map load cost IS measured: timing `ScatterGlbUtils.process_scatter_instances` headless
## against the reference map, chunk 10 costs +13.6 ms of scatter processing over unchunked
## (101.7 ms vs. 88.1 ms, minimum of three reps each) -- about 0.5% of this map's ~2,474 ms
## GLB parse time. Negligible. See docs/PERFORMANCE.md's "Map load cost" section.
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
