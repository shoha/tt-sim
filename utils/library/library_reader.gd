class_name LibraryReader
extends RefCounted

## Parses and validates the files of one content library: library.json, assets/catalog.json and
## biomes/*.json (design doc 2.3, 2.5, 2.6, 2.10). Pure: it is handed the TEXT of each file and
## the list of relative file paths, never a folder (LibraryRegistry is the only module that
## scans or reads), so every check is testable with strings. Everything read is untrusted input:
## sizes are capped before parsing, wrong types are reported, and nothing here ever raises.
##
## read(sources) returns {ok, errors, warnings, library, catalog, catalog_order, biomes}. Any
## error blocks the library (ok false); warnings never do. Unknown keys are WARNINGS here
## because PaletteLibrary.validate_palette drops them silently, so this is the one place a typo
## in a biome-def is caught. sources:
##   {"library": String, "catalog": String, "biomes": {"<file name>": String},
##    "files": Array of every library-relative file path (optional; enables the extension,
##    portable-name, case and existence checks, and the surfaces below),
##    "surfaces": {"<surface name>": the text of its surface.json} and
##    "png": {"<library-relative .png path>": SurfaceBake.png_header's result} (both optional;
##    LibraryRegistry reads the first 33 bytes of each map)}
## The result also holds `surfaces` ({name: {info, maps}} for each valid surfaces/<name>/ set,
## `maps` the kinds present) and `surface_order`.

const BIOME_DIR := "biomes/"
const SURFACE_DIR := "surfaces/"
## A biome-def's `surfaces`: names resolve against the installed palette ("legacy", the
## default) or against the library's own surfaces/ folder first ("library").
const SURFACES_LEGACY := "legacy"
const SURFACES_LIBRARY := "library"


static func read(sources: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"library": {},
		"catalog": {},
		"catalog_order": [] as Array[String],
		"biomes": [] as Array[Dictionary],
		"surfaces": {},
		"surface_order": [] as Array[String],
	}
	var errors: Array[String] = result["errors"]
	var warnings: Array[String] = result["warnings"]
	var files: Array = sources.get("files", []) if sources.get("files") is Array else []
	var have_files := sources.get("files") is Array
	if have_files:
		_check_files(files, errors)
	var library := _parse(
		String(sources.get("library", "")),
		"library.json",
		LibraryContracts.CAPS["library_json_bytes"],
		errors
	)
	result["library"] = library
	if not library.is_empty():
		check_library(library, errors, warnings)
	var catalog_text := String(sources.get("catalog", ""))
	var catalog := _parse(
		catalog_text, "assets/catalog.json", LibraryContracts.CAPS["catalog_bytes"], errors
	)
	if not catalog.is_empty():
		_read_catalog(catalog, files if have_files else [], have_files, result)
		_check_stats(library, result, warnings)
	var biomes: Variant = sources.get("biomes", {})
	if biomes is Dictionary:
		var names: Array = (biomes as Dictionary).keys()
		names.sort()
		if names.size() > int(LibraryContracts.CAPS["biomes"]):
			errors.append(
				(
					"biomes: %d files over the cap of %d"
					% [names.size(), LibraryContracts.CAPS["biomes"]]
				)
			)
			names = names.slice(0, int(LibraryContracts.CAPS["biomes"]))
		for file_name: String in names:
			var def := _parse(
				String((biomes as Dictionary)[file_name]),
				BIOME_DIR + file_name,
				LibraryContracts.CAPS["biome_bytes"],
				errors
			)
			if def.is_empty():
				continue
			if check_biome(def, file_name, errors, warnings):
				(result["biomes"] as Array[Dictionary]).append({"file": file_name, "def": def})
	if have_files:
		_read_surfaces(sources, files, result)
	result["ok"] = errors.is_empty() and not library.is_empty() and not catalog.is_empty()
	return result


## Fills result.surfaces from the library's surfaces/ folder (SurfaceReader).
static func _read_surfaces(sources: Dictionary, files: Array, result: Dictionary) -> void:
	var texts: Variant = sources.get("surfaces", {})
	var headers: Variant = sources.get("png", {})
	var read := SurfaceReader.read(
		files,
		texts if texts is Dictionary else {},
		headers if headers is Dictionary else {},
		result["errors"],
		result["warnings"]
	)
	result["surfaces"] = read["surfaces"]
	result["surface_order"] = read["order"]


