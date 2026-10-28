extends GutTest

## Splitting a street into buildings (card S8; StreetSplit, WallEditor.split_street, the Wall
## tool's picked street): the count and places of the records, their recipes matched to what the
## street drew, one history entry with undo and redo, determinism, the refusals, and the pick and
## the Split button. Summary: docs/systems/structures.md "Splitting a street".

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


func _street(editor: AuthoringEditor, preset: int = 0, seed_value: int = 5) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, 0),
		Vector3(12, 0, 0),
		-1.0,
		{"seed": seed_value, "side": 2, "preset": preset}
	)


func _lot(changes: Dictionary = {}) -> Dictionary:
	var lot := {
		"walls": "stone",
		"roof": "gable",
		"style": "none",
		"trim": [],
		"chimneys": 0,
		"seed": 0,
		"height": 2.6,
		"pitch": 34.0,
		"window_width": 0.0,
	}
	lot.merge(changes, true)
	return lot


func _ref(lot: Dictionary) -> String:
	return String(StreetSplit.match_row(lot, StreetSplit.candidates())["ref"])


# --- the lots become records ------------------------------------------------------------


func test_a_split_makes_one_structure_per_lot_where_the_lot_stood() -> void:
	var editor := _editor()
	var id := _street(editor)
	var lots := WallGeometry.row_lots(_doc, _doc.wall(id))
	assert_gt(lots.size(), 4, "a good few buildings along 24 m")
	assert_eq(editor.walls.split_street(id), lots.size(), "one record per lot")
	assert_eq(_doc.structures.size(), lots.size())
	assert_null(_doc.wall(id), "the street is gone")
	assert_true(_doc.walls.is_empty())
	var ids := {}
	for k in lots.size():
		var structure := _doc.structures[k]
		ids[structure.id] = true
		assert_true(
			ProcgenPlan.is_valid(structure.footprint), "lot %d: a plan the writer takes" % k
		)
		assert_eq(MapStructureIO.structure_problem(structure, _doc.extent_m()), "", "lot %d" % k)
		assert_true(LibraryStructureStore.has(structure.recipe), structure.recipe)
		var points: PackedVector3Array = lots[k].points
		var middle := Vector2.ZERO
		for p in points:
			middle += Vector2(p.x, p.z) * 0.25
		var centre := Vector2.ZERO
		for p in structure.footprint:
			centre += p * 0.25
		assert_lt(centre.distance_to(middle), 0.05, "lot %d stands where the lot did" % k)
		assert_eq(structure.seed_value, posmod(int(lots[k].seed), Structure.MAX_SEED + 1))
	assert_eq(ids.size(), lots.size(), "every id is its own")
	assert_eq(editor.walls.last_split_skipped, 0)


func test_the_front_edge_faces_the_street_on_both_sides_of_it() -> void:
	var editor := _editor()
	var id := _street(editor)
	var street_z := 0.0
	assert_gt(editor.walls.split_street(id), 0)
	for structure in _doc.structures:
		assert_gt(ProcgenPlan.area(structure.footprint), 0.0, "wound as the plan rules want")
		var door := ProcgenPlan.edge_middle(structure.footprint, 0)
		var body := (
			(
				structure.footprint[0]
				+ structure.footprint[1]
				+ structure.footprint[2]
				+ structure.footprint[3]
			)
			* 0.25
		)
		# The door side is the one nearer the street's line (z = 0, but for the setback).
		assert_lt(
			absf(door.y - street_z),
			absf(body.y - street_z) + 0.001,
			"the door side is the street side (structure %d)" % structure.id
		)


