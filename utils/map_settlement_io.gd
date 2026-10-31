class_name MapSettlementIO
extends RefCounted

## The settlements entry of `map.ttmap` (dressed streets), written and read for MapDocumentIO in
## the way MapWallIO does for walls. Summary: docs/systems/settlements.md.
##
##   settlements.json  {"version": 1, "settlements": [settlement, ...]}
##                     settlement: {"id", "kit", "seed", "wealth", "density", "source",
##                       "frozen": [frontage, ...], "removed": [slot, ...],
##                       "pinned": {slot: {"prop", "at": [x, z], "yaw", "scale", "seed"}},
##                       "swapped": {slot: prop}}
##
## A map written before settlements has no such entry and loads unchanged; an older build ignores
## the entry (MapDocumentIO.KNOWN_ENTRIES) and drops it on its next save. Everything read is
## untrusted: a settlement with any problem (id outside 1..32 or repeated, unknown kit, a seed,
## wealth or density out of range, a source with no street id and no frozen frontage, a frozen
## frontage procgen refuses, more than the override caps, a prop name procgen does not know) is
## skipped with a warning, as are settlements past MapDocument.MAX_SETTLEMENTS. The writer refuses
## a document breaking any of these rules (problem()).

const ENTRY := "settlements.json"
const VERSION := 1


static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	if doc.settlements.is_empty():
		return
	var list: Array = []
	for settlement in doc.settlements:
		list.append(settlement_json(settlement))
	var data := {"version": VERSION, "settlements": list}
	entries[ENTRY] = JSON.stringify(data, "", false, true).to_utf8_buffer()


## The first settlement rule `doc` breaks, or "".
static func problem(doc: MapDocument) -> String:
	if doc.settlements.size() > MapDocument.MAX_SETTLEMENTS:
		return "more than %d settlements" % MapDocument.MAX_SETTLEMENTS
	var seen := {}
	var streets := {}
	for settlement in doc.settlements:
		if settlement == null:
			return "a null settlement"
		var reason := settlement_problem(settlement)
		if reason != "":
			return "settlement %d: %s" % [settlement.id, reason]
		if seen.has(settlement.id):
			return "settlement id %d is used twice" % settlement.id
		seen[settlement.id] = true
		if settlement.source > 0:
			if streets.has(settlement.source):
				return "street %d is dressed twice" % settlement.source
			streets[settlement.source] = true
	return ""


## What is wrong with `settlement`, or "". Shared by the writer, the reader and SettlementEditor.
static func settlement_problem(settlement: Settlement) -> String:
	if settlement.id < 1 or settlement.id > Settlement.MAX_ID:
		return "id outside 1..%d" % Settlement.MAX_ID
	if not Settlement.KIND_NAMES.has(settlement.kit):
		return "unknown kit"
	if settlement.seed_value < 0 or settlement.seed_value > Settlement.MAX_SEED:
		return "seed outside 0..%d" % Settlement.MAX_SEED
	if not _within(settlement.wealth, 0.0, 1.0):
		return "wealth outside 0..1"
	if not _within(settlement.density, 0.0, Settlement.MAX_DENSITY):
		return "density outside 0..%s" % Settlement.MAX_DENSITY
	if settlement.source < 0 or settlement.source > Wall.MAX_ID:
		return "source outside 0..%d" % Wall.MAX_ID
	if settlement.frozen.size() > Settlement.MAX_FROZEN:
		return "more than %d frozen frontages" % Settlement.MAX_FROZEN
	if settlement.source == 0 and settlement.frozen.is_empty():
		return "no street and no frozen frontage"
	for data in settlement.frozen:
		var frontage := ProcgenFrontage.from_dict(data)
		if not frontage.problems().is_empty() or frontage.lots.size() > Settlement.MAX_LOTS:
			return "a frozen frontage is not usable"
	if (
		settlement.removed.size() > Settlement.MAX_OVERRIDES
		or settlement.pinned.size() > Settlement.MAX_OVERRIDES
		or settlement.swapped.size() > Settlement.MAX_OVERRIDES
	):
		return "more than %d overrides" % Settlement.MAX_OVERRIDES
	for slot in settlement.removed:
		if not _slot_ok(slot):
			return "a removed slot is not a short text"
	for slot: Variant in settlement.swapped:
		if not _slot_ok(slot) or not ProcgenProps.NAMES.has(str(settlement.swapped[slot])):
			return "a swapped slot or prop is unknown"
	for slot: Variant in settlement.pinned:
		if not _slot_ok(slot) or _pin_problem(settlement.pinned[slot]) != "":
			return "a pinned placement is not usable"
	return ""