## The JSON object in `text`, or {} with an error appended.
static func _parse(text: String, label: String, cap: int, errors: Array[String]) -> Dictionary:
	if text == "":
		errors.append("%s is missing or empty" % label)
		return {}
	if text.to_utf8_buffer().size() > cap:
		errors.append("%s is over %d bytes" % [label, cap])
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append(
			(
				"%s is not valid JSON (line %d: %s)"
				% [label, json.get_error_line(), json.get_error_message()]
			)
		)
		return {}
	if not json.data is Dictionary:
		errors.append("%s is not a JSON object" % label)
		return {}
	return json.data


# ---- the file list ----


static func _check_files(files: Array, errors: Array[String]) -> void:
	var names: Array = []
	for raw: Variant in files:
		var path := String(raw)
		names.append(path)
		for problem in LibraryIds.path_problems(path):
			errors.append("file %s: %s" % [path, problem])
		var extension := "." + path.get_extension().to_lower()
		if not extension in LibraryContracts.EXTENSIONS:
			errors.append("file %s: extension is not allowed" % path)
	for dup in LibraryIds.case_duplicates(names):
		errors.append("file %s: collides with another file when case is ignored" % dup)


# ---- library.json ----


## Checks a parsed library.json. Errors block the library, warnings do not.
static func check_library(
	library: Dictionary, errors: Array[String], warnings: Array[String]
) -> void:
	_unknown(library, LibraryContracts.LIBRARY_KEYS, "library.json", warnings)
	if library.get("format") != LibraryContracts.FORMAT_LIBRARY:
		errors.append("library.json: format must be '%s'" % LibraryContracts.FORMAT_LIBRARY)
	_check_format_version(library, "library.json", errors)
	var id: Variant = library.get("id")
	if not id is String:
		errors.append("library.json: id is missing")
	else:
		for problem in LibraryIds.library_problems(id):
			errors.append("library.json: " + problem)
	var contract: Variant = library.get("contract")
	if not _is_whole(contract) or int(contract) < 1:
		errors.append("library.json: contract must be a whole number from 1")
	elif int(contract) > LibraryContracts.CONTRACT_VERSION:
		errors.append(
			(
				"library.json: written for contract %d, this build reads up to %d"
				% [int(contract), LibraryContracts.CONTRACT_VERSION]
			)
		)
	var version: Variant = library.get("version")
	if not version is String or not LibraryIds.is_semver(version):
		warnings.append("library.json: version is not a semantic version")
	for field in ["name", "description", "author", "license", "url"]:
		var limit := (
			LibraryContracts.MAX_DESCRIPTION_LENGTH
			if field == "description"
			else LibraryContracts.MAX_TEXT_LENGTH
		)
		var value: Variant = library.get(field)
		if value != null and (not value is String or String(value).length() > limit):
			warnings.append(
				"library.json: %s is not a string of at most %d characters" % [field, limit]
			)
	for problem: String in (
		LibraryBindings.flatten(library.get("bindings"), library.get("default_biome"))["problems"]
	):
		warnings.append("library.json: " + problem)
	var deps: Variant = library.get("dependencies", [])
	if not deps is Array or (deps as Array).size() > LibraryContracts.MAX_DEPENDENCIES:
		errors.append(
			(
				"library.json: dependencies must be a list of at most %d"
				% LibraryContracts.MAX_DEPENDENCIES
			)
		)
	elif not (deps as Array).is_empty():
		warnings.append("library.json: dependencies are not resolved in this build (ignored)")


static func _check_format_version(data: Dictionary, label: String, errors: Array[String]) -> void:
	var version: Variant = data.get("format_version")
	if not _is_whole(version) or int(version) < 1:
		errors.append("%s: format_version must be a whole number from 1" % label)
	elif int(version) > LibraryContracts.FORMAT_VERSION:
		errors.append(
			(
				"%s: format_version %d is newer than this build reads (%d)"
				% [label, int(version), LibraryContracts.FORMAT_VERSION]
			)
		)