func test_all_five_species_split_into_valid_records_of_the_librarys_set() -> void:
	var refs := StructureRecipes.core_refs()
	for preset in Wall.ROW_PRESETS:
		_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		var street := Wall.make(
			1, Wall.Kind.ROW, PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]), false, 3.0
		)
		street.preset = preset
		street.seed_value = 11
		_doc.walls.append(street)
		var made := StreetSplit.plan(_doc, street, 1.0)
		var lots: int = made["lots"]
		var structures: Array[Structure] = []
		structures.assign(made["structures"])
		assert_eq(
			structures.size() + int(made["skipped"]),
			lots,
			"species %d: every lot answered" % preset
		)
		assert_gt(structures.size(), 0, "species %d makes buildings" % preset)
		for structure in structures:
			assert_true(structure.recipe in refs, "species %d: %s" % [preset, structure.recipe])


func test_a_terrace_becomes_townhouses_and_a_village_cottages() -> void:
	var counts := {}
	for preset in [1, 3]:
		var street := Wall.make(
			1, Wall.Kind.ROW, PackedVector2Array([Vector2(-14, 0), Vector2(14, 0)]), false, 3.0
		)
		street.preset = preset
		street.seed_value = 3
		_doc.walls = [street] as Array[Wall]
		var made := StreetSplit.plan(_doc, street, 1.0)
		var structures: Array[Structure] = []
		structures.assign(made["structures"])
		var matching := 0
		for structure in structures:
			var local := structure.recipe.get_slice(":", 1)
			if preset == 1 and local.begins_with("townhouse"):
				matching += 1
			if preset == 3 and (local.begins_with("cottage") or local == "stone_house"):
				matching += 1
		counts[preset] = [matching, structures.size()]
	assert_gt(counts[1][0], 0, "a terrace's tall fronts are townhouses")
	assert_eq(counts[3][0], counts[3][1], "a village is cottages and stone houses")


# --- matching a lot to a structure ------------------------------------------------------


func test_plain_lots_take_the_house_that_has_their_walls() -> void:
	assert_eq(_ref(_lot()), "core:stone_house", "stone under a gable")
	assert_eq(_ref(_lot({"walls": "textured"})), "core:stone_house", "textured is stone too")
	assert_eq(_ref(_lot({"walls": "timber"})), "core:cottage", "timber")


func test_a_named_style_wins_over_the_walls() -> void:
	assert_eq(_ref(_lot({"style": "townhouse"})), "core:townhouse")
	assert_eq(_ref(_lot({"style": "townhouse", "walls": "timber"})), "core:townhouse")
	var dressed := _lot(
		{"style": "townhouse", "trim": ["sills", "lintels", "floor_bands", "quoins"]}
	)
	assert_eq(_ref(dressed), "core:townhouse_trimmed", "trim and quoins pick the trimmed one")
	assert_eq(
		_ref(_lot({"style": "cottage", "walls": "timber", "chimneys": 1, "trim": ["shutters"]})),
		"core:cottage_chimneyed",
		"a chimney and shutters"
	)


func test_a_tie_is_broken_by_the_lots_seed_and_a_street_is_not_one_house() -> void:
	var seen := {}
	for seed_value in 8:
		var ref := _ref(
			_lot({"style": "cottage", "chimneys": 1, "trim": ["shutters"], "seed": seed_value})
		)
		seen[ref] = true
		assert_eq(
			ref,
			_ref(
				_lot({"style": "cottage", "chimneys": 1, "trim": ["shutters"], "seed": seed_value})
			),
			"the same seed, the same pick"
		)
	assert_eq(seen.size(), 2, "a stone cottage lot is a stone house or a cottage by its seed")
	assert_true(seen.has("core:stone_house") and seen.has("core:cottage_chimneyed"))


func test_nothing_alike_takes_a_seeded_pick_from_the_table() -> void:
	var rows: Array[Dictionary] = [
		{"ref": "mine:a", "tags": ["castle"], "family": "keep"},
		{"ref": "mine:b", "tags": ["castle"], "family": "keep"},
	]
	var lot := _lot({"seed": 3})
	assert_eq(StreetSplit.match_row(lot, rows)["ref"], "mine:b", "3 % 2")
	assert_eq(StreetSplit.match_row(_lot({"seed": 4}), rows)["ref"], "mine:a")


