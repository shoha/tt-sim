class_name CrossingPlacement
extends RefCounted

## Where a crossing drawn across water goes (phase 4b; the Bridge tool, P4b-2, calls it with a
## dragged line): the pure snapping rule from a drawn segment to an anchored Crossing, read
## from the document's ground and water alone (MapDocument.heights and water_bodies through
## WaterGeometry's point queries), so the tool only wires input. Summary:
## docs/ARCHITECTURE.md "Crossings".
##
## The rule. The drawn segment is walked every STEP_M, reaching SEARCH_M past both drawn ends
## (a short line dropped on the water still finds its banks). A sample is wet where its ground
## is below the water level there (WaterGeometry.is_wet_at). The wet runs along the walk are
## joined over dry gaps shorter than MIN_ISLAND_M (a bar in mid-stream is part of the water),
## and the run the drawn segment overlaps most is the water to cross (with no overlap, the run
## nearest the drawn middle, if within NEAR_M of the line). Each end of it is refined to the
## waterline, and the anchor goes BANK_INSET_M further onto the dry bank, so the crossing
## meets both banks on solid ground and sizes itself to the span. The line keeps the drawn
## direction.
##
## Levels. A plank bridge's ends stand CrossingGeometry.DECK_ABOVE_BANK_M over the bank
## ground at its anchors (its sills bedded there), and its middle rises in a gentle arch
## (ARCH_RISE_PER_M of span, MIN_RISE_M..MAX_RISE_M) and never lower than DECK_CLEAR_M over the
## highest water it crosses. Stepping stones put their tops STONE_FREEBOARD_M over that water.
##
## Refusals (the tool's message): the line is too short, crosses no water, has no dry bank
## within reach on a side (or runs off the map), comes within FALL_CLEAR_M of a waterfall
## (its face or its foam ring, fall_near(); bridges cross calm water, P4c-5), or the span
## exceeds Crossing.MAX_SPAN_M. A line across a fall's face alone crosses no water: the face
## is dry rock between the lip and the plunge pool.

const REFUSED_SHORT := &"short"
const REFUSED_NO_WATER := &"no_water"
const REFUSED_NO_BANK := &"no_bank"
const REFUSED_FALL := &"fall"
const REFUSED_LONG := &"long"

## A drawn line shorter than this is a click, not a crossing.
const MIN_DRAWN_M := 0.3
const SEARCH_M := 8.0
## Water the drawn line does not overlap counts only within this of it (a line drawn on the
## bank beside a river is not a crossing of it).
const NEAR_M := 1.0
const STEP_M := 0.1
## Waterline refinement: bisection steps between a dry and a wet sample (0.1 m / 2^6).
const REFINE_STEPS := 6
const MIN_ISLAND_M := 0.8
## Anchor distance past the waterline onto the bank, per Crossing.Kind: a bridge's sill needs
## firm ground under it; a stone path steps off near the edge.
const BANK_INSET_M: Array[float] = [0.55, 0.35]
const ARCH_RISE_PER_M := 0.06
const MIN_RISE_M := 0.12
const MAX_RISE_M := 0.8
const DECK_CLEAR_M := 0.45
## Over WaterZone's slab (level + 0.05) with the stones' jitter, so a token on a stone is dry.
const STONE_FREEBOARD_M := 0.15
## A crossing keeps at least this far from a waterfall's face and foam ring (fall_near()).
const FALL_CLEAR_M := 1.0


