class_name WaterJunctions
extends RefCounted

## Where water meets water (card painter-water-junctions; docs/systems/water.md "Junctions").
##
## A junction is a place where two waters are one bed: a stroke crossing another or itself, a
## tributary's end in a stream, a fork, a pond dug over a stream, a stream's mouth in a pond, a
## ring closing on itself. It is DERIVED from the document's bodies, never stored: the plan makes
## the waters stand at one level there (WaterEdit._meet_crossed_water, WaterGeometry.
## pond_rim_level's `water`, the end pins), the carve only lowers (two beds at one level are one
## bed), and RiverProfile.stations() holds a bank or a bed that lies in other water at the
## station's level instead of calling it undermined (no film, no film_run or bridged_run event).
## So an edit or an erase needs no bookkeeping, and every peer finds the same junctions.
##
## find() lists them for hints, tests and the renderer's later use (the lap fade at a mouth, the
## cross-fade of two strokes' flow frames): the runs of stations a junction holds, one record per
## place. Waters that meet at levels further apart than the hold are not a junction: the higher
## one is not held, the field's events say so, and a fall into a pond is a stepped connector's
## (WaterPondFit).

## Records whose circles overlap by this share of the larger radius are one place.
const MERGE_SHARE := 1.0


## The junctions of `doc`: [{"pos" (map XZ), "radius" (metres: inside it the beds are one bed),
## "level" (the shared water level), "bodies" (PackedInt32Array: the first reach id of each
## stroke that meets there and the id of a pond under it; one id for a stroke meeting itself),
## "own" (true when a stroke meets only itself: a bend's inside, a self-crossing, a closed ring)}],
## in the document's stroke order. Pure; one RiverProfile.stations() pass per stroke.
static func find(doc: MapDocument) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for chain: Array in RiverProfile.strokes(doc.water_bodies):
		var stroke: Array[WaterBody] = []
		stroke.assign(chain)
		var profile := RiverProfile.for_doc(doc, stroke)
		if profile.points.size() < 2:
			continue
		var stations := profile.stations(doc, WaterFieldStroke.STATION_STEP)
		var marks: PackedByteArray = stations.junction
		var first := -1
		for i in marks.size() + 1:
			var on := i < marks.size() and marks[i] != 0
			if on and first < 0:
				first = i
			elif not on and first >= 0:
				runs.append(_run(doc, stroke[0].id, stations, first, i - 1))
				first = -1
	return _merged(runs)


## The junctions of `doc` (find()) whose circle holds map point `p`.
static func at(doc: MapDocument, p: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for junction in find(doc):
		if p.distance_to(junction.pos) <= float(junction.radius):
			out.append(junction)
	return out


## One stroke's run of junction stations `first`..`last` as a record (find()).
static func _run(
	doc: MapDocument, id: int, stations: Dictionary, first: int, last: int
) -> Dictionary:
	var marks: PackedByteArray = stations.junction
	@warning_ignore("integer_division")
	var mid := (first + last) / 2
	var pos: Vector2 = stations.centre[mid]
	var half := (float(stations.arc[last]) - float(stations.arc[first])) * 0.5
	var own := true
	for i in range(first, last + 1):
		own = own and marks[i] == RiverProfile.JUNCTION_OWN
	var bodies := PackedInt32Array([id])
	var pond := 0
	if doc.pond_mask.size() == doc.sample_count() and doc.sample_count() > 0:
		var last_sample := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
		var s := doc.world_to_sample(pos).round().clamp(Vector2.ZERO, last_sample)
		pond = doc.pond_mask[doc.sample_index(int(s.x), int(s.y))]
	if pond > 0:
		bodies.append(pond)
		own = false
	return {
		"pos": pos,
		"radius": half + float(stations.half_width[mid]) + WaterGeometry.RIVER_BANK_M,
		"level": float(stations.level[mid]),
		"bodies": bodies,
		"own": own,
	}


## `runs` with the records of one place merged: their circle, every body, the highest level.
static func _merged(runs: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run in runs:
		var into := -1
		for k in out.size():
			var reach := maxf(float(out[k].radius), float(run.radius)) * MERGE_SHARE
			if (out[k].pos as Vector2).distance_to(run.pos) <= reach:
				into = k
				break
		if into < 0:
			out.append(run.duplicate(true))
			continue
		var place := out[into]
		var gap := (place.pos as Vector2).distance_to(run.pos)
		var bodies: PackedInt32Array = place.bodies
		for id in run.bodies as PackedInt32Array:
			if not bodies.has(id):
				bodies.append(id)
		place.bodies = bodies
		place.radius = maxf(float(place.radius), gap + float(run.radius))
		place.level = maxf(float(place.level), float(run.level))
		place.own = bool(place.own) and bool(run.own) and bodies.size() == 1
	return out
