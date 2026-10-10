extends GutTest

## GlbCheck, the import check: refusals (one sentence each, nothing else), the footprint and
## floor read from the JSON chunk alone (node matrices, TRS, nesting, scatter sources left
## out), what the extras hold, and the warnings, which never block. Files are written under
## the run's data root in a _test_library_ folder and deleted after each test.

const Fixtures := preload("res://tests/unit/glb_fixtures.gd")

var _dir := ""


func before_each() -> void:
	_dir = Paths.DATA_ROOT + "_test_library_check/"
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for file_name in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + file_name)
	DirAccess.remove_absolute(_dir.trim_suffix("/"))


func _codes(report: Dictionary) -> Array:
	return report.warnings.map(func(w: Dictionary) -> String: return w.code)


func _check_json(
	nodes: Array, roots: Array, low: Vector3, high: Vector3, extras: Dictionary = {}
) -> Dictionary:
	var path := _dir + "shape.glb"
	assert_eq(Fixtures.write_glb(path, Fixtures.gltf_with(nodes, roots, low, high, extras)), OK)
	return GlbCheck.check(path)


func test_gltf_tscn_and_other_files_are_refused_with_one_sentence() -> void:
	assert_eq(GlbCheck.check("D:/maps/harbour/map.gltf").error, GlbCheck.REFUSE_GLTF)
	assert_eq(GlbCheck.check("D:/maps/harbour/map.tscn").error, GlbCheck.REFUSE_SCENE)
	assert_eq(GlbCheck.check("D:/maps/harbour/map.obj").error, GlbCheck.REFUSE_OTHER)
	assert_eq(GlbCheck.check(_dir + "missing.glb").error, GlbCheck.REFUSE_MISSING)
	for refusal: String in [GlbCheck.REFUSE_GLTF, GlbCheck.REFUSE_SCENE, GlbCheck.REFUSE_OTHER]:
		assert_eq(refusal.count(". "), 0, "one sentence: %s" % refusal)


func test_a_file_that_is_not_a_glb_is_refused() -> void:
	var file := FileAccess.open(_dir + "fake.glb", FileAccess.WRITE)
	file.store_string("{\"asset\": {\"version\": \"2.0\"}} and some more bytes")
	file.close()
	assert_eq(GlbCheck.check(_dir + "fake.glb").error, GlbCheck.REFUSE_NOT_GLB)


func test_a_glb_that_names_files_outside_itself_is_refused() -> void:
	var gltf := Fixtures.gltf_with([{"mesh": 0}], [0], -Vector3.ONE, Vector3.ONE)
	gltf["buffers"] = [{"uri": "map.bin", "byteLength": 4}]
	gltf["images"] = [{"uri": "grass.png"}, {"uri": "data:image/png;base64,AAAA"}]
	assert_eq(Fixtures.write_glb(_dir + "external.glb", gltf), OK)
	assert_eq(GlbCheck.check(_dir + "external.glb").error, GlbCheck.REFUSE_EXTERNAL % 2)


func test_a_real_export_reports_its_footprint_floor_and_extras() -> void:
	var path := _dir + "map.glb"
	assert_eq(Fixtures.write_map(path, Vector2(30.0, 20.0), 0.0, 3), OK)
	var report := GlbCheck.check(path)
	assert_eq(report.error, "")
	assert_true(report.has_bounds)
	assert_almost_eq(report.footprint_m.x, 30.0, 0.001, "the scatter source 500 m off is left out")
	assert_almost_eq(report.footprint_m.y, 20.0, 0.001)
	assert_almost_eq(report.footprint_ft.x, 30.0 / 0.3048, 0.01)
	assert_almost_eq(report.floor_m, -0.5, 0.001)
	assert_almost_eq(report.top_m, 0.0, 0.001)
	assert_eq(report.collision_nodes, 1)
	assert_true(report.meshes >= 3, "ground, its collision twin and the rock")
	assert_eq(report.extras.scatter_species, 1)
	assert_eq(report.extras.scatter_instances, 3)
	assert_true(report.extras.ambient_light)
	assert_false(report.extras.background_color)
	assert_eq(report.bytes, FileAccess.get_file_as_bytes(path).size())
	assert_eq(_codes(report), [], "a map at Y = 0 in metres warns of nothing")


