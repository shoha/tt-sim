extends GutTest

## Round and polygonal structures (styles integration card, 2026-10-28): the core library's regular
## polygon starters (plan kind "round", the `sides:<n>` tag), StructurePlacement's round plans
## and size rules, StructureEdit's uniform-scale handles, the brush's ghost and the street split's
## guard and region rules. Summary: docs/systems/structures.md "Round plans".

const ROUND_REFS: Array[String] = [
	"core:roundhouse",
	"core:round_hut",
	"core:watchtower",
	"core:tower_hex",
	"core:dome_hall",
]

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
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


func _radius(plan: PackedVector2Array) -> float:
	return float(StructureEdit.round_of(plan)["radius"])


# --- the library ---------------------------------------------------------------------------


func test_the_core_library_ships_the_round_starters_as_round_plans() -> void:
	for ref in ROUND_REFS:
		var row := _row(ref)
		assert_false(row.is_empty(), ref)
		assert_true(StructurePlacement.is_round(row), ref)
		assert_true(StreetSplit.ROUND_TAG in (row["tags"] as Array), ref)
		assert_true(StreetSplit.REGIONAL_TAG in (row["tags"] as Array), ref)
		assert_gte(StructurePlacement.sides_of(row), 4, ref)
	assert_eq(StructurePlacement.sides_of(_row("core:roundhouse")), 8)
	assert_eq(StructurePlacement.sides_of(_row("core:round_hut")), 12)
	assert_eq(StructurePlacement.sides_of(_row("core:watchtower")), 4)
	assert_eq(StructurePlacement.sides_of(_row("core:tower_hex")), 6)
	assert_eq(StructurePlacement.sides_of(_row("core:dome_hall")), 10)
	assert_eq(StructurePlacement.sides_of(_row("core:cottage")), 0, "a rectangle has no sides tag")


func test_every_sizes_extreme_is_a_valid_plan_and_a_building() -> void:
	for ref in ROUND_REFS:
		var row := _row(ref)
		var sides := StructurePlacement.sides_of(row)
		for d: float in [
			float(row["min_side_m"]),
			StructurePlacement.default_size(row).x,
			float(row["max_side_m"])
		]:
			for yaw in [0.0, 0.7, 2.0]:
				var plan := StructurePlacement.round_plan(Vector2(1, -2), d * 0.5, yaw, sides)
				assert_eq(ProcgenPlan.problems(plan), [] as Array[String], "%s %.1f" % [ref, d])
				assert_eq(plan.size(), sides)
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	for ref in ROUND_REFS:
		var row := _row(ref)
		var big := StructurePlacement.round_plan(
			Vector2.ZERO, float(row["max_side_m"]) * 0.5, 0.0, StructurePlacement.sides_of(row)
		)
		var parts := StructureGeometry.build_one(doc, Structure.make(1, ref, big, 5))
		assert_eq(parts.problem, "", "%s at its largest builds" % ref)
		assert_lt(int(parts.triangles), StructureGeometry.SOFT_TRIANGLES, ref)


func test_the_default_plan_and_the_pin_plan_are_the_rows_regular_polygon() -> void:
	for ref in ROUND_REFS:
		var row := _row(ref)
		var plan := StructurePlacement.pin_plan(row)
		assert_eq(plan.size(), StructurePlacement.sides_of(row), ref)
		assert_almost_eq(_radius(plan) * 2.0, float(row["default_size_m"][0]), 0.02, ref)
	assert_eq(StructurePlacement.pin_plan(_row("core:cottage")).size(), 4)


# --- plans and sizes -----------------------------------------------------------------------


func test_a_round_lot_faces_its_door_to_the_camera_and_turns_with_yaw() -> void:
	var plan := StructurePlacement.round_plan(Vector2(2, 1), 3.0, 0.0, 8)
	assert_gt(ProcgenPlan.outward(plan, 0).y, 0.999, "edge 0 faces +Z at turn 0")
	assert_almost_eq(float(StructureEdit.round_of(plan)["radius"]), 3.0, 0.01)
	assert_almost_eq((StructureEdit.round_of(plan)["centre"] as Vector2).x, 2.0, 0.01)
	var turned := StructurePlacement.round_plan(Vector2(2, 1), 3.0, PI * 0.5, 8)
	assert_almost_eq(
		absf(ProcgenPlan.outward(turned, 0).x), 1.0, 0.01, "a quarter turn faces sideways"
	)
	assert_almost_eq(float(StructureEdit.round_of(turned)["yaw"]), PI * 0.5, 0.01)


