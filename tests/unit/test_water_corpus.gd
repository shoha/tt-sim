extends GutTest

## The water corpus's field-side checks (water_corpus_cases.gd; docs/systems/water.md "The water
## corpus"): every corpus map is built the way the Water tool builds it and its WaterField is read
## for what no render is needed to see. Hard rules: no NaN, the lateral coordinate inside the
## widest channel. Ratchets: the counts of discontinuities the corpus holds today (a stroke's
## flow or lateral coordinate jumping between neighbouring samples, deep water standing beside dry
## ground, the field's film and bridged runs) may fall, never rise; lower a number here when a
## change removes some. The path rules of card painter-water-paths are asserted per layout: the
## same drawing joins the same ends wherever and whenever it is drawn, a stream within its own
## width of a pond is joined to it, a stroke keeps its length, and a stroke that cannot hold
## water is refused whole and carves nothing.

const Corpus := preload("res://tests/unit/water_corpus_cases.gd")

## Per map: [u_jumps, lat_jumps, perched, film_run, bridged_run, end_near_water] as of card
## painter-water-paths (2026-11-20), on the corpus as respaced by that card (cells 24 m apart, so
## that no layout touches its neighbour). The same corpus on the code before the card: flat [2,
## 8, 0, 4, 12, 0], flat2 [0, 0, 0, 1, 0, 0], tilt [1, 14, 0, 3, 4, 0], steps [0, 0, 10, 0, 0, 1],
## steps_wide [0, 0, 2, 0, 2, 0]. What rose, and why it was accepted:
##  - flat: f_self_cross keeps its loop (a 32 m stroke was stored as its first 8 m), and a stroke
##    that crosses itself has what two crossing strokes have: the flow coordinate jumps where the
##    passes meet (u_jumps 41, lat_jumps 12) and each pass finds the other's bed where its bank
##    should be (film_run 2, bridged_run 1). The junction is the next card's.
##  - steps_wide: the widest stroke is a fall now (it was kept as drawn, blocked: six reaches
##    down the cliff's face), and a fall's lip is perched.
##
## Card painter-water-junctions (2026-11-20) brought them down: where water meets water the two
## are one bed (RiverProfile's junction rule), so a crossing, a join, a fork, a pond over a stream
## and the inside of a tight bend raise no film or bridged run (flat film 6 and bridged 13, flat2
## film 1, tilt film 3 and bridged 4, all to 0). The flow and lateral jumps where a stroke meets
## ITSELF (f_self_cross's crossing 41 and 12, f_loop's closure 14, a bend's inside 2 and 1) are
## counted apart as junction_seams (JUNCTION_SEAMS below): two passes of one stroke meet there as
## two strokes do (seam_pairs), two frames at one place that the renderer has to cross-fade, not a
## break inside one frame. What is left in lat_jumps is tilt's t_through_pond (10) and t_y_join
## (4): a stroke's end in other water at a riffle.
const KNOWN := {
	"flat": [0, 0, 0, 0, 0, 0],
	"flat2": [0, 0, 0, 0, 0, 0],
	"tilt": [0, 14, 0, 0, 0, 0],
	"steps": [0, 0, 10, 0, 0, 1],
	"steps_wide": [0, 0, 4, 0, 0, 0],
	"wood": [0, 0, 0, 0, 0, 0],
}

## Per map: the coordinate jumps inside a stroke's junction with itself (a ratchet too).
const JUNCTION_SEAMS := {"flat": 43, "flat2": 14, "tilt": 1, "steps": 0, "steps_wide": 0, "wood": 0}

## The stream ends each pond of these layouts joins (WaterEditor.compute "joined"). 0: the ends
## are within reach but at another level, the stepped connector would stand proud of its bank
## (perched samples), so the guard drops the join and the end is said (not solved: the samples are
## proud by the corpus's own measure too, water over 0.3 m above the dry ground beside it).
## f_end_short's 2.0 m gap is joined since the reach is 2 half-widths (card
## painter-water-junctions).
const JOINED := {
	"f_through_far": 3,
	"f_through_pond": 3,
	"t_through_pond": 3,
	"f_into_pond": 1,
	"f_end_short": 1,
	"t_end_short": 0,
	"s0_fall_pond": 0,
}

