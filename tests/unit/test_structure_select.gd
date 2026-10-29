extends GutTest

## Editing a placed building by direct gestures (card S5): StructureEdit's pure rules (handles, a
## corner or side dragged with its clamps, the door edge, a move, a turn, the stepped recipe
## parameters, the variants), StructureEditor's edits (each one history entry, undo, live edit),
## StructureBrush's selection (a click selects, a drag on a handle or the body, an abort), the
## pane's bar and the input table. Summary: docs/systems/structures.md "Editing a building".

const COTTAGE := "core:cottage"
const CHIMNEYED := "core:cottage_chimneyed"
const STONE_HOUSE := "core:stone_house"
const TOWNHOUSE := "core:townhouse"
const A := BrushTool.Action

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


func _row(ref: String = COTTAGE) -> Dictionary:
	return StructureBrush.scaled_row(LibraryStructureStore.structure(ref), 1.0)


## A structure of `ref` laid at `centre`, 6 x 4 m turned `yaw`; its id.
func _lay(
	editor: AuthoringEditor,
	centre: Vector2 = Vector2.ZERO,
	ref: String = COTTAGE,
	yaw: float = 0.0,
	size: Vector2 = Vector2(6, 4)
) -> int:
	var plan := StructurePlacement.rect_plan(centre, size, yaw)
	return editor.structures.add(editor.structures.lot(ref, plan, 100))


func _rect(size: Vector2 = Vector2(6, 4), yaw: float = 0.0) -> PackedVector2Array:
	return StructurePlacement.rect_plan(Vector2.ZERO, size, yaw)


func _river(x: float, half: float) -> void:
	var line := PackedVector2Array([Vector2(x, -14), Vector2(x, 14)])
	var widths := PackedFloat32Array([half, half])
	_doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, 1.0))
	for k in _doc.heights.size():
		_doc.heights[k] = 0.0


func _corner(plan: PackedVector2Array, index: int) -> Dictionary:
	return {"kind": StructureEdit.CORNER, "index": index, "at": plan[index]}


func _edge(plan: PackedVector2Array, index: int) -> Dictionary:
	return StructureEdit.handles(plan)[plan.size() + index]


# --- handles -----------------------------------------------------------------------------


func test_a_plan_has_a_dot_at_each_corner_and_a_tab_outside_each_side() -> void:
	var plan := _rect()
	var found := StructureEdit.handles(plan)
	assert_eq(found.size(), 8)
	for k in 4:
		assert_eq(found[k]["kind"], StructureEdit.CORNER)
		assert_eq(found[k]["at"], plan[k])
		var tab: Dictionary = found[4 + k]
		var side := ProcgenPlan.edge_middle(plan, k)
		assert_almost_eq(tab["at"].distance_to(side), StructureEdit.EDGE_OUT_M, 0.001)
		assert_gt((tab["at"] - side).dot(ProcgenPlan.outward(plan, k)), 0.0, "outside, not in")


func test_a_corner_is_picked_ahead_of_a_nearby_tab_and_far_points_pick_nothing() -> void:
	var plan := _rect()
	assert_eq(StructureEdit.pick_handle(plan, plan[0] + Vector2(0.1, 0.1), 0.5)["index"], 0)
	assert_eq(StructureEdit.pick_handle(plan, plan[0], 0.5)["kind"], StructureEdit.CORNER)
	var tab: Dictionary = _edge(plan, 1)
	assert_eq(StructureEdit.pick_handle(plan, tab["at"], 0.5), tab)
	assert_true(StructureEdit.pick_handle(plan, Vector2(0, 0), 0.5).is_empty(), "the body is none")


func test_handles_can_be_picked_in_screen_pixels_where_the_ground_is_hidden() -> void:
	var plan := _rect()
	var found := StructureEdit.handles(plan)
	var pixels := PackedVector2Array()
	for k in found.size():
		pixels.append(Vector2(100.0 + 40.0 * k, 50.0))
	var picked := StructureEdit.pick_among(found, pixels, Vector2(142.0, 52.0), 20.0)
	assert_eq(picked, found[1], "the nearest dot within the radius")
	assert_true(StructureEdit.pick_among(found, pixels, Vector2(0, 0), 20.0).is_empty())


# --- dragging a corner or a side ----------------------------------------------------------


func test_dragging_a_corner_resizes_and_the_plan_keeps_its_square_corners() -> void:
	var plan := _rect()
	var made := StructureEdit.drag(plan, _corner(plan, 0), Vector2(5, 3), _row())
	var after: PackedVector2Array = made["plan"]
	assert_true(StructureEdit.is_rect(after), "still a rectangle")
	assert_eq(ProcgenPlan.problems(after), [] as Array[String])
	assert_eq(after[2], plan[2], "the opposite corner stays")
	assert_eq(StructureEdit.extent_of(after), Vector2(8, 5))
	assert_false(made["clamped"])


