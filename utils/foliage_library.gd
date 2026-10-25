class_name FoliageLibrary
extends RefCounted

## The DEVELOPER A/B switch between two foliage sets: "treecube" (the installed palette under
## assets/palette, the default) or "plantgen" (a built package, a folder anywhere on disk laid
## over the installed palette for every biome by PaletteLibrary.overlay_package). It exists so
## the two can be compared in the running game; nothing large ships in the repo, the setting
## points at the package folder. Players choose content through content libraries
## (LibraryRegistry), not through this class: since step S4 it only decides what the registry's
## libraries are laid over, and the libraries are served after it on every apply().
##
## One place applies the choice: apply() clears the palette caches and the wind guard's
## representative caches (so the installed palette reloads for treecube), then lays the
## package over all biomes for plantgen, then the content libraries (LibraryRegistry.apply:
## official, user and the developer override). The overlay has no undo of its own; clearing the
## cache is the removal, because the overlay only ever replaces cached palette entries. switch()
## is apply() plus the persisted setting plus EventBus.foliage_library_changed, which Root turns
## into a rebuild of the open map. refresh_libraries() serves the libraries again (after the
## manager enabled or disabled one) without touching the setting.
##
## Saved maps hold scatter rows keyed by asset id, and the two libraries name their assets
## differently, so a map saved under one library has rows the other cannot resolve. The rows
## are derived data (the document keeps the biome painting and the seed they came from), so
## adapt_async() regenerates them from the painting under the active library whenever a row's
## asset is missing. Hand-placed props are not derived: the ones the library lacks are counted
## and skipped by the build, as for any asset a build lacks. Settings: user://settings.cfg
## section "foliage", keys "library" and "package_path" (a dev setting, empty by default).

const TREECUBE := "treecube"
const PLANTGEN := "plantgen"
const LIBRARIES: Array[String] = [TREECUBE, PLANTGEN]
const SECTION := "foliage"
const KEY_LIBRARY := "library"
const KEY_PATH := "package_path"
## Cells one regeneration job covers; the whole map is a few hundred cells.
const JOB_CELLS := 16

## The library now served; process state, set by apply().
static var _active: String = TREECUBE
## The package folder the plantgen overlay came from, "" while treecube is served.
static var _package: String = ""
## The settings file; tests point it elsewhere.
static var settings_path: String = Paths.SETTINGS_PATH


## The library the palette serves now.
static func current() -> String:
	return _active


## The package folder behind the active plantgen overlay, "" for treecube.
static func active_package() -> String:
	return _package


## The persisted choice, TREECUBE when unset or unknown.
static func saved_library() -> String:
	var chosen := String(_read(KEY_LIBRARY, TREECUBE))
	return chosen if chosen in LIBRARIES else TREECUBE


## The persisted plantgen package folder, "" when unset.
static func package_path() -> String:
	return String(_read(KEY_PATH, ""))


## True when `folder` holds a package palette.json.
static func package_ready(folder: String) -> bool:
	return folder != "" and FileAccess.file_exists(folder.path_join(PaletteLibrary.PALETTE_FILE))


## True when the persisted package folder exists: the only time plantgen is offered.
static func available() -> bool:
	return package_ready(package_path())


## Writes the setting. An empty `folder` leaves the stored path alone.
static func save_settings(library: String, folder: String = "") -> void:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("FoliageLibrary: failed to load settings (err=%d), writing section only" % err)
	config.set_value(SECTION, KEY_LIBRARY, library)
	if folder != "":
		config.set_value(SECTION, KEY_PATH, folder)
	config.save(settings_path)


