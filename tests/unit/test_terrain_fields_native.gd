extends GutTest

## The native rule fields (ScatterNative.rule_fields, native/src/terrain_fields.cpp; card
## terrainrules) against TerrainRules.sample_fields_gdscript, bit for bit: random height grids
## (smooth hills, sculpt-like bumps, one-sample cliffs and flat ground) at the sample steps of
## every map size, random rectangles inside, across and past the grid, the whole grid, and what
## a stroke end asks for (the edit grown by the curvature radius). Pending without the library;
## its absence is the GDScript path every other test checks.

const RECTS_PER_GRID := 40


func after_each() -> void:
	ScatterNative.force_gdscript = false
	ScatterNative.force_gdscript_fields = false


func _skip_without_library() -> bool:
	if ScatterNative.available():
		return false
	pending("the native library is not built (AGENTS.md Testing): GDScript path only")
	return true


## A row-major grid of `columns` x `rows` heights in one of four shapes.
func _grid(columns: int, rows: int, kind: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(columns * rows)
	var bumps: Array[Vector4] = []
	for _i in 12:
		bumps.append(
			Vector4(
				rng.randf_range(0, columns),
				rng.randf_range(0, rows),
				rng.randf_range(2.0, 14.0),
				rng.randf_range(-2.5, 3.0)
			)
		)
	for z in rows:
		for x in columns:
			var h := 0.0
			match kind:
				0:
					h = sin(x * 0.11) * 1.7 + cos(z * 0.07) * 0.9 + sin((x + z) * 0.23) * 0.3
				1:
					for b in bumps:
						var d := Vector2(x - b.x, z - b.y).length() / b.z
						h += b.w * exp(-d * d)
				2:
					# Tiers: 1.524 m steps with one-sample faces, the cliff rule's worst case.
					h = floorf((x + z * 0.5) / 9.0) * 1.524 + rng.randf_range(-0.01, 0.01)
				_:
					h = 0.25
			heights[z * columns + x] = h
	return heights


func _same(a: PackedFloat32Array, b: PackedFloat32Array) -> int:
	var off := 0
	for i in a.size():
		if a[i] != b[i]:
			off += 1
	return off


func _check_rect(
	heights: PackedFloat32Array, columns: int, rows: int, step: Vector2, rect: Rect2i, label: String
) -> void:
	var native := ScatterNative.rule_fields(
		heights,
		columns,
		rows,
		step,
		rect,
		TerrainRules.radius_samples(minf(step.x, step.y)),
		TerrainRules.cliff_start_cos(),
		TerrainRules.cliff_end_cos()
	)
	var reference := TerrainRules.sample_fields_gdscript(heights, columns, rows, step, rect)
	assert_false(native.is_empty(), "%s: the library answered" % label)
	if native.is_empty():
		return
	assert_eq(native.rect, reference.rect, "%s: the clipped rect" % label)
	var nc: PackedFloat32Array = native.curvature
	var ns: PackedFloat32Array = native.steep
	var rc: PackedFloat32Array = reference.curvature
	var rs: PackedFloat32Array = reference.steep
	assert_eq(nc.size(), rc.size(), "%s: curvature size" % label)
	assert_eq(ns.size(), rs.size(), "%s: steep size" % label)
	if nc.size() == rc.size() and ns.size() == rs.size():
		assert_eq(_same(nc, rc), 0, "%s: curvature samples that differ" % label)
		assert_eq(_same(ns, rs), 0, "%s: steepness samples that differ" % label)


func test_native_fields_equal_gdscript_on_random_grids_and_rects() -> void:
	if _skip_without_library():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261108
	# The sample steps of 100, 200 and 320 ft maps (0.25 m at every size since the grid grows),
	# an uneven one, and a coarse one whose curvature radius is a single sample.
	var cases := [
		[123, 123, Vector2(0.2479675, 0.2479675)],
		[245, 245, Vector2(0.2498361, 0.2498361)],
		[391, 391, Vector2(0.2494118, 0.2494118)],
		[131, 71, Vector2(0.2512, 0.2381)],
		[40, 56, Vector2(1.6, 1.9)],
	]
	for c: Array in cases:
		var columns: int = c[0]
		var rows: int = c[1]
		var step: Vector2 = c[2]
		for kind in 4:
			var heights := _grid(columns, rows, kind, rng)
			var label := "%dx%d kind %d" % [columns, rows, kind]
			_check_rect(heights, columns, rows, step, Rect2i(0, 0, columns, rows), label + " whole")
			for i in RECTS_PER_GRID:
				var at := Vector2i(rng.randi_range(-20, columns + 5), rng.randi_range(-20, rows + 5))
				var size := Vector2i(rng.randi_range(1, 90), rng.randi_range(1, 60))
				_check_rect(heights, columns, rows, step, Rect2i(at, size), "%s rect %d" % [label, i])


func test_a_stroke_end_matches_and_empty_rects_answer_like_gdscript() -> void:
	if _skip_without_library():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "fields", 7)
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var half := doc.extent_m() * 0.5
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE, 1.5)
	var dirty := Rect2i()
	var at := Vector2(-6.0, 1.0)
	for _d in 8:
		var next := (at + Vector2(rng.randf_range(0, 3), rng.randf_range(-1, 1))).clamp(-half, half)
		stroke.dab(at, next, 4.0, 0.3)
		dirty = MaskBrush.merge_rect(dirty, stroke.take_pending())
		at = next
	var step := doc.sample_step()
	var reach := TerrainRules.radius_samples(minf(step.x, step.y)) + 1
	var heights := TerrainMeshBuilder.collision_heights(doc)
	_check_rect(heights, columns, rows, step, dirty.grow(reach), "stroke end")
	for rect in [Rect2i(), Rect2i(columns + 3, 2, 5, 5), Rect2i(-9, -9, 4, 4)]:
		var native := ScatterNative.rule_fields(
			heights,
			columns,
			rows,
			step,
			rect,
			6,
			TerrainRules.cliff_start_cos(),
			TerrainRules.cliff_end_cos()
		)
		var reference := TerrainRules.sample_fields_gdscript(heights, columns, rows, step, rect)
		assert_eq(native.rect, reference.rect, "%s: the clipped rect" % rect)
		assert_eq(native.curvature.size(), 0, "%s: no samples" % rect)
		assert_eq(reference.curvature.size(), 0, "%s: no samples (GDScript)" % rect)