func test_a_round_size_is_one_diameter_inside_the_rows_range() -> void:
	var row := _row("core:roundhouse")
	var low := float(row["min_side_m"])
	var high := float(row["max_side_m"])
	assert_eq(StructurePlacement.clamp_size(Vector2(1, 30), row), Vector2(high, high))
	assert_eq(StructurePlacement.clamp_size(Vector2(0.5, 0.2), row), Vector2(low, low))
	var between := StructurePlacement.clamp_size(Vector2(7.0, 6.0), row)
	assert_eq(between.x, between.y, "a square: the shape is fixed")
	var wide := StructurePlacement.default_size(row)
	assert_eq(wide.x, wide.y)


func test_a_click_lays_the_polygon_at_the_nearest_legal_spot() -> void:
	var row := _row("core:roundhouse")
	var size := StructurePlacement.default_size(row)
	var spot := StructurePlacement.nearest_legal(
		_doc, Vector2(1, 1), size, 0.0, StructurePlacement.sides_of(row)
	)
	assert_eq(spot["problem"], "")
	assert_eq((spot["plan"] as PackedVector2Array).size(), 8)
	assert_true(StructurePlacement.lot_problem(_doc, spot["plan"]) == "")


func test_the_brush_ghost_and_lot_are_polygons_and_a_drag_draws_from_the_middle() -> void:
	var editor := _editor()
	var brush := StructureBrush.new()
	brush.pick("core:round_hut")
	brush.track(editor, Vector3(1, 0, 1), 0.1)
	var ghost := brush.ghost_plan()
	assert_eq(ghost.size(), 12, "the ghost is the hut's 12-gon")
	assert_eq(ProcgenPlan.problems(ghost), [] as Array[String])
	# A press and drag: the press is the middle, the pointer the rim.
	brush.begin(Vector3(0, 0, 0))
	brush.track(editor, Vector3(3.0, 0, 0), 0.1)
	assert_not_null(brush.preview)
	var made := brush.preview.footprint
	assert_eq(made.size(), 12)
	assert_almost_eq(_radius(made), 3.0, 0.1, "the radius is how far the pointer went")
	var id := brush.finish(editor)
	assert_gt(id, 0, "the lot is laid")
	assert_eq(editor.document.structure(id).footprint.size(), 12)


# --- handles -------------------------------------------------------------------------------


func test_a_corner_drag_scales_the_polygon_about_its_middle_and_keeps_it_regular() -> void:
	var row := StructureBrush.scaled_row(_row("core:roundhouse"), 1.0)
	var plan := StructurePlacement.round_plan(Vector2(1, 1), 3.0, 0.4, 8)
	var corner := {"kind": StructureEdit.CORNER, "index": 2, "at": plan[2]}
	var centre: Vector2 = StructureEdit.round_of(plan)["centre"]
	var found := StructureEdit.drag(plan, corner, centre + Vector2(4.0, 0.0), row)
	var out: PackedVector2Array = found["plan"]
	assert_eq(out.size(), 8, "the sides do not change")
	assert_almost_eq(_radius(out), 4.0, 0.05)
	assert_almost_eq(
		(StructureEdit.round_of(out)["centre"] as Vector2).distance_to(centre), 0.0, 0.05
	)
	assert_almost_eq(float(StructureEdit.round_of(out)["yaw"]), 0.4, 0.01, "the turn is kept")
	assert_eq(ProcgenPlan.problems(out), [] as Array[String])
	var shortest := INF
	var longest := 0.0
	for k in out.size():
		shortest = minf(shortest, ProcgenPlan.edge_length(out, k))
		longest = maxf(longest, ProcgenPlan.edge_length(out, k))
	assert_almost_eq(longest - shortest, 0.0, 0.03, "all sides equal")
	# Shift does not break the shape either.
	var single := StructureEdit.drag(plan, corner, centre + Vector2(4.0, 0.0), row, null, -1, true)
	assert_eq(single["plan"], out)


