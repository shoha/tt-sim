class_name LibraryRegistry
extends RefCounted

## Finds, reads, resolves and serves content libraries (design doc 3.2, module 5). It is the ONLY
## module that scans folders or reads library files: LibraryReader, BiomeCompiler, LibraryIds,
## LibraryResolver and LibraryContracts take text and dictionaries.
##
## Sources, in load order (step S4):
## - `res://libraries/*/`: the OFFICIAL libraries that ship with the game. `official` is derived
##   from this location alone and never read from a library file.
## - `user://libraries/*/`: the libraries the user imported.
## - the DEVELOPER override: one folder from settings.cfg `[library] dev_path`, or set for a run
##   by set_dev_override(), laid over everything else and replacing biomes of the same runtime
##   id, as the override always did. Off by default.
## The folder name of an official or user library must equal its id. `core` is the game's own
## library: until it ships as `res://libraries/core` it is BUILT IN (the installed palette), so
## `dependencies: [{"id": "core", "version": "^1.0"}]` is met without a folder.
##
## Serving a library means compiling it (BiomeCompiler, through its dependencies) into palette
## biomes and assets and laying them over the palette behind PaletteLibrary.DEFAULT_ROOT with the
## overlay's merge rule (PaletteOverlay.read_palette, PaletteLibrary.install_overlay): a biome
## replaces the palette's biome of the same runtime id with its assets. A core biome keeps its id
## (`savanna_summer_s1`), any other library's is `<lib>__<biome>_<season>_s<seed>`. GLBs are NOT
## read here: the assets are registered with AssetStore, which parses each on first use.
## Which libraries can be served and in what order is LibraryResolver's decision (duplicates,
## dependencies and their version ranges, disabled libraries); a library that cannot be served is
## an entry with status "error" and reasons in list(), never a crash.
##
## Enabling: settings.cfg `[library] disabled` lists the ids the user turned off (all are enabled
## by default, `core` cannot be). set_enabled() persists; the change is served by the next
## apply() (FoliageLibrary.refresh_libraries() applies it and rebuilds the open map).
##
## A map names the libraries it uses (MapLibraries); record_of() gives the {id, version, hash}
## it stores and assets_used_by() the (library, asset ids) a map needs, which a later step uses
## to send only those over the network.
## FoliageLibrary.apply() calls apply() last, after the treecube or plantgen choice, so the
## libraries are a layer over whatever the foliage library serves. Map and model:
## docs/systems/library.md.

const SECTION := "library"
const KEY_DEV_PATH := "dev_path"
const KEY_DISABLED := "disabled"
const OFFICIAL_ROOT := "res://libraries"
const LIBRARY_FILE := "library.json"
const CATALOG_FILE := "assets/catalog.json"
const BIOME_DIR := "biomes"
const SURFACE_DIR := "surfaces"
## A folder holding more files than this, or nested deeper, is refused before anything is read.
const MAX_FILES := 20000
const MAX_DEPTH := 8
const HASH_LENGTH := 8
## The version the built-in core reports until `core` ships as a library folder.
const BUILTIN_VERSION := "1.0.0"

## The settings file; tests point it elsewhere.
static var settings_path: String = Paths.SETTINGS_PATH
## The folders scanned for official and user libraries; tests point them at scratch folders. The
## user root is the data root's own (Paths.LIBRARIES_DIR: `user://libraries/` in the shipped game,
## a disposable folder in a GUT run, so a test never sees the real user's libraries).
static var official_root: String = OFFICIAL_ROOT
static var user_root: String = Paths.LIBRARIES_DIR
static var _dev_path: String = ""
## Library id -> the summary apply() recorded for the library now served.
static var _served: Dictionary = {}
## The last scan: every folder found, annotated by LibraryResolver (status, reasons), with the
## read result and file list kept for compiling; and the indexes of the ones to serve, in order.
static var _entries: Array[Dictionary] = []
static var _order: Array[int] = []
static var _scanned: bool = false


# ---- the developer override ----


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
	return String(_setting(KEY_DEV_PATH, ""))


## Takes the persisted dev path as the override unless one was already set for this run.
static func use_saved_override() -> void:
	if _dev_path == "":
		_dev_path = saved_dev_path()