# ---- assets/catalog.json ----


static func _read_catalog(
	catalog: Dictionary, files: Array, have_files: bool, result: Dictionary
) -> void:
	var errors: Array[String] = result["errors"]
	var warnings: Array[String] = result["warnings"]
	_unknown(catalog, LibraryContracts.CATALOG_KEYS, "catalog.json", warnings)
	if catalog.get("format") != LibraryContracts.FORMAT_CATALOG:
		errors.append("catalog.json: format must be '%s'" % LibraryContracts.FORMAT_CATALOG)
	_check_format_version(catalog, "catalog.json", errors)
	var entries: Variant = catalog.get("assets")
	if not entries is Array:
		errors.append("catalog.json: assets is missing or not a list")
		return
	var cap := int(LibraryContracts.CAPS["assets"])
	if (entries as Array).size() > cap:
		errors.append(
			"catalog.json: %d assets over the cap of %d" % [(entries as Array).size(), cap]
		)
		return
	var by_id: Dictionary = result["catalog"]
	var order: Array[String] = result["catalog_order"]
	var folded_ids := {}
	var folded_files := {}
	var known_files := {}
	for raw: Variant in files:
		known_files[String(raw)] = true
	for raw: Variant in entries as Array:
		if not raw is Dictionary:
			errors.append("catalog.json: an entry is not an object")
			continue
		var entry: Dictionary = raw
		var id := String(entry.get("id", "")) if entry.get("id") is String else ""
		var label := "catalog %s" % (id if id != "" else "(no id)")
		var before := errors.size()
		_unknown(entry, LibraryContracts.CATALOG_ENTRY_KEYS, label, warnings)
		for problem in LibraryIds.local_problems(id):
			errors.append("%s: %s" % [label, problem])
		if folded_ids.has(id.to_lower()):
			errors.append("%s: id repeats (case-insensitively)" % label)
		folded_ids[id.to_lower()] = true
		_check_entry_fields(entry, label, errors)
		var file := String(entry.get("file", "")) if entry.get("file") is String else ""
		for problem in LibraryIds.path_problems(file):
			errors.append("%s: file %s" % [label, problem])
		if file.get_extension().to_lower() != "glb":
			errors.append("%s: file '%s' is not a .glb" % [label, file])
		if folded_files.has(file.to_lower()):
			errors.append("%s: file '%s' is used by another entry" % [label, file])
		folded_files[file.to_lower()] = true
		if have_files and not known_files.has(file):
			var near := files.filter(
				func(f: Variant) -> bool: return String(f).to_lower() == file.to_lower()
			)
			var hint := (
				" (the file list has '%s': names are case-sensitive in a shipped game)" % near[0]
				if not near.is_empty()
				else ""
			)
			errors.append("%s: file '%s' does not exist%s" % [label, file, hint])
		if errors.size() == before:
			by_id[id] = entry
			order.append(id)


static func _check_entry_fields(entry: Dictionary, label: String, errors: Array[String]) -> void:
	if not _one_of(entry.get("category"), LibraryContracts.CATEGORIES):
		errors.append("%s: category must be one of %s" % [label, LibraryContracts.CATEGORIES])
	if not _one_of(entry.get("size_class"), LibraryContracts.SIZE_CLASSES):
		errors.append("%s: size_class must be one of %s" % [label, LibraryContracts.SIZE_CLASSES])
	if not _one_of(entry.get("wind_category"), LibraryContracts.WIND_CATEGORIES):
		errors.append("%s: wind_category must be tree, grass or empty" % label)
	var node: Variant = entry.get("node")
	if not node is String or node == "" or String(node).length() > LibraryContracts.MAX_TEXT_LENGTH:
		errors.append("%s: node must be a node name" % label)
	var dims: Variant = entry.get("dimensions_m")
	var ok := dims is Array and (dims as Array).size() == 3
	if ok:
		for value: Variant in dims as Array:
			ok = ok and _is_num(value) and float(value) > 0.0
	if not ok:
		errors.append("%s: dimensions_m must be three finite positive numbers" % label)


