extends SceneTree

## Headless: writes the `structures/` kind of the core library (card S3): the starter recipes as
## `structures/<id>.structure.json` (procgen's ProcgenRecipes documents, unmodified), the index
## `structures/index.json` and `structures/pins.txt` (one line per structure, the digest of what
## tt-sim's pipeline builds at the fixed footprint and seed). The files are DATA committed in the
## core-library repo; this tool is how they were made and how a change to a recipe or to the
## pipeline is re-pinned on purpose.
##
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/export_core_structures.gd -- \
##       --out D:/dev/tabletop/core-library [--check 1]
##
## --check 1 writes nothing and exits 1 when a file on disk differs from what the tool makes.
## pins.txt lines: `<id> <pipeline digest> <triangles> <procgen digest>`. The pipeline digest is
## StructureGeometry.digest_of (the surfaces split by material role, what a host reads), the
## procgen digest ProcgenBuildingCases.digest (procgen's raw surfaces). The footprint is a 6 by 4 m
## rectangle centred on the origin of a flat 20 by 20 cell map, the seed 5, `textured` on, the
## same inputs as tests/fixtures/structure_digests.txt.

const PIN_SEED := 5
var pin_plan := PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])

## The starter set. `builder` is the ProcgenRecipes function that makes the document.
const STARTERS: Array[Dictionary] = [
	{
		"id": "stone_house",
		"builder": "building",
		"name": "Stone house",
		"family": "house",
		"variant": "Stone",
		"tags": ["house", "stone", "gable"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "roof_pitch"],
	},
	{
		"id": "cottage",
		"builder": "cottage",
		"name": "Cottage",
		"family": "cottage",
		"variant": "Timber",
		"tags": ["house", "timber", "gable"],
		"expose": ["height", "floors", "roof_pitch"],
	},
	{
		"id": "cottage_chimneyed",
		"builder": "cottage_chimneyed",
		"name": "Cottage with chimney",
		"family": "cottage",
		"variant": "Timber, chimney",
		"tags": ["house", "timber", "gable", "chimney", "shutters"],
		"expose": ["height", "floors", "roof_pitch", "chimneys"],
	},
	{
		"id": "townhouse",
		"builder": "townhouse",
		"name": "Townhouse",
		"family": "townhouse",
		"variant": "Plain",
		"tags": ["house", "stone", "gable", "townhouse"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch"],
	},
	{
		"id": "townhouse_trimmed",
		"builder": "townhouse_trimmed",
		"name": "Townhouse, trimmed",
		"family": "townhouse",
		"variant": "Trimmed",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch"],
	},
]


func _initialize() -> void:
	var args := _args()
	var out_dir := String(args.get("out", ""))
	if out_dir == "":
		printerr("--out <core-library folder> is required")
		quit(2)
		return
	var check := String(args.get("check", "")) in ["1", "true"]
	var made := _make()
	var problems := 0
	for relative: String in made["files"]:
		var path := out_dir.path_join(relative)
		var text := String(made["files"][relative])
		if check:
			var have := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
			if have != text:
				printerr("differs: %s" % relative)
				problems += 1
			continue
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("cannot write %s" % path)
			quit(2)
			return
		file.store_string(text)
		file.close()
	for line: String in made["pins"]:
		print(line)
	for warning: String in made["warnings"]:
		printerr("warning: " + warning)
	print("%d files %s" % [(made["files"] as Dictionary).size(), "checked" if check else "written"])
	quit(1 if problems > 0 else 0)


## {files: {library-relative path: text}, pins: [line], warnings: [text]}.
func _make() -> Dictionary:
	var files := {}
	var warnings: Array[String] = []
	var entries: Array = []
	var texts := {}
	for starter in STARTERS:
		var id := String(starter["id"])
		var doc := _document_of(String(starter["builder"]))
		var text := doc.to_json()
		# The shipped recipes are procgen's builders with glazing on (a pane in every window, a leaf
		# in every door), so they differ from procgen's committed `recipes/` files by that node.
		files[LibraryStructures.recipe_path(id)] = text
		texts["core:" + id] = text
		var declares_textured := false
		for entry in doc.interface:
			declares_textured = declares_textured or String(entry.get("name", "")) == "textured"
		(
			entries
			. append(
				{
					"id": id,
					"name": starter["name"],
					"family": starter["family"],
					"variant": starter["variant"],
					"tags": starter["tags"],
					"file": LibraryStructures.recipe_path(id),
					"default_size_m": [6, 4],
					"min_side_m": starter.get("min_side_m", LibraryStructures.DEFAULT_MIN_SIDE_M),
					"max_side_m": starter.get("max_side_m", LibraryStructures.DEFAULT_MAX_SIDE_M),
					"max_area_m2":
					starter.get("max_area_m2", LibraryStructures.DEFAULT_MAX_AREA_M2),
					"plans": ["rect"],
					"expose": starter["expose"],
					"textured": declares_textured,
					"thumb": LibraryStructures.thumb_path(id),
				}
			)
		)
	files[LibraryStructures.INDEX_FILE] = LibraryStructures.index_text(entries)
	StructureRecipes.resolver = func(ref: String) -> Dictionary:
		return {"text": texts[ref]} if texts.has(ref) else {}
	var pins: Array[String] = []
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	for starter in STARTERS:
		var ref := "core:" + String(starter["id"])
		var parts := StructureGeometry.build_one(doc, Structure.make(1, ref, pin_plan, PIN_SEED))
		if String(parts["problem"]) != "":
			warnings.append("%s: %s" % [ref, parts["problem"]])
		pins.append(
			(
				"%s %s %d %s"
				% [
					starter["id"],
					StructureGeometry.digest_of(parts),
					StructureGeometry.triangle_count(parts),
					_raw_digest(doc, ref)
				]
			)
		)
	files[LibraryStructures.PINS_FILE] = "\n".join(pins) + "\n"
	StructureRecipes.resolver = Callable()
	return {"files": files, "pins": pins, "warnings": warnings}


## The ProcgenRecipes document of builder `name`, with glazing on (ProcgenRecipes.building's last
## argument; the named builders do not pass it, so their arguments are repeated here).
func _document_of(name: String) -> PlantGraphDocument:
	var doc: PlantGraphDocument = null
	match name:
		"building":
			doc = ProcgenRecipes.building("gable", "stone", "", [], [], true)
		"cottage":
			doc = ProcgenRecipes.building("gable", "timber", "cottage", [], [], true)
		"cottage_chimneyed":
			doc = ProcgenRecipes.building(
				"gable", "timber", "cottage", ProcgenRecipes.COTTAGE_TRIM, ["chimneys"], true
			)
		"townhouse":
			doc = ProcgenRecipes.building("gable", "stone", "townhouse", [], [], true)
			_set_default(doc, "height", 5.2)
		"townhouse_trimmed":
			doc = ProcgenRecipes.building(
				"gable", "stone", "townhouse", ProcgenRecipes.TOWNHOUSE_TRIM, [], true
			)
			_set_default(doc, "height", 5.2)
	return doc


static func _set_default(doc: PlantGraphDocument, name: String, value: float) -> void:
	for entry in doc.interface:
		if entry["name"] == name:
			entry["default"] = value


## procgen's own digest of the same build (ProcgenBuildingCases.digest of the first LOD).
func _raw_digest(doc: MapDocument, ref: String) -> String:
	var recipe := StructureRecipes.document(ref)
	if recipe == null:
		return "-"
	var structure := Structure.make(1, ref, pin_plan, PIN_SEED)
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(
		recipe, StructureGeometry.inputs_for(doc, structure, recipe), true
	)
	if plant == null:
		return "-"
	return ProcgenBuildingCases.digest((plant as Dictionary)["lods"][0])


func _args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		if raw[i].begins_with("--") and i + 1 < raw.size():
			out[raw[i].trim_prefix("--")] = raw[i + 1]
			i += 2
		else:
			i += 1
	return out
