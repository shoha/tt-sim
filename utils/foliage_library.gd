class_name FoliageLibrary
extends RefCounted

## Serves the content libraries into the palette and keeps the open map in step with them. Since
## step S10 (2026-10-25) there is one foliage set: the libraries LibraryRegistry serves (`core`,
## which ships as the folder res://libraries/core, then the user's libraries and the developer
## override). The treecube palette and the plantgen-package A/B switch it used to run are gone; the
## developer A/B is now "core against a dev folder" (LibraryRegistry.set_dev_override or settings
## `[library] dev_path`, whose biomes replace core's of the same runtime id).
##
## apply() clears the palette caches and the wind guard's representative caches, then serves the
## libraries again (LibraryRegistry.apply). refresh_libraries() is apply() plus
## EventBus.foliage_library_changed, which Root turns into a rebuild of the open map; callers use
## it after the manager enabled, disabled, installed or removed a library. Laying has no undo of
## its own: clearing the cache is the removal.
##
## Saved maps hold scatter rows keyed by asset id. Rows are derived data (the document keeps the
## biome painting and the seed they came from), so adapt_async() regenerates them from the painting
## under the served libraries whenever a row's asset is missing: the documented behaviour for a map
## saved under another asset set (the retired treecube palette: step S10 kept core's biome ids, so
## such a map's painting still resolves and its plants are drawn from core's assets). A painting
## that names a biome no library serves regenerates nothing and the map draws no plants there.
## Hand-placed props are not derived: the ones no library supplies are counted and skipped by the
## build, as for any asset a build lacks. No compatibility work is done for old ids.
##
## settings.cfg section "foliage" (keys "library", "package_path") belonged to the retired switch;
## nothing reads it any more and the file is left alone.

## Cells one regeneration job covers; the whole map is a few hundred cells.
const JOB_CELLS := 16


