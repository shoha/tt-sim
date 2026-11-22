class_name WaterRefit
extends RefCounted

## "Re-fit water" (card painter-water-condition): the plan-time conditioning of WaterEdit.plan_river
## applied to a stored document, for maps drawn before it existed or edited since. Pure: refit()
## works on a snapshot of the document and returns what the document would become; nothing is
## changed until the caller (WaterEditor.refit_water, one undoable history entry; a render job)
## lands it. In order:
##  1. a stroke whose stored levels climb downstream (WaterConditioner.climbs) is counted (`cut`,
##     not said to the author): it is resolved as the plan resolves a drawn line over a rise (card
##     painter-water-cut), by cutting. No part of a stream is ever turned round (until that card a
##     run of climbing reaches was reversed, which left a stream flowing two ways from a crest);
##  2. the river and pond tree (WaterPorts.graph) is solved (WaterConditioner.solve_tree): water
##     only lowered (a reach is at most the water upstream of it: the running minimum along a
##     stroke), steps under the dead band dropped onto the level below, ponds never moved;
##  3. every stroke is carved again at its new levels, in document order, so the banks follow the
##     water (the doc-level solve alone left perched edges, spike note (e)) and a lowered reach
##     gets its cut (WaterCarve.cut_stations).
## ascending_runs() and reverse_chain() are the older rule's parts, kept for tools and tests.
## Loaded by path from WaterEdit.refit_document (test_boot_graph).

## A run of reaches is reversed when its levels climb downstream by more than this (metres).
const REVERSE_MIN_M := 0.3


## What re-fitting `doc`'s water would do: {"bodies" (Array[WaterBody], new copies in the
## document's order), "heights" (the ground after the strokes' new carve), "reversed" (always 0:
## no stroke is turned round), "cut" (strokes whose stored climb is cut through), "changed"
## (bodies whose level moved), "moved" (largest level change, metres),
## "hints" (WaterHints records; none since the cut-through hint was removed), "before" and
## "after" (the WaterPorts.audit of the document and of the result)}.
static func refit(doc: MapDocument) -> Dictionary:
	var work := WaterMeshBuilder.snapshot(doc)
	var before: Dictionary = WaterPorts.audit(doc)
	var hints: Array[Dictionary] = []
	var cut := 0
	for chain in RiverProfile.strokes(work.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		var levels := PackedFloat64Array()
		for body in typed:
			levels.append(body.level_m)
		# A stored stroke that climbs is resolved as the plan resolves a drawn one (WaterEdit
		# cut_through): its direction stays, the solve below lowers the climbing reaches onto the
		# water above them and the re-carve cuts the rise.
		# Not said (the owner, 2026-11-22: the cut-through hint is unwanted); `cut` counts them.
		if not WaterConditioner.climbs(levels).is_empty():
			cut += 1
	var solved: Dictionary = WaterPorts.condition_doc(work)
	var levels: PackedFloat64Array = solved.levels
	var originals := doc.water_bodies
	var changed := 0
	var moved := 0.0
	for i in work.water_bodies.size():
		var shift := absf(levels[i] - originals[i].level_m)
		changed += 1 if shift > 1e-6 else 0
		moved = maxf(moved, shift)
	WaterPorts.apply_levels(work, levels)
	var all := work.water_bodies
	var after_doc := WaterMeshBuilder.snapshot(work)
	_recarve(work, all)
	work.water_bodies = all
	return {
		"bodies": all,
		"heights": work.heights,
		"reversed": 0,
		"cut": cut,
		"changed": changed,
		"moved": moved,
		"hints": hints,
		"before": before,
		"after": WaterPorts.audit(after_doc),
	}


## The runs of reaches `levels` (one per reach of a chain, in order) climbs along: maximal
## stretches of two or more reaches that never descend and rise by more than REVERSE_MIN_M in all,
## as inclusive index ranges. A single reach above its neighbours is a hump, not a stroke drawn the
## wrong way round: the tree solve lowers it instead.
static func ascending_runs(levels: PackedFloat64Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var i := 0
	while i < levels.size() - 1:
		var j := i
		while j < levels.size() - 1 and levels[j + 1] >= levels[j] - 0.001:
			j += 1
		if j > i and levels[j] - levels[i] > REVERSE_MIN_M:
			out.append(Vector2i(i, j))
		i = j + 1
	return out


## `chain` (a stroke's reaches in order, RiverProfile.strokes) turned round in place: each reach's
## points and half-widths reversed, the first reach's upstream skirt course and the last reach's
## downstream one traded, and the order of the reaches flipped in `chain`.
static func reverse_chain(chain: Array[WaterBody]) -> void:
	for body in chain:
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		for i in range(body.points.size() - 1, -1, -1):
			points.append(body.points[i])
			widths.append(body.half_widths[i])
		body.points = points
		body.half_widths = widths
		var down := body.beyond
		body.beyond = body.beyond_up
		body.beyond_up = down
	chain.reverse()


## `doc`'s ground lowered under every stroke of `bodies` in turn (the strokes as they were drawn:
## the document holds the ponds and the strokes before it), at the bodies' levels.
static func _recarve(doc: MapDocument, bodies: Array[WaterBody]) -> void:
	var ponds: Array[WaterBody] = []
	for body in bodies:
		if not body.is_river():
			ponds.append(body)
	doc.water_bodies = ponds
	for chain in RiverProfile.strokes(bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		var goals := WaterCarve.river_goals(doc, typed, doc.heights)
		WaterEditor.lower(doc, goals)
		doc.water_bodies = WaterEdit.with_bodies(doc, typed)


## The goals (WaterCarve goals: {"rect", "goals"}) that take heights `before` to `after` (one grid
## of `width` samples per row) when lowered to: where they differ, `after`, elsewhere INF.
static func goals_between(
	before: PackedFloat32Array, after: PackedFloat32Array, width: int
) -> Dictionary:
	var rect := changed_rect(before, after, width)
	var values := PackedFloat32Array()
	if not rect.has_area():
		return {"rect": rect, "goals": values}
	values.resize(rect.size.x * rect.size.y)
	for j in rect.size.y:
		for i in rect.size.x:
			var at := (rect.position.y + j) * width + rect.position.x + i
			values[j * rect.size.x + i] = after[at] if after[at] != before[at] else INF
	return {"rect": rect, "goals": values}


## The sample rectangle where `after` differs from `before` (heights of one grid of `width`
## samples per row); empty when they are equal.
static func changed_rect(
	before: PackedFloat32Array, after: PackedFloat32Array, width: int
) -> Rect2i:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-1, -1)
	for i in mini(before.size(), after.size()):
		if before[i] != after[i]:
			var x := i % width
			@warning_ignore("integer_division")
			var z := i / width
			low = Vector2i(mini(low.x, x), mini(low.y, z))
			high = Vector2i(maxi(high.x, x), maxi(high.y, z))
	if high.x < 0:
		return Rect2i()
	return Rect2i(low, high - low + Vector2i.ONE)