static func _check_stats(library: Dictionary, result: Dictionary, warnings: Array[String]) -> void:
	var stats: Variant = library.get("stats")
	if stats is Dictionary and (stats as Dictionary).has("assets"):
		var count := (result["catalog_order"] as Array).size()
		if (
			_is_whole((stats as Dictionary)["assets"])
			and int((stats as Dictionary)["assets"]) != count
		):
			warnings.append(
				(
					"library.json: stats.assets is %d but the catalog has %d"
					% [int((stats as Dictionary)["assets"]), count]
				)
			)


# ---- biomes/*.json ----


## Checks a parsed biome-def; true when it is usable. `file_name` is the file under biomes/.
static func check_biome(
	def: Dictionary, file_name: String, errors: Array[String], warnings: Array[String]
) -> bool:
	var where := BIOME_DIR + file_name
	var before := errors.size()
	_unknown(def, LibraryContracts.BIOME_KEYS, where, warnings)
	if def.get("format") != LibraryContracts.FORMAT_BIOME:
		errors.append("%s: format must be '%s'" % [where, LibraryContracts.FORMAT_BIOME])
	_check_format_version(def, where, errors)
	var id := String(def.get("id", "")) if def.get("id") is String else ""
	for problem in LibraryIds.biome_problems(id):
		errors.append("%s: %s" % [where, problem])
	if id != file_name.get_basename():
		errors.append("%s: id '%s' does not match the file name" % [where, id])
	_check_seasons(def, where, errors, warnings)
	var ground: Variant = def.get("ground", {})
	if not ground is Dictionary:
		errors.append("%s: ground must be an object" % where)
	else:
		_unknown(ground, LibraryContracts.GROUND_KEYS, where + " ground", warnings)
	if def.get("ground_look") != null and not def.get("ground_look") is Dictionary:
		errors.append("%s: ground_look must be an object" % where)
	var surfaces: Variant = def.get("surfaces", SURFACES_LEGACY)
	if not surfaces is String or not surfaces in [SURFACES_LEGACY, SURFACES_LIBRARY]:
		warnings.append(
			(
				"%s: surfaces '%s' is not '%s' or '%s', treated as legacy"
				% [where, str(surfaces), SURFACES_LEGACY, SURFACES_LIBRARY]
			)
		)
	var rules: Variant = def.get("rules")
	if not rules is Array or (rules as Array).is_empty():
		errors.append("%s: rules must be a non-empty list" % where)
		return false
	if (rules as Array).size() > int(LibraryContracts.CAPS["rules_per_biome"]):
		errors.append(
			(
				"%s: %d rules over the cap of %d"
				% [where, (rules as Array).size(), LibraryContracts.CAPS["rules_per_biome"]]
			)
		)
		return false
	var keys := {}
	for raw: Variant in rules as Array:
		if raw is Dictionary and (raw as Dictionary).get("key") is String:
			keys[(raw as Dictionary)["key"]] = true
	var seen := {}
	for raw: Variant in rules as Array:
		if not raw is Dictionary:
			errors.append("%s: a rule is not an object" % where)
			continue
		var key := (
			String((raw as Dictionary).get("key", ""))
			if (raw as Dictionary).get("key") is String
			else ""
		)
		if key == "" or key.length() > LibraryContracts.MAX_TEXT_LENGTH or seen.has(key):
			errors.append("%s: rule key '%s' is empty, too long or repeated" % [where, key])
		seen[key] = true
		_check_rule(raw, "%s rule '%s'" % [where, key], keys, errors, warnings)
	return errors.size() == before


