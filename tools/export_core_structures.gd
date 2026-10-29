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
## The starters' default `wonk` (0..1) and the thatched cottages' `fringe` (metres).
const HANDMADE_WONK := 0.7
const THATCH_FRINGE_M := 0.35
var pin_plan := PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])

## The starter set. `recipe` says how ProcgenRecipes.building makes the document (every recipe is
## glazed and exposes the `ridge` choice; the keys are `roof`, `walls`, `style`, `trim` ("" or the
## set's name: "townhouse" or "cottage"), `furniture`, and the interface defaults `height`,
## `chimneys`, `ridge` and `window_width` where they differ from the builder's). A starter's
## default ridge is 0 (the plan's longer side) unless its recipe says otherwise, so the first five
## keep the pins they had before `ridge` existed (their recipe files gain only the interface entry).
const STARTERS: Array[Dictionary] = [
	{
		"id": "stone_house",
		"recipe": {"roof": "gable", "walls": "stone", "style": "", "trim": "", "furniture": []},
		"name": "Stone house",
		"family": "house",
		"variant": "Stone",
		"tags": ["house", "stone", "gable"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "roof_pitch", "ridge"],
	},
	{
		"id": "cottage",
		"recipe":
		{
			"roof": "gable",
			"walls": "timber",
			"style": "cottage",
			"trim": "",
			"furniture": [],
			"fringe": THATCH_FRINGE_M
		},
		"name": "Cottage",
		"family": "cottage",
		"variant": "Timber",
		"tags": ["house", "timber", "gable"],
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	{
		"id": "cottage_chimneyed",
		"recipe":
		{
			"roof": "gable",
			"walls": "timber",
			"style": "cottage",
			"trim": "cottage",
			"furniture": ["chimneys"],
			"fringe": THATCH_FRINGE_M
		},
		"name": "Cottage with chimney",
		"family": "cottage",
		"variant": "Timber, chimney",
		"tags": ["house", "timber", "gable", "chimney", "shutters"],
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "townhouse",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "",
			"furniture": [],
			"height": 5.2
		},
		"name": "Townhouse",
		"family": "townhouse",
		"variant": "Plain",
		"tags": ["house", "stone", "gable", "townhouse"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	{
		"id": "townhouse_trimmed",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": [],
			"height": 5.2
		},
		"name": "Townhouse, trimmed",
		"family": "townhouse",
		"variant": "Trimmed",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	# The street-split card's widening (2026-10-28): the roofs, walls and chimneys a street's
	# species draw that the five above cannot show.
	{
		"id": "townhouse_timber",
		"recipe":
		{
			"roof": "gable",
			"walls": "timber",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": [],
			"height": 5.2
		},
		"name": "Timber townhouse",
		"family": "townhouse",
		"variant": "Timber",
		"tags": ["house", "timber", "gable", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	{
		"id": "townhouse_chimneyed",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": ["end_chimneys"],
			"height": 5.2,
			"chimneys": 2
		},
		"name": "Townhouse with chimneys",
		"family": "townhouse",
		"variant": "Chimneys",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins", "chimney"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "townhouse_end",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": ["end_chimneys"],
			"height": 5.2,
			"chimneys": 2,
			"ridge": 2
		},
		"name": "Terrace-end house",
		"family": "townhouse",
		"variant": "Gable to the front",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins", "chimney", "end"],
		"min_side_m": 3.0,
		"max_side_m": 20.0,
		"max_area_m2": 180.0,
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "townhouse_flat",
		"recipe":
		{
			"roof": "flat",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": [],
			"height": 5.2
		},
		"name": "Flat-roofed townhouse",
		"family": "townhouse",
		"variant": "Flat roof",
		"tags": ["house", "stone", "flat", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors"],
	},
	{
		"id": "townhouse_hip",
		"recipe":
		{
			"roof": "hip",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": ["end_chimneys"],
			"height": 5.2,
			"chimneys": 2
		},
		"name": "Hip-roof townhouse",
		"family": "townhouse",
		"variant": "Hip roof",
		"tags": ["house", "stone", "hip", "townhouse", "trim", "quoins", "chimney"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "cottage_hip",
		"recipe":
		{
			"roof": "hip",
			"walls": "timber",
			"style": "cottage",
			"trim": "cottage",
			"furniture": ["chimneys"]
		},
		"name": "Hip-roof cottage",
		"family": "cottage",
		"variant": "Timber, hip roof",
		"tags": ["house", "timber", "hip", "chimney", "shutters"],
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "house_hip",
		"recipe":
		{
			"roof": "hip",
			"walls": "stone",
			"style": "",
			"trim": "",
			"furniture": [],
			"window_width": 0.9
		},
		"name": "Stone house, hip roof",
		"family": "house",
		"variant": "Stone, hip roof",
		"tags": ["house", "stone", "hip"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "roof_pitch", "window_width", "ridge"],
	},
	{
		"id": "house_flat",
		"recipe":
		{
			"roof": "flat",
			"walls": "stone",
			"style": "",
			"trim": "",
			"furniture": [],
			"window_width": 0.9
		},
		"name": "Stone house, flat roof",
		"family": "house",
		"variant": "Stone, flat roof",
		"tags": ["house", "stone", "flat"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "window_width"],
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
		var doc := _document_of(starter["recipe"] as Dictionary)
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
					"expose": _exposed(starter),
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


## The ProcgenRecipes document of starter recipe `spec` (see STARTERS), with glazing, the ridge
## choice and the handmade look on (ProcgenRecipes.building's last three arguments; the named
## builders do not pass them). The handmade look is the starter set's default (2026-10-28 look
## integration): `wonk` (default 0.7) for every starter, `fringe` (the ragged thatch edge, metres)
## only where the recipe names it, on the timber gable cottages.
func _document_of(spec: Dictionary) -> PlantGraphDocument:
	var trim: Array = []
	match String(spec.get("trim", "")):
		"townhouse":
			trim = ProcgenRecipes.TOWNHOUSE_TRIM
		"cottage":
			trim = ProcgenRecipes.COTTAGE_TRIM
	var doc := ProcgenRecipes.building(
		String(spec["roof"]),
		String(spec["walls"]),
		String(spec["style"]),
		trim,
		spec["furniture"] as Array,
		true,
		true,
		true
	)
	_set_default(doc, "wonk", float(spec.get("wonk", HANDMADE_WONK)))
	for key: String in ["height", "chimneys", "ridge", "window_width", "fringe"]:
		if spec.has(key):
			_set_default(doc, key, float(spec[key]))
	return doc


## The starter's `expose` list plus the handmade look's controls (`wonk` on all, `fringe` where set).
static func _exposed(starter: Dictionary) -> Array:
	var out: Array = (starter["expose"] as Array).duplicate()
	out.append("wonk")
	if (starter["recipe"] as Dictionary).has("fringe"):
		out.append("fringe")
	return out


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