## The crossing of kind `kind` a line drawn from `from` to `to` (map XZ) makes over `doc`'s
## water: {"crossing": Crossing (id 0: the editor gives it one) or null, "refusal": &"" or a
## REFUSED_*}. `width` <= 0 takes the kind's default (Crossing.DEFAULT_WIDTH_M), others are
## clamped to its range; `style` is kept as given (style_at() picks the biome under it). Pure.
static func place(
	doc: MapDocument,
	from: Vector2,
	to: Vector2,
	kind: Crossing.Kind,
	width: float = -1.0,
	style: String = ""
) -> Dictionary:
	var drawn := to - from
	if drawn.length() < MIN_DRAWN_M:
		return _refused(REFUSED_SHORT)
	var d := drawn.normalized()
	var origin := from - d * SEARCH_M
	var count := ceili((drawn.length() + 2.0 * SEARCH_M) / STEP_M) + 1
	var half := doc.extent_m() * 0.5
	# The rivers smoothed once, not per point (the Bridge tool plans every pointer move).
	var walk := Rect2(origin, Vector2.ZERO).expand(origin + d * ((count - 1) * STEP_M))
	var courses := WaterGeometry.river_courses(doc, walk.grow(STEP_M))
	# 1 wet, 0 dry, -1 off the map.
	var state := PackedInt32Array()
	state.resize(count)
	for i in count:
		var p := origin + d * (i * STEP_M)
		if absf(p.x) > half.x or absf(p.y) > half.y:
			state[i] = -1
		else:
			state[i] = 1 if WaterGeometry.is_wet_at(doc, p, -1, courses) else 0
	var runs := _wet_runs(state)
	if runs.is_empty():
		return _refused(REFUSED_NO_WATER)
	var drawn_first := SEARCH_M / STEP_M
	var drawn_last := drawn_first + drawn.length() / STEP_M
	var run := _chosen_run(runs, drawn_first, drawn_last)
	var near := NEAR_M / STEP_M
	if run.x > drawn_last + near or run.y < drawn_first - near:
		return _refused(REFUSED_NO_WATER)
	if run.x <= 0 or run.y >= count - 1 or state[run.x - 1] != 0 or state[run.y + 1] != 0:
		return _refused(REFUSED_NO_BANK)
	var inset: float = BANK_INSET_M[kind]
	var shore_a := _waterline(doc, origin + d * ((run.x - 1) * STEP_M), d, courses)
	var shore_b := _waterline(doc, origin + d * ((run.y + 1) * STEP_M), -d, courses)
	var anchor_a := shore_a - d * inset
	var anchor_b := shore_b + d * inset
	for anchor in [anchor_a, anchor_b]:
		if absf(anchor.x) > half.x or absf(anchor.y) > half.y:
			return _refused(REFUSED_NO_BANK)
	var low: float = Crossing.MIN_WIDTH_M[kind]
	var high: float = Crossing.MAX_WIDTH_M[kind]
	var crossing_width: float = (
		Crossing.DEFAULT_WIDTH_M[kind] if width <= 0.0 else clampf(width, low, high)
	)
	if fall_near(doc, anchor_a, anchor_b, crossing_width):
		return _refused(REFUSED_FALL)
	if anchor_a.distance_to(anchor_b) > Crossing.MAX_SPAN_M:
		return _refused(REFUSED_LONG)
	var level := -INF
	for i in range(run.x, run.y + 1):
		var p := origin + d * (i * STEP_M)
		level = maxf(level, WaterGeometry.level_at(doc, p, -1, courses))
	var crossing := Crossing.new()
	crossing.kind = kind
	crossing.start = anchor_a
	crossing.end = anchor_b
	crossing.style = style
	crossing.width_m = crossing_width
	crossing.levels = levels_for(
		kind,
		WaterGeometry.ground_at(doc, anchor_a),
		WaterGeometry.ground_at(doc, anchor_b),
		level,
		anchor_a.distance_to(anchor_b)
	)
	return {"crossing": crossing, "refusal": &""}


## place()'s crossing, or null.
static func anchor(
	doc: MapDocument,
	from: Vector2,
	to: Vector2,
	kind: Crossing.Kind,
	width: float = -1.0,
	style: String = ""
) -> Crossing:
	return place(doc, from, to, kind, width, style)["crossing"]


## The levels (start, middle, end) of a crossing of `kind` whose anchors stand on ground
## `ground_a` and `ground_b` over water at `water` (the highest level it crosses), `span`
## metres long (see the header). The middle stays within Crossing.MAX_RISE_M of the ends'
## mean. Pure.
static func levels_for(
	kind: Crossing.Kind, ground_a: float, ground_b: float, water: float, span: float
) -> Vector3:
	var a := ground_a
	var b := ground_b
	var middle := water + STONE_FREEBOARD_M
	if kind == Crossing.Kind.PLANK:
		a += CrossingGeometry.DECK_ABOVE_BANK_M
		b += CrossingGeometry.DECK_ABOVE_BANK_M
		var rise := clampf(span * ARCH_RISE_PER_M, MIN_RISE_M, MAX_RISE_M)
		middle = maxf((a + b) * 0.5 + rise, water + DECK_CLEAR_M)
	var mean := (a + b) * 0.5
	middle = clampf(middle, mean - Crossing.MAX_RISE_M, mean + Crossing.MAX_RISE_M)
	return Vector3(a, middle, b)