func test_a_turned_house_keeps_its_square_corners_in_its_own_frame() -> void:
	var plan := _rect(Vector2(6, 4), deg_to_rad(30.0))
	assert_true(StructureEdit.is_rect(plan), "a turned rectangle counts")
	var out := plan[1] + (plan[1] - plan[3]).normalized() * 1.5
	var made := StructureEdit.drag(plan, _corner(plan, 1), out, _row())
	var after: PackedVector2Array = made["plan"]
	assert_true(StructureEdit.is_rect(after))
	assert_eq(after[3], plan[3])
	assert_gt(StructureEdit.extent_of(after).x, 6.0, "it grew along the diagonal's pull")
	assert_eq(ProcgenPlan.problems(after), [] as Array[String])


func test_a_corner_drag_clamps_to_the_recipes_sides_and_never_folds_over() -> void:
	var plan := _rect()
	var wide := StructureEdit.drag(plan, _corner(plan, 0), Vector2(60, 2), _row())
	assert_eq(
		StructureEdit.extent_of(wide["plan"]),
		Vector2(14, 4),
		"the wide side stops, the other is free"
	)
	assert_true(wide["clamped"])
	var over := StructureEdit.drag(plan, _corner(plan, 0), Vector2(-10, -10), _row())
	var floor_size := float(_row()["min_side_m"])
	assert_eq(StructureEdit.extent_of(over["plan"]), Vector2(floor_size, floor_size))
	assert_true(over["clamped"], "past the opposite corner it holds at the least size")
	assert_eq(ProcgenPlan.problems(over["plan"]), [] as Array[String])
	var big := StructureEdit.drag(plan, _corner(plan, 0), Vector2(20, 20), _row())
	var size: Vector2 = StructureEdit.extent_of(big["plan"])
	assert_lte(size.x * size.y, float(_row()["max_area_m2"]) + 0.01, "and within the area")


func test_dragging_a_side_pushes_it_and_leaves_the_others() -> void:
	var plan := _rect()
	var front: Dictionary = _edge(plan, 0)
	var made := StructureEdit.drag(plan, front, front["at"] + Vector2(0, 3), _row())
	assert_eq(StructureEdit.extent_of(made["plan"]), Vector2(6, 7))
	assert_true(StructureEdit.is_rect(made["plan"]))
	assert_eq(made["plan"][2], plan[2], "the far side stays")
	var pulled := StructureEdit.drag(plan, front, front["at"] + Vector2(0, -1), _row())
	assert_eq(StructureEdit.extent_of(pulled["plan"]), Vector2(6, 3), "and pulls in")
	var stopped := StructureEdit.drag(plan, front, front["at"] + Vector2(0, 90), _row())
	assert_eq(StructureEdit.extent_of(stopped["plan"]).y, 14.0, "clamped to the largest side")
	assert_true(stopped["clamped"])
	var folded := StructureEdit.drag(plan, front, Vector2(0, -50), _row())
	assert_eq(StructureEdit.extent_of(folded["plan"]).y, float(_row()["min_side_m"]))


func test_shift_moves_one_corner_alone_and_the_plan_stays_buildable() -> void:
	var plan := _rect()
	var made := StructureEdit.drag(plan, _corner(plan, 0), Vector2(5, 3), _row(), null, -1, true)
	var after: PackedVector2Array = made["plan"]
	assert_eq(after[0], Vector2(5, 3))
	for k in [1, 2, 3]:
		assert_eq(after[k], plan[k], "the others did not follow")
	assert_eq(ProcgenPlan.problems(after), [] as Array[String])
	assert_false(StructureEdit.is_rect(after), "it left the square")
	# A single corner dragged over the plan's own side is walked back, not made a bow tie.
	var tangled := StructureEdit.drag(
		plan, _corner(plan, 0), Vector2(-8, -8), _row(), null, -1, true
	)
	assert_eq(ProcgenPlan.problems(tangled["plan"]), [] as Array[String])
	assert_true(tangled["clamped"])


func test_a_drag_toward_water_is_walked_back_to_the_last_dry_plan() -> void:
	_river(8.0, 1.5)
	var plan := _rect()
	var made := StructureEdit.drag(plan, _corner(plan, 0), Vector2(12, 2), _row(), _doc, -1)
	var after: PackedVector2Array = made["plan"]
	assert_true(made["clamped"])
	assert_eq(StructurePlacement.ground_problem(_doc, after), "", "it stops short of the bank")
	assert_gt(StructureEdit.extent_of(after).x, 6.0, "after growing as far as it could")
	assert_lt(StructureEdit.extent_of(after).x, 12.0)


