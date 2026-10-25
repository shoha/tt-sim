class_name MapLibraries
extends RefCounted

## What a map says about the content libraries it uses, and what to do when this install does
## not match (design doc 2.4 and 2.11). The manifest of `map.ttmap` carries
## `libraries: [{id, version, hash}]`, one per library whose biome, asset or surface the map
## holds (the id's prefix names the library: LibraryIds.library_of). The format number is 2
## while only `core` is used and 3 (MapDocument.FORMAT_LIBRARIES) when any other library is,
## so a build that knows no libraries refuses the document instead of reading its prefixed ids
## as unknown plants and dropping them on its next save.
##
## Reading a map: check() compares the record with the libraries served now (LibraryRegistry)
## and returns what is missing or incompatible; the open flow shows that to the user
## (LibraryMismatchDialog) and, if they choose "Open without those plants", calls
## without_libraries() on the document: the rows of those libraries are dropped, their biomes
## fall back to the default biome, and nothing is silently substituted otherwise. A map with no
## `libraries` record (saved before libraries) counts as core only.
##
## The functions that take a document are pure over the document; the ones that look a library
## up read LibraryRegistry's served state. Nothing here touches the scene tree.

## Library id -> display text the dialog uses when the library is not installed at all.
const NOT_INSTALLED := "not installed"


## The library ids `doc` uses, sorted: the prefix of every biome id, scatter and props asset id
## and painted surface name (a name without a `<lib>__` prefix is core's).
static func used_ids(doc: MapDocument) -> Array[String]:
	var seen := {}
	for biome_id in doc.biome_ids:
		seen[LibraryIds.library_of(biome_id)] = true
	for source: Dictionary in [doc.scatter, doc.props]:
		for asset_id: String in source:
			seen[LibraryIds.library_of(asset_id)] = true
	for surface in doc.surface_ids:
		seen[surface_library(surface)] = true
	if doc.base_surface != "":
		seen[surface_library(doc.base_surface)] = true
	var out: Array[String] = []
	out.assign(seen.keys())
	out.sort()
	return out


## The library a palette surface name belongs to: the part before `__`, else core.
static func surface_library(surface: String) -> String:
	if LibraryIds.SEPARATOR in surface:
		return surface.get_slice(LibraryIds.SEPARATOR, 0)
	return LibraryContracts.CORE_ID


## The `libraries` list to write for `doc`: {id, version, hash} per used library as the
## registry serves it now. A library the registry does not serve keeps what the document read
## from its file (so a map opened without a library's plants still names it until it is saved
## over), else version and hash "". Core is named only when the map holds something.
static func record_for(doc: MapDocument) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in used_ids(doc):
		var served := LibraryRegistry.record_of(id)
		if served.is_empty():
			served = {"id": id, "version": "", "hash": ""}
			for claimed in doc.libraries:
				if claimed.get("id") == id:
					served = claimed.duplicate()
		out.append(served)
	return out


## The format number to write for a `libraries` list: FORMAT_LIBRARIES when any is not core.
static func format_for(libraries: Array[Dictionary]) -> int:
	for item in libraries:
		if item.get("id") != LibraryContracts.CORE_ID:
			return MapDocument.FORMAT_LIBRARIES
	return MapDocument.FORMAT


