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
##
## Live cells (brush-latency, 2026-10-19). A brush re-requests the cells under it every frame,
## so under latest-wins alone no job there finishes current until the brush moves on or lifts,
## and plants appeared only after the release. A live request (a stroke in progress) marks its
## cells live, and a live cell also gets lead jobs: its dirty work restricted to its lead
## species, every species outside the ground class whose asset group is too. Species resolve
## large to ground and only look at earlier ones, so a lead job's rows are exactly what the
## full job gives those species, at a few ms each where a painted cell's ground cover costs
## hundreds (a grassland cell under a forest dab: 780 ms in all, 25 ms of it lead). A lead job
## is never current and never cancelled: provisional() shows it while the cell is still live
## and shows nothing newer, and the cell stays dirty and pending, so its full job still lands
## under latest-wins. Throttle: take_job() hands a live cell a lead job only when none is in
## flight, something newer than its rows on screen is owed, and it has shown nothing for
## LIVE_INTERVAL_MSEC. The final rows do not change: a lead result clears no dirty state, so the
## last full job replaces every asset a lead job did, from the document as the stroke left it.
##
## Whole leads (native-cover, 2026-10-20). Where jobs run natively a painted cell's whole job
## costs about 20 ms, so the ground-class restriction has no reason left: with `whole_leads` a
## lead job carries every dirty species, and so is the cell's full job, only protected. The
## cell's pending entry goes with it; a lead that lands current (no request since it was taken)
## is accepted like any job, and one that lands stale shows provisionally as before. While the
## brush is on a cell (live_hold_msec) the cell gets lead jobs only, one out at a time, so a held
## brush never spends a worker on a full job the next frame's request would make stale; once it
## lifts or moves on, latest-wins takes over. The ground cover then grows in under the brush,
## raised a little at every landing as the stroke raises the density. The GDScript path keeps
## the restricted lead jobs (a painted cell's ground cover costs about 750 ms there).
##
## Brush centres (motion, 2026-10-20). Each job carries, per cell, the point its new rows ripple
## out from as they arrive (ScatterArrival): the centre of the request nearest the cell's middle
## since the cell last landed current. A dab ripples from the dab; a stroke from the nearest point
## of its path, so a long stroke's trail spreads out sideways from where the brush passed instead
## of every cell waiting out the longest ripple from wherever the brush is now. A request that is
## not live (an undo, a cancelled stroke's revert, a sculpt) notes its rectangle's centre only
## where no stroke has noted one.

## Cells per job. One: one cell per job lets the pool run a dab's cells in parallel instead
## of in series (a painted cell under a dab takes 250 to 800 ms on a worker, its relation halo
## 10 to 100 ms; brush-latency, 2026-10-19).
const DEFAULT_CELLS_PER_JOB := 1
## A live cell shows a lead result at most this often.
const LIVE_INTERVAL_MSEC := 100
## A live cell gets lead jobs only while live requests keep coming (the brush is still on it):
## once the brush lifts or moves on, its full job goes first.
const LIVE_HOLD_MSEC := 50
## The size class whose species a lead job leaves to the full job.
const GROUND_CLASS := "ground"
const _NEVER := -1_000_000_000