## True when there is something to serve beyond the installed palette: a developer override or
## a library folder under the official or user root. A cheap check (two directory listings) for
## startup, before anything is read.
static func discoverable() -> bool:
	return has_override() or not _library_folders(official_root).is_empty() or not (
		_library_folders(user_root).is_empty()
	)


# ---- enabling ----


## The ids the user turned off (settings.cfg `[library] disabled`).
static func disabled_ids() -> PackedStringArray:
	var raw: Variant = _setting(KEY_DISABLED, PackedStringArray())
	var out := PackedStringArray()
	if raw is PackedStringArray or raw is Array:
		for item: Variant in raw:
			if item is String:
				out.append(item)
	return out


static func is_enabled(library_id: String) -> bool:
	return library_id == LibraryContracts.CORE_ID or not library_id in disabled_ids()


## Turns library `library_id` on or off and persists it; false for `core` (it cannot be turned
## off) and for an id that is not a library id. Takes effect at the next apply().
static func set_enabled(library_id: String, enabled: bool) -> bool:
	if library_id == LibraryContracts.CORE_ID:
		return false
	if not LibraryIds.library_problems(library_id).is_empty():
		return false
	var disabled := disabled_ids()
	var at := disabled.find(library_id)
	if enabled and at >= 0:
		disabled.remove_at(at)
	elif not enabled and at < 0:
		disabled.append(library_id)
		disabled.sort()
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("LibraryRegistry: failed to load settings (err=%d), writing section only" % err)
	config.set_value(SECTION, KEY_DISABLED, disabled)
	return config.save(settings_path) == OK


# ---- state ----


## The libraries served now: id -> {id, name, version, folder, biome_ids, assets, hash, warnings,
## source, official, dependencies}. Copies. The built-in core is not in it (it is the palette).
static func served() -> Dictionary:
	return _served.duplicate(true)


## Drops the override and the record of what was served. The palette caches are the caller's to
## reset (FoliageLibrary.reset_caches): the overlay has no undo of its own.
static func clear() -> void:
	_dev_path = ""
	_served.clear()
	_entries.clear()
	_order.clear()
	_scanned = false
	AssetStore.clear()
	_forget_surfaces()


## Forgets the served libraries' surfaces and bindings: every name reads the legacy palette and
## the legacy defaults again.
static func _forget_surfaces() -> void:
	SurfaceStore.clear_libraries()
	LibraryBindings.clear()


# ---- scanning and listing ----


## Scans the official and user roots and the override, reads every library folder found and
## resolves them (LibraryResolver). Reads files; changes no palette. list() returns the result.
static func refresh(root: String = PaletteLibrary.DEFAULT_ROOT) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Array in [[official_root, "official"], [user_root, "user"]]:
		for folder in _library_folders(String(item[0])):
			found.append(_entry_of(folder, String(item[1])))
	if _dev_path != "":
		found.append(_entry_of(_dev_path, "dev"))
	var disabled := disabled_ids()
	for entry in found:
		entry["enabled"] = entry["source"] == "dev" or not String(entry["id"]) in disabled
	var resolved := LibraryResolver.resolve(found, _builtin(root))
	_entries.assign(resolved["entries"])
	_order.assign(resolved["order"])
	_scanned = true
	return list(root)


## What the library manager shows: one dictionary per library, the built-in core first (when no
## folder provides `core`), then every folder found in load order, the unusable ones last:
## {id, name, description, version, author, license, url, tags, source ("builtin", "official",
## "user" or "dev"), official, enabled, status ("ok", "error" or "disabled"), reasons, warnings,
## folder, hash, bytes (on disk), asset_count, biome_count, biomes ([{id, name}] local ids),
## biome_ids (runtime ids), default_biome (a runtime id), dependencies, provides, served,
## thumbnail (absolute file or "")}. Scans on first use. Copies.
static func list(root: String = PaletteLibrary.DEFAULT_ROOT) -> Array[Dictionary]:
	if not _scanned:
		refresh(root)
	var out: Array[Dictionary] = []
	var has_core := false
	for entry in _entries:
		if entry["id"] == LibraryContracts.CORE_ID and entry["status"] == LibraryResolver.OK:
			has_core = true
	if not has_core:
		out.append(_builtin_info(root))
	var ranked: Array[int] = []
	ranked.assign(_order)
	for i in _entries.size():
		if not i in ranked:
			ranked.append(i)
	for i in ranked:
		out.append(_public(_entries[i]))
	return out


