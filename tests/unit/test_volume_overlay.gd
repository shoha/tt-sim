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
