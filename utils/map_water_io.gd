class_name MapWaterIO
extends RefCounted

## The water entries of `map.ttmap`, written and read for MapDocumentIO (which owns the
## archive, the byte caps and the warning log; this class owns the water entries' shape
## and validation). Summary: docs/ARCHITECTURE.md "Map document (map.ttmap)".
##
##   splines.json     {"version": 1, "bodies": [body, ...], "flow": flow}
##                    river: {"id", "kind": "river", "depth", "level_m", "speed",
##                            "points": [[x, z], ...], "half_widths": [w, ...],
##                            optional "beyond" / "beyond_up": [[x, z], ...], the course
##                            drawn past the map edge after the last point / before the
##                            first (phase 6, WaterBody; 1..MAX_BEYOND_POINTS points, each
##                            within the ground skirt's reach of the map)
##                    pond:  {"id", "kind": "pond", "depth", "level_m"}
##                    depth is "ankle", "waist" or "deep"; flow (only with a flow map):
##                    {"frame": "map_xz", "size": [nx, nz]}
##   ponds.png        8-bit greyscale on the sample grid: the id of the pond holding each
##                    sample, 0 for none. Needs splines.json.
##   water_flow.png   the baked flow map (WaterFlowBaker), RG8 stored as an RGB PNG with
##                    B = 0, nx x nz texels, in the "map_xz" frame. Needs splines.json.
##
## Everything read is untrusted, as elsewhere in MapDocumentIO: a body with any problem
## (id outside 1..255 or repeated, unknown kind or depth, level NaN, Inf or beyond the
## height cap, a river with fewer than 2 or more than MapDocument.MAX_RIVER_POINTS points,
## a point outside the map, half-widths not one per point or outside the WaterBody range,
## speed outside 0..MAX_SPEED) is skipped with a warning, as are bodies past
## MAX_WATER_BODIES and rivers past MAX_RIVERS; mask bytes naming no pond are cleared; a
## flow map whose metadata is missing or does not match its PNG is dropped. A river's
## course past the edge that is malformed (not a list of [x, z] pairs, empty or longer than
## MAX_BEYOND_POINTS, a point NaN, Inf or further than BEYOND_REACH_M past the map) is
## dropped with a warning and the river kept (its course is then derived). The writer
## refuses a document breaking any of these rules (problem()), so nothing written is
## trimmed on read. Older builds read only their own KNOWN_ENTRIES, so they load a map
## with water as a map without it; a build before phase 6 reads only the body keys it knows
## (_body_from), so it loads a river with "beyond" as the same river without it.

const SPLINES_ENTRY := "splines.json"
const PONDS_ENTRY := "ponds.png"
const FLOW_ENTRY := "water_flow.png"
const VERSION := 1
const FLOW_FRAME := "map_xz"
## A point may sit this far outside the map edge (float32 rounding of an edge point).
const EXTENT_TOLERANCE_M := 1e-3
## A river's course past the edge stays within this of the map (the ground skirt's width,
## AuthoredTerrain.skirt_width_m(), with a margin).
const BEYOND_REACH_M := 50.0
const BEYOND_KEYS: Array[String] = ["beyond", "beyond_up"]


## Adds the water entries of `doc` to `entries` (nothing when it has no water). Assumes
## problem(doc) is "".
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	if doc.water_bodies.is_empty() and doc.pond_mask.is_empty() and doc.water_flow.is_empty():
		return
	var bodies: Array = []
	for body in doc.water_bodies:
		bodies.append(body_json(body))
	var data := {"version": VERSION, "bodies": bodies}
	if not doc.water_flow.is_empty():
		var size := doc.water_flow_size
		data["flow"] = {"frame": FLOW_FRAME, "size": [size.x, size.y]}
		var image := WaterFlowBaker.to_image(doc.water_flow, size)
		entries[FLOW_ENTRY] = image.save_png_to_buffer()
	entries[SPLINES_ENTRY] = JSON.stringify(data, "", false, true).to_utf8_buffer()
	if not doc.pond_mask.is_empty():
		var mask := Image.create_from_data(
			doc.samples_x(), doc.samples_z(), false, Image.FORMAT_L8, doc.pond_mask
		)
		entries[PONDS_ENTRY] = mask.save_png_to_buffer()


