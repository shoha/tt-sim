class_name LibraryWriter
extends RefCounted

## Writes the files the biome designer changes (step S8a): a library's biome-def and lock file,
## and the new collection "Duplicate as new collection" makes. The one place besides the
## importer that creates library files; it never touches a GLB, a surface or a catalog of an
## existing library. Only a user library (Paths.LIBRARIES_DIR) and the developer-override folder
## are ever written; the caller checks `writable`, this class refuses an official folder anyway
## (a path under res://). Files are written beside their target as .tmp and renamed over it, so
## a failure leaves the previous file as it was.

const DEFAULT_VERSION := "0.1.0"
const SCHEMA_NOTE := "Written by the tt-sim biome designer."


## The text of a JSON file as the designer writes it: sorted keys, tab indent, whole floats as
## ints, a trailing newline.
static func json_text(data: Variant) -> String:
	return JSON.stringify(plain(data), "\t", true) + "\n"


## `value` with whole floats turned into ints, recursively (a JSON round trip makes every
## number a float, and a saved `35.0` would be noise in a diff).
static func plain(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value as Dictionary:
			out[key] = plain((value as Dictionary)[key])
		return out
	if value is Array:
		var items := []
		for item: Variant in value as Array:
			items.append(plain(item))
		return items
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e15:
		return int(value)
	return value


## Writes biomes/<biome_id>.json and, when `locks` is not empty, biomes/<biome_id>.lock.json
## (otherwise removes a lock file that was there). `locks`: {"<season>/<rule key>": {query,
## assets}}. Returns {ok, error}.
static func write_biome(
	folder: String, biome_id: String, def: Dictionary, locks: Dictionary
) -> Dictionary:
	var refusal := _refusal(folder)
	if refusal != "":
		return {"ok": false, "error": refusal}
	var biomes := folder.path_join("biomes")
	var made := DirAccess.make_dir_recursive_absolute(biomes)
	if made != OK and not DirAccess.dir_exists_absolute(biomes):
		return {"ok": false, "error": "cannot create %s (error %d)" % [biomes, made]}
	var problem := _write(biomes.path_join(biome_id + ".json"), json_text(def))
	if problem != "":
		return {"ok": false, "error": problem}
	var lock_path := biomes.path_join(biome_id + LibraryReader.LOCK_SUFFIX)
	if locks.is_empty():
		if FileAccess.file_exists(lock_path):
			DirAccess.remove_absolute(lock_path)
		return {"ok": true, "error": ""}
	var lock := {
		"format": LibraryContracts.FORMAT_LOCK,
		"format_version": LibraryContracts.FORMAT_VERSION,
		"biome": biome_id,
		"rules": locks,
	}
	problem = _write(lock_path, json_text(lock))
	return {"ok": problem == "", "error": problem}


## Creates the user library `new_id` under `root` that designs `biome_id` of the library
## described by `source` (BiomeDesignerModel's context) with the biome-def `def`: a library.json
## that depends on the source library, an empty catalog (the assets stay in the source library)
## and the biome-def with every `ref` and `pin` rewritten to `<source id>:<id>` and every surface
## of the source's own named `lib://<source id>/<name>`. Refuses an id that is not valid or a
## folder that exists. Returns {ok, error, folder}.
static func create_collection(
	root: String,
	new_id: String,
	new_name: String,
	source: Dictionary,
	biome_id: String,
	def: Dictionary
) -> Dictionary:
	var problems := LibraryIds.library_problems(new_id)
	if not problems.is_empty():
		return {"ok": false, "error": "id '%s': %s" % [new_id, problems[0]], "folder": ""}
	if new_id in LibraryContracts.RESERVED_LIBRARY_IDS or new_id == LibraryContracts.CORE_ID:
		return {"ok": false, "error": "'%s' is a reserved id" % new_id, "folder": ""}
	var folder := root.path_join(new_id)
	if DirAccess.dir_exists_absolute(folder):
		return {"ok": false, "error": "a library named '%s' already exists" % new_id, "folder": ""}
	var source_id := String(source["id"])
	var copy := rebase_biome(def, source_id, source.get("read", {}))
	var library := {
		"format": LibraryContracts.FORMAT_LIBRARY,
		"format_version": LibraryContracts.FORMAT_VERSION,
		"id": new_id,
		"name": new_name if new_name != "" else new_id,
		"description": "Biomes designed from %s. %s" % [source.get("name", source_id), SCHEMA_NOTE],
		"version": DEFAULT_VERSION,
		"contract": LibraryContracts.CONTRACT_VERSION,
		"dependencies":
		[{"id": source_id, "version": dependency_range(String(source.get("version", "")))}],
		"license": "CC0-1.0",
		"tags": ["designed"],
	}
	var catalog := {
		"format": LibraryContracts.FORMAT_CATALOG,
		"format_version": LibraryContracts.FORMAT_VERSION,
		"assets": [],
	}
	for dir in ["assets", "biomes"]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(dir))
	for item: Array in [
		["library.json", library],
		["assets/catalog.json", catalog],
		["biomes/%s.json" % biome_id, copy]
	]:
		var problem := _write(folder.path_join(String(item[0])), json_text(item[1]))
		if problem != "":
			return {"ok": false, "error": problem, "folder": folder}
	return {"ok": true, "error": "", "folder": folder}


