class_name LibraryStructures
extends RefCounted

## The `structures/` kind of a content library (card S3, docs/systems/structures.md and
## docs/systems/library.md "Structures"): `structures/index.json` lists the building recipes a
## library offers, `structures/<id>.structure.json` is each one's procgen graph document, and
## `thumbnails/structures/<id>.jpg` its palette tile. Pure: it is handed texts and file lists (the
## way LibraryReader is) and never touches a folder.
##
## Everything here is untrusted input. A recipe is DATA run by procgen's fixed set of node types,
## so a hostile library can only be expensive, never harmful; the guards are caps on the bytes,
## the nodes and the connections before the document is built, node types the structure registry
## knows, and no nested tables in a node's parameters. GDScript cannot interrupt an evaluation, so
## the cost is bounded by these input caps (and by the footprint caps of MapStructureIO). A bad
## structure is a WARNING and is left out; it never blocks the library.

const DIR := "structures/"
const INDEX_FILE := "structures/index.json"
const PINS_FILE := "structures/pins.txt"
const RECIPE_SUFFIX := ".structure.json"
const THUMB_DIR := "thumbnails/structures/"
const GRAPH_FORMAT := "plantgen-graph"
## Defaults an index entry may leave out.
const DEFAULT_SIZE_M := Vector2(6.0, 4.0)
const DEFAULT_MIN_SIDE_M := 2.5
const DEFAULT_MAX_SIDE_M := 14.0
const DEFAULT_MAX_AREA_M2 := 120.0
## The largest side or area any entry may claim (MapStructureIO.MAX_SPAN_M, squared).
const LIMIT_SIDE_M := 64.0
const LIMIT_AREA_M2 := 4096.0
const MAX_TAGS := 16
const MAX_NAME := 48
const MAX_INTERFACE := 64
## The tile scene (thumbnail_job): a new map this many feet wide painted with this biome (an
## open meadow, so nothing grows into the picture), the camera
## `TILE_ZOOM_BASE_M + longest side * TILE_ZOOM_PER_M` metres out (orthographic size), looking
## `TILE_LOOK_Z` metres along the map's z from the centre.
const TILE_MAP_FT := 100
const TILE_BIOME := "grassland_meadow_summer_s1"
const TILE_SEED := 1234
const TILE_STRUCTURE_SEED := 5
const TILE_ZOOM_BASE_M := 4.5
const TILE_ZOOM_PER_M := 0.9
## Each metre of wall height above TILE_DEFAULT_HEIGHT_M (a one storey cottage) adds this much.
const TILE_DEFAULT_HEIGHT_M := 2.4
const TILE_ZOOM_PER_HEIGHT_M := 1.9
const TILE_LOOK_Z := 0.0
const TILE_SETTLE_S := 3.0
const TILE_JOB_TIMEOUT_S := 900

static var _param_re: RegEx = _compile("^[a-z][a-z0-9_]*$")


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


## The library-relative file of structure `id`'s recipe.
static func recipe_path(id: String) -> String:
	return "%s%s%s" % [DIR, id, RECIPE_SUFFIX]


## The library-relative file of structure `id`'s thumbnail.
static func thumb_path(id: String) -> String:
	return "%s%s.jpg" % [THUMB_DIR, id]


## The reference a map stores for structure `id` of library `library_id`.
static func ref_of(library_id: String, id: String) -> String:
	return "%s:%s" % [library_id, id]


# ---- reading ----


