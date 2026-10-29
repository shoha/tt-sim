class_name StreetSplit
extends RefCounted

## Turns a street (a Wall of kind ROW) into individual Structure records: the route from a
## generated street to buildings an author can move, restyle and remove one by one (card S8 of
## the structures topic; docs/systems/structures.md "Splitting a street"). Pure functions of the
## document and the library's structure table; WallEditor.split_street() makes the edit.
##
## Lots. The street's lots are the ones it is built from (WallGeometry.row_lots: the same seeds
## and parameters), so the buildings stand where the street's did. Each lot becomes one record:
##   footprint  the lot's rectangle on the street line (the front edge is the one facing the
##              street, wound as ProcgenPlan wants), its sides clamped to the recipe's range;
##   seed       the lot's own building seed (the street's seed derivation: map seed, wall id,
##              wall seed, side and index), folded into 0..Structure.MAX_SEED;
##   recipe     the library structure that looks most like what the street's species drew for the
##              lot (match_row), ties broken by that seed, so a street does not become one house
##              repeated;
##   params     the lot's height and roof pitch (and window width, chimney count and masonry
##              when the recipe declares them), only where they differ from the recipe's default.
##
## What does not carry over: a lot's yard (its fence or low wall and gate), and the trim details a
## recipe does not offer. The silhouettes follow the lot (footprint, height, pitch, roof kind and
## ridge direction, where the library has a recipe with that roof); the dressing follows the
## library's structures.

## Score weights of match_row().
const W_STYLE := 6
const W_STYLE_ALIAS := 4
const W_WALLS := 3
const W_WALLS_MISMATCH := -1
## The roof kind weighs as much as the walls: a hip or flat lot should not become a gable one while
## a recipe with its roof exists.
const W_ROOF := 3
## A "end" recipe (its ridge defaults across, a gable to the front) for a lot whose gable faces the
## street, and against it for a lot whose eave does.
const W_RIDGE := 1
const W_DETAIL := 1
const W_TRIM := 2
const W_NOT_TOWNHOUSE := -4
## The tag of a structure that belongs to one region's architecture (a Mediterranean villa, a turf
## longhouse): the street rows' generic lots (stone or timber, gable, hip or flat) would match them
## by their materials and roof and turn an English village into a mix of cultures, so a split does
## not pick a row with it. The Building tool still offers them.
const REGIONAL_TAG := "regional"
## A best score under this means no structure resembles the lot: a seeded pick from the table.
const MIN_MATCH := 4
## Other tags that satisfy a facade style: a cottage lot may be built as any plain house.
const STYLE_ALIASES: Dictionary = {"cottage": "house", "none": "house"}
## The trim details that a recipe tagged "trim" dresses.
const TRIM_DETAILS: Array[String] = ["sills", "lintels", "floor_bands", "door_frame"]


## The records for the lots of row `wall` in `doc` (map frame; `scale` is the map's scale, so a
## recipe's metre limits fit the map): {"structures": Array[Structure] with id 0 (WallEditor
## gives them free ids), "lots": how many lots the street has, "skipped": lots that made no valid
## record (a footprint the writer would refuse)}. Empty when `wall` is no row or no library
## structure is served.
static func plan(doc: MapDocument, wall: Wall, scale: float) -> Dictionary:
	var structures: Array[Structure] = []
	var out := {"structures": structures, "lots": 0, "skipped": 0}
	if not wall.is_row():
		return out
	var rows := candidates()
	if rows.is_empty():
		return out
	var lots := WallGeometry.row_lots(doc, wall)
	out["lots"] = lots.size()
	for lot in lots:
		var row := match_row(lot, rows)
		var recipe := StructureRecipes.document(String(row["ref"]))
		var footprint := footprint_of(lot, StructureBrush.scaled_row(row, scale))
		var middle := Vector2.ZERO
		for p in footprint:
			middle += p * 0.25
		var made := Structure.make(
			1,
			String(row["ref"]),
			footprint,
			posmod(int(lot.get("seed", 0)), Structure.MAX_SEED + 1),
			params_of(lot, recipe),
			CrossingPlacement.style_at(doc, middle)
		)
		if recipe == null or MapStructureIO.structure_problem(made, doc.extent_m()) != "":
			out["skipped"] = int(out["skipped"]) + 1
			continue
		made.id = 0
		structures.append(made)
	return out


## The library rows a split picks from: the core library's structures without the regional ones
## (REGIONAL_TAG; all of them when nothing else is left), else every served one.
static func candidates() -> Array[Dictionary]:
	StructureRecipes.ensure_served()
	var rows := LibraryStructureStore.structures(StructureRecipes.CORE_LIBRARY)
	if rows.is_empty():
		return LibraryStructureStore.structures()
	var generic: Array[Dictionary] = []
	for row in rows:
		if not REGIONAL_TAG in (row.get("tags", []) as Array):
			generic.append(row)
	return generic if not generic.is_empty() else rows


