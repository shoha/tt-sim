class_name LibraryTransfer
extends RefCounted

## Multiplayer transfer of the library assets a map uses (docs/systems/library.md "Multiplayer").
## The host serves a PARTIAL library (LibraryPartial: the used assets, the biome-defs of the
## biomes the map uses with only their used rules, the surfaces those biomes use) and the client
## installs it into a TRANSIENT cache (LibraryRegistry.received_root(), `user://libraries/.received/
## <id>/`), never into the user's libraries unless the player chooses to keep it (promote()).
##
## The three halves, none of which touches the network or the scene tree:
## - client: plan(doc) says which libraries to ask the host for, and which cannot be asked for;
## - host: authorize() (is every asked id used by a map this session serves?), quote() (sizes)
##   and build_bundle() (the wire bytes), reading the host's library folder;
## - client: verify_and_install() decodes, inspects (LibraryPartial.inspect: caps, portable names,
##   extensions, no extra file, reserved ids, sha256 and size of every GLB, GlbGuard, the reader,
##   a compile dry-run) and only then writes, atomically per library, with an LRU cap.
##
## LibraryTransferChannel (autoloads/ side: scenes/library_transfer_channel.gd) carries the
## messages and the chunked bytes (AssetStreamer's windowed transfer).

## What one request may ask for, in bytes of the bundle (LibraryPartial.MAX_TOTAL_BYTES).
const MAX_REQUEST_BYTES := LibraryPartial.MAX_TOTAL_BYTES

# ---- client: what to ask for ----


## The libraries `doc` needs that this install can ask the host for. `view` is
## {library id: LibraryRegistry.info()} (null reads the registry), `assets` the palette's asset
## table (null reads the palette), `extra` {library id: [asset ids]} assets known to be needed
## beyond the document's (a live edit). Returns {requests: [request], blocked: [{library, code,
## text}], satisfied: [ids]}. A request is what LibraryPartial.request_problem accepts. Pure over
## its inputs. Block codes: reserved, disabled, error, incompatible, lacks.
static func plan(
	doc: MapDocument, view: Variant = null, assets: Variant = null, extra: Dictionary = {}
) -> Dictionary:
	var out := {"requests": [], "blocked": [], "satisfied": [] as Array[String]}
	var known: Dictionary = (
		assets if assets is Dictionary else PaletteLibrary.get_palette()["assets"]
	)
	var by_library := LibraryRegistry.assets_used_by(doc)
	for library: String in extra:
		var held: PackedStringArray = by_library.get(library, PackedStringArray())
		for asset_id: Variant in extra[library] as Array:
			if not String(asset_id) in held:
				held.append(String(asset_id))
		by_library[library] = held
	var ids: Array[String] = MapLibraries.used_ids(doc)
	for claimed in doc.libraries:
		if not String(claimed.get("id", "")) in ids:
			ids.append(String(claimed.get("id", "")))
	ids.sort()
	var infos: Dictionary = view if view is Dictionary else _view_of(ids)
	for id in ids:
		if id == LibraryContracts.CORE_ID:
			continue
		var wanted := _claim(doc, id)
		var used: PackedStringArray = by_library.get(id, PackedStringArray())
		var lacking: Array[String] = []
		for asset_id in used:
			if not known.has(asset_id):
				lacking.append(asset_id)
		var verdict := _verdict(id, wanted, infos.get(id, {}), lacking)
		if verdict["kind"] == "request":
			(out["requests"] as Array).append(
				_request(doc, id, wanted, used, infos, String(verdict["reason"]))
			)
		elif verdict["kind"] == "blocked":
			(out["blocked"] as Array).append(
				{"library": id, "code": verdict["code"], "text": verdict["text"]}
			)
		else:
			(out["satisfied"] as Array[String]).append(id)
	return out


