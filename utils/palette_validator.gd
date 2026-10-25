class_name PaletteValidator
extends PaletteSurfaces

## Validation of a parsed palette.json (assets, biomes, species rules and their relations),
## split out of PaletteLibrary (step S2 of the content library, docs/systems/library.md).
## PaletteLibrary.validate_palette delegates here. Everything read is untrusted: counts and
## lengths are capped, wrong types rejected field by field, a malformed entry skipped with a
## warning, nothing raises. The rule fields the scatter code reads (including the library's
## `role`, `habit` and `weight`) are a WHITELIST here: a field not read in
## _validate_species is dropped silently, so each new compiled field is added in the step that
## makes the scatter code read it.


## Validates a parsed palette.json document. Pure: returns {"palette": Dictionary,
## "warnings": Array[String]} and never touches files, caches or the log.
##
## The palette is always well-formed, even for garbage input:
## {"format": int, "palette_version": String, "surfaces": Dictionary,
##  "biomes": Array[Dictionary], "assets": Dictionary}. Assets are validated first, so a
## species keeps only asset ids that resolve, and a species left with none is dropped.
static func validate_palette(data: Variant) -> Dictionary:
	var warnings: Array[String] = []
	var palette := empty_palette()
	if not data is Dictionary:
		warnings.append("palette.json is not a JSON object")
		return {"palette": palette, "warnings": warnings}
	var format: Variant = data.get("format")
	if not (format is float or format is int) or int(format) != FORMAT:
		warnings.append("unsupported palette format %s (expected %d)" % [str(format), FORMAT])
		return {"palette": palette, "warnings": warnings}
	palette["palette_version"] = _text_or(data.get("palette_version"), MAX_TEXT_LENGTH, "")
	palette["surfaces"] = _validate_surfaces(data.get("surfaces"), warnings)
	palette["assets"] = _validate_assets(data.get("assets"), warnings)
	palette["biomes"] = _validate_biomes(
		data.get("biomes"), palette["assets"], palette["surfaces"], warnings
	)
	return {"palette": palette, "warnings": warnings}


## A well-formed palette with nothing in it.
static func empty_palette() -> Dictionary:
	var no_biomes: Array[Dictionary] = []
	return {
		"format": FORMAT, "palette_version": "", "surfaces": {}, "biomes": no_biomes, "assets": {}
	}


static func _validate_assets(raw: Variant, warnings: Array[String]) -> Dictionary:
	var result := {}
	if not raw is Dictionary:
		warnings.append("assets is missing or not an object")
		return result
	for id in _capped_keys(raw, MAX_ASSETS, "assets", warnings):
		var entry: Variant = raw[id]
		if not _is_asset_id(id) or not entry is Dictionary:
			warnings.append("asset '%s' skipped: malformed id or entry" % _label(id))
			continue
		var file := _path_or(entry.get("file"), "")
		var node: Variant = _text(entry.get("node"), MAX_TEXT_LENGTH)
		if file == "" or not file.to_lower().ends_with(".glb") or node == null or node == "":
			warnings.append("asset '%s' skipped: needs a .glb file and a node name" % id)
			continue
		var category: Variant = entry.get("wind_category")
		if not category is String or not category in WIND_CATEGORIES:
			# An unknown category (a newer producer) still places the asset, just still.
			warnings.append("asset '%s': unknown wind_category, treated as none" % id)
			category = ""
		result[id] = {
			"file": file,
			"node": node,
			"wind_category": category,
			"size_class": _text_or(entry.get("size_class"), MAX_TEXT_LENGTH, ""),
			"dimensions_m": _vector3_or_zero(entry.get("dimensions_m")),
		}
	return result


