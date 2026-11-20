extends GutTest

## The water field (card painter-water-field-model; WaterField, WaterFieldStroke): the per-sample
## water surface derived from a document, in rules mode, nothing drawing from it yet. Run on the
## spike's canonical 61 m map (tests/fixtures/water_field_canonical.ttmap: terraced falls on
## several streams, two ponds, 31 bodies, rebuilt by the spike's build job on main's code).
##
## Pinned here: transect goldens (w, depth and energy along the lines of the falls f1, f2, f5 and
## the stream st, tests/fixtures/water_field_transects.json: regenerate with `regenerate_goldens`
## below only for a deliberate change), a determinism test, build and update time bounds (generous:
## the measured full build is about 0.2 s and a whole-stroke update 20 to 80 ms headless), the
## dirty-rect rebuild equal to a full rebuild bit for bit after several kinds of edit, and the
## events a map validation reads (the canonical map's stream head f4 and the film st_o).

const FIXTURE := "res://tests/fixtures/water_field_canonical.ttmap"
const GOLDENS := "res://tests/fixtures/water_field_transects.json"
## The canonical map's falls and stream, as lines (XZ from, to) down their courses.
const TRANSECTS := {
	"f1": [Vector2(-8.0, -13.5), Vector2(-8.0, 0.0)],
	"f2": [Vector2(9.0, -13.5), Vector2(9.0, -1.0)],
	"f5": [Vector2(-21.5, -6.0), Vector2(-11.5, -0.5)],
	"st": [Vector2(23.0, -25.0), Vector2(23.0, -2.0)],
}
const GOLDEN_TOLERANCE := 0.002
const FULL_BUDGET_MS := 3000.0
const UPDATE_BUDGET_MS := 1500.0
const _ARRAYS := [
	"ground", "w", "depth", "energy", "steep", "shore", "river", "spill", "calm", "owner", "foot"
]

var _doc: MapDocument = null
var _full: WaterField = null


func before_all() -> void:
	_doc = _read()
	_full = WaterField.build(_doc)


func _read() -> MapDocument:
	return MapDocumentIO.read(FIXTURE).get("document")


## The array names of two fields that differ, "" when they are bit-identical (events included).
func _difference(a: WaterField, b: WaterField) -> String:
	for name: String in _ARRAYS:
		if a.get(name) != b.get(name):
			return name
	if a.events != b.events:
		return "events"
	return ""


## w, depth and energy at every 0.25 m along the line from `from` to `to`, dry as -999.
static func transect(f: WaterField, from: Vector2, to: Vector2) -> Dictionary:
	var out := {"w": [], "depth": [], "energy": []}
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var t := 0.0
	while t <= length:
		var i := f.index_of(from + dir * t)
		var wet := i >= 0 and f.w[i] != WaterGeometry.DRY
		out.w.append(snappedf(f.w[i], 0.001) if wet else -999.0)
		out.depth.append(snappedf(f.depth[i], 0.001) if wet else -999.0)
		out.energy.append(snappedf(f.energy[i], 0.001) if i >= 0 else 0.0)
		t += 0.25
	return out


## Rewrites the goldens file from the field of the fixture. Not a test: call it from a probe.
static func regenerate_goldens() -> void:
	var doc: MapDocument = MapDocumentIO.read(FIXTURE).get("document")
	var f := WaterField.build(doc)
	var lines := {}
	for key: String in TRANSECTS:
		var ends: Array = TRANSECTS[key]
		lines[key] = transect(f, ends[0], ends[1])
	var file := FileAccess.open(GOLDENS, FileAccess.WRITE)
	file.store_string(JSON.stringify(lines, "\t"))


func test_build_is_deterministic() -> void:
	var again := WaterField.build(_read())
	assert_eq(_difference(_full, again), "", "the same document builds the same field")


func test_transects_match_goldens() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDENS))
	assert_true(parsed is Dictionary, "goldens parse")
	for key: String in TRANSECTS:
		var ends: Array = TRANSECTS[key]
		var now := transect(_full, ends[0], ends[1])
		var want: Dictionary = parsed[key]
		for channel: String in ["w", "depth", "energy"]:
			var a: Array = now[channel]
			var b: Array = want[channel]
			assert_eq(a.size(), b.size(), "%s %s sample count" % [key, channel])
			var worst := 0.0
			var at := -1
			for k in mini(a.size(), b.size()):
				var d := absf(float(a[k]) - float(b[k]))
				if d > worst:
					worst = d
					at = k
			assert_lt(worst, GOLDEN_TOLERANCE, "%s %s worst at sample %d" % [key, channel, at])