func test_a_drag_stops_short_of_a_neighbour_but_not_of_itself() -> void:
	var editor := _editor()
	var mine := _lay(editor, Vector2.ZERO)
	_lay(editor, Vector2(10, 0))
	var plan := _doc.structure(mine).footprint
	var made := StructureEdit.drag(plan, _corner(plan, 0), Vector2(8, 2), _row(), _doc, mine)
	assert_true(made["clamped"])
	assert_eq(StructurePlacement.occupied(_doc, made["plan"], mine), "")
	var inward := StructureEdit.drag(plan, _corner(plan, 0), Vector2(1, 1), _row(), _doc, mine)
	assert_false(inward["clamped"], "its own footprint is not in its way")


# --- door, move, turn ---------------------------------------------------------------------


func test_the_chosen_side_becomes_edge_zero_and_the_door_follows() -> void:
	var plan := _rect()
	var out_before := ProcgenPlan.outward(plan, 2)
	var moved := StructureEdit.front_to(plan, 2)
	assert_eq(moved.size(), 4)
	assert_eq(ProcgenPlan.edge_start(moved, 0), ProcgenPlan.edge_start(plan, 2))
	assert_eq(ProcgenPlan.outward(moved, 0), out_before, "the door now faces where edge 2 did")
	assert_eq(ProcgenPlan.area(moved), ProcgenPlan.area(plan), "the same house")
	assert_eq(ProcgenPlan.problems(moved), [] as Array[String])
	assert_eq(StructureEdit.front_to(plan, 0), plan, "edge 0 is already the front")
	assert_eq(StructureEdit.front_to(plan, 9), plan, "no such edge: unchanged")
	var round := plan
	for _k in 4:
		round = StructureEdit.front_to(round, 1)
	assert_eq(round, plan, "four notches round is where it began")


func test_a_move_carries_the_plan_and_settles_beside_what_is_in_the_way() -> void:
	var editor := _editor()
	var mine := _lay(editor, Vector2.ZERO)
	_lay(editor, Vector2(10, 0))
	var plan := _doc.structure(mine).footprint
	var free := StructureEdit.move_legal(_doc, plan, Vector2(-4, 3), mine)
	assert_false(free["moved"])
	assert_eq(free["plan"][0], plan[0] + Vector2(-4, 3))
	var blocked := StructureEdit.move_legal(_doc, plan, Vector2(4, 0), mine)
	assert_true(blocked["moved"], "it eased to a legal spot instead of refusing")
	assert_eq(blocked["problem"], "")
	assert_eq(StructurePlacement.occupied(_doc, blocked["plan"], mine), "")
	assert_eq(StructureEdit.extent_of(blocked["plan"]), StructureEdit.extent_of(plan))


func test_a_turn_keeps_the_plan_valid_and_its_size() -> void:
	var plan := _rect()
	var turned := StructureEdit.turned(plan, deg_to_rad(15.0))
	assert_eq(ProcgenPlan.problems(turned), [] as Array[String])
	assert_almost_eq(ProcgenPlan.area(turned), ProcgenPlan.area(plan), 0.15)
	assert_true(StructureEdit.is_rect(turned))
	var quarter := StructureEdit.turned(plan, deg_to_rad(90.0))
	assert_almost_eq(StructureEdit.extent_of(quarter).x, 6.0, 0.02)


# --- parameters and variants --------------------------------------------------------------


func test_the_floors_stepper_stores_an_override_and_drops_it_at_the_default() -> void:
	var recipe := StructureRecipes.document(COTTAGE)
	var one := StructureEdit.stepped_params({}, recipe.interface, "floors", 1)
	assert_eq(one, {"floors": 1.0})
	var two := StructureEdit.stepped_params(one, recipe.interface, "floors", 1)
	assert_eq(two["floors"], 2.0)
	assert_eq(
		StructureEdit.stepped_params(one, recipe.interface, "floors", -1),
		{},
		"back to the default stores nothing"
	)
	var top := {"floors": 6.0}
	assert_eq(
		StructureEdit.stepped_params(top, recipe.interface, "floors", 1),
		top,
		"stops at the recipe's limit"
	)
	assert_eq(
		StructureEdit.stepped_params({}, recipe.interface, "floors", -1), {}, "and at the floor"
	)
	var pitch := StructureEdit.stepped_params({}, recipe.interface, "roof_pitch", 1)
	assert_eq(pitch["roof_pitch"], 39.0, "a pitch notch is five degrees from the default")
	assert_eq(StructureEdit.stepped_params({}, recipe.interface, "no_such", 1), {})


