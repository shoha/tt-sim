class_name LibraryHashes
extends RefCounted

## The file hashes and byte totals of a built library's library.json (`stats.file_sha256`,
## `stats.surface_bytes`, `stats.thumb_bytes`), recomputed from the files on disk. plantgen's
## exporter writes them (LibrarySurfaces.measure); a tile or picture regenerated afterwards in
## tt-sim (the structure thumbnails) changes a file's bytes without touching library.json, and
## plantgen's `--check-built` then fails. This is the same measure, in the host, for that case.
## Pure over a folder: measure() reads files, reconciled() and differences() take dictionaries.
## tools/recompute_library_hashes.gd is the command line.

## The folders whose files stats.file_sha256 lists, and the one whose bytes count as thumb_bytes
## (the asset thumbnails) rather than surface_bytes (surface sets and biome pictures).
const SURFACE_DIR := "surfaces"
const PICTURE_DIR := "thumbnails"
const ASSET_THUMB_DIR := "assets/thumbs"
const DIRS: Array[String] = [SURFACE_DIR, PICTURE_DIR, ASSET_THUMB_DIR]
## The engine's own import sidecars sit beside the files in a project's copy of a library; the
## exporter's folder has none, so they are neither hashed nor counted.
const SIDECAR_EXTENSION := "import"


## {"sha256": {relative path: sha256}, "surface_bytes": int, "thumb_bytes": int} for the files of
## the library folder `dir` (absolute or res://), sidecars left out.
static func measure(dir: String) -> Dictionary:
	var hashes := {}
	var surface_bytes := 0
	var thumb_bytes := 0
	for prefix: String in DIRS:
		for relative: String in _files(dir, prefix):
			var path := "%s/%s" % [dir, relative]
			hashes[relative] = FileAccess.get_sha256(path)
			var size := FileAccess.get_file_as_bytes(path).size()
			if prefix == ASSET_THUMB_DIR:
				thumb_bytes += size
			else:
				surface_bytes += size
	return {"sha256": hashes, "surface_bytes": surface_bytes, "thumb_bytes": thumb_bytes}


## `library` (the library.json dictionary) with its stats set to `measured` (measure()'s result):
## the hash list is replaced whole (a file no longer on disk drops out), the byte totals follow.
## A library without `stats.file_sha256` (a source library) is returned unchanged. A copy.
static func reconciled(library: Dictionary, measured: Dictionary) -> Dictionary:
	var out := library.duplicate(true)
	var stats: Variant = out.get("stats")
	if not stats is Dictionary or not (stats as Dictionary).get("file_sha256") is Dictionary:
		return out
	(stats as Dictionary)["file_sha256"] = (measured["sha256"] as Dictionary).duplicate()
	(stats as Dictionary)["surface_bytes"] = int(measured["surface_bytes"])
	(stats as Dictionary)["thumb_bytes"] = int(measured["thumb_bytes"])
	return out


## `value` (parsed JSON) with every whole-number float turned into an int, so a library.json that
## was read and written back keeps its integers (JSON.parse_string yields floats, and stringify
## would print 1 as 1.0). A copy.
static func whole_numbers_as_ints(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)) and absf(value) < 9.0e15:
		return int(value)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = whole_numbers_as_ints(value[key])
		return out
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(whole_numbers_as_ints(item))
		return items
	return value


## What differs between `library`'s stats and `measured`, one line each; empty when they agree
## (or the library has no hash list).
static func differences(library: Dictionary, measured: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var stats: Variant = library.get("stats")
	if not stats is Dictionary or not (stats as Dictionary).get("file_sha256") is Dictionary:
		return out
	var listed: Dictionary = (stats as Dictionary)["file_sha256"]
	var have: Dictionary = measured["sha256"]
	for relative: String in listed:
		if not have.has(relative):
			out.append("%s is listed but missing" % relative)
		elif have[relative] != listed[relative]:
			out.append("sha256 of %s differs" % relative)
	for relative: String in have:
		if not listed.has(relative):
			out.append("%s is not listed" % relative)
	for field: String in ["surface_bytes", "thumb_bytes"]:
		if int((stats as Dictionary).get(field, -1)) != int(measured[field]):
			out.append(
				(
					"stats.%s is %d, the files hold %d"
					% [field, int((stats as Dictionary).get(field, -1)), measured[field]]
				)
			)
	out.sort()
	return out


## Relative paths (under `dir`, forward slashes, sorted) of the files below `prefix`, sidecars out.
static func _files(dir: String, prefix: String) -> Array[String]:
	var out: Array[String] = []
	var here := "%s/%s" % [dir, prefix]
	if not DirAccess.dir_exists_absolute(here):
		return out
	for file_name in DirAccess.get_files_at(here):
		if file_name.get_extension() != SIDECAR_EXTENSION:
			out.append("%s/%s" % [prefix, file_name])
	for sub in DirAccess.get_directories_at(here):
		out.append_array(_files(dir, "%s/%s" % [prefix, sub]))
	out.sort()
	return out
