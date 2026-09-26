extends GutTest

## PropRows (utils/prop_rows.gd): hand-placed prop rows for the Place brush.


func _row_transform(row: PackedFloat32Array) -> Transform3D:
	return AuthoredScatter.transforms_from_rows(row, PackedInt32Array([0]))[0]


func test_upright_row_stands_on_y_at_the_point() -> void:
	var row := PropRows.make_row(
		Vector3(1, 0.2, -3), Vector3(0.3, 0.9, 0).normalized(), false, 0.7, 1.1
	)
	assert_eq(row.size(), MapDocument.ROW_STRIDE)
	var xform := _row_transform(row)
	assert_almost_eq(xform.origin, Vector3(1, 0.2, -3), Vector3.ONE * 1e-5)
	assert_almost_eq(PropRows.row_up(row), Vector3.UP, Vector3.ONE * 1e-5, "upright ignores slope")
	assert_almost_eq(xform.basis.get_scale(), Vector3.ONE * 1.1, Vector3.ONE * 1e-4)
	assert_almost_eq(PropRows.row_yaw(row), 0.7, 1e-4)


func test_normal_aligned_row_follows_the_ground() -> void:
	var normal := Vector3(0.3, 0.9, 0.1).normalized()
	var row := PropRows.make_row(Vector3.ZERO, normal, true, -1.2, 1.0)
	assert_almost_eq(PropRows.row_up(row), normal, Vector3.ONE * 1e-4)
	assert_almost_eq(PropRows.row_yaw(row), -1.2, 1e-4)


func test_with_yaw_turns_about_the_row_up_axis_only() -> void:
	var normal := Vector3(-0.2, 0.95, 0.2).normalized()
	var row := PropRows.make_row(Vector3(2, 0, 2), normal, true, 0.1, 0.9)
	var turned := PropRows.with_yaw(row, 2.5)
	assert_almost_eq(PropRows.row_up(turned), normal, Vector3.ONE * 1e-4, "tilt kept")
	assert_almost_eq(PropRows.row_yaw(turned), 2.5, 1e-4)
	assert_eq(turned[0], row[0])
	assert_eq(turned[7], row[7], "scale kept")


func test_scale_range_widens_narrow_species_for_heroes_and_honours_the_floor() -> void:
	var tree := PropRows.scale_range({"scale_spread": 0.15})
	assert_almost_eq(tree, Vector2(0.75, 1.25), Vector2.ONE * 1e-6)
	var wide := PropRows.scale_range({"scale_spread": 0.4})
	assert_almost_eq(wide, Vector2(0.6, 1.4), Vector2.ONE * 1e-6)
	var floored := PropRows.scale_range({"scale_spread": 0.3, "scale_floor": 0.8})
	assert_almost_eq(floored.x, 0.8, 1e-6)
	assert_almost_eq(PropRows.stepped_scale(1.2, 3.0, tree), 1.25, 1e-6, "clamped")
	assert_almost_eq(PropRows.stepped_scale(1.0, -2.0, tree), 0.9, 1e-6)


func test_pick_finds_the_nearest_prop_whose_footprint_holds_the_point() -> void:
	var rows := PackedFloat32Array()
	rows.append_array(PropRows.make_row(Vector3(0, 0, 0), Vector3.UP, false, 0.0, 1.0))
	rows.append_array(PropRows.make_row(Vector3(3, 0, 0), Vector3.UP, false, 0.0, 2.0))
	var radius_of := func(_asset: String) -> float: return 1.0
	var hit := PropRows.pick({"a": rows}, Vector2(0.4, 0.2), radius_of)
	assert_eq(hit.get("index"), 0)
	var scaled := PropRows.pick({"a": rows}, Vector2(4.8, 0), radius_of)
	assert_eq(scaled.get("index"), 1, "the footprint scales with the prop")
	assert_true(PropRows.pick({"a": rows}, Vector2(0, 1.5), radius_of).is_empty())


func test_replaced_and_removed_leave_other_rows_alone() -> void:
	var rows := PackedFloat32Array()
	for i in 3:
		rows.append_array(PropRows.make_row(Vector3(i, 0, 0), Vector3.UP, false, 0.0, 1.0))
	var fresh := PropRows.make_row(Vector3(9, 0, 9), Vector3.UP, false, 1.0, 1.0)
	var replaced := PropRows.replaced(rows, 1, fresh)
	assert_eq(PropRows.row_at(replaced, 1), fresh)
	assert_eq(PropRows.row_at(replaced, 0), PropRows.row_at(rows, 0))
	assert_eq(PropRows.row_at(rows, 1)[0], 1.0, "input untouched")
	var removed := PropRows.removed(rows, 1)
	assert_eq(removed.size(), 2 * MapDocument.ROW_STRIDE)
	assert_eq(PropRows.row_at(removed, 1), PropRows.row_at(rows, 2))
