extends GutTest

## Unit tests for MeshInstancingUtils.process_duplicate_mesh_instancing() -- the load-time pass
## that collapses groups of separately-placed MeshInstance3D nodes sharing one Mesh
## resource (Blender linked duplicates: Shift+D, or a Place Helper scatter stroke)
## into a single MultiMeshInstance3D.
##
## Every "skipped" test below guards a behaviour that would otherwise break silently
## rather than loudly -- collision disappearing with a freed parent, a token no longer
## fading into view behind a large prop, an animated prop freezing.

const SMALL_MESH_SIZE := Vector3(0.4, 0.4, 0.4)
const LARGE_MESH_SIZE := Vector3(4.0, 4.0, 4.0)


func _small_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = SMALL_MESH_SIZE
	return mesh


## Builds `count` MeshInstance3D siblings that all share `mesh`, spaced along X so
## their transforms are distinguishable.
func _add_duplicates(parent: Node3D, mesh: Mesh, count: int, prefix := "Rock") -> Array:
	var nodes := []
	for i in count:
		var node := MeshInstance3D.new()
		node.name = "%s_%d" % [prefix, i]
		node.mesh = mesh
		node.position = Vector3(i, 0.0, 0.0)
		parent.add_child(node)
		nodes.append(node)
	return nodes


func test_collapses_a_group_of_duplicates_into_one_multimesh() -> void:
	var scene := Node3D.new()
	_add_duplicates(scene, _small_mesh(), 30)

	var converted := MeshInstancingUtils.process_duplicate_mesh_instancing(scene)

	assert_eq(converted, 1)
	var multimesh_instance := scene.get_node_or_null("Rock_0_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	assert_eq(multimesh_instance.multimesh.instance_count, 30)
	assert_eq(multimesh_instance.transform, Transform3D.IDENTITY)

	scene.free()


func test_frees_the_leaf_source_nodes_it_replaced() -> void:
	var scene := Node3D.new()
	var nodes := _add_duplicates(scene, _small_mesh(), 30)

	MeshInstancingUtils.process_duplicate_mesh_instancing(scene)

	for node in nodes:
		assert_false(is_instance_valid(node), "source node should be freed")

	scene.free()


func test_keeps_a_source_node_that_has_children_but_drops_its_mesh() -> void:
	# The Blender authoring shape this protects: a "-col" collision mesh parented
	# under the visual mesh, which process_collision_meshes() turns into a
	# StaticBody3D child of that same visual node. Freeing the visual node would take
	# the prop's collision with it.
	var scene := Node3D.new()
	var nodes := _add_duplicates(scene, _small_mesh(), 30)
	var body := StaticBody3D.new()
	body.name = "Rock_0_collision"
	(nodes[0] as MeshInstance3D).add_child(body)

	MeshInstancingUtils.process_duplicate_mesh_instancing(scene)

	assert_true(is_instance_valid(nodes[0]), "node with children should survive")
	assert_true(is_instance_valid(body), "its collision body should survive")
	assert_null((nodes[0] as MeshInstance3D).mesh, "but it should no longer render")
	assert_false(is_instance_valid(nodes[1]), "childless siblings are still freed")

	scene.free()


func test_instance_transforms_include_parent_transforms() -> void:
	# Checked through transform_relative_to() rather than by reading the built
	# MultiMesh back: under the headless rendering driver
	# MultiMesh.get_instance_transform() always returns identity regardless of what
	# was set (see GlbUtils._row_to_transform's docstring for the same finding).
	var scene := Node3D.new()
	var group := Node3D.new()
	group.name = "PropGroup"
	group.position = Vector3(0.0, 10.0, 0.0)
	group.rotate_y(PI / 2.0)
	scene.add_child(group)
	var nodes := _add_duplicates(group, _small_mesh(), 30)

	# Rock_2 sits at (2, 0, 0) inside a parent rotated 90 degrees about Y and lifted
	# 10 units, so relative to the scene root it lands at (0, 10, -2).
	var relative := MeshInstancingUtils.transform_relative_to(nodes[2] as Node3D, scene)
	assert_almost_eq(relative.origin, Vector3(0.0, 10.0, -2.0), Vector3.ONE * 0.001)

	MeshInstancingUtils.process_duplicate_mesh_instancing(scene)
	var multimesh_instance := scene.get_node_or_null("Rock_0_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance, "the MultiMesh still lands at the scene root")
	assert_eq(multimesh_instance.multimesh.instance_count, 30)

	scene.free()


func test_leaves_groups_below_the_minimum_alone() -> void:
	var scene := Node3D.new()
	var nodes := _add_duplicates(scene, _small_mesh(), 5)

	var converted := MeshInstancingUtils.process_duplicate_mesh_instancing(scene)

	assert_eq(converted, 0)
	for node in nodes:
		assert_true(is_instance_valid(node))

	scene.free()


func test_does_not_group_nodes_with_different_meshes() -> void:
	var scene := Node3D.new()
	for i in 30:
		var node := MeshInstance3D.new()
		node.name = "Unique_%d" % i
		node.mesh = _small_mesh()  # a separate Mesh resource each time
		scene.add_child(node)

	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene), 0)

	scene.free()


