class_name RockKeeper
extends RefCounted

## AuthoringEditor's side of "rocks survive terrain changes" (rules in RockKeep): at a sculpt
## stroke's end, start() works out on a worker thread which drawn rocks the stroke's
## regeneration would remove; finish() then moves them from the scatter into the props (both
## unanimated, so nothing visibly changes) and fills the stroke's history record, and the
## editor requests the regeneration only after that, so no rock shrinks in the meantime.
## swap() is undo and redo's half. One per editor; it holds the map's nodes, never the editor.

var document: MapDocument = null
var scatter: AuthoredScatter = null
var props: AuthoredScatter = null
var palette_root: String = PaletteLibrary.DEFAULT_ROOT
## The last applied job, for measurement: main-thread and worker microseconds, rocks kept.
var last_usec: int = 0
var last_worker_usec: int = 0
var last_kept: int = 0

## The running job: {"id", "result", "cells", "changed", "record"}, or {}.
var _job: Dictionary = {}


static func create(
	doc: MapDocument, scatter_node: AuthoredScatter, props_node: AuthoredScatter, root: String
) -> RockKeeper:
	var keeper := RockKeeper.new()
	keeper.document = doc
	keeper.scatter = scatter_node
	keeper.props = props_node
	keeper.palette_root = root
	return keeper


func is_running() -> bool:
	return not _job.is_empty()


## Starts the job for a stroke that changed sample rectangle `changed` from heights `before`,
## whose regeneration covers map rectangle `area` (before request_region's per-species
## growth); `rocks` is RockKeep.rock_assets, `record` the stroke's history record ({
## "props_before", "props_after", "kept"}), filled by finish(). `dressing_before` is the wet
## dressing that went with `before` (a water carve changes it; null: the document's).
## `keep` (optional, Callable(asset id, row) -> bool) drops rocks the stroke would keep: a
## water carve lets the ones under the water or blocking its channel go (WaterCarve
## .keeps_rock). False (nothing started) when no rock is drawn there.
func start(
	before: PackedFloat32Array,
	changed: Rect2i,
	area: Rect2,
	record: Dictionary,
	rocks: Dictionary,
	dressing_before: Variant = null,
	keep: Callable = Callable()
) -> bool:
	var cells := _cells(area, rocks)
	if cells.is_empty():
		return false
	var species_by_biome := {}
	for biome_id in document.biome_ids:
		species_by_biome[biome_id] = PaletteLibrary.species(biome_id, palette_root)
	var was := RockKeep.snapshot(document, before, dressing_before)
	var now := RockKeep.snapshot(document, document.heights)
	var built := PackedStringArray(PaletteLibrary.surfaces_with_role("built", palette_root))
	var cliff := PackedStringArray(PaletteLibrary.surfaces_with_role("cliff", palette_root))
	var result := {}
	var task := func() -> void:
		var started := Time.get_ticks_usec()
		var removed := RockKeep.removed_keys(was, now, species_by_biome, cells, built, cliff)
		result.merge({"removed": removed, "usec": Time.get_ticks_usec() - started})
	var id := WorkerThreadPool.add_task(task, false, "Rocks kept by a sculpt stroke")
	_job = {
		"id": id,
		"result": result,
		"cells": cells,
		"changed": changed,
		"record": record,
		"keep": keep,
	}
	return true


## Applies a finished job (`wait`: waits for it): its rocks become props and its record is
## filled. `rocks`, `aligned` (DressingGround.aligned_assets) and `snap_start` (cell -> {asset
## id -> rows} at the stroke's start) are the editor's. Returns the stroke's sample rectangle
## to regenerate, or an empty one when nothing was applied.
func finish(wait: bool, rocks: Dictionary, aligned: Dictionary, snap_start: Dictionary) -> Rect2i:
	if _job.is_empty() or (not wait and not WorkerThreadPool.is_task_completed(_job.id)):
		return Rect2i()
	WorkerThreadPool.wait_for_task_completion(_job.id)
	var job := _job
	_job = {}
	var started := Time.get_ticks_usec()
	var kept := _convert(
		job.result.get("removed", {}), job.cells, rocks, aligned, snap_start, job.keep
	)
	var record: Dictionary = job.record
	for cell in kept.props_before:
		if not record.props_before.has(cell):
			record.props_before[cell] = kept.props_before[cell]
		record.props_after[cell] = props.cell_rows(cell).duplicate(true)
	record.kept.merge(kept.scatter_start)
	last_usec = Time.get_ticks_usec() - started
	last_worker_usec = int(job.result.get("usec", 0))
	last_kept = 0
	for cell in record.kept:
		for asset_id in record.kept[cell]:
			@warning_ignore("integer_division")
			last_kept += (record.kept[cell][asset_id] as PackedFloat32Array).size() / 10
	return job.changed