## Fills result["structures"] (and result["structure_order"]) from `raw`, the "structures" part of
## the reader's sources: {"index": String (structures/index.json), "recipes": {file name: text}}.
## Each result entry is {id, file, entry (the cleaned index entry), digest (sha256 of the recipe
## text)}, in index order. `files` is the library's file list (empty when unknown): it is only
## used to see whether a thumbnail exists. Problems are appended to `warnings`.
static func read(raw: Variant, files: Array, have_files: bool, result: Dictionary) -> void:
	result["structures"] = [] as Array[Dictionary]
	if not raw is Dictionary:
		return
	var warnings: Array[String] = result["warnings"]
	var index_text := String((raw as Dictionary).get("index", ""))
	if index_text == "":
		return
	var index := _parse_object(
		index_text, INDEX_FILE, int(LibraryContracts.STRUCTURE_CAPS["index_bytes"]), warnings
	)
	if index.is_empty():
		return
	_unknown(index, LibraryContracts.STRUCTURE_KEYS, INDEX_FILE, warnings)
	if index.get("format") != LibraryContracts.FORMAT_STRUCTURES:
		warnings.append(
			(
				"%s: format must be '%s' (the structures are ignored)"
				% [INDEX_FILE, LibraryContracts.FORMAT_STRUCTURES]
			)
		)
		return
	var version: Variant = index.get("format_version")
	if (
		not (version is int or version is float)
		or int(version) < 1
		or int(version) > LibraryContracts.FORMAT_VERSION
	):
		warnings.append(
			(
				"%s: format_version is not one this build reads (the structures are ignored)"
				% INDEX_FILE
			)
		)
		return
	var listed: Variant = index.get("structures")
	if not listed is Array:
		warnings.append("%s: structures is missing or not a list" % INDEX_FILE)
		return
	var cap := int(LibraryContracts.STRUCTURE_CAPS["structures"])
	var items: Array = listed
	if items.size() > cap:
		warnings.append(
			(
				"%s: %d structures over the cap of %d (the rest are ignored)"
				% [INDEX_FILE, items.size(), cap]
			)
		)
		items = items.slice(0, cap)
	var recipes: Dictionary = (raw as Dictionary).get("recipes", {}) as Dictionary
	var registry := ProcgenStructureRegistry.new()
	var seen := {}
	var out: Array[Dictionary] = result["structures"]
	for position in items.size():
		var made := _read_entry(
			items[position], position, recipes, files, have_files, registry, seen, warnings
		)
		if not made.is_empty():
			out.append(made)
			seen[String(made["id"])] = true


static func _read_entry(
	raw: Variant,
	position: int,
	recipes: Dictionary,
	files: Array,
	have_files: bool,
	registry: ProcgenRegistry,
	seen: Dictionary,
	warnings: Array[String]
) -> Dictionary:
	var where := "%s: structure %d" % [INDEX_FILE, position]
	if not raw is Dictionary:
		warnings.append("%s is not an object (ignored)" % where)
		return {}
	var entry: Dictionary = raw
	var id := String(entry.get("id", "")) if entry.get("id") is String else ""
	if not LibraryIds.biome_problems(id).is_empty():
		warnings.append("%s: id must match [a-z][a-z0-9_]* (at most 48, no '__'); ignored" % where)
		return {}
	where = "%s: structure '%s'" % [INDEX_FILE, id]
	if seen.has(id):
		warnings.append("%s repeats (ignored)" % where)
		return {}
	_unknown(entry, LibraryContracts.STRUCTURE_ENTRY_KEYS, where, warnings)
	var file := recipe_path(id)
	if entry.has("file") and entry["file"] != file:
		warnings.append("%s: file must be '%s' (ignored)" % [where, file])
		return {}
	var text := String(recipes.get(file.get_file(), ""))
	var problem := recipe_problem(text, registry)
	if problem != "":
		warnings.append("%s: recipe %s %s (ignored)" % [where, file, problem])
		return {}
	var recipe := _parse_object(
		text, file, int(LibraryContracts.STRUCTURE_CAPS["recipe_bytes"]), [] as Array[String]
	)
	var clean := _clean_entry(entry, id, recipe, where, warnings)
	if clean.is_empty():
		return {}
	var thumb := String(clean["thumb"])
	if have_files and thumb != "" and not thumb in files:
		warnings.append(
			"%s: thumbnail %s is missing (the tile shows a placeholder)" % [where, thumb]
		)
		clean["thumb"] = ""
	return {
		"id": id,
		"file": file,
		"entry": clean,
		"digest": text.sha256_text(),
		"height_m": default_height(recipe),
	}