func test_skips_meshes_large_enough_to_occlude_a_token() -> void:
	# OcclusionFadeManager only fades real MeshInstance3D surfaces, so a prop big
	# enough to hide a token must stay a real node.
	var scene := Node3D.new()
	var mesh := BoxMesh.new()
	mesh.size = LARGE_MESH_SIZE
	_add_duplicates(scene, mesh, 30, "Boulder")

	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene), 0)

	scene.free()


func test_accounts_for_node_scale_when_measuring_extent() -> void:
	# A small mesh scaled up 10x is just as capable of hiding a token.
	var scene := Node3D.new()
	var nodes := _add_duplicates(scene, _small_mesh(), 30)
	for node in nodes:
		(node as MeshInstance3D).scale = Vector3.ONE * 10.0

	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene), 0)

	scene.free()


func test_extent_guard_can_be_disabled() -> void:
	var scene := Node3D.new()
	var mesh := BoxMesh.new()
	mesh.size = LARGE_MESH_SIZE
	_add_duplicates(scene, mesh, 30, "Boulder")

	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene, 25, 0.0), 1)

	scene.free()


func test_skips_hidden_and_collision_suffixed_nodes() -> void:
	var scene := Node3D.new()
	var mesh := _small_mesh()
	var hidden := _add_duplicates(scene, mesh, 15, "Rock")
	for node in hidden:
		(node as Node3D).visible = false
	# The suffix is matched at the END of the name, which is where Blender's
	# collision naming convention puts it.
	var collision_meshes := _add_duplicates(scene, mesh, 15, "Boulder")
	for node in collision_meshes:
		(node as Node3D).name = String((node as Node3D).name) + "-col"

	var converted := MeshInstancingUtils.process_duplicate_mesh_instancing(scene, 10)

	assert_eq(converted, 0, "neither hidden nor collision meshes are candidates")
	for node in hidden + collision_meshes:
		assert_true(is_instance_valid(node))

	scene.free()


func test_skips_nodes_with_a_material_override() -> void:
	# This is also what keeps WaterGlbUtils' animated water planes out of a MultiMesh.
	var scene := Node3D.new()
	var nodes := _add_duplicates(scene, _small_mesh(), 30)
	for node in nodes:
		(node as MeshInstance3D).material_override = StandardMaterial3D.new()

	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene), 0)

	scene.free()


func test_skips_skinned_meshes() -> void:
	var scene := Node3D.new()
	var nodes := _add_duplicates(scene, _small_mesh(), 30)
	for node in nodes:
		(node as MeshInstance3D).skin = Skin.new()

	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene), 0)

	scene.free()


func test_skips_nodes_driven_by_an_animation_player() -> void:
	var scene := Node3D.new()
	_add_duplicates(scene, _small_mesh(), 30, "Windmill")

	var animation := Animation.new()
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Windmill_3:position"))
	var library := AnimationLibrary.new()
	library.add_animation("spin", animation)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	scene.add_child(player)
	player.add_animation_library("", library)

	var converted := MeshInstancingUtils.process_duplicate_mesh_instancing(scene)

	assert_eq(converted, 1, "the rest of the group is still worth collapsing")
	var multimesh_instance := scene.get_node_or_null("Windmill_0_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	assert_eq(multimesh_instance.multimesh.instance_count, 29, "the animated one is excluded")
	assert_not_null(scene.get_node_or_null("Windmill_3"), "and is left as a real node")

	scene.free()


func test_is_a_no_op_on_a_null_scene() -> void:
	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(null), 0)
