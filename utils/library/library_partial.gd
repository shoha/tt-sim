class_name LibraryPartial
extends RefCounted

## The pure half of multiplayer library transfer (docs/systems/library.md "Multiplayer"): what a
## PARTIAL library is, how the host trims a full library down to what a map uses, the wire
## bundle that carries it, and the checks a client runs on a bundle before anything is written.
## No files, no scene tree, no network: LibraryTransfer reads and writes, LibraryTransferChannel
## sends. Everything that arrives from the network is hostile until inspect() says otherwise.
##
## A partial library is an ordinary library folder (library.json, assets/catalog.json,
## biomes/*.json, the GLBs, surfaces/) with the SAME id and version as the host's, marked by a
## `partial` block in library.json: {format, source_version, source_hash, assets (the catalog
## ids kept), biomes, surfaces, assets_only, bytes}. Its catalog lists only the used assets, with
## `sha256` and `bytes` always set; its biome-defs keep only the rules whose assets are used. A
## dependency's assets that the map uses travel as an `assets_only` partial of the dependency (no
## biomes) unless the client already has a compatible one.
##
## The wire bundle is one blob of files keyed `<library id>/<relative path>`: the magic `TTLP`,
## a version byte, a u32 count, then per file a u16 path length, the path, a u32 size and the
## bytes. decode() checks counts, sizes and bounds BEFORE it allocates, so a hostile header
## cannot ask for memory the caps do not allow.

const PROTOCOL := 1
const FORMAT := 1
const BUNDLE_VERSION := 1
const MAGIC: PackedByteArray = [0x54, 0x54, 0x4C, 0x50]
const PARTIAL_KEY := "partial"
const LIBRARY_FILE := "library.json"
const CATALOG_FILE := "assets/catalog.json"
## Bundle caps: files in all, libraries in one bundle, bytes in all.
const MAX_ENTRIES := 4096
const MAX_LIBRARIES := 8
const MAX_TOTAL_BYTES := 256 * 1024 * 1024
## Per-file caps by extension (the whitelist is LibraryContracts.EXTENSIONS).
const FILE_CAPS := {
	".json": 4 * 1024 * 1024,
	".glb": 64 * 1024 * 1024,
	".png": 16 * 1024 * 1024,
	".jpg": 4 * 1024 * 1024,
	".txt": 65536,
	".md": 65536,
}
## Bounds on a request from a peer.
const MAX_REQUEST_ASSETS := 8192
const MAX_REQUEST_BIOMES := 256
const MAX_REQUEST_SURFACES := 64
const MAX_REQUEST_HAVE := 32
const MAX_ID_TEXT := 160

## Error codes of inspect() and decode().
const E_CAPS := "caps"
const E_TRUNCATED := "truncated"
const E_TRAVERSAL := "traversal"
const E_EXTENSION := "extension"
const E_RESERVED := "reserved_id"
const E_ID := "id_mismatch"
const E_VERSION := "version_mismatch"
const E_HASH := "bad_hash"
const E_EXTRA := "extra_file"
const E_INVALID := "invalid_library"
const E_COMPILE := "compile"
const E_PARTIAL := "not_partial"

# ---- the wire bundle ----


## The bundle for `files` ({path: PackedByteArray}), paths sorted so two builds of the same
## content are the same bytes (a resumed transfer depends on it).
static func encode(files: Dictionary) -> PackedByteArray:
	var paths: Array = files.keys()
	paths.sort()
	var out := PackedByteArray()
	out.append_array(MAGIC)
	out.append(BUNDLE_VERSION)
	out.resize(9)
	out.encode_u32(5, paths.size())
	for path: String in paths:
		var name_bytes := path.to_utf8_buffer()
		var data: PackedByteArray = files[path]
		var head := PackedByteArray()
		head.resize(2)
		head.encode_u16(0, name_bytes.size())
		out.append_array(head)
		out.append_array(name_bytes)
		var size := PackedByteArray()
		size.resize(4)
		size.encode_u32(0, data.size())
		out.append_array(size)
		out.append_array(data)
	return out


