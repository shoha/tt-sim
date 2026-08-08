extends GutTest

## Unit tests for GlbUtils.process_scatter_instances() -- the prototype bridge that
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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

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
	var xform: Variant = GlbUtils._row_to_transform(
		[5.0, 0.0, 10.0, 0.0, 0.0, 0.0, 1.0, 2.0, 2.0, 2.0]
	)
	assert_not_null(xform)
	assert_eq(xform.origin, Vector3(5.0, 0.0, 10.0))
	assert_eq(xform.basis.get_scale(), Vector3(2.0, 2.0, 2.0))


func test_row_to_transform_rejects_a_malformed_row() -> void:
	assert_null(GlbUtils._row_to_transform(["not", "enough", "numbers"]))
	assert_null(GlbUtils._row_to_transform([1, 2, 3]))
	assert_null(GlbUtils._row_to_transform("not an array"))


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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	# Only the two well-formed rows should have made it through.
	assert_eq(multimesh_instance.multimesh.instance_count, 2)

	scene.free()


func test_leaves_scene_untouched_when_extras_group_is_not_an_array() -> void:
	var built := _make_scene_with_template("GrassBlade")
	var scene: Node3D = built.scene
	scene.set_meta("tt_gltf_scene_extras", {"tt_scatter_instances": {"GrassBlade": "not an array"}})

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

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

	GlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_eq(multimesh_instance.get_meta("wind_foliage_category", ""), "grass")

	scene.free()
