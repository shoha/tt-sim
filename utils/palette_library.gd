class_name PaletteLibrary
extends RefCounted

## The built-in palette treecube produces for in-game map authoring: biomes, their
## per-species placement rules, ground surfaces, and the asset GLBs those rules place.
## The file format is docs/ASSET_PIPELINE.md section 9; read it before changing anything
## here, since the consumer owns that contract.
##
## Everything read from palette.json is validated as untrusted input even though the
## palette ships with the game: the same rules will read authored map documents that
## arrive from network peers. Counts and string lengths are capped before anything is
## kept, wrong types are rejected field by field, a malformed entry is skipped with a
## warning, and nothing here ever raises. A missing or unreadable palette is an empty
## palette, not an error, so a build without one still starts cleanly.
##
## Loaded lazily on first use and cached per palette root; the cache is the only state.
## The root is a parameter so tests can point at a palette they build on the fly.
## validate_palette() is pure, so the validation rules are testable without files.

const DEFAULT_ROOT := "res://assets/palette"
const PALETTE_FILE := "palette.json"
const FORMAT := 1
const WIND_CATEGORIES := ["tree", "grass", ""]
const ALIGN_MODES := ["upright", "normal"]
const SURFACE_MAPS := ["albedo", "normal", "orm", "height"]

## Hard caps, checked before anything is kept. Sized an order of magnitude above what
## treecube builds today (8 biomes, about 25 assets and species each, a dozen surfaces),
## so they only ever bite on a corrupt or hostile document.
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_ASSET_FILE_BYTES := 64 * 1024 * 1024
const MAX_BIOMES := 128
const MAX_SPECIES_PER_BIOME := 128
const MAX_ASSETS := 8192
const MAX_ASSETS_PER_SPECIES := 64
const MAX_SURFACES := 128
const MAX_RELATIONS := 32
const MAX_PATTERN_KEYS := 64
const MAX_VERBATIM_DEPTH := 4
const MAX_ID_LENGTH := 160
const MAX_TEXT_LENGTH := 128
const MAX_PATH_LENGTH := 256
## At most this many individual warnings are printed per palette load; the rest are
## summarised in one line so a badly broken file cannot flood the log.
const MAX_WARNINGS_PRINTED := 20

## palette root -> validated palette (see validate_palette for the shape).
static var _palettes: Dictionary = {}
## "<root>|<asset id>" -> the Mesh loaded from that asset's GLB, or null when the load
## failed (cached too, so a broken asset warns once rather than on every map load).
static var _source_meshes: Dictionary = {}


## The validated palette under `root`, loading it on first use. The returned Dictionary
## is the cached one; callers must not mutate it (the typed getters below hand out
## copies).
static func get_palette(root: String = DEFAULT_ROOT) -> Dictionary:
	if not _palettes.has(root):
		_palettes[root] = _load_palette(root)
	return _palettes[root]


## Drops every cached palette and source mesh. For tests and a future palette reload;
## meshes already handed out by resolve() are independent duplicates and unaffected.
static func clear_cache() -> void:
	_palettes.clear()
	_source_meshes.clear()


static func palette_version(root: String = DEFAULT_ROOT) -> String:
	return get_palette(root)["palette_version"]


## Every valid biome, in file order. Each is {id, biome, season, seed, name, climate,
## thumbnail, ground_surface, species}; paths are relative to the palette root.
static func biomes(root: String = DEFAULT_ROOT) -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for biome in get_palette(root)["biomes"]:
		copies.append((biome as Dictionary).duplicate(true))
	return copies


