class_name BiomeCompiler
extends RefCounted

## Compiles a read library (LibraryReader.read's result) into exactly the palette form
## PaletteLibrary validates and the scatter solver consumes: the `biomes` list and the `assets`
## table of a palette.json, one palette biome per season, in the same dictionaries a treecube or
## plantgen package carries, plus the authoring fields `role`, `habit`, `weight` and `library`
## on a rule and `library` on a biome. validate_palette keeps `role`, `habit` and `weight` of a
## rule since S2 (PaletteValidator._library_fields; the scatter code reads `habit` through
## ScatterGround.habit_of) and still drops `library` silently: each new field is whitelisted in
## the step that makes the scatter code read it.
##
## This build compiles the minimal subset (design doc 6.1): rules select assets by explicit
## `query.match[].ref` only, numbers are explicit (a missing density takes the class default
## times `density_factor`), seasons are expanded with their overrides (BiomeSeasons, S9: the
## ground, the ground look, the density scale and per-rule fields by season), surfaces are the base
## palette's names (`surfaces: legacy`) or, with `surfaces: library`, resolved against the
## library's own surfaces/ folder first (S3; resolve_surface). Pure: no files, no scene tree.
## Asset `file` values stay library-relative (the palette contract); `paths` carries the
## absolute file of each asset, joined from the library folder, never the other way round.

const PALETTE_FORMAT := 1


## compile(read, options) -> {palette (a palette.json-shaped Dictionary; its `surfaces` are the
## base table plus the library's own, as `surfaces/<runtime name>/<map>.png` paths SurfaceStore
## resolves), paths ({asset id: absolute file}), surfaces ({runtime name: {library, name, info,
## maps}} of the library's own, for SurfaceStore.register_library), biome_ids, library (the id),
## warnings (compile problems), palette_warnings (PaletteLibrary.validate_palette's on
## `palette`), origins ({asset id: {library, file, node, sha256, bytes, path}}: where each asset's
## GLB lives and which library supplied it, the dependency's for a `<lib>:<id>` ref; what
## AssetStore.register_library takes), thumbnails ({palette-relative thumbnail path: absolute
## file} of the biomes that ship their own picture)}. `read` must be an ok LibraryReader result;
## otherwise the result is empty with the warning saying so. options: {"folder": the library
## folder (absolute), "surfaces": the surface table the biomes' names resolve against (the base
## palette's), "hash": a short content hash for palette_version, "files": the library's file
## list (a biome thumbnail is used only when it is listed), "dependencies": {library id:
## {"read": that library's LibraryReader result, "folder": its folder}} for every declared
## dependency that is available (a `<lib>:<id>` ref and a `lib://<lib>/<surface>` reference
## resolve through it)}.
static func compile(read: Dictionary, options: Dictionary = {}) -> Dictionary:
	var warnings: Array[String] = []
	var result := {
		"palette": {},
		"paths": {},
		"origins": {},
		"thumbnails": {},
		"surfaces": {},
		"biome_ids": [] as Array[String],
		"library": "",
		"warnings": warnings,
		"palette_warnings": [] as Array[String],
	}
	if not read.get("ok", false):
		warnings.append("library was not read cleanly; nothing compiled")
		return result
	var library: Dictionary = read["library"]
	var library_id := String(library["id"])
	var folder := String(options.get("folder", ""))
	var biomes: Array[Dictionary] = []
	var assets := {}
	var table := (options.get("surfaces", {}) as Dictionary).duplicate(true)
	var own := _library_surfaces(read, library_id, table, result)
	var context := {
		"library": library_id,
		"own": own,
		"table": table,
		"catalog": read["catalog"],
		"folder": folder,
		"deps": options.get("dependencies", {}),
		"files": options.get("files", []),
		"origins": result["origins"],
		"thumbnails": result["thumbnails"],
		"locks": read.get("locks", {}),
	}
	for item: Dictionary in read["biomes"]:
		var def: Dictionary = item["def"]
		var seasons: Array = def.get("seasons", [{"id": "summer", "seed": 1}])
		for season: Dictionary in seasons:
			var biome := _compile_biome(def, season, context, assets, warnings)
			if not biome.is_empty():
				biomes.append(biome)
				(result["biome_ids"] as Array[String]).append(String(biome["id"]))
	var paths := {}
	for asset_id: String in result["origins"]:
		if String(result["origins"][asset_id]["path"]) != "":
			paths[asset_id] = result["origins"][asset_id]["path"]
	var version := "%s@%s" % [library_id, String(library.get("version", ""))]
	if String(options.get("hash", "")) != "":
		version += "+" + String(options["hash"])
	var palette := {
		"format": PALETTE_FORMAT,
		"palette_version": version,
		"surfaces": table,
		"biomes": biomes,
		"assets": assets,
	}
	result["palette"] = palette
	result["paths"] = paths
	result["library"] = library_id
	result["palette_warnings"] = PaletteLibrary.validate_palette(palette)["warnings"]
	return result