func test_fields_are_consistent() -> void:
	var wet := 0
	var spilled := 0
	var buried := 0
	for i in _full.w.size():
		var d := _full.depth[i]
		if d > 0.0:
			wet += 1
			assert_gt(_full.shore[i], -0.0001, "wet sample %d has a positive shore" % i)
		else:
			assert_lt(_full.shore[i], 0.0001, "dry or buried sample %d has no positive shore" % i)
			if _full.w[i] != WaterGeometry.DRY:
				buried += 1
		assert_true(absf(_full.shore[i]) <= WaterField.SHORE_FAR + 0.0001, "shore is clamped")
		assert_true(_full.energy[i] >= 0.0 and _full.energy[i] <= 1.0, "energy is a share")
		assert_true(_full.steep[i] >= 0.0 and _full.steep[i] <= 1.0, "steep is a share")
		if _full.spill[i] != 0:
			spilled += 1
	assert_gt(wet, 4000, "the map's water is wet in the field")
	assert_gt(buried, 0, "the water ends in buried rings")
	assert_gt(spilled, 0, "a river's unheld water spills")


func test_buried_rings_stay_under_the_ground() -> void:
	for i in _full.w.size():
		if _full.w[i] != WaterGeometry.DRY and _full.depth[i] <= 0.0:
			assert_lt(_full.w[i], _full.ground[i], "a buried sample is under its ground")


func test_a_fall_is_one_steep_surface() -> void:
	# The f1 fall: along its line the level drops by the profile's step and a run of samples is
	# steep and white, with no dry gap between the reaches.
	var line := transect(_full, TRANSECTS.f1[0], TRANSECTS.f1[1])
	var top := -INF
	var bottom := INF
	var gaps := 0
	var seen_wet := false
	for k in line.w.size():
		var level := float(line.w[k])
		if level == -999.0:
			if seen_wet:
				gaps += 1
			continue
		seen_wet = true
		top = maxf(top, level)
		bottom = minf(bottom, level)
	assert_gt(top - bottom, 1.0, "f1 drops over a metre")
	assert_eq(gaps, 0, "the water along f1 is one unbroken surface")


func test_the_foot_coordinate_runs_through_the_fall() -> void:
	# Foot spike: along the f1 line the signed arc distance to the fall's foot only grows (face
	# negative, plunge pool positive) and crosses zero once; no sample is written far from a fall.
	var from: Vector2 = TRANSECTS.f1[0]
	var to: Vector2 = TRANSECTS.f1[1]
	var dir := (to - from).normalized()
	var last := -INF
	var neg := 0
	var pos := 0
	var t := 0.0
	while t <= from.distance_to(to):
		var i := _full.index_of(from + dir * t)
		var ft := _full.foot[i]
		if ft < WaterFieldStroke.NO_FOOT * 0.5:
			assert_gte(ft, last - 0.3, "the foot coordinate does not run back along the fall")
			last = maxf(last, ft)
			if ft < -0.2:
				neg += 1
			elif ft > 0.2:
				pos += 1
		t += 0.25
	assert_gt(neg, 2, "the face lies before the foot")
	assert_gt(pos, 2, "the plunge pool lies after it")


func test_full_build_time_is_bounded() -> void:
	var t0 := Time.get_ticks_usec()
	var f := WaterField.build(_read())
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	gut.p("full build %.0f ms (%s)" % [ms, str(f.timings)])
	assert_lt(ms, FULL_BUDGET_MS, "a full build stays under the generous bound")


## `doc` edited by `edit.call(doc)`, a field built before the edit updated over `rect_of.call` and
## a field built after: the three must agree.
func _check_edit(label: String, edit: Callable, bodies: Array[int]) -> void:
	var doc := _read()
	var field := WaterField.build(doc)
	var before: Array[WaterBody] = []
	for body in doc.water_bodies:
		if bodies.has(body.id):
			before.append(body)
	var rect := WaterField.rect_of_bodies(doc, before)
	edit.call(doc)
	rect = rect.merge(WaterField.rect_of_bodies(doc, before))
	var t0 := Time.get_ticks_usec()
	var changed := field.update(doc, rect)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_true(changed.has_area(), "%s: the update reports a changed rect" % label)
	assert_lt(ms, UPDATE_BUDGET_MS, "%s: the update stays under the generous bound" % label)
	gut.p("%s: update %.1f ms of rect %s (%s)" % [label, ms, str(rect), str(field.timings)])
	assert_eq(_difference(field, WaterField.build(doc)), "", "%s: update equals a full build" % label)


func _remove_st(doc: MapDocument) -> void:
	var keep: Array[WaterBody] = []
	for body in doc.water_bodies:
		if body.id < 11 or body.id > 26:
			keep.append(body)
	doc.water_bodies = keep


func _remove_deep_pond(doc: MapDocument) -> void:
	var gone := doc.water_bodies[28]
	doc.water_bodies.remove_at(28)
	for i in doc.pond_mask.size():
		if doc.pond_mask[i] == gone.id:
			doc.pond_mask[i] = 0