## {ok, code, error, files: {path: bytes}} for bundle bytes from the network. Counts and sizes are
## checked against the caps before any file is copied; a short or overlong buffer is `truncated`.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "code": "", "error": "", "files": {}}
	if bytes.size() < 9 or bytes.slice(0, 4) != MAGIC:
		return _fail(out, E_INVALID, "not a library bundle")
	if bytes[4] != BUNDLE_VERSION:
		return _fail(out, E_VERSION, "bundle version %d is not %d" % [bytes[4], BUNDLE_VERSION])
	var count := bytes.decode_u32(5)
	if count > MAX_ENTRIES:
		return _fail(out, E_CAPS, "%d files is over the cap of %d" % [count, MAX_ENTRIES])
	var at := 9
	var total := 0
	var files: Dictionary = out["files"]
	for _i in count:
		if at + 2 > bytes.size():
			return _fail(out, E_TRUNCATED, "the bundle ends inside a file header")
		var name_size := bytes.decode_u16(at)
		at += 2
		if name_size == 0 or name_size > LibraryContracts.MAX_RELATIVE_PATH + 40:
			return _fail(out, E_CAPS, "a file name is %d bytes long" % name_size)
		if at + name_size + 4 > bytes.size():
			return _fail(out, E_TRUNCATED, "the bundle ends inside a file name")
		var path := bytes.slice(at, at + name_size).get_string_from_utf8()
		at += name_size
		var size := bytes.decode_u32(at)
		at += 4
		var cap := file_cap(path)
		if cap == 0:
			return _fail(out, E_EXTENSION, "file %s: extension not allowed" % _short(path))
		if size > cap:
			return _fail(out, E_CAPS, "file %s: %d bytes is over its cap" % [_short(path), size])
		total += size
		if total > MAX_TOTAL_BYTES:
			return _fail(out, E_CAPS, "the bundle is over %d bytes" % MAX_TOTAL_BYTES)
		if at + size > bytes.size():
			return _fail(out, E_TRUNCATED, "the bundle ends inside %s" % _short(path))
		if files.has(path):
			return _fail(out, E_EXTRA, "file %s appears twice" % _short(path))
		files[path] = bytes.slice(at, at + size)
		at += size
	if at != bytes.size():
		return _fail(out, E_EXTRA, "%d bytes follow the last file" % (bytes.size() - at))
	out["ok"] = true
	return out


## Whether a transfer header from the host (AssetStreamer, the chunk array is sized from it) is
## within the bundle cap: a compressed stream is about as long as the bytes it holds.
static func header_ok(total_chunks: int, original_size: int, chunk_size: int) -> bool:
	return (
		original_size >= 0
		and original_size <= MAX_TOTAL_BYTES + 1048576
		and total_chunks >= 0
		and total_chunks <= original_size / chunk_size + 2
	)


## The cap for a file by its extension, 0 for an extension that is not allowed.
static func file_cap(path: String) -> int:
	return int(FILE_CAPS.get("." + path.get_extension().to_lower(), 0))


## {library id: {relative path: bytes}} of a decoded bundle's files, split at the first slash.
## Paths with no slash land under "".
static func split_libraries(files: Dictionary) -> Dictionary:
	var out := {}
	for path: String in files:
		var slash := path.find("/")
		var id := path.substr(0, slash) if slash > 0 else ""
		var relative := path.substr(slash + 1) if slash > 0 else path
		var held: Dictionary = out.get(id, {})
		held[relative] = files[path]
		out[id] = held
	return out


# ---- requests from a peer ----


## "" when `request` is a well-formed library request, else why not. It arrives over the network:
## every type and bound is checked, nothing is trusted.
static func request_problem(request: Variant) -> String:
	if not request is Dictionary:
		return "the request is not a dictionary"
	var data: Dictionary = request
	if not data.get("protocol") is int or int(data["protocol"]) != PROTOCOL:
		return "library transfer protocol %s is not %d" % [str(data.get("protocol")), PROTOCOL]
	var library: Variant = data.get("library")
	if not library is String or not LibraryIds.library_problems(library).is_empty():
		return "the library id is not valid"
	if library == LibraryContracts.CORE_ID:
		return "the core library is not transferred"
	for field in ["version", "hash"]:
		if not data.get(field) is String or String(data[field]).length() > 64:
			return "%s is not a short text" % field
	var problem := _ids_problem(data.get("assets"), "assets", MAX_REQUEST_ASSETS, true)
	if problem == "":
		problem = _ids_problem(data.get("biomes"), "biomes", MAX_REQUEST_BIOMES, false)
	if problem == "":
		problem = _ids_problem(data.get("surfaces"), "surfaces", MAX_REQUEST_SURFACES, false)
	if problem == "" and data.has("held_surfaces"):
		# The local names of surfaces a kept copy already holds: the host does not send them again.
		problem = _ids_problem(data["held_surfaces"], "held_surfaces", MAX_REQUEST_SURFACES, false)
	if problem != "":
		return problem
	var have: Variant = data.get("have", {})
	if not have is Dictionary or (have as Dictionary).size() > MAX_REQUEST_HAVE:
		return "have is not a short dictionary"
	for id: Variant in have as Dictionary:
		if not id is String or not (have as Dictionary)[id] is String:
			return "have holds a non-text entry"
		if String((have as Dictionary)[id]).length() > 64:
			return "have holds a long version"
	return ""


