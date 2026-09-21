extends GutTest

## Unit tests for GlbUtils.process_collision_meshes() -- the Godot "-col"/"-colonly"
## suffix convention, reimplemented here because GLTFDocument does not apply it to
## runtime-loaded GLBs the way the editor's import pipeline does.
##
## The keeps-visual half of the convention is the point of most of these: a map whose
## terrain object is simply named "<something>-col" used to load with collision and no
## visible terrain at all.


func _mesh_node(node_name: String, mesh: Mesh = null) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	mesh_node.mesh = mesh if mesh != null else BoxMesh.new()
	return mesh_node


func _static_bodies(root: Node) -> Array:
	return root.get_children().filter(func(child): return child is StaticBody3D)


func _shape_of(body: StaticBody3D) -> Shape3D:
	return (body.get_child(0) as CollisionShape3D).shape


func test_col_suffix_keeps_the_mesh_visible() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Plane-col")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_true(is_instance_valid(mesh_node), "-col must not free its visual mesh")
	assert_true(mesh_node.visible, "-col adds collision to a mesh that stays visible")
	assert_eq(_static_bodies(root).size(), 1)

	root.free()


func test_col_suffix_builds_a_trimesh_shape() -> void:
	var root := Node3D.new()
	root.add_child(_mesh_node("Plane-col"))

	GlbUtils.process_collision_meshes(root, true)

	var body := _static_bodies(root)[0] as StaticBody3D
	assert_eq(body.name, "Plane_collision")
	assert_true(_shape_of(body) is ConcavePolygonShape3D)

	root.free()


func test_convcol_suffix_keeps_the_mesh_visible_with_a_convex_shape() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Rock-convcol")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_true(is_instance_valid(mesh_node))
	assert_true(mesh_node.visible)
	assert_true(_shape_of(_static_bodies(root)[0]) is ConvexPolygonShape3D)

	root.free()


func test_trimesh_suffix_keeps_the_mesh_visible() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Floor-trimesh")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_true(is_instance_valid(mesh_node))
	assert_true(mesh_node.visible)
	assert_true(_shape_of(_static_bodies(root)[0]) is ConcavePolygonShape3D)

	root.free()


func test_colonly_suffix_removes_the_mesh() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Plane-colonly")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_false(is_instance_valid(mesh_node), "-colonly is collision only")
	assert_eq(_static_bodies(root).size(), 1)

	root.free()


func test_convcolonly_suffix_removes_the_mesh() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Crate-convcolonly")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_false(is_instance_valid(mesh_node))
	assert_true(_shape_of(_static_bodies(root)[0]) is ConvexPolygonShape3D)

	root.free()


func test_convco_short_form_removes_the_mesh_like_convcolonly() -> void:
	# "-convco" is our own short form for "-convcolonly". It contains no "only", so the
	# previous suffix.contains("only") check misread it as a keeps-visual suffix.
	var root := Node3D.new()
	var mesh_node := _mesh_node("Crate-convco")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_false(is_instance_valid(mesh_node), "-convco is the short form of -convcolonly")
	assert_true(_shape_of(_static_bodies(root)[0]) is ConvexPolygonShape3D)

	root.free()


func test_token_path_keeps_a_col_mesh_visible_and_adds_a_collision_shape() -> void:
	# create_static_bodies = false is the token path: a CollisionShape3D sibling is
	# added for the factory to reparent onto a RigidBody3D, but the same visibility
	# rule applies.
	var root := Node3D.new()
	var mesh_node := _mesh_node("Mini-col")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, false)

	assert_true(is_instance_valid(mesh_node))
	assert_true(mesh_node.visible)
	assert_eq(
		root.get_children().filter(func(child): return child is CollisionShape3D).size(), 1
	)

	root.free()


func test_token_path_still_removes_a_colonly_mesh() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Mini-colonly")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, false)

	assert_false(is_instance_valid(mesh_node))

	root.free()


func test_unsuffixed_mesh_is_left_completely_alone() -> void:
	var root := Node3D.new()
	var mesh_node := _mesh_node("Terrain")
	root.add_child(mesh_node)

	GlbUtils.process_collision_meshes(root, true)

	assert_true(is_instance_valid(mesh_node))
	assert_true(mesh_node.visible)
	assert_eq(root.get_child_count(), 1)

	root.free()