func test_params_keep_the_lots_height_and_pitch_where_they_differ_from_the_recipes() -> void:
	var recipe := StructureRecipes.document("core:stone_house")
	var params := StreetSplit.params_of(_lot({"height": 3.14159, "pitch": 34.0}), recipe)
	assert_eq(params.get("height"), 3.14, "rounded to the record's step")
	assert_false(params.has("roof_pitch"), "the recipe's own pitch is not stored")
	assert_true(params.has("textured"), "stone is textured on a street")
	assert_false(params.has("floors"), "a parameter the recipe lacks is dropped")
	var timber := StreetSplit.params_of(_lot({"walls": "timber", "height": 99.0}), recipe)
	assert_eq(timber.get("height"), 5.0, "clamped to the recipe's range")
	assert_false(timber.has("textured"), "timber is not")


func test_a_footprint_is_clamped_to_the_recipes_sides_and_keeps_its_centre() -> void:
	var lot := {
		"points":
		PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(30, 0, 0), Vector3(30, 0, 6), Vector3(0, 0, 6)]
		)
	}
	var row := {"min_side_m": 3.0, "max_side_m": 12.0, "max_area_m2": 100.0}
	var plan := StreetSplit.footprint_of(lot, row)
	var size := StructurePlacement.clamp_size(Vector2(30, 6), row)
	assert_almost_eq(ProcgenPlan.edge_length(plan, 0), size.x, 0.02)
	assert_almost_eq(ProcgenPlan.edge_length(plan, 1), size.y, 0.02)
	assert_almost_eq(((plan[0] + plan[2]) * 0.5).distance_to(Vector2(15, 3)), 0.0, 0.02)


# --- the edit ---------------------------------------------------------------------------


func test_a_split_is_one_history_entry_and_undo_puts_the_street_back() -> void:
	var editor := _editor()
	var id := _street(editor)
	var street := _doc.wall(id).copy()
	var undo_count := _history.undo_count()
	var made := editor.walls.split_street(id)
	assert_gt(made, 0)
	assert_eq(_history.undo_count(), undo_count + 1, "one entry")
	var laid: Array[Structure] = _doc.structures.duplicate()
	assert_eq(_history.undo(), "Split street into buildings")
	assert_true(_doc.structures.is_empty(), "the buildings are gone")
	assert_eq(_doc.walls.size(), 1)
	assert_true(_doc.wall(id).same_as(street), "the street is back, field for field")
	assert_eq(_history.redo(), "Split street into buildings")
	assert_true(_doc.walls.is_empty())
	assert_eq(_doc.structures.size(), laid.size())
	for k in laid.size():
		assert_true(_doc.structures[k].same_as(laid[k]), "building %d comes back as it was" % k)


func test_the_nodes_follow_a_split_and_its_undo() -> void:
	var editor := _editor()
	var id := _street(editor)
	var walls := _map.get_node(AuthoredWalls.NODE_NAME) as AuthoredWalls
	assert_not_null(walls.get_wall_node(id), "the street stands")
	editor.walls.split_street(id)
	assert_null(walls.get_wall_node(id), "and goes")
	var nodes := _map.get_node(AuthoredStructures.NODE_NAME) as AuthoredStructures
	assert_not_null(nodes)
	assert_gt(nodes.flush(), 0, "the buildings are built")
	assert_gt(nodes.get_child_count(), 0, "and have nodes")
	_history.undo()
	assert_not_null(walls.get_wall_node(id), "undone, the street stands again")


