class_name LibraryIds
extends RefCounted

## The id grammar of the content library and the one mapping from library-level ids to the
## runtime ids the palette, the map document and the scatter code use (design doc 2.4 and the
## S0 probe P4/P5). Pure and static.
##
## Runtime ids: the core library keeps today's ids unchanged (`savanna_summer_s1`, assets
## `savanna_summer_s1/Tree_Acacia_v0`) so every saved map keeps opening; any other library is
## prefixed `<lib>__<biome>_<season>_s<seed>`. Rules the S0 probes established:
## no `/` inside a library id, biome name or local asset id (an asset id has exactly one slash,
## and the biome is read back as the part before it); no `__` in a library id or biome name (it
## separates the library); the whole asset id stays under PaletteLibrary.MAX_ID_LENGTH; and
## every season and seed gets its own asset-id prefix (live edits accept an asset only when its
## prefix is the whole biome id). Portable names: nothing that cannot exist on every platform
## (case-insensitive duplicates, Windows device names, a trailing dot or space, a backslash or
## drive letter) and short relative paths.

const SEPARATOR := "__"
const SURFACE_SCHEME := "lib://"
const MAX_ASSET_ID_LENGTH := 160

static var _library_re: RegEx = _compile("^[a-z][a-z0-9_-]{1,31}$")
static var _biome_re: RegEx = _compile("^[a-z][a-z0-9_]*$")
static var _season_re: RegEx = _compile("^[a-z][a-z0-9]{0,15}$")
static var _local_re: RegEx = _compile("^[A-Za-z0-9_]+$")
static var _semver_re: RegEx = _compile("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.]+)?$")
static var _sha_re: RegEx = _compile("^[0-9a-f]{64}$")
static var _runtime_re: RegEx = _compile("^([a-z][a-z0-9_]*)_([a-z][a-z0-9]{0,15})_s(-?[0-9]+)$")


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


