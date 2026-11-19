extends GutTest

## The painted meadow grass as marks (PainterGrassMarks, painter_grass_mark.gdshader;
## docs/systems/painter.md "Plant roles"): painting points every wide grass cell's MultiMesh at its
## species' one-quad mark mesh and release puts the very same card mesh back, the shared card mesh
## is never edited, the A/B switch keeps the cards, a cell built later is caught, the marks take
## their stand-in's tones, and the sheet's grass-mark-pitch (core: 45) puts the cards beside the
## mark with the pitch on both materials, 0 the quad alone. Uses the built-in palette's temperate
## forest grass.

const BIOME := "temperate_forest_summer_s1"
const GRASS := BIOME + "/Grass_Grass_v0_temperate_forest"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}

var _map: Node3D = null


func before_each() -> void:
	PainterSheet.clear_cache()
	var container := Node3D.new()
	add_child_autofree(container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	container.add_child(_map)


func after_each() -> void:
	PainterGrassMarks.enabled = true
	PainterSheet.clear_cache()


func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p: Vector2 in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _grass_scatter() -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	scatter.build_all({GRASS: _rows([Vector2(1, 1), Vector2(2, 1)])})
	return scatter


func _card(scatter: AuthoredScatter) -> Mesh:
	return scatter.resolved_species()[GRASS]["mesh"]


func _height(scatter: AuthoredScatter) -> float:
	return maxf(float(scatter.resolved_species()[GRASS]["height"]), 0.05)


## The mesh every cell of `scatter` draws.
func _drawn(scatter: AuthoredScatter) -> Array[Mesh]:
	var out: Array[Mesh] = []
	for node in scatter.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null:
			out.append(mm.mesh)
	return out


func _mark_material(mesh: Mesh) -> ShaderMaterial:
	return mesh.surface_get_material(mesh.get_surface_count() - 1) as ShaderMaterial


## Sets the cached core sheet's grass-mark-pitch in every keyframe (cleared after each test).
func _set_pitch(deg: float) -> void:
	var sheet := PainterSheet.load_sheet("core")
	for mood: Variant in sheet:
		var frames: Variant = sheet[mood]
		if not frames is Array:
			continue
		for f: Variant in frames:
			if f is Dictionary and (f as Dictionary).has("numbers"):
				f["numbers"][PainterGrassMarks.PITCH_NUMBER] = deg


func test_a_wide_painted_grass_tuft_is_a_mark_and_a_narrow_or_unpainted_one_is_not() -> void:
	var scatter := _grass_scatter()
	var card := _card(scatter)
	var classic := card.surface_get_material(0)
	var extent := card.get_aabb().size * 0.5
	var height := _height(scatter)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var stand_in := card.surface_get_material(0)

	assert_true(PainterGrassMarks.is_mark_tuft(stand_in, extent, height), "a painted meadow tuft")
	assert_false(PainterGrassMarks.is_mark_tuft(classic, extent, height), "the Classic material")
	assert_false(PainterGrassMarks.is_mark_tuft(null, extent, height), "no material")
	assert_false(
		PainterGrassMarks.is_mark_tuft(stand_in, Vector3(0.05, 0.4, 0.05), 0.4), "a reed-thin tuft"
	)
	surfaces.release()


func test_the_quad_is_one_plain_quad_and_its_bounds_hold_the_largest_mark() -> void:
	var extent := Vector3(0.3, 0.2, 0.25)
	var arrays := PainterGrassMarks.quad(extent, 0.4)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 4)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 6, "two triangles")
	var uv := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	assert_eq(uv[0], Vector2(0, 1), "UV.y 1 at the foot")
	assert_null(arrays[Mesh.ARRAY_COLOR], "LAYOUT_PLAIN: no colour")
	# The largest mark: a footprint of 0.9 half widths plus 0.6 of a reach (at most 1.22 heights),
	# lifted toward the eye by about as much again, its top 1.22 x 1.42 heights over the root plus
	# that; the points below hold the first marks' larger reach (1.4 x 1.22 x 1.06 half widths).
	var box := PainterGrassMarks.bounds(extent, 0.4)
	assert_true(box.has_point(Vector3(3.5 * 0.3, 0.0, 0.0)), "reach and lift across")
	assert_true(box.has_point(Vector3(0.0, 1.75 * 0.4 + 3.5 * 0.3, 0.0)), "top and lift up")
	assert_true(box.has_point(Vector3(0.0, -0.35, -3.5 * 0.3)), "below the root")