func test_variants_are_the_same_familys_other_recipes_and_a_lone_recipe_has_none() -> void:
	var refs: Array[String] = []
	for row in StructureEdit.variants_of(COTTAGE):
		refs.append(String(row["ref"]))
	assert_true(COTTAGE in refs and CHIMNEYED in refs, "%s" % [refs])
	assert_false(TOWNHOUSE in refs, "another family is not a variant")
	var houses: Array[String] = []
	for row in StructureEdit.variants_of(STONE_HOUSE):
		houses.append(String(row["ref"]))
	houses.sort()
	var expected: Array[String] = [
		"core:adobe_house",
		"core:adobe_parapet",
		"core:adobe_rounded",
		"core:alpine_chalet",
		"core:close_studded_house",
		"core:dormered_house",
		"core:half_timber_house",
		"core:house_flat",
		"core:house_hip",
		"core:minka",
		"core:pueblo",
		"core:slate_house",
		"core:stone_house",
		"core:villa_stucco",
	]
	assert_eq(houses, expected, "the house family holds the stone houses and the styles' houses")
	assert_true(StructureEdit.variants_of("core:no_such").is_empty())


func test_the_ruin_family_swaps_among_rectangles_and_the_tower_has_no_variants() -> void:
	var ruins: Array[String] = []
	for row in StructureEdit.variants_of("core:ruin_cottage"):
		ruins.append(String(row["ref"]))
	ruins.sort()
	assert_eq(
		ruins,
		["core:ruin_barn", "core:ruin_chapel", "core:ruin_cottage", "core:ruin_townhouse"],
		"the round tower is not offered for a rectangle (a swap keeps the footprint)"
	)
	assert_true(StructureEdit.variants_of("core:ruin_tower").is_empty(), "alone of its plan kind")


func test_ruin_and_jetty_step_in_tenths_within_their_range() -> void:
	var chapel := StructureRecipes.document("core:ruin_chapel")
	var more := StructureEdit.stepped_params({}, chapel.interface, "ruin", 1)
	assert_almost_eq(float(more["ruin"]), 0.55, 0.001, "a notch is a tenth over the default 0.45")
	var gone := StructureEdit.stepped_params({"ruin": 0.95}, chapel.interface, "ruin", 1)
	assert_almost_eq(float(gone["ruin"]), 1.0, 0.001, "clamped at the recipe's top")
	assert_true(
		(
			(StructureEdit.stepped_params({"ruin": 1.0}, chapel.interface, "ruin", 1)).get("ruin")
			== 1.0
		)
	)
	var tudor := StructureRecipes.document("core:tudor_townhouse")
	var deeper := StructureEdit.stepped_params({}, tudor.interface, "jetty", 1)
	assert_true(deeper.has("jetty"), "the tudor's jetty steps")
	assert_eq(StructureEdit.stepped_params({}, chapel.interface, "jetty", 1), {}, "a ruin has none")


func test_a_recipe_keeps_only_the_parameters_it_declares() -> void:
	var cottage := StructureRecipes.document(COTTAGE)
	var kept := StructureEdit.kept_params(
		{"floors": 2.0, "chimneys": 3.0, "bogus": 1.0}, cottage.interface
	)
	assert_eq(kept, {"floors": 2.0})


func test_refit_brings_a_rectangle_inside_another_recipes_sides() -> void:
	var small := _rect(Vector2(2.5, 2.5))
	var fitted := StructureEdit.refit(small, _row(TOWNHOUSE))
	assert_eq(StructureEdit.extent_of(fitted), Vector2(3, 3), "the townhouse's least side")
	assert_eq(StructureEdit.centre_of(fitted), StructureEdit.centre_of(small), "about its middle")
	assert_eq(StructureEdit.refit(_rect(), _row(COTTAGE)), _rect(), "a fitting plan is untouched")


# --- the editor: one history entry each ---------------------------------------------------


func test_a_reshape_is_one_entry_and_undoes_to_the_plan_it_began_with() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var before := _doc.structure(id).footprint.duplicate()
	var entries := _history.undo_count()
	var grown: PackedVector2Array = (
		StructureEdit.drag(before, _corner(before, 0), Vector2(5, 3), _row())["plan"]
	)
	assert_true(editor.structures.set_plan(id, grown, "Resize"))
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(_doc.structure(id).footprint, grown)
	_history.undo()
	assert_eq(_doc.structure(id).footprint, before)
	_history.redo()
	assert_eq(_doc.structure(id).footprint, grown)


func test_a_previewed_drag_commits_as_one_entry_from_the_list_before_it() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var original := editor.structures.list()
	var base := _history.undo_count()
	var wide := _doc.structure(id).copy()
	wide.footprint = StructurePlacement.rect_plan(Vector2.ZERO, Vector2(8, 4), 0.0)
	assert_true(editor.structures.preview(wide))
	assert_eq(_history.undo_count(), base, "a preview makes no entry")
	assert_eq(_doc.structure(id).footprint, wide.footprint)
	var wider := wide.copy()
	wider.footprint = StructurePlacement.rect_plan(Vector2.ZERO, Vector2(9, 4), 0.0)
	assert_true(editor.structures.preview(wider))
	assert_true(editor.structures.set_plan(id, wider.footprint, "Resize", original))
	assert_eq(_history.undo_count(), base + 1, "the gesture is one entry")
	_history.undo()
	assert_eq(
		_doc.structure(id).footprint, original[0].footprint, "an undo goes back to before the drag"
	)