## list() entry of library `library_id`, {} when none. A served library wins over a failed one.
static func info(library_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var fallback := {}
	for item in list(root):
		if item["id"] == library_id:
			if item["status"] == LibraryResolver.OK:
				return item
			if fallback.is_empty():
				fallback = item
	return fallback


## {id, version, hash} a map stores for library `library_id` while it is served (the built-in
## core counts), {} when it is not.
static func record_of(library_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	if _served.has(library_id):
		var found: Dictionary = _served[library_id]
		return {"id": library_id, "version": found["version"], "hash": found["hash"]}
	if library_id == LibraryContracts.CORE_ID:
		var core := _builtin_info(root)
		return {"id": library_id, "version": core["version"], "hash": core["hash"]}
	return {}


## The (library, asset ids) a map needs: {library id: PackedStringArray of palette asset ids},
## from the keys of its scatter rows and hand-placed props. A library is named by the id's
## prefix (LibraryIds.library_of), so it works whether or not the library is installed; a later
## step sends exactly these over the network. Pure of registry state.
static func assets_used_by(doc: MapDocument) -> Dictionary:
	var by_library := {}
	for source: Dictionary in [doc.scatter, doc.props]:
		for asset_id: String in source:
			var library := LibraryIds.library_of(asset_id)
			var held: PackedStringArray = by_library.get(library, PackedStringArray())
			if not asset_id in held:
				held.append(asset_id)
			by_library[library] = held
	for library: String in by_library:
		var sorted: PackedStringArray = by_library[library]
		sorted.sort()
		by_library[library] = sorted
	return by_library


## `asset_id` after the owning library's `aliases` ({old id: new id}, a renamed biome or asset),
## when the palette does not hold `asset_id` itself; the id unchanged when the library is not
## served, has no alias for it, or the renamed asset is not in the palette either.
static func resolve_asset_alias(
	asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> String:
	var assets: Dictionary = PaletteLibrary.get_palette(root)["assets"]
	if not "/" in asset_id or assets.has(asset_id):
		return asset_id
	var aliases := _aliases_of(LibraryIds.library_of(asset_id))
	if aliases.is_empty():
		return asset_id
	var biome := resolve_biome_alias(asset_id.get_slice("/", 0), root)
	var renamed := LibraryIds.runtime_asset(
		biome, LibraryIds.resolve_alias(aliases, asset_id.get_slice("/", 1))
	)
	return renamed if assets.has(renamed) else asset_id


## The runtime biome id `biome_id` after its library's `aliases` (a renamed biome keeps its
## season and seed), when the palette has no biome of that id; unchanged otherwise.
static func resolve_biome_alias(
	biome_id: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> String:
	var parsed := LibraryIds.parse_runtime_biome(biome_id)
	if parsed.is_empty() or PaletteLibrary.biome(biome_id, root) != {}:
		return biome_id
	var aliases := _aliases_of(String(parsed["library"]))
	var renamed := LibraryIds.resolve_alias(aliases, String(parsed["biome"]))
	if renamed == parsed["biome"]:
		return biome_id
	var now := LibraryIds.runtime_biome(
		String(parsed["library"]), renamed, String(parsed["season"]), int(parsed["seed"])
	)
	return now if PaletteLibrary.biome(now, root) != {} else biome_id


static func _aliases_of(library_id: String) -> Dictionary:
	for entry in _entries:
		if entry["id"] == library_id and entry["status"] == LibraryResolver.OK:
			var raw: Variant = (entry["read"]["library"] as Dictionary).get("aliases")
			if raw is Dictionary:
				var out := {}
				for old: Variant in raw as Dictionary:
					if (raw as Dictionary)[old] is String:
						out[String(old)] = (raw as Dictionary)[old]
				return out
	return {}


static func _builtin(root: String) -> Dictionary:
	return {"id": LibraryContracts.CORE_ID, "version": BUILTIN_VERSION, "root": root}


## The list() entry of the game's own core library: the installed palette's core biomes.
static func _builtin_info(root: String) -> Dictionary:
	var palette := PaletteLibrary.get_palette(root)
	var biome_ids: Array[String] = []
	var names: Array[Dictionary] = []
	var served_elsewhere := {}
	for found: Dictionary in _served.values():
		if found["id"] != LibraryContracts.CORE_ID:
			for id: String in found["biome_ids"]:
				served_elsewhere[id] = true
	for biome: Dictionary in palette["biomes"]:
		var id := String(biome["id"])
		if LibraryIds.library_of(id) == LibraryContracts.CORE_ID and not served_elsewhere.has(id):
			biome_ids.append(id)
			names.append({"id": id, "name": String(biome["name"])})
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(String(palette["palette_version"]).to_utf8_buffer() + PackedByteArray([0]))
	return {
		"id": LibraryContracts.CORE_ID,
		"name": "tt-sim Core",
		"description": "The plants and ground that come with the game.",
		"version": BUILTIN_VERSION,
		"author": "tt-sim",
		"license": "",
		"url": "",
		"tags": ["official"],
		"source": "builtin",
		"official": true,
		"enabled": true,
		"status": LibraryResolver.OK,
		"reasons": [] as Array[String],
		"warnings": [] as Array[String],
		"folder": root,
		"hash": hashing.finish().hex_encode().substr(0, HASH_LENGTH),
		"bytes": 0,
		"asset_count": (palette["assets"] as Dictionary).size(),
		"biome_count": names.size(),
		"biomes": names,
		"biome_ids": biome_ids,
		"default_biome": LibraryBindings.default_biome(),
		"dependencies": [] as Array[Dictionary],
		"provides": {},
		"served": true,
		"thumbnail": "",
	}


## The public dictionary of one scanned entry (no read result, no file list).
static func _public(entry: Dictionary) -> Dictionary:
	var read: Dictionary = entry["read"]
	var biomes: Array[Dictionary] = []
	var runtime_ids: Array[String] = []
	var default_runtime := ""
	var library: Dictionary = read.get("library", {})
	var wanted := String(library.get("default_biome", ""))
	for item: Dictionary in read.get("biomes", []):
		var def: Dictionary = item["def"]
		biomes.append({"id": String(def["id"]), "name": String(def.get("name", def["id"]))})
		var seasons: Array = def.get("seasons", [{"id": "summer", "seed": 1}])
		var first_of_biome := ""
		for season: Dictionary in seasons:
			var runtime := LibraryIds.runtime_biome(
				String(entry["id"]),
				String(def["id"]),
				String(season.get("id", "summer")),
				int(season.get("seed", 1))
			)
			runtime_ids.append(runtime)
			if first_of_biome == "":
				first_of_biome = runtime
			# default_biome is a local biome id, or a runtime id (what the first export wrote).
			if default_runtime == "" and wanted != "" and (runtime == wanted or def["id"] == wanted):
				default_runtime = first_of_biome
		if default_runtime == "" and wanted == "":
			default_runtime = first_of_biome
	if default_runtime == "" and not runtime_ids.is_empty():
		default_runtime = runtime_ids[0]
	var served_info: Dictionary = _served.get(entry["id"], {})
	if not served_info.is_empty() and served_info.get("folder") == entry["folder"]:
		runtime_ids.assign(served_info["biome_ids"])
	var thumbnail := ""
	var cover: Variant = library.get("thumbnail")
	if cover is String and LibraryIds.path_problems(cover).is_empty():
		thumbnail = String(entry["folder"]).path_join(cover)
	return {
		"id": entry["id"],
		"name": entry["name"],
		"description": entry["description"],
		"version": entry["version"],
		"author": entry["author"],
		"license": entry["license"],
		"url": entry["url"],
		"tags": entry["tags"],
		"source": entry["source"],
		"official": entry["official"],
		"enabled": entry["enabled"],
		"status": entry["status"],
		"reasons": (entry["reasons"] as Array).duplicate(),
		"warnings": (entry["warnings"] as Array).duplicate(),
		"folder": entry["folder"],
		"hash": entry["hash"],
		"bytes": entry["bytes"],
		"asset_count": (read.get("catalog_order", []) as Array).size(),
		"biome_count": biomes.size(),
		"biomes": biomes,
		"biome_ids": runtime_ids,
		"default_biome": default_runtime,
		"dependencies": (entry["dependencies"] as Array).duplicate(true),
		"provides": (entry["provides"] as Dictionary).duplicate(),
		"served": not served_info.is_empty() and served_info.get("folder") == entry["folder"],
		"thumbnail": thumbnail,
	}


## The subfolders of `root` that may hold a library (names not starting with a dot, which is how
## a quarantine folder for an import in progress is kept out), full paths, sorted.
static func _library_folders(root: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	var names := Array(DirAccess.get_directories_at(root))
	names.sort()
	for folder_name: String in names:
		if not folder_name.begins_with("."):
			out.append(root.path_join(folder_name))
	return out


## One scanned entry for the library folder `folder` found under `source` ("official", "user"
## or "dev"): read and checked, not yet resolved.
static func _entry_of(folder: String, source: String) -> Dictionary:
	var entry := {
		"folder": folder,
		"source": source,
		"official": source == "official",
		"id": folder.get_file(),
		"name": folder.get_file(),
		"description": "",
		"version": "",
		"author": "",
		"license": "",
		"url": "",
		"tags": [] as Array,
		"read_ok": false,
		"reasons": [] as Array,
		"warnings": [] as Array,
		"read": {},
		"hash": "",
		"files": [] as Array,
		"bytes": 0,
		"dependencies": [] as Array,
	}
	var sources := read_sources(folder)
	if sources.has("error"):
		(entry["reasons"] as Array).append(String(sources["error"]))
		return entry
	var read := LibraryReader.read(sources)
	var library: Dictionary = read["library"]
	entry["read"] = read
	entry["hash"] = _hash_of(sources)
	entry["files"] = sources["files"]
	(entry["reasons"] as Array).append_array(read["errors"])
	(entry["warnings"] as Array).append_array(read["warnings"])
	if library.get("id") is String and String(library["id"]) != "":
		entry["id"] = String(library["id"])
	for field in ["name", "description", "version", "author", "license", "url"]:
		if library.get(field) is String:
			entry[field] = String(library[field])
	if library.get("tags") is Array:
		for tag: Variant in library["tags"] as Array:
			if tag is String:
				(entry["tags"] as Array).append(tag)
	var deps: Variant = library.get("dependencies", [])
	if read["ok"] and deps is Array:
		for dep: Variant in deps as Array:
			if dep is Dictionary:
				(entry["dependencies"] as Array).append(
					{"id": String(dep.get("id", "")), "version": String(dep.get("version", "*"))}
				)
	entry["read_ok"] = read["ok"]
	if source != "dev" and read["ok"] and folder.get_file() != String(entry["id"]):
		entry["read_ok"] = false
		(entry["reasons"] as Array).append(
			"folder '%s' must be named after the library id '%s'" % [folder.get_file(), entry["id"]]
		)
	entry["bytes"] = _size_of(folder, sources["files"])
	return entry


## The total size on disk of `files` (library-relative) under `folder`.
static func _size_of(folder: String, files: Array) -> int:
	var total := 0
	for relative: Variant in files:
		var file := FileAccess.open(folder.path_join(String(relative)), FileAccess.READ)
		if file != null:
			total += file.get_length()
			file.close()
	return total


# ---- compiling one folder (the CLI, tests) ----


## Reads the library at `folder` and compiles it alone: {ok, errors, warnings, read
## (LibraryReader's result), compiled (BiomeCompiler's, {} when the read failed), hash}.
## `surfaces` is the table the biomes' surface names resolve against; null takes the default
## palette's. Dependencies are not resolved here (a `<lib>:<id>` ref warns); apply() does.
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
		read, {"folder": folder, "surfaces": table, "hash": out["hash"], "files": sources["files"]}
	)
	out["compiled"] = compiled
	(out["warnings"] as Array[String]).append_array(compiled["warnings"])
	for warning: String in compiled["palette_warnings"]:
		(out["warnings"] as Array[String]).append("palette: " + warning)
	out["ok"] = not (compiled["biome_ids"] as Array).is_empty()
	if not out["ok"]:
		(out["errors"] as Array[String]).append("no biome of the library compiled")
	return out


# ---- serving ----


## Scans the roots and lays every library that can be served over the palette under `root`, in
## load order (dependencies first). Returns {ok, applied (a library was laid), error (the
## developer override's problem, "" otherwise), errors (every library problem, one line each),
## warnings, library (the id laid last), libraries (every id laid), biomes (their runtime ids),
## report (the last overlay report)}. `ok` is false only when the developer override cannot be
## served; a user library that fails is an entry with status "error" in list() and a line in
## `errors`, and the others are served. Nothing changes for a library that fails.
static func apply(root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var result := {
		"ok": true,
		"applied": false,
		"error": "",
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"library": "",
		"libraries": [] as Array[String],
		"biomes": [] as Array[String],
		"report": {},
	}
	_served.clear()
	_forget_surfaces()
	AssetStore.clear()
	refresh(root)
	if _entries.is_empty():
		return result
	var official_of := {LibraryContracts.CORE_ID: true}
	for entry in _entries:
		official_of[entry["id"]] = entry["official"]
	var failed: Dictionary = {}
	for i in _order:
		var entry := _entries[i]
		var made := _serve(entry, root, official_of)
		(result["warnings"] as Array[String]).append_array(made["warnings"])
		if not made["ok"]:
			failed[i] = made["error"]
			continue
		result["applied"] = true
		result["library"] = entry["id"]
		(result["libraries"] as Array[String]).append(String(entry["id"]))
		(result["biomes"] as Array[String]).append_array(made["biome_ids"])
		result["report"] = made["report"]
	for i in failed:
		_entries[i]["status"] = LibraryResolver.ERROR
		(_entries[i]["reasons"] as Array).append(String(failed[i]))
	for entry in _entries:
		if entry["status"] == LibraryResolver.ERROR:
			for reason: String in entry["reasons"]:
				(result["errors"] as Array[String]).append("library %s: %s" % [entry["id"], reason])
		if entry["source"] == "dev" and entry["status"] != LibraryResolver.OK:
			result["ok"] = false
			result["error"] = (
				"library at '%s': %s" % [entry["folder"], _first(entry["reasons"] as Array)]
			)
	return result


## Compiles one resolved entry (through the dependencies it declared) and lays it over the
## palette; {ok, error, warnings, biome_ids, report}. A failure changes no cache.
static func _serve(entry: Dictionary, root: String, official_of: Dictionary) -> Dictionary:
	var out := {"ok": false, "error": "", "warnings": [], "biome_ids": [], "report": {}}
	var read: Dictionary = entry["read"]
	var folder := String(entry["folder"])
	var compiled := BiomeCompiler.compile(
		read,
		{
			"folder": folder,
			"surfaces": PaletteLibrary.get_palette(root)["surfaces"],
			"hash": entry["hash"],
			"files": entry["files"],
			"dependencies": _dependency_context(entry),
		}
	)
	out["warnings"] = (compiled["warnings"] as Array).duplicate()
	for warning: String in compiled["palette_warnings"]:
		(out["warnings"] as Array).append("palette: " + warning)
	(entry["warnings"] as Array).append_array(out["warnings"])
	if (compiled["biome_ids"] as Array).is_empty():
		out["error"] = "no biome of the library compiled"
		return out
	var report := PaletteLibrary.install_overlay(
		PaletteOverlay.read_palette(
			compiled["palette"], folder, PaletteLibrary.get_palette(root), root, [], true
		),
		root
	)
	out["report"] = report
	if not report["ok"]:
		out["error"] = String(report["error"])
		return out
	AssetStore.register_library(root, compiled["origins"], entry["official"], official_of)
	_serve_surfaces(root, entry, compiled)
	var library: Dictionary = read["library"]
	_served[entry["id"]] = {
		"id": entry["id"],
		"name": entry["name"],
		"version": entry["version"],
		"folder": folder,
		"biome_ids": compiled["biome_ids"],
		"assets": (compiled["origins"] as Dictionary).size(),
		"hash": entry["hash"],
		"warnings": (entry["warnings"] as Array).duplicate(),
		"source": entry["source"],
		"official": entry["official"],
		"dependencies": (entry["dependencies"] as Array).duplicate(true),
		"default_biome": String(library.get("default_biome", "")),
	}
	out["ok"] = true
	out["biome_ids"] = compiled["biome_ids"]
	return out


## {dependency id: {read, folder}} for the dependencies entry declared and a folder provides.
static func _dependency_context(entry: Dictionary) -> Dictionary:
	var out := {}
	for dep: Dictionary in entry["dependencies"]:
		var need := String(dep["id"])
		var provider := _provider_entry(need, entry)
		if provider.is_empty():
			# The built-in core: no catalog to resolve refs against until it ships as a folder.
			if need == LibraryContracts.CORE_ID:
				out[need] = {"read": {"library": {}, "catalog": {}}, "folder": ""}
			continue
		out[need] = {"read": provider["read"], "folder": provider["folder"]}
	return out


## The scanned entry that provides library `need` to `entry` (an ok one, preferring a folder
## that is not the developer override), {} when none.
static func _provider_entry(need: String, entry: Dictionary) -> Dictionary:
	var found := {}
	for other in _entries:
		if other["id"] != need or other["status"] != LibraryResolver.OK or other == entry:
			continue
		if found.is_empty() or other["source"] != "dev":
			found = other
	return found


## Hands the compiled library's own surfaces and thumbnails to SurfaceStore and, for core and the
## developer override, its bindings to LibraryBindings (runtime names), once its palette is
## installed. A library of the user's own does not rebind what the game's code names.
static func _serve_surfaces(root: String, entry: Dictionary, compiled: Dictionary) -> void:
	var library_id := String(compiled["library"])
	SurfaceStore.register_library(root, String(entry["folder"]), compiled["surfaces"])
	SurfaceStore.register_thumbnails(root, compiled["thumbnails"])
	if library_id != LibraryContracts.CORE_ID and entry["source"] != "dev":
		return
	var read: Dictionary = entry["read"]
	var library: Dictionary = read["library"]
	var flat: Dictionary = (
		LibraryBindings.flatten(library.get("bindings"), library.get("default_biome"))["values"]
	)
	LibraryBindings.set_served(
		library_id,
		LibraryBindings.to_runtime(
			library_id, flat, read["surface_order"], compiled["palette"]["biomes"]
		)
	)


## apply() for the persisted override, at startup (FoliageLibrary.apply_saved); a failure warns.
static func apply_saved(root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	use_saved_override()
	var result := apply(root)
	if not result["ok"]:
		push_warning("LibraryRegistry: %s" % result["error"])
	return result


# ---- reading a folder ----


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
	var surfaces := {}
	var png := {}
	for relative in files:
		var parts := relative.split("/")
		if parts.size() != 3 or parts[0] != SURFACE_DIR:
			continue
		if parts[2] == SurfaceReader.INFO_FILE:
			surfaces[parts[1]] = _text(folder.path_join(relative), SurfaceBake.MAX_INFO_BYTES)
		elif relative.get_extension().to_lower() == "png":
			png[relative] = SurfaceStore.png_header_of(folder.path_join(relative))
	return {
		"library":
		_text(folder.path_join(LIBRARY_FILE), LibraryContracts.CAPS["library_json_bytes"]),
		"catalog": _text(folder.path_join(CATALOG_FILE), LibraryContracts.CAPS["catalog_bytes"]),
		"biomes": biomes,
		"surfaces": surfaces,
		"png": png,
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


## A short content hash of the library's JSON files (the identity a map records).
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
	var surfaces: Dictionary = sources.get("surfaces", {})
	var surface_names: Array = surfaces.keys()
	surface_names.sort()
	for surface_name: String in surface_names:
		_feed(hashing, String(surfaces[surface_name]))
	return hashing.finish().hex_encode().substr(0, HASH_LENGTH)


## Adds `text` to the hash; an empty text adds nothing (HashingContext rejects empty input).
static func _feed(hashing: HashingContext, text: String) -> void:
	if text != "":
		hashing.update(text.to_utf8_buffer())


static func _setting(key: String, fallback: Variant) -> Variant:
	var config := ConfigFile.new()
	var err := config.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("LibraryRegistry: failed to load settings (err=%d), using defaults" % err)
	return config.get_value(SECTION, key, fallback)


static func _first(items: Array) -> String:
	return String(items[0]) if not items.is_empty() else "unknown error"
