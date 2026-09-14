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


func test_serializes_vector2i() -> void:
	var value: Variant = BridgeEval.to_json_safe(Vector2i(4, 5), 0)
	assert_eq(value, {"x": 4.0, "y": 5.0})


func test_serializes_vector3i() -> void:
	var value: Variant = BridgeEval.to_json_safe(Vector3i(1, 2, 3), 0)
	assert_eq(value, {"x": 1.0, "y": 2.0, "z": 3.0})


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


## The regression these guard: `truthy` used to be re-derived by the bridge from the serialized
## `value`, where `Vector2.ZERO` is the non-empty Dictionary {"x": 0.0, "y": 0.0} and therefore
## truthy -- the opposite of what GDScript says about the value itself. Truthiness is now computed
## on the raw Variant before serialization, so a zero vector and the default Color must report false
## while their own serialized forms are truthy Dictionaries.
func test_zero_vector_is_not_truthy() -> void:
	# Spelled with the constructor, not `Vector2.ZERO`: Godot's Expression cannot resolve a built-in
	# type's named constants and fails to parse that form. The Variant is identical either way.
	var result := BridgeEval.evaluate("Vector2(0, 0)", null)
	assert_true(result["ok"])
	assert_false(result["truthy"], "Vector2.ZERO is false in GDScript")
	assert_eq(
		result["value"], {"x": 0.0, "y": 0.0}, "but serializes to a truthy non-empty Dictionary"
	)


func test_zero_vector_variant_is_not_truthy() -> void:
	assert_false(BridgeEval.is_truthy(Vector2.ZERO))
	assert_false(BridgeEval.is_truthy(Vector3.ZERO))


func test_nonzero_vector_is_truthy() -> void:
	var result := BridgeEval.evaluate("Vector2(1, 0)", null)
	assert_true(result["ok"])
	assert_true(result["truthy"])


func test_empty_array_is_not_truthy() -> void:
	var result := BridgeEval.evaluate("[]", null)
	assert_true(result["ok"])
	assert_false(result["truthy"])


func test_non_empty_array_is_truthy() -> void:
	var result := BridgeEval.evaluate("[1, 2]", null)
	assert_true(result["ok"])
	assert_true(result["truthy"])


## GDScript's zero Color is the DEFAULT one -- opaque black, alpha 1 -- because Variant truthiness
## compares against `Color()`. A fully transparent black is therefore truthy, which is the opposite
## of what it looks like. Asserted both ways so the surprising half is recorded rather than
## rediscovered.
func test_color_truthiness_follows_the_default_color_not_transparency() -> void:
	var opaque_black := BridgeEval.evaluate("Color(0, 0, 0, 1)", null)
	assert_true(opaque_black["ok"])
	assert_false(opaque_black["truthy"], "Color(0, 0, 0, 1) equals Color() and is false")
	assert_eq(
		opaque_black["value"],
		{"r": 0.0, "g": 0.0, "b": 0.0, "a": 1.0},
		"but serializes to a truthy non-empty Dictionary"
	)

	var transparent := BridgeEval.evaluate("Color(0, 0, 0, 0)", null)
	assert_true(transparent["ok"])
	assert_true(transparent["truthy"], "a transparent Color differs from Color() and is true")


func test_empty_string_and_dictionary_are_not_truthy() -> void:
	assert_false(BridgeEval.evaluate('""', null)["truthy"])
	assert_false(BridgeEval.evaluate("{}", null)["truthy"])


func test_non_empty_string_and_dictionary_are_truthy() -> void:
	assert_true(BridgeEval.evaluate('"x"', null)["truthy"])
	assert_true(BridgeEval.evaluate('{"a": 1}', null)["truthy"])


func test_booleans_and_numbers_follow_gdscript_truthiness() -> void:
	assert_true(BridgeEval.evaluate("true", null)["truthy"])
	assert_false(BridgeEval.evaluate("false", null)["truthy"])
	assert_true(BridgeEval.evaluate("1", null)["truthy"])
	assert_false(BridgeEval.evaluate("0", null)["truthy"])
	assert_false(BridgeEval.evaluate("null", null)["truthy"])


func test_result_survives_json_stringify() -> void:
	var result := BridgeEval.evaluate("Vector3(1, 2, 3)", null)
	assert_true(result["ok"])
	var encoded := JSON.stringify(result["value"])
	assert_string_contains(encoded, '"x"')