## The first water rule `doc` breaks, or "" (see the header).
static func problem(doc: MapDocument) -> String:
	if doc.water_bodies.size() > MapDocument.MAX_WATER_BODIES:
		return "more than %d water bodies" % MapDocument.MAX_WATER_BODIES
	var seen := {}
	var rivers := 0
	var ponds := {}
	for body in doc.water_bodies:
		if body == null:
			return "a null water body"
		var body_problem := body_problem(body, doc.extent_m())
		if body_problem != "":
			return "water body %d: %s" % [body.id, body_problem]
		if seen.has(body.id):
			return "water body id %d is used twice" % body.id
		seen[body.id] = true
		if body.is_river():
			rivers += 1
		else:
			ponds[body.id] = true
	if rivers > MapDocument.MAX_RIVERS:
		return "more than %d rivers" % MapDocument.MAX_RIVERS
	if not doc.pond_mask.is_empty():
		if doc.pond_mask.size() != doc.sample_count():
			return "pond_mask does not match the sample grid"
		for value in doc.pond_mask:
			if value != 0 and not ponds.has(value):
				return "pond_mask names %d, which is not a pond" % value
	if doc.water_flow.is_empty():
		return ""
	var size := doc.water_flow_size
	if not _flow_size_ok(size):
		return "water_flow_size %s outside 2..%d" % [size, MapDocument.MAX_FLOW_TEXELS]
	if doc.water_flow.size() != size.x * size.y * 2:
		return "water_flow does not hold %s RG8 texels" % size
	return ""


## What is wrong with `body` in a map of `extent` metres, or "". Shared by the writer and
## the reader.
static func body_problem(body: WaterBody, extent: Vector2) -> String:
	if body.id < 1 or body.id > WaterBody.MAX_ID:
		return "id outside 1..%d" % WaterBody.MAX_ID
	if body.depth < 0 or body.depth >= WaterBody.DEPTH_M.size():
		return "unknown depth class"
	if not _finite(body.level_m) or absf(body.level_m) > MapDocument.MAX_ABS_HEIGHT_M:
		return "level is NaN, Inf or out of range"
	if not body.is_river():
		if body.kind != WaterBody.Kind.POND:
			return "unknown kind"
		if not body.points.is_empty() or not body.half_widths.is_empty():
			return "a pond has no line"
		return ""
	var count := body.points.size()
	if count < 2 or count > MapDocument.MAX_RIVER_POINTS:
		return "%d points, a river needs 2..%d" % [count, MapDocument.MAX_RIVER_POINTS]
	if body.half_widths.size() != count:
		return "half_widths do not match the points"
	if not _finite(body.speed) or body.speed < 0.0 or body.speed > WaterBody.MAX_SPEED:
		return "speed outside 0..%s" % WaterBody.MAX_SPEED
	var half := extent * 0.5 + Vector2.ONE * EXTENT_TOLERANCE_M
	for p in body.points:
		if not (_finite(p.x) and _finite(p.y)) or absf(p.x) > half.x or absf(p.y) > half.y:
			return "a point is NaN, Inf or off the map"
	for w in body.half_widths:
		if not _finite(w) or w < WaterBody.MIN_HALF_WIDTH_M or w > WaterBody.MAX_HALF_WIDTH_M:
			return (
				"a half-width is outside %s..%s m"
				% [WaterBody.MIN_HALF_WIDTH_M, WaterBody.MAX_HALF_WIDTH_M]
			)
	for course in [body.beyond, body.beyond_up]:
		var course_problem := beyond_problem(course, extent)
		if course_problem != "":
			return course_problem
	return ""


## What is wrong with a river's course past the edge `course` (WaterBody.beyond, beyond_up;
## empty is none) in a map of `extent` metres, or "".
static func beyond_problem(course: PackedVector2Array, extent: Vector2) -> String:
	if course.size() > WaterBody.MAX_BEYOND_POINTS:
		return "a course past the edge has more than %d points" % WaterBody.MAX_BEYOND_POINTS
	var reach := extent * 0.5 + Vector2.ONE * BEYOND_REACH_M
	for p in course:
		if not (_finite(p.x) and _finite(p.y)) or absf(p.x) > reach.x or absf(p.y) > reach.y:
			return "a point past the edge is NaN, Inf or too far from the map"
	return ""