static func _check_seasons(
	def: Dictionary, where: String, errors: Array[String], warnings: Array[String]
) -> void:
	var seasons: Variant = def.get("seasons", [{"id": "summer", "seed": 1}])
	if (
		not seasons is Array
		or (seasons as Array).is_empty()
		or (seasons as Array).size() > LibraryContracts.MAX_SEASONS
	):
		errors.append(
			"%s: seasons must be a list of 1 to %d" % [where, LibraryContracts.MAX_SEASONS]
		)
		return
	var seen := {}
	for raw: Variant in seasons as Array:
		if not raw is Dictionary:
			errors.append("%s: a season is not an object" % where)
			continue
		var season: Dictionary = raw
		var id := String(season.get("id", "")) if season.get("id") is String else ""
		for problem in LibraryIds.season_problems(id):
			errors.append("%s: %s" % [where, problem])
		if seen.has(id):
			errors.append("%s: season '%s' repeats" % [where, id])
		seen[id] = true
		if not _is_whole(season.get("seed")):
			errors.append("%s: season '%s' needs a whole-number seed" % [where, id])
		for extra: String in season:
			if not extra in ["id", "seed", "overrides"]:
				warnings.append("%s: season key '%s' is unknown" % [where, extra])
		if (
			season.get("overrides") is Dictionary
			and not (season["overrides"] as Dictionary).is_empty()
		):
			warnings.append("%s: season '%s' overrides are not applied in this build" % [where, id])