static func parse(blobs: Dictionary, doc: MapDocument, warn_log: MapDocumentIO._WarningLog) -> void:
	if not blobs.has(ENTRY):
		return
	var data: Variant = MapDocumentIO._json(blobs[ENTRY], ENTRY, warn_log)
	var version: Variant = null
	if data is Dictionary:
		version = MapDocumentIO._integer(data.get("version"), 0, 1000000)
	if version != VERSION:
		warn_log.add(
			"%s is not a version %d settlements object; settlements ignored" % [ENTRY, VERSION]
		)
		return
	var list: Variant = data.get("settlements")
	if not list is Array:
		warn_log.add("%s needs a settlements list; settlements ignored" % ENTRY)
		return
	doc.settlements = parse_list(list, warn_log)


# --- writing ------------------------------------------------------------------------


## One settlement's JSON form, as the document stores it (and a live edit carries it).
static func settlement_json(settlement: Settlement) -> Dictionary:
	var removed: Array = []
	for slot in settlement.removed:
		removed.append(slot)
	var pinned := {}
	for slot: Variant in settlement.pinned:
		var pin: Dictionary = settlement.pinned[slot]
		var at: Vector2 = pin["at"]
		pinned[str(slot)] = {
			"prop": pin["prop"],
			"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)],
			"yaw": snappedf(float(pin["yaw"]), 0.001),
			"scale": snappedf(float(pin["scale"]), 0.01),
			"seed": int(pin["seed"]),
		}
	var swapped := {}
	for slot: Variant in settlement.swapped:
		swapped[str(slot)] = str(settlement.swapped[slot])
	return {
		"id": settlement.id,
		"kit": settlement.kit,
		"seed": settlement.seed_value,
		"wealth": snappedf(settlement.wealth, Settlement.WEALTH_STEP),
		"density": snappedf(settlement.density, Settlement.WEALTH_STEP),
		"source": settlement.source,
		"frozen": settlement.frozen.duplicate(true),
		"removed": removed,
		"pinned": pinned,
		"swapped": swapped,
	}


# --- reading ------------------------------------------------------------------------


## The settlements of a JSON list (settlement_json() forms, untrusted): each one
## settlement_problem() accepts, a warning in `warn_log` for each one dropped.
static func parse_list(list: Array, warn_log: MapDocumentIO._WarningLog) -> Array[Settlement]:
	var out: Array[Settlement] = []
	var seen := {}
	var streets := {}
	if list.size() > MapDocument.MAX_SETTLEMENTS:
		warn_log.add(
			(
				"%s: %d settlements over the cap of %d ignored"
				% [ENTRY, list.size() - MapDocument.MAX_SETTLEMENTS, MapDocument.MAX_SETTLEMENTS]
			)
		)
	for index in mini(list.size(), MapDocument.MAX_SETTLEMENTS):
		var parsed: Variant = _settlement_from(list[index])
		var settlement: Settlement = parsed if parsed is Settlement else null
		var reason: String = parsed if parsed is String else settlement_problem(settlement)
		if reason == "" and seen.has(settlement.id):
			reason = "id %d is used twice" % settlement.id
		if reason == "" and settlement.source > 0 and streets.has(settlement.source):
			reason = "street %d is dressed twice" % settlement.source
		if reason != "":
			warn_log.add("%s: settlement %d skipped: %s" % [ENTRY, index, reason])
			continue
		seen[settlement.id] = true
		if settlement.source > 0:
			streets[settlement.source] = true
		out.append(settlement)
	return out