func test_a_split_is_the_same_each_time() -> void:
	var a := _editor()
	var id := _street(a, 1, 77)
	var wall := _doc.wall(id)
	var first := StreetSplit.plan(_doc, wall, 1.0)
	var second := StreetSplit.plan(_doc, wall, 1.0)
	assert_eq(first["structures"].size(), second["structures"].size())
	for k in (first["structures"] as Array).size():
		assert_true((first["structures"][k] as Structure).same_as(second["structures"][k]))
	a.walls.split_street(id)
	# The same street in a fresh document of the same map seed splits into the same records.
	var other_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	other_doc.walls.append(wall.copy())
	var again := StreetSplit.plan(other_doc, other_doc.walls[0], 1.0)
	assert_eq(again["structures"].size(), _doc.structures.size())
	for k in _doc.structures.size():
		var made: Structure = again["structures"][k]
		made.id = _doc.structures[k].id
		assert_true(made.same_as(_doc.structures[k]), "building %d" % k)
	# Another seed, another street, another set.
	var changed := wall.copy()
	changed.seed_value = 4242
	var other := StreetSplit.plan(_doc, changed, 1.0)
	var same: bool = other["structures"].size() == _doc.structures.size()
	if same:
		var all_same := true
		for k in _doc.structures.size():
			var made: Structure = other["structures"][k]
			made.id = _doc.structures[k].id
			all_same = all_same and made.same_as(_doc.structures[k])
		assert_false(all_same, "another seed changes the buildings")


func test_a_split_survives_a_save_and_reload() -> void:
	var editor := _editor()
	var id := _street(editor, 2, 21)
	editor.walls.split_street(id)
	var path := "user://test_street_split.ttmap"
	assert_eq(MapDocumentIO.write(_doc, path), OK)
	var read: MapDocument = MapDocumentIO.read(path)["document"]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(read.structures.size(), _doc.structures.size())
	assert_true(read.walls.is_empty())
	for k in _doc.structures.size():
		assert_true(read.structures[k].same_as(_doc.structures[k]), "building %d" % k)


func test_what_cannot_be_split_is_refused_and_changes_nothing() -> void:
	var editor := _editor()
	var fence := editor.walls.place(Wall.Kind.FENCE, Vector3(-3, 0, 6), Vector3(1, 0, 6))
	var undo_count := _history.undo_count()
	assert_eq(editor.walls.split_street(fence), -1, "a fence is not a street")
	assert_eq(editor.walls.last_refusal, WallEditor.REFUSED_INVALID)
	assert_eq(editor.walls.split_street(77), -1, "no such wall")
	var id := _street(editor)
	# A document that cannot hold the buildings keeps its street.
	for k in MapDocument.MAX_STRUCTURES - 1:
		_doc.structures.append(
			Structure.make(
				k + 1,
				"core:cottage",
				StructurePlacement.rect_plan(Vector2(-9, -9), Vector2(3, 3), 0.0)
			)
		)
	var before := _doc.walls.size()
	assert_eq(editor.walls.split_street(id), -1)
	assert_eq(editor.walls.last_refusal, WallEditor.REFUSED_FULL)
	assert_eq(_doc.walls.size(), before, "the street stays")
	assert_eq(_doc.structures.size(), MapDocument.MAX_STRUCTURES - 1, "and nothing was laid")
	assert_eq(_history.undo_count(), undo_count + 1, "only the street's own placement is recorded")


func test_ids_already_taken_are_not_reused() -> void:
	_doc.structures.append(
		Structure.make(
			1, "core:cottage", StructurePlacement.rect_plan(Vector2(-9, -9), Vector2(3, 3), 0.0)
		)
	)
	_doc.structures.append(
		Structure.make(
			3, "core:cottage", StructurePlacement.rect_plan(Vector2(9, -9), Vector2(3, 3), 0.0)
		)
	)
	assert_eq(StreetSplit.free_ids(_doc, 3), PackedInt32Array([2, 4, 5]))
	assert_true(StreetSplit.free_ids(_doc, 0).is_empty())
	assert_true(StreetSplit.free_ids(_doc, MapDocument.MAX_STRUCTURES).is_empty(), "too many")


func test_a_split_reaches_a_peer_as_two_live_ops() -> void:
	var host := _editor()
	var id := _street(host)
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	host.walls.split_street(id)
	assert_eq(entries.size(), 1, "one entry")
	var ops := LiveEditCodec.ops_of(entries[0], host)
	assert_eq(ops.size(), 2, "the structures laid, then the street removed")
	assert_eq([ops[0].kind, ops[1].kind], ["structures", "walls"])
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	for op in ops:
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded.problem, "")
		LiveEditCodec.apply(decoded.op, peer)
	assert_eq(peer_doc.structures.size(), _doc.structures.size())
	assert_true(peer_doc.walls.is_empty())


