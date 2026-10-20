class_name ScatterApply
extends RefCounted

## How AuthoredScatter lands its finished regeneration jobs on the main thread: which of them,
## in what order, and how many a frame (card native-cover round 2, 2026-10-20).
##
## Why it needs a policy. With whole leads (ScatterRegen "Whole leads") every cell under a brush
## lands a fresh result about every live_interval_msec, and each landing rebuilds that cell's
## MultiMeshes on the main thread. Landing all of them as they arrive cost 3 ms of p95 frame
## time; landing one lead a frame (round 1's cap) kept the frames but backed up, so the cover
## trailed the brush wherever frames were slow. So landings are spent by cost:
##
## - Coalesced. A cell takes only the newest of its waiting results; an older one is dropped
##   unapplied, never shown in sequence (the newer one already holds the cell as the brush
##   left it). ScatterRegen.landed() lets a cell take its next lead while one waits here.
## - Nearest first. Waiting results land in order of distance from ScatterRegen.focus (the
##   latest live request), so the cells under the brush change first and the halo waits.
## - Within a budget. Each frame lands results until budget_usec of rebuild time is spent,
##   judging the next one's cost from the rows it carries at the cost per row measured so far,
##   and always lands at least one, so a burst spreads over frames instead of spiking one.
## - Skipping what shows nothing. A provisional landing (a stale whole lead) that changes no
##   rows is not rebuilt, nor one outside the brush's rectangle that changes almost none (the
##   relation halo's leads at the brush edge): the cell's later landing carries the change.
##
## A current result (ScatterRegen.accept) always lands when its turn comes; only provisional
## ones are skipped. `legacy` restores round 1's behaviour (in arrival order, no coalescing or
## skipping, `max_leads` lead results a frame) for measurement.

## The rebuild time a frame may spend landing results, in microseconds. Chosen from cover_perf
## (PERFORMANCE.md "Ground cover under the brush").
const BUDGET_USEC := 2000
## A provisional landing outside the brush that changes at most this many rows is skipped.
const NEAR_NOTHING_ROWS := 2
## Starting estimate of the rebuild cost per carried row, before any landing is measured.
const START_USEC_PER_ROW := 1.0

## Microseconds of rebuild a frame may spend; negative lands everything ready.
var budget_usec: int = BUDGET_USEC
## Lead results landed per frame at most; negative for no count cap (round 1's cap was 1).
var max_leads: int = -1
## Round 1's landing: arrival order, every ready result, no coalescing or skipping.
var legacy: bool = false
## Counts since the last reset_counts(), for measurement.
var counts: Dictionary = {}
var _usec_per_row: float = START_USEC_PER_ROW


func _init() -> void:
	reset_counts()


func reset_counts() -> void:
	counts = {"landed": 0, "dropped": 0, "skipped": 0, "deferred": 0, "frames": 0}


## Moves the jobs of `jobs` whose worker task has completed to `finished`, noting the species
## their rows need, and tells `regen` their lead jobs landed (unless legacy). Returns the worker
## microseconds of the last one, or -1 when none completed.
func collect(jobs: Array[Dictionary], finished: Array[Dictionary], regen: ScatterRegen) -> int:
	var usec := -1
	for entry in jobs.duplicate():
		if not WorkerThreadPool.is_task_completed(entry.id):
			continue
		jobs.erase(entry)
		WorkerThreadPool.wait_for_task_completion(entry.id)
		var result: Dictionary = entry.result
		usec = result.get("usec", 0)
		var needs := {}
		for cell_rows in (result.get("rows_by_cell", {}) as Dictionary).values():
			for asset_id in cell_rows:
				needs[asset_id] = true
		entry["needs"] = needs.keys()
		finished.append(entry)
		if not legacy:
			regen.landed(entry.job)
	return usec


