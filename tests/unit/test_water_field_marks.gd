extends GutTest

## The data the Painted shader's edge rules read from the water field (cards painter-water-mouths
## and painter-water-shoreline). The marks (WaterFieldMarks: the film and bank shares that replace
## the old enum): in range, deterministic, an update equal to a build, the mesh carrying them the
## same on both paths. And the one shoreline: `WaterField.shore` is the distance to the waterline
## of all the water together, so it has no shore across a mouth, a join or a crossing (the lap
## reads nothing else there), it never steps between neighbours, and it is the same after an
## update as after a build.

const FIXTURE := "res://tests/fixtures/water_field_canonical.ttmap"
const Corpus := preload("res://tests/unit/water_corpus_cases.gd")
## The widest the lap ribbon and its outer dashes reach from the waterline (m): the shader's
## p_foam_w * 1.6 + 0.14 at its default, with the wobble. A walk through a mouth must stay
## further than this from every shore.
const LAP_REACH_M := 0.6

var _docs := {}


func after_each() -> void:
	ScatterNative.force_gdscript_wfield = false


func _read() -> MapDocument:
	return MapDocumentIO.read(FIXTURE).get("document")


func _corpus_field(map: String) -> WaterField:
	if not _docs.has(map):
		_docs[map] = WaterField.build(Corpus.build(Corpus.map_named(map)).doc)
	return _docs[map]


## "" when the marks of `a` and `b` are the same arrays, else the first that differs.
func _marks_difference(a: WaterField, b: WaterField) -> String:
	for name: String in ["film", "bank"]:
		if a.marks.get(name) != b.marks.get(name):
			return name
	return ""


func _check_ranges(f: WaterField, label: String) -> Dictionary:
	var bad := 0
	var banks := 0
	var n := f.size.x * f.size.y
	for i in n:
		var film := f.marks.film[i]
		var bank := f.marks.bank[i]
		if is_nan(film) or is_nan(bank):
			bad += 1
		elif (film != 0.0 and film != 1.0) or bank < 0.0 or bank > 1.0:
			bad += 1
		if bank > 0.0:
			banks += 1
			if f.spill[i] != WaterField.SPILL_BANK:
				bad += 1
	assert_eq(bad, 0, "%s: every mark in range, a bank share only on a bank's spill" % label)
	return {"banks": banks}


## The lowest shore distance of `f` along the walk a -> b (map metres relative to the layout
## `name`'s centre), read at the nearest sample every eighth of a metre.
func _least_shore(f: WaterField, name: String, a: Vector2, b: Vector2) -> float:
	var at: Vector2 = Corpus.layout_named(name).at
	var least := INF
	var count := maxi(1, int(ceil(a.distance_to(b) / 0.125)))
	for k in count + 1:
		var i := f.index_of(at + a.lerp(b, float(k) / count))
		least = minf(least, f.shore[i] if i >= 0 else -INF)
	return least


func test_the_marks_are_in_range_and_deterministic() -> void:
	var doc := _read()
	var a := WaterField.build(doc)
	var b := WaterField.build(doc)
	assert_eq(_marks_difference(a, b), "", "two builds of one document hold the same marks")
	var counts := _check_ranges(a, "canonical")
	assert_gt(int(counts.banks), 100, "the canonical map has bank spill")
	_check_ranges(_corpus_field("flat"), "corpus flat")


func test_no_shore_crosses_a_mouth_a_join_or_a_crossing() -> void:
	# Each walk follows a stream's centre line through the place it meets other water. A shore
	# across the mouth (a pond's ring closed over it, a sill between two beds) would bring the
	# distance to 0 on the way; the lap ribbon reaches LAP_REACH_M from a shore.
	var walks := [
		["flat", "f_into_pond", Vector2(-5, 0), Vector2(2, 0), "a stream into a pond"],
		["flat", "f_cross", Vector2(-4, 0), Vector2(4, 0), "a crossing, the first stroke"],
		["flat", "f_cross", Vector2(0, -4), Vector2(0, 4), "a crossing, the second stroke"],
		["flat", "f_y_join", Vector2(-1, -1), Vector2(0, 2), "a tributary into a stream"],
		["flat", "f_through_far", Vector2(-6.5, -1.1), Vector2(-2.5, -0.1), "a stream through a pond"],
		["flat2", "f_two_inflows", Vector2(-3, -3), Vector2(1.5, -1.07), "one of two inflows"],
		["flat2", "f_pond_over_stream", Vector2(-5, 0), Vector2(4, 0), "a stream under a pond"],
		["flat2", "f_pond_over_stream", Vector2(-1, 0), Vector2(-1, 3), "from the stream into the pond"],
		["flat2", "f_pond_chain", Vector2(-4, -2.4), Vector2(4, 2.4), "a stream between two ponds"],
		["flat2", "f_out_of_pond", Vector2(-3, 0), Vector2(3, 0.5), "a stream out of a pond"],
		["steps", "s1_fall_pond", Vector2(-4, 0), Vector2(4, 0), "a fall into a pond"],
	]
	for w: Array in walks:
		var f := _corpus_field(w[0])
		var least := _least_shore(f, w[1], w[2], w[3])
		assert_gt(least, LAP_REACH_M, "%s (%s): no shore within the lap's reach" % [w[4], w[1]])