static func _verdict(
	id: String, wanted: Dictionary, local: Dictionary, lacking: Array[String]
) -> Dictionary:
	if (
		not LibraryIds.library_problems(id).is_empty()
		or id in LibraryContracts.RESERVED_LIBRARY_IDS
	):
		return _blocked("reserved", "'%s' is not a library id that can be received." % id)
	if local.is_empty():
		return {"kind": "request", "reason": "missing"}
	if String(local.get("status", "")) == LibraryResolver.DISABLED:
		return _blocked("disabled", "%s is installed but turned off." % local.get("name", id))
	if String(local.get("status", "")) != LibraryResolver.OK:
		return _blocked("error", "%s is installed but cannot be loaded." % local.get("name", id))
	var want_version := String(wanted.get("version", ""))
	var have_version := String(local.get("version", ""))
	var want_parts := LibraryVersions.parse(want_version)
	var have_parts := LibraryVersions.parse(have_version)
	if not want_parts.is_empty() and not have_parts.is_empty():
		if int(want_parts["major"]) != int(have_parts["major"]):
			return _blocked(
				"incompatible",
				(
					"%s %s is installed; the map needs %s."
					% [local.get("name", id), have_version, want_version]
				)
			)
	if lacking.is_empty():
		return {"kind": "satisfied"}
	if String(local.get("source", "")) == "received":
		return {"kind": "request", "reason": "more"}
	if want_version != "" and LibraryVersions.compare(have_version, want_version) < 0:
		if String(local.get("source", "")) == "user":
			return {"kind": "request", "reason": "newer"}
	return _blocked(
		"lacks",
		(
			"%s %s lacks %d plants this map uses."
			% [local.get("name", id), have_version, lacking.size()]
		)
	)


static func _blocked(code: String, text: String) -> Dictionary:
	return {"kind": "blocked", "code": code, "text": text}


static func _claim(doc: MapDocument, id: String) -> Dictionary:
	for claimed in doc.libraries:
		if String(claimed.get("id", "")) == id:
			return claimed
	return {}


static func _request(
	doc: MapDocument,
	id: String,
	wanted: Dictionary,
	used: PackedStringArray,
	infos: Dictionary,
	reason: String
) -> Dictionary:
	var biomes: Array[String] = []
	for biome_id in doc.biome_ids:
		if LibraryIds.library_of(biome_id) == id and not biome_id in biomes:
			biomes.append(biome_id)
	biomes.sort()
	var surfaces: Array[String] = []
	var named: Array[String] = []
	named.assign(doc.surface_ids)
	if doc.base_surface != "":
		named.append(doc.base_surface)
	for surface in named:
		if MapLibraries.surface_library(surface) == id and not surface in surfaces:
			surfaces.append(surface)
	surfaces.sort()
	var have := {}
	for other: String in infos:
		var entry: Dictionary = infos[other]
		if String(entry.get("status", "")) == LibraryResolver.OK and have.size() < 24:
			have[other] = String(entry.get("version", ""))
	var asset_ids: Array[String] = []
	asset_ids.assign(Array(used))
	return {
		"protocol": LibraryPartial.PROTOCOL,
		"library": id,
		"version": String(wanted.get("version", "")),
		"hash": String(wanted.get("hash", "")),
		"assets": asset_ids,
		"biomes": biomes,
		"surfaces": surfaces,
		"have": have,
		"reason": reason,
	}


## The request skeleton for library `id` as `doc` uses it (what a host announces when it starts
## using a library mid-session): a request without `have`, {} when the document holds nothing of
## it.
static func hint_of(doc: MapDocument, id: String) -> Dictionary:
	var used: PackedStringArray = LibraryRegistry.assets_used_by(doc).get(id, PackedStringArray())
	var wanted := {}
	for record in MapLibraries.record_for(doc):
		if String(record.get("id", "")) == id:
			wanted = record
	var hint := _request(doc, id, wanted, used, {}, "hint")
	if used.size() > LibraryPartial.MAX_REQUEST_ASSETS:
		return {}
	return hint


## The document a client plans a hint against: a map holding exactly what the hint names. null
## when the hint is not a well-formed request (it came over the network).
static func document_of_hint(hint: Dictionary) -> MapDocument:
	if LibraryPartial.request_problem(hint) != "":
		return null
	var doc := MapDocument.new()
	for asset_id: Variant in hint["assets"] as Array:
		doc.scatter[String(asset_id)] = PackedFloat32Array()
	for biome_id: Variant in hint["biomes"] as Array:
		doc.biome_ids.append(String(biome_id))
	for surface: Variant in hint["surfaces"] as Array:
		doc.surface_ids.append(String(surface))
	doc.libraries.append({"id": hint["library"], "version": hint["version"], "hash": hint["hash"]})
	return doc