## Layouts where water meets water at one level: each holds a junction and no film or bridged run.
const ONE_BED := [
	"f_cross",
	"f_y_join",
	"f_split",
	"f_self_cross",
	"f_pond_over_stream",
	"f_loop",
	"t_cross",
	"t_y_join",
]

var _was_enabled := true
var _builds := {}


func before_all() -> void:
	_was_enabled = WaterEdit.conditioning_enabled
	WaterEdit.conditioning_enabled = true


func after_all() -> void:
	WaterEdit.conditioning_enabled = _was_enabled
	_builds.clear()


## Corpus map `name` built once for the whole script.
func _built(name: String) -> Dictionary:
	if not _builds.has(name):
		_builds[name] = Corpus.build(Corpus.map_named(name))
	return _builds[name]


## Layout `name` alone on a 200 ft map of its ground, at `at`, its ops in `order` (indices).
func _alone(name: String, at: Vector2, order: Array = []) -> Dictionary:
	var l := Corpus.layout_named(name)
	var m := Corpus.map_named(String(l.map))
	var ops: Array = l.ops
	if not order.is_empty():
		ops = []
		for i: int in order:
			ops.append(l.ops[i])
	var one := {"name": name, "at": at, "ops": ops}
	return Corpus.build({"name": "one", "size_ft": 200, "ground": m.ground, "layouts": [one]})


func test_layout_names_are_unique() -> void:
	var seen := {}
	for m in Corpus.maps():
		for l: Dictionary in m.layouts:
			assert_false(seen.has(l.name), "layout %s is listed once" % l.name)
			seen[l.name] = true
	assert_gt(seen.size(), 40, "the corpus holds its layouts")


func test_a_build_repeats() -> void:
	var m := Corpus.map_named("tilt")
	var a: MapDocument = _built("tilt").doc
	var b: MapDocument = Corpus.build(m).doc
	assert_eq(Corpus.digest(a), Corpus.digest(b), "two builds of one map are the same document")
	assert_gt(a.water_bodies.size(), 10, "the tilt map holds its water")


func test_field_of_every_map() -> void:
	for m in Corpus.maps():
		var built := _built(m.name)
		var doc: MapDocument = built.doc
		# A map of too many layouts reaches the document's body cap and its last strokes are
		# refused: every stroke of the corpus must land, but the one that cannot hold water
		# (f_short's 0.9 m line: test_a_stroke_too_short_to_hold_water...).
		for s: Dictionary in built.strokes:
			if s.layout == "f_short" and s.get("refused", "") == "too_short":
				continue
			assert_false(s.has("refused"), "%s: a stroke of %s was refused" % [m.name, s.layout])
		var r := Corpus.field_report(doc)
		var known: Array = KNOWN[m.name]
		var film := int(r.events.get(&"film_run", 0))
		var bridged := int(r.events.get(&"bridged_run", 0))
		gut.p(
			(
				"corpus %s: digest %s, bodies %d, u_jumps %d, lat_jumps %d, perched %d, film %d, bridged %d"
				% [
					m.name,
					Corpus.digest(doc),
					doc.water_bodies.size(),
					r.u_jumps,
					r.lat_jumps,
					r.perched,
					film,
					bridged
				]
			)
		)
		# What the Water tool builds must save: the writer refuses a document past the reader's
		# caps (a fall's plunge pool on the widest stroke once widened past MAX_HALF_WIDTH_M).
		var packed := MapDocumentSnapshot.capture(doc).encode()
		assert_eq(String(packed.error), "", "%s: the document can be saved" % m.name)
		assert_gt(int(r.wet), 1000, "%s: the field holds water" % m.name)
		assert_eq(int(r.nan), 0, "%s: no NaN or infinite value in a wet sample" % m.name)
		assert_eq(int(r.lateral_out), 0, "%s: the lateral coordinate stays inside the channel" % m.name)
		assert_lte(int(r.u_jumps), int(known[0]), "%s: flow coordinate jumps inside a stroke" % m.name)
		assert_lte(int(r.lat_jumps), int(known[1]), "%s: lateral jumps inside a stroke" % m.name)
		assert_lte(int(r.perched), int(known[2]), "%s: deep water beside dry ground" % m.name)
		assert_lte(film, int(known[3]), "%s: film runs" % m.name)
		assert_lte(bridged, int(known[4]), "%s: bridged runs" % m.name)
		var near := int(r.events.get(&"end_near_water", 0))
		assert_lte(near, int(known[5]), "%s: stroke ends left short of water" % m.name)
		var seams := int(JUNCTION_SEAMS[m.name])
		assert_lte(int(r.junction_seams), seams, "%s: jumps where a stroke meets itself" % m.name)


