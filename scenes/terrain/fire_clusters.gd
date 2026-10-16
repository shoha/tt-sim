class_name FireClusters
extends RefCounted

## Where the persistent fire's lights and smoke stand (FireField; design:
## docs/plans/2026-10-11-fire-features/design.md section 4, "Light" and "Smoke"). Pure and
## deterministic, so every peer agrees, and run only when blocks re-plan, never per frame.
##
## A cluster is a hot spot of the burn, found on a coarse grid of CELL_M cells: each cell sums
## the size of the flames standing in it, a flame's height squared (square metres, about its
## drawn area, so a blaze's big flames outweigh a wide field of small ones; sparks add
## nothing), from each block's plan (cells_of, kept per block by FireField, merge sums them in
## block order). A cell's score is its sum and its eight neighbours'; a cluster is a burning
## cell whose score tops every burning neighbour's (ties to the earlier cell in row order). Its
## size is that score, its place the flames' size-weighted centroid over the nine cells, its
## top the tallest flame there. A small separate fire is one cluster; a burn wider than the
## 3 x 3 cells has one per hot spot, at least two cells apart, so a map-wide fire spreads its
## lights over its hottest
## parts (connected components would make it one cluster with one light at its middle,
## perhaps over a gap). The blaze (flames at BLAZE_MIN and up) keeps sums of its own, so smoke
## rises over blaze clusters only.
##
## Locality: a cluster reads the cells within two of its own, so re-planning one block changes
## only the clusters within two cells of its flames; every other keeps its exact values (each
## cell sums its blocks in row order whatever order they were planned in, and each score sums
## its nine cells in a fixed order).

## The grid's cell (metres): clusters stand at least two cells apart, about a light's range.
const CELL_M := 3.5
## Sums per cell: the flames' size (heights squared, summed), the size-weighted x, y and z, the
## tallest; then the same five for the blaze alone, from BLAZE.
const FIELDS := 10
const SIZE := 0
const TOP := 4
const BLAZE := 5
## The lights stand over at most this many clusters, the smoke over at most this many blaze
## clusters of at least SMOKE_MIN_SIZE (square metres: a blaze's big flame and its licks).
const MAX_LIGHTS := 4
const MAX_SMOKE := 8
const SMOKE_MIN_SIZE := 8.0


## The sums of `plan`'s flames (FireField's STRIDE layout) per grid cell: Vector2i ->
## PackedFloat64Array of FIELDS (see the header). Pure.
static func cells_of(plan: PackedFloat32Array) -> Dictionary:
	var cells := {}
	# A flame of the blaze band: its plan's intensity (0..1) is the mask byte over 255.
	var blaze_from := (FireField.BLAZE_MIN - 0.01) / 255.0
	@warning_ignore("integer_division")
	for k in plan.size() / FireField.STRIDE:
		var o := k * FireField.STRIDE
		if plan[o + FireField.KIND] != FireField.FLAME:
			continue
		var at := Vector3(plan[o], plan[o + 1], plan[o + 2])
		var cell := Vector2i(floori(at.x / CELL_M), floori(at.z / CELL_M))
		var sums: PackedFloat64Array = cells.get(cell, PackedFloat64Array())
		if sums.is_empty():
			sums.resize(FIELDS)
		var height := plan[o + FireField.HEIGHT]
		_add(sums, SIZE, at, height)
		if plan[o + FireField.INTENSITY] >= blaze_from:
			_add(sums, BLAZE, at, height)
		cells[cell] = sums
	return cells


## The cells of every block in `per_block` (block -> cells_of) summed into one map, the blocks
## taken in row order. Pure.
static func merge(per_block: Dictionary) -> Dictionary:
	var blocks: Array = per_block.keys()
	blocks.sort_custom(_row_order)
	var cells := {}
	for block in blocks:
		var part: Dictionary = per_block[block]
		for cell in part:
			var add: PackedFloat64Array = part[cell]
			if not cells.has(cell):
				cells[cell] = add.duplicate()
				continue
			var sums: PackedFloat64Array = cells[cell]
			for f in FIELDS:
				var top := f == TOP or f == BLAZE + TOP
				sums[f] = maxf(sums[f], add[f]) if top else sums[f] + add[f]
			cells[cell] = sums
	return cells