## Fills the water fields of `doc` from `blobs` (entry name -> bytes, already within
## their caps) with MapDocumentIO's warning log. Never raises.
static func parse(blobs: Dictionary, doc: MapDocument, log: MapDocumentIO._WarningLog) -> void:
	if not blobs.has(SPLINES_ENTRY):
		for entry_name in [PONDS_ENTRY, FLOW_ENTRY]:
			if blobs.has(entry_name):
				log.add("%s without %s; ignored" % [entry_name, SPLINES_ENTRY])
		return
	var data: Variant = MapDocumentIO._json(blobs[SPLINES_ENTRY], SPLINES_ENTRY, log)
	var version: Variant = null
	if data is Dictionary:
		version = MapDocumentIO._integer(data.get("version"), 0, 1000000)
	if version != VERSION:
		log.add("%s is not a version %d water object; water ignored" % [SPLINES_ENTRY, VERSION])
		return
	var bodies: Variant = data.get("bodies")
	if not bodies is Array:
		log.add("%s needs a bodies list; water ignored" % SPLINES_ENTRY)
		return
	doc.water_bodies = parse_bodies(bodies, doc.extent_m(), log)
	if blobs.has(PONDS_ENTRY):
		_parse_ponds(blobs[PONDS_ENTRY], doc, log)
	if blobs.has(FLOW_ENTRY):
		_parse_flow(blobs[FLOW_ENTRY], data.get("flow"), doc, log)


# --- writing ------------------------------------------------------------------------


## One body's JSON form, as the document stores it (and a live water edit carries it).
static func body_json(body: WaterBody) -> Dictionary:
	var out := {
		"id": body.id,
		"kind": WaterBody.KIND_NAMES[body.kind],
		"depth": WaterBody.DEPTH_NAMES[body.depth],
		"level_m": body.level_m,
	}
	if body.is_river():
		var points: Array = []
		for p in body.points:
			points.append([p.x, p.y])
		out["speed"] = body.speed
		out["points"] = points
		out["half_widths"] = Array(body.half_widths)
		for key in BEYOND_KEYS:
			var course: PackedVector2Array = body.get(key)
			if not course.is_empty():
				out[key] = Array(course).map(func(p: Vector2) -> Array: return [p.x, p.y])
	return out


# --- reading ------------------------------------------------------------------------


## The bodies of a JSON list (body_json() forms, untrusted) on a map of `extent`: each one the
## rules accept, a warning in `log` for each one dropped.
static func parse_bodies(
	list: Array, extent: Vector2, log: MapDocumentIO._WarningLog
) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	var seen := {}
	var rivers := 0
	if list.size() > MapDocument.MAX_WATER_BODIES:
		log.add(
			(
				"%s: %d bodies over the cap of %d ignored"
				% [
					SPLINES_ENTRY,
					list.size() - MapDocument.MAX_WATER_BODIES,
					MapDocument.MAX_WATER_BODIES
				]
			)
		)
	for index in mini(list.size(), MapDocument.MAX_WATER_BODIES):
		var parsed: Variant = _body_from(list[index])
		var body: WaterBody = parsed if parsed is WaterBody else null
		if body != null:
			for key in BEYOND_KEYS:
				var course_problem := beyond_problem(body.get(key), extent)
				if course_problem != "":
					log.add(
						"%s: body %d %s dropped: %s" % [SPLINES_ENTRY, index, key, course_problem]
					)
					body.set(key, PackedVector2Array())
		var problem: String = parsed if parsed is String else body_problem(body, extent)
		if problem == "" and seen.has(body.id):
			problem = "id %d is used twice" % body.id
		if problem == "" and body.is_river() and rivers >= MapDocument.MAX_RIVERS:
			problem = "over the cap of %d rivers" % MapDocument.MAX_RIVERS
		if problem != "":
			log.add("%s: body %d skipped: %s" % [SPLINES_ENTRY, index, problem])
			continue
		seen[body.id] = true
		rivers += 1 if body.is_river() else 0
		out.append(body)
	return out