func test_sample_fields_takes_the_library_and_the_switches_send_it_back() -> void:
	if _skip_without_library():
		return
	assert_string_contains(ScatterNative.version(), ScatterNative.CAPABILITY_FIELDS)
	var heights := _grid(60, 60, 0, RandomNumberGenerator.new())
	var step := Vector2(0.25, 0.25)
	var rect := Rect2i(5, 5, 20, 20)
	var native_of := func() -> Dictionary:
		return ScatterNative.rule_fields(
			heights,
			60,
			60,
			step,
			rect,
			TerrainRules.radius_samples(0.25),
			TerrainRules.cliff_start_cos(),
			TerrainRules.cliff_end_cos()
		)
	assert_false(native_of.call().is_empty(), "native by default")
	ScatterNative.force_gdscript_fields = true
	assert_true(native_of.call().is_empty(), "fields forced to GDScript")
	ScatterNative.force_gdscript_fields = false
	ScatterNative.force_gdscript = true
	assert_true(native_of.call().is_empty(), "everything forced to GDScript")
	var forced := TerrainRules.sample_fields(heights, 60, 60, step, rect)
	ScatterNative.force_gdscript = false
	var native := TerrainRules.sample_fields(heights, 60, 60, step, rect)
	assert_eq(_same(forced.curvature, native.curvature), 0, "the two paths agree")
	assert_eq(_same(forced.steep, native.steep), 0, "the two paths agree (steep)")
