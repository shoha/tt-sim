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


func test_scatter_within_budget_keeps_every_instance() -> void:
	var scene := _scatter_scene({"GrassBlade": 40})
	# A BoxMesh is 12 triangles, so 40 instances cost 480 -- inside a 10000 budget.
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10000)
	var built := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(built)
	assert_eq(built.multimesh.instance_count, 40)
	assert_false(scene.has_meta("tt_foliage_budget_report"))
	scene.free()


func test_scatter_over_budget_is_thinned() -> void:
	var scene := _scatter_scene({"GrassBlade": 100})
	# 100 instances x 12 triangles = 1200, against a 600 budget -> half survive.
	ScatterGlbUtils.process_scatter_instances(scene, {}, 600)
	var built := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(built)
	assert_eq(built.multimesh.instance_count, 50)
	scene.free()


func test_thinning_records_a_report_on_the_scene() -> void:
	# The report leaves utils/ as scene meta because nothing in utils/ may touch an
	# autoload; level_loader.gd reads it back and shows the toast.
	var scene := _scatter_scene({"GrassBlade": 100})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 600)
	assert_true(scene.has_meta("tt_foliage_budget_report"))
	var report: Dictionary = scene.get_meta("tt_foliage_budget_report")
	assert_true(report.thinned)
	assert_eq(report.instances_before, 100)
	assert_eq(report.instances_after, 50)
	scene.free()


func test_a_deny_listed_rock_species_is_still_budgeted() -> void:
	# WindFoliage.classify_category() returns "" for rock/stone/boulder names, but that
	# decides what sways in the wind, not what costs primitives. Budgeting only tree and
	# grass would let a map escape the cap by naming its species "rock_grass".
	var scene := _scatter_scene({"RockCluster": 100})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 600)
	var built := scene.get_node_or_null("RockCluster_MultiMesh") as MultiMeshInstance3D
	assert_not_null(built)
	assert_eq(built.multimesh.instance_count, 50)
	# Confirms the species really was deny-listed (wind category "") rather than merely
	# having "rock" in its name while some future keyword change reclassified it as grass.
	assert_eq(built.get_meta("wind_foliage_category", "unset"), "")
	scene.free()


func test_thinning_is_identical_across_two_loads_of_the_same_map() -> void:
	var first := _scatter_scene({"GrassBlade": 100})
	ScatterGlbUtils.process_scatter_instances(first, {}, 600)
	var second := _scatter_scene({"GrassBlade": 100})
	ScatterGlbUtils.process_scatter_instances(second, {}, 600)
	var first_built := first.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	var second_built := second.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_eq(first_built.multimesh.instance_count, second_built.multimesh.instance_count)
	first.free()
	second.free()


func test_every_species_is_thinned_when_several_share_the_budget() -> void:
	var scene := _scatter_scene({"GrassBlade": 100, "PineTree": 100})
	# 200 instances x 12 = 2400, against 1200 -> each keeps half.
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1200)
	var grass := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	var pine := scene.get_node_or_null("PineTree_MultiMesh") as MultiMeshInstance3D
	assert_eq(grass.multimesh.instance_count, 50)
	assert_eq(pine.multimesh.instance_count, 50)
	scene.free()


func test_thinned_single_instance_species_still_frees_its_template_node() -> void:
	# Pipeline-level regression guard for FoliageBudget.plan()'s floor-to-1: a species whose
	# proportional share rounds down to zero would otherwise leave
	# _build_multimesh_from_transforms' early-return path taken, its template MeshInstance3D
	# never freed, and HeroTree rendering once, standalone, at its Blender template
	# transform instead of being replaced by a MultiMesh at its one authored position.
	#
	# Both species use a BoxMesh (12 primitives/instance, see _scatter_scene). 1000
	# GrassBlade + 1 HeroTree = 1001 instances x 12 = 12,012 total primitives. At a 6000
	# budget, ratio = 6000/12012 = 0.4995...; HeroTree's raw share is
	# floor(1 * 0.4995) = 0, which plan()'s floor bumps to 1. GrassBlade's share is
	# floor(1000 * 0.4995) = 499, unaffected by the floor.
	var scene := _scatter_scene({"GrassBlade": 1000, "HeroTree": 1})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 6000)

	assert_null(scene.get_node_or_null("HeroTree"))
	var hero := scene.get_node_or_null("HeroTree_MultiMesh") as MultiMeshInstance3D
	assert_not_null(hero)
	assert_eq(hero.multimesh.instance_count, 1)

	scene.free()
