class_name BiomeCompiler
extends RefCounted

## Compiles a read library (LibraryReader.read's result) into exactly the palette form
## PaletteLibrary validates and the scatter solver consumes: the `biomes` list and the `assets`
## table of a palette.json, one palette biome per season, in the same dictionaries a treecube or
## plantgen package carries, plus the authoring fields the palette does not read yet (`role`,
## `habit`, `weight`, `library` on a rule, `library` on a biome). validate_palette drops those
## silently until the step that makes the scatter code read them extends its whitelist (S2).
##
## This build compiles the minimal subset (design doc 6.1): rules select assets by explicit
## `query.match[].ref` only, numbers are explicit (a missing density takes the class default
## times `density_factor`), seasons are expanded without overrides, surfaces are the base
## palette's names (`surfaces: legacy`). Pure: no files, no scene tree. Asset `file` values stay
## library-relative (the palette contract); `paths` carries the absolute file of each asset,
## joined from the library folder, never the other way round.

const PALETTE_FORMAT := 1


## compile(read, options) -> {palette (a palette.json-shaped Dictionary), paths ({asset id:
## absolute file}), biome_ids, library (the id), warnings (compile problems), palette_warnings
## (PaletteLibrary.validate_palette's on `palette`)}. `read` must be an ok LibraryReader result;
## otherwise the result is empty with the warning saying so. options: {"folder": the library
## folder (absolute), "surfaces": the surface table the biomes' names resolve against (the base
## palette's), "hash": a short content hash for palette_version}.
static func compile(read: Dictionary, options: Dictionary = {}) -> Dictionary:
	var warnings: Array[String] = []
	var result := {
		"palette": {},
		"paths": {},
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
	var paths := {}
	for item: Dictionary in read["biomes"]:
		var def: Dictionary = item["def"]
		var seasons: Array = def.get("seasons", [{"id": "summer", "seed": 1}])
		for season: Dictionary in seasons:
			var biome := _compile_biome(
				def, season, library_id, read["catalog"], assets, paths, folder, warnings
			)
			if not biome.is_empty():
				biomes.append(biome)
				(result["biome_ids"] as Array[String]).append(String(biome["id"]))
	var version := "%s@%s" % [library_id, String(library.get("version", ""))]
	if String(options.get("hash", "")) != "":
		version += "+" + String(options["hash"])
	var palette := {
		"format": PALETTE_FORMAT,
		"palette_version": version,
		"surfaces": (options.get("surfaces", {}) as Dictionary).duplicate(true),
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
	library_id: String,
	catalog: Dictionary,
	assets: Dictionary,
	paths: Dictionary,
	folder: String,
	warnings: Array[String]
) -> Dictionary:
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
	for raw: Dictionary in def["rules"]:
		var rule := _compile_rule(raw, runtime, library_id, catalog, role_of, used, warnings)
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
		var entry: Dictionary = catalog[used[asset_id]]
		var dims: Array = entry["dimensions_m"]
		assets[asset_id] = {
			"file": entry["file"],
			"node": entry["node"],
			"wind_category": entry["wind_category"],
			"size_class": entry["size_class"],
			"dimensions_m": [dims[0], dims[1], dims[2]],
		}
		if folder != "":
			paths[asset_id] = folder.path_join(String(entry["file"]))
	return _biome_fields(def, season, runtime, library_id, rules)


static func _biome_fields(
	def: Dictionary,
	season: Dictionary,
	runtime: String,
	library_id: String,
	rules: Array[Dictionary]
) -> Dictionary:
	var biome_name := String(def["id"])
	var ground: Dictionary = def.get("ground", {})
	var biome := {
		"id": runtime,
		"biome": LibraryIds.biome_field(library_id, biome_name),
		"season": String(season.get("id", "summer")),
		"seed": int(season.get("seed", 1)),
		"name": String(def.get("name", biome_name)),
		"climate": String(def.get("climate", "")),
		"thumbnail": String((def.get("legacy", {}) as Dictionary).get("thumbnail", "")),
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
			biome[map[source]] = _copy(ground[source])
	if def.get("ground_look") is Dictionary:
		biome["ground_look"] = _copy(def["ground_look"])
	return biome


## One palette species rule from a biome-def rule, or {} when none of its refs resolve.
static func _compile_rule(
	raw: Dictionary,
	runtime: String,
	library_id: String,
	catalog: Dictionary,
	role_of: Dictionary,
	used: Dictionary,
	warnings: Array[String]
) -> Dictionary:
	var key := String(raw["key"])
	var role := String(raw["role"])
	var size_class := String(raw.get("size_class", LibraryContracts.size_class_of(role)))
	var defaults := LibraryContracts.class_defaults(size_class)
	var label := "biome %s rule %s" % [runtime, key]
	var assets: Array[String] = []
	for clause: Variant in (raw["query"] as Dictionary).get("match", []):
		if not clause is Dictionary or not (clause as Dictionary).get("ref") is String:
			continue
		var ref := String((clause as Dictionary)["ref"])
		if not catalog.has(ref):
			warnings.append("%s: ref '%s' is not in the catalog (skipped)" % [label, ref])
			continue
		if not LibraryIds.asset_id_fits(runtime, ref):
			warnings.append("%s: asset id for '%s' is too long (skipped)" % [label, ref])
			continue
		var asset_id := LibraryIds.runtime_asset(runtime, ref)
		if not asset_id in assets:
			assets.append(asset_id)
			used[asset_id] = ref
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
	return rule


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
