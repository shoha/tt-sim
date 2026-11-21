extends GutTest

## The continuous marks of the water field (WaterFieldMarks; card painter-water-mouths): the film
## and bank shares and the mouth distance the Painted shader reads per vertex in place of the old
## enum. In range, deterministic, the mouth distance continuous (1-Lipschitz) across stroke joins,
## crossings and body borders, a mouth found where a stream meets a pond or another stream and
## nowhere else, an update equal to a build, and the mesh carrying them the same on both paths.

const FIXTURE := "res://tests/fixtures/water_field_canonical.ttmap"
const Corpus := preload("res://tests/unit/water_corpus_cases.gd")

var _flat: MapDocument


func after_each() -> void:
	ScatterNative.force_gdscript_wfield = false


func _read() -> MapDocument:
	return MapDocumentIO.read(FIXTURE).get("document")


func _flat_doc() -> MapDocument:
	if _flat == null:
		_flat = Corpus.build(Corpus.map_named("flat")).doc
	return _flat


## The lowest mouth distance of `f` over the samples within `reach` metres of map point `p`.
func _nearest_mouth(f: WaterField, p: Vector2, reach: float) -> float:
	var best := INF
	var steps := int(ceil(reach / f.step.x))
	var centre := Vector2i(((p - f.origin) / f.step).round())
	for dz in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var x := centre.x + dx
			var z := centre.y + dz
			if x >= 0 and z >= 0 and x < f.size.x and z < f.size.y:
				best = minf(best, f.marks.mouth[z * f.size.x + x])
	return best


## "" when the marks of `a` and `b` are the same arrays, else the first that differs.
func _marks_difference(a: WaterField, b: WaterField) -> String:
	for name: String in ["film", "bank", "mouth", "chan"]:
		if a.marks.get(name) != b.marks.get(name):
			return name
	return ""


func _check_ranges(f: WaterField, label: String) -> Dictionary:
	var far := WaterFieldMarks.MOUTH_FAR
	var bad := 0
	var near := 0
	var banks := 0
	var jump := 0.0
	var n := f.size.x * f.size.y
	for i in n:
		var film := f.marks.film[i]
		var bank := f.marks.bank[i]
		var mouth := f.marks.mouth[i]
		if is_nan(film) or is_nan(bank) or is_nan(mouth):
			bad += 1
		elif (film != 0.0 and film != 1.0) or bank < 0.0 or bank > 1.0 or mouth < 0.0 or mouth > far:
			bad += 1
		if bank > 0.0:
			banks += 1
			if f.spill[i] != WaterField.SPILL_BANK:
				bad += 1
		if mouth < far:
			near += 1
		if i % f.size.x != f.size.x - 1:
			jump = maxf(jump, absf(mouth - f.marks.mouth[i + 1]))
		if i + f.size.x < n:
			jump = maxf(jump, absf(mouth - f.marks.mouth[i + f.size.x]))
	assert_eq(bad, 0, "%s: every mark in range, a bank share only on a bank's spill" % label)
	assert_lt(jump, f.step.x + 1e-4, "%s: the mouth distance never steps more than a sample" % label)
	return {"near": near, "banks": banks}


func test_the_marks_are_in_range_continuous_and_deterministic() -> void:
	var doc := _read()
	var a := WaterField.build(doc)
	var b := WaterField.build(doc)
	assert_eq(_marks_difference(a, b), "", "two builds of one document hold the same marks")
	var counts := _check_ranges(a, "canonical")
	assert_gt(int(counts.near), 100, "the canonical map has mouths")
	assert_gt(int(counts.banks), 100, "and bank spill")
	var flat := WaterField.build(_flat_doc())
	_check_ranges(flat, "corpus flat")


func test_a_mouth_is_where_water_meets_water_and_nowhere_else() -> void:
	var f := WaterField.build(_flat_doc())
	var far := WaterFieldMarks.MOUTH_FAR
	# f_into_pond (36, 12): a stream from the west into a pond centred 3 m east of the cell.
	assert_lt(_nearest_mouth(f, Vector2(35.5, 12.0), 2.0), 0.3, "a stream's mouth in a pond")
	# f_cross (-36, 12): two strokes crossing at the cell's centre.
	assert_lt(_nearest_mouth(f, Vector2(-36.0, 12.0), 2.5), 0.3, "a crossing")
	# f_y_join (-12, -12): a tributary ending in a stream.
	assert_lt(_nearest_mouth(f, Vector2(-12.0, -10.4), 2.5), 0.3, "a tributary's join")
	# f_pond_only (12, 12) and the middle of f_meander (-12, -36): one body, no mouth.
	assert_eq(_nearest_mouth(f, Vector2(12.0, 12.0), 5.0), far, "a pond alone has none")
	assert_eq(_nearest_mouth(f, Vector2(-12.0, -36.0), 1.5), far, "nor a stream's middle")


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
		assert_eq(
			_marks_difference(field, WaterField.build(doc)), "", "ground edit at %s" % centre
		)
	var doc := _read()
	var field := WaterField.build(doc)
	var before: Array[WaterBody] = [doc.water_bodies[2], doc.water_bodies[28]]
	var rect := WaterField.rect_of_bodies(doc, before)
	doc.water_bodies[2].level_m += 0.4
	doc.water_bodies[28].level_m -= 0.3
	field.update(doc, rect.merge(WaterField.rect_of_bodies(doc, before)))
	assert_eq(_marks_difference(field, WaterField.build(doc)), "", "level changes")
	# Every stroke in turn removed: its mouths go, its neighbours' corners are found again.
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
		assert_eq(_marks_difference(field, WaterField.build(doc)), "", "stroke %d removed" % k)


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
		elif c2[v * 4 + 3] != field.marks.mouth[s]:
			wrong += 1
	assert_eq(wrong, 0, "CUSTOM2 holds each vertex's film, bank and mouth")
	if ScatterNative.wfield_instance() == null:
		pass_test("the native library is not built: the GDScript path only")
		return
	var native := WaterFieldMesh.build(field)
	assert_eq(native.arrays[Mesh.ARRAY_CUSTOM2], c2, "the native mesh's CUSTOM2 equals the twin's")
	assert_eq(native.arrays[Mesh.ARRAY_CUSTOM0], gd.arrays[Mesh.ARRAY_CUSTOM0], "CUSTOM0 unchanged")
