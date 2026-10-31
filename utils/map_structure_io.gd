class_name MapStructureIO
extends RefCounted

## The structures entry of `map.ttmap`, written and read for MapDocumentIO (which owns the
## archive, the byte caps and the warning log; this class owns the entry's shape and validation),
## in the way MapWallIO does for walls. Summary: docs/systems/structures.md.
##
##   structures.json   {"version": 1, "structures": [structure, ...]}
##                     structure: {"id", "recipe": "<library id>:<structure id>",
##                                 "footprint": [[x, z], ...], "seed", "params": {name: number
##                                 or bool}, "style": palette biome id or ""}
##
## Everything read is untrusted: a structure with any problem (id outside 1..255 or repeated, a
## recipe that is not a well formed `<library>:<structure>` reference, fewer than
## Structure.MIN_POINTS or more than Structure.MAX_POINTS footprint points, a point NaN, Inf or
## off the map, a footprint wider than MAX_SPAN_M, a footprint ProcgenPlan refuses, a seed
## outside 0..Structure.MAX_SEED, params that are not at most Structure.MAX_PARAMS well named
## numbers or bools, a style that is not a short string) is skipped with a warning, as are
## structures past MapDocument.MAX_STRUCTURES. The writer refuses a document breaking any of
## these rules (problem()). Older builds read only their own KNOWN_ENTRIES, so they load a map
## with structures as a map without them.
##
## Bytes. The text is written with sorted keys and the default float precision. A footprint
## point is a float32, printed with 14 significant digits and parsed to the same float32; a
## numeric param is rounded to Structure.PARAM_STEP on every read and write, so a map read and
## written again gives the same bytes.
##
## Whether the recipe exists is not judged here: a reference names a library the map's
## `libraries` record covers, and the registry resolves it when the structure is built.

const ENTRY := "structures.json"
const VERSION := 1
## The widest the footprint's bounding box may be on either axis, metres. A hostile-input cap;
## each recipe's own size range is the library's (design.md "Files").
const MAX_SPAN_M := 64.0

static var _param_name_re: RegEx = _compile("^[a-z][a-z0-9_]*$")


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


## Adds structures.json for `doc` to `entries` (nothing when it has no structure). Assumes
## problem(doc) is "".
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	if doc.structures.is_empty():
		return
	entries[ENTRY] = list_text(doc.structures).to_utf8_buffer()


## The entry's text for `list`: the document form, as serialize() writes it.
static func list_text(list: Array[Structure]) -> String:
	var out: Array = []
	for structure in list:
		out.append(structure_json(structure))
	return JSON.stringify({"version": VERSION, "structures": out}, "", true)


## The first structure rule `doc` breaks, or "".
static func problem(doc: MapDocument) -> String:
	if doc.structures.size() > MapDocument.MAX_STRUCTURES:
		return "more than %d structures" % MapDocument.MAX_STRUCTURES
	var seen := {}
	for structure in doc.structures:
		if structure == null:
			return "a null structure"
		var reason := structure_problem(structure, doc.extent_m())
		if reason != "":
			return "structure %d: %s" % [structure.id, reason]
		if seen.has(structure.id):
			return "structure id %d is used twice" % structure.id
		seen[structure.id] = true
	return ""


## What is wrong with `structure` in a map of `extent` metres, or "". Shared by the writer, the
## reader and the editor (which refuses to add a structure the writer would refuse).
static func structure_problem(structure: Structure, extent: Vector2) -> String:
	if structure.id < 1 or structure.id > Structure.MAX_ID:
		return "id outside 1..%d" % Structure.MAX_ID
	var recipe := recipe_problem(structure.recipe)
	if recipe != "":
		return recipe
	var served := LibraryStructureStore.structure(structure.recipe)
	var kind := ProcgenPlan.KIND_PROP if ProcgenStructureIndex.is_prop(served) else ""
	var plan := footprint_problem(structure.footprint, extent, kind)
	if plan != "":
		return plan
	if structure.seed_value < 0 or structure.seed_value > Structure.MAX_SEED:
		return "seed outside 0..%d" % Structure.MAX_SEED
	var overrides := params_problem(structure.params)
	if overrides != "":
		return overrides
	if structure.style.length() > MapDocumentIO.MAX_ID_LENGTH:
		return "style is too long"
	return ""


