class_name SettlementGroundIO
extends RefCounted

## The ground strokes a Dress laid, as the settlement record keeps them (`Settlement.ground`,
## villages3): one dictionary per capsule {"surface": palette surface id, "from": Vector2,
## "to": Vector2, "radius": metres, "seconds": exposure}, in paint order. The record keeps them so
## Clear and a re-dress can take back exactly that paint (SettlementUnpaint) and leave ground the
## author painted. Positions, radii and exposures are held to a hundredth (snapped_stroke), the
## host paints with the snapped values and a peer reads the same ones, so the list round trips
## byte for byte. Summary: docs/systems/settlements.md "Ground".
##
## Saved form (inside the settlement entry, left out when there are no strokes):
##   "ground": {"surfaces": [surface id, ...],
##              "strokes": [[surface index, from x, from z, to x, to z, radius, seconds], ...]}
## Everything read is untrusted: a wrong shape, an unlisted surface index, a number out of range, or
## more than MAX_STROKES strokes or MAX_SURFACES surfaces refuses the whole list (null).

const MAX_STROKES := 256
const MAX_SURFACES := 4
const STEP := 0.01
## A stroke stays within this of the map's middle (a map is at most 640 m a side).
const REACH_M := 1000.0
const MIN_RADIUS_M := 0.05
const MAX_RADIUS_M := 20.0
const MIN_SECONDS := 0.05
const MAX_SECONDS := 10.0


## `stroke` (SettlementGround.plan's, with any extra keys such as "role") reduced to the five
## fields the record keeps, each held to a hundredth.
static func snapped_stroke(stroke: Dictionary) -> Dictionary:
	var from: Vector2 = stroke["from"]
	var to: Vector2 = stroke["to"]
	return {
		"surface": str(stroke["surface"]),
		"from": Vector2(snappedf(from.x, STEP), snappedf(from.y, STEP)),
		"to": Vector2(snappedf(to.x, STEP), snappedf(to.y, STEP)),
		"radius": snappedf(float(stroke["radius"]), STEP),
		"seconds": snappedf(float(stroke["seconds"]), STEP),
	}


## What is wrong with `strokes`, or "".
static func problem(strokes: Array[Dictionary]) -> String:
	if strokes.size() > MAX_STROKES:
		return "more than %d ground strokes" % MAX_STROKES
	var surfaces := {}
	for stroke in strokes:
		var why := _stroke_problem(stroke)
		if why != "":
			return "a ground stroke is not usable (%s)" % why
		surfaces[stroke["surface"]] = true
	if surfaces.size() > MAX_SURFACES:
		return "ground on more than %d surfaces" % MAX_SURFACES
	return ""


## The saved form of `strokes` ({} when there are none).
static func to_json(strokes: Array[Dictionary]) -> Dictionary:
	if strokes.is_empty():
		return {}
	var surfaces: Array = []
	var rows: Array = []
	for stroke in strokes:
		var surface := str(stroke["surface"])
		if not surfaces.has(surface):
			surfaces.append(surface)
		var from: Vector2 = stroke["from"]
		var to: Vector2 = stroke["to"]
		rows.append(
			[
				surfaces.find(surface),
				snappedf(from.x, STEP),
				snappedf(from.y, STEP),
				snappedf(to.x, STEP),
				snappedf(to.y, STEP),
				snappedf(float(stroke["radius"]), STEP),
				snappedf(float(stroke["seconds"]), STEP),
			]
		)
	return {"surfaces": surfaces, "strokes": rows}


## The strokes of a saved form (untrusted), or null when it is not usable.
static func from_json(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var surfaces: Variant = value.get("surfaces")
	var rows: Variant = value.get("strokes")
	if not surfaces is Array or not rows is Array:
		return null
	if (surfaces as Array).size() > MAX_SURFACES or (rows as Array).size() > MAX_STROKES:
		return null
	for surface: Variant in surfaces:
		if not MapDocumentIO._is_id(surface):
			return null
	var out: Array[Dictionary] = []
	for row: Variant in rows:
		if not row is Array or (row as Array).size() != 7:
			return null
		var index: Variant = MapDocumentIO._integer(row[0], 0, (surfaces as Array).size() - 1)
		if index == null:
			return null
		var numbers: Array[float] = []
		for k in range(1, 7):
			var number: Variant = MapDocumentIO._number(row[k])
			if number == null:
				return null
			numbers.append(number)
		var stroke := {
			"surface": str(surfaces[index]),
			"from": Vector2(numbers[0], numbers[1]),
			"to": Vector2(numbers[2], numbers[3]),
			"radius": numbers[4],
			"seconds": numbers[5],
		}
		if _stroke_problem(stroke) != "":
			return null
		out.append(snapped_stroke(stroke))
	return out if problem(out) == "" else null


static func _stroke_problem(stroke: Variant) -> String:
	if not stroke is Dictionary:
		return "not an object"
	if not MapDocumentIO._is_id(stroke.get("surface")):
		return "surface"
	for key in ["from", "to"]:
		var at: Variant = stroke.get(key)
		if not at is Vector2:
			return key
		var point: Vector2 = at
		if not _within(point.x, -REACH_M, REACH_M) or not _within(point.y, -REACH_M, REACH_M):
			return key
	if not _within(float(stroke.get("radius", NAN)), MIN_RADIUS_M, MAX_RADIUS_M):
		return "radius"
	if not _within(float(stroke.get("seconds", NAN)), MIN_SECONDS, MAX_SECONDS):
		return "seconds"
	return ""


static func _within(value: float, low: float, high: float) -> bool:
	return not is_nan(value) and value >= low and value <= high
