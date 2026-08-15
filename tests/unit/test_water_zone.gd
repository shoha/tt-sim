extends GutTest

## Unit tests for WaterZone.create_for_mesh() -- the Area3D shape/layer setup that
## detects tokens overlapping a `-water` mesh's footprint (see the design spec's
## "Token water detection" section).


func test_creates_a_box_shape_matching_the_mesh_footprint() -> void:
	var mesh_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 6.0)
	mesh_node.mesh = plane

	var zone := WaterZone.create_for_mesh(mesh_node)
	add_child_autofree(zone)

	assert_not_null(zone)
	var collision_shape := zone.get_child(0) as CollisionShape3D
	assert_not_null(collision_shape)
	var shape := collision_shape.shape as BoxShape3D
	assert_not_null(shape)
	assert_almost_eq(shape.size.x, 4.0, 0.01)
	assert_almost_eq(shape.size.z, 6.0, 0.01)
	assert_almost_eq(shape.size.y, WaterZone.VERTICAL_BAND_HEIGHT, 0.01)

	mesh_node.free()


func test_sets_token_layer_mask_and_monitoring_flags() -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = PlaneMesh.new()

	var zone := WaterZone.create_for_mesh(mesh_node)
	add_child_autofree(zone)

	assert_eq(zone.collision_mask, WaterZone.TOKEN_COLLISION_LAYER_MASK)
	assert_eq(zone.collision_layer, 0)
	assert_true(zone.monitoring)
	assert_false(zone.monitorable)

	mesh_node.free()


func test_returns_null_for_a_degenerate_mesh_footprint() -> void:
	var mesh_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.0, 0.0)
	mesh_node.mesh = plane

	var zone := WaterZone.create_for_mesh(mesh_node)

	assert_null(zone)

	mesh_node.free()


func test_returns_null_when_mesh_node_has_no_mesh() -> void:
	var mesh_node := MeshInstance3D.new()

	var zone := WaterZone.create_for_mesh(mesh_node)

	assert_null(zone)

	mesh_node.free()
