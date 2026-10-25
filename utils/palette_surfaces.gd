class_name PaletteSurfaces
extends PaletteFields

## Validation of a palette's `surfaces` table and of the surface fields of a biome (cliff,
## scree, water bed and shore, ground accents, path surfaces), split out of PaletteLibrary
## (step S2 of the content library, docs/systems/library.md). Pure: returns values and
## appends to the caller's warnings; see PaletteLibrary.validate_palette.


static func _validate_surfaces(raw: Variant, warnings: Array[String]) -> Dictionary:
	var result := {}
	if raw == null:
		return result
	if not raw is Dictionary:
		warnings.append("surfaces is not an object")
		return result
	for kind in _capped_keys(raw, MAX_SURFACES, "surfaces", warnings):
		var name: Variant = _text(kind, MAX_TEXT_LENGTH)
		var entry: Variant = raw[kind]
		if name == null or not entry is Dictionary:
			warnings.append("surface '%s' skipped: malformed" % _label(kind))
			continue
		var tile: Variant = _number(entry.get("tile_m"), 0.001, 10000.0)
		var albedo := _path_or(entry.get("albedo"), "")
		if tile == null or albedo == "":
			warnings.append("surface '%s' skipped: needs albedo and tile_m" % name)
			continue
		var role: Variant = entry.get("role")
		if role == null:
			role = "ground"  # a palette from before roles: every surface was ground
		elif not role is String or not role in SURFACE_ROLES:
			warnings.append(
				"surface '%s': unknown role '%s', treated as ground" % [name, _label(role)]
			)
			role = "ground"
		var surface := {
			"tile_m": tile, "kind": _text_or(entry.get("kind"), MAX_TEXT_LENGTH, ""), "role": role
		}
		for map_name in SURFACE_MAPS:
			surface[map_name] = _path_or(entry.get(map_name), "")
		# Optional (section 9): the albedo map's mean linear colour, a ground look's light
		# reference (GroundLookUniforms.ref_linear measures it when absent or malformed).
		var mean: Variant = entry.get("albedo_mean_linear")
		var numeric := func(v: Variant) -> bool: return v is float or v is int
		if mean is Array and mean.size() == 3 and mean.all(numeric):
			surface["albedo_mean_linear"] = mean.map(
				func(v: Variant) -> float: return clampf(float(v), 0.0, 1.0)
			)
		elif mean != null:
			warnings.append("surface '%s': malformed albedo_mean_linear ignored" % name)
		result[name] = surface
	return result


## The names in a validated surfaces table whose role is `role`, in file order.
static func names_with_role(known: Dictionary, role: String) -> Array[String]:
	var names: Array[String] = []
	for name in known:
		if known[name]["role"] == role:
			names.append(name)
	return names


## A biome's cliff_surface: the named surface when it is a cliff; else (with a warning
## when a name was given) the first cliff surface in file order, or "" when there is none.
static func _cliff_surface_of(
	entry: Dictionary, id: String, known: Dictionary, warnings: Array[String]
) -> String:
	var fallback := ""
	var cliffs := names_with_role(known, "cliff")
	if not cliffs.is_empty():
		fallback = cliffs[0]
	var raw: Variant = entry.get("cliff_surface")
	if raw == null:
		return fallback
	var cliff := _text_or(raw, MAX_TEXT_LENGTH, "")
	if known.has(cliff) and known[cliff]["role"] == "cliff":
		return cliff
	warnings.append(
		(
			"biome '%s': cliff surface '%s' is not a cliff surface, using '%s'"
			% [id, _label(raw), fallback]
		)
	)
	return fallback


## A biome's scree_surface: the named surface when it is ground, else "" (the foot keeps
## the biome ground), with a warning when a name was given.
static func _scree_surface_of(
	entry: Dictionary, id: String, known: Dictionary, warnings: Array[String]
) -> String:
	var raw: Variant = entry.get("scree_surface")
	if raw == null:
		return ""
	var scree := _text_or(raw, MAX_TEXT_LENGTH, "")
	if known.has(scree) and known[scree]["role"] == "ground":
		return scree
	warnings.append("biome '%s': scree surface '%s' is not a ground surface" % [id, _label(raw)])
	return ""