## The default of the recipe's `height` interface parameter (the wall height in metres), 2.4 when
## it declares none, plus the height of every `stack` node (a storey on top, a number in its
## params): what a tile's framing needs to fit a tall building.
static func default_height(recipe: Dictionary) -> float:
	var base := TILE_DEFAULT_HEIGHT_M
	var declared: Variant = recipe.get("interface")
	if declared is Array:
		for item: Variant in declared as Array:
			if (
				item is Dictionary
				and (item as Dictionary).get("name") == "height"
				and (
					(item as Dictionary).get("default") is float
					or (item as Dictionary).get("default") is int
				)
			):
				base = float((item as Dictionary)["default"])
	var nodes: Variant = recipe.get("nodes")
	var top := base
	if nodes is Array:
		for node: Variant in nodes as Array:
			if not node is Dictionary:
				continue
			var params: Variant = (node as Dictionary).get("params")
			if not params is Dictionary:
				continue
			var values: Dictionary = params
			match (node as Dictionary).get("type"):
				"stack":
					if values.get("height") is float:
						base += float(values["height"])
						top = maxf(top, base)
				"tower":
					# A tower stands `extra` above the building under a roof about as high as 0.8 of
					# its width (a spire more, a flat top none).
					top = maxf(
						top, base + _num(values.get("extra")) + 0.8 * _num(values.get("size"))
					)
				"roof_profile":
					# A pagoda's tiers pile up above the wall.
					var tiers := _num(values.get("tiers"))
					if tiers > 0.0:
						top = maxf(
							top,
							(
								base
								+ tiers * _num(values.get("tier_height"))
								+ _num(values.get("finial"))
							)
						)
	return clampf(maxf(base, top), 1.0, 16.0)