static func _ids_problem(value: Variant, field: String, limit: int, asset: bool) -> String:
	if not value is Array or (value as Array).size() > limit:
		return "%s is not a list of at most %d" % [field, limit]
	for item: Variant in value as Array:
		if not item is String or String(item).length() > MAX_ID_TEXT or String(item) == "":
			return "%s holds a bad entry" % field
		if asset and String(item).count("/") != 1:
			return "%s holds an id that is not <biome>/<asset>" % field
	return ""


# ---- trimming a library to what a map uses (host) ----


## What of the library `read` (LibraryReader.read's result) a request needs. `request` is a
## validated request. Returns {assets: Array[String] (catalog ids kept, sorted), dependency_assets:
## {dependency id: Array[String] local ids}, biomes: {file name: trimmed biome-def}, surfaces:
## Array[String] (names), skipped: Array[String] (requested asset ids the library lacks),
## biome_names: Array[String]}. The biome-defs keep only rules with a used asset; a biome left
## with none keeps its first rule and that rule's first asset so its ground still works.
static func select(read: Dictionary, request: Dictionary) -> Dictionary:
	var library: Dictionary = read.get("library", {})
	var library_id := String(library.get("id", ""))
	var catalog: Dictionary = read.get("catalog", {})
	var deps := dependency_ids(library)
	var wanted := {}
	var biome_names := {}
	var dependency_assets := {}
	var skipped: Array[String] = []
	for raw: Variant in request.get("assets", []):
		var asset_id := String(raw)
		if LibraryIds.library_of(asset_id) != library_id:
			continue
		var parsed := LibraryIds.parse_runtime_biome(asset_id.get_slice("/", 0))
		if not parsed.is_empty():
			biome_names[String(parsed["biome"])] = true
		var local := asset_id.get_slice("/", 1)
		var owner := dependency_owner(local, deps)
		if owner != "":
			var held: Dictionary = dependency_assets.get(owner, {})
			held[local.substr(owner.length() + LibraryIds.SEPARATOR.length())] = true
			dependency_assets[owner] = held
			wanted[local] = true
		elif catalog.has(local):
			wanted[local] = true
		else:
			skipped.append(asset_id)
	for raw: Variant in request.get("biomes", []):
		var parsed := LibraryIds.parse_runtime_biome(String(raw))
		if not parsed.is_empty() and String(parsed["library"]) == library_id:
			biome_names[String(parsed["biome"])] = true
	var biomes := {}
	var kept := wanted.duplicate()
	for item: Dictionary in read.get("biomes", []):
		var def: Dictionary = item["def"]
		if not biome_names.has(String(def.get("id", ""))):
			continue
		var trimmed := trim_biome(def, kept, catalog, deps)
		if not trimmed.is_empty():
			biomes[String(item["file"])] = trimmed
	var out_assets: Array[String] = []
	for local: String in kept:
		if catalog.has(local):
			out_assets.append(local)
	out_assets.sort()
	var deps_out := {}
	for dep: String in dependency_assets:
		var names: Array[String] = []
		names.assign((dependency_assets[dep] as Dictionary).keys())
		names.sort()
		deps_out[dep] = names
	var names_out: Array[String] = []
	names_out.assign(biome_names.keys())
	names_out.sort()
	return {
		"assets": out_assets,
		"dependency_assets": deps_out,
		"biomes": biomes,
		"surfaces": _without_held(surfaces_used(read, biomes, request), request),
		"skipped": skipped,
		"biome_names": names_out,
	}