## The row of `rows` that looks most like `lot` (one of ProcgenRow.plan's: "walls", "roof",
## "style", "trim", "chimneys", "seed"): the best score (see score()), the tie broken by the lot's
## seed. Under MIN_MATCH nothing resembles the lot, and the pick is the seed's from the whole table.
## `rows` must not be empty. Pure.
static func match_row(lot: Dictionary, rows: Array[Dictionary]) -> Dictionary:
	var best := -INF
	var tied: Array[Dictionary] = []
	for row in rows:
		var value := score(lot, row)
		if value > best:
			best = value
			tied = [row]
		elif value == best:
			tied.append(row)
	if best < MIN_MATCH:
		tied = rows
	return tied[posmod(int(lot.get("seed", 0)), tied.size())]


## How well library row `row` (tags, family) matches `lot`: its facade style (a named style is
## the row's family or tag; a plain lot or a cottage takes a "house"), its walls (stone or
## timber; a textured lot is stone), its roof, and the chimney, shutters, quoins and trim the lot
## was dressed with. A row that is a townhouse for a lot that is not takes a penalty. Pure.
static func score(lot: Dictionary, row: Dictionary) -> int:
	var tags: Array = row.get("tags", [])
	var family := String(row.get("family", ""))
	var style := String(lot.get("style", "none"))
	var value := 0
	if style != "none" and (style in tags or family == style):
		value += W_STYLE
	elif STYLE_ALIASES.has(style) and String(STYLE_ALIASES[style]) in tags:
		value += W_STYLE_ALIAS
	if style != "townhouse" and "townhouse" in tags:
		value += W_NOT_TOWNHOUSE
	var walls := "timber" if String(lot.get("walls", "stone")) == "timber" else "stone"
	var other := "stone" if walls == "timber" else "timber"
	if walls in tags:
		value += W_WALLS
	elif other in tags:
		value += W_WALLS_MISMATCH
	if String(lot.get("roof", "gable")) in tags:
		value += W_ROOF
	if "end" in tags:
		value += W_RIDGE if int(lot.get("ridge", 1)) == 2 else -W_RIDGE
	var stacks := int(lot.get("chimneys", 0))
	if "chimney" in tags:
		value += W_DETAIL if stacks > 0 else -W_DETAIL
	var trim: Array = lot.get("trim", [])
	if "shutters" in tags and ("shutters" in trim or "upper_shutters" in trim):
		value += W_DETAIL
	if "quoins" in tags:
		value += W_DETAIL if "quoins" in trim else -W_DETAIL
	if "trim" in tags:
		var dressed := false
		for detail in TRIM_DETAILS:
			dressed = dressed or detail in trim
		value += W_TRIM if dressed else -W_TRIM
	return value


## The footprint of `lot` as a structure plan: its rectangle, front (edge 0) on the street side
## and wound as ProcgenPlan wants, its sides clamped to `row`'s range (StructurePlacement
## .clamp_size, `row` already scaled to the map). Points snap to Structure.FOOTPRINT_STEP_M. Pure.
static func footprint_of(lot: Dictionary, row: Dictionary) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for q: Vector3 in lot["points"]:
		corners.append(Vector2(q.x, q.z))
	if ProcgenPlan.area(corners) < 0.0:
		# The lot is wound the other way (the street's right side): the same rectangle with the
		# front edge reversed, so edge 0 is still the street side and the door faces out.
		corners = PackedVector2Array([corners[1], corners[0], corners[3], corners[2]])
	var front := corners[1] - corners[0]
	var size := StructurePlacement.clamp_size(
		Vector2(front.length(), (corners[3] - corners[0]).length()), row
	)
	var centre := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	return StructurePlacement.rect_plan(centre, size, atan2(-front.y, -front.x))


## The parameters of the record for `lot` on `recipe`: the lot's height, roof pitch, window
## width, chimney count, masonry and ridge direction (1 eave to the street, 2 gable), kept where
## the recipe declares the parameter, clamped to its range, and only where they differ from its
## default (the record's rule). Pure.
static func params_of(lot: Dictionary, recipe: PlantGraphDocument) -> Dictionary:
	if recipe == null:
		return {}
	var walls := String(lot.get("walls", "stone"))
	var wanted := {
		"height": float(lot.get("height", 0.0)),
		"roof_pitch": float(lot.get("pitch", 0.0)),
		"window_width": float(lot.get("window_width", 0.0)),
		"chimneys": float(lot.get("chimneys", 0)),
		"textured": 0.0 if walls == "timber" else 1.0,
		# 1 the eave to the street, 2 a gable to it: the lot's own, so a terrace keeps its eaves out.
		"ridge": float(lot.get("ridge", 0)),
	}
	var clamped := StructureRecipes.clamp_params(recipe, wanted)
	var out := {}
	for entry: Dictionary in recipe.interface:
		var key := String(entry.get("name", ""))
		if not clamped.has(key):
			continue
		var value := Structure.round_param(float(clamped[key]))
		if not is_equal_approx(value, Structure.round_param(float(entry.get("default", 0.0)))):
			out[key] = value
	return out


## `count` free structure ids of `doc`, lowest first, or an empty array when the document cannot
## hold that many more structures. Pure.
static func free_ids(doc: MapDocument, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count <= 0 or doc.structures.size() + count > MapDocument.MAX_STRUCTURES:
		return out
	var used := {}
	for entry in doc.structures:
		used[entry.id] = true
	for candidate in range(1, Structure.MAX_ID + 1):
		if not used.has(candidate):
			out.append(candidate)
			if out.size() == count:
				return out
	return PackedInt32Array()