var map_seed: int = 0
## The map rectangle in world XZ; nothing outside it is regenerated.
var bounds: Rect2 = Rect2()
## Lead jobs carry every dirty species and stand as the cell's full job (see the header). Set by
## AuthoredScatter where jobs run natively; off, lead jobs leave the ground class out.
var whole_leads: bool = false
## The live throttle (see the header), variables so a measurement can sweep them.
var live_interval_msec: int = LIVE_INTERVAL_MSEC
var live_hold_msec: int = LIVE_HOLD_MSEC
## The document's sample step (the larger axis); the bilinear lookup reaches this far.
var sample_step: float = 0.25
## Palette surfaces with role "built" (read on the main thread): painted ones clear the
## plants under them (ScatterGenerator.document_fields).
var built_surfaces: PackedStringArray = PackedStringArray()
## Palette surfaces with role "cliff" (main thread): painted rock clears plants too.
var cliff_surfaces: PackedStringArray = PackedStringArray()
## The rectangle (world XZ) of the latest live request: where the brush is, or last was.
var focus: Rect2 = Rect2()

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
## cell -> true for cells the latest request was live for, until a current job is applied.
var _live: Dictionary = {}
## cell -> the generation of the job whose rows the cell shows (lead or current), and the
## Time.get_ticks_msec() it was applied at.
var _shown_generation: Dictionary = {}
var _shown_msec: Dictionary = {}
## cell -> true while a lead job for it is out.
var _lead_out: Dictionary = {}
## cell -> Time.get_ticks_msec() of the last live request that touched it.
var _requested_msec: Dictionary = {}
## cell -> Time.get_ticks_msec() a lead job for it finished on its worker (landed()).
var _landed_msec: Dictionary = {}
## cell -> brush centre (Vector2, world XZ) its jobs carry (see "Brush centres").
var _centres: Dictionary = {}


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
	var groups := _asset_groups(assets)
	# Lead species (see the header): outside the ground class, with every asset-sharing one.
	var lead := {}
	for s in copy.size():
		var all_lead := true
		for other in groups[s]:
			all_lead = all_lead and copy[other].get("size_class", "") != GROUND_CLASS
		if all_lead:
			lead[s] = true
	var needs: Array[PackedInt32Array] = []
	for entry: Dictionary in plan.species:
		needs.append(_needs_of(plan, entry))
	_biomes[biome_id] = {
		"species": copy,
		"reach": ScatterGenerator.species_reach(plan),
		"assets": assets,
		"groups": groups,
		"lead": lead,
		"needs": needs,
	}


## set_biome() for a biome that is already registered and whose rules were edited (the biome
## designer): registers the new rules and says what they changed. Returns {"indices" (species
## of the NEW list whose rows may now differ: the rules that changed or are new, and every
## species that reads one of them through a relation, a shared spacing field or a clearance, or
## read a rule that was removed), "keys" (the same as rule keys), "removed_assets" (asset ids
## the old rules placed and the new ones do not)}. A biome not registered before is all new.
func replace_biome(biome_id: String, species: Array[Dictionary]) -> Dictionary:
	var old: Dictionary = _biomes.get(biome_id, {})
	set_biome(biome_id, species)
	var info: Dictionary = _biomes[biome_id]
	var now: Array = info.species
	var changed := {}
	var old_by_key := {}
	for s in (old.get("species", []) as Array).size():
		old_by_key[old.species[s].key] = s
	for s in now.size():
		var before: Variant = old_by_key.get(now[s].key)
		if before == null or old.species[before] != now[s]:
			changed[s] = true
	var removed := PackedStringArray()
	var new_assets := {}
	for asset_list: PackedStringArray in info.assets:
		for asset_id in asset_list:
			new_assets[asset_id] = true
	for asset_list: PackedStringArray in old.get("assets", []):
		for asset_id in asset_list:
			if not new_assets.has(asset_id) and not asset_id in removed:
				removed.append(asset_id)
	# Species that read a rule which is gone: found in the OLD dependency graph, by key.
	var new_index := {}
	for s in now.size():
		new_index[now[s].key] = s
	var gone := {}
	for key in old_by_key:
		if not new_index.has(key):
			gone[old_by_key[key]] = true
	var old_needs: Array = old.get("needs", [])
	for s in old_needs.size():
		for need in old_needs[s]:
			if gone.has(need) and new_index.has(old.species[s].key):
				changed[new_index[old.species[s].key]] = true
	var indices := _readers_closure(info.needs, changed)
	var keys := PackedStringArray()
	for s in indices:
		keys.append(String(now[s].key))
	return {"indices": indices, "keys": keys, "removed_assets": removed}


func has_biome(biome_id: String) -> bool:
	return _biomes.has(biome_id)


## Stops regenerating `biome_id` (the designer left a season for another).
func forget_biome(biome_id: String) -> void:
	_biomes.erase(biome_id)


