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
## The palette contract's constants live in PaletteFields (the validators' shared base) and are
## re-exported here so every caller keeps reading them as PaletteLibrary.<NAME>.
const FORMAT := PaletteFields.FORMAT
const WIND_CATEGORIES := PaletteFields.WIND_CATEGORIES
const ALIGN_MODES := PaletteFields.ALIGN_MODES
const SURFACE_MAPS := PaletteFields.SURFACE_MAPS
const SURFACE_ROLES := PaletteFields.SURFACE_ROLES
const MAX_BIOMES := PaletteFields.MAX_BIOMES
const MAX_SPECIES_PER_BIOME := PaletteFields.MAX_SPECIES_PER_BIOME
const MAX_ASSETS := PaletteFields.MAX_ASSETS
const MAX_ASSETS_PER_SPECIES := PaletteFields.MAX_ASSETS_PER_SPECIES
const MAX_SURFACES := PaletteFields.MAX_SURFACES
const MAX_RELATIONS := PaletteFields.MAX_RELATIONS
const MAX_ACCENTS := PaletteFields.MAX_ACCENTS
const MAX_PATH_SURFACES := PaletteFields.MAX_PATH_SURFACES
const MAX_PATTERN_KEYS := PaletteFields.MAX_PATTERN_KEYS
const MAX_VERBATIM_DEPTH := PaletteFields.MAX_VERBATIM_DEPTH
const MAX_ID_LENGTH := PaletteFields.MAX_ID_LENGTH
const MAX_TEXT_LENGTH := PaletteFields.MAX_TEXT_LENGTH
const MAX_PATH_LENGTH := PaletteFields.MAX_PATH_LENGTH
const DEFAULT_ACCENT_SCALE_M := PaletteFields.DEFAULT_ACCENT_SCALE_M
const MAX_ACCENT_SCALE_M := PaletteFields.MAX_ACCENT_SCALE_M
const WATER_SURFACE_DEFAULTS := PaletteFields.WATER_SURFACE_DEFAULTS
const DEFAULT_WATER_SURFACES := PaletteFields.DEFAULT_WATER_SURFACES
## Hard caps on the palette file and on one asset GLB (docs/ASSET_PIPELINE.md section 9).
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_ASSET_FILE_BYTES := PaletteAssetFiles.MAX_ASSET_FILE_BYTES
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
## meshes already handed out by resolve() are independent duplicates and unaffected. Also
## forgets the content library's registered assets (AssetStore): LibraryRegistry.apply registers
## them again after the palette they belong to is laid back.
static func clear_cache() -> void:
	_palettes.clear()
	_source_meshes.clear()
	AssetStore.clear()


## Lays a built treecube package (a build_palette.py output folder anywhere on disk) over
## the palette under `root` for this run, as PaletteOverlay.read describes: the package's
## biomes (those `only` names, or all) and their assets replace the cached ones, the GLBs
## whose bytes differ from root's are parsed now and the rest load from root as before.
## Call it before a map opens; meshes already handed out are unaffected. Returns read()'s
## report; when it is not ok the caches are left as they were.
static func overlay_package(
	package: String, root: String = DEFAULT_ROOT, only: Array = []
) -> Dictionary:
	return install_overlay(PaletteOverlay.read(package, get_palette(root), root, only), root)


## Caches a PaletteOverlay report (read, or read_palette for LibraryRegistry); not ok: no change.
static func install_overlay(report: Dictionary, root: String = DEFAULT_ROOT) -> Dictionary:
	if not report["ok"]:
		return report
	_palettes[root] = report["palette"]
	for asset_id: String in report["dropped"]:
		_source_meshes.erase(root + "|" + asset_id)
	var meshes: Dictionary = report["meshes"]
	for asset_id: String in meshes:
		_source_meshes[root + "|" + asset_id] = meshes[asset_id]
	# After every mesh is cached: the layout guard resolves its representatives, which may be
	# overlaid assets later in the list (resolving one before it was cached warned and cached
	# a failed load from the installed root).
	for asset_id: String in meshes:
		var category := String(report["palette"]["assets"][asset_id].get("wind_category", ""))
		WindFoliage.check_layout(root, asset_id, meshes[asset_id], category)
	return report


static func palette_version(root: String = DEFAULT_ROOT) -> String:
	return get_palette(root)["palette_version"]


## Every valid biome, in file order. Each is {id, biome, season, seed, name, climate,
## thumbnail, ground_surface, cliff_surface, scree_surface, water_bed_surface,
## shore_surface, ground_accents, path_surfaces, ground_look (GroundLook.validate's merged look,
## {} when the biome has none), species}; paths are relative to the palette
## root. cliff_surface names a role-cliff surface or is "" when the palette has none;
## scree_surface names a role-ground surface or is "" (keep the ground);
## water_bed_surface and shore_surface name role-ground surfaces (the palette's, else
## WATER_SURFACE_DEFAULTS) or are "" (keep the ground). ground_accents is an Array of
## {surface, coverage, scale_m} in priority order (role-ground surfaces other than the
## biome's ground; coverage 0..1, scale_m > 0), path_surfaces an Array[String] of role-built
## surfaces; both [] when the palette lists none (a palette from before 2026-09-27).
static func biomes(root: String = DEFAULT_ROOT) -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for entry in get_palette(root)["biomes"]:
		copies.append((entry as Dictionary).duplicate(true))
	return copies


