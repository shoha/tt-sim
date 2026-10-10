class_name MapCrossingIO
extends RefCounted

## The crossings entry of `map.ttmap` (phase 4b), written and read for MapDocumentIO (which
## owns the archive, the byte caps and the warning log; this class owns the entry's shape and
## validation). Summary: docs/ARCHITECTURE.md "Map document (map.ttmap)" and
## docs/systems/crossings.md.
##
##   crossings.json   {"version": 1, "crossings": [crossing, ...]}
##                    crossing: {"id", "kind": "plank" | "stones", "start": [x, z],
##                               "end": [x, z], "levels": [start_y, middle_y, end_y],
##                               "width_m", "style": palette biome id or ""}
##
## Everything read is untrusted, as elsewhere in MapDocumentIO: a crossing with any problem
## (id outside 1..255 or repeated, unknown kind, an anchor NaN, Inf or off the map, a span
## outside Crossing.MIN_SPAN_M..MAX_SPAN_M, a level NaN, Inf or beyond the height cap, a middle
## level more than Crossing.MAX_RISE_M from the ends' mean, a width outside its kind's range, a
## style that is not a short string) is skipped with a warning, as are crossings past
## MapDocument.MAX_CROSSINGS. The writer refuses a document breaking any of these rules
## (problem()), so nothing written is trimmed on read. Older builds read only their own
## KNOWN_ENTRIES, so they load a map with crossings as a map without them.

const ENTRY := "crossings.json"
const VERSION := 1


## Adds crossings.json for `doc` to `entries` (nothing when it has no crossing). Assumes
## problem(doc) is "".
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	if doc.crossings.is_empty():
		return
	var list: Array = []
	for crossing in doc.crossings:
		list.append(crossing_json(crossing))
	var data := {"version": VERSION, "crossings": list}
	entries[ENTRY] = JSON.stringify(data, "", false, true).to_utf8_buffer()


## The first crossing rule `doc` breaks, or "" (see the header).
static func problem(doc: MapDocument) -> String:
	if doc.crossings.size() > MapDocument.MAX_CROSSINGS:
		return "more than %d crossings" % MapDocument.MAX_CROSSINGS
	var seen := {}
	for crossing in doc.crossings:
		if crossing == null:
			return "a null crossing"
		var crossing_problem := crossing_problem(crossing, doc.extent_m())
		if crossing_problem != "":
			return "crossing %d: %s" % [crossing.id, crossing_problem]
		if seen.has(crossing.id):
			return "crossing id %d is used twice" % crossing.id
		seen[crossing.id] = true
	return ""


## What is wrong with `crossing` in a map of `extent` metres, or "". Shared by the writer,
## the reader and CrossingEditor (which refuses to add a crossing the writer would refuse).
static func crossing_problem(crossing: Crossing, extent: Vector2) -> String:
	if crossing.id < 1 or crossing.id > Crossing.MAX_ID:
		return "id outside 1..%d" % Crossing.MAX_ID
	if crossing.kind < 0 or crossing.kind >= Crossing.KIND_NAMES.size():
		return "unknown kind"
	var half := extent * 0.5 + Vector2.ONE * MapWaterIO.EXTENT_TOLERANCE_M
	for p in [crossing.start, crossing.end]:
		if not (_finite(p.x) and _finite(p.y)) or absf(p.x) > half.x or absf(p.y) > half.y:
			return "an anchor is NaN, Inf or off the map"
	var span := crossing.span_m()
	if span < Crossing.MIN_SPAN_M or span > Crossing.MAX_SPAN_M:
		return "span %.2f m outside %s..%s m" % [span, Crossing.MIN_SPAN_M, Crossing.MAX_SPAN_M]
	for y in [crossing.levels.x, crossing.levels.y, crossing.levels.z]:
		if not _finite(y) or absf(y) > MapDocument.MAX_ABS_HEIGHT_M:
			return "a level is NaN, Inf or out of range"
	var mean := (crossing.levels.x + crossing.levels.z) * 0.5
	if absf(crossing.levels.y - mean) > Crossing.MAX_RISE_M:
		return "the middle level is more than %s m from the ends" % Crossing.MAX_RISE_M
	var low: float = Crossing.MIN_WIDTH_M[crossing.kind]
	var high: float = Crossing.MAX_WIDTH_M[crossing.kind]
	if not _finite(crossing.width_m) or crossing.width_m < low or crossing.width_m > high:
		return "width outside %s..%s m" % [low, high]
	if crossing.style.length() > MapDocumentIO.MAX_ID_LENGTH:
		return "style is too long"
	return ""


