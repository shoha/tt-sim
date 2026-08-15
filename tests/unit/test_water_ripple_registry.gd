extends GutTest

## Unit tests for WaterRippleRegistry -- register/unregister and the fixed-size
## disturbance array building used to feed water.gdshader's water_disturbance_points
## uniform (see WaterZone._process()).


func before_each() -> void:
	WaterRippleRegistry.clear()


func test_register_then_build_array_includes_the_tokens_position() -> void:
	var token := Node3D.new()
	add_child_autofree(token)
	token.global_position = Vector3(3.0, 0.0, 4.0)

	WaterRippleRegistry.register(token.get_instance_id(), token)
	var points := WaterRippleRegistry.build_disturbance_array()

	assert_eq(points.size(), WaterRippleRegistry.MAX_DISTURBANCE_POINTS)
	assert_eq(points[0], Vector4(3.0, 4.0, 0.0, 1.0))
	assert_eq(points[1], Vector4(0.0, 0.0, 0.0, 0.0))


func test_unregister_removes_the_token_from_the_array() -> void:
	var token := Node3D.new()
	add_child_autofree(token)
	var id := token.get_instance_id()

	WaterRippleRegistry.register(id, token)
	WaterRippleRegistry.unregister(id)
	var points := WaterRippleRegistry.build_disturbance_array()

	for point in points:
		assert_eq(point, Vector4(0.0, 0.0, 0.0, 0.0))


func test_unregister_unknown_id_is_a_no_op() -> void:
	WaterRippleRegistry.unregister(999999)

	assert_eq(
		WaterRippleRegistry.build_disturbance_array().size(),
		WaterRippleRegistry.MAX_DISTURBANCE_POINTS
	)


func test_build_disturbance_array_caps_at_max_points() -> void:
	var tokens: Array[Node3D] = []
	for i in range(WaterRippleRegistry.MAX_DISTURBANCE_POINTS + 3):
		var token := Node3D.new()
		add_child_autofree(token)
		token.global_position = Vector3(float(i), 0.0, 0.0)
		tokens.append(token)
		WaterRippleRegistry.register(token.get_instance_id(), token)

	var points := WaterRippleRegistry.build_disturbance_array()

	assert_eq(points.size(), WaterRippleRegistry.MAX_DISTURBANCE_POINTS)
	for point in points:
		assert_eq(point.w, 1.0)


func test_build_disturbance_array_skips_freed_nodes() -> void:
	var token := Node3D.new()
	# Not added to tree, freed immediately -- simulates a token deleted while submerged
	WaterRippleRegistry.register(token.get_instance_id(), token)
	token.free()

	var points := WaterRippleRegistry.build_disturbance_array()

	for point in points:
		assert_eq(point, Vector4(0.0, 0.0, 0.0, 0.0))


func test_register_returns_true_only_on_first_registration() -> void:
	var token := Node3D.new()
	add_child_autofree(token)
	var id := token.get_instance_id()

	var first := WaterRippleRegistry.register(id, token)
	var second := WaterRippleRegistry.register(id, token)

	assert_true(first)
	assert_false(second)


func test_unregister_returns_true_only_when_refcount_reaches_zero() -> void:
	var token := Node3D.new()
	add_child_autofree(token)
	var id := token.get_instance_id()

	WaterRippleRegistry.register(id, token)
	WaterRippleRegistry.register(id, token)

	var first_unregister := WaterRippleRegistry.unregister(id)
	assert_false(first_unregister)
	assert_eq(WaterRippleRegistry.build_disturbance_array()[0].w, 1.0)

	var second_unregister := WaterRippleRegistry.unregister(id)
	assert_true(second_unregister)
	for point in WaterRippleRegistry.build_disturbance_array():
		assert_eq(point.w, 0.0)
