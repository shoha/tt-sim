class_name ScatterRegen
extends RefCounted

## Bookkeeping for regenerating authored scatter after the biome masks change: which 10 m
## cells and species a painted region dirties, how that becomes a job a worker thread can
## run on plain data, and which finished jobs are still current. AuthoredScatter owns one
## and runs the jobs on WorkerThreadPool; everything here except run() is main-thread
## state, and run() is a pure static so it is safe on any thread.
##
## Dirty region. Painting changes the density samples inside a rectangle. An instance at
## p depends on the density within ScatterGenerator.species_reach() of p plus one sample
## step (the bilinear lookup), so species s is regenerated in every cell the rectangle
## grown by that reach touches. Most species have reach 0 and are regenerated only where
## the brush was; the relation-driven ones (stones near boulders, bluebells near bushes)
## also in the halo around it, which is cheap because those are the sparse species.
## Species that place the same asset are always regenerated together, since a cell's
## rows are replaced per asset.
##
## Latest wins, per cell. Every request bumps the generation of each cell it dirties, and
## a job records the generations it was taken at. A finished job is applied only to the
## cells no request has touched since; the rest are dropped, and the newer request (queued
## or already running) carries their work too, because a cell's dirty species accumulate
## until a current job for it is applied. Queued cells are coalesced: a stroke that
## dabs the same cell ten times while a job runs queues it once.

## Cells per job. One: a dense cell takes about 50 ms, and one cell per job lets the pool
## run a four-cell dab in parallel instead of in series.
const DEFAULT_CELLS_PER_JOB := 1

var map_seed: int = 0
## The map rectangle in world XZ; nothing outside it is regenerated.
var bounds: Rect2 = Rect2()
## The document's sample step (the larger axis); the bilinear lookup reaches this far.
var sample_step: float = 0.25

## biome id -> {"species": Array[Dictionary], "reach": PackedFloat32Array,
## "assets": Array[PackedStringArray] per species, "groups": Array[PackedInt32Array]
## (species sharing an asset with each species, itself included)}.
var _biomes: Dictionary = {}
## cell -> {biome id -> {species index: true}}: accumulated since the cell was last applied.
var _dirty: Dictionary = {}
## cell -> generation, bumped by every request that dirties the cell.
var _generation: Dictionary = {}
## cell -> true for cells waiting for a job, in request order.
var _pending: Dictionary = {}


## A scheduler for one map: its seed, rectangle and sample step.
static func for_document(doc: MapDocument) -> ScatterRegen:
	var regen := ScatterRegen.new()
	regen.map_seed = doc.map_seed
	regen.bounds = Rect2(-doc.extent_m() * 0.5, doc.extent_m())
	var step := doc.sample_step()
	regen.sample_step = maxf(step.x, step.y)
	return regen


## Registers a biome the document paints (PaletteLibrary.species(biome_id), read on the
## main thread; a copy is kept so workers never touch the palette cache).
func set_biome(biome_id: String, species: Array[Dictionary]) -> void:
	var copy: Array[Dictionary] = []
	for rule in species:
		copy.append(rule.duplicate(true))
	var plan := ScatterPlan.build(biome_id, copy, map_seed)
	var assets: Array[PackedStringArray] = []
	for rule in copy:
		assets.append(PackedStringArray(rule.get("assets", [])))
	_biomes[biome_id] = {
		"species": copy,
		"reach": ScatterGenerator.species_reach(plan),
		"assets": assets,
		"groups": _asset_groups(assets),
	}


func has_biome(biome_id: String) -> bool:
	return _biomes.has(biome_id)


## The deepest species reach of a registered biome, in metres (0 for an unknown one).
func max_reach(biome_id: String) -> float:
	var reach: PackedFloat32Array = _biomes.get(biome_id, {}).get("reach", PackedFloat32Array())
	var deepest := 0.0
	for r in reach:
		deepest = maxf(deepest, r)
	return deepest