func test_a_side_tab_scales_too_and_a_stopped_drag_clamps_to_the_row() -> void:
	var row := StructureBrush.scaled_row(_row("core:round_hut"), 1.0)
	var plan := StructurePlacement.round_plan(Vector2.ZERO, 2.8, 0.0, 12)
	var edge := StructureEdit.handles(plan)[plan.size() + 3]
	assert_eq(edge["kind"], StructureEdit.EDGE)
	var pushed := StructureEdit.drag(plan, edge, (edge["at"] as Vector2) * 1.3, row)
	assert_gt(_radius(pushed["plan"]), 2.8)
	assert_eq((pushed["plan"] as PackedVector2Array).size(), 12)
	var way_out := StructureEdit.drag(plan, edge, (edge["at"] as Vector2) * 20.0, row)
	assert_true(way_out["clamped"], "asking for more than the largest is stopped")
	assert_lte(_radius(way_out["plan"]) * 2.0, float(row["max_side_m"]) + 0.03)
	var tiny := StructureEdit.drag(plan, edge, Vector2.ZERO, row)
	assert_gte(_radius(tiny["plan"]) * 2.0, float(row["min_side_m"]) - 0.03)
	assert_eq(ProcgenPlan.problems(tiny["plan"]), [] as Array[String])


func test_a_round_drag_walks_back_from_water_and_always_stays_a_valid_polygon() -> void:
	var editor := _editor()
	var row := StructureBrush.scaled_row(_row("core:tower_hex"), 1.0)
	var plan := StructurePlacement.round_plan(Vector2(-6, 0), 2.6, 0.0, 6)
	var corner := {"kind": StructureEdit.CORNER, "index": 0, "at": plan[0]}
	var line := PackedVector2Array([Vector2(-1, -14), Vector2(-1, 14)])
	var widths := PackedFloat32Array([1.0, 1.0])
	_doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, 1.0))
	for k in _doc.heights.size():
		_doc.heights[k] = 0.0
	var found := StructureEdit.drag(plan, corner, Vector2(0.0, 0.0), row, editor.document)
	assert_true(found["clamped"])
	assert_eq(ProcgenPlan.problems(found["plan"]), [] as Array[String])
	assert_eq(StructurePlacement.lot_problem(_doc, found["plan"]), "")
	for target: Vector2 in [
		Vector2(-6, 0), Vector2(-6.2, 0.1), Vector2(-30, 30), Vector2(-5.9, -0.1)
	]:
		var any := StructureEdit.drag(plan, corner, target, row, editor.document)
		assert_eq(ProcgenPlan.problems(any["plan"]), [] as Array[String], str(target))
		assert_eq((any["plan"] as PackedVector2Array).size(), 6)


func test_a_move_a_turn_and_a_door_change_keep_a_polygon_a_polygon() -> void:
	var plan := StructurePlacement.round_plan(Vector2.ZERO, 3.0, 0.0, 8)
	var turned := StructureEdit.turned(plan, deg_to_rad(15.0))
	assert_eq(ProcgenPlan.problems(turned), [] as Array[String])
	assert_almost_eq(_radius(turned), 3.0, 0.02)
	var door := StructureEdit.front_to(plan, 3)
	assert_eq(door.size(), 8)
	assert_almost_eq(_radius(door), 3.0, 0.01)
	assert_ne(ProcgenPlan.outward(door, 0), ProcgenPlan.outward(plan, 0))
	var editor := _editor()
	var moved := StructureEdit.move_legal(editor.document, plan, Vector2(2, 1), -1)
	assert_eq(moved["problem"], "")
	assert_almost_eq(_radius(moved["plan"]), 3.0, 0.02)


func test_a_variant_swap_refits_a_polygon_to_the_new_rows_range() -> void:
	var row := StructureBrush.scaled_row(_row("core:round_hut"), 1.0)
	var fat := StructurePlacement.round_plan(Vector2.ZERO, 9.0, 0.3, 12)
	var fitted := StructureEdit.refit(fat, row)
	assert_eq(fitted.size(), 12)
	assert_almost_eq(_radius(fitted) * 2.0, float(row["max_side_m"]), 0.03)
	var fine := StructurePlacement.round_plan(Vector2.ZERO, 2.5, 0.3, 12)
	assert_eq(StructureEdit.refit(fine, row), fine, "inside the range it is left alone")


