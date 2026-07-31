extends GutTest

## Tests for VolumeOverlay static geometry helpers.


func test_shape_enum_values() -> void:
	assert_eq(VolumeOverlay.Shape.SPHERE, 0)
	assert_eq(VolumeOverlay.Shape.CYLINDER, 1)


func test_horizontal_ring_vertex_count() -> void:
	var verts := VolumeOverlay.build_horizontal_ring(Vector3.ZERO, 5.0, 0.0, 32)
	assert_eq(verts.size(), 64)  # 32 segments * 2 vertices per line


func test_horizontal_ring_correct_radius() -> void:
	var radius := 3.5
	var verts := VolumeOverlay.build_horizontal_ring(Vector3.ZERO, radius, 0.0, 16)
	for i in range(0, verts.size(), 2):
		var v: Vector3 = verts[i]
		var dist := Vector2(v.x, v.z).length()
		assert_almost_eq(dist, radius, 0.001)


func test_horizontal_ring_at_correct_y() -> void:
	var center := Vector3(1.0, 2.0, 3.0)
	var y_offset := 4.5
	var verts := VolumeOverlay.build_horizontal_ring(center, 1.0, y_offset, 8)
	for v: Vector3 in verts:
		assert_almost_eq(v.y, center.y + y_offset, 0.001)


func test_horizontal_ring_centered_on_xz() -> void:
	var center := Vector3(3.0, 0.0, -2.0)
	var radius := 2.0
	var verts := VolumeOverlay.build_horizontal_ring(center, radius, 0.0, 4)
	for i in range(0, verts.size(), 2):
		var v: Vector3 = verts[i]
		var xz_dist := Vector2(v.x - center.x, v.z - center.z).length()
		assert_almost_eq(xz_dist, radius, 0.001)


## Tests for VolumeOverlay instance geometry methods (_add_cylinder_geometry,
## _add_sphere_rings, _update_fill_mesh). These are exercised directly against a
## bare VolumeOverlay instance (no camera/viewport setup() call needed) by poking
## the private state the methods read/write — setup() is only needed for the
## camera-driven label positioning, which isn't under test here.


func test_cylinder_fill_position_sits_above_center() -> void:
	var overlay := VolumeOverlay.new()
	add_child_autofree(overlay)
	overlay._cylinder_mesh = CylinderMesh.new()
	overlay._fill_instance = autofree(MeshInstance3D.new())
	overlay._center = Vector3(1.0, 2.0, 3.0)
	overlay._radius = 4.0

	overlay._update_fill_mesh(VolumeOverlay.Shape.CYLINDER)

	# Cylinder is centered horizontally on _center but sits on top of it vertically —
	# its mesh-local origin is at half its height, so the fill instance position is
	# offset upward by half of CYLINDER_HEIGHT rather than being centered on _center.y.
	var expected_y := overlay._center.y + VolumeOverlay.CYLINDER_HEIGHT * 0.5
	assert_almost_eq(overlay._fill_instance.position.y, expected_y, 0.001)
	assert_almost_eq(overlay._fill_instance.position.x, overlay._center.x, 0.001)
	assert_almost_eq(overlay._fill_instance.position.z, overlay._center.z, 0.001)
	assert_almost_eq(overlay._cylinder_mesh.top_radius, 4.0, 0.001)
	assert_almost_eq(overlay._cylinder_mesh.bottom_radius, 4.0, 0.001)


func test_sphere_fill_position_centered_on_center() -> void:
	var overlay := VolumeOverlay.new()
	add_child_autofree(overlay)
	overlay._sphere_mesh = SphereMesh.new()
	overlay._fill_instance = autofree(MeshInstance3D.new())
	overlay._center = Vector3(1.0, 2.0, 3.0)
	overlay._radius = 4.0

	overlay._update_fill_mesh(VolumeOverlay.Shape.SPHERE)

	# Unlike the cylinder, the sphere fill sits exactly at _center — no vertical offset.
	assert_eq(overlay._fill_instance.position, overlay._center)
	assert_almost_eq(overlay._sphere_mesh.radius, 4.0, 0.001)
	assert_almost_eq(overlay._sphere_mesh.height, 8.0, 0.001)


