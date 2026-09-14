extends GutTest


func test_evaluates_arithmetic() -> void:
	var result := BridgeEval.evaluate("1 + 2", null)
	assert_true(result["ok"])
	assert_eq(result["value"], 3)


func test_evaluates_against_a_base_instance() -> void:
	var node := Node.new()
	node.name = "Probe"
	autofree(node)
	var result := BridgeEval.evaluate("name", node)
	assert_true(result["ok"])
	assert_eq(result["value"], "Probe")


func test_reports_parse_errors() -> void:
	var result := BridgeEval.evaluate("1 +", null)
	assert_false(result["ok"])
	assert_string_contains(result["error"], "Parse error")


func test_reports_execution_errors() -> void:
	var node := Node.new()
	autofree(node)
	var result := BridgeEval.evaluate("no_such_method()", node)
	assert_false(result["ok"])


func test_serializes_vector3() -> void:
	var value: Variant = BridgeEval.to_json_safe(Vector3(1.0, 2.0, 3.0), 0)
	assert_eq(value, {"x": 1.0, "y": 2.0, "z": 3.0})


func test_serializes_vector2() -> void:
	var value: Variant = BridgeEval.to_json_safe(Vector2(4.0, 5.0), 0)
	assert_eq(value, {"x": 4.0, "y": 5.0})


func test_serializes_color() -> void:
	var value: Variant = BridgeEval.to_json_safe(Color(1.0, 0.5, 0.25, 1.0), 0)
	assert_eq(value, {"r": 1.0, "g": 0.5, "b": 0.25, "a": 1.0})


func test_serializes_nested_dictionary() -> void:
	var value: Variant = BridgeEval.to_json_safe({"pos": Vector2(1.0, 2.0)}, 0)
	assert_eq(value, {"pos": {"x": 1.0, "y": 2.0}})


func test_truncates_long_arrays() -> void:
	var source: Array = []
	for i in range(BridgeEval.MAX_ARRAY_ITEMS + 10):
		source.append(i)
	var value: Array = BridgeEval.to_json_safe(source, 0)
	assert_eq(value.size(), BridgeEval.MAX_ARRAY_ITEMS + 1)
	assert_string_contains(str(value[-1]), "more")


func test_stops_at_maximum_depth() -> void:
	var deep: Variant = "leaf"
	for i in range(BridgeEval.MAX_DEPTH + 2):
		deep = {"nested": deep}
	var value: Variant = BridgeEval.to_json_safe(deep, 0)
	assert_string_contains(JSON.stringify(value), "max depth")


func test_serializes_a_node_as_its_path_and_class() -> void:
	var node := Node.new()
	node.name = "Probe"
	add_child_autofree(node)
	var value: Dictionary = BridgeEval.to_json_safe(node, 0)
	assert_string_contains(str(value["node"]), "Probe")
	assert_eq(value["type"], "Node")


func test_result_survives_json_stringify() -> void:
	var result := BridgeEval.evaluate("Vector3(1, 2, 3)", null)
	assert_true(result["ok"])
	var encoded := JSON.stringify(result["value"])
	assert_string_contains(encoded, '"x"')
