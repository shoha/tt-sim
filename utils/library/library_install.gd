class_name LibraryInstall
extends RefCounted

## The second half of an import (LibraryImporter is the first): describing a staged folder for the
## install card, moving it into place, and removing a library again. No scene tree, no UI.
##
##   examine(folder)   read the staged folder with LibraryReader, compile it in a dry run through
##                     the libraries installed, and describe it for the install card: what it is,
##                     what it needs, what it would replace, why it is refused;
##   install(card)     move the staged folder to `<libraries>/<id>/` (replacing a library of the
##                     same id when asked, the old one set aside until the new one is in);
##   remove(id)        delete a library the user installed (never an official one);
##   levels_using(id)  the saved maps whose manifest names a library (a lazy scan).

## Install card relations to an installed library of the same id.
const RELATION_NEW := "new"
const RELATION_SAME := "same"
const RELATION_NEWER := "newer"
const RELATION_OLDER := "older"
## Dependency states on the card.
const DEP_OK := "ok"
const DEP_MISSING := "missing"
const DEP_UNMET := "unmet"
const DEP_DISABLED := "disabled"
const DEP_BROKEN := "broken"
const CARD_TEXT_FIELDS: Array[String] = [
	"name", "description", "author", "license", "url", "version"
]
const RESERVED_ID := "The id '%s' belongs to the game and cannot be installed."
const RESERVED_HINT := " Ask the author for an id of its own."


## The install card of the staged folder `folder`: reads it (LibraryReader), compiles it in a dry
## run against the libraries installed, and compares it with the installed library of its id.
## {can_install, errors, warnings, folder, id, name, description, author, license, url, version,
## bytes, file_count, asset_count, biome_count, biomes ([{id, name}]), dependencies
## ([{id, version, state, installed}]), relation, existing ({} or the installed list() entry),
## reserved (the id is not the user's to use), thumbnail (a staged file or "")}. Reads the
## registry's state, so call it on the main thread.
static func examine(folder: String) -> Dictionary:
	LibraryRegistry.refresh()
	var card := _empty_card(folder)
	var errors: Array = card["errors"]
	var warnings: Array = card["warnings"]
	var sources := LibraryRegistry.read_sources(folder)
	if sources.has("error"):
		errors.append(String(sources["error"]))
		return card
	var read := LibraryReader.read(sources)
	errors.append_array(read["errors"])
	warnings.append_array(read["warnings"])
	var library: Dictionary = read["library"]
	for field in CARD_TEXT_FIELDS:
		if library.get(field) is String:
			card[field] = String(library[field])
	var files: Array = sources["files"]
	card["file_count"] = files.size()
	card["bytes"] = _folder_bytes(folder, files)
	card["asset_count"] = (read.get("catalog_order", []) as Array).size()
	for item: Dictionary in read["biomes"]:
		var def: Dictionary = item["def"]
		var biome := {"id": String(def["id"]), "name": String(def.get("name", def["id"]))}
		(card["biomes"] as Array).append(biome)
	card["biome_count"] = (card["biomes"] as Array).size()
	card["id"] = String(library.get("id", ""))
	_check_identity(card)
	card["dependencies"] = dependency_states(library)
	for dep: Dictionary in card["dependencies"]:
		if dep["state"] != DEP_OK:
			warnings.append(dependency_line(dep))
	var cover: Variant = library.get("thumbnail")
	if cover is String and LibraryIds.path_problems(cover).is_empty():
		var staged_cover := folder.path_join(cover)
		if FileAccess.file_exists(staged_cover):
			card["thumbnail"] = staged_cover
	if bool(read["ok"]):
		_dry_run(card, read, sources, folder)
	var soft := LibraryImporter.limit_of("library_soft_bytes")
	if int(card["bytes"]) > soft:
		var big := "This is a large %s (%s)."
		warnings.append(big % [LibraryNames.lower(), LibraryImporter.size_text(int(card["bytes"]))])
	card["can_install"] = errors.is_empty()
	return card


static func _empty_card(folder: String) -> Dictionary:
	return {
		"can_install": false,
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"folder": folder,
		"id": "",
		"name": "",
		"description": "",
		"author": "",
		"license": "",
		"url": "",
		"version": "",
		"bytes": 0,
		"file_count": 0,
		"asset_count": 0,
		"biome_count": 0,
		"biomes": [] as Array[Dictionary],
		"dependencies": [] as Array[Dictionary],
		"relation": RELATION_NEW,
		"existing": {},
		"reserved": false,
		"thumbnail": "",
	}


