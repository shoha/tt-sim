class_name FirePlanJob
extends RefCounted

## The pure half of a FireField refresh (card F4b-4; docs/PERFORMANCE.md "Fire (F4)"): a brush
## dab's re-plan held the main thread 15 ms of its 20 (GDScript per lattice point), on the host
## and on every peer. compute() re-plans the touched blocks (FireField.plan_block), sums them on
## the clusters' grid (FireClusters.cells_of), re-splats the flames' rasters around them and
## encodes their texture's bytes, all from a snapshot of the document and copies of the field's
## plans and rasters, so it can run on a WorkerThreadPool task while the document is edited. The
## field lands the result on the main thread (FireField._land). The same function computes it on
## or off the worker, from the same inputs, so every peer and every reload plans the same flames.

## The document's parts the plan reads (snapshot_of).
var doc: MapDocument = null
## The blocks to re-plan.
var touched: Array[Vector2i] = []
## In: the field's whole plans (block -> PackedFloat32Array). Out: the same with the touched
## blocks re-planned (a block that no longer burns erased).
var plans := {}
## Out: the touched blocks' new plans (empty: no longer burning) and their cluster sums.
var planned := {}
var cells := {}
## In: the field's rasters (copies) and their size; out: re-splatted (a new size: whole), and
## the texture's bytes (FireLook.heat_bytes).
var heat := PackedFloat32Array()
var pools := PackedFloat32Array()
var heat_size := Vector2i.ZERO
var heat_bytes := PackedByteArray()
## The WorkerThreadPool task (-1: none, or computed on the caller's thread).
var task := -1


## A job for `field_doc`'s blocks `blocks`, from the field's `field_plans` and its rasters
## `field_heat`, `field_pools` of `size` texels; everything copied, so it is safe to hand to a
## worker while the document and the field change.
static func make(
	field_doc: MapDocument,
	blocks: Array[Vector2i],
	field_plans: Dictionary,
	field_heat: PackedFloat32Array,
	field_pools: PackedFloat32Array,
	size: Vector2i
) -> FirePlanJob:
	var job := FirePlanJob.new()
	job.doc = snapshot_of(field_doc)
	job.touched = blocks.duplicate()
	job.plans = field_plans.duplicate()
	job.heat = field_heat.duplicate()
	job.pools = field_pools.duplicate()
	job.heat_size = size
	return job


## A copy of what the plan reads of `source` (the grid, seed, heights, fire mask and wet
## dressing), safe to hand to a worker while `source` is edited.
static func snapshot_of(source: MapDocument) -> MapDocument:
	var copy := MapDocument.new()
	copy.size_cells = source.size_cells
	copy.cell_size_m = source.cell_size_m
	copy.sample_spacing_m = source.sample_spacing_m
	copy.map_seed = source.map_seed
	copy.heights = source.heights.duplicate()
	copy.fire_mask = source.fire_mask.duplicate()
	copy.water_dressing = source.water_dressing.duplicate()
	return copy


## Re-plans the touched blocks and re-splats the rasters (see the header). Reads and writes this
## job's own data only.
func compute() -> void:
	for block in touched:
		var plan := FireField.plan_block(doc, block)
		planned[block] = plan
		if plan.is_empty():
			plans.erase(block)
		else:
			plans[block] = plan
			cells[block] = FireClusters.cells_of(plan)
	var rasters := FireField.resplat(doc, plans, touched, heat, pools, heat_size)
	heat = rasters["heat"]
	pools = rasters["pools"]
	heat_size = rasters["size"]
	heat_bytes = FireLook.heat_bytes(heat, heat_size, FireField.HEAT_FULL_M, pools)