## The clusters of `cells` (merge's map), the blaze's alone when `blaze`, largest first (ties in
## the row order of their cells): each {"cell": Vector2i, "size": square metres of flame, "at":
## Vector3 the centroid in document metres, "top": the tallest flame}. Pure.
static func find(cells: Dictionary, blaze: bool) -> Array[Dictionary]:
	var o := BLAZE if blaze else 0
	var scores := {}
	for cell: Vector2i in cells:
		if (cells[cell] as PackedFloat64Array)[o + SIZE] > 0.0:
			scores[cell] = _score(cells, cell, o)
	var out: Array[Dictionary] = []
	for cell: Vector2i in scores:
		if _tops(scores, cell):
			out.append(_cluster(cells, cell, o))
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["size"] != b["size"]:
				return a["size"] > b["size"]
			return _row_order(a["cell"], b["cell"])
	)
	return out


## The clusters the lights stand over: the MAX_LIGHTS largest burning ones. Pure.
static func lights(cells: Dictionary) -> Array[Dictionary]:
	return find(cells, false).slice(0, MAX_LIGHTS)


## The clusters the smoke rises over: the MAX_SMOKE largest blaze ones of at least
## SMOKE_MIN_SIZE. Pure.
static func smoke(cells: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cluster in find(cells, true):
		if out.size() >= MAX_SMOKE or float(cluster["size"]) < SMOKE_MIN_SIZE:
			break
		out.append(cluster)
	return out


## Which of `wanted` (clusters' cells, in rank order) each slot shows, for slots that showed
## `previous` (a cell each, NONE for an empty slot): -1 for none. A cluster already shown keeps
## its slot, so a re-plan moves only the lights whose clusters changed; the rest take the free
## slots in order. Pure.
static func keep_slots(previous: Array[Vector2i], wanted: Array[Vector2i]) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(previous.size())
	out.fill(-1)
	var kept := {}
	for slot in previous.size():
		var k := wanted.find(previous[slot])
		if k >= 0:
			out[slot] = k
			kept[k] = true
	var free := 0
	for k in wanted.size():
		if kept.has(k):
			continue
		while free < out.size() and out[free] >= 0:
			free += 1
		if free >= out.size():
			break
		out[free] = k
	return out


static func _add(sums: PackedFloat64Array, o: int, at: Vector3, height: float) -> void:
	var size := height * height
	sums[o + SIZE] += size
	sums[o + 1] += at.x * size
	sums[o + 2] += at.y * size
	sums[o + 3] += at.z * size
	sums[o + TOP] = maxf(sums[o + TOP], height)


## The size of `cell` and its eight neighbours, summed in a fixed order.
static func _score(cells: Dictionary, cell: Vector2i, o: int) -> float:
	var total := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var sums: PackedFloat64Array = cells.get(cell + Vector2i(dx, dz), PackedFloat64Array())
			if not sums.is_empty():
				total += sums[o + SIZE]
	return total


## Whether `cell`'s score tops every burning neighbour's (ties to the earlier in row order).
static func _tops(scores: Dictionary, cell: Vector2i) -> bool:
	var own: float = scores[cell]
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var other := cell + Vector2i(dx, dz)
			if other == cell or not scores.has(other):
				continue
			var score: float = scores[other]
			if score > own or (score == own and _row_order(other, cell)):
				return false
	return true


static func _cluster(cells: Dictionary, cell: Vector2i, o: int) -> Dictionary:
	var size := 0.0
	var at := Vector3.ZERO
	var top := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var sums: PackedFloat64Array = cells.get(cell + Vector2i(dx, dz), PackedFloat64Array())
			if sums.is_empty():
				continue
			size += sums[o + SIZE]
			at += Vector3(sums[o + 1], sums[o + 2], sums[o + 3])
			top = maxf(top, sums[o + TOP])
	return {"cell": cell, "size": size, "at": at / maxf(size, 1e-6), "top": top}


static func _row_order(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