static func _check_identity(card: Dictionary) -> void:
	var id := String(card["id"])
	var errors: Array = card["errors"]
	if id == "":
		return
	var reserved: Array[String] = [LibraryContracts.CORE_ID]
	reserved.append_array(LibraryContracts.RESERVED_LIBRARY_IDS)
	if id in reserved:
		card["reserved"] = true
		errors.append((RESERVED_ID % id) + RESERVED_HINT)
		return
	var existing := LibraryRegistry.info(id)
	card["existing"] = existing
	if existing.is_empty():
		return
	if bool(existing.get("official", false)) or String(existing["source"]) == "builtin":
		card["reserved"] = true
		errors.append("'%s' comes with the game and cannot be replaced." % id)
		return
	if String(existing["source"]) == "dev":
		(card["warnings"] as Array).append("A developer copy of '%s' is set for this run." % id)
	var order := LibraryVersions.compare(String(card["version"]), String(existing["version"]))
	if order > 0:
		card["relation"] = RELATION_NEWER
	elif order < 0:
		card["relation"] = RELATION_OLDER
	else:
		card["relation"] = RELATION_SAME


## Compiles the staged library alone, through the dependencies installed, adding what it says
## to the card (no palette or registry state changes).
static func _dry_run(
	card: Dictionary, read: Dictionary, sources: Dictionary, folder: String
) -> void:
	var options := {
		"folder": folder,
		"surfaces": PaletteLibrary.get_palette()["surfaces"],
		"hash": "",
		"files": sources["files"],
		"dependencies": _dependency_context(read["library"]),
	}
	var compiled := BiomeCompiler.compile(read, options)
	(card["warnings"] as Array).append_array(compiled["warnings"])
	for line: String in compiled["palette_warnings"]:
		(card["warnings"] as Array).append("palette: " + line)
	if (compiled["biome_ids"] as Array).is_empty():
		(card["errors"] as Array).append("No biome of this %s compiles." % LibraryNames.lower())


## {dependency id: {read, folder}} for the dependencies `library` declares that are installed.
static func _dependency_context(library: Dictionary) -> Dictionary:
	var out := {}
	for dep: Dictionary in _declared(library):
		var need := String(dep.get("id", ""))
		var info := LibraryRegistry.info(need)
		if info.is_empty() or String(info["status"]) != LibraryResolver.OK:
			continue
		if String(info["source"]) == "builtin":
			out[need] = {"read": {"library": {}, "catalog": {}}, "folder": ""}
			continue
		var folder := String(info["folder"])
		var read := LibraryReader.read(LibraryRegistry.read_sources(folder))
		out[need] = {"read": read, "folder": folder}
	return out