## True when the strip from `a` to `b` (map XZ) `width` wide (a deck, or the stones' path)
## comes within FALL_CLEAR_M of a waterfall of `doc` (WaterFalls.falls): of its footprint
## (WaterFalls.footprint_of, the face from the lip to its foot across the channel) or of its
## foam ring (WaterFallMesh.ring_radius of the channel's full width, centred ring_centre()
## past the face's foot, WaterFalls.face_foot). A fall whose lip stands further from the
## strip than any of that reaches is not measured, so a line over calm water costs the
## falls() scan alone. Pure.
static func fall_near(doc: MapDocument, a: Vector2, b: Vector2, width: float) -> bool:
	var falls := WaterFalls.falls(doc)
	if falls.is_empty():
		return false
	var half := width * 0.5
	var columns := doc.samples_x()
	for fall in falls:
		var lip: Vector2 = fall.lip
		var channel: float = fall.half_width
		var drop := float(fall.top) - float(fall.bottom)
		var radius := WaterFallMesh.ring_radius(2.0 * channel)
		var reach := WaterFalls.face_search(drop, channel) + channel + 2.0 * radius + FALL_CLEAR_M
		if _strip_distance(a, b, half, lip) > reach:
			continue
		var foot := WaterFalls.face_foot(doc, fall)
		var centre := WaterFallMesh.ring_centre(lip, fall.dir, foot, radius)
		if _strip_distance(a, b, half, centre) <= radius + FALL_CLEAR_M:
			return true
		for i in WaterFalls.footprint_of(doc, fall):
			var p := doc.sample_to_world(Vector2(i % columns, floori(float(i) / columns)))
			if _strip_distance(a, b, half, p) <= FALL_CLEAR_M:
				return true
	return false


## The distance from map point `p` to the strip from `a` to `b` `half` wide either side (0
## inside it).
static func _strip_distance(a: Vector2, b: Vector2, half: float, p: Vector2) -> float:
	var d := b - a
	var span := d.length()
	if span < 1e-9:
		return maxf(p.distance_to(a) - half, 0.0)
	d /= span
	var local := p - a
	var u := local.dot(d)
	var v := local.dot(d.orthogonal())
	return Vector2(maxf(maxf(-u, u - span), 0.0), maxf(absf(v) - half, 0.0)).length()


## The palette biome painted under map point `p` (the document's biome mask, nearest sample),
## else the document's first biome, else "": the style a crossing placed there takes.
static func style_at(doc: MapDocument, p: Vector2) -> String:
	if doc.biome_ids.is_empty():
		return ""
	if doc.biome_slots.size() == doc.sample_count():
		var s := doc.world_to_sample(p).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		var slot := doc.biome_slots[doc.sample_index(x, z)]
		if slot > 0 and slot <= doc.biome_ids.size():
			return doc.biome_ids[slot - 1]
	return doc.biome_ids[0]


static func _refused(reason: StringName) -> Dictionary:
	return {"crossing": null, "refusal": reason}


## Inclusive index ranges Vector2i(first, last) of the wet samples of `state`, joined over dry
## gaps shorter than MIN_ISLAND_M (an off-map gap never joins).
static func _wet_runs(state: PackedInt32Array) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var i := 0
	while i < state.size():
		if state[i] != 1:
			i += 1
			continue
		var first := i
		while i < state.size() and state[i] == 1:
			i += 1
		var run := Vector2i(first, i - 1)
		if not runs.is_empty():
			var previous := runs[-1]
			var gap := run.x - previous.y - 1
			var dry := true
			for k in range(previous.y + 1, run.x):
				dry = dry and state[k] == 0
			if dry and gap * STEP_M < MIN_ISLAND_M:
				runs[-1] = Vector2i(previous.x, run.y)
				continue
		runs.append(run)
	return runs


## The run overlapping sample indices [first, last] most, else the one nearest their middle.
static func _chosen_run(runs: Array[Vector2i], first: float, last: float) -> Vector2i:
	var best := runs[0]
	var best_overlap := -INF
	var middle := (first + last) * 0.5
	for run in runs:
		var overlap := minf(run.y, last) - maxf(run.x, first)
		if overlap < 0.0:
			# No overlap: rank by distance to the middle, below every overlapping run.
			overlap = -1000.0 - minf(absf(run.x - middle), absf(run.y - middle))
		if overlap > best_overlap:
			best_overlap = overlap
			best = run
	return best


## The waterline between dry map point `dry` and the wet point STEP_M on along `toward`,
## by bisection (`courses`: WaterGeometry.river_courses of `doc`).
static func _waterline(
	doc: MapDocument, dry: Vector2, toward: Vector2, courses: Dictionary
) -> Vector2:
	var low := dry
	var high := dry + toward * STEP_M
	for _k in REFINE_STEPS:
		var mid := (low + high) * 0.5
		if WaterGeometry.is_wet_at(doc, mid, -1, courses):
			high = mid
		else:
			low = mid
	return low