## `names` without the surfaces the request says a kept copy already holds (`held_surfaces`).
static func _without_held(names: Array[String], request: Dictionary) -> Array[String]:
	var held: Variant = request.get("held_surfaces", [])
	var out: Array[String] = []
	for item in names:
		if not (held is Array and item in held):
			out.append(item)
	return out


## select() for a dependency that only supplies assets: `locals` are its catalog ids. No biome and
## no surface is kept (the dependent library's biomes use the assets).
static func select_assets_only(read: Dictionary, locals: Array) -> Dictionary:
	var catalog: Dictionary = read.get("catalog", {})
	var kept: Array[String] = []
	var skipped: Array[String] = []
	for raw: Variant in locals:
		if catalog.has(String(raw)):
			kept.append(String(raw))
		else:
			skipped.append(String(raw))
	kept.sort()
	return {
		"assets": kept,
		"dependency_assets": {},
		"biomes": {},
		"surfaces": [] as Array[String],
		"skipped": skipped,
		"biome_names": [] as Array[String],
	}


## The ids of the dependencies library.json declares.
static func dependency_ids(library: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = library.get("dependencies", [])
	if raw is Array:
		for item: Variant in raw as Array:
			if item is Dictionary and (item as Dictionary).get("id") is String:
				out.append(String((item as Dictionary)["id"]))
	return out


## The dependency a local asset id belongs to (`core__Tree_Oak_v0` -> `core`), "" for the
## library's own.
static func dependency_owner(local: String, deps: Array[String]) -> String:
	for dep in deps:
		if local.begins_with(dep + LibraryIds.SEPARATOR):
			return dep
	return ""


## `def` with its rules cut to the ones holding a ref in `kept` (a set of local ids as they are
## in the biome: a dependency's are `<dep>__<id>`), or {} when nothing can stay. A biome left
## with no rule keeps the first rule with a catalog ref and adds that ref to `kept`.
static func trim_biome(
	def: Dictionary, kept: Dictionary, catalog: Dictionary, deps: Array[String]
) -> Dictionary:
	var rules: Array = []
	var keys := {}
	for raw: Variant in def.get("rules", []):
		if not raw is Dictionary:
			continue
		var refs := _kept_refs(raw as Dictionary, kept)
		if not refs.is_empty():
			rules.append(_with_refs(raw, refs))
			keys[String((raw as Dictionary).get("key", ""))] = true
	if rules.is_empty():
		for raw: Variant in def.get("rules", []):
			if not raw is Dictionary:
				continue
			for ref: Dictionary in _all_refs(raw):
				var local := _ref_local(String(ref["ref"]))
				if catalog.has(local) and dependency_owner(local, deps) == "":
					kept[local] = true
					rules.append(_with_refs(raw, [ref]))
					keys[String((raw as Dictionary).get("key", ""))] = true
					break
			if not rules.is_empty():
				break
	if rules.is_empty():
		return {}
	var out := def.duplicate(true)
	out["rules"] = rules.map(func(rule: Dictionary) -> Dictionary: return _without_dead(rule, keys))
	out.erase("thumbnail")
	return out


static func _kept_refs(rule: Dictionary, kept: Dictionary) -> Array:
	var out: Array = []
	for ref: Dictionary in _all_refs(rule):
		if kept.has(_ref_local(String(ref["ref"]))):
			out.append(ref)
	return out


static func _all_refs(rule: Variant) -> Array:
	var out: Array = []
	var query: Variant = (rule as Dictionary).get("query")
	if query is Dictionary and (query as Dictionary).get("match") is Array:
		for clause: Variant in (query as Dictionary)["match"] as Array:
			if clause is Dictionary and (clause as Dictionary).get("ref") is String:
				out.append(clause)
	return out


## The local id a ref names inside the biome: `Tree_Oak_v0`, or `core__Tree_Oak_v0` for
## `core:Tree_Oak_v0`.
static func _ref_local(ref: String) -> String:
	var parts := LibraryIds.split_ref(ref)
	if parts.is_empty():
		return ref
	if String(parts["library"]) == "":
		return String(parts["local"])
	return LibraryIds.dependency_local(String(parts["library"]), String(parts["local"]))


static func _with_refs(rule: Variant, refs: Array) -> Dictionary:
	var out: Dictionary = (rule as Dictionary).duplicate(true)
	var query: Dictionary = out["query"]
	query["match"] = refs
	return out


## `rule` without near/avoid relations that name a rule key that was cut.
static func _without_dead(rule: Dictionary, keys: Dictionary) -> Dictionary:
	for field in ["near", "avoid"]:
		if rule.get(field) is Array:
			var live: Array = []
			for item: Variant in rule[field] as Array:
				if item is Dictionary and (item as Dictionary).get("rule") is String:
					if not keys.has(String((item as Dictionary)["rule"])):
						continue
				live.append(item)
			rule[field] = live
	return rule


## The surface names (of the library's own surfaces/) the kept biome-defs' ground and the request
## name.
static func surfaces_used(
	read: Dictionary, biomes: Dictionary, request: Dictionary
) -> Array[String]:
	var library_id := String((read.get("library", {}) as Dictionary).get("id", ""))
	var own: Dictionary = read.get("surfaces", {})
	var found := {}
	for def: Dictionary in biomes.values():
		_collect_surfaces(def.get("ground"), library_id, own, found)
	for raw: Variant in request.get("surfaces", []):
		var text := String(raw)
		var prefix := library_id + LibraryIds.SEPARATOR
		if text.begins_with(prefix) and own.has(text.substr(prefix.length())):
			found[text.substr(prefix.length())] = true
	var out: Array[String] = []
	out.assign(found.keys())
	out.sort()
	return out


static func _collect_surfaces(
	value: Variant, library_id: String, own: Dictionary, found: Dictionary
) -> void:
	if value is String:
		var ref := LibraryIds.parse_surface_ref(value)
		if not ref.is_empty() and String(ref["library"]) == library_id and own.has(ref["name"]):
			found[String(ref["name"])] = true
		elif own.has(value):
			found[value] = true
	elif value is Array:
		for item: Variant in value as Array:
			_collect_surfaces(item, library_id, own, found)
	elif value is Dictionary:
		for item: Variant in (value as Dictionary).values():
			_collect_surfaces(item, library_id, own, found)


## library.json for the partial: the host's with its stats, cover, bindings and default biome
## removed and the `partial` block added.
static func trim_library(library: Dictionary, info: Dictionary) -> Dictionary:
	var out := library.duplicate(true)
	for key in ["stats", "thumbnail", "bindings", "default_biome"]:
		out.erase(key)
	out[PARTIAL_KEY] = info
	return out


## assets/catalog.json holding only `kept` ids (in catalog order), without file references the
## partial does not carry.
static func trim_catalog(read: Dictionary, kept: Array[String]) -> Dictionary:
	var catalog: Dictionary = read.get("catalog", {})
	var entries: Array = []
	for id: String in read.get("catalog_order", []):
		if id in kept:
			var entry: Dictionary = (catalog[id] as Dictionary).duplicate(true)
			entry.erase("thumb")
			entry.erase("sidecar")
			entries.append(entry)
	return {
		"format": LibraryContracts.FORMAT_CATALOG,
		"format_version": LibraryContracts.FORMAT_VERSION,
		"assets": entries,
	}


## Canonical JSON bytes (sorted keys, so a rebuild is the same bytes).
static func json_bytes(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data, "\t", true).to_utf8_buffer()


# ---- checking a received library (client) ----


## The in-memory twin of LibraryRegistry.read_sources: the dictionary LibraryReader.read takes,
## made from a library's files ({relative path: bytes}).
static func sources_of(files: Dictionary) -> Dictionary:
	var names: Array = files.keys()
	names.sort()
	var biomes := {}
	var surfaces := {}
	var png := {}
	for relative: String in names:
		var data: PackedByteArray = files[relative]
		if (
			relative.begins_with("biomes/")
			and relative.count("/") == 1
			and relative.ends_with(".json")
		):
			biomes[relative.get_file()] = data.get_string_from_utf8()
		var parts := relative.split("/")
		if parts.size() == 3 and parts[0] == "surfaces":
			if parts[2] == SurfaceReader.INFO_FILE:
				surfaces[parts[1]] = data.get_string_from_utf8()
			elif relative.get_extension().to_lower() == "png":
				png[relative] = SurfaceBake.png_header(data.slice(0, SurfaceBake.PNG_HEADER_BYTES))
	var library: PackedByteArray = files.get(LIBRARY_FILE, PackedByteArray())
	var catalog: PackedByteArray = files.get(CATALOG_FILE, PackedByteArray())
	return {
		"library": library.get_string_from_utf8(),
		"catalog": catalog.get_string_from_utf8(),
		"biomes": biomes,
		"surfaces": surfaces,
		"png": png,
		"files": names,
	}


## Checks the files of ONE received library ({relative path: bytes}). `expect` is
## {id (the folder name the bundle used), wanted_version (the version the map was saved with, ""
## for none), official_ids (library ids that ship with the game), surfaces (the palette's surface
## table for the compile dry-run), dependencies ({id: {read}} for refs, may be empty)}. Returns
## {ok, errors: [{code, text}], warnings, read, library, partial}. Nothing is written; every
## failure is a structured error and nothing raises.
static func inspect(files: Dictionary, expect: Dictionary) -> Dictionary:
	var out := {"ok": false, "errors": [], "warnings": [], "read": {}, "library": {}, "partial": {}}
	var errors: Array = out["errors"]
	var id := String(expect.get("id", ""))
	_check_ids(id, expect, errors)
	_check_names(files, errors)
	if not errors.is_empty():
		return out
	var read := LibraryReader.read(sources_of(files))
	out["read"] = read
	out["library"] = read["library"]
	for text: String in read["errors"]:
		errors.append({"code": E_INVALID, "text": text})
	out["warnings"] = read["warnings"]
	var library: Dictionary = read["library"]
	if library.is_empty():
		return out
	if String(library.get("id", "")) != id:
		errors.append(
			{
				"code": E_ID,
				"text": "library.json names '%s' but the folder is '%s'" % [library.get("id"), id]
			}
		)
	_check_version(library, expect, errors)
	var partial := _check_partial(library, errors)
	out["partial"] = partial
	if errors.is_empty() and bool(read["ok"]):
		_check_extra(files, read, errors)
		_check_assets(files, read, errors)
	if errors.is_empty():
		_dry_run(read, partial, expect, errors, out["warnings"])
	out["ok"] = errors.is_empty()
	return out


static func _check_ids(id: String, expect: Dictionary, errors: Array) -> void:
	var problems := LibraryIds.library_problems(id)
	if id == LibraryContracts.CORE_ID or id in (expect.get("official_ids", []) as Array):
		errors.append(
			{"code": E_RESERVED, "text": "'%s' is an official library; it is never received" % id}
		)
	elif not problems.is_empty():
		errors.append({"code": E_RESERVED, "text": problems[0]})


static func _check_names(files: Dictionary, errors: Array) -> void:
	var total := 0
	if files.size() > MAX_ENTRIES:
		errors.append({"code": E_CAPS, "text": "%d files is over the cap" % files.size()})
		return
	for path: String in files:
		if not LibraryIds.path_problems(path).is_empty():
			var code := (
				E_TRAVERSAL if (".." in path or path.begins_with("/") or ":" in path) else E_INVALID
			)
			errors.append(
				{"code": code, "text": "file %s: not a portable relative path" % _short(path)}
			)
			continue
		var cap := file_cap(path)
		if cap == 0:
			errors.append(
				{"code": E_EXTENSION, "text": "file %s: extension not allowed" % _short(path)}
			)
		elif (files[path] as PackedByteArray).size() > cap:
			errors.append({"code": E_CAPS, "text": "file %s is over its size cap" % _short(path)})
		total += (files[path] as PackedByteArray).size()
	if total > MAX_TOTAL_BYTES:
		errors.append({"code": E_CAPS, "text": "the library is over %d bytes" % MAX_TOTAL_BYTES})
	for duplicate in LibraryIds.case_duplicates(files.keys()):
		errors.append(
			{"code": E_INVALID, "text": "file %s collides when case is ignored" % duplicate}
		)


static func _check_version(library: Dictionary, expect: Dictionary, errors: Array) -> void:
	var wanted := String(expect.get("wanted_version", ""))
	var have := String(library.get("version", ""))
	if wanted == "":
		return
	var want_parts := LibraryVersions.parse(wanted)
	var have_parts := LibraryVersions.parse(have)
	if (
		have_parts.is_empty()
		or (not want_parts.is_empty() and int(want_parts["major"]) != int(have_parts["major"]))
	):
		errors.append(
			{
				"code": E_VERSION,
				"text": "the host sent version '%s', the map was saved with '%s'" % [have, wanted]
			}
		)


## The `partial` block of library.json, checked; {} (and an error) when it is absent or bad.
static func _check_partial(library: Dictionary, errors: Array) -> Dictionary:
	var raw: Variant = library.get(PARTIAL_KEY)
	if not raw is Dictionary:
		errors.append({"code": E_PARTIAL, "text": "library.json has no partial block"})
		return {}
	var info: Dictionary = raw
	if not info.get("format") is int and not info.get("format") is float:
		errors.append({"code": E_PARTIAL, "text": "partial.format is missing"})
	elif int(info["format"]) != FORMAT:
		errors.append(
			{"code": E_PARTIAL, "text": "partial.format %s is not %d" % [info["format"], FORMAT]}
		)
	for field in ["assets", "biomes", "surfaces"]:
		if not info.get(field, []) is Array:
			errors.append({"code": E_PARTIAL, "text": "partial.%s is not a list" % field})
	return info


## Every file must be one the library names: library.json, the catalog, the biome-defs the reader
## accepted, a catalog entry's GLB or a surface set's files. Anything else is an extra file.
static func _check_extra(files: Dictionary, read: Dictionary, errors: Array) -> void:
	var allowed := {LIBRARY_FILE: true, CATALOG_FILE: true}
	for item: Dictionary in read.get("biomes", []):
		allowed["biomes/" + String(item["file"])] = true
	for id: String in read.get("catalog", {}):
		allowed[String((read["catalog"][id] as Dictionary).get("file", ""))] = true
	for name: String in read.get("surfaces", {}):
		allowed["surfaces/%s/%s" % [name, SurfaceReader.INFO_FILE]] = true
		for kind: String in (read["surfaces"][name] as Dictionary).get("maps", []):
			allowed["surfaces/%s/%s.png" % [name, kind]] = true
	for path: String in files:
		if not allowed.has(path):
			errors.append({"code": E_EXTRA, "text": "unexpected file %s" % _short(path)})
	for id: String in read.get("catalog", {}):
		if not files.has(String((read["catalog"][id] as Dictionary).get("file", ""))):
			errors.append({"code": E_TRUNCATED, "text": "catalog %s: its file is missing" % id})


## Each GLB against the catalog's sha256 and bytes (both required for a received library) and
## GlbGuard before anything decodes it.
static func _check_assets(files: Dictionary, read: Dictionary, errors: Array) -> void:
	for id: String in read.get("catalog", {}):
		var entry: Dictionary = read["catalog"][id]
		var data: PackedByteArray = files.get(String(entry.get("file", "")), PackedByteArray())
		if data.is_empty():
			continue
		var has_bytes: bool = entry.get("bytes") is int or entry.get("bytes") is float
		if not entry.get("sha256") is String or not has_bytes:
			errors.append({"code": E_HASH, "text": "catalog %s has no sha256 and bytes" % id})
			continue
		if int(entry["bytes"]) != data.size():
			errors.append(
				{"code": E_HASH, "text": "catalog %s: size differs from the catalog" % id}
			)
			continue
		if sha256_of(data) != String(entry["sha256"]):
			errors.append(
				{"code": E_HASH, "text": "catalog %s: sha256 differs from the catalog" % id}
			)
			continue
		var guard := GlbGuard.inspect(data)
		if not guard["ok"]:
			errors.append({"code": E_INVALID, "text": "catalog %s: %s" % [id, guard["error"]]})


## Compiles the library alone (BiomeCompiler, no files): a partial with biomes must give at least
## one palette biome and no reader error; an `assets_only` one is a pool for a dependent's refs.
static func _dry_run(
	read: Dictionary, partial: Dictionary, expect: Dictionary, errors: Array, warnings: Array
) -> void:
	var assets_only := bool(partial.get("assets_only", false))
	var surfaces: Variant = expect.get("surfaces")
	var compiled := (
		BiomeCompiler
		. compile(
			read,
			{
				"folder": "",
				"surfaces": surfaces if surfaces is Dictionary else {},
				"hash": "",
				"files": [],
				"dependencies": expect.get("dependencies", {}),
			}
		)
	)
	warnings.append_array(compiled.get("warnings", []))
	if (compiled.get("biome_ids", []) as Array).is_empty() and not assets_only:
		errors.append({"code": E_COMPILE, "text": "no biome of the received library compiles"})


static func sha256_of(data: PackedByteArray) -> String:
	if data.is_empty():
		return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish().hex_encode()


static func _fail(out: Dictionary, code: String, text: String) -> Dictionary:
	out["code"] = code
	out["error"] = text
	return out


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