## One biome by id, or {} when there is no such biome.
static func biome(biome_id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	for entry in get_palette(root)["biomes"]:
		if entry["id"] == biome_id:
			return (entry as Dictionary).duplicate(true)
	return {}


## The species rules of one biome, in file order (large classes first, the order
## treecube writes and a generator should honour), or [] for an unknown biome. Each rule
## also carries `height_m` and `width_m`, the tallest and widest of its assets (manifest
## dimensions_m y, and the larger of x and z; 0 when none is known), which
## ScatterGround.role_of and GroundSnap.footing_radius read.
static func species(biome_id: String, root: String = DEFAULT_ROOT) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	var entry := biome(biome_id, root)
	var assets: Dictionary = get_palette(root)["assets"]
	for rule in entry.get("species", []):
		var tallest := 0.0
		var widest := 0.0
		for asset_id in rule.get("assets", []):
			var size: Variant = (assets.get(asset_id, {}) as Dictionary).get("dimensions_m")
			if size is Vector3:
				tallest = maxf(tallest, size.y)
				widest = maxf(widest, maxf(size.x, size.z))
		# A grass mass grown in its core (ScatterPlan.MASS_FIELDS) is as tall as its tallest core
		# tuft, held under core_height_m; base_height_m keeps the ungrown height (the cap's base).
		rule["base_height_m"] = tallest
		var clump: Variant = rule.get("clump")
		if clump is Dictionary and float(clump.get("mass", 0.0)) >= 0.5:
			var core := maxf(1.0, float(clump.get("core_scale", 1.0)))
			var grown := tallest * maxf(1.0, float(clump.get("core_height", core)))
			var cap := float(clump.get("core_height_m", 0.0))
			tallest = minf(grown, maxf(cap, tallest)) if cap > 0.0 else grown
		rule["height_m"] = tallest
		rule["width_m"] = widest
		rules.append(rule)
	return rules


## Surface preset name (treecube's, e.g. "grass_alpine", not the kind "grass") ->
## {albedo, normal, orm, height, tile_m, kind, role}; map paths are relative to the palette
## root and a map the palette does not ship is "". role is one of SURFACE_ROLES; kind is
## the treecube surface kind ("grass" for "grass_alpine"), "" when the palette omits it.
static func surfaces(root: String = DEFAULT_ROOT) -> Dictionary:
	return (get_palette(root)["surfaces"] as Dictionary).duplicate(true)


## A biome's merged ground look (GroundLook.validate: every contract key, the biome's overrides
## over GroundLook.BASE), or {} when the biome has none or is unknown.
static func ground_look(biome_id: String, root: String = DEFAULT_ROOT) -> Dictionary:
	for entry in get_palette(root)["biomes"]:
		if entry["id"] == biome_id:
			return (entry.get("ground_look", {}) as Dictionary).duplicate(true)
	return {}


## The names of the surfaces with `role` ("ground", "cliff" or "built"), in file order.
static func surfaces_with_role(role: String, root: String = DEFAULT_ROOT) -> Array[String]:
	return PaletteSurfaces.names_with_role(get_palette(root)["surfaces"], role)


## The ground accents of one biome ({surface, coverage, scale_m}, priority order), or [] for
## an unknown biome or one without accents.
static func ground_accents(biome_id: String, root: String = DEFAULT_ROOT) -> Array[Dictionary]:
	var accents: Array[Dictionary] = []
	accents.assign(biome(biome_id, root).get("ground_accents", []))
	return accents


## The path surfaces the Paint tool shows first on one biome, in order, or [].
static func path_surfaces(biome_id: String, root: String = DEFAULT_ROOT) -> Array[String]:
	var names: Array[String] = []
	names.assign(biome(biome_id, root).get("path_surfaces", []))
	return names


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
	return PaletteValidator.validate_palette(data)


## Loads and validates <root>/palette.json. A root without one is an empty palette and a
## single warning, which is the expected state until a palette ships.
static func _load_palette(root: String) -> Dictionary:
	var path := root.path_join(PALETTE_FILE)
	if not FileAccess.file_exists(path):
		push_warning("PaletteLibrary: no palette at %s; the palette is empty" % path)
		return PaletteValidator.empty_palette()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("PaletteLibrary: cannot open %s; the palette is empty" % path)
		return PaletteValidator.empty_palette()
	if file.get_length() > MAX_FILE_BYTES:
		push_warning("PaletteLibrary: %s exceeds %d bytes; ignored" % [path, MAX_FILE_BYTES])
		return PaletteValidator.empty_palette()
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
		return PaletteValidator.empty_palette()
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


## The cached source mesh for one asset, loading its GLB on first use.
static func _source_mesh(root: String, asset_id: String, entry: Dictionary) -> Mesh:
	var cache_key := root + "|" + asset_id
	if not _source_meshes.has(cache_key):
		var path := root.path_join(entry["file"])
		var mesh: Mesh = null
		if AssetStore.serves(asset_id, root):
			# A content-library asset: AssetStore parses its GLB lazily (and warns itself).
			mesh = AssetStore.mesh_for(asset_id, root)
		else:
			mesh = PaletteAssetFiles.load_mesh(path, entry["node"])
			if mesh == null:
				push_warning(
					"PaletteLibrary: asset '%s' could not be loaded from %s" % [asset_id, path]
				)
		_source_meshes[cache_key] = mesh
		# After caching, so the guard's own resolve of the representative cannot recurse here.
		WindFoliage.check_layout(root, asset_id, mesh, String(entry.get("wind_category", "")))
	return _source_meshes[cache_key]