func test_cylinder_wire_bottom_ring_at_center_height() -> void:
	var overlay := VolumeOverlay.new()
	add_child_autofree(overlay)
	overlay._wire_mesh = ImmediateMesh.new()
	overlay._center = Vector3(2.0, 5.0, -1.0)
	overlay._radius = 3.0

	overlay._wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	overlay._add_cylinder_geometry()
	overlay._wire_mesh.surface_end()

	var arrays := overlay._wire_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Bottom ring is the first RING_SEGMENTS*2 vertices, at _center.y exactly.
	var bottom_count := VolumeOverlay.RING_SEGMENTS * 2
	for i in range(bottom_count):
		var v: Vector3 = verts[i]
		assert_almost_eq(v.y, overlay._center.y, 0.001)
		var xz_dist := Vector2(v.x - overlay._center.x, v.z - overlay._center.z).length()
		assert_almost_eq(xz_dist, overlay._radius, 0.001)


func test_cylinder_wire_top_ring_at_center_plus_height() -> void:
	var overlay := VolumeOverlay.new()
	add_child_autofree(overlay)
	overlay._wire_mesh = ImmediateMesh.new()
	overlay._center = Vector3(2.0, 5.0, -1.0)
	overlay._radius = 3.0

	overlay._wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	overlay._add_cylinder_geometry()
	overlay._wire_mesh.surface_end()

	var arrays := overlay._wire_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Top ring is the second RING_SEGMENTS*2 vertices, at _center.y + CYLINDER_HEIGHT.
	var bottom_count := VolumeOverlay.RING_SEGMENTS * 2
	var top_count := VolumeOverlay.RING_SEGMENTS * 2
	var expected_y := overlay._center.y + VolumeOverlay.CYLINDER_HEIGHT
	for i in range(bottom_count, bottom_count + top_count):
		var v: Vector3 = verts[i]
		assert_almost_eq(v.y, expected_y, 0.001)
		var xz_dist := Vector2(v.x - overlay._center.x, v.z - overlay._center.z).length()
		assert_almost_eq(xz_dist, overlay._radius, 0.001)


func test_cylinder_wire_vertical_lines_span_full_height() -> void:
	var overlay := VolumeOverlay.new()
	add_child_autofree(overlay)
	overlay._wire_mesh = ImmediateMesh.new()
	overlay._center = Vector3(0.0, 1.0, 0.0)
	overlay._radius = 2.0

	overlay._wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	overlay._add_cylinder_geometry()
	overlay._wire_mesh.surface_end()

	var arrays := overlay._wire_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Vertical lines come after the two rings: each pair is (bottom point, top point)
	# at the same XZ location, spanning from _center.y to _center.y + CYLINDER_HEIGHT.
	var ring_count := VolumeOverlay.RING_SEGMENTS * 2 * 2
	for i in range(VolumeOverlay.VERTICAL_LINES):
		var bottom_v: Vector3 = verts[ring_count + i * 2]
		var top_v: Vector3 = verts[ring_count + i * 2 + 1]
		assert_almost_eq(bottom_v.y, overlay._center.y, 0.001)
		assert_almost_eq(top_v.y, overlay._center.y + VolumeOverlay.CYLINDER_HEIGHT, 0.001)
		assert_almost_eq(bottom_v.x, top_v.x, 0.001)
		assert_almost_eq(bottom_v.z, top_v.z, 0.001)


func test_sphere_vertical_rings_span_symmetric_around_center() -> void:
	var overlay := VolumeOverlay.new()
	add_child_autofree(overlay)
	overlay._wire_mesh = ImmediateMesh.new()
	overlay._center = Vector3(0.0, 4.0, 0.0)
	overlay._radius = 2.5

	overlay._wire_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	overlay._add_sphere_rings()
	overlay._wire_mesh.surface_end()

	var arrays := overlay._wire_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	# Unlike the cylinder (which only extends upward from _center), the sphere's
	# vertical rings are centered on _center: heights range from -radius to +radius.
	var min_y := INF
	var max_y := -INF
	for v: Vector3 in verts:
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
	assert_almost_eq(min_y, overlay._center.y - overlay._radius, 0.001)
	assert_almost_eq(max_y, overlay._center.y + overlay._radius, 0.001)
