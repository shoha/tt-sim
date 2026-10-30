extends GutTest

## The courtyard structures (courtyard_rows, 2026-10-29): coaching_inn, siheyuan and hof_farm, the
## core rows built from procgen's courtyard styles. Large size limits (least side 9 m, default
## about 14 by 12 m), `regional` so no street picks one, pinned at their default rectangle.
## Summary: docs/systems/structures.md "Courtyards".

const REFS: Array[String] = ["core:coaching_inn", "core:siheyuan", "core:hof_farm"]

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _row(ref: String) -> Dictionary:
	return LibraryStructureStore.structure(ref)


func test_the_rows_are_regional_courtyards_with_large_limits() -> void:
	for ref in REFS:
		var row := _row(ref)
		assert_false(row.is_empty(), ref)
		assert_true(StreetSplit.REGIONAL_TAG in (row["tags"] as Array), "%s is regional" % ref)
		assert_true("courtyard" in (row["tags"] as Array), "%s is a courtyard" % ref)
		assert_gte(float(row["min_side_m"]), 9.0, ref)
		assert_gte(StructurePlacement.default_size(row).x, 9.0, ref)
		assert_gte(StructurePlacement.default_size(row).y, 9.0, ref)
		assert_lte(float(row["max_side_m"]), 30.0, "sane for a tabletop map")
		assert_lte(float(row["max_area_m2"]), 400.0, "sane for a tabletop map")
	assert_true("inn" in (_row("core:coaching_inn")["tags"] as Array))
	assert_true("farm" in (_row("core:hof_farm")["tags"] as Array))
	assert_eq(StructurePlacement.default_size(_row("core:coaching_inn")), Vector2(14, 12))


func test_a_street_split_never_picks_a_courtyard() -> void:
	for region: Array[String] in [
		[] as Array[String],
		["english"] as Array[String],
		["dutch"] as Array[String],
		["nordic", "alpine"] as Array[String],
		["desert"] as Array[String],
	]:
		for row in StreetSplit.candidates(region):
			assert_false(String(row["ref"]) in REFS, "%s offered to %s" % [row["ref"], region])


func test_the_pin_is_the_default_rectangle_and_other_rows_keep_six_by_four() -> void:
	for ref in REFS:
		var plan := StructurePlacement.pin_plan(_row(ref))
		var box := Rect2(plan[0], Vector2.ZERO)
		for p in plan:
			box = box.expand(p)
		assert_eq(plan.size(), 4, ref)
		assert_eq(box.size, StructurePlacement.default_size(_row(ref)), ref)
	assert_eq(StructurePlacement.pin_plan(_row("core:inn_gallery")).size(), 4)
	assert_eq(StructurePlacement.pin_plan(_row("core:inn_gallery"))[1], Vector2(3, -2))


func test_a_drag_clamps_up_to_the_least_side_and_down_to_the_largest() -> void:
	for ref in REFS:
		var row := _row(ref)
		var low := float(row["min_side_m"])
		var tiny := StructurePlacement.corner_plan(Vector2.ZERO, Vector2(1.0, 0.5), 0.0, row)
		assert_eq(tiny["size"], Vector2(low, low), "%s: a tiny drag clamps up" % ref)
		var huge := StructurePlacement.corner_plan(Vector2.ZERO, Vector2(80.0, 80.0), 0.0, row)
		var size: Vector2 = huge["size"]
		assert_lte(size.x * size.y, float(row["max_area_m2"]) + 0.01, "%s: area capped" % ref)
		assert_lte(maxf(size.x, size.y), float(row["max_side_m"]) + 0.01)
		assert_gte(minf(size.x, size.y), low - 0.01)
		var strip := StructurePlacement.corner_plan(Vector2.ZERO, Vector2(30.0, 2.0), 0.0, row)
		assert_gte((strip["size"] as Vector2).y, low, "%s: a thin strip is widened" % ref)


func test_a_click_and_a_minimum_drag_lay_a_built_courtyard() -> void:
	var editor := _editor()
	for ref in REFS:
		var brush := StructureBrush.new()
		brush.pick(ref)
		brush.track(editor, Vector3(0, 0, 0), 0.1)
		assert_eq(brush.ghost_plan().size(), 4, ref)
		assert_eq(ProcgenPlan.problems(brush.ghost_plan()), [] as Array[String], ref)
		var spot := StructurePlacement.nearest_legal(
			_doc, Vector2(0, 0), StructurePlacement.default_size(_row(ref)), 0.0
		)
		assert_eq(spot["problem"], "", ref)
		var plain := StructureGeometry.build_one(
			_doc,
			Structure.make(
				1, ref, StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0), 5
			)
		)
		var full := StructureGeometry.build_one(_doc, Structure.make(1, ref, spot["plan"], 5))
		var least := float(_row(ref)["min_side_m"])
		var small := StructureGeometry.build_one(
			_doc,
			Structure.make(
				1, ref, StructurePlacement.rect_plan(Vector2.ZERO, Vector2(least, least), 0.0), 5
			)
		)
		assert_eq(full.problem, "", ref)
		assert_eq(small.problem, "", ref)
		assert_gt(
			StructureGeometry.triangle_count(full),
			StructureGeometry.triangle_count(plain) * 2,
			"%s at its default is a courtyard, not the plain building" % ref
		)
		assert_gt(
			StructureGeometry.triangle_count(small),
			StructureGeometry.triangle_count(plain) * 2,
			"%s at its least side is still a courtyard" % ref
		)