func test_water_that_meets_water_is_one_bed() -> void:
	var seen := 0
	for m in Corpus.maps():
		var r: Dictionary = Corpus.field_report(_built(m.name).doc)
		for l: Dictionary in m.layouts:
			if not ONE_BED.has(l.name):
				continue
			seen += 1
			var at: Vector2 = l.at
			var junctions := 0
			for junction: Dictionary in r.junctions:
				junctions += 1 if at.distance_to(junction.pos) < Corpus.CELL_HALF else 0
			assert_gt(junctions, 0, "%s: the meeting is a junction" % l.name)
			for e: Dictionary in r.event_list:
				if at.distance_to(e.pos) < Corpus.CELL_PITCH * 0.5:
					assert_eq(e.kind, &"end_near_water", "%s: no run of undermined water" % l.name)
	assert_eq(seen, ONE_BED.size(), "every such layout was built")


func test_a_junction_is_one_level() -> void:
	# Crossing strokes on the tilt stood 5 cm apart (-1.45 and -1.50): the later one takes the
	# crossed water's level. A pond dug over a stream stood a bed's depth under it (-1.20 against
	# -0.15): it takes the stream's level.
	var cross := _alone("t_cross", Vector2.ZERO)
	var first: PackedInt32Array = cross.strokes[0].ids
	var second: PackedInt32Array = cross.strokes[1].ids
	var crossed := PackedFloat32Array()
	for id in first:
		crossed.append((cross.doc as MapDocument).water_body(id).level_m)
	var met := false
	for id in second:
		met = met or crossed.has((cross.doc as MapDocument).water_body(id).level_m)
	assert_true(met, "a reach of the crossing stroke stands at the crossed stream's level")
	var over := _alone("f_pond_over_stream", Vector2.ZERO)
	var doc: MapDocument = over.doc
	var stream := doc.water_body((over.strokes[0].ids as PackedInt32Array)[0])
	var pond := doc.water_body(int(over.ponds[0].id))
	assert_almost_eq(pond.level_m, stream.level_m, 1e-4, "the pond stands at the stream's level")
	# A drawn ring closes: neither end tapers, and the closure is the stroke's own junction.
	var ring := _alone("f_loop", Vector2.ZERO)
	var chain: Array[WaterBody] = []
	for id in ring.strokes[0].ids as PackedInt32Array:
		chain.append((ring.doc as MapDocument).water_body(id))
	var profile := RiverProfile.for_doc(ring.doc, chain)
	assert_eq(profile.taper, Vector2i.ZERO, "a closed ring has no tapered end")
	assert_eq(profile.own_end, Vector2i.ONE, "both ends lie in the stroke's own channel")
	var own := 0
	for junction in WaterJunctions.find(ring.doc):
		own += 1 if bool(junction.own) else 0
	assert_eq(own, 1, "the closure is one junction of the stroke with itself")


func test_a_join_the_document_has_no_room_for_is_said() -> void:
	# f_into_pond with the document one river short of its cap: the connector's two reaches do
	# not fit. It was skipped silently.
	var doc := NewMap.create(200, Corpus.BIOME, 1234)
	var hw := WaterBrush.radius_for(1.0, Corpus.WAIST)
	var line := Corpus.gesture_line(PackedVector2Array([Vector2(-8, 0), Vector2(-1.6, 0)]), hw)
	Corpus.add_stroke(doc, line, hw, Corpus.WAIST)
	var bodies := doc.water_bodies.duplicate()
	var k := 0
	while bodies.size() < MapDocument.MAX_RIVERS - 1:
		var from := Vector2(-28.0 + 1.5 * k, -27.0)
		var pts := PackedVector2Array([from, from + Vector2(0.0, 1.0)])
		var filler := WaterBody.river(
			doc.next_water_id() + k, pts, PackedFloat32Array([0.3, 0.3]), Corpus.ANKLE, -0.15, 1.0
		)
		bodies.append(filler)
		k += 1
	doc.water_bodies = bodies
	var out := Corpus.dig(doc, PackedVector2Array([Vector2(3, 0), Vector2(3.4, 0)]), 3.5, Corpus.DEEP)
	assert_eq(int(out.get("joined", 0)), 0, "nothing is joined")
	var said := false
	for hint: Dictionary in out.get("hints", []):
		said = said or hint.kind == &"no_room"
	assert_true(said, "the full document is said")
	assert_true(WaterHints.worth_saying(out.hints), "and worth a toast")