static func _declared(library: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var deps: Variant = library.get("dependencies", [])
	if deps is Array:
		for dep: Variant in deps as Array:
			if dep is Dictionary:
				out.append(dep)
	return out


## One entry per dependency `library` declares: {id, version (the range), state, installed (the
## installed version or "")}, state one of DEP_OK, DEP_MISSING, DEP_UNMET (installed at a version
## outside the range), DEP_DISABLED, DEP_BROKEN (installed but failing). Reads the registry.
static func dependency_states(library: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dep in _declared(library):
		var need := String(dep.get("id", ""))
		var range_text := String(dep.get("version", "*"))
		var info := LibraryRegistry.info(need)
		var state := DEP_OK
		var installed := ""
		if info.is_empty():
			state = DEP_MISSING
		else:
			installed = String(info["version"])
			if not LibraryVersions.satisfies(installed, range_text):
				state = DEP_UNMET
			elif not bool(info["enabled"]):
				state = DEP_DISABLED
			elif String(info["status"]) != LibraryResolver.OK:
				state = DEP_BROKEN
		out.append({"id": need, "version": range_text, "state": state, "installed": installed})
	return out


## One dependency's problem in a sentence ("Needs core ^1.0, but 0.9.0 is installed.").
static func dependency_line(dep: Dictionary) -> String:
	var need := "%s %s" % [dep["id"], dep["version"]]
	match String(dep["state"]):
		DEP_MISSING:
			return "Needs %s, which is not installed." % need
		DEP_UNMET:
			return "Needs %s, but %s is installed." % [need, dep["installed"]]
		DEP_DISABLED:
			return "Needs %s, which is turned off." % need
		DEP_BROKEN:
			return "Needs %s, which has a problem of its own." % need
	return "Needs %s." % need


static func _folder_bytes(folder: String, files: Array) -> int:
	var total := 0
	for relative: Variant in files:
		total += LibraryImporter.file_length(folder.path_join(String(relative)))
	return total


# ---- installing and removing ----


## Moves the staged folder of `card` (examine's answer, can_install true) to
## `<libraries>/<id>/`. An installed library of that id is replaced only when `replace` is true
## (it is set aside in the quarantine until the new one is in place and put back if the move
## fails). {ok, error, folder, replaced}.
static func install(card: Dictionary, replace: bool = false) -> Dictionary:
	var out := {"ok": false, "error": "", "folder": "", "replaced": false}
	var id := String(card.get("id", ""))
	var staged := String(card.get("folder", ""))
	if not bool(card.get("can_install", false)) or not LibraryIds.library_problems(id).is_empty():
		out["error"] = "This %s cannot be installed." % LibraryNames.lower()
		return out
	if not LibraryImporter.is_quarantined(staged) or not DirAccess.dir_exists_absolute(staged):
		out["error"] = "The staged files are gone; import the %s again." % LibraryNames.lower()
		return out
	var root := LibraryRegistry.user_root
	if DirAccess.make_dir_recursive_absolute(root) != OK:
		out["error"] = "The %s folder cannot be created." % LibraryNames.lower(2)
		return out
	var target := root.path_join(id)
	var aside := ""
	if DirAccess.dir_exists_absolute(target):
		if not replace:
			out["error"] = "'%s' is already installed." % id
			return out
		aside = LibraryImporter.incoming_root().path_join(LibraryImporter.token() + "_old")
		if DirAccess.rename_absolute(target, aside) != OK:
			out["error"] = "The installed copy of '%s' is in use and could not be set aside." % id
			return out
		out["replaced"] = true
	if DirAccess.rename_absolute(staged, target) != OK:
		if aside != "":
			DirAccess.rename_absolute(aside, target)
		out["error"] = "The %s could not be moved into place." % LibraryNames.lower()
		out["replaced"] = false
		return out
	if aside != "":
		LibraryImporter.remove_tree(aside)
	out["ok"] = true
	out["folder"] = target
	return out


## Deletes the user library `library_id` ({ok, error}). Refuses anything that is not a folder
## named `library_id` directly under the user's libraries folder (an official or built-in one
## is never there).
static func remove(library_id: String) -> Dictionary:
	if not LibraryIds.library_problems(library_id).is_empty():
		return {"ok": false, "error": "'%s' is not a %s id." % [library_id, LibraryNames.lower()]}
	var reserved := library_id == LibraryContracts.CORE_ID
	if reserved or library_id in LibraryContracts.RESERVED_LIBRARY_IDS:
		return {
			"ok": false, "error": "'%s' belongs to the game and cannot be removed." % library_id
		}
	var folder := LibraryRegistry.user_root.path_join(library_id)
	if not DirAccess.dir_exists_absolute(folder):
		return {"ok": false, "error": "'%s' is not installed." % library_id}
	if not LibraryImporter.remove_tree(folder):
		return {"ok": false, "error": "Some files of '%s' could not be deleted." % library_id}
	# Its baked surface maps (SurfaceCache) go with it; nothing else prunes that cache.
	LibraryImporter.remove_tree(SurfaceCache.root.path_join(library_id))
	return {"ok": true, "error": ""}


## The folders under `levels_dir` of the saved maps whose manifest names library `library_id`,
## found by reading each map.ttmap's manifest only (MapDocumentIO.peek_libraries). Reads a
## directory listing and one small archive per level, so call it on demand, not every frame.
static func levels_using(library_id: String, levels_dir: String) -> Array[String]:
	var found: Array[String] = []
	if not DirAccess.dir_exists_absolute(levels_dir):
		return found
	var folders := Array(DirAccess.get_directories_at(levels_dir))
	folders.sort()
	for folder_name: String in folders:
		var map_file := levels_dir.path_join(folder_name).path_join("map.ttmap")
		if not FileAccess.file_exists(map_file):
			continue
		for entry in MapDocumentIO.peek_libraries(map_file):
			if String(entry.get("id", "")) == library_id:
				found.append(folder_name)
				break
	return found