static func _settlement_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return "not an object"
	var id: Variant = MapDocumentIO._integer(value.get("id"), 1, Settlement.MAX_ID)
	if id == null:
		return "id missing or outside 1..%d" % Settlement.MAX_ID
	var kit: Variant = value.get("kit")
	if not kit is String:
		return "kit is not a string"
	var seed_read: Variant = MapDocumentIO._integer(value.get("seed", 0), 0, Settlement.MAX_SEED)
	var source: Variant = MapDocumentIO._integer(value.get("source", 0), 0, Wall.MAX_ID)
	if seed_read == null or source == null:
		return "seed or source is not a whole number in range"
	var settlement := Settlement.make(id, kit, source, seed_read)
	settlement.wealth = _number_or_nan(value.get("wealth", Settlement.DEFAULT_WEALTH))
	settlement.density = _number_or_nan(value.get("density", Settlement.DEFAULT_DENSITY))
	var frozen: Variant = value.get("frozen", [])
	if not frozen is Array or (frozen as Array).size() > Settlement.MAX_FROZEN:
		return "frozen is not a short list"
	for entry: Variant in frozen:
		if not entry is Dictionary:
			return "a frozen frontage is not an object"
		settlement.frozen.append(entry)
	var removed: Variant = value.get("removed", [])
	if not removed is Array or (removed as Array).size() > Settlement.MAX_OVERRIDES:
		return "removed is not a short list"
	for slot: Variant in removed:
		if not slot is String:
			return "a removed slot is not a string"
		settlement.removed.append(slot)
	var swapped: Variant = value.get("swapped", {})
	if not swapped is Dictionary or (swapped as Dictionary).size() > Settlement.MAX_OVERRIDES:
		return "swapped is not a short object"
	for slot: Variant in swapped:
		settlement.swapped[str(slot)] = str(swapped[slot])
	var pinned: Variant = value.get("pinned", {})
	if not pinned is Dictionary or (pinned as Dictionary).size() > Settlement.MAX_OVERRIDES:
		return "pinned is not a short object"
	for slot: Variant in pinned:
		var pin: Variant = _pin_from(pinned[slot])
		if pin == null:
			return "a pinned placement is not usable"
		settlement.pinned[str(slot)] = pin
	return settlement


static func _pin_from(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var at: Variant = value.get("at")
	if not at is Array or (at as Array).size() != 2:
		return null
	var pin := {
		"prop": str(value.get("prop", "")),
		"at": Vector2(_number_or_nan(at[0]), _number_or_nan(at[1])),
		"yaw": _number_or_nan(value.get("yaw")),
		"scale": _number_or_nan(value.get("scale")),
		"seed": MapDocumentIO._integer(value.get("seed"), 0, ProcgenSettlement.VARIANTS - 1),
	}
	return pin if _pin_problem(pin) == "" else null


static func _pin_problem(pin: Variant) -> String:
	if not pin is Dictionary:
		return "not an object"
	var at: Variant = pin.get("at")
	if not at is Vector2 or not _finite((at as Vector2).x) or not _finite((at as Vector2).y):
		return "position"
	if not ProcgenProps.NAMES.has(str(pin.get("prop", ""))):
		return "prop"
	if not _within(float(pin.get("yaw", NAN)), -10.0, 10.0):
		return "yaw"
	if not _within(float(pin.get("scale", NAN)), 0.3, 3.0):
		return "scale"
	if pin.get("seed") == null:
		return "seed"
	return ""


static func _slot_ok(slot: Variant) -> bool:
	return (
		slot is String
		and (slot as String).length() > 0
		and (slot as String).length() <= Settlement.MAX_TEXT
	)


static func _number_or_nan(value: Variant) -> float:
	var number: Variant = MapDocumentIO._number(value)
	return number if number != null else NAN


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _within(value: float, low: float, high: float) -> bool:
	return not is_nan(value) and value >= low and value <= high