static func _num(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0


## The index entry with every field checked and defaulted, or {} (with a warning) when its size
## limits cannot hold its own default footprint.
static func _clean_entry(
	entry: Dictionary, id: String, recipe: Dictionary, where: String, warnings: Array[String]
) -> Dictionary:
	var name := _text(entry.get("name"), MAX_NAME, id)
	var size := _pair(entry.get("default_size_m"), DEFAULT_SIZE_M)
	var min_side := _number(entry.get("min_side_m"), DEFAULT_MIN_SIDE_M, 0.5, LIMIT_SIDE_M)
	var max_side := _number(entry.get("max_side_m"), DEFAULT_MAX_SIDE_M, 0.5, LIMIT_SIDE_M)
	var max_area := _number(entry.get("max_area_m2"), DEFAULT_MAX_AREA_M2, 1.0, LIMIT_AREA_M2)
	if (
		min_side > max_side
		or size.x < min_side
		or size.y < min_side
		or size.x > max_side
		or size.y > max_side
		or size.x * size.y > max_area
	):
		(
			warnings
			. append(
				(
					"%s: default_size_m %s does not fit min_side_m, max_side_m and max_area_m2 (ignored)"
					% [where, str(size)]
				)
			)
		)
		return {}
	var plans: Array = []
	for plan: Variant in entry.get("plans", ["rect"]) if entry.get("plans") is Array else ["rect"]:
		if plan is String and plan in LibraryContracts.STRUCTURE_PLANS and not plan in plans:
			plans.append(plan)
		else:
			warnings.append("%s: plans holds a bad entry (dropped)" % where)
	if plans.is_empty():
		plans = ["rect"]
	# The cleaned plans decide whether the entry is round; the index's own `sides` and tags give the
	# corner count.
	var shape := entry.duplicate()
	shape["plans"] = plans
	for problem: String in ProcgenStructureIndex.sides_errors(shape):
		warnings.append("%s: %s (ignored)" % [where, problem])
	var thumb := thumb_path(id)
	if entry.get("thumb") is String:
		var given := String(entry["thumb"])
		if given == "":
			thumb = ""
		elif (
			LibraryIds.path_problems(given).is_empty()
			and given.begins_with("thumbnails/")
			and given.get_extension().to_lower() == "jpg"
		):
			thumb = given
		else:
			warnings.append("%s: thumb must be a thumbnails/ .jpg path (default used)" % where)
	var clean := {
		"id": id,
		"name": name,
		"family": _text(entry.get("family"), MAX_NAME, id),
		"variant": _text(entry.get("variant"), MAX_NAME, ""),
		"tags": _tags(entry.get("tags"), where, warnings),
		"file": recipe_path(id),
		"default_size_m": [size.x, size.y],
		"min_side_m": min_side,
		"max_side_m": max_side,
		"max_area_m2": max_area,
		"plans": plans,
		"expose": _expose(entry.get("expose"), recipe, where, warnings),
		"textured": entry.get("textured") == true,
		"thumb": thumb,
	}
	# A round entry always carries its corner count, as a key (a legacy `sides:<n>` tag or the
	# default fills it in); a rectangle has none.
	if ProcgenStructureIndex.is_round(clean):
		clean["sides"] = ProcgenStructureIndex.sides_of(shape)
	return clean


static func _tags(raw: Variant, where: String, warnings: Array[String]) -> Array:
	var out: Array = []
	if raw == null:
		return out
	if not raw is Array:
		warnings.append("%s: tags is not a list (dropped)" % where)
		return out
	for tag: Variant in raw as Array:
		if tag is String and String(tag) != "" and String(tag).length() <= 32 and not tag in out:
			out.append(tag)
		else:
			warnings.append("%s: a tag is not a short text (dropped)" % where)
		if out.size() >= MAX_TAGS:
			break
	return out


## The names of `expose` that the recipe's interface declares; the others are dropped.
static func _expose(
	raw: Variant, recipe: Dictionary, where: String, warnings: Array[String]
) -> Array:
	var out: Array = []
	if raw == null:
		return out
	if not raw is Array or (raw as Array).size() > int(LibraryContracts.STRUCTURE_CAPS["expose"]):
		warnings.append("%s: expose is not a short list (dropped)" % where)
		return out
	var declared := interface_names(recipe)
	for name: Variant in raw as Array:
		if name is String and name in declared and not name in out:
			out.append(name)
		else:
			warnings.append(
				(
					"%s: expose names '%s', which the recipe's interface lacks (dropped)"
					% [where, str(name).left(32)]
				)
			)
	return out


## The parameter names a recipe document (parsed JSON) declares in its `interface`.
static func interface_names(recipe: Dictionary) -> Array:
	var out: Array = []
	var declared: Variant = recipe.get("interface")
	if declared is Array:
		for item: Variant in declared as Array:
			if item is Dictionary and (item as Dictionary).get("name") is String:
				out.append(String((item as Dictionary)["name"]))
	return out


# ---- the recipe document ----


## "" when `text` is a recipe the game may build, else what is wrong with it (a short phrase). The
## checks run before PlantGraphDocument.from_json sees the text, because from_dict indexes keys
## directly: size, JSON, the format tag, node and connection counts, every node an object with a
## text id and a registered type, parameters without nested tables, connections between known
## nodes, an interface of well named entries. `registry` is reused across calls (null makes one).
static func recipe_problem(text: String, registry: ProcgenRegistry = null) -> String:
	if text == "":
		return "is missing or empty"
	var cap := int(LibraryContracts.STRUCTURE_CAPS["recipe_bytes"])
	if text.to_utf8_buffer().size() > cap:
		return "is over %d bytes" % cap
	var json := JSON.new()
	if json.parse(text) != OK:
		return "is not valid JSON"
	if not json.data is Dictionary:
		return "is not a JSON object"
	var data: Dictionary = json.data
	if data.get("format") != GRAPH_FORMAT:
		return "is not a '%s' document" % GRAPH_FORMAT
	var nodes: Variant = data.get("nodes")
	if not nodes is Array or (nodes as Array).is_empty():
		return "has no nodes"
	if (nodes as Array).size() > int(LibraryContracts.STRUCTURE_CAPS["recipe_nodes"]):
		return "has more than %d nodes" % int(LibraryContracts.STRUCTURE_CAPS["recipe_nodes"])
	var known: ProcgenRegistry = registry if registry != null else ProcgenStructureRegistry.new()
	var ids := {}
	for raw: Variant in nodes as Array:
		var why := _node_problem(raw, known, ids)
		if why != "":
			return why
	var connections: Variant = data.get("connections", [])
	if not connections is Array:
		return "has connections that are not a list"
	if (connections as Array).size() > int(LibraryContracts.STRUCTURE_CAPS["recipe_connections"]):
		return (
			"has more than %d connections"
			% int(LibraryContracts.STRUCTURE_CAPS["recipe_connections"])
		)
	for raw: Variant in connections as Array:
		if not raw is Dictionary:
			return "has a connection that is not an object"
		var link: Dictionary = raw
		if not (ids.has(link.get("from")) and ids.has(link.get("to"))):
			return "has a connection between unknown nodes"
		for port: String in ["from_port", "to_port"]:
			if not link.get(port) is int and not link.get(port) is float:
				return "has a connection without port numbers"
	return _interface_problem(data.get("interface", []))


static func _node_problem(raw: Variant, registry: ProcgenRegistry, ids: Dictionary) -> String:
	if not raw is Dictionary:
		return "has a node that is not an object"
	var node: Dictionary = raw
	if not node.get("id") is String or String(node["id"]) == "" or String(node["id"]).length() > 64:
		return "has a node without a short text id"
	if ids.has(node["id"]):
		return "repeats a node id"
	ids[node["id"]] = true
	if not node.get("type") is String or not registry.has_type(String(node["type"])):
		return "uses a node type this game does not know"
	var position: Variant = node.get("position", [0, 0])
	if not position is Array or (position as Array).size() != 2:
		return "has a node position that is not a pair"
	for part: Variant in position as Array:
		if not (part is int or part is float) or is_nan(float(part)) or is_inf(float(part)):
			return "has a node position that is not a number"
	var params: Variant = node.get("params", {})
	if not params is Dictionary:
		return "has node parameters that are not an object"
	for value: Variant in (params as Dictionary).values():
		if value is Dictionary or (value is Array and not _flat(value as Array)):
			return "has a node parameter that holds a table"
	return ""


static func _flat(items: Array) -> bool:
	for item: Variant in items:
		if item is Dictionary or item is Array:
			return false
	return true


static func _interface_problem(declared: Variant) -> String:
	if not declared is Array or (declared as Array).size() > MAX_INTERFACE:
		return "has an interface that is not a short list"
	for item: Variant in declared as Array:
		if not item is Dictionary:
			return "has an interface entry that is not an object"
		var name: Variant = (item as Dictionary).get("name")
		if (
			not name is String
			or _param_re.search(String(name)) == null
			or String(name).length() > 32
		):
			return "has an interface entry without a well formed name"
		for value: Variant in (item as Dictionary).values():
			if value is Dictionary or (value is Array and not _flat(value as Array)):
				return "has an interface entry that holds a table"
	return ""


# ---- the thumbnail render job ----


## The render job (tools/render_jobs/REFERENCE.md's JSON form) that draws one tile per entry of
## `items` (the reader's "structures" results) of library `library_id` and writes each to
## `dest_folder`/thumbnails/structures/<id>.jpg through the driver's `thumbnail` op (`structure`
## true). `serve_folder` is the library folder to lay over the game as the developer override
## ("" when the library is already served, as core is). Each tile is also a capture
## (`tile_<id>`) in the job's output folder, for a look. One map, one structure at a time, laid
## at the default footprint through the editor API (probes/structures.gd `tile`).
static func thumbnail_job(
	library_id: String, items: Array, dest_folder: String, serve_folder: String = ""
) -> Dictionary:
	var steps: Array = [{"op": "wait", "s": 1.0}, {"op": "wait_title"}]
	if serve_folder != "":
		steps.append({"op": "library_dev", "path": serve_folder})
		steps.append({"op": "wait", "s": 2.0})
	steps.append({"op": "new_map", "biome": TILE_BIOME, "size": TILE_MAP_FT, "seed": TILE_SEED})
	steps.append({"op": "wait_ready", "settle": TILE_SETTLE_S})
	steps.append({"op": "no_autosave"})
	steps.append({"op": "hide_ui"})
	for item: Dictionary in items:
		var entry: Dictionary = item["entry"]
		var size: Array = entry["default_size_m"]
		var longest := maxf(float(size[0]), float(size[1]))
		(
			steps
			. append(
				{
					"op": "call",
					"script": "res://tools/render_jobs/probes/structures.gd",
					"action": "tile",
					"ref": ref_of(library_id, String(item["id"])),
					"width": float(size[0]),
					"depth": float(size[1]),
					"sides": StructurePlacement.sides_of(entry),
					"seed": TILE_STRUCTURE_SEED,
				}
			)
		)
		steps.append({"op": "wait", "s": 1.0})
		(
			steps
			. append(
				{
					"op": "thumbnail_prepare",
					"zoom": _tile_zoom(longest, float(item.get("height_m", TILE_DEFAULT_HEIGHT_M))),
					"at": [0.0, TILE_LOOK_Z],
				}
			)
		)
		steps.append({"op": "settle"})
		(
			steps
			. append(
				{
					"op": "thumbnail",
					"structure": true,
					"biome": String(item["id"]),
					"folder": dest_folder,
				}
			)
		)
		steps.append(
			{
				"op": "capture",
				"name": "tile_" + String(item["id"]),
				"desc": "The tile of " + entry["name"]
			}
		)
	steps.append({"op": "title"})
	steps.append({"op": "wait", "s": 0.5})
	return {
		"out_dir": "render_jobs/structure_thumbs",
		"timeout_s": TILE_JOB_TIMEOUT_S,
		"hang_s": 120,
		"steps": steps,
	}


## The camera size of a tile for a building whose longest side is `longest` and whose walls are
## `height` metres high.
static func _tile_zoom(longest: float, height: float) -> float:
	var extra := maxf(0.0, height - TILE_DEFAULT_HEIGHT_M) * TILE_ZOOM_PER_HEIGHT_M
	return TILE_ZOOM_BASE_M + longest * TILE_ZOOM_PER_M + extra


# ---- writing and trimming (pure data, the host side of a transfer, the export tool) ----


## Canonical text of an index holding `entries` (cleaned entries): sorted keys, tab indent, a
## final newline, so two builds of the same content are the same bytes.
static func index_text(entries: Array) -> String:
	var list: Array = []
	for entry: Variant in entries:
		list.append((entry as Dictionary).duplicate(true))
	var data := {
		"format": LibraryContracts.FORMAT_STRUCTURES,
		"format_version": LibraryContracts.FORMAT_VERSION,
		"structures": list,
	}
	return JSON.stringify(data, "\t", true) + "\n"


## The cleaned entries of `read` (LibraryReader.read's result) whose id is in `kept`, index order.
static func entries_of(read: Dictionary, kept: Array) -> Array:
	var out: Array = []
	for item: Dictionary in read.get("structures", []):
		if String(item["id"]) in kept:
			out.append((item["entry"] as Dictionary).duplicate(true))
	return out


## `left` and `right` (index texts as bytes) united by id. {ok, error, text}: an id in both must
## hold an identical entry. An index that does not parse counts as empty.
static func merge_index(left: Variant, right: Variant) -> Dictionary:
	var entries: Array = []
	var by_id := {}
	for source: Variant in [left, right]:
		var data := _json_of(source)
		for raw: Variant in data.get("structures", []) if data.get("structures") is Array else []:
			if not raw is Dictionary or not (raw as Dictionary).get("id") is String:
				continue
			var id := String((raw as Dictionary)["id"])
			if by_id.has(id):
				if JSON.stringify(by_id[id], "", true) != JSON.stringify(raw, "", true):
					return {
						"ok": false,
						"error": "structure %s differs between the kept copy and the delta" % id,
						"text": ""
					}
				continue
			by_id[id] = raw
			entries.append(raw)
	return {"ok": true, "error": "", "text": index_text(entries)}


# ---- helpers ----


static func _json_of(bytes: Variant) -> Dictionary:
	var text := ""
	if bytes is PackedByteArray:
		text = (bytes as PackedByteArray).get_string_from_utf8()
	elif bytes is String:
		text = bytes
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func _parse_object(
	text: String, label: String, cap: int, warnings: Array[String]
) -> Dictionary:
	if text.to_utf8_buffer().size() > cap:
		warnings.append("%s is over %d bytes (the structures are ignored)" % [label, cap])
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		warnings.append("%s is not valid JSON (line %d)" % [label, json.get_error_line()])
		return {}
	if not json.data is Dictionary:
		warnings.append("%s is not a JSON object" % label)
		return {}
	return json.data


static func _unknown(
	data: Dictionary, allowed: Array[String], where: String, warnings: Array[String]
) -> void:
	for key: Variant in data:
		if not key is String or not String(key) in allowed:
			warnings.append("%s: unknown key '%s'" % [where, str(key).left(32)])


static func _text(value: Variant, limit: int, fallback: String) -> String:
	if value is String and String(value) != "" and String(value).length() <= limit:
		return String(value)
	return fallback


static func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is int or value is float) and not is_nan(float(value)) and not is_inf(float(value)):
		return clampf(float(value), low, high)
	return fallback


static func _pair(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		var x: Variant = (value as Array)[0]
		var y: Variant = (value as Array)[1]
		if (x is int or x is float) and (y is int or y is float):
			return Vector2(
				_number(x, fallback.x, 0.5, LIMIT_SIDE_M), _number(y, fallback.y, 0.5, LIMIT_SIDE_M)
			)
	return fallback