func test_the_shore_distance_is_continuous_in_range_and_deterministic() -> void:
	for map: String in ["flat", "steps"]:
		var f := _corpus_field(map)
		var far := WaterField.SHORE_FAR
		var bad := 0
		var jump := 0.0
		var near_jump := 0.0
		var n := f.size.x * f.size.y
		for i in n:
			var s := f.shore[i]
			if is_nan(s) or absf(s) > far + 1e-4:
				bad += 1
			# Neighbours both in the water: across a join, a body's border and a pond's rim alike.
			if s <= 0.0:
				continue
			for j: int in [i + 1 if i % f.size.x != f.size.x - 1 else -1, i + f.size.x]:
				if j < 0 or j >= n or f.shore[j] <= 0.0:
					continue
				var d := absf(s - f.shore[j])
				jump = maxf(jump, d)
				if maxf(s, f.shore[j]) < WaterField.EXACT_M:
					near_jump = maxf(near_jump, d)
		assert_eq(bad, 0, "%s: the shore distance within its clamp everywhere" % map)
		# A true distance changes by at most a sample's step between neighbours. The pass measures
		# each sample to the crossing (and the contour piece) of its NEAREST BOUNDARY SAMPLE only,
		# and where two boundary samples tie it can take the one whose crossing lies further: the
		# distance then reads up to 0.18 m long on the second row from a bank (measured 2026-11-20:
		# steps of 0.33 m on corpus "flat" and 0.43 m on "steps" between neighbours 0.25 m apart,
		# 71 and 23 pairs, at notches of the bank). Two steps is what holds today; one step is the
		# target once the pass compares the crossings of every boundary sample round the nearest
		# (a native change: docs/systems/water_field.md "Marks and the one shoreline").
		assert_lt(near_jump, f.step.x * 2.0, "%s: two steps at most in the exact range" % map)
		assert_lt(jump, f.step.x * 2.0, "%s: it never jumps between wet neighbours" % map)
	var doc := _read()
	assert_eq(WaterField.build(doc).shore, WaterField.build(doc).shore, "two builds, one shore")


func test_an_update_equals_a_build() -> void:
	var step := _read().sample_step()
	for centre: Vector2 in [Vector2(9.0, -2.0), Vector2(-21.0, 12.0)]:
		var doc := _read()
		var field := WaterField.build(doc)
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
		var fresh := WaterField.build(doc)
		assert_eq(_marks_difference(field, fresh), "", "ground edit at %s" % centre)
		assert_eq(field.shore, fresh.shore, "the shore after a ground edit at %s" % centre)
	var doc := _read()
	var field := WaterField.build(doc)
	var before: Array[WaterBody] = [doc.water_bodies[2], doc.water_bodies[28]]
	var rect := WaterField.rect_of_bodies(doc, before)
	doc.water_bodies[2].level_m += 0.4
	doc.water_bodies[28].level_m -= 0.3
	field.update(doc, rect.merge(WaterField.rect_of_bodies(doc, before)))
	assert_eq(_marks_difference(field, WaterField.build(doc)), "", "level changes")
	# Every stroke in turn removed: the shore closes where its mouths were.
	var chains := RiverProfile.strokes(_read().water_bodies)
	for k in chains.size():
		doc = _read()
		field = WaterField.build(doc)
		var gone: Array[WaterBody] = []
		gone.assign(RiverProfile.strokes(doc.water_bodies)[k])
		rect = WaterField.rect_of_bodies(doc, gone)
		for body in gone:
			doc.water_bodies.erase(body)
		field.update(doc, rect)
		var fresh := WaterField.build(doc)
		assert_eq(_marks_difference(field, fresh), "", "stroke %d removed" % k)
		assert_eq(field.shore, fresh.shore, "the shore with stroke %d removed" % k)


func test_the_mesh_carries_the_marks_on_both_paths() -> void:
	var field := WaterField.build(_read())
	ScatterNative.force_gdscript_wfield = true
	var gd := WaterFieldMesh.build(field)
	ScatterNative.force_gdscript_wfield = false
	var c2: PackedFloat32Array = gd.arrays[Mesh.ARRAY_CUSTOM2]
	assert_eq(c2.size(), int(gd.vertices) * 4, "four floats per vertex")
	var uvs: PackedVector2Array = gd.arrays[Mesh.ARRAY_TEX_UV]
	var wrong := 0
	for v in int(gd.vertices):
		var x := roundi(uvs[v].x * (field.size.x - 1))
		var z := roundi(uvs[v].y * (field.size.y - 1))
		var s := z * field.size.x + x
		if c2[v * 4 + 1] != field.marks.film[s] or c2[v * 4 + 2] != field.marks.bank[s]:
			wrong += 1
	assert_eq(wrong, 0, "CUSTOM2 holds each vertex's film and bank share")
	if ScatterNative.wfield_instance() == null:
		pass_test("the native library is not built: the GDScript path only")
		return
	var native := WaterFieldMesh.build(field)
	assert_eq(native.arrays[Mesh.ARRAY_CUSTOM2], c2, "the native mesh's CUSTOM2 equals the twin's")
	assert_eq(native.arrays[Mesh.ARRAY_CUSTOM0], gd.arrays[Mesh.ARRAY_CUSTOM0], "CUSTOM0 unchanged")