## Clears the caches and serves the libraries again: {"ok", "error", "content_library"
## (LibraryRegistry.apply's report)}. Meshes already handed out are unaffected, so a map built
## before the call keeps drawing its old plants until it is rebuilt. Not ok only when the developer
## override cannot be served; a library that fails is an entry with status error in the manager and
## a warning, and the others are served.
static func apply(root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	reset_caches()
	PaletteLibrary.base_for_serving(root)
	var content := LibraryRegistry.apply(root)
	if not content["ok"]:
		push_warning("FoliageLibrary: %s" % content["error"])
	for line: String in content["errors"]:
		push_warning("FoliageLibrary: %s" % line)
	return {"ok": content["ok"], "error": content["error"], "content_library": content}


## apply() at startup, before any map or the graphics warm-up reads the palette: a persisted
## developer path (settings.cfg `[library] dev_path`) becomes the override, then the housekeeping
## of the downloaded-collections cache runs (a crashed install's leftovers go, a `.received`
## folder of the earlier session-only cache is adopted once; LibraryFromHost.startup) and the
## libraries are served again when it adopted any.
static func apply_saved() -> void:
	LibraryRegistry.use_saved_override()
	var result := apply()
	if not result["ok"]:
		push_warning("FoliageLibrary: %s" % result["error"])
	var started := LibraryFromHost.startup()
	if not (started["adopted"] as Array).is_empty():
		apply()


## Serves the libraries again (one was enabled, disabled, installed or removed, or the override
## changed) and announces it so the open map rebuilds.
static func refresh_libraries() -> Dictionary:
	var result := apply()
	if result["ok"]:
		EventBus.foliage_library_changed.emit("")
	return result


## Drops every palette-derived cache that keys on the served libraries.
static func reset_caches() -> void:
	PaletteLibrary.clear_cache()
	WindFoliage.reset_caches()


## What `doc` holds that the served libraries cannot resolve: {"missing_ids" (scatter asset ids
## the palette lacks), "missing_rows" (their rows), "props_missing" (hand-placed asset ids the
## palette lacks)}. Pure reads.
static func analyse(doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var assets: Dictionary = PaletteLibrary.get_palette(root)["assets"]
	var missing := PackedStringArray()
	var missing_rows := 0
	for asset_id: String in doc.scatter:
		if not assets.has(asset_id):
			missing.append(asset_id)
			missing_rows += doc.scatter[asset_id].size() / MapDocument.ROW_STRIDE
	var props_missing := 0
	for asset_id: String in doc.props:
		if not assets.has(asset_id):
			props_missing += 1
	return {"missing_ids": missing, "missing_rows": missing_rows, "props_missing": props_missing}


## Regenerates `doc.scatter` (and its mass anchors) from the biome painting under the served
## libraries when any scatter row names an asset the palette lacks; otherwise leaves the document
## alone. A coroutine: the palette reads happen here on the main thread, the generation on a
## worker over a snapshot, and `tree` supplies the frames to wait on. Returns analyse()'s report
## plus "regenerated" (bool), "rows" (rows written) and "usec". A caller that split the rows
## into cells beforehand splits them again when "regenerated".
static func adapt_async(
	doc: MapDocument, tree: SceneTree, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	var report := analyse(doc, root)
	report["regenerated"] = false
	report["rows"] = 0
	report["usec"] = 0
	if (report["missing_ids"] as PackedStringArray).is_empty() or doc.biome_ids.is_empty():
		return report
	var started := Time.get_ticks_usec()
	var regen := _planned(doc, root)
	var snapshot := ScatterRegen.snapshot(doc)
	var out := {}
	var task := WorkerThreadPool.add_task(
		func() -> void: _run_all(regen, snapshot, out), false, "FoliageLibrary regenerate scatter"
	)
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	doc.scatter = out["scatter"]
	doc.mass_anchors = out["mass_anchors"]
	report["regenerated"] = true
	report["rows"] = out["rows"]
	report["usec"] = Time.get_ticks_usec() - started
	return report


## One line for the player/log about what adapt_async did, "" when it did nothing.
static func describe(report: Dictionary) -> String:
	if not report.get("regenerated", false):
		return ""
	var text := (
		(
			"Foliage: scatter rebuilt from the biome painting (%d plants; the saved rows named %d"
			+ " assets the installed libraries lack)."
		)
		% [report["rows"], (report["missing_ids"] as PackedStringArray).size()]
	)
	if report["props_missing"] > 0:
		text += " %d hand-placed assets are missing and skipped." % report["props_missing"]
	return text


## The scheduler with every painted biome registered and the whole map requested.
static func _planned(doc: MapDocument, root: String) -> ScatterRegen:
	var regen := ScatterRegen.for_document(doc)
	regen.built_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("built", root))
	regen.cliff_surfaces = PackedStringArray(PaletteLibrary.surfaces_with_role("cliff", root))
	for biome_id in doc.biome_ids:
		regen.set_biome(biome_id, PaletteLibrary.species(biome_id, root))
	regen.request_region(regen.bounds)
	return regen


## Worker half of adapt_async(): runs every job, then writes "scatter", "mass_anchors" and
## "rows" into `out`. Touches only its arguments.
static func _run_all(regen: ScatterRegen, snapshot: MapDocument, out: Dictionary) -> void:
	var by_cell := {}
	var table := {}
	while regen.has_pending():
		var job := regen.take_job(JOB_CELLS)
		if job.is_empty():
			break
		var result := ScatterRegen.run(snapshot, job["work"])
		var rows_by_cell: Dictionary = result["rows_by_cell"]
		for cell: Vector2i in rows_by_cell:
			var held: Dictionary = by_cell.get(cell, {})
			held.merge(rows_by_cell[cell])
			by_cell[cell] = held
		ScatterMass.merge_into(table, result["anchors"])
	var cells: Array = by_cell.keys()
	cells.sort()
	var flat: Dictionary[String, PackedFloat32Array] = {}
	var total := 0
	for cell: Vector2i in cells:
		for asset_id: String in by_cell[cell]:
			var rows: PackedFloat32Array = by_cell[cell][asset_id]
			var joined: PackedFloat32Array = flat.get(asset_id, PackedFloat32Array())
			joined.append_array(rows)
			flat[asset_id] = joined
			total += rows.size() / MapDocument.ROW_STRIDE
	out["scatter"] = flat
	out["mass_anchors"] = ScatterMass.anchors_entry(table, flat)
	out["rows"] = total
