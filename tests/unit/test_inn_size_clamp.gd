extends GutTest

## The coaching inn stops at its style limits (check G4, 2026-10-31): its index row (min_side_m 9,
## max_side_m 24, max_area_m2 330, default 14 x 12) is the range, an undersized or oversized
## footprint clamps to a legal size, and every clamped footprint builds valid, both through
## StructurePlacement and through the Buildings brush's drag.

const INN := "core:coaching_inn"

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _row() -> Dictionary:
	return LibraryStructureStore.structure(INN)


## Builds the inn on a lot of `size`; the result's problem is "" when it is a valid build.
func _build(size: Vector2) -> Dictionary:
	var plan := StructurePlacement.lot_plan(
		Vector2.ZERO, size, 0.0, StructurePlacement.sides_of(_row())
	)
	return StructureGeometry.build_one(_doc, Structure.make(1, INN, plan, 5))


func _assert_legal(size: Vector2, label: String) -> void:
	var row := _row()
	assert_gte(size.x, float(row.min_side_m) - 0.001, "%s: x not under the least side" % label)
	assert_gte(size.y, float(row.min_side_m) - 0.001, "%s: y not under the least side" % label)
	assert_lte(size.x, float(row.max_side_m) + 0.001, "%s: x not over the largest side" % label)
	assert_lte(size.y, float(row.max_side_m) + 0.001, "%s: y not over the largest side" % label)
	assert_lte(size.x * size.y, float(row.max_area_m2) + 0.01, "%s: area within its limit" % label)
	var parts := _build(size)
	assert_eq(parts.problem, "", "%s: the clamped lot builds valid" % label)
	assert_gt(StructureGeometry.triangle_count(parts), 0, "%s: and has geometry" % label)


func test_the_row_holds_the_index_limits() -> void:
	var row := _row()
	assert_eq(float(row.min_side_m), 9.0)
	assert_eq(float(row.max_side_m), 24.0)
	assert_eq(float(row.max_area_m2), 330.0)
	assert_eq(StructurePlacement.default_size(row), Vector2(14, 12))


func test_nine_by_eight_is_held_to_the_least_side() -> void:
	var got := StructurePlacement.clamp_size(Vector2(9, 8), _row())
	assert_eq(got, Vector2(9, 9), "the 8 m side comes up to 9")
	_assert_legal(got, "9 x 8")


func test_oversize_and_undersize_clamp_to_legal_sizes_that_build() -> void:
	var cases := {
		"tiny": Vector2(1, 1),
		"thin": Vector2(40, 2),
		"wide": Vector2(80, 12),
		"huge": Vector2(60, 60),
		"edge": Vector2(24, 24),
		"fits": Vector2(20, 16),
	}
	for label: String in cases:
		var asked: Vector2 = cases[label]
		var got := StructurePlacement.clamp_size(asked, _row())
		gut.p("%s %s -> %s (area %.0f)" % [label, str(asked), str(got), got.x * got.y])
		_assert_legal(got, label)
	assert_eq(
		StructurePlacement.clamp_size(Vector2(20, 16), _row()),
		Vector2(20, 16),
		"a legal size stays"
	)
	assert_eq(StructurePlacement.clamp_size(Vector2(80, 12), _row()).x, 24.0, "the largest side")
	var huge := StructurePlacement.clamp_size(Vector2(60, 60), _row())
	assert_almost_eq(huge.x, huge.y, 0.001, "the shape is kept while the area comes down")


func test_the_brush_drag_clamps_the_inn_and_the_noted_size_matches() -> void:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	var history := AuthoringHistory.new()
	map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	map.add_child(node)
	var editor := AuthoringEditor.create(_doc, map, history)
	editor.scatter.attach_document(_doc)
	var brush := StructureBrush.new()
	brush.pick(INN)
	brush.begin(Vector3(-5.0, 0.0, -5.0))
	brush.track(editor, Vector3(-3.0, 0.0, -4.0), 0.0)
	assert_eq(brush.ghost_size, Vector2(9, 9), "a 2 x 1 m drag lays the least inn")
	brush.cancel(null)
	brush.begin(Vector3(-17.0, 0.0, -17.0))
	brush.track(editor, Vector3(17.0, 0.0, 17.0), 0.0)
	assert_lte(brush.ghost_size.x * brush.ghost_size.y, 330.01, "a 34 m drag is held to the area")
	assert_lte(brush.ghost_size.x, 24.001)
	assert_eq(brush.finish(editor), 1, "and the clamped inn is laid")
	var laid := _doc.structure(1)
	assert_eq(MapStructureIO.structure_problem(laid, _doc.extent_m()), "", "the writer takes it")
	assert_eq(_build(laid.bounds().size).problem, "", "and it builds")