## Every asset id the registered rules of `biome_id` place.
func assets_of(biome_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for asset_list: PackedStringArray in _biomes.get(biome_id, {}).get("assets", []):
		for asset_id in asset_list:
			if not asset_id in out:
				out.append(asset_id)
	return out


## Drops every queued and in-flight request: nothing is pending afterwards, and a job already
## out is stale (its result is dropped when it lands). The rows that are on screen stay as the
## landed jobs left them.
func cancel_all() -> void:
	_pending.clear()
	_dirty.clear()
	_live.clear()
	_lead_out.clear()
	for cell in _generation:
		_generation[cell] += 1


## The deepest species reach of a registered biome, in metres (0 for an unknown one).
func max_reach(biome_id: String) -> float:
	var reach: PackedFloat32Array = _biomes.get(biome_id, {}).get("reach", PackedFloat32Array())
	var deepest := 0.0
	for r in reach:
		deepest = maxf(deepest, r)
	return deepest


## Marks everything the density samples inside `rect` (world XZ) can change, in every
## registered biome. Returns the cells it dirtied. A `live` request (a brush stroke in
## progress) marks them live (see the header) and queues them nearest the rectangle first,
## so the cells under the brush get the first slots. `now_msec` defaults to now. `only`
## ({biome id: PackedInt32Array of species indices}) restricts the request to those species
## (and the species sharing an asset with them) of the biomes it names: the designer's edit of
## one rule regenerates the rules it can change and leaves the rest of the cell's rows alone.
func request_region(
	rect: Rect2, live: bool = false, now_msec: int = -1, only: Dictionary = {}
) -> Array[Vector2i]:
	var now := _now(now_msec)
	var touched := {}
	for biome_id in _biomes:
		if not only.is_empty() and not only.has(biome_id):
			continue
		var info: Dictionary = _biomes[biome_id]
		var reach: PackedFloat32Array = info.reach
		var wanted: PackedInt32Array = only.get(biome_id, PackedInt32Array())
		for s in reach.size():
			if not only.is_empty() and not s in wanted:
				continue
			var grown := rect.grow(reach[s] + sample_step)
			if not grown.intersects(bounds, true):
				continue
			for cell in ScatterGenerator.cells_in_bounds(grown.intersection(bounds)):
				_mark(cell, biome_id, info.groups[s])
				touched[cell] = true
	var cells: Array[Vector2i] = []
	cells.assign(touched.keys())
	if live:
		focus = rect
		var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
		var centre := rect.get_center() / size - Vector2(0.5, 0.5)
		cells.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				return (
					Vector2(a).distance_squared_to(centre) < Vector2(b).distance_squared_to(centre)
				)
		)
	for cell in cells:
		_generation[cell] = _generation.get(cell, 0) + 1
		_pending.erase(cell)
		_pending[cell] = true
		_note_centre(cell, rect.get_center(), live)
		# Live while the latest request was: an undo or a cancelled stroke's revert shows
		# nothing provisional.
		if live:
			_live[cell] = true
			_requested_msec[cell] = now
		else:
			_live.erase(cell)
	return cells


func has_pending() -> bool:
	return not _pending.is_empty()


func pending_count() -> int:
	return _pending.size()


## The next job, or {} when nothing waits: up to `max_cells` of the oldest pending cells,
## {"cells": Array[Vector2i], "generations": {cell: int}, "regenerated": {cell:
## PackedStringArray asset ids whose rows the job replaces}, "work": {biome id:
## {"species", "cells_by_species", "window"}}}. The work part is plain data for run(). A
## live cell due a lead job (see the header) at `now_msec` (default: now) gets one first: the
## same form for that one cell with "lead": true, its lead species only, the cell left pending;
## with whole_leads every dirty species, "whole": true, and the cell taken off pending. With
## whole_leads a cell the brush is still on gets no other job, so this can return {} while cells
## are pending.
func take_job(max_cells: int = DEFAULT_CELLS_PER_JOB, now_msec: int = -1) -> Dictionary:
	if _pending.is_empty():
		return {}
	var now := _now(now_msec)
	for cell in _pending:
		if _due_lead(cell, now):
			_lead_out[cell] = true
			var one: Array[Vector2i] = [cell]
			if whole_leads:
				_pending.erase(cell)
			return _job(one, true)
	var cells: Array[Vector2i] = []
	for cell in _pending:
		if cells.size() >= maxi(max_cells, 1):
			break
		if whole_leads and _held(cell, now):
			continue
		cells.append(cell)
	if cells.is_empty():
		return {}
	for cell in cells:
		_pending.erase(cell)
	return _job(cells, false)