## One biome by id, or {} when there is no such biome.
static func biome(biome_id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	for entry in get_palette(root)["biomes"]:
		if entry["id"] == biome_id:
			return (entry as Dictionary).duplicate(true)
	return {}


## The species rules of one biome, in file order (large classes first, the order
## treecube writes and a generator should honour), or [] for an unknown biome.
static func species(biome_id: String, root: String = DEFAULT_ROOT) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	var entry := biome(biome_id, root)
	for rule in entry.get("species", []):
		rules.append(rule)
	return rules


## Ground surface preset name (treecube's, e.g. "grass_alpine", not the kind "grass") ->
## {albedo, normal, orm, height, tile_m}; map paths are relative to the palette root and
## a map the palette does not ship is "".
static func surfaces(root: String = DEFAULT_ROOT) -> Dictionary:
	return (get_palette(root)["surfaces"] as Dictionary).duplicate(true)


## The manifest entry of one asset ({file, node, wind_category, size_class,
## dimensions_m}), or {} for an unknown id.
static func asset(asset_id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	var assets: Dictionary = get_palette(root)["assets"]
	return (assets.get(asset_id, {}) as Dictionary).duplicate(true)


## Template for ScatterGlbUtils.build_scatter(): {"mesh", "wind_category", "name"}, or
## {} (with a warning) when the id is unknown or its GLB cannot be loaded, so a level
## that names an asset this build lacks loads without it instead of failing.
##
## The mesh is a fresh duplicate on every call. WindFoliage.apply_material replaces a
## mesh's surface materials in place, so handing out the cached source would leave the
## first map load's wind overrides baked into every later one. A shallow
## Mesh.duplicate() is enough: probed on a real treecube GLB (2026-09-26), the duplicate
## is a separate ArrayMesh with its own RID and its own surface-material slots (initially
## pointing at the same StandardMaterial3D objects), and apply_material on it leaves the
## source's surfaces as StandardMaterial3D. Vertex data is re-uploaded per duplicate,
## which is the price of that independence; it is freed with the map that used it.
##
## The wind category comes from the manifest, never WindFoliage.classify_category():
## palette ids contain biome names (birch_woodland) the keyword heuristic would misread.
## "name" is the id made node-name-safe, so two biomes' same-named objects stay separate
## species for FoliageDensityController.
static func resolve(asset_id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	var assets: Dictionary = get_palette(root)["assets"]
	if not assets.has(asset_id):
		push_warning("PaletteLibrary: unknown asset id '%s' in %s" % [asset_id, root])
		return {}
	var entry: Dictionary = assets[asset_id]
	var source := _source_mesh(root, asset_id, entry)
	if source == null:
		return {}
	return {
		"mesh": source.duplicate() as Mesh,
		"wind_category": entry["wind_category"],
		"name": asset_id.validate_node_name(),
	}


## resolve() bound to one palette root, in the shape build_scatter() takes.
static func resolver(root: String = DEFAULT_ROOT) -> Callable:
	return func(asset_id: String) -> Dictionary: return resolve(asset_id, root)


## Validates a parsed palette.json document. Pure: returns {"palette": Dictionary,
## "warnings": Array[String]} and never touches files, caches or the log.
##
## The palette is always well-formed, even for garbage input:
## {"format": int, "palette_version": String, "surfaces": Dictionary,
##  "biomes": Array[Dictionary], "assets": Dictionary}. Assets are validated first, so a
## species keeps only asset ids that resolve, and a species left with none is dropped.
static func validate_palette(data: Variant) -> Dictionary:
	var warnings: Array[String] = []
	var palette := _empty_palette()
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


## Loads and validates <root>/palette.json. A root without one is an empty palette and a
## single warning, which is the expected state until a palette ships.
static func _load_palette(root: String) -> Dictionary:
	var path := root.path_join(PALETTE_FILE)
	if not FileAccess.file_exists(path):
		push_warning("PaletteLibrary: no palette at %s; the palette is empty" % path)
		return _empty_palette()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("PaletteLibrary: cannot open %s; the palette is empty" % path)
		return _empty_palette()
	if file.get_length() > MAX_FILE_BYTES:
		push_warning("PaletteLibrary: %s exceeds %d bytes; ignored" % [path, MAX_FILE_BYTES])
		return _empty_palette()
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning(
			(
				"PaletteLibrary: %s is not valid JSON (line %d: %s)"
				% [path, json.get_error_line(), json.get_error_message()]
			)
		)
		return _empty_palette()
	var result := validate_palette(json.data)
	_print_warnings(path, result["warnings"])
	return result["palette"]


static func _print_warnings(path: String, warnings: Array[String]) -> void:
	for i in mini(warnings.size(), MAX_WARNINGS_PRINTED):
		push_warning("PaletteLibrary: %s: %s" % [path, warnings[i]])
	if warnings.size() > MAX_WARNINGS_PRINTED:
		push_warning(
			(
				"PaletteLibrary: %s: %d more problems not shown"
				% [path, warnings.size() - MAX_WARNINGS_PRINTED]
			)
		)


static func _empty_palette() -> Dictionary:
	var no_biomes: Array[Dictionary] = []
	return {
		"format": FORMAT, "palette_version": "", "surfaces": {}, "biomes": no_biomes, "assets": {}
	}


## The cached source mesh for one asset, loading its GLB on first use.
static func _source_mesh(root: String, asset_id: String, entry: Dictionary) -> Mesh:
	var cache_key := root + "|" + asset_id
	if not _source_meshes.has(cache_key):
		var path := root.path_join(entry["file"])
		var mesh := _load_asset_mesh(path, entry["node"])
		if mesh == null:
			push_warning(
				"PaletteLibrary: asset '%s' could not be loaded from %s" % [asset_id, path]
			)
		_source_meshes[cache_key] = mesh
	return _source_meshes[cache_key]


## Loads the Mesh of node `node_name` from an asset GLB. The built-in res:// palette goes
## through Godot's editor import (ResourceLoader on the imported PackedScene): an
## exported game ships only the imported .scn, never the raw .glb, so FileAccess finds
## nothing there. Its import settings (committed .glb.import sidecars: textures embedded
## uncompressed, no LODs, no shadow meshes) and the evidence for them are in
## docs/ASSET_PIPELINE.md section 9 "Import path". A GLB with no import (a user:// palette,
## the unit-test fixture) is parsed at runtime through GLTFDocument instead, the path
## GlbUtils uses for user:// maps; with those settings both give the same meshes, vertex
## colours, materials and unmipmapped textures.
##
## Returns null (the caller warns) for a missing, oversized or unparseable file or a
## missing node. Treecube exports the asset node at the identity transform; one that is
## not would be placed without that offset, since only its Mesh is used, so it warns.
static func _load_asset_mesh(path: String, node_name: String) -> Mesh:
	var scene := _load_asset_scene(path)
	if scene == null:
		return null
	var node := GlbUtils.find_node_by_name(scene, node_name)
	if node == null:
		node = GlbUtils.find_node_by_name(scene, node_name.validate_node_name())
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
		if (node as Node3D).transform != Transform3D.IDENTITY:
			push_warning("PaletteLibrary: node '%s' in %s is not at the origin" % [node_name, path])
	scene.free()
	return mesh


## The instantiated scene of an asset GLB (the caller frees it), or null. Imported
## resources win over the raw file so the editor exercises the same path as an export.
static func _load_asset_scene(path: String) -> Node:
	if ResourceLoader.exists(path, "PackedScene"):
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		return packed.instantiate() if packed != null else null
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_ASSET_FILE_BYTES:
		return null
	var buffer := file.get_buffer(file.get_length())
	file.close()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(buffer, "", state) != OK:
		return null
	return document.generate_scene(state)


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
		var surface := {"tile_m": tile}
		for map_name in SURFACE_MAPS:
			surface[map_name] = _path_or(entry.get(map_name), "")
		result[name] = surface
	return result


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
	raw: Variant, assets: Dictionary, surfaces: Dictionary, warnings: Array[String]
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
		if ground != "" and not surfaces.has(ground):
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
	return {
		"key": key,
		"kind": kind,
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
		"assets": asset_ids,
	}


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


## `<package id>/<object>` (`<biome>_<season>_s<seed>/<object>`): one slash, both halves
## non-empty, no path tricks. The package half is not parsed further; ids are opaque keys.
static func _is_asset_id(id: Variant) -> bool:
	if not id is String or id.length() > MAX_ID_LENGTH or id.count("/") != 1:
		return false
	var halves: PackedStringArray = id.split("/")
	return halves[0] != "" and halves[1] != "" and not ".." in id and not "\\" in id


## The value as a String when it is one and fits, else null.
static func _text(value: Variant, max_length: int) -> Variant:
	if value is String and value.length() <= max_length:
		return value
	if value is StringName and String(value).length() <= max_length:
		return String(value)
	return null


static func _text_or(value: Variant, max_length: int, fallback: String) -> String:
	var text: Variant = _text(value, max_length)
	return text if text != null else fallback


## A palette-relative path, or `fallback` when the value could escape the palette root
## (absolute, a scheme, a parent segment, a backslash) or is not a short String.
static func _path_or(value: Variant, fallback: String) -> String:
	var text: Variant = _text(value, MAX_PATH_LENGTH)
	if text == null or text == "":
		return fallback
	if text.begins_with("/") or ":" in text or "\\" in text:
		return fallback
	if ".." in text.split("/"):
		return fallback
	return text


## The value as a float clamped to [low, high], or null when it is not a finite number.
static func _number(value: Variant, low: float, high: float) -> Variant:
	if value is bool or not (value is float or value is int):
		return null
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return null
	return clampf(number, low, high)


## An optional numeric field: `fallback` when absent (or explicitly null), a warning plus
## `fallback` when present with the wrong type, else clamped.
static func _optional_number(
	entry: Dictionary,
	field: String,
	low: float,
	high: float,
	fallback: Variant,
	label: String,
	warnings: Array[String]
) -> Variant:
	var value: Variant = entry.get(field)
	if value == null:
		return fallback
	var number: Variant = _number(value, low, high)
	if number == null:
		warnings.append("%s: %s is not a number, using the default" % [label, field])
		return fallback
	return number


static func _vector3_or_zero(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.ZERO
	var parts: Array[float] = []
	for component in value:
		var number: Variant = _number(component, 0.0, 10000.0)
		if number == null:
			return Vector3.ZERO
		parts.append(number)
	return Vector3(parts[0], parts[1], parts[2])


## The first `cap` entries of an array; one warning when the rest are dropped.
static func _capped(items: Array, cap: int, label: String, warnings: Array[String]) -> Array:
	if items.size() <= cap:
		return items
	warnings.append("%s: %d entries over the cap of %d ignored" % [label, items.size() - cap, cap])
	return items.slice(0, cap)


## The first `cap` keys of a Dictionary (insertion order, i.e. file order for JSON).
static func _capped_keys(
	items: Dictionary, cap: int, label: String, warnings: Array[String]
) -> Array:
	return _capped(items.keys(), cap, label, warnings)


## A short printable form of an untrusted value for a warning message.
static func _label(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 48 else text.substr(0, 48) + "..."
