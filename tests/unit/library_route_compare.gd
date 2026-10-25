extends RefCounted

## What the package route and the library route must agree on, for the row-parity tests (step S5).
## A snapshot is taken of whatever palette is currently cached under a root: per runtime biome its
## palette entry (without the rules), its rules (as the scatter code reads them), and the scatter
## rows at a fixed seed over a fixed square as {asset id: "count:md5"}; plus the assets table.
## The library route's ids differ from the package's where the game profile tones one stem per
## biome (`Tree_Oak_v0_savanna` for the package stem `Tree_Oak_v0`), so `mapped` turns a library
## snapshot into package ids through the catalog's `package_stem` before the two are compared.
## Not a test file itself (GUT only collects test_*.gd). Preload it as a const.

const SEED := 1234
const HALF_M := 16.0
## Fields the library route's compiled rules carry that a package's do not (authoring data).
const AUTHORING_FIELDS: Array[String] = ["role", "habit", "weight", "library", "origin", "query"]


static func _density(p: Vector2) -> float:
	return clampf(0.55 + 0.45 * sin(p.x * 0.21) * cos(p.y * 0.17), 0.0, 1.0)


static func _flat(_p: Vector2) -> float:
	return 0.0


static func _up(_p: Vector2) -> Vector3:
	return Vector3.UP


## {asset id: "count:md5"} of one biome's rows at the fixed seed over the fixed square.
static func digest(biome_id: String, root: String) -> Dictionary:
	var bounds := Rect2(-HALF_M, -HALF_M, 2.0 * HALF_M, 2.0 * HALF_M)
	var rows := ScatterGenerator.generate(
		biome_id,
		PaletteLibrary.species(biome_id, root),
		_density,
		_flat,
		_up,
		SEED,
		ScatterGenerator.cells_in_bounds(bounds),
		bounds
	)
	var out := {}
	for asset_id: String in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_MD5)
		hashing.update(flat.to_byte_array())
		out[asset_id] = (
			"%d:%s" % [flat.size() / MapDocument.ROW_STRIDE, hashing.finish().hex_encode()]
		)
	return out


## {runtime biome id: {biome, species, rows}, "assets": the assets table} for `runtimes`.
static func snapshot(root: String, runtimes: Array) -> Dictionary:
	var out := {}
	var entries := {}
	for entry: Dictionary in PaletteLibrary.biomes(root):
		entries[entry["id"]] = entry
	for runtime: String in runtimes:
		var entry: Dictionary = (entries[runtime] as Dictionary).duplicate(true)
		entry.erase("species")
		out[runtime] = {
			"biome": entry,
			"species": PaletteLibrary.species(runtime, root),
			"rows": digest(runtime, root),
		}
	out["assets"] = (PaletteLibrary.get_palette(root)["assets"] as Dictionary).duplicate(true)
	return out


## {library asset id: package stem} from a library folder's catalog (`package_stem`, else the id).
static func stems_of(library_folder: String) -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string(library_folder.path_join("assets/catalog.json"))
	var catalog: Variant = JSON.parse_string(text)
	if catalog is Dictionary:
		for entry: Dictionary in (catalog as Dictionary).get("assets", []):
			out[String(entry["id"])] = String(entry.get("package_stem", entry["id"]))
	return out


## `<runtime>/<library id>` as `<runtime>/<package stem>`.
static func package_id(full: String, stems: Dictionary) -> String:
	var runtime := full.get_slice("/", 0)
	var local := full.substr(runtime.length() + 1)
	return "%s/%s" % [runtime, stems.get(local, local)]


## A library snapshot with its asset ids turned into the package's.
static func mapped(library: Dictionary, stems: Dictionary) -> Dictionary:
	var out := {}
	for key: String in library:
		if key == "assets":
			var table := {}
			for id: String in library["assets"]:
				table[package_id(id, stems)] = library["assets"][id]
			out["assets"] = table
			continue
		var item: Dictionary = (library[key] as Dictionary).duplicate(true)
		var rows := {}
		for id: String in item["rows"]:
			rows[package_id(id, stems)] = item["rows"][id]
		item["rows"] = rows
		for rule: Dictionary in item["species"]:
			var ids: Array[String] = []
			for id: String in rule.get("assets", []):
				ids.append(package_id(id, stems))
			rule["assets"] = ids
		out[key] = item
	return out


## A rule without the authoring-only fields, as JSON text (the same text for equal rules).
static func rule_text(rule: Dictionary) -> String:
	var copy := rule.duplicate(true)
	for field in AUTHORING_FIELDS:
		copy.erase(field)
	return JSON.stringify(copy, "", true)


## The plan role and habit the scatter code derives for each rule of a biome, in rule order.
static func plans(species: Array) -> Array[String]:
	var out: Array[String] = []
	for rule: Dictionary in species:
		out.append(
			"%s|%s" % [JSON.stringify(ScatterGround.habit_of(rule), "", true), rule.get("kind", "")]
		)
	return out