## A WaterBody from one JSON body, or a String saying why its shape is wrong. Values are
## taken as they are (a non-number becomes NAN) and left for body_problem() to judge;
## list sizes are checked before any per-element work.
static func _body_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return "not an object"
	var kind := WaterBody.KIND_NAMES.find(str(value.get("kind", "")))
	if kind < 0:
		return "unknown kind"
	var depth := WaterBody.DEPTH_NAMES.find(str(value.get("depth", "")))
	if depth < 0:
		return "unknown depth class"
	var id: Variant = MapDocumentIO._integer(value.get("id"), 1, WaterBody.MAX_ID)
	if id == null:
		return "id missing or outside 1..%d" % WaterBody.MAX_ID
	var body := WaterBody.new()
	body.id = id
	body.kind = kind as WaterBody.Kind
	body.depth = depth as WaterBody.Depth
	body.level_m = _number_or_nan(value.get("level_m"))
	if body.kind == WaterBody.Kind.POND:
		if value.has("points") or value.has("half_widths"):
			return "a pond has no line"
		return body
	body.speed = _number_or_nan(value.get("speed"))
	var points: Variant = value.get("points")
	var widths: Variant = value.get("half_widths")
	if not points is Array or not widths is Array:
		return "a river needs points and half_widths lists"
	if points.size() < 2 or points.size() > MapDocument.MAX_RIVER_POINTS:
		return "%d points, a river needs 2..%d" % [points.size(), MapDocument.MAX_RIVER_POINTS]
	if widths.size() != points.size():
		return "half_widths do not match the points"
	for p in points:
		if not p is Array or p.size() != 2:
			return "a point is not an [x, z] pair"
		body.points.append(Vector2(_number_or_nan(p[0]), _number_or_nan(p[1])))
	for w in widths:
		body.half_widths.append(_number_or_nan(w))
	for key in BEYOND_KEYS:
		if value.has(key):
			body.set(key, _course_from(value.get(key)))
	return body


## A course past the edge from JSON: its points, a NaN point standing in for anything that is
## not an [x, z] pair (beyond_problem() then drops it), or MAX_BEYOND_POINTS + 1 NaN points
## for a list too long or not a list.
static func _course_from(value: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not value is Array or (value as Array).size() > WaterBody.MAX_BEYOND_POINTS:
		out.resize(WaterBody.MAX_BEYOND_POINTS + 1)
		out.fill(Vector2(NAN, NAN))
		return out
	for p in value:
		if p is Array and (p as Array).size() == 2:
			out.append(Vector2(_number_or_nan(p[0]), _number_or_nan(p[1])))
		else:
			out.append(Vector2(NAN, NAN))
	return out


static func _parse_ponds(
	bytes: PackedByteArray, doc: MapDocument, log: MapDocumentIO._WarningLog
) -> void:
	var mask := MapDocumentIO._parse_mask(bytes, doc, Image.FORMAT_L8, PONDS_ENTRY, log)
	if mask.is_empty():
		return
	var ponds := PackedByteArray()
	ponds.resize(WaterBody.MAX_ID + 1)
	for body in doc.water_bodies:
		if not body.is_river():
			ponds[body.id] = 1
	var cleared := 0
	for i in mask.size():
		if mask[i] != 0 and ponds[mask[i]] == 0:
			mask[i] = 0
			cleared += 1
	if cleared > 0:
		log.add("%s: %d samples name no pond, cleared" % [PONDS_ENTRY, cleared])
	doc.pond_mask = mask


static func _parse_flow(
	bytes: PackedByteArray, meta: Variant, doc: MapDocument, log: MapDocumentIO._WarningLog
) -> void:
	var size := Vector2i.ZERO
	if meta is Dictionary and str(meta.get("frame", "")) == FLOW_FRAME:
		var pair: Variant = meta.get("size")
		if pair is Array and pair.size() == 2:
			var nx: Variant = MapDocumentIO._integer(pair[0], 2, MapDocument.MAX_FLOW_TEXELS)
			var nz: Variant = MapDocumentIO._integer(pair[1], 2, MapDocument.MAX_FLOW_TEXELS)
			if nx != null and nz != null:
				size = Vector2i(nx, nz)
	if size == Vector2i.ZERO:
		log.add("%s has no usable flow metadata; %s ignored" % [SPLINES_ENTRY, FLOW_ENTRY])
		return
	var declared := MapDocumentIO._png_size(bytes)
	if declared != size:
		log.add("%s is %s, its metadata says %s; ignored" % [FLOW_ENTRY, declared, size])
		return
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_size() != size:
		log.add("%s could not be decoded; ignored" % FLOW_ENTRY)
		return
	if image.get_format() != Image.FORMAT_RG8:
		image.convert(Image.FORMAT_RG8)
	doc.water_flow = image.get_data()
	doc.water_flow_size = size


static func _flow_size_ok(size: Vector2i) -> bool:
	var top := MapDocument.MAX_FLOW_TEXELS
	return size.x >= 2 and size.y >= 2 and size.x <= top and size.y <= top


static func _number_or_nan(value: Variant) -> float:
	var number: Variant = MapDocumentIO._number(value)
	return number if number != null else NAN


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