## One palette biome of `def` for one season, or {} when no rule survives.
static func _compile_biome(
	def: Dictionary,
	season: Dictionary,
	surface_context: Dictionary,
	assets: Dictionary,
	warnings: Array[String]
) -> Dictionary:
	# The season's own overrides (BiomeSeasons): the def itself when it has none.
	def = BiomeSeasons.effective(def, String(season.get("id", "summer")))
	var library_id := String(surface_context["library"])
	var biome_name := String(def["id"])
	var seed_value := int(season.get("seed", 1))
	var runtime := LibraryIds.runtime_biome(
		library_id, biome_name, String(season.get("id", "summer")), seed_value
	)
	var role_of := {}
	for rule: Dictionary in def["rules"]:
		role_of[String(rule["key"])] = String(rule["role"])
	var rules: Array[Dictionary] = []
	var used := {}
	var scope := {
		"biome": biome_name,
		"season": String(season.get("id", "summer")),
		"locks":
		((surface_context.get("locks", {}) as Dictionary).get(biome_name, {}) as Dictionary).get(
			"rules", {}
		),
	}
	for raw: Dictionary in def["rules"]:
		var rule := _compile_rule(raw, runtime, surface_context, role_of, used, warnings, scope)
		if not rule.is_empty():
			rules.append(rule)
	if rules.is_empty():
		warnings.append("biome %s: no rule selects any asset; skipped" % runtime)
		return {}
	var kept := {}
	for rule: Dictionary in rules:
		kept[rule["key"]] = true
	_drop_dangling(rules, kept, runtime, warnings)
	for asset_id: String in used:
		var found: Dictionary = used[asset_id]
		var entry: Dictionary = found["entry"]
		var dims: Array = entry["dimensions_m"]
		assets[asset_id] = {
			"file": entry["file"],
			"node": entry["node"],
			"wind_category": entry["wind_category"],
			"size_class": entry["size_class"],
			"dimensions_m": [dims[0], dims[1], dims[2]],
		}
		var folder := String(found["folder"])
		(surface_context["origins"] as Dictionary)[asset_id] = {
			"library": found["library"],
			"file": entry["file"],
			"node": entry["node"],
			"sha256": String(entry.get("sha256", "")),
			"bytes": int(entry.get("bytes", 0)),
			"path": folder.path_join(String(entry["file"])) if folder != "" else "",
		}
	return _biome_fields(def, season, runtime, surface_context, rules, warnings)


## The library's own surfaces laid into `table` (the palette's surface table, by runtime name)
## and recorded in result.surfaces ({runtime name: {library, name, info, maps}}). Returns
## {local name: runtime name}.
static func _library_surfaces(
	read: Dictionary, library_id: String, table: Dictionary, result: Dictionary
) -> Dictionary:
	var own := {}
	var recorded := {}
	for name: String in read.get("surface_order", []):
		var found: Dictionary = (read["surfaces"] as Dictionary)[name]
		var runtime := LibraryIds.runtime_surface(library_id, name)
		own[name] = runtime
		table[runtime] = SurfaceBake.palette_entry(runtime, found["info"], found["maps"])
		recorded[runtime] = {
			"library": library_id, "name": name, "info": found["info"], "maps": found["maps"]
		}
	result["surfaces"] = recorded
	return own


## The runtime surface name `ref` stands for in a `surfaces: library` biome: a `lib://` reference
## or a plain name that is one of the library's own surfaces becomes its runtime name; any other
## plain name is the installed palette's (kept as written). A name in neither the library nor the
## table is kept with a warning, and the palette validator then blanks it.
static func resolve_surface(
	ref: Variant, surface_context: Dictionary, label: String, warnings: Array[String]
) -> Variant:
	if not ref is String:
		warnings.append("%s: a surface reference is not a string (dropped)" % label)
		return null
	var library_id := String(surface_context["library"])
	var own: Dictionary = surface_context["own"]
	var table: Dictionary = surface_context["table"]
	var name := String(ref)
	var parsed := LibraryIds.parse_surface_ref(name)
	if name.begins_with(LibraryIds.SURFACE_SCHEME) and parsed.is_empty():
		warnings.append("%s: '%s' is not a lib://<library>/<surface> reference" % [label, name])
		return name
	if not parsed.is_empty():
		if parsed["library"] == library_id:
			name = String(parsed["name"])
		elif parsed["library"] == LibraryContracts.CORE_ID:
			return _known(parsed["name"], table, label, warnings)
		elif (surface_context.get("deps", {}) as Dictionary).has(parsed["library"]):
			var runtime := LibraryIds.runtime_surface(parsed["library"], parsed["name"])
			return _known(runtime, table, label, warnings)
		else:
			warnings.append(
				"%s: '%s' names a library this one does not depend on" % [label, name]
			)
			return name
	if own.has(name):
		return own[name]
	return _known(name, table, label, warnings)