func test_a_laid_round_building_survives_a_save_and_reload() -> void:
	var editor := _editor()
	var plan := StructurePlacement.round_plan(Vector2(2, 2), 3.6, 0.5, 8)
	var id := editor.structures.add(editor.structures.lot("core:roundhouse", plan, 100))
	assert_gt(id, 0)
	var path := "user://test_round_structures.ttmap"
	assert_eq(MapDocumentIO.write(editor.document, path), OK)
	var back: MapDocument = MapDocumentIO.read(path)["document"]
	assert_eq(back.structures.size(), 1)
	assert_true(back.structures[0].same_as(editor.document.structure(id)), "the same record")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- the street split ----------------------------------------------------------------------


func test_a_street_split_never_picks_a_round_structure() -> void:
	var regions: Array[Array] = [[], ["desert"], ["english"], ["nordic", "alpine"]]
	for tags in regions:
		var region: Array[String] = []
		region.assign(tags)
		for row in StreetSplit.candidates(region):
			assert_false(StreetSplit.ROUND_TAG in (row["tags"] as Array), String(row["ref"]))


func test_a_streets_region_comes_from_its_biome_then_its_species() -> void:
	assert_eq(StreetSplit.region_tags("savanna", 0), ["desert", "mediterranean"] as Array[String])
	assert_eq(StreetSplit.region_tags("rocky_badlands", 3), ["desert"] as Array[String])
	assert_eq(StreetSplit.region_tags("grassland_meadow", 0), [] as Array[String])
	assert_eq(StreetSplit.region_tags("grassland_meadow", 3), ["english"] as Array[String])
	assert_eq(StreetSplit.region_tags("", 2), ["dutch"] as Array[String])


func test_a_desert_street_is_adobe_and_a_mediterranean_one_adds_villas() -> void:
	var desert := StreetSplit.candidates(["desert"] as Array[String])
	var refs: Array = desert.map(func(r: Dictionary) -> String: return r["ref"])
	assert_true("core:adobe_house" in refs)
	assert_false("core:stone_house" in refs, "the generic houses are replaced")
	var both := StreetSplit.candidates(["desert", "mediterranean"] as Array[String])
	var both_refs: Array = both.map(func(r: Dictionary) -> String: return r["ref"])
	assert_true("core:villa_stucco" in both_refs)
	assert_true("core:adobe_house" in both_refs)
	var none := StreetSplit.candidates()
	for row in none:
		assert_false(StreetSplit.REGIONAL_TAG in (row["tags"] as Array), String(row["ref"]))


func test_an_english_village_joins_thatch_and_slate_to_the_generic_houses() -> void:
	var english := StreetSplit.candidates(["english"] as Array[String])
	var refs: Array = english.map(func(r: Dictionary) -> String: return r["ref"])
	assert_true("core:thatched_cottage" in refs)
	assert_true("core:slate_house" in refs)
	assert_true("core:cottage" in refs, "the generic set stays")
	assert_false("core:adobe_house" in refs, "other regions stay out")
	var lot := {"walls": "stone", "roof": "gable", "style": "cottage", "seed": 0, "trim": []}
	var plain := StreetSplit.score(lot, _row("core:thatched_cottage"))
	var region := StreetSplit.score(
		lot, _row("core:thatched_cottage"), ["english"] as Array[String]
	)
	assert_eq(region - plain, StreetSplit.W_REGION)


func test_the_region_choice_is_deterministic_and_a_desert_street_splits_into_adobe() -> void:
	var street := Wall.make(
		1, Wall.Kind.ROW, PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]), false, 3.0
	)
	street.preset = 0
	street.seed_value = 7
	_doc.biome_ids = PackedStringArray(["savanna"])
	_doc.walls = [street] as Array[Wall]
	var first := StreetSplit.plan(_doc, street, 1.0)
	var again := StreetSplit.plan(_doc, street, 1.0)
	var a: Array[Structure] = []
	var b: Array[Structure] = []
	a.assign(first["structures"])
	b.assign(again["structures"])
	assert_gt(a.size(), 0)
	assert_eq(a.size(), b.size())
	for k in a.size():
		assert_eq(a[k].recipe, b[k].recipe)
		assert_true(
			(
				a[k].recipe
				in [
					"core:adobe_house",
					"core:adobe_parapet",
					"core:adobe_rounded",
					"core:pueblo",
					"core:villa_stucco"
				]
			),
			"%s in a savanna" % a[k].recipe
		)