func test_the_door_swap_variant_floors_and_copy_are_each_one_undoable_entry() -> void:
	var editor := _editor()
	var id := _lay(editor, Vector2.ZERO, CHIMNEYED)
	var plan := _doc.structure(id).footprint.duplicate()
	var base := _history.undo_count()
	assert_true(editor.structures.set_front(id, 1))
	assert_eq(_doc.structure(id).footprint[0], plan[1], "edge 1 is the front now")
	assert_false(editor.structures.set_front(id, 0), "edge 0 already is")
	assert_false(editor.structures.set_front(id, 7))
	assert_eq(_history.undo_count(), base + 1)
	assert_true(editor.structures.step_param(id, "floors", 1))
	assert_eq(_doc.structure(id).params["floors"], 1.0)
	assert_false(editor.structures.step_param(id, "no_such", 1))
	assert_true(editor.structures.swap_recipe(id, COTTAGE))
	var swapped := _doc.structure(id)
	assert_eq(swapped.recipe, COTTAGE)
	assert_eq(swapped.seed_value, 100, "the same draw")
	assert_eq(swapped.params, {"floors": 1.0}, "the parameter both recipes declare")
	assert_eq(swapped.footprint, _doc.structure(id).footprint)
	assert_false(editor.structures.swap_recipe(id, "core:no_such"))
	var copy := editor.structures.duplicate(id)
	assert_gt(copy, 0)
	assert_eq(_doc.structures.size(), 2)
	var twin := _doc.structure(copy)
	assert_true(twin.recipe == swapped.recipe and twin.seed_value == swapped.seed_value)
	assert_eq(twin.params, swapped.params)
	assert_eq(StructurePlacement.occupied(_doc, twin.footprint, copy), "", "beside it, not on it")
	assert_eq(_history.undo_count(), base + 4, "door, floors, style and copy")
	for _k in 4:
		_history.undo()
	assert_eq(_doc.structures.size(), 1)
	assert_eq(_doc.structure(id).recipe, CHIMNEYED)
	assert_eq(_doc.structure(id).footprint, plan)
	assert_true(_doc.structure(id).params.is_empty())


func test_a_swap_to_a_recipe_with_larger_least_sides_refits_the_plan() -> void:
	var editor := _editor()
	var id := _lay(editor, Vector2.ZERO, COTTAGE, 0.0, Vector2(2.5, 2.5))
	assert_true(editor.structures.swap_recipe(id, TOWNHOUSE))
	assert_eq(StructureEdit.extent_of(_doc.structure(id).footprint), Vector2(3, 3))


func test_a_turn_is_one_entry_and_a_gesture_reaches_a_peer_as_a_live_edit() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	assert_true(editor.structures.turn(id, deg_to_rad(15.0)))
	assert_eq(entries.size(), 1)
	var op := LiveEditCodec.op_of(entries[0], editor)
	assert_eq(op.kind, "structures")
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
	assert_eq(decoded.problem, "")
	LiveEditCodec.apply(decoded.op, peer)
	assert_true(
		peer_doc.structures[0].same_as(_doc.structures[0]), "the peer holds the turned house"
	)


func test_the_live_building_follows_an_edit_and_an_undo_brings_it_back() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var nodes := _map.get_node(AuthoredStructures.NODE_NAME) as AuthoredStructures
	nodes.flush()
	var wide := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(10, 4), 0.0)
	assert_true(editor.structures.set_plan(id, wide, "Resize"))
	nodes.flush()
	assert_not_null(nodes.get_structure_node(id), "the node is rebuilt")
	var widths := _node_width(nodes.get_structure_node(id))
	assert_gt(widths, 9.0, "the mesh follows the new plan")
	_history.undo()
	nodes.flush()
	assert_lt(_node_width(nodes.get_structure_node(id)), 8.0, "and the undo narrows it again")