## Fills doc.crossings from `blobs` (entry name -> bytes, already within their caps) with
## MapDocumentIO's warning log. Never raises.
static func parse(blobs: Dictionary, doc: MapDocument, log: MapDocumentIO._WarningLog) -> void:
	if not blobs.has(ENTRY):
		return
	var data: Variant = MapDocumentIO._json(blobs[ENTRY], ENTRY, log)
	var version: Variant = null
	if data is Dictionary:
		version = MapDocumentIO._integer(data.get("version"), 0, 1000000)
	if version != VERSION:
		log.add("%s is not a version %d crossings object; crossings ignored" % [ENTRY, VERSION])
		return
	var list: Variant = data.get("crossings")
	if not list is Array:
		log.add("%s needs a crossings list; crossings ignored" % ENTRY)
		return
	doc.crossings = parse_list(list, doc.extent_m(), log)


# --- writing ------------------------------------------------------------------------


## One crossing's JSON form, as the document stores it (and a live crossings edit carries it).
static func crossing_json(crossing: Crossing) -> Dictionary:
	return {
		"id": crossing.id,
		"kind": Crossing.KIND_NAMES[crossing.kind],
		"start": [crossing.start.x, crossing.start.y],
		"end": [crossing.end.x, crossing.end.y],
		"levels": [crossing.levels.x, crossing.levels.y, crossing.levels.z],
		"width_m": crossing.width_m,
		"style": crossing.style,
	}


# --- reading ------------------------------------------------------------------------


## The crossings of a JSON list (crossing_json() forms, untrusted) on a map of `extent`: each
## one crossing_problem() accepts, a warning in `log` for each one dropped.
static func parse_list(
	list: Array, extent: Vector2, log: MapDocumentIO._WarningLog
) -> Array[Crossing]:
	var out: Array[Crossing] = []
	var seen := {}
	if list.size() > MapDocument.MAX_CROSSINGS:
		log.add(
			(
				"%s: %d crossings over the cap of %d ignored"
				% [ENTRY, list.size() - MapDocument.MAX_CROSSINGS, MapDocument.MAX_CROSSINGS]
			)
		)
	for index in mini(list.size(), MapDocument.MAX_CROSSINGS):
		var parsed: Variant = _crossing_from(list[index])
		var crossing: Crossing = parsed if parsed is Crossing else null
		var problem: String = parsed if parsed is String else crossing_problem(crossing, extent)
		if problem == "" and seen.has(crossing.id):
			problem = "id %d is used twice" % crossing.id
		if problem != "":
			log.add("%s: crossing %d skipped: %s" % [ENTRY, index, problem])
			continue
		seen[crossing.id] = true
		out.append(crossing)
	return out


## A Crossing from one JSON object, or a String saying why its shape is wrong. Numbers are
## taken as they are (a non-number becomes NAN) and left for crossing_problem() to judge.
static func _crossing_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return "not an object"
	var kind := Crossing.KIND_NAMES.find(str(value.get("kind", "")))
	if kind < 0:
		return "unknown kind"
	var id: Variant = MapDocumentIO._integer(value.get("id"), 1, Crossing.MAX_ID)
	if id == null:
		return "id missing or outside 1..%d" % Crossing.MAX_ID
	var start: Variant = _pair(value.get("start"))
	var end: Variant = _pair(value.get("end"))
	if start == null or end == null:
		return "start and end must be [x, z] pairs"
	var levels: Variant = value.get("levels")
	if not levels is Array or levels.size() != 3:
		return "levels must be [start, middle, end]"
	var style: Variant = value.get("style", "")
	if not style is String:
		return "style is not a string"
	var crossing := Crossing.make(
		id,
		kind as Crossing.Kind,
		start,
		end,
		Vector3(_number_or_nan(levels[0]), _number_or_nan(levels[1]), _number_or_nan(levels[2])),
		_number_or_nan(value.get("width_m")),
		(style as String).substr(0, MapDocumentIO.MAX_ID_LENGTH + 1)
	)
	return crossing


static func _pair(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	return Vector2(_number_or_nan(value[0]), _number_or_nan(value[1]))


static func _number_or_nan(value: Variant) -> float:
	var number: Variant = MapDocumentIO._number(value)
	return number if number != null else NAN


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