## The cells of a finished `job` that are still current (no request touched them since
## the job was taken), clearing their dirty and live state. The rest are dropped. A lead job
## is never current (provisional() shows it) unless it is whole.
func accept(job: Dictionary, now_msec: int = -1) -> Array[Vector2i]:
	var current: Array[Vector2i] = []
	if job.get("lead", false) and not job.get("whole", false):
		return current
	var now := _now(now_msec)
	for cell in job.get("cells", []):
		var generation: int = job.generations.get(cell, -1)
		if _generation.get(cell, 0) == generation:
			current.append(cell)
			_dirty.erase(cell)
			_live.erase(cell)
			_centres.erase(cell)
			_shown_generation[cell] = generation
			_shown_msec[cell] = now
	return current


## The cells of a finished lead `job` that show its rows until their full job lands: still
## live, and showing nothing as new. Their dirty state stays, so the full job still replaces
## every asset this one did. Empty for a job that is not a lead job. Call it after accept(): a
## whole lead's current cells were accepted there and show nothing newer here.
func provisional(job: Dictionary, now_msec: int = -1) -> Array[Vector2i]:
	var shown: Array[Vector2i] = []
	if not job.get("lead", false):
		return shown
	var now := _now(now_msec)
	for cell in job.get("cells", []):
		_lead_out.erase(cell)
		var generation: int = job.generations.get(cell, -1)
		if not _live.has(cell) or generation <= _shown_generation.get(cell, -1):
			continue
		shown.append(cell)
		_shown_generation[cell] = generation
		_shown_msec[cell] = now
	return shown


## Notes that lead `job` finished on its worker at `now_msec` (default: now), before it is applied:
## its cells may take their next lead job from here (live_interval_msec after this landing) while
## it waits to be applied, and AuthoredScatter's landing (ScatterApply) keeps only the newest of a
## cell's waiting results. Without this call a lead stays out until provisional() applies it.
func landed(job: Dictionary, now_msec: int = -1) -> void:
	if not job.get("lead", false):
		return
	var now := _now(now_msec)
	for cell in job.get("cells", []):
		_lead_out.erase(cell)
		_landed_msec[cell] = now


## True when a request has touched every cell of `job` (take_job's) since it was taken, so
## accept() would drop all of its rows; a newer request carries those cells' work.
func is_stale(job: Dictionary) -> bool:
	for cell in job.get("cells", []):
		if _generation.get(cell, 0) == job.generations.get(cell, -1):
			return false
	return true


## Posts the cancel of each of AuthoredScatter's in-flight `entries` ({"job", "cancel": Semaphore})
## that is_stale: accept() would drop all its rows, and a stroke re-requests its cells every frame,
## so such jobs would otherwise hold the slots the current ones wait for (ground-opt-cpu2). run()
## then hands back what it has. Lead jobs are left to finish: they are short, and they are what
## a held brush shows.
func cancel_stale(entries: Array[Dictionary]) -> void:
	for entry in entries:
		if entry.get("cancelled", false) or entry.job.get("lead", false):
			continue
		if is_stale(entry.job):
			(entry.cancel as Semaphore).post()
			entry["cancelled"] = true


## True when live `cell` may have a lead job now: the brush still on it (LIVE_HOLD_MSEC), none
## out, something newer than its rows on screen owed, nothing shown for LIVE_INTERVAL_MSEC, and
## a lead species dirty there.
func _due_lead(cell: Vector2i, now: int) -> bool:
	if _lead_out.has(cell) or not _held(cell, now):
		return false
	if _shown_generation.get(cell, -1) >= _generation.get(cell, 0):
		return false
	var last := maxi(_shown_msec.get(cell, _NEVER), _landed_msec.get(cell, _NEVER))
	if now - last < live_interval_msec:
		return false
	var per_biome: Dictionary = _dirty.get(cell, {})
	for biome_id in per_biome:
		if whole_leads and not (per_biome[biome_id] as Dictionary).is_empty():
			return true
		var lead: Dictionary = _biomes[biome_id].lead
		for s in per_biome[biome_id]:
			if lead.has(s):
				return true
	return false