static func _view_of(ids: Array[String]) -> Dictionary:
	var out := {}
	for id in ids:
		var info := LibraryRegistry.info(id)
		if not info.is_empty():
			out[id] = info
	for info: Dictionary in LibraryRegistry.list():
		if String(info["status"]) == LibraryResolver.OK and not out.has(info["id"]):
			out[info["id"]] = info
	return out


# ---- host: authorization ----


## What the maps being served use: {assets: {id: true}, biomes: {id: true}, surfaces: {name:
## true}} over `docs` (the table map's live document and the shelf maps').
static func usage_of(docs: Array) -> Dictionary:
	var usage := {"assets": {}, "biomes": {}, "surfaces": {}}
	for doc: MapDocument in docs:
		if doc == null:
			continue
		for source: Dictionary in [doc.scatter, doc.props]:
			for asset_id: String in source:
				usage["assets"][asset_id] = true
		for biome_id in doc.biome_ids:
			usage["biomes"][biome_id] = true
		for surface in doc.surface_ids:
			usage["surfaces"][surface] = true
		if doc.base_surface != "":
			usage["surfaces"][doc.base_surface] = true
	return usage


## Adds the ids of usage `other` (usage_of's form) to `into`.
static func merge_usage(into: Dictionary, other: Dictionary) -> void:
	for field in ["assets", "biomes", "surfaces"]:
		(into[field] as Dictionary).merge(other.get(field, {}))


## "" when every asset, biome and surface of `request` is used by a served map, else why not. A
## client can only ask for what the table or the shelf holds, never an arbitrary library file.
static func authorize(request: Dictionary, usage: Dictionary) -> String:
	for field in [["assets", "assets"], ["biomes", "biomes"], ["surfaces", "surfaces"]]:
		var allowed: Dictionary = usage.get(field[1], {})
		for item: Variant in request.get(field[0], []) as Array:
			if not allowed.has(String(item)):
				return "'%s' is not used by any map in this session" % String(item)
	return ""


# ---- host: building the partial ----


## The partial for `request` from the served library: {ok, code, error, parts: [part]} where a
## part is {id, name, version, author, assets_only, files: {path: bytes or {} when !with_data},
## sizes: {path: int}, bytes, count, skipped}. `served` is LibraryRegistry.served() (null reads
## it). `with_data` false measures (a quote) and true reads every file (a bundle).
static func prepare(request: Dictionary, with_data: bool, served: Variant = null) -> Dictionary:
	var out := {"ok": false, "code": "", "error": "", "parts": []}
	var problem := LibraryPartial.request_problem(request)
	if problem != "":
		return _fail(out, "request", problem)
	var table: Dictionary = served if served is Dictionary else LibraryRegistry.served()
	var id := String(request["library"])
	var main := _part(id, request, null, with_data, table, out)
	if not out["error"].is_empty():
		return out
	var parts: Array = [main["part"]]
	var read: Dictionary = main["read"]
	var library: Dictionary = read["library"]
	var have: Dictionary = request.get("have", {})
	for dep: String in main["selection"]["dependency_assets"]:
		if dep == LibraryContracts.CORE_ID or _have_satisfies(library, dep, have):
			continue
		var host_dep: Dictionary = table.get(dep, {})
		if host_dep.is_empty() or bool(host_dep.get("official", false)):
			continue
		var dep_part := _part(
			dep, request, main["selection"]["dependency_assets"][dep], with_data, table, out
		)
		if not out["error"].is_empty():
			return out
		for dep_of_dep in LibraryPartial.dependency_ids(dep_part["read"]["library"]):
			if dep_of_dep != LibraryContracts.CORE_ID and not have.has(dep_of_dep):
				return _fail(
					out, "dependency", "%s needs %s, which is too deep to send" % [dep, dep_of_dep]
				)
		parts.append(dep_part["part"])
	var total := 0
	var count := 0
	for part: Dictionary in parts:
		total += int(part["bytes"])
		count += int(part["count"])
	if total > MAX_REQUEST_BYTES or count > LibraryPartial.MAX_ENTRIES:
		return _fail(
			out, "caps", "the plants for this map are %s, over the limit" % format_bytes(total)
		)
	out["parts"] = parts
	out["ok"] = true
	return out