## Marks everything the density samples inside `rect` (world XZ) can change, in every
## registered biome. Returns the cells it dirtied.
func request_region(rect: Rect2) -> Array[Vector2i]:
	var touched := {}
	for biome_id in _biomes:
		var info: Dictionary = _biomes[biome_id]
		var reach: PackedFloat32Array = info.reach
		for s in reach.size():
			var grown := rect.grow(reach[s] + sample_step)
			if not grown.intersects(bounds, true):
				continue
			for cell in ScatterGenerator.cells_in_bounds(grown.intersection(bounds)):
				_mark(cell, biome_id, info.groups[s])
				touched[cell] = true
	var cells: Array[Vector2i] = []
	for cell in touched:
		_generation[cell] = _generation.get(cell, 0) + 1
		_pending.erase(cell)
		_pending[cell] = true
		cells.append(cell)
	return cells


func has_pending() -> bool:
	return not _pending.is_empty()


func pending_count() -> int:
	return _pending.size()


## The next job, or {} when nothing waits: up to `max_cells` of the oldest pending cells,
## {"cells": Array[Vector2i], "generations": {cell: int}, "regenerated": {cell:
## PackedStringArray asset ids whose rows the job replaces}, "work": {biome id:
## {"species", "cells_by_species", "window"}}}. The work part is plain data for run().
func take_job(max_cells: int = DEFAULT_CELLS_PER_JOB) -> Dictionary:
	if _pending.is_empty():
		return {}
	var cells: Array[Vector2i] = []
	for cell in _pending:
		if cells.size() >= maxi(max_cells, 1):
			break
		cells.append(cell)
	var generations := {}
	var regenerated := {}
	var work := {}
	for cell in cells:
		_pending.erase(cell)
		generations[cell] = _generation.get(cell, 0)
		var assets := PackedStringArray()
		var per_biome: Dictionary = _dirty.get(cell, {})
		for biome_id in per_biome:
			var info: Dictionary = _biomes[biome_id]
			if not work.has(biome_id):
				work[biome_id] = _new_work(info)
			var entry: Dictionary = work[biome_id]
			for s in per_biome[biome_id]:
				(entry.cells_by_species[s] as Array).append(cell)
				entry.depth = maxf(entry.depth, info.reach[s])
				assets.append_array(info.assets[s])
		regenerated[cell] = assets
	for biome_id in work:
		var entry: Dictionary = work[biome_id]
		entry.window = _cells_rect(cells).grow(entry.depth + 2.0 * sample_step)
		entry.erase("depth")
	return {"cells": cells, "generations": generations, "regenerated": regenerated, "work": work}


## The cells of a finished `job` that are still current (no request touched them since
## the job was taken), clearing their dirty state. The rest are dropped.
func accept(job: Dictionary) -> Array[Vector2i]:
	var current: Array[Vector2i] = []
	for cell in job.get("cells", []):
		if _generation.get(cell, 0) == job.generations.get(cell, -1):
			current.append(cell)
			_dirty.erase(cell)
	return current