func test_painting_draws_the_grass_as_marks_and_release_puts_the_same_cards_back() -> void:
	var scatter := _grass_scatter()
	var card := _card(scatter)
	var surfaces_before := card.get_surface_count()
	_set_pitch(0.0)
	var surfaces := PainterSurfaces.new()

	surfaces.paint(_map, STATE)

	var drawn := _drawn(scatter)
	assert_gt(drawn.size(), 0, "grass cells")
	for mesh in drawn:
		assert_ne(mesh, card, "a cell draws the mark")
		assert_eq(mesh.get_surface_count(), 1, "the quad alone at pitch 0")
		assert_eq(_mark_material(mesh).shader.resource_path, PainterGrassMarks.SHADER)
		assert_true(_mark_material(mesh).has_meta(PainterSurfaces.META), "a painted material")
		assert_eq(
			mesh.custom_aabb,
			PainterGrassMarks.bounds(card.get_aabb().size * 0.5, _height(scatter)),
			"culling sees the largest mark"
		)
	assert_eq(card.get_surface_count(), surfaces_before, "the shared card mesh is untouched")

	surfaces.release()

	for mesh in _drawn(scatter):
		assert_eq(mesh, card, "the very same card mesh back")


func test_the_switch_off_keeps_the_cards_under_painted() -> void:
	var scatter := _grass_scatter()
	var card := _card(scatter)
	PainterGrassMarks.enabled = false
	var surfaces := PainterSurfaces.new()

	surfaces.paint(_map, STATE)

	for mesh in _drawn(scatter):
		assert_eq(mesh, card, "cards")
	assert_true(card.surface_get_material(0).has_meta(PainterSurfaces.META), "still painted")
	surfaces.release()


func test_a_cell_built_after_painting_draws_its_mark() -> void:
	var scatter := _grass_scatter()
	var card := _card(scatter)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var before := _drawn(scatter).size()

	scatter.set_cells({Vector2i(3, 3): {GRASS: _rows([Vector2(30, 30)])}})
	await get_tree().process_frame

	var drawn := _drawn(scatter)
	assert_gt(drawn.size(), before, "a new cell")
	for mesh in drawn:
		assert_ne(mesh, card, "every cell draws the mark")
	surfaces.release()
	for mesh in _drawn(scatter):
		assert_eq(mesh, card, "and every cell gets its card back")


func test_the_marks_take_their_stand_ins_tones_and_thinning() -> void:
	var scatter := _grass_scatter()
	var card := _card(scatter)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var stand_in := card.surface_get_material(0) as ShaderMaterial
	var mark := _mark_material(_drawn(scatter)[0])

	for uniform in PainterGrassMarks.TONED:
		assert_eq(
			mark.get_shader_parameter(uniform),
			stand_in.get_shader_parameter(uniform),
			"%s copied" % uniform
		)
	var pitch := PainterSheet.number(
		PainterSheet.load_sheet("core"), "summer", PainterGrassMarks.PITCH_NUMBER, 45.0
	)
	assert_eq(float(mark.get_shader_parameter(&"mark_pitch")), pitch, "the sheet's pitch")
	surfaces.release()


func test_the_sheets_pitch_puts_the_cards_beside_the_mark_and_release_clears_it() -> void:
	var scatter := _grass_scatter()
	var card := _card(scatter)
	_set_pitch(40.0)
	var surfaces := PainterSurfaces.new()

	surfaces.paint(_map, STATE)

	var stand_in := card.surface_get_material(0) as ShaderMaterial
	for mesh in _drawn(scatter):
		assert_eq(mesh.get_surface_count(), card.get_surface_count() + 1, "the cards and the quad")
		assert_eq(mesh.surface_get_material(0), stand_in, "the cards keep their stand-in")
		assert_eq(float(_mark_material(mesh).get_shader_parameter(&"mark_pitch")), 40.0)
	assert_eq(float(stand_in.get_shader_parameter(&"mark_pitch")), 40.0, "the cards fade below it")

	surfaces.release()

	assert_eq(float(stand_in.get_shader_parameter(&"mark_pitch")), 0.0, "the stand-in's pitch off")