static func _have_satisfies(library: Dictionary, dep: String, have: Dictionary) -> bool:
	if not have.has(dep):
		return false
	for item: Variant in library.get("dependencies", []) as Array:
		if item is Dictionary and String((item as Dictionary).get("id", "")) == dep:
			return LibraryVersions.satisfies(
				String(have[dep]), String((item as Dictionary).get("version", "*"))
			)
	return true


## One library's part. `only` is null for the requested library (a full selection), or the list
## of local ids of a dependency (assets only).
static func _part(
	id: String,
	request: Dictionary,
	only: Variant,
	with_data: bool,
	table: Dictionary,
	out: Dictionary
) -> Dictionary:
	var found: Dictionary = table.get(id, {})
	if found.is_empty():
		_fail(out, "not_served", "the host does not have the library '%s'" % id)
		return {}
	if bool(found.get("official", false)):
		_fail(out, "official", "'%s' ships with the game and is not sent" % id)
		return {}
	var folder := String(found["folder"])
	var sources := LibraryRegistry.read_sources(folder)
	if sources.has("error"):
		_fail(out, "unreadable", String(sources["error"]))
		return {}
	var read := LibraryReader.read(sources)
	if not read["ok"]:
		_fail(out, "unreadable", "the host's copy of '%s' does not read" % id)
		return {}
	var selection: Dictionary
	if only == null:
		var wanted := LibraryVersions.parse(String(request.get("version", "")))
		var have := LibraryVersions.parse(String(found.get("version", "")))
		if not wanted.is_empty() and not have.is_empty() and wanted["major"] != have["major"]:
			_fail(
				out,
				"version",
				(
					"the host has %s %s, the map was saved with %s"
					% [id, found["version"], request["version"]]
				)
			)
			return {}
		selection = LibraryPartial.select(read, request)
	else:
		selection = LibraryPartial.select_assets_only(read, only as Array)
	var built := _files_of(
		folder, read, selection, sources["files"], only != null, with_data, found
	)
	if built.has("error"):
		_fail(out, "unreadable", String(built["error"]))
		return {}
	var library: Dictionary = read["library"]
	return {
		"read": read,
		"selection": selection,
		"part":
		{
			"id": id,
			"name": String(library.get("name", id)),
			"version": String(library.get("version", "")),
			"author": String(library.get("author", "")),
			"assets_only": only != null,
			"files": built["files"],
			"sizes": built["sizes"],
			"bytes": built["bytes"],
			"count": built["sizes"].size(),
			"assets": selection["assets"].size(),
			"skipped": selection["skipped"].size(),
		},
	}


## The partial's files: {files: {path: bytes}, sizes: {path: int}, bytes: GLB and surface bytes}
## or {error}. Without `with_data` the byte arrays are empty and sizes come from the disk.
static func _files_of(
	folder: String,
	read: Dictionary,
	selection: Dictionary,
	listing: Array,
	assets_only: bool,
	with_data: bool,
	found: Dictionary
) -> Dictionary:
	var files := {}
	var sizes := {}
	var payload := 0
	var kept: Array[String] = []
	kept.assign(selection["assets"])
	var catalog := LibraryPartial.trim_catalog(read, kept)
	for entry: Dictionary in catalog["assets"]:
		var relative := String(entry["file"])
		var data := _read_file(folder, relative, with_data)
		if data.has("error"):
			return data
		sizes[relative] = int(data["size"])
		payload += int(data["size"])
		files[relative] = data["data"]
		# A quote measures the bytes the bundle will hold (a digest is 64 characters either way).
		entry["bytes"] = int(data["size"])
		entry["sha256"] = (LibraryPartial.sha256_of(data["data"]) if with_data else "0".repeat(64))
	for name: String in selection["surfaces"]:
		for relative: String in listing:
			if relative.begins_with("surfaces/%s/" % name):
				var data := _read_file(folder, relative, with_data)
				if data.has("error"):
					return data
				sizes[relative] = int(data["size"])
				payload += int(data["size"])
				files[relative] = data["data"]
	var info := {
		"format": LibraryPartial.FORMAT,
		"source_version": String(found.get("version", "")),
		"source_hash": String(found.get("hash", "")),
		"assets": kept,
		"biomes":
		(selection["biomes"] as Dictionary).keys().map(
			func(file: String) -> String: return file.get_basename()
		),
		"surfaces": selection["surfaces"],
		"assets_only": assets_only,
		"bytes": payload,
	}
	var library_bytes := LibraryPartial.json_bytes(
		LibraryPartial.trim_library(read["library"], info)
	)
	var catalog_bytes := LibraryPartial.json_bytes(catalog)
	files[LibraryPartial.LIBRARY_FILE] = library_bytes if with_data else PackedByteArray()
	files[LibraryPartial.CATALOG_FILE] = catalog_bytes if with_data else PackedByteArray()
	sizes[LibraryPartial.LIBRARY_FILE] = library_bytes.size()
	sizes[LibraryPartial.CATALOG_FILE] = catalog_bytes.size()
	for file_name: String in selection["biomes"]:
		var biome_bytes := LibraryPartial.json_bytes(selection["biomes"][file_name])
		files["biomes/" + file_name] = biome_bytes if with_data else PackedByteArray()
		sizes["biomes/" + file_name] = biome_bytes.size()
	var total := 0
	for size: int in sizes.values():
		total += size
	return {"files": files, "sizes": sizes, "bytes": total}


