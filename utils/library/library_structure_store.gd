class_name LibraryStructureStore
extends RefCounted

## The structures the served libraries offer (the `structures/` kind, LibraryStructures), keyed by
## the reference a map stores: `<library id>:<structure id>`. LibraryRegistry fills it while it
## serves libraries (begin, register, publish) and everything else reads it: the palette rows
## (structures), one row (structure), the recipe document text and digest the builder needs
## (recipe: the shape StructureRecipes wants), and the references a map document uses
## (used_by). docs/systems/library.md "Structures".
##
## A worker builds structures (AuthoredStructures, AuthoredLoadPrep) while the main thread may
## re-serve libraries, so the table is only ever replaced whole: apply() builds a new one beside
## it and publish() swaps it in under a mutex; a reader gets the table it started with.

## ref -> {library, id, entry (the cleaned index entry), text (the recipe document), digest
## (sha256 of the text), folder}.
static var _mutex := Mutex.new()
static var _table: Dictionary = {}
static var _building: Dictionary = {}

# ---- reading a library folder (the registry's half) ----


## The "structures" part of LibraryReader's sources for `folder`: {"index": the text of
## structures/index.json, "recipes": {file name: text}}. `files` is the folder's file list,
## `read_text` a Callable (path, cap) -> String that reads one file. Line ends are made LF, so a
## CRLF checkout digests like a pack.
static func sources_of(folder: String, files: Array, read_text: Callable) -> Dictionary:
	var index := ""
	var recipes := {}
	for relative: String in files:
		if relative == LibraryStructures.INDEX_FILE:
			index = _normal(read_text.call(folder.path_join(relative), _cap("index_bytes")))
		elif (
			relative.begins_with(LibraryStructures.DIR)
			and relative.count("/") == 1
			and relative.ends_with(LibraryStructures.RECIPE_SUFFIX)
		):
			recipes[relative.get_file()] = _normal(
				read_text.call(folder.path_join(relative), _cap("recipe_bytes"))
			)
	return {"index": index, "recipes": recipes}


## {structure id: recipe text} of the structures the reader accepted (`read`'s "structures").
static func texts_of(sources: Dictionary, read: Dictionary) -> Dictionary:
	var recipes: Dictionary = (sources["structures"] as Dictionary)["recipes"]
	var texts := {}
	for item: Dictionary in read["structures"]:
		texts[String(item["id"])] = String(recipes.get(String(item["file"]).get_file(), ""))
	return texts


# ---- filling it (the registry's apply) ----


## Whether a library whose reader result is `read` offers buildings and no biome-def at all: the
## registry serves it as a pool (it lays nothing on the palette).
static func buildings_only(read: Dictionary) -> bool:
	return (
		(read["biomes"] as Array).is_empty()
		and not (read.get("structures", []) as Array).is_empty()
	)


## Empties the table (the registry forgot every library).
static func clear() -> void:
	begin()
	publish()


## Starts the table the next publish() makes current.
static func begin() -> void:
	_building = {}


## Adds the structures of the scanned `entry` (a resolved, readable library: its "read" and
## "structure_texts") to the table being built; a later library of the load order replaces an
## earlier one's reference.
static func register(entry: Dictionary) -> void:
	var texts: Dictionary = entry.get("structure_texts", {})
	for item: Dictionary in (entry["read"] as Dictionary).get("structures", []):
		var id := String(item["id"])
		var text := String(texts.get(id, ""))
		if text == "":
			continue
		_building[LibraryStructures.ref_of(String(entry["id"]), id)] = {
			"library": String(entry["id"]),
			"id": id,
			"entry": item["entry"],
			"text": text,
			"digest": String(item["digest"]),
			"folder": String(entry["folder"]),
		}


## Makes the table begin() and register() built the one the readers see.
static func publish() -> void:
	_mutex.lock()
	_table = _building
	_mutex.unlock()
	_building = {}


# ---- reading it (any thread) ----


## The structures served now as palette rows: {ref, library, id, name, family, variant, tags,
## default_size_m, min_side_m, max_side_m, max_area_m2, plans, expose, textured, thumb (absolute
## path of the thumbnail file, "" when it has none), digest}. `library_id` "" lists every library;
## sorted by library, family, variant, id.
static func structures(library_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table := _current()
	for ref: String in table:
		var held: Dictionary = table[ref]
		if library_id == "" or String(held["library"]) == library_id:
			out.append(_row(ref, held))
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var left := [a["library"], a["family"], a["variant"], a["id"]]
			var right := [b["library"], b["family"], b["variant"], b["id"]]
			return left < right
	)
	return out


## The row of structure `ref` (`<library>:<id>`), {} when no served library offers it.
static func structure(ref: String) -> Dictionary:
	var held: Variant = _current().get(ref)
	return _row(ref, held) if held is Dictionary else {}


static func has(ref: String) -> bool:
	return _current().has(ref)


## {text, digest} of structure `ref`'s recipe document, {} when no served library offers it: the
## shape StructureRecipes wants.
static func recipe(ref: String) -> Dictionary:
	var held: Variant = _current().get(ref)
	if not held is Dictionary:
		return {}
	return {"text": (held as Dictionary)["text"], "digest": (held as Dictionary)["digest"]}


## The structure references a map needs: {library id: PackedStringArray of `<library>:<id>`
## refs, sorted}, from its structure records. Apart from LibraryRegistry.assets_used_by because a
## structure is no palette asset (a transfer asks for them in their own list). Pure.
static func used_by(doc: MapDocument) -> Dictionary:
	var by_library := {}
	for structure_record in doc.structures:
		var parts := LibraryIds.split_ref(structure_record.recipe)
		if parts.is_empty() or String(parts["library"]) == "":
			continue
		var library := String(parts["library"])
		var held: PackedStringArray = by_library.get(library, PackedStringArray())
		if not structure_record.recipe in held:
			held.append(structure_record.recipe)
		by_library[library] = held
	for library: String in by_library:
		var sorted: PackedStringArray = by_library[library]
		sorted.sort()
		by_library[library] = sorted
	return by_library


# ---- helpers ----


static func _current() -> Dictionary:
	_mutex.lock()
	var table := _table
	_mutex.unlock()
	return table


static func _row(ref: String, held: Dictionary) -> Dictionary:
	var row: Dictionary = (held["entry"] as Dictionary).duplicate(true)
	row["ref"] = ref
	row["library"] = held["library"]
	var thumb := String(row.get("thumb", ""))
	row["thumb"] = String(held["folder"]).path_join(thumb) if thumb != "" else ""
	row["digest"] = held["digest"]
	return row


static func _cap(key: String) -> int:
	return int(LibraryContracts.STRUCTURE_CAPS[key])


static func _normal(text: String) -> String:
	return text.replace("\r\n", "\n")