## Runs a job's work on a snapshot of the document. Pure and thread-safe: it reads only
## its arguments (the snapshot must not be mutated while it runs; AuthoredScatter hands
## over a copy). Returns {"rows_by_cell": {cell: {asset id: PackedFloat32Array}},
## "usec": int}.
static func run(snapshot: MapDocument, work: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var rows_by_cell := {}
	for biome_id in work:
		var entry: Dictionary = work[biome_id]
		var fields := ScatterGenerator.document_fields(snapshot, biome_id, entry.window)
		var species: Array[Dictionary] = []
		species.assign(entry.species)
		var rows := ScatterGenerator.generate_species_cells(
			biome_id,
			species,
			fields.density_at,
			fields.height_at,
			fields.normal_at,
			snapshot.map_seed,
			entry.cells_by_species,
			fields.bounds
		)
		for asset_id in rows:
			var split := split_by_cell(rows[asset_id])
			for cell in split:
				if not rows_by_cell.has(cell):
					rows_by_cell[cell] = {}
				var cell_rows: Dictionary = rows_by_cell[cell]
				var joined: PackedFloat32Array = cell_rows.get(asset_id, PackedFloat32Array())
				joined.append_array(split[cell])
				cell_rows[asset_id] = joined
	return {"rows_by_cell": rows_by_cell, "usec": Time.get_ticks_usec() - started}


## One cell's new asset rows: `existing` without the `regenerated` assets, plus `fresh`
## (empty arrays dropped). Pure; neither input is modified.
static func merge_cell(
	existing: Dictionary, regenerated: PackedStringArray, fresh: Dictionary
) -> Dictionary:
	var merged := {}
	for asset_id in existing:
		if not asset_id in regenerated:
			merged[asset_id] = existing[asset_id]
	for asset_id in fresh:
		var rows: PackedFloat32Array = fresh[asset_id]
		if rows.is_empty():
			continue
		if merged.has(asset_id):
			var joined: PackedFloat32Array = merged[asset_id].duplicate()
			joined.append_array(rows)
			merged[asset_id] = joined
		else:
			merged[asset_id] = rows
	return merged


## Flat rows split by the 10 m cell their origin falls in: cell -> PackedFloat32Array, rows
## kept in their original order. A trailing partial row is dropped.
@warning_ignore("integer_division")
static func split_by_cell(
	rows: PackedFloat32Array, chunk_size: float = ScatterChunker.CHUNK_SIZE_WORLD_UNITS
) -> Dictionary:
	var stride := MapDocument.ROW_STRIDE
	var by_cell := {}
	var count := rows.size() / stride
	var start := 0
	# Runs of consecutive rows in one cell are copied with one slice: generator output is
	# grouped by cell, so a whole cell's rows usually move in one native call.
	while start < count:
		var cell := _cell_of(rows, start, chunk_size)
		var end := start + 1
		while end < count and _cell_of(rows, end, chunk_size) == cell:
			end += 1
		var run_rows := rows.slice(start * stride, end * stride)
		if by_cell.has(cell):
			# A packed array read out of a Dictionary is a copy; write the joined one back.
			var joined: PackedFloat32Array = by_cell[cell]
			joined.append_array(run_rows)
			by_cell[cell] = joined
		else:
			by_cell[cell] = run_rows
		start = end
	return by_cell


static func _cell_of(rows: PackedFloat32Array, row: int, chunk_size: float) -> Vector2i:
	var base := row * MapDocument.ROW_STRIDE
	return Vector2i(floori(rows[base] / chunk_size), floori(rows[base + 2] / chunk_size))


## For each species, the species that share an asset with it, transitively (itself
## included), so a cell's rows of a shared asset are always rebuilt from every species
## that places it.
static func _asset_groups(assets: Array[PackedStringArray]) -> Array[PackedInt32Array]:
	var group_of := PackedInt32Array()
	for s in assets.size():
		group_of.append(s)
	var changed := true
	while changed:
		changed = false
		for a in assets.size():
			for b in range(a + 1, assets.size()):
				if group_of[a] == group_of[b]:
					continue
				for asset_id in assets[a]:
					if asset_id in assets[b]:
						var low := mini(group_of[a], group_of[b])
						group_of[a] = low
						group_of[b] = low
						changed = true
						break
	var groups: Array[PackedInt32Array] = []
	for s in assets.size():
		var members := PackedInt32Array()
		for other in assets.size():
			if group_of[other] == group_of[s]:
				members.append(other)
		groups.append(members)
	return groups


func _mark(cell: Vector2i, biome_id: String, species_group: PackedInt32Array) -> void:
	if not _dirty.has(cell):
		_dirty[cell] = {}
	var per_biome: Dictionary = _dirty[cell]
	if not per_biome.has(biome_id):
		per_biome[biome_id] = {}
	for s in species_group:
		per_biome[biome_id][s] = true


func _new_work(info: Dictionary) -> Dictionary:
	var cells_by_species: Array = []
	for _s in info.species.size():
		var none: Array[Vector2i] = []
		cells_by_species.append(none)
	var species: Array = []
	for rule in info.species:
		species.append((rule as Dictionary).duplicate(true))
	return {"species": species, "cells_by_species": cells_by_species, "depth": 0.0}


static func _cells_rect(cells: Array[Vector2i]) -> Rect2:
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var rect := Rect2(Vector2(cells[0]) * size, Vector2(size, size))
	for cell in cells:
		rect = rect.merge(Rect2(Vector2(cell) * size, Vector2(size, size)))
	return rect