## Lands this frame's share of `finished` (AuthoredScatter's) on `scatter` (see the header):
## each landed result's current cells (ScatterRegen.accept) and, for a lead job, the live cells
## it shows until their full job lands (ScatterRegen.provisional).
func land(scatter: AuthoredScatter, finished: Array[Dictionary], regen: ScatterRegen) -> void:
	var ready: Array[Dictionary] = []
	for entry in finished:
		if scatter.species_ready(entry.needs):
			ready.append(entry)
	if ready.is_empty():
		return
	counts.frames += 1
	if not legacy:
		var waiting := ready.size()
		ready = _coalesced(ready, finished)
		counts.dropped += waiting - ready.size()
		var centre := regen.focus.get_center() / ScatterChunker.CHUNK_SIZE_WORLD_UNITS
		ready.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return _distance(a, centre) < _distance(b, centre)
		)
	var started := Time.get_ticks_usec()
	var spent := 0.0
	var delta := 0
	var leads := 0
	var cells: Array[Vector2i] = []
	for entry in ready:
		var job: Dictionary = entry.job
		var lead: bool = job.get("lead", false)
		if lead and max_leads >= 0 and leads >= max_leads:
			counts.deferred += 1
			continue
		var carried := _rows_carried(entry)
		# The first landing of a frame always goes, so the queue never stalls.
		if budget_usec >= 0 and spent > 0.0 and spent + carried * _usec_per_row > budget_usec:
			counts.deferred += 1
			continue
		finished.erase(entry)
		leads += 1 if lead else 0
		ScatterMass.merge_into(scatter.mass_anchors, entry.result.get("anchors", {}))
		var fresh: Dictionary = entry.result.get("rows_by_cell", {})
		var current := regen.accept(job)
		var shown: Array[Vector2i] = []
		if not entry.get("cancelled", false):
			shown = regen.provisional(job)
		var by_cell := {}
		for cell in current + shown:
			var base := scatter.cell_rows(cell)
			var merged := ScatterRegen.merge_cell(base, job.regenerated[cell], fresh.get(cell, {}))
			if not legacy and cell in shown and _skip(cell, base, merged, regen.focus):
				counts.skipped += 1
				continue
			by_cell[cell] = merged
		if by_cell.is_empty():
			continue
		var t := Time.get_ticks_usec()
		delta += scatter.rebuild_cells(by_cell)
		var cost := float(Time.get_ticks_usec() - t)
		spent += cost
		counts.landed += 1
		if carried > 0:
			_usec_per_row = lerpf(_usec_per_row, cost / carried, 0.2)
		for cell in by_cell:
			cells.append(cell)
	if not cells.is_empty():
		scatter.finish_cells(cells, delta, started)


## `ready` without the results a newer ready one supersedes in every cell (dropped from
## `finished` too): a cell lands only its newest result.
static func _coalesced(ready: Array[Dictionary], finished: Array[Dictionary]) -> Array[Dictionary]:
	var newest := {}
	for entry in ready:
		for cell in entry.job.cells:
			newest[cell] = maxi(newest.get(cell, -1), entry.job.generations.get(cell, -1))
	var kept: Array[Dictionary] = []
	for entry in ready:
		var keep := false
		for cell in entry.job.cells:
			keep = keep or entry.job.generations.get(cell, -1) >= newest[cell]
		if keep:
			kept.append(entry)
		else:
			finished.erase(entry)
	return kept


## Distance (in cells) from `centre` to the nearest cell of a ready entry's job.
static func _distance(entry: Dictionary, centre: Vector2) -> float:
	var best := INF
	for cell: Vector2i in entry.job.cells:
		best = minf(best, (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(centre))
	return best


## Rows a result carries (every regenerated asset of its cells): what its rebuild scales with.
@warning_ignore("integer_division")
static func _rows_carried(entry: Dictionary) -> int:
	var rows := 0
	for cell_rows: Dictionary in (entry.result.get("rows_by_cell", {}) as Dictionary).values():
		for asset_rows: PackedFloat32Array in cell_rows.values():
			rows += asset_rows.size() / MapDocument.ROW_STRIDE
	return rows


## True when a provisional landing of `cell` from `base` to `merged` rows shows nothing worth
## a rebuild: no asset's rows differ, or the cell lies outside the brush (`focus`) and the rows
## that differ come to at most NEAR_NOTHING_ROWS (a differing asset counts at least one).
@warning_ignore("integer_division")
static func _skip(cell: Vector2i, base: Dictionary, merged: Dictionary, focus: Rect2) -> bool:
	var changed := 0
	var assets := base.duplicate()
	assets.merge(merged)
	for asset_id in assets:
		var before: PackedFloat32Array = base.get(asset_id, PackedFloat32Array())
		var after: PackedFloat32Array = merged.get(asset_id, PackedFloat32Array())
		if before != after:
			changed += maxi(1, absi(after.size() - before.size()) / MapDocument.ROW_STRIDE)
	if changed == 0:
		return true
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var under := Rect2(Vector2(cell) * size, Vector2(size, size)).intersects(focus, true)
	return not under and changed <= NEAR_NOTHING_ROWS