# --- the Wall tool ----------------------------------------------------------------------


func test_a_click_on_a_street_picks_it_and_a_click_elsewhere_lets_go() -> void:
	var editor := _editor()
	var id := _street(editor)
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	var brush := WallBrush.new()
	watch_signals(brush)
	assert_false(brush.has_selection())
	brush.begin(Vector3(0, 0, 0))
	brush.end(tool)
	assert_eq(brush.selected_id, id, "a click over the street's line")
	assert_true(brush.has_selection())
	assert_signal_emitted_with_parameters(brush, "selection_changed", [id])
	assert_eq(_doc.walls.size(), 1, "and lays nothing")
	var bare := Vector3.INF
	for x in range(-9, 10, 3):
		for z in range(-9, 10, 3):
			if bare == Vector3.INF and editor.walls.wall_at(Vector3(x, 0, z)) < 0:
				bare = Vector3(x, 0, z)
	assert_ne(bare, Vector3.INF, "some ground is clear of the street")
	brush.begin(bare)
	brush.end(tool)
	assert_eq(brush.selected_id, -1, "a click on bare ground")
	brush.select(id)
	brush.cancel(tool)
	assert_eq(brush.selected_id, -1, "Escape")
	brush.select(id)
	brush.leave(tool)
	assert_eq(brush.selected_id, -1, "putting the tool down")


func test_a_drag_still_lays_a_side_with_a_street_picked() -> void:
	var editor := _editor()
	var id := _street(editor)
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	var brush := WallBrush.new()
	brush.kind = Wall.Kind.FENCE
	brush.select(id)
	brush.begin(Vector3(-3, 0, 8))
	brush.track(editor, Vector3(1, 0, 8), false)
	brush.end(tool)
	assert_eq(_doc.walls.size(), 2, "a fence was laid")
	assert_eq(brush.selected_id, id, "the picked street stays picked")


func test_the_pane_and_the_brush_split_the_picked_street() -> void:
	var editor := _editor()
	var id := _street(editor)
	var brush := WallBrush.new()
	assert_eq(brush.split_selected(editor), -1, "nothing picked")
	assert_eq(brush.message(), WallBrush.SPLIT_GONE)
	brush.select(id)
	var made := brush.split_selected(editor)
	assert_gt(made, 0)
	assert_eq(_doc.structures.size(), made)
	assert_eq(brush.selected_id, -1, "the street is gone, so is the pick")
	var pane := WallToolPane.new()
	add_child_autofree(pane)
	assert_false(pane.selection_box.visible)
	pane.show_selection(Wall.make(1, Wall.Kind.ROW, PackedVector2Array(), false, 3.0))
	assert_true(pane.selection_box.visible)
	watch_signals(pane)
	pane.split_button.pressed.emit()
	assert_signal_emitted(pane, "split_requested")
	pane.done_button.pressed.emit()
	assert_signal_emitted(pane, "done_requested")
	pane.show_selection(null)
	assert_false(pane.selection_box.visible)


func test_an_undone_street_is_let_go_by_the_next_frame() -> void:
	var editor := _editor()
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	var id := _street(editor)
	var brush := WallBrush.new()
	brush.select(id)
	_history.undo()
	brush.frame(tool)
	assert_eq(brush.selected_id, -1, "the street it held is gone")


func test_the_wall_tool_lists_the_click_and_the_split_in_its_help() -> void:
	var tool := ToolRegistry.find(WallTool.ID)
	var rows := tool.help_rows()
	var text := ""
	for row in rows:
		text += " ".join(row) + "\n"
	assert_string_contains(text, "Click a street")
	assert_string_contains(text, "Split")