static func _known(
	name: String, table: Dictionary, label: String, warnings: Array[String]
) -> String:
	if not table.has(name):
		warnings.append(
			"%s: surface '%s' is not in the library's surfaces/ or the palette" % [label, name]
		)
	return name


## The biome's `ground` references as the palette stores them: `legacy` copies the names
## verbatim, `library` resolves each (resolve_surface), accents' surfaces and paths included.
static func _ground_value(
	source: String,
	value: Variant,
	mode: String,
	surface_context: Dictionary,
	label: String,
	warnings: Array[String]
) -> Variant:
	if mode != LibraryReader.SURFACES_LIBRARY:
		return _copy(value)
	var here := "%s ground.%s" % [label, source]
	match source:
		"accents":
			var accents := []
			for raw: Variant in value if value is Array else []:
				if not raw is Dictionary:
					continue
				var entry := (raw as Dictionary).duplicate(true)
				var surface: Variant = resolve_surface(
					entry.get("surface"), surface_context, here, warnings
				)
				if surface != null:
					entry["surface"] = surface
					accents.append(entry)
			return accents
		"paths":
			var names := []
			for raw: Variant in value if value is Array else []:
				var surface: Variant = resolve_surface(raw, surface_context, here, warnings)
				if surface != null:
					names.append(surface)
			return names
	var resolved: Variant = resolve_surface(value, surface_context, here, warnings)
	return resolved if resolved != null else ""


## The palette `thumbnail` of a biome: its own picture (the biome-def's `thumbnail`, a listed
## library file) as the palette-relative path `thumbnails/<runtime id>.<ext>` that SurfaceStore
## serves from the library folder (recorded in context.thumbnails), else the legacy palette
## thumbnail the biome-def names, else "".
static func _thumbnail(def: Dictionary, runtime: String, context: Dictionary) -> String:
	var own: Variant = def.get("thumbnail")
	var folder := String(context.get("folder", ""))
	if own is String and folder != "" and LibraryIds.path_problems(own).is_empty():
		var extension := String(own).get_extension().to_lower()
		if extension in ["jpg", "png"] and String(own) in (context.get("files", []) as Array):
			var relative := "thumbnails/%s.%s" % [runtime, extension]
			(context["thumbnails"] as Dictionary)[relative] = folder.path_join(own)
			return relative
	return String((def.get("legacy", {}) as Dictionary).get("thumbnail", ""))


static func _biome_fields(
	def: Dictionary,
	season: Dictionary,
	runtime: String,
	surface_context: Dictionary,
	rules: Array[Dictionary],
	warnings: Array[String]
) -> Dictionary:
	var library_id := String(surface_context["library"])
	var mode := String(def.get("surfaces", LibraryReader.SURFACES_LEGACY))
	var biome_name := String(def["id"])
	var ground: Dictionary = def.get("ground", {})
	var biome := {
		"id": runtime,
		"biome": LibraryIds.biome_field(library_id, biome_name),
		"season": String(season.get("id", "summer")),
		"seed": int(season.get("seed", 1)),
		"name": String(def.get("name", biome_name)),
		"climate": String(def.get("climate", "")),
		"thumbnail": _thumbnail(def, runtime, surface_context),
		"library": library_id,
		"species": rules,
	}
	var map := {
		"surface": "ground_surface",
		"cliff": "cliff_surface",
		"scree": "scree_surface",
		"water_bed": "water_bed_surface",
		"shore": "shore_surface",
		"accents": "ground_accents",
		"paths": "path_surfaces",
	}
	for source: String in map:
		if ground.has(source):
			biome[map[source]] = _ground_value(
				source, ground[source], mode, surface_context, "biome " + runtime, warnings
			)
	if def.get("ground_look") is Dictionary:
		biome["ground_look"] = _copy(def["ground_look"])
	return biome


