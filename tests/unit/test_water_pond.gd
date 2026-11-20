extends GutTest

## The pond conditioner (card painter-water-pond; WaterPondFit through WaterEditor.compute()): a
## pond dug after the streams beside it keeps its outline and never rises, a stream end within
## reach of it that can meet it at a riffle is joined by a short connector reach, what cannot be
## joined is said and left as drawn, the result is deterministic, and over random maps conditioning
## on does not raise the field's events over conditioning off.

const Cases := preload("res://tests/unit/water_condition_cases.gd")
const PondCases := preload("res://tests/unit/water_pond_cases.gd")
const Fit := preload("res://utils/water_pond_fit.gd")


func _kinds(hints: Array) -> Array:
	var out := []
	for hint: Dictionary in hints:
		out.append(hint.kind)
	return out


func _signature(doc: MapDocument) -> Array:
	var out := []
	for body in doc.water_bodies:
		out.append([body.id, body.level_m, body.points, body.half_widths])
	return out


func test_the_pond_outline_never_moves_and_its_level_never_rises() -> void:
	for name in PondCases.NAMES:
		var off := PondCases.make(name, false)
		var on := PondCases.make(name, true)
		assert_eq(on.doc.pond_mask, off.doc.pond_mask, "%s: the outline is as painted" % name)
		var pond: WaterBody = on.doc.water_body(on.id)
		assert_true(pond.level_m <= on.rim_level + 1e-6, "%s: the pond never rises" % name)
		assert_true(
			pond.level_m >= on.rim_level - Fit.LEVEL_BAND_M - 1e-6, "%s: and sinks at most the band" % name
		)
		assert_false(off.out.has("joined"), "%s: off is the pond as dug" % name)


func test_two_inflows_and_an_outlet_are_all_joined_by_short_connectors() -> void:
	var off := PondCases.make("two_in_one_out", false)
	var on := PondCases.make("two_in_one_out", true)
	assert_eq(int(on.out.joined), 3, "two tails and a head reach the pond")
	assert_eq(on.doc.water_bodies.size(), off.doc.water_bodies.size() + 3, "one connector each")
	var longest := 0.0
	for body in on.doc.water_bodies:
		if body.is_river() and body.id > off.doc.water_bodies.size() + 1:
			longest = maxf(longest, Cases.course_length(body))
	assert_true(longest > 0.0 and longest <= 3.2, "a connector is a snap long (%.2f m)" % longest)
	var audit := WaterPorts.audit(on.doc)
	assert_eq(audit.rises, 0, "no connector climbs")
	assert_true(Fit.event_counts(on.doc).values().all(func(n: int) -> bool: return n == 0))


func test_a_river_stopping_at_a_square_corner_is_joined() -> void:
	var off := PondCases.make("corner", false)
	var on := PondCases.make("corner", true)
	assert_eq(Fit.event_counts(off.doc)[&"end_near_water"], 1, "off leaves the end short of the pond")
	assert_eq(Fit.event_counts(on.doc)[&"end_near_water"], 0, "on joins it")
	assert_eq(int(on.out.joined), 1)


func test_a_head_above_the_pond_and_a_far_end_are_said_not_changed() -> void:
	var perched := PondCases.make("perched_head", true)
	assert_true(_kinds(perched.out.hints).has(&"perched_head"), "a head above the pond is said")
	assert_eq(_signature(perched.doc), _signature(PondCases.make("perched_head", false).doc))
	var short := PondCases.make("end_short", true)
	assert_true(_kinds(short.out.hints).has(&"end_near_water_below"), "a tail a fall above it is said")
	assert_eq(_signature(short.doc), _signature(PondCases.make("end_short", false).doc))
	assert_eq(int(short.out.joined), 0)


func test_a_pond_sinks_to_meet_a_stream_end_below_it() -> void:
	var off := PondCases.make("end_below", false)
	var pond: WaterBody = off.doc.water_body(off.id)
	var report := {}
	var level := Fit.fit_level(off.doc, pond, report)
	assert_true(level <= pond.level_m and level >= pond.level_m - Fit.LEVEL_BAND_M)
	assert_almost_eq(float(report.level_moved), pond.level_m - level, 1e-6)
	assert_eq(Fit.fit_level(off.doc, pond, {}), level, "asking again gives the same level")


func test_the_result_is_deterministic_and_idempotent() -> void:
	var a := PondCases.make("two_in_one_out", true)
	var b := PondCases.make("two_in_one_out", true)
	assert_eq(_signature(a.doc), _signature(b.doc))
	assert_true(a.doc.heights == b.doc.heights, "the carve too")
	var pond: WaterBody = a.doc.water_body(a.id)
	var again: Dictionary = Fit.join_ends(a.doc, pond)
	assert_eq(int(again.joined), 0, "a joined end has nothing left to decide")


func test_random_maps_never_get_more_events_with_conditioning_on() -> void:
	var off_total := 0
	var on_total := 0
	var worse := 0
	var joins := 0
	for seed_value in range(5, 13):
		var off := Cases.metrics(PondCases.fuzz_map(seed_value, false).doc)
		var r := PondCases.fuzz_map(seed_value, true)
		var on := Cases.metrics(r.doc)
		var off_events: int = off.film_run + off.bridged_run + off.end_near
		var on_events: int = on.film_run + on.bridged_run + on.end_near
		off_total += off_events
		on_total += on_events
		worse += 1 if on_events > off_events else 0
		for pond: Dictionary in r.ponds:
			joins += int(pond.out.get("joined", 0))
			assert_true(float(pond.out.get("level_moved", 0.0)) <= Fit.LEVEL_BAND_M + 1e-6)
		assert_eq(on.rises, 0, "seed %d: no stream climbs" % seed_value)
	assert_true(joins > 0, "the fuzz exercises the joins")
	assert_true(on_total <= off_total, "events %d off, %d on" % [off_total, on_total])
	assert_true(worse <= 1, "%d of 8 maps worse (seed 10 gains a bridged run)" % worse)