static func _read_file(folder: String, relative: String, with_data: bool) -> Dictionary:
	if not LibraryIds.path_problems(relative).is_empty():
		return {"error": "unsafe path %s" % relative}
	var path := folder.path_join(relative)
	if not FileAccess.file_exists(path):
		return {"error": "missing file %s" % relative}
	if not with_data:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"error": "cannot read %s" % relative}
		var size := file.get_length()
		file.close()
		return {"size": size, "data": PackedByteArray()}
	var data := FileAccess.get_file_as_bytes(path)
	return {"size": data.size(), "data": data}


## The quote the host sends before any bytes: {ok, protocol, libraries: [{id, name, version,
## author, assets, files, bytes, assets_only}], bytes, files, skipped} or {ok: false, code,
## error}. Sizes are the bundle's own (JSON included).
static func quote(request: Dictionary, served: Variant = null) -> Dictionary:
	var made := prepare(request, false, served)
	if not made["ok"]:
		return {
			"ok": false,
			"protocol": LibraryPartial.PROTOCOL,
			"code": made["code"],
			"error": made["error"]
		}
	var libraries: Array = []
	var bytes := 0
	var files := 0
	var skipped := 0
	for part: Dictionary in made["parts"]:
		var size := 0
		for path: String in part["sizes"]:
			size += int(part["sizes"][path])
		(
			libraries
			. append(
				{
					"id": part["id"],
					"name": part["name"],
					"version": part["version"],
					"author": part["author"],
					"assets": part["assets"],
					"files": part["count"],
					"bytes": size,
					"assets_only": part["assets_only"],
				}
			)
		)
		bytes += size
		files += int(part["count"])
		skipped += int(part["skipped"])
	return {
		"ok": true,
		"protocol": LibraryPartial.PROTOCOL,
		"libraries": libraries,
		"bytes": bytes,
		"files": files,
		"skipped": skipped,
	}


## The wire bytes for `request` (empty with an error in `out` when it cannot be built).
static func build_bundle(request: Dictionary, served: Variant = null) -> PackedByteArray:
	var made := prepare(request, true, served)
	if not made["ok"]:
		return PackedByteArray()
	var files := {}
	for part: Dictionary in made["parts"]:
		for relative: String in part["files"]:
			files["%s/%s" % [part["id"], relative]] = part["files"][relative]
	return LibraryPartial.encode(files)


# ---- client: checking and installing ----