## The x extent (world) of every building mesh under a structure node (not its yard).
func _node_width(node: Node) -> float:
	var low := INF
	var high := -INF
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).begins_with("dressing_"):
			continue
		var box := (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		low = minf(low, box.position.x)
		high = maxf(high, box.end.x)
	return high - low


# --- the brush: select, then act ----------------------------------------------------------


func _tool(editor: AuthoringEditor) -> BrushTool:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	return tool


func test_a_click_on_a_building_selects_it_and_bare_ground_lets_go_without_laying() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	var tool := _tool(editor)
	watch_signals(brush)
	tool.hit = Vector3(0, 0, 0)
	assert_false(brush.press(tool))
	assert_eq(brush.selected_id, id, "a click on the body selects")
	assert_true(brush.has_selection())
	assert_signal_emitted_with_parameters(brush, "selection_changed", [id])
	assert_true(brush.took_press(), "a press on it may become a move")
	brush.end(tool)
	assert_eq(_doc.structures.size(), 1)
	assert_eq(_history.undo_count(), 1, "a click only selects: the lay is the one entry")
	tool.hit = Vector3(12, 0, 12)
	assert_false(brush.press(tool))
	assert_false(brush.took_press(), "the bare click did not begin a lot")
	assert_eq(brush.selected_id, -1, "it let go")
	assert_eq(_doc.structures.size(), 1, "and laid nothing")
	assert_false(brush.press(tool), "a lot is not a dab stroke")
	assert_true(brush.drawing, "the next click on bare ground begins a lot again")


func test_while_selected_no_lot_follows_the_pointer() -> void:
	var editor := _editor()
	_lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.track(editor, Vector3(10, 0, 8), 0.1)
	assert_ne(brush.ghost_centre, Vector2.INF, "idle, a lot follows")
	brush.select(1)
	assert_eq(brush.ghost_centre, Vector2.INF, "selected, it steps aside")
	brush.track(editor, Vector3(10, 0, 8), 0.1)
	assert_eq(brush.ghost_centre, Vector2.INF)


func test_dragging_a_corner_dot_resizes_in_one_entry_and_shows_the_building_as_it_goes() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	var plan := _doc.structure(id).footprint.duplicate()
	var base := _history.undo_count()
	assert_true(brush.begin_edit(editor, plan[0]))
	assert_eq(brush.edit["kind"], StructureEdit.CORNER)
	brush.edit_to(editor, Vector2(5, 3))
	assert_eq(StructureEdit.extent_of(brush.edit["plan"]), Vector2(8, 5), "the outline follows")
	assert_eq(
		_doc.structure(id).footprint, brush.edit["plan"], "and the building is shown as it will be"
	)
	assert_eq(_history.undo_count(), base, "nothing recorded mid-drag")
	assert_true(brush.finish_edit(editor))
	assert_eq(_history.undo_count(), base + 1)
	assert_eq(StructureEdit.extent_of(_doc.structure(id).footprint), Vector2(8, 5))
	_history.undo()
	assert_eq(_doc.structure(id).footprint, plan)


func test_a_dropped_drag_puts_the_building_back_and_a_still_drag_changes_nothing() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	var plan := _doc.structure(id).footprint.duplicate()
	var base := _history.undo_count()
	brush.begin_edit(editor, plan[0])
	brush.edit_to(editor, Vector2(7, 4))
	assert_ne(_doc.structure(id).footprint, plan)
	brush.abort_edit(editor)
	assert_eq(_doc.structure(id).footprint, plan, "an Escape or right click drops it")
	assert_true(brush.edit.is_empty())
	brush.begin_edit(editor, plan[0])
	assert_false(brush.finish_edit(editor), "a click on a dot that never moved is nothing")
	brush.begin_edit(editor, plan[0])
	brush.edit_to(editor, Vector2(5, 3))
	brush.edit_to(editor, plan[0])
	assert_false(brush.finish_edit(editor), "dragged back to where it began: no entry")
	assert_eq(_doc.structure(id).footprint, plan)
	assert_eq(_history.undo_count(), base)


func test_a_click_on_a_side_tab_makes_it_the_front_and_a_drag_pushes_it() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	var plan := _doc.structure(id).footprint.duplicate()
	var tab: Dictionary = _edge(plan, 1)
	assert_true(brush.begin_edit(editor, tab["at"]))
	assert_eq(brush.edit["kind"], StructureEdit.EDGE)
	assert_true(brush.finish_edit(editor), "a click on a side tab")
	assert_eq(_doc.structure(id).footprint[0], plan[1], "put the door on that side")
	assert_eq(_doc.structure(id).footprint.size(), 4)
	var turned := _doc.structure(id).footprint.duplicate()
	var front: Dictionary = _edge(turned, 0)
	brush.begin_edit(editor, front["at"])
	brush.edit_to(editor, front["at"] + ProcgenPlan.outward(turned, 0) * 2.0)
	assert_true(brush.finish_edit(editor))
	assert_gt(
		StructureEdit.extent_of(_doc.structure(id).footprint).y, StructureEdit.extent_of(turned).y
	)
	_history.undo()
	_history.undo()
	assert_eq(_doc.structure(id).footprint, plan, "two undos, back to the start")


func test_dragging_the_body_moves_the_building_and_a_press_off_it_does_not() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	var plan := _doc.structure(id).footprint.duplicate()
	assert_false(brush.begin_edit(editor, Vector2(9, 9)), "bare ground is not the building")
	assert_true(brush.begin_edit(editor, Vector2(0.4, 0.3)), "the body is")
	assert_eq(brush.edit["kind"], &"move")
	brush.edit_to(editor, Vector2(3.4, 2.3))
	assert_true(brush.finish_edit(editor))
	assert_eq(_doc.structure(id).footprint[0], plan[0] + Vector2(3, 2))
	assert_eq(_doc.structure(id).recipe, COTTAGE)


func test_q_e_r_and_ctrl_d_act_on_the_selected_building_not_the_next_lot() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	var tool := _tool(editor)
	brush.select(id)
	var yaw := brush.yaw
	var seed_before := _doc.structure(id).seed_value
	var plan := _doc.structure(id).footprint.duplicate()
	brush.rotate(tool, 1)
	assert_eq(brush.yaw, yaw, "the next lot's turn is left alone")
	assert_ne(_doc.structure(id).footprint, plan, "the building turned")
	brush.reroll(tool)
	assert_ne(_doc.structure(id).seed_value, seed_before, "it was redrawn")
	assert_true(brush.duplicates())
	brush.duplicate(tool)
	assert_eq(_doc.structures.size(), 2, "Ctrl+D copied it")
	assert_eq(brush.selected_id, 2, "and the copy is selected")


func test_escape_and_leaving_the_tool_let_go_and_a_removed_building_is_deselected() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	var tool := _tool(editor)
	brush.select(id)
	brush.cancel(tool)
	assert_eq(brush.selected_id, -1, "Escape with nothing held lets go")
	brush.select(id)
	brush.leave(tool)
	assert_eq(brush.selected_id, -1, "a tool switch too")
	brush.select(id)
	assert_true(brush.delete_selected(editor))
	assert_eq(brush.selected_id, -1)
	assert_true(_doc.structures.is_empty())
	brush.select(7)
	brush.track(editor, Vector3.ZERO, 0.0)
	assert_eq(brush.selected_id, -1, "a selection that is gone (an undo, a peer) is dropped")


func test_the_brush_asks_again_for_the_bar_when_an_undo_changes_the_selected_record() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	brush.track(editor, Vector3(9, 0, 9), 0.0)
	assert_true(brush.step_selected(editor, "floors", 1))
	watch_signals(brush)
	brush.track(editor, Vector3(9, 0, 9), 0.0)
	assert_signal_emitted(brush, "selection_changed")
	_history.undo()
	watch_signals(brush)
	brush.track(editor, Vector3(9, 0, 9), 0.0)
	assert_signal_emitted(brush, "selection_changed", "the undo changed what the bar shows")


func test_pixels_become_metres_from_the_camera_so_handles_are_picked_by_what_is_seen() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	add_child_autofree(camera)
	var sized := StructureBrush.metres_for_pixels(camera, Vector3.ZERO, 20.0, 1.0)
	assert_gt(sized, 0.0)
	assert_lt(sized, 10.0)
	var scaled := StructureBrush.metres_for_pixels(camera, Vector3.ZERO, 20.0, 2.0)
	assert_almost_eq(scaled, sized * 0.5, 0.001, "a scaled map picks in document metres")
	assert_eq(
		StructureBrush.metres_for_pixels(null, Vector3.ZERO, 20.0, 1.0),
		StructureBrush.PICK_FALLBACK_M
	)


# --- the input table ----------------------------------------------------------------------


func _key(code: Key, ctrl: bool = false) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	key.ctrl_pressed = ctrl
	return key


func test_escape_is_the_brushs_only_with_something_held_or_selected() -> void:
	assert_eq(BrushTool.decide(_key(KEY_ESCAPE), true, false, false), A.NONE, "idle: the drawer's")
	assert_eq(
		BrushTool.decide(_key(KEY_ESCAPE), true, false, false, true), A.CANCEL, "selected: let go"
	)
	assert_eq(BrushTool.decide(_key(KEY_ESCAPE), true, true, false), A.CANCEL, "held: as before")


func test_ctrl_d_copies_only_where_the_mode_can() -> void:
	assert_eq(BrushTool.decide(_key(KEY_D, true), true, false, false, true, true), A.DUPLICATE)
	assert_eq(BrushTool.decide(_key(KEY_D, true), true, false, false, true, false), A.NONE)
	assert_eq(
		BrushTool.decide(_key(KEY_D), true, false, false, true, true), A.NONE, "a bare D is not it"
	)


# --- the pane's bar -----------------------------------------------------------------------


func test_the_bar_replaces_the_palette_while_a_building_is_selected() -> void:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	var editor := _editor()
	var id := _lay(editor, Vector2.ZERO, CHIMNEYED)
	assert_false(pane.selection_box.visible)
	assert_true(pane.family_fields[0].visible)
	pane.show_selection(_doc.structure(id))
	assert_true(pane.selection_box.visible)
	assert_false(pane.family_fields[0].visible, "the tiles step aside")
	assert_false(pane.reroll_button.visible)
	assert_eq(pane.selection_title.text, "Cottage with chimney")
	assert_not_null(pane.variant_field, "a cottage has a variant")
	assert_eq(pane.variant_field.tiles.selected, StringName(CHIMNEYED))
	assert_true((pane.steppers["floors"]["row"] as Control).visible)
	assert_eq((pane.steppers["floors"]["value"] as Label).text, "Auto")
	assert_true(
		(pane.steppers["chimneys"]["row"] as Control).visible, "this recipe exposes chimneys"
	)
	pane.show_selection(null)
	assert_false(pane.selection_box.visible)
	assert_true(pane.family_fields[0].visible, "the palette is back")


func test_the_bar_offers_only_what_the_recipe_exposes() -> void:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	var editor := _editor()
	var id := _lay(editor, Vector2.ZERO, STONE_HOUSE)
	pane.show_selection(_doc.structure(id))
	assert_false((pane.steppers["floors"]["row"] as Control).visible, "it has no floors")
	assert_true((pane.steppers["ridge"]["row"] as Control).visible, "it can turn its ridge")
	assert_false((pane.steppers["chimneys"]["row"] as Control).visible)
	assert_true((pane.steppers["roof_pitch"]["row"] as Control).visible)
	var cottage := _lay(editor, Vector2(12, 0), COTTAGE)
	var held := _doc.structure(cottage).copy()
	held.params = {"floors": 2.0}
	pane.show_selection(held)
	assert_eq((pane.steppers["floors"]["value"] as Label).text, "2")
	assert_false(
		(pane.steppers["chimneys"]["row"] as Control).visible, "the plain cottage has no chimney"
	)


func test_the_bars_buttons_say_what_they_were_asked() -> void:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	var editor := _editor()
	var id := _lay(editor, Vector2.ZERO, COTTAGE)
	pane.show_selection(_doc.structure(id))
	watch_signals(pane)
	(pane.steppers["floors"]["plus"] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(pane, "param_stepped", ["floors", 1])
	(pane.steppers["roof_pitch"]["minus"] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(pane, "param_stepped", ["roof_pitch", -1])
	pane.variant_field.tiles.selection_changed.emit(StringName(CHIMNEYED))
	assert_signal_emitted_with_parameters(pane, "variant_picked", [CHIMNEYED])
	pane.door_button.pressed.emit()
	pane.copy_button.pressed.emit()
	pane.remove_button.pressed.emit()
	pane.redraw_button.pressed.emit()
	pane.done_button.pressed.emit()
	for signal_name in [
		"door_requested", "copy_requested", "remove_requested", "redraw_requested", "done_requested"
	]:
		assert_signal_emitted(pane, signal_name)
	(pane.steppers["floors"]["minus"] as Button).pressed.emit()
	assert_true((pane.steppers["floors"]["minus"] as Button).disabled, "at Auto there is no fewer")


func test_the_tool_wires_the_bar_to_the_brush_and_a_press_on_a_building_shows_it() -> void:
	var editor := _editor()
	var id := _lay(editor, Vector2.ZERO, COTTAGE)
	var tool := ToolRegistry.find(StructureTool.ID) as StructureTool
	var controller := AuthoringController.new()
	add_child_autofree(controller)
	var brush := _tool(editor)
	controller.brush = brush
	controller.editor = editor
	var pane := tool.build_pane(null) as StructureToolPane
	add_child_autofree(pane)
	tool.connect_pane(controller, pane)
	var mode := StructureTool.of(brush)
	mode.select(id)
	assert_true(pane.selection_box.visible, "the brush's selection shows the bar")
	pane.param_stepped.emit("floors", 1)
	assert_eq(_doc.structure(id).params["floors"], 1.0, "a stepper press is one edit")
	assert_eq((pane.steppers["floors"]["value"] as Label).text, "1", "and the bar shows it")
	pane.variant_picked.emit(CHIMNEYED)
	assert_eq(_doc.structure(id).recipe, CHIMNEYED)
	pane.door_requested.emit()
	pane.copy_requested.emit()
	assert_eq(_doc.structures.size(), 2)
	assert_eq(mode.selected_id, 2, "the copy is selected")
	pane.remove_requested.emit()
	assert_eq(_doc.structures.size(), 1)
	assert_false(pane.selection_box.visible, "and the palette returns")
	# A second pane (the panel was rebuilt) takes over; the first one's links are gone.
	var second := tool.build_pane(null) as StructureToolPane
	add_child_autofree(second)
	tool.connect_pane(controller, second)
	mode.select(1)
	assert_true(second.selection_box.visible)