static func _check_rule(
	rule: Dictionary,
	label: String,
	keys: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	_unknown(rule, LibraryContracts.RULE_KEYS, label, warnings)
	var role := String(rule.get("role", "")) if rule.get("role") is String else ""
	if not LibraryContracts.has_role(role):
		errors.append("%s: unknown role '%s'" % [label, role])
	if rule.has("size_class") and not _one_of(rule["size_class"], LibraryContracts.SIZE_CLASSES):
		errors.append("%s: size_class must be one of %s" % [label, LibraryContracts.SIZE_CLASSES])
	_check_number(rule, "weight", 0.0, 1000000.0, false, label, errors)
	_check_number(rule, "density_per_m2", 0.0, 1000.0, true, label, errors)
	_check_number(rule, "density_factor", 0.0, 1000.0, true, label, errors)
	_check_number(rule, "spacing_m", 0.0, 1000.0, true, label, errors)
	_check_number(rule, "slope_max_deg", 0.0, 90.0, true, label, errors)
	_check_number(rule, "slope_min_deg", 0.0, 90.0, true, label, errors)
	_check_response(rule.get("response"), label, errors, warnings)
	_check_number(rule, "scale_spread", 0.0, 0.9, true, label, errors)
	_check_number(rule, "scale_floor", 0.0, 100.0, true, label, errors)
	_check_number(rule, "yaw_random_deg", 0.0, 360.0, true, label, errors)
	_check_number(rule, "avoid_bare", 0.0, 1.0, true, label, errors)
	if rule.get("align") != null and not _one_of(rule.get("align"), LibraryContracts.ALIGNS):
		errors.append("%s: align must be upright or normal" % label)
	if rule.get("keep_colour") != null and not rule.get("keep_colour") is bool:
		errors.append("%s: keep_colour must be true or false" % label)
	for object_field in ["pattern", "clump"]:
		if rule.get(object_field) != null and not rule.get(object_field) is Dictionary:
			errors.append("%s: %s must be an object or null" % [label, object_field])
	_check_habit(rule.get("habit"), label, errors, warnings)
	for relation_field in ["near", "avoid"]:
		_check_relations(rule.get(relation_field), relation_field, label, keys, errors, warnings)
	_check_query(rule.get("query"), label, errors, warnings)


## A rule's `response` (S12): an object of axis -> curve; a malformed curve is an error (an
## authored library fails loudly), an unknown axis a warning, and an axis this build does not
## evaluate yet (LibraryContracts.RESPONSE_UNSUPPORTED) a warning too.
static func _check_response(
	response: Variant, label: String, errors: Array[String], warnings: Array[String]
) -> void:
	if response == null:
		return
	if not response is Dictionary:
		errors.append("%s: response must be an object of axis -> curve" % label)
		return
	for axis: Variant in response as Dictionary:
		var axis_name := String(axis)
		if not LibraryContracts.RESPONSE_AXES.has(axis_name):
			warnings.append(
				"%s: response axis '%s' is unknown (ignored)" % [label, _short(axis_name)]
			)
			continue
		var problem := LibraryContracts.response_problem(axis_name, (response as Dictionary)[axis])
		if problem != "":
			errors.append("%s: response.%s %s" % [label, axis_name, problem])
		elif axis_name in LibraryContracts.RESPONSE_UNSUPPORTED:
			warnings.append(
				"%s: response.%s is not evaluated in this build (ignored)" % [label, axis_name]
			)


static func _check_habit(
	habit: Variant, label: String, errors: Array[String], warnings: Array[String]
) -> void:
	if habit == null:
		return
	if not habit is Dictionary:
		errors.append("%s: habit must be an object" % label)
		return
	_unknown(habit, ["water", "charred"], label + " habit", warnings)
	if (
		(habit as Dictionary).has("water")
		and not _one_of((habit as Dictionary)["water"], LibraryContracts.HABIT_WATER)
	):
		errors.append("%s: habit.water must be one of %s" % [label, LibraryContracts.HABIT_WATER])
	if (habit as Dictionary).has("charred") and not (habit as Dictionary)["charred"] is bool:
		errors.append("%s: habit.charred must be true or false" % label)


static func _check_relations(
	items: Variant,
	field: String,
	label: String,
	keys: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if items == null:
		return
	if not items is Array or (items as Array).size() > 32:
		errors.append("%s: %s must be a list of at most 32" % [label, field])
		return
	for raw: Variant in items as Array:
		if not raw is Dictionary:
			errors.append("%s: a %s entry is not an object" % [label, field])
			continue
		var item: Dictionary = raw
		_unknown(
			item,
			["rule", "role", "distance_m", "transition_m", "influence"],
			label + " " + field,
			warnings
		)
		if item.get("role") is String:
			if not LibraryContracts.has_role(item["role"]):
				errors.append("%s: %s names unknown role '%s'" % [label, field, item["role"]])
		elif item.get("rule") is String:
			if not keys.has(item["rule"]):
				warnings.append(
					(
						"%s: %s target '%s' is not a rule of this biome (dropped)"
						% [label, field, item["rule"]]
					)
				)
		else:
			errors.append("%s: a %s entry needs a rule or a role" % [label, field])
		for number_field in ["distance_m", "transition_m"]:
			_check_number(item, number_field, 0.0, 1000.0, true, label + " " + field, errors)
		_check_number(item, "influence", 0.0, 1.0, true, label + " " + field, errors)


static func _check_query(
	query: Variant, label: String, errors: Array[String], warnings: Array[String]
) -> void:
	if not query is Dictionary:
		errors.append("%s: query is missing" % label)
		return
	_unknown(query, LibraryContracts.QUERY_KEYS, label + " query", warnings)
	var clauses: Variant = (query as Dictionary).get("match")
	if not clauses is Array or (clauses as Array).is_empty():
		errors.append("%s: query.match must list at least one ref" % label)
		return
	if (clauses as Array).size() > int(LibraryContracts.CAPS["assets_per_rule"]):
		errors.append(
			"%s: query.match is over %d entries" % [label, LibraryContracts.CAPS["assets_per_rule"]]
		)
		return
	for raw: Variant in clauses as Array:
		if not raw is Dictionary or not (raw as Dictionary).get("ref") is String:
			warnings.append(
				"%s: only {ref} clauses are compiled in this build (clause skipped)" % label
			)
			continue
		for problem in LibraryIds.local_problems((raw as Dictionary)["ref"]):
			errors.append("%s: ref: %s" % [label, problem])


# ---- helpers ----


static func _check_number(
	data: Dictionary,
	field: String,
	low: float,
	high: float,
	nullable: bool,
	label: String,
	errors: Array[String]
) -> void:
	if not data.has(field):
		return
	var value: Variant = data[field]
	if value == null and nullable:
		return
	if not _is_num(value) or float(value) < low or float(value) > high:
		errors.append("%s: %s must be a number from %s to %s" % [label, field, str(low), str(high)])


static func _unknown(
	data: Dictionary, allowed: Array[String], label: String, warnings: Array[String]
) -> void:
	for key: Variant in data:
		if not String(key) in allowed:
			warnings.append("%s: unknown key '%s' (ignored)" % [label, _short(String(key))])


## Whether `value` is a String listed in `allowed` (a typed-array `in` errors on other types).
static func _one_of(value: Variant, allowed: Array[String]) -> bool:
	return value is String and allowed.has(value)


static func _is_num(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _is_whole(value: Variant) -> bool:
	return _is_num(value) and float(value) == floorf(float(value))


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
