class_name ScatterRefresh
extends RefCounted

## Regenerating an authored map's scatter when a biome's RULES change, not its painting (the
## biome designer, step S8a): AuthoredScatter regenerates cells when a brush changes the masks,
## and this is the same machinery pointed at the rules. After the new compile was laid over the
## palette (LibraryRegistry.serve_draft), biome() re-registers the biome's rules with the
## scheduler (ScatterRegen.replace_biome says which species the edit can change), clears the
## rows of assets no rule places any more, and queues the whole map for exactly those species,
## so one edited rule regenerates the rules it can influence and leaves the others' rows as
## they are. Static functions over an AuthoredScatter (they use its scheduler and job list, which
## is why they live beside it and not in it: scatter.gd is at the lint cap).

## Seconds a cancelled or finished regeneration needs no more, for a caller's polling.
const POLL_SECONDS := 0.05


## Re-registers `biome_id`'s rules from the palette and requests the regeneration of the map
## for the species they changed (`whole`: for every species of the biome). Returns {"species"
## (requested), "of" (rules in the biome), "keys", "cells", "removed" (assets cleared),
## "usec" (main-thread time of this call)}; {} when the scatter has no document attached.
static func biome(scatter: AuthoredScatter, biome_id: String, whole: bool = false) -> Dictionary:
	var regen := scatter.get_regen()
	if regen == null:
		return {}
	var started := Time.get_ticks_usec()
	var species := PaletteLibrary.species(biome_id, scatter.palette_root)
	var delta := regen.replace_biome(biome_id, species)
	scatter.prepare_biome(biome_id)
	var removed: PackedStringArray = delta["removed_assets"]
	var cleared := drop_assets(scatter, removed)
	var indices: PackedInt32Array = delta["indices"]
	if whole:
		indices = PackedInt32Array(range(species.size()))
	var cells := regen.request_region(regen.bounds, false, -1, {biome_id: indices})
	regen.cancel_stale(scatter._jobs)
	scatter._dispatch_jobs()
	scatter.set_process(true)
	return {
		"species": indices.size(),
		"of": species.size(),
		"keys": delta["keys"],
		"cells": cells.size(),
		"removed": cleared,
		"usec": Time.get_ticks_usec() - started,
	}


## Removes every instance of `asset_ids` from the scatter (shrinking out) and returns how many
## cells held one.
static func drop_assets(scatter: AuthoredScatter, asset_ids: PackedStringArray) -> int:
	if asset_ids.is_empty():
		return 0
	var fresh := {}
	for cell: Vector2i in scatter._cells:
		var held: Dictionary = scatter._cells[cell]
		var kept := {}
		var hit := false
		for asset_id: String in held:
			if asset_id in asset_ids:
				hit = true
			else:
				kept[asset_id] = held[asset_id]
		if hit:
			fresh[cell] = kept
	if not fresh.is_empty():
		var cells: Array[Vector2i] = []
		cells.assign(fresh.keys())
		var started := Time.get_ticks_usec()
		scatter.finish_cells(cells, scatter.rebuild_cells(fresh, true), started)
	return fresh.size()


## Cells still waiting for a job, jobs running and results waiting to land: 0 when the
## regeneration is over (the progress indicator's remaining count).
static func left(scatter: AuthoredScatter) -> int:
	var regen := scatter.get_regen()
	if regen == null:
		return 0
	return regen.pending_count() + scatter._jobs.size() + scatter._finished.size()


## Drops the queued work and tells the jobs in flight to stop; what has landed stays on screen
## (cells regenerated for the new rules next to cells still showing the old ones).
static func cancel(scatter: AuthoredScatter) -> void:
	var regen := scatter.get_regen()
	if regen == null:
		return
	regen.cancel_all()
	for entry in scatter._jobs:
		if not entry.get("cancelled", false):
			(entry.cancel as Semaphore).post()
			entry["cancelled"] = true
	scatter._finished.clear()
