extends GutTest

## GroundShadeField (the Painted ground's shading field) and TerrainBackCaster: a dirty-rect
## update equals a full bake bit for bit, the map's edge and a chunk's border carry no step, a
## short sheer step keeps its steep channel, and the back-face caster twin comes and goes.

const SIZE_M := Vector2i(30, 30)


func _document(law: Callable) -> MapDocument:
	var doc := MapDocument.create_flat(SIZE_M, "", "", 0)
	var count := doc.samples_x() * doc.samples_z()
	if doc.heights.size() < count:
		doc.heights.resize(count)
	_apply(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()), law)
	return doc


func _apply(doc: MapDocument, rect: Rect2i, law: Callable) -> void:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := doc.sample_index(x, z)
			doc.heights[i] = law.call(doc.sample_to_world(Vector2(x, z)), doc.heights[i])


static func _hills(p: Vector2, _h: float) -> float:
	return 2.0 * sin(p.x * 0.31) * cos(p.y * 0.23) + 0.4 * sin(p.x * 1.7 + p.y * 1.1)


func _baked(doc: MapDocument) -> GroundShadeField:
	var field := GroundShadeField.new()
	field.bake(doc)
	return field


func test_update_of_a_dirty_rect_equals_a_full_bake() -> void:
	var doc := _document(_hills)
	var field := _baked(doc)
	var rect := Rect2i(50, 30, 28, 26)
	var middle := doc.sample_to_world(Vector2(rect.get_center()))
	var bump := func(p: Vector2, h: float) -> float:
		return h + 1.5 * exp(-p.distance_squared_to(middle) / 4.0)
	_apply(doc, rect, bump)
	var touched := field.update(doc, rect)
	assert_true(touched.has_area(), "the update reports the texels it rewrote")
	assert_true(touched.encloses(rect), "they hold the edited samples")
	assert_true(field.bytes() == _baked(doc).bytes(), "update equals a full bake, bit for bit")


func test_update_at_the_map_corner_and_over_a_wider_rect_equals_a_full_bake() -> void:
	var doc := _document(_hills)
	var field := _baked(doc)
	var step := func(p: Vector2, h: float) -> float: return h + (1.0 if p.x + p.y < -27.0 else 0.0)
	_apply(doc, Rect2i(0, 0, 9, 7), step)
	# The reported rect may be wider than the change (ground_edited adds the rule fields' reach).
	field.update(doc, Rect2i(-4, -4, 40, 40))
	assert_true(field.bytes() == _baked(doc).bytes(), "a corner edit equals a full bake")
	var last := doc.samples_x() - 1
	_apply(doc, Rect2i(last - 3, doc.samples_z() - 2, 4, 2), step.bind())
	doc.heights[doc.sample_index(last, doc.samples_z() - 1)] += 0.7
	field.update(doc, Rect2i(last - 10, doc.samples_z() - 10, 30, 30))
	assert_true(field.bytes() == _baked(doc).bytes(), "the far corner too")


func test_an_edit_that_changes_no_height_rewrites_nothing() -> void:
	var doc := _document(_hills)
	var field := _baked(doc)
	var before := field.bytes().duplicate()
	assert_eq(field.update(doc, Rect2i(10, 10, 30, 30)), Rect2i(), "a mask edit touches no texel")
	assert_true(field.bytes() == before)


func test_a_document_of_another_size_is_baked_whole() -> void:
	var field := _baked(_document(_hills))
	var small := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	var touched := field.update(small, Rect2i(0, 0, 4, 4))
	assert_eq(touched.size, Vector2i(small.samples_x(), small.samples_z()))
	assert_true(field.matches(small))


func test_a_second_map_of_another_size_resizes_the_texture() -> void:
	# A second map played in one session: the texture exists from the first map, and updating it
	# in place with the second map's image errored and kept the first map's field.
	var field := _baked(_document(_hills))
	var texture := field.texture()
	assert_eq(texture.get_size(), Vector2(field.width, field.depth))
	var small := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	field.bake(small)
	assert_engine_error(0, "baking another size raises no engine error")
	assert_same(field.texture(), texture, "the bound texture object stays")
	assert_eq(texture.get_size(), Vector2(small.samples_x(), small.samples_z()))
	var large := MapDocument.create_flat(Vector2i(40, 26), "", "", 0)
	field.update(large, Rect2i(0, 0, 2, 2))
	assert_engine_error(0, "nor does an update that finds another size")
	assert_eq(texture.get_size(), Vector2(large.samples_x(), large.samples_z()))


func test_map_edge_samples_are_finite_and_follow_a_ramp() -> void:
	var doc := _document(func(p: Vector2, _h: float) -> float: return 0.5 * p.x)
	var field := _baked(doc)
	var mid := doc.samples_z() / 2
	var inner := field.texel(doc.samples_x() / 2, mid)
	assert_almost_eq(inner.r, 0.5, 0.002, "the gradient of a ramp")
	assert_almost_eq(inner.g, 0.0, 0.002)
	assert_almost_eq(inner.b, 0.0, 0.01, "a ramp is neither rim nor foot")
	for x: int in [0, 1, doc.samples_x() - 2, doc.samples_x() - 1]:
		var edge := field.texel(x, mid)
		assert_true(is_finite(edge.r) and is_finite(edge.b) and is_finite(edge.a), "finite at %d" % x)
		assert_between(edge.r, 0.0, 0.502, "the edge clamps the ramp, never overshoots it")
	for z: int in [0, doc.samples_z() - 1]:
		assert_almost_eq(field.texel(doc.samples_x() / 2, z).r, 0.5, 0.002, "edge row %d" % z)