## What is wrong with the recipe reference `recipe` (`<library id>:<structure id>`), or "".
static func recipe_problem(recipe: String) -> String:
	if recipe.length() > Structure.MAX_RECIPE_LENGTH:
		return "recipe reference is too long"
	var parts := LibraryIds.split_ref(recipe)
	if parts.is_empty() or String(parts["library"]) == "":
		return "recipe is not a <library>:<structure> reference"
	if not LibraryIds.library_problems(String(parts["library"])).is_empty():
		return "recipe names a malformed library id"
	if not LibraryIds.biome_problems(String(parts["local"])).is_empty():
		return "recipe names a malformed structure id"
	return ""


## What is wrong with `plan` as a footprint on a map of `extent` metres, or "". The record's own
## caps first (point count, finite, on the map, MAX_SPAN_M), then the plan rules.
static func footprint_problem(
	plan: PackedVector2Array, extent: Vector2, kind: String = ""
) -> String:
	var count := plan.size()
	if count < Structure.MIN_POINTS or count > Structure.MAX_POINTS:
		return "%d points outside %d..%d" % [count, Structure.MIN_POINTS, Structure.MAX_POINTS]
	var half := extent * 0.5 + Vector2.ONE * MapWaterIO.EXTENT_TOLERANCE_M
	var box := Rect2(plan[0], Vector2.ZERO)
	for p in plan:
		if not (_finite(p.x) and _finite(p.y)) or absf(p.x) > half.x or absf(p.y) > half.y:
			return "a point is NaN, Inf or off the map"
		box = box.expand(p)
	if box.size.x > MAX_SPAN_M or box.size.y > MAX_SPAN_M:
		return "wider than %s m" % MAX_SPAN_M
	return _plan_problem(plan, kind)


## What the shared plan rules (procgen's ProcgenPlan, the same ones structgen edits by) say about
## `plan`, or "": a simple polygon wound the way the presets are, no side shorter than 0.5 m,
## none closer than 0.3 m to another it does not meet, no corner sharper than 15 degrees, an
## area of at least 2 m2 (a prop's `kind` has ProcgenPlan's smaller prop limits). The first
## problem is returned.
static func _plan_problem(plan: PackedVector2Array, kind: String = "") -> String:
	var problems := ProcgenPlan.problems_of(plan, kind)
	return "" if problems.is_empty() else problems[0]


## What is wrong with the params `overrides`, or "": at most Structure.MAX_PARAMS entries, each a
## String name of the form [a-z][a-z0-9_]* (at most Structure.MAX_PARAM_NAME) with a bool or a
## finite number of magnitude at most Structure.MAX_PARAM_ABS.
static func params_problem(overrides: Dictionary) -> String:
	if overrides.size() > Structure.MAX_PARAMS:
		return "more than %d params" % Structure.MAX_PARAMS
	for key: Variant in overrides:
		if not key is String or (key as String).length() > Structure.MAX_PARAM_NAME:
			return "a param name is not a short string"
		if _param_name_re.search(key as String) == null:
			return "param name '%s' must match [a-z][a-z0-9_]*" % key
		var value: Variant = overrides[key]
		if value is bool:
			continue
		if not (value is float or value is int):
			return "param '%s' is not a number or a boolean" % key
		var number := float(value)
		if not _finite(number) or absf(number) > Structure.MAX_PARAM_ABS:
			return "param '%s' is not a finite number within %s" % [key, Structure.MAX_PARAM_ABS]
	return ""


## Fills doc.structures from `blobs` (entry name -> bytes, already within their caps) with
## MapDocumentIO's warning log. Never raises.
static func parse(blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog) -> void:
	if not blobs.has(ENTRY):
		return
	var data: Variant = MapDocumentIO._json(blobs[ENTRY], ENTRY, warn_log)
	var version: Variant = null
	if data is Dictionary:
		version = MapDocumentIO._integer(data.get("version"), 0, 1000000)
	if version != VERSION:
		warn_log.add(
			"%s is not a version %d structures object; structures ignored" % [ENTRY, VERSION]
		)
		return
	var list: Variant = data.get("structures")
	if not list is Array:
		warn_log.add("%s needs a structures list; structures ignored" % ENTRY)
		return
	doc.structures = parse_list(list, doc.extent_m(), warn_log)


# --- writing ------------------------------------------------------------------------


