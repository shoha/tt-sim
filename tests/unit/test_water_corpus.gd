extends GutTest

## The water corpus's field-side checks (water_corpus_cases.gd; docs/systems/water.md "The water
## corpus"): every corpus map is built the way the Water tool builds it and its WaterField is read
## for what no render is needed to see. Hard rules: no NaN, the lateral coordinate inside the
## widest channel. Ratchets: the counts of discontinuities the corpus holds today (a stroke's
## flow or lateral coordinate jumping between neighbouring samples, deep water standing beside dry
## ground) may fall, never rise; lower a number here when a change removes some.

const Corpus := preload("res://tests/unit/water_corpus_cases.gd")

## Per map: [u_jumps, lat_jumps, perched] as of card painter-water-robust (2026-11-20).
const KNOWN := {
	"flat": [2, 8, 0],
	"flat2": [0, 0, 0],
	"tilt": [3, 4, 0],
	"steps": [0, 1, 12],
	"wood": [0, 0, 0],
}

var _was_enabled := true


func before_all() -> void:
	_was_enabled = WaterEdit.conditioning_enabled
	WaterEdit.conditioning_enabled = true


func after_all() -> void:
	WaterEdit.conditioning_enabled = _was_enabled


func test_layout_names_are_unique() -> void:
	var seen := {}
	for m in Corpus.maps():
		for l: Dictionary in m.layouts:
			assert_false(seen.has(l.name), "layout %s is listed once" % l.name)
			seen[l.name] = true
	assert_gt(seen.size(), 40, "the corpus holds its layouts")


func test_a_build_repeats() -> void:
	var m := Corpus.map_named("tilt")
	var a: MapDocument = Corpus.build(m).doc
	var b: MapDocument = Corpus.build(m).doc
	assert_eq(Corpus.digest(a), Corpus.digest(b), "two builds of one map are the same document")
	assert_gt(a.water_bodies.size(), 10, "the tilt map holds its water")


func test_field_of_every_map() -> void:
	for m in Corpus.maps():
		var built := Corpus.build(m)
		var doc: MapDocument = built.doc
		# A map of too many layouts reaches the document's body cap and its last strokes are
		# refused: every stroke of the corpus must land.
		for s: Dictionary in built.strokes:
			assert_false(s.has("refused"), "%s: a stroke of %s was refused" % [m.name, s.layout])
		var r := Corpus.field_report(doc)
		var known: Array = KNOWN[m.name]
		assert_gt(int(r.wet), 1000, "%s: the field holds water" % m.name)
		assert_eq(int(r.nan), 0, "%s: no NaN or infinite value in a wet sample" % m.name)
		assert_eq(int(r.lateral_out), 0, "%s: the lateral coordinate stays inside the channel" % m.name)
		assert_lte(int(r.u_jumps), int(known[0]), "%s: flow coordinate jumps inside a stroke" % m.name)
		assert_lte(int(r.lat_jumps), int(known[1]), "%s: lateral jumps inside a stroke" % m.name)
		assert_lte(int(r.perched), int(known[2]), "%s: deep water beside dry ground" % m.name)