## The catalog entry a query ref names: {library, local (the id the asset takes in the biome's
## asset ids), entry, folder (of the library that holds the GLB)}, or {} with a warning. A plain
## ref is this library's catalog; `<lib>:<id>` is a declared dependency's, through that library's
## `aliases` (an old id) and refused when its `retired` list holds the id.
static func resolve_ref(
	ref: String, context: Dictionary, label: String, warnings: Array[String]
) -> Dictionary:
	var parts := LibraryIds.split_ref(ref)
	var library := String(parts.get("library", ""))
	var own_id := String(context["library"])
	if library == "" or library == own_id:
		var catalog: Dictionary = context["catalog"]
		var local := String(parts.get("local", ref))
		if not catalog.has(local):
			warnings.append("%s: ref '%s' is not in the catalog (skipped)" % [label, ref])
			return {}
		return {
			"library": own_id,
			"local": local,
			"entry": catalog[local],
			"folder": String(context.get("folder", "")),
		}
	var deps: Dictionary = context.get("deps", {})
	if not deps.has(library):
		warnings.append(
			"%s: ref '%s' names a library this one does not depend on (skipped)" % [label, ref]
		)
		return {}
	var dep: Dictionary = deps[library]
	var dep_read: Dictionary = dep["read"]
	var wanted := LibraryIds.resolve_alias(
		_aliases_of(dep_read["library"]), String(parts["local"])
	)
	if wanted in _retired_of(dep_read["library"]):
		warnings.append("%s: '%s' is retired in %s (skipped)" % [label, ref, library])
		return {}
	var dep_catalog: Dictionary = dep_read["catalog"]
	if not dep_catalog.has(wanted):
		warnings.append("%s: ref '%s' is not in the catalog of %s (skipped)" % [label, ref, library])
		return {}
	return {
		"library": library,
		"local": LibraryIds.dependency_local(library, wanted),
		"entry": dep_catalog[wanted],
		"folder": String(dep.get("folder", "")),
	}


## The `aliases` of a read library.json ({old: new}), only the string pairs.
static func _aliases_of(library: Dictionary) -> Dictionary:
	var out := {}
	var raw: Variant = library.get("aliases")
	if raw is Dictionary:
		for old: Variant in raw as Dictionary:
			if (raw as Dictionary)[old] is String:
				out[String(old)] = (raw as Dictionary)[old]
	return out


