class_name MapWallIO
extends RefCounted

## The walls entry of `map.ttmap`, written and read for MapDocumentIO (which owns the archive,
## the byte caps and the warning log; this class owns the entry's shape and validation), in the
## way MapCrossingIO does for crossings. Summary: docs/systems/walls.md.
##
##   walls.json   {"version": 1, "walls": [wall, ...]}
##                wall: {"id", "kind": "stone" | "fence" | "building", "points": [[x, z], ...],
##                       "closed": bool, "height_m", "style": palette biome id or ""}
##
## Everything read is untrusted: a wall with any problem (id outside 1..255 or repeated, unknown
## kind, fewer than Wall.MIN_POINTS or more than Wall.MAX_POINTS points, a point NaN, Inf or off
## the map, a segment shorter than Wall.MIN_SEGMENT_M, a line longer than Wall.MAX_LENGTH_M, a
## height outside its kind's range, a style that is not a short string) is skipped with a
## warning, as are walls past MapDocument.MAX_WALLS. The writer refuses a document breaking any
## of these rules (problem()). Older builds read only their own KNOWN_ENTRIES, so they load a map
## with walls as a map without them.

const ENTRY := "walls.json"
const VERSION := 1
## How far from square a building's corners may be (the cosine of the angle between sides).
const RIGHT_ANGLE_TOLERANCE := 0.02


## Adds walls.json for `doc` to `entries` (nothing when it has no wall). Assumes problem(doc)
## is "".
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	if doc.walls.is_empty():
		return
	var list: Array = []
	for wall in doc.walls:
		list.append(wall_json(wall))
	var data := {"version": VERSION, "walls": list}
	entries[ENTRY] = JSON.stringify(data, "", false, true).to_utf8_buffer()


## The first wall rule `doc` breaks, or "".
static func problem(doc: MapDocument) -> String:
	if doc.walls.size() > MapDocument.MAX_WALLS:
		return "more than %d walls" % MapDocument.MAX_WALLS
	var seen := {}
	for wall in doc.walls:
		if wall == null:
			return "a null wall"
		var reason := wall_problem(wall, doc.extent_m())
		if reason != "":
			return "wall %d: %s" % [wall.id, reason]
		if seen.has(wall.id):
			return "wall id %d is used twice" % wall.id
		seen[wall.id] = true
	return ""


## What is wrong with `wall` in a map of `extent` metres, or "". Shared by the writer, the
## reader and WallEditor (which refuses to add a wall the writer would refuse).
static func wall_problem(wall: Wall, extent: Vector2) -> String:
	if wall.id < 1 or wall.id > Wall.MAX_ID:
		return "id outside 1..%d" % Wall.MAX_ID
	if wall.kind < 0 or wall.kind >= Wall.KIND_NAMES.size():
		return "unknown kind"
	var count := wall.points.size()
	if count < Wall.MIN_POINTS or count > Wall.MAX_POINTS:
		return "%d points outside %d..%d" % [count, Wall.MIN_POINTS, Wall.MAX_POINTS]
	var half := extent * 0.5 + Vector2.ONE * MapWaterIO.EXTENT_TOLERANCE_M
	for p in wall.points:
		if not (_finite(p.x) and _finite(p.y)) or absf(p.x) > half.x or absf(p.y) > half.y:
			return "a point is NaN, Inf or off the map"
	if wall.closed and count < 3:
		return "a closed wall needs three points"
	var segments := count if wall.closed else count - 1
	for k in segments:
		if wall.points[k].distance_to(wall.points[(k + 1) % count]) < Wall.MIN_SEGMENT_M:
			return "a side is shorter than %s m" % Wall.MIN_SEGMENT_M
	if wall.is_building():
		var shape := _building_problem(wall)
		if shape != "":
			return shape
	elif wall.length_m() > Wall.MAX_LENGTH_M:
		return "longer than %s m" % Wall.MAX_LENGTH_M
	var low: float = Wall.MIN_HEIGHT_M[wall.kind]
	var high: float = Wall.MAX_HEIGHT_M[wall.kind]
	if not _finite(wall.height_m) or wall.height_m < low or wall.height_m > high:
		return "height outside %s..%s m" % [low, high]
	if wall.style.length() > MapDocumentIO.MAX_ID_LENGTH:
		return "style is too long"
	return ""