## Problems with a library id (empty when it is fine). `core` is allowed; legacy, draft and dev
## are tt-sim's own.
static func library_problems(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _library_re.search(id) == null:
		out.append("library id '%s' must match [a-z][a-z0-9_-]{1,31}" % _short(id))
	elif SEPARATOR in id:
		out.append("library id '%s' contains '__'" % id)
	elif id in LibraryContracts.RESERVED_LIBRARY_IDS:
		out.append("library id '%s' is reserved" % id)
	return out


## Problems with a biome's local name (it becomes part of a runtime id).
static func biome_problems(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _biome_re.search(name) == null or name.length() > LibraryContracts.MAX_BIOME_NAME:
		out.append("biome id '%s' must match [a-z][a-z0-9_]* (at most 48)" % _short(name))
	elif SEPARATOR in name:
		out.append("biome id '%s' contains '__'" % name)
	return out


static func season_problems(season: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _season_re.search(season) == null:
		out.append("season id '%s' must match [a-z][a-z0-9]{0,15}" % _short(season))
	return out


## Problems with a library-local asset id (a catalog id or a ref): letters, digits and
## underscores, no slash, at most 64, and a portable file stem.
static func local_problems(local: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _local_re.search(local) == null or local.length() > LibraryContracts.MAX_LOCAL_ID:
		out.append("asset id '%s' must match [A-Za-z0-9_]+ (at most 64)" % _short(local))
	elif local.to_lower() in LibraryContracts.RESERVED_DEVICE_NAMES:
		out.append("asset id '%s' is a reserved device name" % local)
	return out


static func is_semver(version: String) -> bool:
	return _semver_re.search(version) != null


## True for a lower-case SHA-256 hex digest (64 characters).
static func is_sha256(text: String) -> bool:
	return _sha_re.search(text) != null


## {library, local} of a query ref: `Tree_Oak_v0` is a local id (library ""), `core:Tree_Oak_v0`
## names an asset of a dependency. {} when the text has more than one colon.
static func split_ref(ref: String) -> Dictionary:
	if ref.count(":") > 1:
		return {}
	if ref.count(":") == 1:
		return {"library": ref.get_slice(":", 0), "local": ref.get_slice(":", 1)}
	return {"library": "", "local": ref}


## Problems with a query ref: a local id, or `<library id>:<local id>` for a dependency's asset.
static func ref_problems(ref: String) -> PackedStringArray:
	var out := PackedStringArray()
	var parts := split_ref(ref)
	if parts.is_empty():
		out.append("ref '%s' has more than one colon" % _short(ref))
		return out
	var library := String(parts["library"])
	if library != "":
		out.append_array(library_problems(library))
	elif ":" in ref:
		out.append("ref '%s' names no library before the colon" % _short(ref))
	out.append_array(local_problems(String(parts["local"])))
	return out


## The local id a dependency's asset takes in the depending library's biome:
## `<library id>__<local id>`, so it can never equal a local asset id of the library's own that
## has no double underscore (the compiler skips a collision with a warning).
static func dependency_local(library: String, local: String) -> String:
	return library + SEPARATOR + local


## The palette biome id: `<biome>_<season>_s<seed>` for core, `<lib>__<biome>_<season>_s<seed>`
## for any other library.
static func runtime_biome(
	library: String, biome: String, season: String, seed_value: int
) -> String:
	var id := "%s_%s_s%d" % [biome, season, seed_value]
	return id if library == LibraryContracts.CORE_ID else library + SEPARATOR + id


## The palette rule/biome `biome` field: the bare name for core, `<lib>__<biome>` otherwise, so
## code comparing it with a bare name never matches another library's biome of that name.
static func biome_field(library: String, biome: String) -> String:
	return biome if library == LibraryContracts.CORE_ID else library + SEPARATOR + biome


## The palette asset id `<runtime biome id>/<local id>`.
static func runtime_asset(runtime_biome_id: String, local: String) -> String:
	return "%s/%s" % [runtime_biome_id, local]


## The palette surface name: bare for core, `<lib>__<name>` otherwise.
static func runtime_surface(library: String, surface: String) -> String:
	return surface if library == LibraryContracts.CORE_ID else library + SEPARATOR + surface


## The surface reference string of library surface `name`: `lib://<library id>/<name>`. A string
## convention only (nothing registers a scheme): SurfaceStore and the compiler read it.
static func surface_ref(library: String, name: String) -> String:
	return SURFACE_SCHEME + library + "/" + name


## {library, name} of a `lib://<library id>/<name>` reference, or {} for anything else (a plain
## legacy surface name, a malformed or hostile string). Both parts are grammar-checked.
static func parse_surface_ref(ref: String) -> Dictionary:
	if not ref.begins_with(SURFACE_SCHEME):
		return {}
	var rest := ref.substr(SURFACE_SCHEME.length())
	if rest.count("/") != 1:
		return {}
	var library := rest.get_slice("/", 0)
	var name := rest.get_slice("/", 1)
	if _library_re.search(library) == null or SEPARATOR in library:
		return {}
	if not surface_problems(name).is_empty():
		return {}
	return {"library": library, "name": name}


## Problems with a library-local surface name (a `surfaces/<name>/` folder): it becomes part of
## the runtime surface name and of a cache file name, so lower case, no `__`, no device name.
static func surface_problems(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _biome_re.search(name) == null or name.length() > LibraryContracts.MAX_BIOME_NAME:
		out.append("surface name '%s' must match [a-z][a-z0-9_]* (at most 48)" % _short(name))
	elif SEPARATOR in name:
		out.append("surface name '%s' contains '__'" % name)
	elif name in LibraryContracts.RESERVED_DEVICE_NAMES:
		out.append("surface name '%s' is a reserved device name" % name)
	return out


## True when the whole palette asset id fits (PaletteLibrary rejects 160 and over).
static func asset_id_fits(runtime_biome_id: String, local: String) -> bool:
	return runtime_biome_id.length() + 1 + local.length() < MAX_ASSET_ID_LENGTH


## The library an id belongs to: the part before `__` in a runtime biome id or the biome half
## of an asset id; ids without one belong to core.
static func library_of(runtime_id: String) -> String:
	var biome_half := runtime_id.get_slice("/", 0)
	if SEPARATOR in biome_half:
		return biome_half.get_slice(SEPARATOR, 0)
	return LibraryContracts.CORE_ID


## {library, biome, season, seed} of a runtime biome id, or {} when it does not parse.
static func parse_runtime_biome(runtime_id: String) -> Dictionary:
	var library := LibraryContracts.CORE_ID
	var rest := runtime_id
	if SEPARATOR in runtime_id:
		library = runtime_id.get_slice(SEPARATOR, 0)
		rest = runtime_id.substr(library.length() + SEPARATOR.length())
		if SEPARATOR in rest:
			return {}
	var found := _runtime_re.search(rest)
	if found == null:
		return {}
	return {
		"library": library,
		"biome": found.get_string(1),
		"season": found.get_string(2),
		"seed": int(found.get_string(3)),
	}


## `id` through a library's `aliases` ({old: new}), following at most a few renames.
static func resolve_alias(aliases: Dictionary, id: String) -> String:
	var seen := 0
	while aliases.has(id) and seen < 8:
		id = String(aliases[id])
		seen += 1
	return id


## Problems with one path segment (a file or directory name): empty, a dot segment, a control
## character, a backslash or colon, a trailing dot or space, or a Windows device name (also
## with an extension: `con.json`).
static func segment_problems(segment: String) -> PackedStringArray:
	var out := PackedStringArray()
	if segment == "" or segment == "." or segment == "..":
		out.append("'%s' is not a usable name" % segment)
		return out
	for i in segment.length():
		if segment.unicode_at(i) < 32:
			out.append("'%s' contains a control character" % _short(segment))
			return out
	if "\\" in segment or ":" in segment:
		out.append("'%s' contains a backslash or colon" % _short(segment))
	if segment.ends_with(".") or segment.ends_with(" "):
		out.append("'%s' ends with a dot or space" % _short(segment))
	if segment.begins_with(" "):
		out.append("'%s' begins with a space" % _short(segment))
	if segment.get_slice(".", 0).to_lower() in LibraryContracts.RESERVED_DEVICE_NAMES:
		out.append("'%s' is a reserved device name" % _short(segment))
	return out


## Problems with a library-relative path: absolute, a scheme, a drive letter, a backslash, a
## parent segment, an over-long path, or a non-portable segment.
static func path_problems(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if path == "":
		out.append("empty path")
		return out
	if path.begins_with("/") or ":" in path or "\\" in path:
		out.append("'%s' is absolute, has a drive or scheme, or a backslash" % _short(path))
		return out
	if path.length() > LibraryContracts.MAX_RELATIVE_PATH:
		out.append(
			"'%s' is over %d characters" % [_short(path), LibraryContracts.MAX_RELATIVE_PATH]
		)
	for segment in path.split("/"):
		out.append_array(segment_problems(segment))
	return out


## The names that collide with an earlier one when case is ignored (the later spelling is
## reported once), in input order. Two spellings of one name are one file on Windows.
static func case_duplicates(names: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for raw: Variant in names:
		var name := String(raw)
		var folded := name.to_lower()
		if seen.has(folded):
			if not name in out:
				out.append(name)
		else:
			seen[folded] = name
	return out


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