static func _retired_of(library: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = library.get("retired")
	if raw is Array:
		for item: Variant in raw as Array:
			if item is String:
				out.append(item)
	return out


## One palette species rule from a biome-def rule, or {} when none of its refs resolve.
static func _compile_rule(
	raw: Dictionary,
	runtime: String,
	context: Dictionary,
	role_of: Dictionary,
	used: Dictionary,
	warnings: Array[String],
	scope: Dictionary = {}
) -> Dictionary:
	var library_id := String(context["library"])
	var key := String(raw["key"])
	var role := String(raw["role"])
	var size_class := String(raw.get("size_class", LibraryContracts.size_class_of(role)))
	var defaults := LibraryContracts.class_defaults(size_class)
	var label := "biome %s rule %s" % [runtime, key]
	var assets := _rule_assets(raw, runtime, context, used, warnings, scope)
	if assets.is_empty():
		warnings.append("%s: no asset resolves; rule dropped" % label)
		return {}
	var density: Variant = raw.get("density_per_m2")
	if density == null:
		density = float(defaults.get("density_per_m2", 0.0)) * float(raw.get("density_factor", 1.0))
		warnings.append("%s: no density_per_m2, using the %s class default" % [label, size_class])
	var rule := {
		"key": key,
		"kind": LibraryContracts.kind_of(role),
		"size_class": size_class,
		"density_per_m2": density,
		"min_spacing_m": _number(raw, "spacing_m", defaults, "spacing_m"),
		"slope_max_deg": _number(raw, "slope_max_deg", defaults, "slope_max_deg"),
		"scale_spread": _number(raw, "scale_spread", defaults, "scale_spread"),
		"scale_floor": _copy(raw.get("scale_floor")),
		"yaw_random_deg": _number(raw, "yaw_random_deg", defaults, "yaw_random_deg"),
		"align": String(raw.get("align", LibraryContracts.align_of(role))),
		"pattern": _copy(raw.get("pattern")),
		"clump": _copy(raw.get("clump")),
		"near": _relations(raw.get("near"), key, role_of),
		"avoid": _relations(raw.get("avoid"), key, role_of),
		"assets": assets,
		"role": role,
		"habit": LibraryContracts.habit_for(role, raw.get("habit")),
		"weight": float(raw.get("weight", 1.0)),
		"library": library_id,
	}
	for field: String in ["avoid_bare", "keep_colour"]:
		if raw.has(field) and raw[field] != null:
			rule[field] = raw[field]
	# Terrain response (S12): carried only when the rule has it, so legacy rules compile as before.
	for field: String in ["slope_min_deg", "response"]:
		if raw.has(field) and raw[field] != null:
			rule[field] = _copy(raw[field])
	return rule


## The runtime asset ids of a rule's query, in order (`used` records each one's source): the
## `ref` clauses first, as listed (a ref naming a group stands for its variants), then the
## selection of the filter clauses and pins (LibraryQuery.select), capped at
## LibraryContracts.QUERY_MAX_ASSETS in all.
static func _rule_assets(
	raw: Dictionary,
	runtime: String,
	context: Dictionary,
	used: Dictionary,
	warnings: Array[String],
	scope: Dictionary
) -> Array[String]:
	var key := String(raw["key"])
	var label := "biome %s rule %s" % [runtime, key]
	var query: Dictionary = raw["query"]
	var wanted: Array[Dictionary] = []
	for clause: Variant in query.get("match", []):
		if not clause is Dictionary or not (clause as Dictionary).get("ref") is String:
			continue
		var ref := String((clause as Dictionary)["ref"])
		var members := LibraryQuery.group_members(ref, context)
		if not members.is_empty():
			for member in members:
				wanted.append({"ref": ref, "found": member})
			continue
		var found := resolve_ref(ref, context, label, warnings)
		if not found.is_empty():
			wanted.append({"ref": ref, "found": found})
	if LibraryQuery.has_selection(query):
		var season := String(scope.get("season", "summer"))
		var picked := LibraryQuery.select(
			query,
			context,
			{
				"biome": String(scope.get("biome", "")),
				"rule": key,
				"season": season,
				"label": label,
				"lock": (scope.get("locks", {}) as Dictionary).get("%s/%s" % [season, key]),
			},
			warnings
		)
		for found: Dictionary in picked["found"]:
			wanted.append({"ref": String(found["ref"]), "found": found})
	var assets: Array[String] = []
	for item in wanted:
		var found: Dictionary = item["found"]
		var local := String(found["local"])
		if not LibraryIds.asset_id_fits(runtime, local):
			warnings.append("%s: asset id for '%s' is too long (skipped)" % [label, item["ref"]])
			continue
		var asset_id := LibraryIds.runtime_asset(runtime, local)
		if used.has(asset_id) and used[asset_id]["entry"] != found["entry"]:
			warnings.append(
				"%s: '%s' collides with another asset id (skipped)" % [label, item["ref"]]
			)
			continue
		if not asset_id in assets:
			assets.append(asset_id)
			used[asset_id] = found
	if assets.size() > LibraryContracts.QUERY_MAX_ASSETS:
		var cap := LibraryContracts.QUERY_MAX_ASSETS
		warnings.append("%s: %d assets; the first %d are kept" % [label, assets.size(), cap])
		assets.resize(LibraryContracts.QUERY_MAX_ASSETS)
	return assets


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


static func _number(
	raw: Dictionary, field: String, defaults: Dictionary, default_field: String
) -> Variant:
	if raw.get(field) != null:
		return raw[field]
	return defaults.get(default_field)


## A biome-def relation list in the palette's form: `rule` becomes `species`, and a `role`
## target expands to every other rule of that role.
static func _relations(items: Variant, own_key: String, role_of: Dictionary) -> Array:
	var out := []
	if not items is Array:
		return out
	for raw: Dictionary in items:
		var entry := raw.duplicate(true)
		var targets: Array[String] = []
		if entry.has("role"):
			for key: String in role_of:
				if role_of[key] == entry["role"] and key != own_key:
					targets.append(key)
			entry.erase("role")
		elif entry.has("rule"):
			targets.append(String(entry["rule"]))
			entry.erase("rule")
		for target in targets:
			var copy := entry.duplicate(true)
			copy["species"] = target
			out.append(copy)
	return out


## Removes relations to rules that were dropped from the biome, with a warning each.
static func _drop_dangling(
	rules: Array[Dictionary], kept: Dictionary, runtime: String, warnings: Array[String]
) -> void:
	for rule: Dictionary in rules:
		for field: String in ["near", "avoid"]:
			var live := []
			for relation: Dictionary in rule[field]:
				if kept.has(relation["species"]):
					live.append(relation)
				else:
					warnings.append(
						(
							"biome %s rule %s: %s relation to '%s' dropped (no such rule)"
							% [runtime, rule["key"], field, relation["species"]]
						)
					)
			rule[field] = live