## What is wrong with `wall` as a building (a closed rectangle of four points whose sides are
## within Wall.BUILDING_MIN_SIDE_M..BUILDING_MAX_SIDE_M), or "".
static func _building_problem(wall: Wall) -> String:
	if not wall.closed or wall.points.size() != Wall.BUILDING_POINTS:
		return "a building is a closed rectangle of %d points" % Wall.BUILDING_POINTS
	for k in Wall.BUILDING_POINTS:
		var side := wall.points[(k + 1) % 4] - wall.points[k]
		var next := wall.points[(k + 2) % 4] - wall.points[(k + 1) % 4]
		if side.length() < Wall.BUILDING_MIN_SIDE_M or side.length() > Wall.BUILDING_MAX_SIDE_M:
			return "a side outside %s..%s m" % [Wall.BUILDING_MIN_SIDE_M, Wall.BUILDING_MAX_SIDE_M]
		if absf(side.normalized().dot(next.normalized())) > RIGHT_ANGLE_TOLERANCE:
			return "a building's corners are not square"
	return ""


## Fills doc.walls from `blobs` (entry name -> bytes, already within their caps) with
## MapDocumentIO's warning log. Never raises.
static func parse(blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog) -> void:
	if not blobs.has(ENTRY):
		return
	var data: Variant = MapDocumentIO._json(blobs[ENTRY], ENTRY, warn_log)
	var version: Variant = null
	if data is Dictionary:
		version = MapDocumentIO._integer(data.get("version"), 0, 1000000)
	if version != VERSION:
		warn_log.add("%s is not a version %d walls object; walls ignored" % [ENTRY, VERSION])
		return
	var list: Variant = data.get("walls")
	if not list is Array:
		warn_log.add("%s needs a walls list; walls ignored" % ENTRY)
		return
	doc.walls = parse_list(list, doc.extent_m(), warn_log)


# --- writing ------------------------------------------------------------------------


## One wall's JSON form, as the document stores it (and a live walls edit carries it).
static func wall_json(wall: Wall) -> Dictionary:
	var points: Array = []
	for p in wall.points:
		points.append([p.x, p.y])
	return {
		"id": wall.id,
		"kind": Wall.KIND_NAMES[wall.kind],
		"points": points,
		"closed": wall.closed,
		"height_m": wall.height_m,
		"style": wall.style,
	}


# --- reading ------------------------------------------------------------------------


## The walls of a JSON list (wall_json() forms, untrusted) on a map of `extent`: each one
## wall_problem() accepts, a warning in `warn_log` for each one dropped.
static func parse_list(
	list: Array, extent: Vector2, warn_log: MapDocumentIO._WarningLog
) -> Array[Wall]:
	var out: Array[Wall] = []
	var seen := {}
	if list.size() > MapDocument.MAX_WALLS:
		warn_log.add(
			(
				"%s: %d walls over the cap of %d ignored"
				% [ENTRY, list.size() - MapDocument.MAX_WALLS, MapDocument.MAX_WALLS]
			)
		)
	for index in mini(list.size(), MapDocument.MAX_WALLS):
		var parsed: Variant = _wall_from(list[index])
		var wall: Wall = parsed if parsed is Wall else null
		var reason: String = parsed if parsed is String else wall_problem(wall, extent)
		if reason == "" and seen.has(wall.id):
			reason = "id %d is used twice" % wall.id
		if reason != "":
			warn_log.add("%s: wall %d skipped: %s" % [ENTRY, index, reason])
			continue
		seen[wall.id] = true
		out.append(wall)
	return out


## A Wall from one JSON object, or a String saying why its shape is wrong. Numbers are taken
## as they are (a non-number becomes NAN) and left for wall_problem() to judge.
static func _wall_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return "not an object"
	var kind := Wall.KIND_NAMES.find(str(value.get("kind", "")))
	if kind < 0:
		return "unknown kind"
	var id: Variant = MapDocumentIO._integer(value.get("id"), 1, Wall.MAX_ID)
	if id == null:
		return "id missing or outside 1..%d" % Wall.MAX_ID
	var raw: Variant = value.get("points")
	if not raw is Array or raw.size() > Wall.MAX_POINTS:
		return "points must be a list of at most %d [x, z] pairs" % Wall.MAX_POINTS
	var points := PackedVector2Array()
	for entry in raw:
		var pair: Variant = _pair(entry)
		if pair == null:
			return "points must be [x, z] pairs"
		points.append(pair)
	var closed: Variant = value.get("closed", false)
	if not closed is bool:
		return "closed is not a boolean"
	var style: Variant = value.get("style", "")
	if not style is String:
		return "style is not a string"
	return Wall.make(
		id,
		kind as Wall.Kind,
		points,
		closed,
		_number_or_nan(value.get("height_m")),
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
