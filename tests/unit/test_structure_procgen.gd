extends GutTest

## StructureProcgen copies two of procgen's values so the start-up can check recipes and size walls
## without compiling the structure registry (perf audit boot). These pin the copies to procgen, so a
## new node type or street species fails here until the copy follows.


func test_type_ids_match_the_structure_registry() -> void:
	assert_eq(
		StructureProcgen.STRUCTURE_TYPE_IDS,
		ProcgenStructureRegistry.new().type_ids(),
		"StructureProcgen.STRUCTURE_TYPE_IDS must list ProcgenStructureRegistry's types in order"
	)


func test_row_preset_modern_matches_procgen() -> void:
	assert_eq(StructureProcgen.ROW_PRESET_MODERN, ProcgenRow.PRESET_MODERN)


func test_type_names_answers_like_the_registry() -> void:
	var names := StructureProcgen.type_names()
	var registry := StructureProcgen.new_registry()
	for id in ["guide", "building", "street_row", "output", "no_such_type", ""]:
		assert_eq(names.has_type(id), registry.has_type(id), "has_type(%s)" % id)
	assert_null(names.get_type("building"), "TypeNames builds no node")
	assert_true(registry is ProcgenStructureRegistry)


func test_row_helpers_forward_to_procgen() -> void:
	var lot := {"side": 1.0, "index": 3}
	assert_eq(StructureProcgen.row_lot_path(lot), ProcgenRow.lot_path(lot))
	assert_true(StructureProcgen.new_row_node() is RowNode)
