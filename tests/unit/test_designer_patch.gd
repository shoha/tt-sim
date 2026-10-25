extends GutTest

## DesignerPatch: the reversible edits behind the biome designer's undo stack. Every op's
## inverse, applied, restores the document exactly; values are copied, not shared.


func _doc() -> Dictionary:
	return {
		"name": "Meadow",
		"rules": [{"key": "oak", "weight": 1, "tags": ["a"]}, {"key": "elm", "weight": 2}],
		"ground": {"surface": "grass"},
	}


func test_set_and_its_inverse_restore_the_value() -> void:
	var doc := _doc()
	var before := doc.duplicate(true)
	var undo := DesignerPatch.apply(doc, [DesignerPatch.set_op(["rules", 0, "weight"], 5)])
	assert_eq(doc["rules"][0]["weight"], 5)
	DesignerPatch.apply(doc, undo)
	assert_eq(doc, before)


func test_set_of_a_new_key_is_undone_by_erasing_it() -> void:
	var doc := _doc()
	var undo := DesignerPatch.apply(doc, [DesignerPatch.set_op(["rules", 1, "habit"], {"water": "bank"})])
	assert_true(doc["rules"][1].has("habit"))
	assert_eq(undo[0]["op"], "erase")
	DesignerPatch.apply(doc, undo)
	assert_false(doc["rules"][1].has("habit"))


func test_erase_and_its_inverse() -> void:
	var doc := _doc()
	var before := doc.duplicate(true)
	var undo := DesignerPatch.apply(doc, [DesignerPatch.erase_op(["ground", "surface"])])
	assert_false(doc["ground"].has("surface"))
	DesignerPatch.apply(doc, undo)
	assert_eq(doc, before)


func test_insert_remove_and_move_round_trip() -> void:
	var doc := _doc()
	var before := doc.duplicate(true)
	var ops: Array = [
		DesignerPatch.insert_op(["rules"], 1, {"key": "fir"}),
		DesignerPatch.move_op(["rules"], 0, 2),
		DesignerPatch.remove_op(["rules"], 0),
	]
	var undo := DesignerPatch.apply(doc, ops)
	var keys: Array = []
	for rule: Dictionary in doc["rules"]:
		keys.append(rule["key"])
	assert_eq(keys, ["elm", "oak"], "inserted, moved to the end, first removed")
	DesignerPatch.apply(doc, undo)
	assert_eq(doc, before)


func test_values_are_copied_in_and_out() -> void:
	var doc := _doc()
	var value := {"key": "pine", "tags": ["x"]}
	DesignerPatch.apply(doc, [DesignerPatch.insert_op(["rules"], 0, value)])
	value["tags"].append("y")
	assert_eq(doc["rules"][0]["tags"], ["x"], "the document does not share the caller's value")
	var undo := DesignerPatch.apply(doc, [DesignerPatch.remove_op(["rules"], 0)])
	doc["rules"].append({"key": "z"})
	assert_eq(undo[0]["value"]["tags"], ["x"])


func test_a_bad_path_is_a_noop_inverse() -> void:
	var doc := _doc()
	var before := doc.duplicate(true)
	var undo := DesignerPatch.apply(
		doc,
		[
			DesignerPatch.set_op(["rules", 9, "weight"], 1),
			DesignerPatch.erase_op(["ground", "nothing"]),
			DesignerPatch.remove_op(["rules"], 9),
			DesignerPatch.insert_op(["name"], 0, 1),
		]
	)
	assert_eq(doc, before)
	for op: Dictionary in undo:
		assert_eq(op["op"], "noop")


func test_get_at_walks_keys_and_indices() -> void:
	var doc := _doc()
	assert_eq(DesignerPatch.get_at(doc, ["rules", 1, "key"]), "elm")
	assert_eq(DesignerPatch.get_at(doc, ["rules", 5, "key"], "none"), "none")
	assert_eq(DesignerPatch.get_at(doc, []), doc)