func test_matrices_and_nesting_carry_the_bounds() -> void:
	# Parent moved 10 m along X; child scaled 2 on X and Z and lifted 3 m by its matrix.
	var matrix := [2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 2, 0, 0, 3, 0, 1]
	var nodes := [{"children": [1], "translation": [10, 0, 0]}, {"mesh": 0, "matrix": matrix}]
	var report := _check_json(nodes, [0], Vector3(-1, 0, -1), Vector3(1, 1, 1))
	assert_eq(report.bounds, AABB(Vector3(8, 3, -2), Vector3(4, 1, 4)))
	assert_eq(_codes(report), [GlbCheck.WARN_FLOOR], "lowest point 3 m above Y = 0")


func test_rotation_turns_the_footprint() -> void:
	var quarter_turn := [0.0, sin(PI / 4.0), 0.0, cos(PI / 4.0)]
	var nodes := [{"mesh": 0, "rotation": quarter_turn, "scale": [1, 1, 1]}]
	var report := _check_json(nodes, [0], Vector3(-2, 0, -1), Vector3(2, 1, 1))
	assert_almost_eq(report.footprint_m.x, 2.0, 0.001)
	assert_almost_eq(report.footprint_m.y, 4.0, 0.001)


func test_scatter_sources_and_nodes_outside_the_scene_are_left_out() -> void:
	var nodes := [{"mesh": 0}, {"mesh": 0, "name": "Tree_Oak", "translation": [300, 0, 0]}]
	nodes.append({"mesh": 0, "translation": [-900, 0, 0]})
	var extras := {"tt_scatter_instances": {"Tree_Oak": []}, "tt_custom": 1}
	var report := _check_json(nodes, [0, 1], Vector3(-1, 0, -1), Vector3(1, 1, 1), extras)
	assert_eq(report.bounds, AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2)))
	assert_eq(report.extras.scatter_species, 1)
	assert_eq(report.extras.other_keys, PackedStringArray(["tt_custom"]))


func test_unit_mistakes_warn_but_never_refuse() -> void:
	var tiny := _check_json([{"mesh": 0}], [0], Vector3(-0.3, 0, -0.3), Vector3(0.3, 0.1, 0.3))
	assert_eq(tiny.error, "")
	assert_eq(_codes(tiny), [GlbCheck.WARN_UNIT])
	var huge := _check_json([{"mesh": 0}], [0], Vector3(-3000, 0, -3000), Vector3(3000, 5, 3000))
	assert_eq(_codes(huge), [GlbCheck.WARN_UNIT])


func test_the_floor_warns_only_when_the_map_is_off_the_table() -> void:
	var sunk := _check_json([{"mesh": 0}], [0], Vector3(-20, -6, -20), Vector3(20, -1, 20))
	assert_eq(_codes(sunk), [GlbCheck.WARN_FLOOR], "the whole map under Y = 0")
	var pond := _check_json([{"mesh": 0}], [0], Vector3(-20, -3, -20), Vector3(20, 4, 20))
	assert_eq(_codes(pond), [], "a pond dug below the floor is a map, not a mistake")


func test_no_ground_and_the_streaming_budget_warn() -> void:
	var empty := Fixtures.gltf_with([{"name": "Empty"}], [0], Vector3.ZERO, Vector3.ONE)
	assert_eq(Fixtures.write_glb(_dir + "empty.glb", empty), OK)
	var report := GlbCheck.check(_dir + "empty.glb")
	assert_eq(report.error, "")
	assert_eq(_codes(report), [GlbCheck.WARN_EMPTY])
	report.has_bounds = true
	report.footprint_m = Vector2(60, 60)
	report.top_m = 2.0
	report.mb = GlbCheck.STREAMING_BUDGET_MB + 6.0
	assert_eq(_codes({"warnings": GlbCheck.warnings(report)}), [GlbCheck.WARN_BUDGET])
	report.mb = GlbCheck.STREAMING_BUDGET_MB - 1.0
	assert_eq(GlbCheck.warnings(report), [] as Array[Dictionary])