## True while the brush is on live `cell`: a live request touched it within live_hold_msec.
func _held(cell: Vector2i, now: int) -> bool:
	return _live.has(cell) and now - _requested_msec.get(cell, _NEVER) < live_hold_msec


## A job for `cells` (take_job's form): every dirty species, or with `lead` the lead ones (all of
## them with whole_leads).
func _job(cells: Array[Vector2i], lead: bool) -> Dictionary:
	var restricted := lead and not whole_leads
	var generations := {}
	var regenerated := {}
	var work := {}
	for cell in cells:
		generations[cell] = _generation.get(cell, 0)
		var assets := PackedStringArray()
		var per_biome: Dictionary = _dirty.get(cell, {})
		for biome_id in per_biome:
			var info: Dictionary = _biomes[biome_id]
			for s in per_biome[biome_id]:
				if restricted and not info.lead.has(s):
					continue
				if not work.has(biome_id):
					work[biome_id] = _new_work(info)
				var entry: Dictionary = work[biome_id]
				(entry.cells_by_species[s] as Array).append(cell)
				entry.depth = maxf(entry.depth, info.reach[s])
				assets.append_array(info.assets[s])
		regenerated[cell] = assets
	for biome_id in work:
		var entry: Dictionary = work[biome_id]
		entry.window = _cells_rect(cells).grow(entry.depth + 2.0 * sample_step)
		entry.erase("depth")
		entry.built = built_surfaces.duplicate()
		entry.cliff = cliff_surfaces.duplicate()
	var job := {
		"cells": cells, "generations": generations, "regenerated": regenerated, "work": work
	}
	var centres := {}
	for cell in cells:
		if _centres.has(cell):
			centres[cell] = _centres[cell]
	job["centres"] = centres
	if lead:
		job["lead"] = true
		if whole_leads:
			job["whole"] = true
	return job


## Notes `centre` (a request's) as `cell`'s brush centre when it is nearer the cell's middle than
## the one noted, or when none is (always for a live request; see "Brush centres").
func _note_centre(cell: Vector2i, centre: Vector2, live: bool) -> void:
	if not _centres.has(cell):
		_centres[cell] = centre
		return
	if not live:
		return
	var middle := (Vector2(cell) + Vector2(0.5, 0.5)) * ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var noted: Vector2 = _centres[cell]
	if middle.distance_squared_to(centre) < middle.distance_squared_to(noted):
		_centres[cell] = centre


static func _now(now_msec: int) -> int:
	return now_msec if now_msec >= 0 else Time.get_ticks_msec()


## A copy of what generation reads of `doc` (wet dressing and crossings too), for a worker:
## packed arrays are shared by reference (4.7), so without the copy a worker would read masks
## while the brush writes them or lose a buffer an append reallocates (crossings are replaced
## whole, never edited in place). About 0.1 ms for a 200 ft map. (Moved here from
## AuthoredScatter, which the mass anchors put over the line cap.)
static func snapshot(doc: MapDocument) -> MapDocument:
	var copy := MapDocument.new()
	copy.map_seed = doc.map_seed
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.heights = doc.heights.duplicate()
	copy.biome_ids = doc.biome_ids.duplicate()
	copy.biome_slots = doc.biome_slots.duplicate()
	copy.biome_density = doc.biome_density.duplicate()
	copy.surface_ids = doc.surface_ids.duplicate()
	copy.surface_weights = doc.surface_weights.duplicate()
	copy.water_dressing = doc.water_dressing.duplicate()
	copy.crossings = doc.crossings.duplicate()
	copy.walls = doc.walls.duplicate()
	return copy