func test_streams_within_their_own_width_of_a_pond_are_joined_or_said() -> void:
	var seen := {}
	for m in Corpus.maps():
		for p: Dictionary in _built(m.name).ponds:
			if not JOINED.has(p.layout):
				continue
			seen[p.layout] = true
			var want := int(JOINED[p.layout])
			assert_eq(int(p.get("joined", 0)), want, "%s: ends joined" % p.layout)
			assert_eq(bool(p.get("undone", false)), want == 0, "%s: the guard's verdict" % p.layout)
			if want == 0:
				# Never silent: an end the pond could not take is said.
				assert_true(WaterHints.worth_saying(p.hints), "%s: the end is said" % p.layout)
	assert_eq(seen.size(), JOINED.size(), "every layout with a join was built")


func test_the_same_drawing_joins_the_same_ends_wherever_and_whenever() -> void:
	# The probe of the card: f_through_pond joined 3 ends alone on a map and 0 after ten other
	# layouts, because the guard read the whole map's events. On and off the 0.25 m sample grid,
	# near the origin and far from it, and with the streams drawn in any order.
	for at: Vector2 in [Vector2.ZERO, Vector2(-17.0, 16.0), Vector2(0.1, 0.07), Vector2(10.13, -7.31)]:
		var built := _alone("f_through_pond", at)
		assert_eq(int(built.ponds[0].joined), 3, "three ends joined at %s" % at)
	for order: Array in [[2, 1, 0, 3], [1, 2, 0, 3]]:
		var built := _alone("f_through_pond", Vector2(3.0, -4.0), order)
		assert_eq(int(built.ponds[0].joined), 3, "three ends joined in order %s" % [order])


func test_a_stroke_keeps_its_length() -> void:
	for s: Dictionary in _built("flat").strokes:
		if s.layout == "f_self_cross":
			# The stroke crosses itself once; the loop is the author's, not a pointer curl.
			assert_gt(float(s.stored_m), 0.9 * float(s.drawn_m), "a self-crossing stroke is kept whole")
	var wide: Dictionary = _built("steps_wide").strokes[0]
	assert_false(bool(wide.blocked), "the widest stroke over the 2.5 m cliff is planned")
	assert_eq((wide.ids as PackedInt32Array).size(), 2, "as one fall: a reach each side of the lip")


func test_a_stroke_too_short_to_hold_water_is_refused_whole_and_carves_nothing() -> void:
	var refused := 0
	for s: Dictionary in _built("flat").strokes:
		if s.layout == "f_short" and s.get("refused", "") == "too_short":
			refused += 1
			assert_true(WaterHints.worth_saying(s.hints), "the refusal is said")
	assert_eq(refused, 1, "f_short's 0.9 m line is refused, its 2 m line lands")
	for depth: int in [Corpus.ANKLE, Corpus.WAIST, Corpus.DEEP]:
		var doc := NewMap.create(100, Corpus.BIOME, 1234)
		var start := doc.heights.duplicate()
		var hw := WaterBrush.radius_for(0.6, depth)
		var line := PackedVector2Array([Vector2(-0.45, 0.1), Vector2(0.0, 0.1), Vector2(0.45, 0.1)])
		var report := Corpus.add_stroke(doc, line, hw, depth as WaterBody.Depth)
		assert_eq(String(report.get("refused", "")), "too_short", "depth %d: refused" % depth)
		assert_true(doc.heights == start, "depth %d: no ground is carved" % depth)
		assert_eq(doc.water_bodies.size(), 0, "depth %d: no body is stored" % depth)
		# Off stores the stroke as drawn.
		WaterEdit.conditioning_enabled = false
		var off := Corpus.add_stroke(doc, line, hw, depth as WaterBody.Depth)
		WaterEdit.conditioning_enabled = true
		assert_false(off.has("refused"), "depth %d: conditioning off plans it as drawn" % depth)