## Waits for a running job and drops it (the map is closing).
func release() -> void:
	if not _job.is_empty():
		WorkerThreadPool.wait_for_task_completion(_job.id)
		_job = {}


## Undo (`redo` false) puts a stroke's kept rocks (`kept`: cell -> {asset id -> scatter rows at
## the stroke's start}) back into the scatter; redo takes them out again. Unanimated: the
## editor swaps the props at the same time.
func swap(kept: Dictionary, redo: bool) -> void:
	if not is_instance_valid(scatter):
		return
	for cell in kept:
		var rows := RockKeep.swap_kept(scatter.cell_rows(cell), kept[cell], redo)
		scatter.set_cells({cell: rows}, false)


## The cells of `area` grown by the relation halo (stones near a boulder) with a rock drawn.
func _cells(area: Rect2, rocks: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if rocks.is_empty() or not is_instance_valid(scatter) or not is_instance_valid(props):
		return cells
	var halo := maxf(document.sample_step().x, document.sample_step().y)
	var regen := scatter.get_regen()
	if regen != null:
		var deepest := 0.0
		for biome_id in document.biome_ids:
			deepest = maxf(deepest, regen.max_reach(biome_id))
		halo += deepest
	for cell in ScatterGenerator.cells_in_bounds(area.grow(halo)):
		for asset_id in scatter.cell_rows(cell):
			if rocks.has(asset_id):
				cells.append(cell)
				break
	return cells


## Every drawn rock of `cells` whose key `removed` lists (RockKeep.removed_keys) leaves the
## scatter and becomes a prop (RockKeep.kept_row: tilted as the snap left it, capped, bedded),
## at once and unanimated, unless `keep` (Callable(asset id, bedded row) -> bool, optional)
## refuses it: that one stays in the scatter, and the regeneration shrinks it out. Returns
## {"props_before": {cell: props rows before, for the cells that gained rocks},
## "scatter_start": {cell: {asset id: the kept rows at the stroke's start}}}.
func _convert(
	removed: Dictionary,
	cells: Array[Vector2i],
	rocks: Dictionary,
	aligned: Dictionary,
	snap_start: Dictionary,
	keep: Callable = Callable()
) -> Dictionary:
	var out := {"props_before": {}, "scatter_start": {}}
	if removed.is_empty() or not is_instance_valid(scatter) or not is_instance_valid(props):
		return out
	var grid := GroundSnap.grid_of(document)
	for cell in cells:
		var rows: Dictionary = scatter.cell_rows(cell).duplicate()
		var start: Dictionary = snap_start.get(cell, {})
		var gained := {}
		var starts := {}
		for asset_id in rows.keys():
			var gone: Dictionary = removed.get(asset_id, {})
			if gone.is_empty() or not rocks.has(asset_id):
				continue
			var split := RockKeep.split_kept(
				rows[asset_id], start.get(asset_id, PackedFloat32Array()), gone
			)
			var flat: PackedFloat32Array = split.kept
			if flat.is_empty():
				continue
			var rest: PackedFloat32Array = split.rest
			var start_rows := PackedFloat32Array()
			var radius := GroundSnap.footing_radius(rocks[asset_id])
			var bedded := PackedFloat32Array()
			@warning_ignore("integer_division")
			for r in flat.size() / MapDocument.ROW_STRIDE:
				var row := PropRows.row_at(flat, r)
				var bed := RockKeep.kept_row(
					row, document.heights, grid, radius, aligned.has(asset_id)
				)
				if keep.is_valid() and not keep.call(asset_id, bed):
					rest.append_array(row)
					continue
				bedded.append_array(bed)
				start_rows.append_array(PropRows.row_at(split.start, r))
			rows[asset_id] = rest
			if bedded.is_empty():
				continue
			starts[asset_id] = start_rows
			gained[asset_id] = bedded
		if gained.is_empty():
			continue
		scatter.set_cells({cell: rows}, false)
		var placed: Dictionary = props.cell_rows(cell).duplicate(true)
		out.props_before[cell] = placed.duplicate(true)
		for asset_id in gained:
			var joined: PackedFloat32Array = placed.get(asset_id, PackedFloat32Array()).duplicate()
			joined.append_array(gained[asset_id])
			placed[asset_id] = joined
		props.set_cells({cell: placed}, false)
		out.scatter_start[cell] = starts
	return out