func test_a_chunk_border_pixel_has_no_step() -> void:
	var doc := _document(
		func(p: Vector2, _h: float) -> float:
			return 3.0 * exp(-p.distance_squared_to(Vector2(1.5, 0.8)) / 18.0)
	)
	var field := _baked(doc)
	# The terrain's chunks are 10 m cells: world x = 0 and x = 10 are chunk borders.
	for border_m: float in [0.0, 10.0]:
		var bx := roundi(doc.world_to_sample(Vector2(border_m, 0.0)).x)
		for z in range(40, 80, 5):
			for channel in 3:
				var across := absf(field.texel(bx, z)[channel] - field.texel(bx - 1, z)[channel])
				var beside := 0.0
				for k: int in [-3, -2, 1, 2]:
					var a: float = field.texel(bx + k, z)[channel]
					var b: float = field.texel(bx + k - 1, z)[channel]
					beside = maxf(beside, absf(a - b))
				assert_lte(across, beside * 1.5 + 0.002, "channel %d at z %d" % [channel, z])


func test_a_short_sheer_step_keeps_its_steep_face() -> void:
	# A sheer step along x = 0: half a metre high on the near half of the map, a quarter on the far.
	var doc := _document(
		func(p: Vector2, _h: float) -> float:
			return (0.5 if p.y < 0.0 else 0.25) if p.x > 0.0 else 0.0
	)
	var field := _baked(doc)
	var sx := roundi(doc.world_to_sample(Vector2(0.0, 0.0)).x)
	var tall := field.texel(sx, 20)
	var short := field.texel(sx, doc.samples_z() - 20)
	var banded := 1.0 - 1.0 / sqrt(1.0 + tall.r * tall.r + tall.g * tall.g)
	assert_lt(banded, 0.3, "the band-limited slope alone loses a half-metre step")
	assert_gt(tall.a, 0.36, "the steep channel keeps it over the rock threshold (0.3 and its noise)")
	assert_lt(short.a, 0.24, "a quarter-metre kerb stays ground")
	assert_almost_eq(field.texel(sx + 12, 20).a, 0.0, 0.001, "level ground beside it is not steep")


func test_the_steep_channel_reads_a_face_the_same_along_the_grid_and_across_it() -> void:
	# A 50 degree ramp is rock (slope 0.357, over the 0.3 threshold) whichever way it faces.
	var rise := tan(deg_to_rad(50.0))
	var along := _baked(_document(func(p: Vector2, _h: float) -> float: return p.x * rise))
	var across := _baked(
		_document(func(p: Vector2, _h: float) -> float: return (p.x + p.y) * rise / sqrt(2.0))
	)
	var a := along.texel(60, 60).a
	var d := across.texel(60, 60).a
	assert_almost_eq(a, 1.0 - cos(deg_to_rad(50.0)), 0.005, "a ramp along the grid")
	assert_almost_eq(d, a, 0.005, "the same ramp across the diagonal")
	# A quarter-metre kerb across a 20 degree slope stays ground with the two axes joined.
	var slope := tan(deg_to_rad(20.0))
	var kerb := _baked(
		_document(
			func(p: Vector2, _h: float) -> float: return p.y * slope + (0.25 if p.x > 0.0 else 0.0)
		)
	)
	var doc := MapDocument.create_flat(SIZE_M, "", "", 0)
	var sx := roundi(doc.world_to_sample(Vector2(0.0, 0.0)).x)
	assert_lt(kerb.texel(sx, 60).a, 0.3, "a kerb on a 20 degree slope stays ground")


func test_back_caster_twin_comes_and_goes() -> void:
	var chunk := MeshInstance3D.new()
	chunk.mesh = BoxMesh.new()
	add_child_autofree(chunk)
	var on := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	TerrainBackCaster.apply(chunk, on, true)
	var twin := chunk.get_node_or_null(TerrainBackCaster.NAME) as MeshInstance3D
	assert_not_null(twin, "a casting chunk gets its twin")
	assert_eq(chunk.cast_shadow, off, "and stops casting itself")
	assert_eq(twin.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(twin.mesh, chunk.mesh)
	assert_eq(chunk.get_child_count(), 0, "the twin is an internal child")
	assert_eq(TerrainBackCaster.casting(chunk), on)
	TerrainBackCaster.apply(chunk, off, true)
	assert_false(twin.visible, "a flat chunk's twin casts nothing")
	assert_eq(TerrainBackCaster.casting(chunk), off)
	TerrainBackCaster.apply(chunk, on, true)
	TerrainBackCaster.apply(chunk, TerrainBackCaster.casting(chunk), false)
	assert_eq(chunk.cast_shadow, on, "the Classic way is put back")
	assert_false(twin.visible, "and the twin casts nothing")
	assert_eq(TerrainBackCaster.casting(chunk), on)