## Runs a job's work on a snapshot of the document. Pure and thread-safe: it reads only
## its arguments (the copy must not be mutated while it runs; AuthoredScatter hands
## over a copy). A work entry's optional "blockers" (RockKeep.blockers) are the footprints
## of kept rocks no generated rock, tree or shrub grows inside. Returns {"rows_by_cell":
## {cell: {asset id: PackedFloat32Array}}, "anchors": the grass-mass anchors of those rows
## (ScatterMass.collect's table, this job's own), "usec": int}. Once `cancel` is posted
## (AuthoredScatter, for a job whose cells are all stale) it stops and returns what it has.
## Each biome runs in the native generator where it is built and covers the job (ScatterNative;
## the same rows, about fifty times faster), else in GDScript.
static func run(frozen: MapDocument, work: Dictionary, cancel: Semaphore = null) -> Dictionary:
	var started := Time.get_ticks_usec()
	var rows_by_cell := {}
	var anchors := {}
	for biome_id in work:
		if ScatterGenerator.cancelled(cancel):
			break
		var entry: Dictionary = work[biome_id]
		# The native generator when it is built and covers the job (ScatterNative), with
		# rows equal to GDScript's; otherwise the whole biome runs in GDScript.
		var rows: Variant = ScatterNative.run_biome(frozen, biome_id, entry, anchors)
		if rows == null:
			rows = _generate(frozen, biome_id, entry, anchors, cancel)
		for asset_id in rows:
			var split := split_by_cell(rows[asset_id])
			for cell in split:
				if not rows_by_cell.has(cell):
					rows_by_cell[cell] = {}
				var cell_rows: Dictionary = rows_by_cell[cell]
				var joined: PackedFloat32Array = cell_rows.get(asset_id, PackedFloat32Array())
				joined.append_array(split[cell])
				cell_rows[asset_id] = joined
	return {
		"rows_by_cell": rows_by_cell,
		"anchors": anchors,
		"usec": Time.get_ticks_usec() - started,
	}


## One biome of a job in GDScript (generate_species_cells over document_fields).
static func _generate(
	frozen: MapDocument, biome_id: String, entry: Dictionary, anchors: Dictionary, cancel: Semaphore
) -> Dictionary:
	var fields := ScatterGenerator.document_fields(
		frozen,
		biome_id,
		entry.window,
		entry.get("built", PackedStringArray()),
		entry.get("cliff", PackedStringArray())
	)
	var species: Array[Dictionary] = []
	species.assign(entry.species)
	return ScatterGenerator.generate_species_cells(
		biome_id,
		species,
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		frozen.map_seed,
		entry.cells_by_species,
		fields.bounds,
		fields.species_density_at,
		entry.get("blockers", PackedFloat32Array()),
		anchors,
		fields.density_ceiling_at,
		cancel,
		fields.wet_at,
		fields.water_dist_at
	)


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


## The species indices `entry` reads the final instances or the placement field of: its
## relation targets, the owners of its clearance fields and of its own spacing and clump
## fields (species of one size class share a spacing field, so they place against each other).
static func _needs_of(plan: Dictionary, entry: Dictionary) -> PackedInt32Array:
	var needs := PackedInt32Array()
	for relation: Dictionary in entry.near + entry.avoid:
		if not relation.target in needs:
			needs.append(relation.target)
	var field_indices: Array = entry.clearance.duplicate()
	field_indices.append(entry.field)
	field_indices.append(entry.parent_field)
	for field_index: int in field_indices:
		if field_index < 0:
			continue
		for owner in plan.fields[field_index].owners:
			if not owner in needs:
				needs.append(owner)
	return needs


## `seeds` ({species index: true}) grown to every species that reads a member (needs[s] holds
## a member), until nothing more joins; sorted indices.
static func _readers_closure(needs: Array, seeds: Dictionary) -> PackedInt32Array:
	var members := seeds.duplicate()
	var grew := true
	while grew:
		grew = false
		for s in needs.size():
			if members.has(s):
				continue
			for need in needs[s]:
				if members.has(need):
					members[s] = true
					grew = true
					break
	var out := PackedInt32Array()
	var keys: Array = members.keys()
	keys.sort()
	for s in keys:
		if s >= 0 and s < needs.size():
			out.append(s)
	return out


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