## One structure's JSON form, as the document stores it (and a live structures edit carries it).
## Numeric params are written rounded to Structure.PARAM_STEP, in name order.
static func structure_json(structure: Structure) -> Dictionary:
	var points: Array = []
	for p in structure.footprint:
		points.append([p.x, p.y])
	var overrides := {}
	var names: Array = structure.params.keys()
	names.sort()
	for key: String in names:
		var value: Variant = structure.params[key]
		overrides[key] = value if value is bool else Structure.round_param(float(value))
	return {
		"id": structure.id,
		"recipe": structure.recipe,
		"footprint": points,
		"seed": structure.seed_value,
		"params": overrides,
		"style": structure.style,
	}


# --- reading ------------------------------------------------------------------------


## The structures of a JSON list (structure_json() forms, untrusted) on a map of `extent`: each
## one structure_problem() accepts, a warning in `warn_log` for each one dropped.
static func parse_list(
	list: Array, extent: Vector2, warn_log: MapDocumentIO._WarningLog
) -> Array[Structure]:
	var out: Array[Structure] = []
	var seen := {}
	if list.size() > MapDocument.MAX_STRUCTURES:
		warn_log.add(
			(
				"%s: %d structures over the cap of %d ignored"
				% [ENTRY, list.size() - MapDocument.MAX_STRUCTURES, MapDocument.MAX_STRUCTURES]
			)
		)
	for index in mini(list.size(), MapDocument.MAX_STRUCTURES):
		var parsed: Variant = _structure_from(list[index])
		var structure: Structure = parsed if parsed is Structure else null
		var reason: String = parsed if parsed is String else structure_problem(structure, extent)
		if reason == "" and seen.has(structure.id):
			reason = "id %d is used twice" % structure.id
		if reason != "":
			warn_log.add("%s: structure %d skipped: %s" % [ENTRY, index, reason])
			continue
		seen[structure.id] = true
		out.append(structure)
	return out


## A Structure from one JSON object, or a String saying why its shape is wrong. Numbers are
## taken as they are (a non-number becomes NAN) and left for structure_problem() to judge.
static func _structure_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return "not an object"
	var id: Variant = MapDocumentIO._integer(value.get("id"), 1, Structure.MAX_ID)
	if id == null:
		return "id missing or outside 1..%d" % Structure.MAX_ID
	var recipe: Variant = value.get("recipe")
	if not recipe is String:
		return "recipe is not a string"
	var raw: Variant = value.get("footprint")
	if not raw is Array or raw.size() > Structure.MAX_POINTS:
		return "footprint must be a list of at most %d [x, z] pairs" % Structure.MAX_POINTS
	var plan := PackedVector2Array()
	for entry in raw:
		var pair: Variant = _pair(entry)
		if pair == null:
			return "footprint must be [x, z] pairs"
		plan.append(pair)
	var seed_read: Variant = MapDocumentIO._integer(value.get("seed"), 0, Structure.MAX_SEED)
	if seed_read == null:
		return "seed is not a whole number in 0..%d" % Structure.MAX_SEED
	var raw_params: Variant = value.get("params", {})
	if not raw_params is Dictionary or raw_params.size() > Structure.MAX_PARAMS:
		return "params must be an object of at most %d entries" % Structure.MAX_PARAMS
	var overrides := {}
	for key: Variant in raw_params:
		var item: Variant = raw_params[key]
		if item is bool:
			overrides[key] = item
		elif item is float or item is int:
			# Rounded here so a value read and written again keeps its bytes. A NaN or Inf
			# stays one for params_problem() to refuse.
			overrides[key] = Structure.round_param(float(item))
		else:
			return "param '%s' is not a number or a boolean" % str(key).left(40)
	var style: Variant = value.get("style", "")
	if not style is String:
		return "style is not a string"
	return Structure.make(
		id,
		(recipe as String).substr(0, Structure.MAX_RECIPE_LENGTH + 1),
		plan,
		seed_read,
		overrides,
		(style as String).substr(0, MapDocumentIO.MAX_ID_LENGTH + 1)
	)


static func _pair(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	return Vector2(_number_or_nan(value[0]), _number_or_nan(value[1]))


static func _number_or_nan(value: Variant) -> float:
	var number: Variant = MapDocumentIO._number(value)
	return number if number != null else NAN


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