## What this install makes of the document's `libraries` record (`libraries`, the claimed list):
## {ok (nothing missing or incompatible), missing: [{id, version, name, url, reason}],
## incompatible: [{id, wanted, have, name}], warnings: [text], blocked: [library ids that cannot
## be used]}. A library is "missing" when it is not served: not installed, disabled, or failed
## (reason says which). It is "incompatible" when the served version has another major. A newer
## minor or patch opens fine; a different hash at the same version only warns (a library being
## edited). Pure of the document; reads LibraryRegistry's served state.
static func check(libraries: Array[Dictionary]) -> Dictionary:
	var out := {
		"ok": true, "missing": [], "incompatible": [], "warnings": [] as Array[String], "blocked": []
	}
	for claimed in libraries:
		var id := String(claimed.get("id", ""))
		var wanted := String(claimed.get("version", ""))
		var served := LibraryRegistry.record_of(id)
		if served.is_empty():
			var found := LibraryRegistry.info(id)
			(out["missing"] as Array).append(
				{
					"id": id,
					"version": wanted,
					"name": String(found.get("name", id)),
					"author": String(found.get("author", "")),
					"url": String(found.get("url", "")),
					"reason": _why_missing(found),
				}
			)
			(out["blocked"] as Array).append(id)
			continue
		var have := String(served.get("version", ""))
		var wanted_parts := LibraryVersions.parse(wanted)
		var have_parts := LibraryVersions.parse(have)
		if (
			not wanted_parts.is_empty()
			and not have_parts.is_empty()
			and wanted_parts["major"] != have_parts["major"]
		):
			(out["incompatible"] as Array).append(
				{"id": id, "wanted": wanted, "have": have, "name": id}
			)
			(out["blocked"] as Array).append(id)
		elif wanted == have and String(claimed.get("hash", "")) not in ["", String(served["hash"])]:
			(out["warnings"] as Array[String]).append(
				"library %s %s differs from the version this map was saved with" % [id, have]
			)
	out["ok"] = (out["missing"] as Array).is_empty() and (out["incompatible"] as Array).is_empty()
	return out


static func _why_missing(found: Dictionary) -> String:
	if found.is_empty():
		return NOT_INSTALLED
	if found["status"] == LibraryResolver.DISABLED:
		return "installed but turned off"
	var reasons: Array = found.get("reasons", [])
	return String(reasons[0]) if not reasons.is_empty() else "it could not be loaded"


## One line for the dialog: "alienworld 0.3.1 (not installed)" per missing or incompatible
## library, joined with newlines.
static func describe(report: Dictionary) -> String:
	var lines: Array[String] = []
	for item: Dictionary in report["missing"]:
		var line := "%s %s (%s)" % [item["name"], item["version"], item["reason"]]
		if String(item.get("author", "")) != "":
			line += ", by %s" % item["author"]
		lines.append(line)
	for item: Dictionary in report["incompatible"]:
		lines.append("%s: the map was saved with %s, this game has %s" % [
			item["id"], item["wanted"], item["have"]
		])
	return "\n".join(lines)


## Drops what the libraries `blocked` supply from `doc`, for "Open without those plants": their
## scatter and prop rows go, and each of their biome ids becomes `fallback_biome` (their painting
## keeps its slots). Returns {rows (scatter and prop rows removed), biomes (ids replaced)}. A
## `fallback_biome` that is not in the palette leaves the biome ids as they were.
static func without_libraries(
	doc: MapDocument, blocked: Array, fallback_biome: String
) -> Dictionary:
	var rows := 0
	for source: Dictionary in [doc.scatter, doc.props]:
		for asset_id: String in source.keys():
			if LibraryIds.library_of(asset_id) in blocked:
				rows += (source[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
				source.erase(asset_id)
	var replaced := 0
	if fallback_biome != "":
		for i in doc.biome_ids.size():
			if LibraryIds.library_of(doc.biome_ids[i]) in blocked:
				doc.biome_ids[i] = fallback_biome
				replaced += 1
	if replaced > 0:
		doc.mass_anchors = {}
	return {"rows": rows, "biomes": replaced}


## Renames the document's scatter and prop asset ids and biome ids through the served
## libraries' `aliases` (a library renamed an id and kept the old one as an alias): the rows
## move to the new id (joined with rows already there), biome ids follow. Returns how many ids
## were renamed. Ids that are not served, have no alias, or whose target is not in the palette
## are left as they were.
static func apply_aliases(doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT) -> int:
	var renamed := 0
	for source: Dictionary in [doc.scatter, doc.props]:
		for asset_id: String in source.keys():
			var now := LibraryRegistry.resolve_asset_alias(asset_id, root)
			if now == asset_id:
				continue
			var moved: PackedFloat32Array = source[asset_id]
			source.erase(asset_id)
			var joined: PackedFloat32Array = source.get(now, PackedFloat32Array())
			joined.append_array(moved)
			source[now] = joined
			renamed += 1
	for i in doc.biome_ids.size():
		var biome := LibraryRegistry.resolve_biome_alias(doc.biome_ids[i], root)
		if biome != doc.biome_ids[i]:
			doc.biome_ids[i] = biome
			renamed += 1
	return renamed
