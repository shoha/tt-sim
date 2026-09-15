extends GutTest

## Unit tests for ScatterGlbUtils.process_scatter_instances() -- the prototype bridge that
## turns terrain-paint's per-instance Geoscatter transform data (written as
## "tt_scatter_instances" scene extras, see engine/scatter_instancing.py in the
## terrain-paint repo) into a real MultiMeshInstance3D, instead of the
## many-real-duplicated-triangles shape a "Bake Scatter to Mesh" export produces.


func _make_scene_with_template(template_name: String) -> Dictionary:
	var scene := Node3D.new()
	var template := MeshInstance3D.new()
	template.name = template_name
	template.mesh = BoxMesh.new()
	scene.add_child(template)
	return {"scene": scene, "template": template}


func test_builds_multimesh_with_correct_instance_count() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	(
		scene
		. set_meta(
			"tt_gltf_scene_extras",
			{
				"tt_scatter_instances":
				{
					"GrassBlade":
					[
						[1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
						[2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
						[3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
					]
				}
			}
		)
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	assert_eq(multimesh_instance.multimesh.instance_count, 3)

	scene.free()


func test_removes_the_original_template_node() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	var template: MeshInstance3D = built.template
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"GrassBlade": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	assert_false(is_instance_valid(template))
	assert_null(scene.get_node_or_null("GrassBlade"))

	scene.free()


func test_multimesh_shares_the_templates_mesh_resource() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	var template: MeshInstance3D = built.template
	var original_mesh := template.mesh
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"GrassBlade": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_eq(multimesh_instance.multimesh.mesh, original_mesh)

	scene.free()


func test_row_to_transform_matches_the_row_data() -> void:
	# Confirmed via a real headless probe that MultiMesh.get_instance_transform()
	# always reads back identity under Godot's headless/dummy rendering driver
	# regardless of what was set -- so this checks the row -> Transform3D math
	# directly (see _row_to_transform's own docstring) rather than round-tripping
	# through a MultiMesh, which cannot be verified this way in an automated run.
	# Translation (5, 0, 10), identity rotation, uniform scale 2 -- picked so a
	# transposed/misordered column would visibly fail rather than accidentally pass
	# (e.g. swapping scale and translation would still "work" at the origin).
	var xform: Variant = ScatterGlbUtils._row_to_transform(
		[5.0, 0.0, 10.0, 0.0, 0.0, 0.0, 1.0, 2.0, 2.0, 2.0]
	)
	assert_not_null(xform)
	assert_eq(xform.origin, Vector3(5.0, 0.0, 10.0))
	assert_eq(xform.basis.get_scale(), Vector3(2.0, 2.0, 2.0))


func test_row_to_transform_rejects_a_malformed_row() -> void:
	assert_null(ScatterGlbUtils._row_to_transform(["not", "enough", "numbers"]))
	assert_null(ScatterGlbUtils._row_to_transform([1, 2, 3]))
	assert_null(ScatterGlbUtils._row_to_transform("not an array"))


func test_multimesh_instance_sits_directly_under_scene_root_with_identity_transform() -> void:
	# The template can be parented anywhere in the tree, and can itself carry a
	# non-identity local transform (e.g. wherever the user happened to place the
	# single low-poly asset object in Blender) -- the recorded per-instance
	# transforms are Blender WORLD-space matrices, already relative to an identity
	# scene root, so the new MultiMeshInstance3D must NOT inherit the template's own
	# parent chain or local offset, or every instance would land in the wrong place.
	var scene := Node3D.new()
	var wrapper := Node3D.new()
	wrapper.name = "SomeWrapper"
	scene.add_child(wrapper)
	var template := MeshInstance3D.new()
	template.name = "GrassBlade"
	template.mesh = BoxMesh.new()
	template.position = Vector3(100.0, 50.0, -20.0)
	wrapper.add_child(template)
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"GrassBlade": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := (
		GlbUtils.find_node_by_name(scene, "GrassBlade_MultiMesh") as MultiMeshInstance3D
	)
	assert_not_null(multimesh_instance)
	assert_eq(multimesh_instance.get_parent(), scene)
	assert_eq(multimesh_instance.transform, Transform3D.IDENTITY)

	scene.free()


func test_groups_two_distinct_instance_names_into_two_multimeshes() -> void:
	var scene := Node3D.new()
	var fern := MeshInstance3D.new()
	fern.name = "Fern"
	fern.mesh = BoxMesh.new()
	scene.add_child(fern)
	var flower := MeshInstance3D.new()
	flower.name = "Flower"
	flower.mesh = SphereMesh.new()
	scene.add_child(flower)
	(
		scene
		. set_meta(
			"tt_gltf_scene_extras",
			{
				"tt_scatter_instances":
				{
					"Fern": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1], [1, 0, 0, 0, 0, 0, 1, 1, 1, 1]],
					"Flower": [[2, 0, 0, 0, 0, 0, 1, 1, 1, 1]],
				}
			}
		)
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var fern_mm := scene.get_node_or_null("Fern_MultiMesh") as MultiMeshInstance3D
	var flower_mm := scene.get_node_or_null("Flower_MultiMesh") as MultiMeshInstance3D
	assert_not_null(fern_mm)
	assert_not_null(flower_mm)
	assert_eq(fern_mm.multimesh.instance_count, 2)
	assert_eq(flower_mm.multimesh.instance_count, 1)

	scene.free()


func test_does_nothing_with_no_scatter_instances_extras() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene

	ScatterGlbUtils.process_scatter_instances(scene)

	assert_true(is_instance_valid(built.template))
	assert_null(scene.get_node_or_null("GrassBlade_MultiMesh"))

	scene.free()


func test_ignores_a_reference_to_a_name_not_present_in_the_scene() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"SomeOtherAsset": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	# The unrelated template is left completely alone -- it was never named in the
	# extras, so nothing about it should change.
	assert_true(is_instance_valid(built.template))
	assert_null(scene.get_node_or_null("SomeOtherAsset_MultiMesh"))

	scene.free()


func test_skips_a_malformed_row_without_raising() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	(
		scene
		. set_meta(
			"tt_gltf_scene_extras",
			{
				"tt_scatter_instances":
				{
					"GrassBlade":
					[
						[0, 0, 0, 0, 0, 0, 1, 1, 1, 1],
						["not", "enough", "numbers"],
						[1, 0, 0, 0, 0, 0, 1, 1, 1, 1],
					]
				}
			}
		)
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	# Only the two well-formed rows should have made it through.
	assert_eq(multimesh_instance.multimesh.instance_count, 2)

	scene.free()


func test_leaves_scene_untouched_when_extras_group_is_not_an_array() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	scene.set_meta("tt_gltf_scene_extras", {"tt_scatter_instances": {"GrassBlade": "not an array"}})

	ScatterGlbUtils.process_scatter_instances(scene)

	assert_true(is_instance_valid(built.template))
	assert_null(scene.get_node_or_null("GrassBlade_MultiMesh"))

	scene.free()


func test_tags_a_tree_named_instance_with_the_tree_wind_foliage_category() -> void:
	var built := _make_scene_with_template("OakTree")
	var scene: Node3D = built.scene
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"OakTree": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("OakTree_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	assert_eq(multimesh_instance.get_meta("wind_foliage_category", ""), "tree")

	scene.free()


func test_tags_an_unrecognized_instance_name_with_the_grass_wind_foliage_category() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"GrassBlade": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_eq(multimesh_instance.get_meta("wind_foliage_category", ""), "grass")

	scene.free()


func test_grass_category_multimesh_has_shadow_casting_disabled() -> void:
	# Measured perf fix (see ScatterGlbUtils._build_multimesh_from_transforms' inline comment):
	# Godot runs the same fragment() code (with discard) in the shadow pass as the color
	# pass for an alpha-cutout shader, disabling early-Z there -- dense overlapping grass
	# pays full fragment cost per covered shadow-pass sample. Grass no longer casts.
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"GrassBlade": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_eq(multimesh_instance.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	scene.free()


func test_tree_category_multimesh_keeps_shadow_casting_on() -> void:
	# Trees keep casting real shadows -- only "grass" gets SHADOW_CASTING_SETTING_OFF.
	var built := _make_scene_with_template("OakTree")
	var scene: Node3D = built.scene
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"OakTree": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("OakTree_MultiMesh") as MultiMeshInstance3D
	assert_eq(multimesh_instance.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	scene.free()


func _rows(count: int) -> Array:
	var rows: Array = []
	for i in count:
		rows.append([float(i), 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _scatter_scene(species: Dictionary) -> Node3D:
	# species maps a template node name to a row count.
	var scene := Node3D.new()
	var groups := {}
	for species_name in species.keys():
		var template := MeshInstance3D.new()
		template.name = species_name
		template.mesh = BoxMesh.new()
		scene.add_child(template)
		groups[species_name] = _rows(species[species_name])
	scene.set_meta("tt_gltf_scene_extras", {"tt_scatter_instances": groups})
	return scene


func _count_multimesh_children(scene: Node3D) -> int:
	var found := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D:
			found += 1
	return found


func _total_instances(scene: Node3D) -> int:
	var total := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D:
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func test_a_species_spanning_several_cells_becomes_several_multimesh_nodes() -> void:
	# 25 instances at x = 0..24 with chunk_size 10 occupy cells 0, 1 and 2: x = 0..9 is cell
	# 0 (10 instances), x = 10..19 is cell 1 (10 instances), x = 20..24 is cell 2 (5
	# instances). Asserting only node count (3) and total instances (25), as this test used
	# to, would also pass a 1/1/23 mis-split -- neither number distinguishes an even split
	# from a lopsided one, so assert each node's own count instead.
	var scene := _scatter_scene({"GrassBlade": 25})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10.0)
	var cell0 := scene.get_node_or_null("GrassBlade_MultiMesh_c0_0") as MultiMeshInstance3D
	var cell1 := scene.get_node_or_null("GrassBlade_MultiMesh_c1_0") as MultiMeshInstance3D
	var cell2 := scene.get_node_or_null("GrassBlade_MultiMesh_c2_0") as MultiMeshInstance3D
	assert_not_null(cell0)
	assert_not_null(cell1)
	assert_not_null(cell2)
	assert_eq(cell0.multimesh.instance_count, 10)
	assert_eq(cell1.multimesh.instance_count, 10)
	assert_eq(cell2.multimesh.instance_count, 5)
	scene.free()


func test_chunk_nodes_carry_the_cell_suffix() -> void:
	var scene := _scatter_scene({"GrassBlade": 25})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10.0)
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh_c0_0"))
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh_c1_0"))
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh_c2_0"))
	scene.free()


func test_a_single_cell_species_keeps_its_unsuffixed_name() -> void:
	# Deliberate: an unchunked species keeps today's naming contract, so the suffix reads as
	# a signal that a species was split rather than noise on every foliage node.
	var scene := _scatter_scene({"GrassBlade": 5})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 100.0)
	assert_eq(_count_multimesh_children(scene), 1)
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh"))
	scene.free()


func test_chunking_frees_the_template_exactly_once() -> void:
	# The builder used to free the template as its last statement. Called once per chunk that
	# would free the same node repeatedly, which is an intermittent crash rather than a red
	# test, so this is the regression guard for hoisting the free out.
	var scene := _scatter_scene({"GrassBlade": 25})
	var template := scene.get_node_or_null("GrassBlade") as MeshInstance3D
	assert_not_null(template)
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10.0)
	assert_false(is_instance_valid(template))
	assert_null(scene.get_node_or_null("GrassBlade"))
	scene.free()


func test_every_grass_chunk_keeps_its_category_meta_and_shadow_setting() -> void:
	# Both are applied per built node, so chunking must not drop either: the meta is how
	# OcclusionFadeManager finds foliage, and cast_shadow OFF is a measured -17% frame-time
	# change for grass.
	var scene := _scatter_scene({"GrassBlade": 25})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10.0)
	var checked := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			assert_eq(mmi.get_meta("wind_foliage_category", "unset"), "grass")
			assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			checked += 1
	assert_eq(checked, 3)
	scene.free()


func _instances_for_species(scene: Node3D, species_name: String) -> int:
	var total := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D and child.name.begins_with(species_name + "_MultiMesh"):
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func _chunk_count_for_species(scene: Node3D, species_name: String) -> int:
	var found := 0
	for child in scene.get_children():
		if child is MultiMeshInstance3D and child.name.begins_with(species_name + "_MultiMesh"):
			found += 1
	return found


func test_pipeline_chunks_along_both_axes_across_the_origin() -> void:
	# _rows emits every instance at x = i, z = 0, so every other pipeline test in this file
	# chunks along +X only, with z pinned at 0 -- ScatterChunker's own unit tests cover
	# negative cells and both axes thoroughly, but nothing here does. _scatter_scene/_rows
	# cannot express instances straddling the origin on both axes, so this builds the
	# extras dictionary directly, the same way _scatter_scene does internally.
	#
	# At ScatterChunker.CHUNK_SIZE_WORLD_UNITS (10.0): cell_for(-5, 0, -5) is
	# (floori(-5.0 / 10.0), floori(-5.0 / 10.0)) = (floori(-0.5), floori(-0.5)) = (-1, -1).
	# cell_for(5, 0, 5) is (floori(5.0 / 10.0), floori(5.0 / 10.0)) = (floori(0.5),
	# floori(0.5)) = (0, 0). So this also covers ScatterChunker.cell_suffix's hyphenated
	# node name ("_c-1_-1") landing on a real node via add_child -- cell_suffix's own tests
	# only ever check the returned string, never a real node name.
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	(
		scene
		. set_meta(
			"tt_gltf_scene_extras",
			{
				"tt_scatter_instances":
				{
					"GrassBlade":
					[
						[-5.0, 0.0, -5.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
						[5.0, 0.0, 5.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
					]
				}
			}
		)
	)

	ScatterGlbUtils.process_scatter_instances(scene)

	var negative_cell := (
		scene.get_node_or_null("GrassBlade_MultiMesh_c-1_-1") as MultiMeshInstance3D
	)
	var origin_cell := scene.get_node_or_null("GrassBlade_MultiMesh_c0_0") as MultiMeshInstance3D
	assert_not_null(negative_cell)
	assert_not_null(origin_cell)
	assert_eq(negative_cell.multimesh.instance_count, 1)
	assert_eq(origin_cell.multimesh.instance_count, 1)

	scene.free()


func test_import_builds_every_instance_regardless_of_size() -> void:
	# Import no longer thins. The density dial is applied at runtime over the full set, so
	# everything must be present in the MultiMesh for the slider to be able to raise.
	var scene := _scatter_scene({"GrassBlade": 100})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10.0)
	assert_eq(_total_instances(scene), 100)
	assert_false(scene.has_meta("tt_foliage_budget_report"))
	scene.free()


func test_transforms_to_buffer_matches_the_documented_layout() -> void:
	# ScatterGlbUtils._build_multimesh_from_transforms uploads every instance in one
	# MultiMesh.buffer assignment instead of one set_instance_transform() call per
	# instance. MultiMesh.get_instance_transform() always reads back identity under
	# Godot's headless/dummy rendering driver regardless of what was set or how it was
	# set (confirmed via a real headless probe, same as _row_to_transform's own
	# docstring notes) -- and a MultiMesh built via the old set_instance_transform()
	# loop reads back an EMPTY `buffer` property headless too, so comparing the loop
	# path's buffer against the new path's buffer is also a dead end. That leaves the
	# pure flattening math as the only thing this environment can actually check, so
	# this asserts the built PackedFloat32Array's exact float values against the
	# documented MultiMesh.buffer TRANSFORM_3D layout (12 floats/instance, row-major:
	# [basis.x.<axis>, basis.y.<axis>, basis.z.<axis>, origin.<axis>] per axis in x, y,
	# z) for two distinct, non-trivial transforms -- picked with distinct rotation,
	# non-uniform scale and translation per axis so a transposed row/column or a
	# swapped basis/origin slot would visibly fail rather than accidentally pass.
	var xform0 := Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, -1.0, 0.0)),
		Vector3(5.0, 1.0, -7.0)
	)
	var xform1 := Transform3D(
		Basis(Vector3(2.0, 0.0, 0.0), Vector3(0.0, 3.0, 0.0), Vector3(0.0, 0.0, 4.0)),
		Vector3(-2.0, 4.5, 9.0)
	)
	var transforms: Array[Transform3D] = [xform0, xform1]

	var buffer := ScatterGlbUtils._transforms_to_buffer(transforms)

	assert_eq(buffer.size(), 24)
	var expected := PackedFloat32Array(
		[
			1.0,
			0.0,
			0.0,
			5.0,
			0.0,
			0.0,
			-1.0,
			1.0,
			0.0,
			1.0,
			0.0,
			-7.0,
			2.0,
			0.0,
			0.0,
			-2.0,
			0.0,
			3.0,
			0.0,
			4.5,
			0.0,
			0.0,
			4.0,
			9.0,
		]
	)
	for i in expected.size():
		assert_almost_eq(buffer[i], expected[i], 0.00001, "buffer[%d]" % i)


func test_transforms_to_buffer_round_trips_through_multimesh_buffer_headless() -> void:
	# The dummy rendering driver used headless does correctly store and return whatever
	# is assigned directly to MultiMesh.buffer (unlike get_instance_transform(), and
	# unlike buffer after a set_instance_transform() loop -- see the test above), so this
	# confirms _build_multimesh_from_transforms' actual multimesh.buffer assignment
	# survives unchanged, i.e. nothing about MultiMesh's own property setter mutates or
	# reorders the array this module built.
	var xform := Transform3D(Basis().rotated(Vector3.UP, 0.7), Vector3(3.0, 0.0, -4.0))
	var transforms: Array[Transform3D] = [xform]
	var buffer := ScatterGlbUtils._transforms_to_buffer(transforms)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = 1
	multimesh.buffer = buffer

	assert_eq(multimesh.buffer, buffer)


func test_import_frees_the_template_of_a_single_instance_species() -> void:
	# The builder returns early on an empty transform list, before it frees the template,
	# so a species reduced to nothing used to strand a MeshInstance3D rendering standalone
	# at an arbitrary Blender transform. Nothing is reduced at import any more, but the
	# guard is cheap to keep honest.
	var scene := _scatter_scene({"GrassBlade": 1000, "HeroTree": 1})
	var template := scene.get_node_or_null("HeroTree") as MeshInstance3D
	assert_not_null(template)
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10.0)
	assert_false(is_instance_valid(template))
	assert_eq(_instances_for_species(scene, "HeroTree"), 1)
	scene.free()