## Serves `library` from now on: {"ok", "library" (what is served after the call), "error",
## "report" (PaletteLibrary.overlay_package's, {} for treecube)}. Plantgen reads `folder`, else
## the persisted package folder; a missing or unreadable package changes nothing and says why.
## Meshes already handed out are unaffected, so a map built before the call keeps drawing its
## old plants until it is rebuilt.
static func apply(
	library: String, folder: String = "", root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	var result := {"ok": false, "library": _active, "error": "", "report": {}}
	if not library in LIBRARIES:
		result["error"] = "unknown foliage library '%s'" % library
		return result
	var package := folder if folder != "" else package_path()
	if library == PLANTGEN and not package_ready(package):
		result["error"] = "no plantgen package at '%s'" % package
		return result
	reset_caches()
	_active = TREECUBE
	_package = ""
	result["library"] = TREECUBE
	if library == PLANTGEN:
		var report := PaletteLibrary.overlay_package(package, root)
		result["report"] = report
		if not report["ok"]:
			# The cache was cleared, so the installed palette serves again.
			result["error"] = String(report["error"])
			_layer_content(result, root)
			return result
		_active = PLANTGEN
		_package = package
		result["library"] = PLANTGEN
	_layer_content(result, root)
	result["ok"] = true
	return result


## The content libraries (LibraryRegistry: official, user and the developer override, none by
## default) lay over whichever palette is served; the registry's report goes in
## result["content_library"]. A failure warns and changes nothing else.
static func _layer_content(result: Dictionary, root: String) -> void:
	var content := LibraryRegistry.apply(root)
	result["content_library"] = content
	if not content["ok"]:
		push_warning("FoliageLibrary: %s" % content["error"])
	for line: String in content["errors"]:
		push_warning("FoliageLibrary: %s" % line)


## apply() for the persisted choice, at startup before any map or the graphics warm-up reads
## the palette. A failure warns and leaves treecube. The content libraries (installed ones, and
## a persisted dev path, settings.cfg `[library] dev_path`) are served here too.
static func apply_saved() -> void:
	LibraryRegistry.use_saved_override()
	if saved_library() != PLANTGEN and not LibraryRegistry.discoverable():
		return
	var result := apply(saved_library())
	if not result["ok"]:
		push_warning("FoliageLibrary: %s; serving treecube" % result["error"])


## apply() as the user's choice: persisted when `persist`, and announced on the EventBus so the
## open map rebuilds. A failed apply persists and announces nothing.
static func switch(library: String, folder: String = "", persist: bool = true) -> Dictionary:
	var result := apply(library, folder)
	if not result["ok"]:
		push_warning("FoliageLibrary: %s" % result["error"])
		return result
	if persist:
		save_settings(library, folder)
	EventBus.foliage_library_changed.emit(library)
	return result


## Serves the content libraries again under the foliage set already active (a library was
## enabled, disabled, installed or removed) and announces it so the open map rebuilds; the
## persisted foliage setting is left alone.
static func refresh_libraries() -> Dictionary:
	return switch(_active, _package, false)


## Drops every palette-derived cache that keys on the active library.
static func reset_caches() -> void:
	PaletteLibrary.clear_cache()
	WindFoliage.reset_caches()


## What `doc` holds that the active library cannot resolve: {"missing_ids" (scatter asset ids
## the palette lacks), "missing_rows" (their rows), "props_missing" (hand-placed asset ids the
## palette lacks)}. Pure reads.
static func analyse(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
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


## Regenerates `doc.scatter` (and its mass anchors) from the biome painting under the active
## library when any scatter row names an asset the palette lacks; otherwise leaves the document
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
		func() -> void: _run_all(regen, snapshot, out),
		false,
		"FoliageLibrary regenerate scatter"
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
		"Foliage: %s scatter rebuilt from the biome painting (%d plants; the saved rows named %d"
		+ " assets this library lacks)."
	) % [current(), report["rows"], (report["missing_ids"] as PackedStringArray).size()]
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


static func _read(key: String, fallback: Variant) -> Variant:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("FoliageLibrary: failed to load settings (err=%d), using defaults" % err)
	return config.get_value(SECTION, key, fallback)