## Decodes, inspects and installs a received bundle. `ctx`: {library (the requested id),
## wanted_version, root (default LibraryRegistry.received_root()), official_ids (default: the
## game's), surfaces (default: the palette's), now (unix time, default the clock), cap (cache
## cap, default CACHE_CAP_BYTES)}. Returns {ok, errors: [{code, text}], libraries: [ids],
## bytes, files}. Nothing is written unless every library in the bundle passes.
static func verify_and_install(bundle: Variant, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "errors": [], "libraries": [] as Array[String], "bytes": 0, "files": 0}
	var errors: Array = out["errors"]
	var files: Dictionary
	if bundle is PackedByteArray:
		var decoded := LibraryPartial.decode(bundle)
		if not decoded["ok"]:
			errors.append({"code": decoded["code"], "text": decoded["error"]})
			return out
		files = decoded["files"]
	else:
		files = bundle
	var split := LibraryPartial.split_libraries(files)
	var requested := String(ctx.get("library", ""))
	if split.has("") or split.is_empty() or split.size() > LibraryPartial.MAX_LIBRARIES:
		errors.append(
			{"code": LibraryPartial.E_EXTRA, "text": "the bundle holds stray or no libraries"}
		)
		return out
	if not split.has(requested):
		errors.append(
			{
				"code": LibraryPartial.E_ID,
				"text": "the host did not send the library '%s' that was asked for" % requested
			}
		)
		return out
	var expect := {
		"official_ids": ctx.get("official_ids", official_ids()),
		"surfaces": ctx.get("surfaces", PaletteLibrary.get_palette()["surfaces"]),
		"dependencies": {},
	}
	var order: Array = split.keys()
	order.sort()
	var reads := {}
	var allowed_extra: Array[String] = []
	for id: String in order:
		var mine := expect.duplicate()
		mine["id"] = id
		mine["wanted_version"] = String(ctx.get("wanted_version", "")) if id == requested else ""
		var checked := LibraryPartial.inspect(split[id], mine)
		for error: Dictionary in checked["errors"]:
			errors.append({"code": error["code"], "text": "%s: %s" % [id, error["text"]]})
		reads[id] = checked
		if id == requested and checked["ok"]:
			allowed_extra = LibraryPartial.dependency_ids(checked["library"])
	for id: String in order:
		if id != requested and not id in allowed_extra:
			errors.append(
				{
					"code": LibraryPartial.E_ID,
					"text":
					"the bundle holds '%s', which is not a dependency of '%s'" % [id, requested]
				}
			)
	if not errors.is_empty():
		return out
	return _install(split, reads, ctx, out)


static func _install(
	split: Dictionary, reads: Dictionary, ctx: Dictionary, out: Dictionary
) -> Dictionary:
	var root := String(ctx.get("root", LibraryRegistry.received_root()))
	var now := int(ctx.get("now", Time.get_unix_time_from_system()))
	var total := 0
	var count := 0
	for id: String in split:
		for data: PackedByteArray in (split[id] as Dictionary).values():
			total += data.size()
		count += (split[id] as Dictionary).size()
	var keep: Array[String] = []
	keep.assign(split.keys())
	var cap := int(ctx.get("cap", LibraryReceivedStore.CACHE_CAP_BYTES))
	LibraryReceivedStore.evict_to_fit(total, keep, cap, root)
	var written: Array[String] = []
	for id: String in split:
		var problem := LibraryReceivedStore.write_library(
			root, id, split[id], now, reads[id]["library"]
		)
		if problem != "":
			for done in written:
				LibraryReceivedStore.remove(done, root)
			(out["errors"] as Array).append({"code": "io", "text": problem})
			return out
		written.append(id)
	out["libraries"] = written
	out["bytes"] = total
	out["files"] = count
	out["ok"] = true
	return out


## The ids of libraries that ship with the game (official folders) and core.
static func official_ids() -> Array[String]:
	var out: Array[String] = [LibraryContracts.CORE_ID]
	for info: Dictionary in LibraryRegistry.list():
		if bool(info.get("official", false)) and not info["id"] in out:
			out.append(String(info["id"]))
	return out


## True when received library `id` is still a partial one (library.json carries the block).
static func is_partial(library: Dictionary) -> bool:
	return library.get(LibraryPartial.PARTIAL_KEY) is Dictionary


static func format_bytes(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
	if bytes >= 1024:
		return "%d KB" % int(ceil(float(bytes) / 1024.0))
	return "%d bytes" % bytes


static func _fail(out: Dictionary, code: String, text: String) -> Dictionary:
	out["code"] = code
	out["error"] = text
	return out
