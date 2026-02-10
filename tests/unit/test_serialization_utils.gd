extends GutTest

## Unit tests for SerializationUtils.


func test_vec3_to_dict_zero() -> void:
	var result = SerializationUtils.vec3_to_dict(Vector3.ZERO)
	assert_eq(result, {"x": 0.0, "y": 0.0, "z": 0.0})


func test_vec3_to_dict_values() -> void:
	var result = SerializationUtils.vec3_to_dict(Vector3(1.5, -2.3, 4.0))
	assert_almost_eq(result["x"], 1.5, 0.001)
	assert_almost_eq(result["y"], -2.3, 0.001)
	assert_almost_eq(result["z"], 4.0, 0.001)


func test_dict_to_vec3_full() -> void:
	var result = SerializationUtils.dict_to_vec3({"x": 1.0, "y": 2.0, "z": 3.0})
	assert_eq(result, Vector3(1.0, 2.0, 3.0))


func test_dict_to_vec3_empty_uses_default() -> void:
	var result = SerializationUtils.dict_to_vec3({})
	assert_eq(result, Vector3.ZERO)


func test_dict_to_vec3_custom_default() -> void:
	var result = SerializationUtils.dict_to_vec3({}, Vector3.ONE)
	assert_eq(result, Vector3.ONE)


func test_dict_to_vec3_partial_keys() -> void:
	var result = SerializationUtils.dict_to_vec3({"x": 5.0}, Vector3.ONE)
	assert_eq(result, Vector3(5.0, 1.0, 1.0))


func test_vec3_round_trip() -> void:
	var original = Vector3(1.23, -4.56, 7.89)
	var round_tripped = SerializationUtils.dict_to_vec3(
		SerializationUtils.vec3_to_dict(original)
	)
	assert_almost_eq(round_tripped.x, original.x, 0.0001)
	assert_almost_eq(round_tripped.y, original.y, 0.0001)
	assert_almost_eq(round_tripped.z, original.z, 0.0001)


func test_color_to_dict() -> void:
	var result = SerializationUtils.color_to_dict(Color(0.5, 0.6, 0.7, 0.8))
	assert_almost_eq(result["r"], 0.5, 0.001)
	assert_almost_eq(result["g"], 0.6, 0.001)
	assert_almost_eq(result["b"], 0.7, 0.001)
	assert_almost_eq(result["a"], 0.8, 0.001)


func test_dict_to_color_full() -> void:
	var result = SerializationUtils.dict_to_color(
		{"r": 0.1, "g": 0.2, "b": 0.3, "a": 1.0}
	)
	assert_almost_eq(result.r, 0.1, 0.001)
	assert_almost_eq(result.g, 0.2, 0.001)
	assert_almost_eq(result.b, 0.3, 0.001)
	assert_almost_eq(result.a, 1.0, 0.001)


func test_color_round_trip() -> void:
	var original = Color(0.12, 0.34, 0.56, 0.78)
	var round_tripped = SerializationUtils.dict_to_color(
		SerializationUtils.color_to_dict(original)
	)
	assert_almost_eq(round_tripped.r, original.r, 0.0001)
	assert_almost_eq(round_tripped.g, original.g, 0.0001)
	assert_almost_eq(round_tripped.b, original.b, 0.0001)
	assert_almost_eq(round_tripped.a, original.a, 0.0001)
