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
	# Explicit chunk_size large enough that these all-positive-x fixtures land in one cell
	# (ScatterChunker.cell_for uses floori, so coordinates straddling zero land in cell -1
	# and cell 0 at ANY chunk size -- this only works because _rows emits every instance at
	# x >= 0, z = 0). These budget tests are about thinning, not chunking, so they pin the
	# orthogonal variable the same way they already pin primitive_budget -- and that keeps
	# their unsuffixed `<Species>_MultiMesh` lookups valid. Chunking with thinning is
	# covered separately by test_thinning_and_chunking_compose.
	ScatterGlbUtils.process_scatter_instances(scene, {}, 10000, 10000.0)
	var built := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(built)
	assert_eq(built.multimesh.instance_count, 40)
	assert_false(scene.has_meta("tt_foliage_budget_report"))
	scene.free()


func test_scatter_over_budget_is_thinned() -> void:
	var scene := _scatter_scene({"GrassBlade": 100})
	# 100 instances x 12 triangles = 1200, against a 600 budget -> half survive.
	ScatterGlbUtils.process_scatter_instances(scene, {}, 600, 10000.0)
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
	ScatterGlbUtils.process_scatter_instances(scene, {}, 600, 10000.0)
	var built := scene.get_node_or_null("RockCluster_MultiMesh") as MultiMeshInstance3D
	assert_not_null(built)
	assert_eq(built.multimesh.instance_count, 50)
	# Confirms the species really was deny-listed (wind category "") rather than merely
	# having "rock" in its name while some future keyword change reclassified it as grass.
	assert_eq(built.get_meta("wind_foliage_category", "unset"), "")
	scene.free()


func test_thinning_is_identical_across_two_loads_of_the_same_map() -> void:
	var first := _scatter_scene({"GrassBlade": 100})
	ScatterGlbUtils.process_scatter_instances(first, {}, 600, 10000.0)
	var second := _scatter_scene({"GrassBlade": 100})
	ScatterGlbUtils.process_scatter_instances(second, {}, 600, 10000.0)
	var first_built := first.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	var second_built := second.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_eq(first_built.multimesh.instance_count, second_built.multimesh.instance_count)
	first.free()
	second.free()


func test_every_species_is_thinned_when_several_share_the_budget() -> void:
	var scene := _scatter_scene({"GrassBlade": 100, "PineTree": 100})
	# 200 instances x 12 = 2400, against 1200 -> each keeps half.
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1200, 10000.0)
	var grass := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	var pine := scene.get_node_or_null("PineTree_MultiMesh") as MultiMeshInstance3D
	assert_eq(grass.multimesh.instance_count, 50)
	assert_eq(pine.multimesh.instance_count, 50)
	scene.free()


func test_thinned_single_instance_species_still_frees_its_template_node() -> void:
	# Pipeline-level regression guard for FoliageBudget.plan()'s floor-to-1: a species whose
	# proportional share rounds down to zero would otherwise leave kept_transforms empty,
	# so bucket_by_cell would build no chunk at all for HeroTree -- but
	# process_scatter_instances frees the template node unconditionally after the per-cell
	# build loop regardless of how many chunks that loop built, so HeroTree would not
	# render standalone at its Blender template transform, it would just silently vanish
	# instead of being replaced by a MultiMesh at its one authored position.
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
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1 << 40, 10.0)
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
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1 << 40, 10.0)
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh_c0_0"))
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh_c1_0"))
	assert_not_null(scene.get_node_or_null("GrassBlade_MultiMesh_c2_0"))
	scene.free()


func test_a_single_cell_species_keeps_its_unsuffixed_name() -> void:
	# Deliberate: an unchunked species keeps today's naming contract, so the suffix reads as
	# a signal that a species was split rather than noise on every foliage node.
	var scene := _scatter_scene({"GrassBlade": 5})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1 << 40, 100.0)
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
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1 << 40, 10.0)
	assert_false(is_instance_valid(template))
	assert_null(scene.get_node_or_null("GrassBlade"))
	scene.free()


func test_every_grass_chunk_keeps_its_category_meta_and_shadow_setting() -> void:
	# Both are applied per built node, so chunking must not drop either: the meta is how
	# OcclusionFadeManager finds foliage, and cast_shadow OFF is a measured -17% frame-time
	# change for grass.
	var scene := _scatter_scene({"GrassBlade": 25})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1 << 40, 10.0)
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


func test_thinning_and_chunking_compose() -> void:
	# Two species x 100 instances x 12 primitives (BoxMesh) = 2400 total, against a 1200
	# budget -> ratio 1200/2400 = 0.5, so each species' floor(100 * 0.5) = 50 survive (the
	# same arithmetic as test_every_species_is_thinned_when_several_share_the_budget, which
	# is single-cell because it pins chunk_size; this test exercises the same thinning at
	# the real default chunk_size instead). select_indices shuffles then sorts per species
	# (keyed by species name, so GrassBlade and PineTree get independent shuffles), so each
	# species' survivors are spread across its own whole 0..99 index range rather than
	# being a prefix, and _rows puts instance i at x = i -- so each species' kept
	# transforms still span most of cells 0..9 and must occupy more than one, independently
	# of the other species.
	var scene := _scatter_scene({"GrassBlade": 100, "PineTree": 100})
	ScatterGlbUtils.process_scatter_instances(scene, {}, 1200, 10.0)
	assert_eq(_instances_for_species(scene, "GrassBlade"), 50)
	assert_eq(_instances_for_species(scene, "PineTree"), 50)
	assert_gt(_chunk_count_for_species(scene, "GrassBlade"), 1)
	assert_gt(_chunk_count_for_species(scene, "PineTree"), 1)
	scene.free()


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