## A biome's water bed (`key` "water_bed_surface", index 0 of the defaults) or shore surface
## ("shore_surface", index 1): the named surface when it is ground; absent, the default for
## the biome key (WATER_SURFACE_DEFAULTS) when the palette has it as ground, else ""; named
## but absent or not ground, a warning and the default.
static func _water_surface_of(
	entry: Dictionary,
	id: String,
	key: String,
	index: int,
	known: Dictionary,
	warnings: Array[String]
) -> String:
	var defaults: Array = WATER_SURFACE_DEFAULTS.get(
		_text_or(entry.get("biome"), MAX_TEXT_LENGTH, ""), DEFAULT_WATER_SURFACES
	)
	var fallback := String(defaults[index])
	if not known.has(fallback) or known[fallback]["role"] != "ground":
		fallback = ""
	var raw: Variant = entry.get(key)
	if raw == null:
		return fallback
	var named := _text_or(raw, MAX_TEXT_LENGTH, "")
	if known.has(named) and known[named]["role"] == "ground":
		return named
	warnings.append(
		"biome '%s': %s '%s' is not a ground surface, using '%s'" % [id, key, _label(raw), fallback]
	)
	return fallback


## A biome's ground_accents (contract section 9, "Accents and path surfaces degrade, never
## fail"): absent is [] silently; not an array warns and is []; an entry that is not an
## object, has no numeric coverage, or names a surface that is absent, not role ground or
## the biome's own ground warns and is dropped, as is a second entry for one surface;
## coverage is clamped to 0..1; a missing scale_m is DEFAULT_ACCENT_SCALE_M silently, a
## non-numeric or non-positive one warns and is too. Order is kept (priority order).
static func _ground_accents_of(
	entry: Dictionary, id: String, ground: String, known: Dictionary, warnings: Array[String]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = entry.get("ground_accents")
	if raw == null:
		return result
	var where := "biome '%s' ground_accents" % id
	if not raw is Array:
		warnings.append("%s is not an array, ignored" % where)
		return result
	for accent in _capped(raw, MAX_ACCENTS, where, warnings):
		var surface: Variant = _text(
			accent.get("surface") if accent is Dictionary else null, MAX_TEXT_LENGTH
		)
		var coverage: Variant = _number(
			accent.get("coverage") if accent is Dictionary else null, 0.0, 1.0
		)
		if surface == null or coverage == null:
			warnings.append("%s: malformed entry '%s' dropped" % [where, _label(accent)])
			continue
		if not known.has(surface) or known[surface]["role"] != "ground" or surface == ground:
			warnings.append(
				(
					"%s: '%s' is not a ground surface other than the biome's own, dropped"
					% [where, _label(surface)]
				)
			)
			continue
		if result.any(func(kept: Dictionary) -> bool: return kept["surface"] == surface):
			warnings.append("%s: '%s' listed twice, the second dropped" % [where, surface])
			continue
		var scale_m := DEFAULT_ACCENT_SCALE_M
		var raw_scale: Variant = accent.get("scale_m")
		if raw_scale != null:
			var number: Variant = _number(raw_scale, -INF, MAX_ACCENT_SCALE_M)
			if number != null and number > 0.0:
				scale_m = number
			else:
				warnings.append(
					"%s: '%s' scale_m is not positive, using %.0f" % [where, surface, scale_m]
				)
		result.append({"surface": surface, "coverage": coverage, "scale_m": scale_m})
	return result


## A biome's path_surfaces: absent is [] silently; not an array warns and is []; a name that
## is absent or not role built warns and is dropped; a duplicate is ignored silently.
static func _path_surfaces_of(
	entry: Dictionary, id: String, known: Dictionary, warnings: Array[String]
) -> Array[String]:
	var result: Array[String] = []
	var raw: Variant = entry.get("path_surfaces")
	if raw == null:
		return result
	var where := "biome '%s' path_surfaces" % id
	if not raw is Array:
		warnings.append("%s is not an array, ignored" % where)
		return result
	for name in _capped(raw, MAX_PATH_SURFACES, where, warnings):
		var surface: Variant = _text(name, MAX_TEXT_LENGTH)
		if surface == null or not known.has(surface) or known[surface]["role"] != "built":
			warnings.append("%s: '%s' is not a built surface, dropped" % [where, _label(name)])
			continue
		if not surface in result:
			result.append(surface)
	return result