static func _validate_biomes(
	raw: Variant, assets: Dictionary, known: Dictionary, warnings: Array[String]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		warnings.append("biomes is missing or not an array")
		return result
	var seen := {}
	for entry in _capped(raw, MAX_BIOMES, "biomes", warnings):
		var id: Variant = _text(entry.get("id") if entry is Dictionary else null, MAX_ID_LENGTH)
		if id == null or id == "" or seen.has(id):
			warnings.append("biome '%s' skipped: missing or duplicate id" % _label(id))
			continue
		seen[id] = true
		var ground := _text_or(entry.get("ground_surface"), MAX_TEXT_LENGTH, "")
		if ground != "" and not known.has(ground):
			warnings.append("biome '%s': ground surface '%s' not in surfaces" % [id, ground])
			ground = ""
		var seed_value: Variant = _number(entry.get("seed"), -2147483648.0, 2147483647.0)
		var species_rules := _validate_species_list(entry.get("species"), id, assets, warnings)
		if species_rules.is_empty():
			warnings.append("biome '%s' skipped: no usable species" % id)
			continue
		(
			result
			. append(
				{
					"id": id,
					"biome": _text_or(entry.get("biome"), MAX_TEXT_LENGTH, ""),
					"season": _text_or(entry.get("season"), MAX_TEXT_LENGTH, ""),
					"seed": int(seed_value) if seed_value != null else 0,
					"name": _text_or(entry.get("name"), MAX_TEXT_LENGTH, id),
					"climate": _text_or(entry.get("climate"), MAX_TEXT_LENGTH, ""),
					"thumbnail": _path_or(entry.get("thumbnail"), ""),
					"ground_surface": ground,
					"cliff_surface": _cliff_surface_of(entry, id, known, warnings),
					"scree_surface": _scree_surface_of(entry, id, known, warnings),
					"water_bed_surface":
					_water_surface_of(entry, id, "water_bed_surface", 0, known, warnings),
					"shore_surface":
					_water_surface_of(entry, id, "shore_surface", 1, known, warnings),
					"ground_accents": _ground_accents_of(entry, id, ground, known, warnings),
					"path_surfaces": _path_surfaces_of(entry, id, known, warnings),
					"ground_look":
					GroundLook.validate(entry.get("ground_look"), id, ground, known, warnings),
					"species": species_rules,
				}
			)
		)
	return result


static func _validate_species_list(
	raw: Variant, biome_id: String, assets: Dictionary, warnings: Array[String]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array:
		warnings.append("biome '%s': species is not an array" % biome_id)
		return result
	var where := "biome '%s'" % biome_id
	for entry in _capped(raw, MAX_SPECIES_PER_BIOME, where + " species", warnings):
		var rule := _validate_species(entry, where, assets, warnings)
		if rule.is_empty():
			continue
		if result.any(func(kept: Dictionary) -> bool: return kept["key"] == rule["key"]):
			warnings.append("%s: duplicate species '%s' skipped" % [where, rule["key"]])
			continue
		result.append(rule)
	# Relations may only name species that survived validation in the same biome.
	var keys := result.map(func(kept: Dictionary) -> String: return kept["key"])
	for rule in result:
		for relation_kind in ["near", "avoid"]:
			var kept_relations: Array[Dictionary] = []
			for relation in rule[relation_kind]:
				if relation["species"] in keys:
					kept_relations.append(relation)
				else:
					warnings.append(
						(
							"%s species '%s': %s relation to unknown species '%s' dropped"
							% [where, rule["key"], relation_kind, relation["species"]]
						)
					)
			rule[relation_kind] = kept_relations
	return result


## One species rule, or {} (with a warning) when it is unusable. Required: key, kind,
## density_per_m2 and at least one asset id that resolves. Optional fields fall back to
## the neutral default when absent and warn when present with the wrong type; numbers
## outside their contract range are clamped rather than rejected.
static func _validate_species(
	entry: Variant, where: String, assets: Dictionary, warnings: Array[String]
) -> Dictionary:
	if not entry is Dictionary:
		warnings.append("%s: species entry is not an object" % where)
		return {}
	var key: Variant = _text(entry.get("key"), MAX_TEXT_LENGTH)
	var kind: Variant = _text(entry.get("kind"), MAX_TEXT_LENGTH)
	var density: Variant = _number(entry.get("density_per_m2"), 0.0, 1000.0)
	if key == null or key == "" or kind == null or density == null:
		warnings.append("%s: species '%s' skipped: needs key, kind, density" % [where, _label(key)])
		return {}
	var label := "%s species '%s'" % [where, key]
	var asset_ids: Array[String] = []
	var raw_assets: Variant = entry.get("assets")
	for id in _capped(
		raw_assets if raw_assets is Array else [], MAX_ASSETS_PER_SPECIES, label, warnings
	):
		if id is String and assets.has(id):
			if not id in asset_ids:
				asset_ids.append(id)
		else:
			warnings.append("%s: asset '%s' not in the palette, skipped" % [label, _label(id)])
	if asset_ids.is_empty():
		warnings.append("%s skipped: no asset resolves" % label)
		return {}
	var align := _text_or(entry.get("align"), MAX_TEXT_LENGTH, "upright")
	if not align in ALIGN_MODES:
		warnings.append("%s: unknown align '%s', using upright" % [label, align])
		align = "upright"
	var rule := {
		"key": key,
		"kind": kind,
		"keep_colour": entry.get("keep_colour") == true,
		"size_class": _text_or(entry.get("size_class"), MAX_TEXT_LENGTH, ""),
		"density_per_m2": density,
		"min_spacing_m":
		_optional_number(entry, "min_spacing_m", 0.0, 1000.0, 0.0, label, warnings),
		"slope_max_deg": _optional_number(entry, "slope_max_deg", 0.0, 90.0, 90.0, label, warnings),
		"scale_spread": _optional_number(entry, "scale_spread", 0.0, 0.9, 0.0, label, warnings),
		"scale_floor": _optional_number(entry, "scale_floor", 0.0, 100.0, null, label, warnings),
		"yaw_random_deg":
		_optional_number(entry, "yaw_random_deg", 0.0, 360.0, 360.0, label, warnings),
		"align": align,
		"pattern": _validate_pattern(entry.get("pattern"), label, warnings),
		"clump": _validate_clump(entry.get("clump"), label, warnings),
		"near": _validate_relations(entry.get("near"), label + " near", warnings),
		"avoid": _validate_relations(entry.get("avoid"), label + " avoid", warnings),
		"avoid_bare": _optional_number(entry, "avoid_bare", 0.0, 1.0, 0.0, label, warnings),
		"assets": asset_ids,
	}
	rule.merge(_library_fields(entry, label, warnings))
	return rule


## The optional content-library fields of a rule (step S2), present in the result only when the
## rule carries them, so a legacy palette's rules are unchanged: `role` (a LibraryContracts
## role), `habit` ({water: "", "bank", "emergent" or "arid"; charred: bool}, the role's habit
## with the rule's own flags laid over it; present whenever the rule has a role or a habit) and
## `weight` (0 to 1000, not read by the scatter code yet). A bad value warns and is dropped,
## an absent one never warns. ScatterGround.habit_of reads `habit`, then the legacy key lists.
static func _library_fields(
	entry: Dictionary, label: String, warnings: Array[String]
) -> Dictionary:
	var out := {}
	var role := ""
	if entry.get("role") != null:
		var text: Variant = _text(entry["role"], MAX_TEXT_LENGTH)
		if text != null and LibraryContracts.has_role(text):
			role = text
			out["role"] = role
		else:
			warnings.append("%s: unknown role '%s', ignored" % [label, _label(entry["role"])])
	if entry.get("habit") != null or role != "":
		out["habit"] = LibraryContracts.habit_for(
			role, _habit_flags(entry.get("habit"), label, warnings)
		)
	var weight: Variant = _optional_number(entry, "weight", 0.0, 1000.0, null, label, warnings)
	if weight != null:
		out["weight"] = weight
	return out


## The valid flags of a rule's `habit` (water, charred); anything else warns and is left out.
static func _habit_flags(raw: Variant, label: String, warnings: Array[String]) -> Dictionary:
	var flags := {}
	if raw == null:
		return flags
	if not raw is Dictionary:
		warnings.append("%s: habit is not an object, ignored" % label)
		return flags
	for flag: Variant in raw:
		var value: Variant = raw[flag]
		if flag == "water" and value is String and value in LibraryContracts.HABIT_WATER:
			flags["water"] = value
		elif flag == "charred" and value is bool:
			flags["charred"] = value
		else:
			warnings.append("%s: habit.%s is not valid, ignored" % [label, _label(flag)])
	return flags


## {influence, scale_influence, geoscatter_pattern} or null. geoscatter_pattern is
## Geoscatter's s_pattern1_* settings carried verbatim for later calibration (contract
## section 9), including a nested texture dict, so it is copied structurally rather than
## field by field: see _verbatim.
static func _validate_pattern(raw: Variant, label: String, warnings: Array[String]) -> Variant:
	if raw == null:
		return null
	if not raw is Dictionary:
		warnings.append("%s: pattern is not an object, ignored" % label)
		return null
	var noise: Variant = _verbatim(raw.get("geoscatter_pattern"), 0)
	return {
		"influence": _optional_number(raw, "influence", 0.0, 1.0, 0.0, label, warnings),
		"scale_influence": _optional_number(raw, "scale_influence", 0.0, 1.0, 0.0, label, warnings),
		"geoscatter_pattern": noise if noise is Dictionary else {},
	}


## A bounded copy of an opaque JSON value tt-sim stores but does not interpret: numbers,
## bools and short strings as-is, objects and arrays up to MAX_VERBATIM_DEPTH levels and
## MAX_PATTERN_KEYS entries each. Anything else (and anything deeper) becomes null, and a
## null is dropped from an object, so the result is always small and plain.
static func _verbatim(value: Variant, depth: int) -> Variant:
	if value is bool or value is int:
		return value
	if value is float:
		return value if not (is_nan(value) or is_inf(value)) else null
	if value is String:
		return value if value.length() <= MAX_TEXT_LENGTH else null
	if depth >= MAX_VERBATIM_DEPTH:
		return null
	if value is Array:
		var items: Array = []
		for item in value.slice(0, MAX_PATTERN_KEYS):
			items.append(_verbatim(item, depth + 1))
		return items
	if value is Dictionary:
		var copy := {}
		for key in value.keys().slice(0, MAX_PATTERN_KEYS):
			var name: Variant = _text(key, MAX_TEXT_LENGTH)
			var inner: Variant = _verbatim(value[key], depth + 1)
			if name != null and inner != null:
				copy[name] = inner
		return copy
	return null


static func _validate_clump(raw: Variant, label: String, warnings: Array[String]) -> Variant:
	if raw == null:
		return null
	if not raw is Dictionary:
		warnings.append("%s: clump is not an object, ignored" % label)
		return null
	var clump := {}
	for field in ["parents_per_m2", "radius_m", "transition_m", "children_spacing_m"]:
		clump[field] = _optional_number(raw, field, 0.0, 1000.0, 0.0, label, warnings)
	# The grass-mass fields (ScatterPlan.MASS_FIELDS), read only with mass 1 and kept only when
	# given, clamped; zone_keep and zone_family are four-element arrays.
	if _optional_number(raw, "mass", 0.0, 1.0, 0.0, label, warnings) < 0.5:
		return clump
	for field: String in ScatterPlan.MASS_FIELDS:
		var limits: Array = ScatterPlan.MASS_FIELDS[field]
		var value: Variant = _optional_number(
			raw, field, limits[0], limits[1], null, label, warnings
		)
		if value != null:
			clump[field] = value
	for field: String in ScatterPlan.MASS_ARRAYS:
		var limits: Array = ScatterPlan.MASS_ARRAYS[field]
		var items: Variant = raw.get(field)
		if items == null:
			continue
		var values := []
		for item: Variant in items if items is Array and items.size() == 4 else []:
			var number: Variant = _number(item, limits[0], limits[1])
			if number != null:
				values.append(roundf(number) if field == "zone_family" else number)
		if values.size() == 4:
			clump[field] = values
		else:
			warnings.append("%s: %s is not four numbers, using the default" % [label, field])
	return clump


static func _validate_relations(
	raw: Variant, label: String, warnings: Array[String]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw == null:
		return result
	if not raw is Array:
		warnings.append("%s is not an array, ignored" % label)
		return result
	for entry in _capped(raw, MAX_RELATIONS, label, warnings):
		var target: Variant = _text(
			entry.get("species") if entry is Dictionary else null, MAX_TEXT_LENGTH
		)
		if target == null or target == "":
			warnings.append("%s: relation without a species skipped" % label)
			continue
		(
			result
			. append(
				{
					"species": target,
					"distance_m":
					_optional_number(entry, "distance_m", 0.0, 1000.0, 0.0, label, warnings),
					"transition_m":
					_optional_number(entry, "transition_m", 0.0, 1000.0, 0.0, label, warnings),
					"influence":
					_optional_number(entry, "influence", 0.0, 1.0, 1.0, label, warnings),
				}
			)
		)
	return result