func _remove_first(doc: MapDocument) -> void:
	doc.water_bodies.remove_at(0)


func test_update_after_removing_a_stroke() -> void:
	_check_edit("remove a reach of f1", _remove_first, [1])
	_check_edit("remove the st stroke", _remove_st, [11])


func test_update_after_a_level_change() -> void:
	_check_edit(
		"raise a fall reach",
		func(doc: MapDocument) -> void: doc.water_bodies[2].level_m += 0.4,
		[3]
	)
	_check_edit(
		"lower a pond",
		func(doc: MapDocument) -> void: doc.water_bodies[28].level_m -= 0.3,
		[29]
	)


func test_update_after_removing_a_pond() -> void:
	_check_edit("remove the deep pond", _remove_deep_pond, [29])


func test_update_after_a_ground_edit() -> void:
	# Raise a disc of ground over the f2 plunge pool and beside the st film: no body changes, the
	# caller's rect is the disc grown by the field's reach.
	for centre: Vector2 in [Vector2(9.0, -9.0), Vector2(23.0, -14.0), Vector2(-21.0, 12.0)]:
		var doc := _read()
		var field := WaterField.build(doc)
		var step := doc.sample_step()
		var origin := -doc.extent_m() * 0.5
		var low := Vector2i(((centre - Vector2(2.5, 2.5) - origin) / step).floor())
		var high := Vector2i(((centre + Vector2(2.5, 2.5) - origin) / step).ceil())
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var d := (origin + Vector2(x, z) * step).distance_to(centre)
				if d < 2.5:
					doc.heights[z * doc.samples_x() + x] += 0.5 * (1.0 - d / 2.5)
		var rect := Rect2i(low, high - low + Vector2i.ONE).grow(int(WaterField.INFLUENCE_M / step.x))
		field.update(doc, rect)
		assert_eq(
			_difference(field, WaterField.build(doc)), "", "ground edit at %s equals a full build" % centre
		)


func test_an_empty_update_changes_nothing() -> void:
	var f := WaterField.build(_read())
	var out := f.update(_read(), Rect2i())
	assert_false(out.has_area(), "an empty dirty rect does nothing")
	assert_eq(_difference(f, _full), "", "and the field stays as it was")


func test_rect_of_bodies_covers_the_stroke() -> void:
	var one: Array[WaterBody] = [_doc.water_bodies[0]]
	var rect := WaterField.rect_of_bodies(_doc, one)
	var f := _full
	var inside := f.index_of(_doc.water_bodies[0].points[0])
	assert_true(rect.has_point(Vector2i(inside % f.size.x, inside / f.size.x)), "the first point")
	assert_true(Rect2i(Vector2i.ZERO, f.size).encloses(rect), "clipped to the grid")
	var none: Array[WaterBody] = []
	assert_false(WaterField.rect_of_bodies(_doc, none).has_area(), "no bodies, no rect")


func test_events_flag_the_maps_inconsistencies() -> void:
	var films := 0
	var heads := 0
	var bridged := 0
	for e in _full.events:
		match e.kind:
			&"film_run":
				films += 1
				assert_eq(e.body, 11, "the films are the st stroke's (st_o)")
				assert_gt(e.length, 2.0, "a film is longer than the bridge")
			&"end_near_water":
				heads += 1
				assert_eq(e.body, 7, "the stream head is the f4 stroke's")
				assert_eq(e.other_body, 29, "it stops short of the deep pond")
				assert_lt(e.level_gap, -3.0, "which lies about 3.9 m below")
			&"bridged_run":
				bridged += 1
				assert_lt(e.length, WaterFieldStroke.BRIDGE_M + 0.01, "a bridged run is short")
	assert_eq(films, 3, "three film runs on st")
	assert_eq(heads, 1, "one stream head near a pond at another level (f4)")
	assert_gt(bridged, 0, "short dips are reported as information")


func test_runs_bridge_only_short_runs_between_held_stations() -> void:
	var lost := PackedByteArray([0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1])
	var found := WaterFieldStroke.runs(lost)
	assert_eq(found.size(), 3, "three runs")
	assert_eq(found[0], Vector3i(1, 3, 1), "a short dip between held stations is bridged")
	assert_eq(found[1], Vector3i(5, 14, 0), "a run longer than the bridge is a film")
	assert_eq(found[2], Vector3i(15, 17, 0), "a run to the stroke's end is a film")
	var kept := WaterFieldStroke.without_bridged(lost, found)
	assert_eq(kept[1], 0, "the bridged dip is cleared")
	assert_eq(kept[6], 1, "the film stays")


func test_debug_image_is_the_grid_sized() -> void:
	var img := _full.debug_image()
	assert_eq(Vector2i(img.get_width(), img.get_height()), _full.size, "one pixel per sample")
