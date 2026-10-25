class_name LibraryRegistry
extends RefCounted

## Finds, reads and serves content libraries (design doc 3.2, module 5). It is the ONLY module
## that scans folders or reads library files: LibraryReader, BiomeCompiler, LibraryIds and
## LibraryContracts take text and dictionaries. This build serves one source, the developer
## override: a library folder given by settings.cfg `[library] dev_path` or set for one run by
## set_dev_override(). It is opt-in and off by default, so nothing changes without it.
##
## Serving a library means compiling it (BiomeCompiler) into palette biomes and assets and
## laying them over the palette behind PaletteLibrary.DEFAULT_ROOT with the same merge rule a
## plantgen package gets (PaletteOverlay.read_palette, PaletteLibrary.install_overlay): each
## compiled biome replaces the palette's biome of the same runtime id, with its assets, and a core
## biome keeps today's id (`savanna_summer_s1`), so a saved map and every scatter row still
## resolve. The GLBs are parsed through PaletteOverlay.parse_mesh, the path the plantgen
## package route uses.
## Nothing here raises: every failure comes back in the result's `error` and `errors`.
##
## FoliageLibrary.apply() calls apply() last, after the treecube or plantgen choice, so the
## library is a layer over whatever the foliage library serves; clear() drops the override.
## Map and model: docs/systems/library.md.

const SECTION := "library"
const KEY_DEV_PATH := "dev_path"
const LIBRARY_FILE := "library.json"
const CATALOG_FILE := "assets/catalog.json"
const BIOME_DIR := "biomes"
## A folder holding more files than this, or nested deeper, is refused before anything is read.
const MAX_FILES := 20000
const MAX_DEPTH := 8
const HASH_LENGTH := 8

## The settings file; tests point it elsewhere.
static var settings_path: String = Paths.SETTINGS_PATH
static var _dev_path: String = ""
## Library id -> the summary apply() recorded for the library now served.
static var _served: Dictionary = {}


## Sets the developer override for this run ("" clears it). Does not touch the palette: call
## apply() (or FoliageLibrary.apply) afterwards.
static func set_dev_override(folder: String) -> void:
	_dev_path = folder


static func dev_override() -> String:
	return _dev_path


static func has_override() -> bool:
	return _dev_path != ""


## The persisted dev path (settings.cfg `[library] dev_path`), "" when unset.
static func saved_dev_path() -> String:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("LibraryRegistry: failed to load settings (err=%d), using defaults" % err)
	return String(config.get_value(SECTION, KEY_DEV_PATH, ""))


## Takes the persisted dev path as the override unless one was already set for this run.
static func use_saved_override() -> void:
	if _dev_path == "":
		_dev_path = saved_dev_path()


## The libraries served now: id -> {id, name, version, folder, biome_ids, assets, hash,
## warnings}. Copies.
static func served() -> Dictionary:
	return _served.duplicate(true)


## Drops the override and the record of what was served. The palette caches are the caller's to
## reset (FoliageLibrary.reset_caches): the overlay has no undo of its own.
static func clear() -> void:
	_dev_path = ""
	_served.clear()


## Reads the library at `folder` and compiles it: {ok, errors, warnings, read (LibraryReader's
## result), compiled (BiomeCompiler's, {} when the read failed), hash}. `surfaces` is the table
## the biomes' surface names resolve against; null takes the default palette's.
static func compile_folder(folder: String, surfaces: Variant = null) -> Dictionary:
	var sources := read_sources(folder)
	var out := {
		"ok": false,
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"read": {},
		"compiled": {},
		"hash": "",
	}
	if sources.has("error"):
		(out["errors"] as Array[String]).append(String(sources["error"]))
		return out
	var read := LibraryReader.read(sources)
	out["read"] = read
	out["hash"] = _hash_of(sources)
	(out["errors"] as Array[String]).append_array(read["errors"])
	(out["warnings"] as Array[String]).append_array(read["warnings"])
	if not read["ok"]:
		return out
	var table: Dictionary = (
		surfaces if surfaces is Dictionary else PaletteLibrary.get_palette()["surfaces"]
	)
	var compiled := BiomeCompiler.compile(
		read, {"folder": folder, "surfaces": table, "hash": out["hash"]}
	)
	out["compiled"] = compiled
	(out["warnings"] as Array[String]).append_array(compiled["warnings"])
	for warning: String in compiled["palette_warnings"]:
		(out["warnings"] as Array[String]).append("palette: " + warning)
	out["ok"] = not (compiled["biome_ids"] as Array).is_empty()
	if not out["ok"]:
		(out["errors"] as Array[String]).append("no biome of the library compiled")
	return out