## `def` as a biome of another library that depends on `source_id`: refs and pins prefixed
## `<source id>:`, surfaces the source defines itself named `lib://<source id>/<name>` (read:
## the source's LibraryReader result), `surfaces` set to "library" so the names resolve through
## the dependency. Filter clauses are kept: they search the dependencies' catalogs too.
static func rebase_biome(def: Dictionary, source_id: String, read: Dictionary) -> Dictionary:
	var out: Dictionary = def.duplicate(true)
	var own: Dictionary = read.get("surfaces", {})
	for rule: Dictionary in out.get("rules", []):
		var query: Dictionary = rule.get("query", {})
		for clause: Variant in query.get("match", []):
			if clause is Dictionary and (clause as Dictionary).get("ref") is String:
				(clause as Dictionary)["ref"] = _prefixed(String(clause["ref"]), source_id)
		if query.get("pin") is Array:
			var pins := []
			for pin: Variant in query["pin"] as Array:
				pins.append(_prefixed(String(pin), source_id))
			query["pin"] = pins
	var ground: Dictionary = out.get("ground", {})
	for field: String in ["surface", "cliff", "scree", "water_bed", "shore"]:
		if ground.get(field) is String and own.has(ground[field]):
			ground[field] = LibraryIds.surface_ref(source_id, String(ground[field]))
	if ground.get("paths") is Array:
		var paths := []
		for name: Variant in ground["paths"] as Array:
			paths.append(LibraryIds.surface_ref(source_id, String(name)) if own.has(name) else name)
		ground["paths"] = paths
	if ground.get("accents") is Array:
		for accent: Variant in ground["accents"] as Array:
			if accent is Dictionary and own.has((accent as Dictionary).get("surface")):
				accent["surface"] = LibraryIds.surface_ref(source_id, String(accent["surface"]))
	out["surfaces"] = LibraryReader.SURFACES_LIBRARY
	out.erase("thumbnail")
	return out


## The dependency range for a source library at `version`: "^major.minor", "*" when the
## version cannot be read.
static func dependency_range(version: String) -> String:
	var parts := version.split("-")[0].split(".")
	if parts.size() >= 2 and String(parts[0]).is_valid_int() and String(parts[1]).is_valid_int():
		return "^%s.%s" % [parts[0], parts[1]]
	return "*"


static func _prefixed(ref: String, source_id: String) -> String:
	return ref if ":" in ref else source_id + ":" + ref


static func _refusal(folder: String) -> String:
	if folder == "" or folder.begins_with("res://"):
		return "'%s' is not a folder the designer may write" % folder
	return ""


static func _write(path: String, text: String) -> String:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(text)
	file.close()
	var err := DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
		return "cannot replace %s (error %d)" % [path, err]
	return ""