## Lays the dev override library over the palette under `root`. Returns {ok, applied (false
## when there is no override), error, errors, warnings, library, biomes, report
## (PaletteOverlay.read_palette's)}. A failure changes no cache.
static func apply(root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var result := {
		"ok": true,
		"applied": false,
		"error": "",
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"library": "",
		"biomes": [] as Array[String],
		"report": {},
	}
	_served.clear()
	if _dev_path == "":
		return result
	result["ok"] = false
	var built := compile_folder(_dev_path, PaletteLibrary.get_palette(root)["surfaces"])
	result["errors"] = built["errors"]
	result["warnings"] = built["warnings"]
	if not built["ok"]:
		result["error"] = "library at '%s': %s" % [_dev_path, _first(built["errors"])]
		return result
	var compiled: Dictionary = built["compiled"]
	var report := PaletteLibrary.install_overlay(
		PaletteOverlay.read_palette(
			compiled["palette"], _dev_path, PaletteLibrary.get_palette(root), root
		),
		root
	)
	result["report"] = report
	if not report["ok"]:
		result["error"] = "library at '%s': %s" % [_dev_path, String(report["error"])]
		return result
	result["ok"] = true
	result["applied"] = true
	result["library"] = compiled["library"]
	result["biomes"] = compiled["biome_ids"]
	var library: Dictionary = built["read"]["library"]
	_served[compiled["library"]] = {
		"id": compiled["library"],
		"name": String(library.get("name", "")),
		"version": String(library.get("version", "")),
		"folder": _dev_path,
		"biome_ids": compiled["biome_ids"],
		"assets": (compiled["paths"] as Dictionary).size(),
		"hash": built["hash"],
		"warnings": built["warnings"],
	}
	return result


## apply() for the persisted override, at startup (FoliageLibrary.apply_saved); a failure warns.
static func apply_saved(root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	use_saved_override()
	var result := apply(root)
	if not result["ok"]:
		push_warning("LibraryRegistry: %s" % result["error"])
	return result


## The text of each library file under `folder`, in the form LibraryReader.read takes, or
## {"error": ...} when the folder is unusable. The one place that lists a library folder; listings
## are sorted, never trusted for precedence.
static func read_sources(folder: String) -> Dictionary:
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return {"error": "'%s' is not a folder" % folder}
	var files: Array[String] = []
	if not _list(folder, "", 0, files):
		return {
			"error":
			"'%s' holds more than %d files or nests deeper than %d" % [folder, MAX_FILES, MAX_DEPTH]
		}
	files.sort()
	var biomes := {}
	for relative in files:
		var in_biomes := relative.begins_with(BIOME_DIR + "/") and relative.count("/") == 1
		if in_biomes and relative.ends_with(".json") and not relative.ends_with(".lock.json"):
			biomes[relative.get_file()] = _text(
				folder.path_join(relative), LibraryContracts.CAPS["biome_bytes"]
			)
	return {
		"library":
		_text(folder.path_join(LIBRARY_FILE), LibraryContracts.CAPS["library_json_bytes"]),
		"catalog": _text(folder.path_join(CATALOG_FILE), LibraryContracts.CAPS["catalog_bytes"]),
		"biomes": biomes,
		"files": files,
	}


## Every file under `folder` as a sorted-later relative path; false when over the caps.
static func _list(folder: String, prefix: String, depth: int, out: Array[String]) -> bool:
	if depth > MAX_DEPTH:
		return false
	var here := folder if prefix == "" else folder.path_join(prefix)
	for file_name in DirAccess.get_files_at(here):
		out.append(file_name if prefix == "" else prefix + "/" + file_name)
		if out.size() > MAX_FILES:
			return false
	for sub in DirAccess.get_directories_at(here):
		if not _list(folder, sub if prefix == "" else prefix + "/" + sub, depth + 1, out):
			return false
	return true


## The file's text, "" when missing; a file over `cap` is read up to cap + 1 bytes so the reader's
## size check reports it.
static func _text(path: String, cap: int) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(mini(file.get_length(), cap + 1))
	file.close()
	return bytes.get_string_from_utf8()


## A short content hash of the library's JSON files (the identity a map will record).
static func _hash_of(sources: Dictionary) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for text: String in [String(sources.get("library", "")), String(sources.get("catalog", ""))]:
		_feed(hashing, text)
	var biomes: Dictionary = sources.get("biomes", {})
	var names: Array = biomes.keys()
	names.sort()
	for biome_name: String in names:
		_feed(hashing, String(biomes[biome_name]))
	return hashing.finish().hex_encode().substr(0, HASH_LENGTH)


## Adds `text` to the hash; an empty text adds nothing (HashingContext rejects empty input).
static func _feed(hashing: HashingContext, text: String) -> void:
	if text != "":
		hashing.update(text.to_utf8_buffer())


static func _first(items: Array) -> String:
	return String(items[0]) if not items.is_empty() else "unknown error"
