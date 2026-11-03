extends GutTest

## Where a village furnishing belongs and the buttons beside a picked one (topic villages5,
## docs/systems/villages.md section 14): VillagePieceHome's plaza, lot and street homes as a refusal
## table, every planned piece at home where the plan put it, VillageFurnishings.problem refusing a
## move off its home, and VillagePieceButtons' actions, layout and press (one edit, the piece kept).

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
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


## A `kit` village dressed on a street along z = 0 (both sides) with a plaza north of it.
func _village(kit: String, seed_value: int = 5) -> Dictionary:
	var editor := _editor()
	var wall := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-14, 0, 0),
		Vector3(14, 0, 0),
		-1.0,
		{"seed": seed_value, "side": 2, "preset": 3}
	)
	var id := editor.settlements.dress(wall, kit, 0.8, 1.2)
	assert_gt(id, 0, "%s dressed" % kit)
	editor.settlements.add_plaza(id, Vector2(-6, 14), 5.0)
	return {"editor": editor, "id": id, "held": _doc.settlement(id)}


## The first standing piece of village `id` whose home is `kind`, or {}.
func _piece_of(editor: AuthoringEditor, id: int, kind: StringName) -> Dictionary:
	var held := _doc.settlement(id)
	for row in VillageProps.rows_of(editor, id):
		var slot := str(row["item"]["slot"])
		if VillageFurnishings.is_centre_piece(held.kit, slot):
			continue
		if VillagePieceHome.kind_of(held.kit, slot) == kind:
			return row["item"]
	return {}


## The point `across` metres towards the street from frontage `fr`'s line at arc length `s`.
func _on(fr: ProcgenFrontage, s: float, across: float) -> Vector2:
	return fr.point_at(s) + fr.street_normal_at(s) * across


## The point `beyond` metres on past the end of frontage `fr`'s line, half a metre into its street
## (point_at clamps to the line, so this runs on along the last tangent).
func _past_end(fr: ProcgenFrontage, beyond: float) -> Vector2:
	var end := fr.length()
	return _on(fr, end, 0.5) + fr.tangent_at(end) * beyond


func test_the_home_kind_is_read_from_the_slot_and_the_kits_rule() -> void:
	var table := [
		["market_town", "w1l:p0/square_stalls/r1", VillagePieceHome.PLAZA],
		["farming_hamlet", "w1l:l2/door_goods/d0r", VillagePieceHome.LOT],
		["farming_hamlet", "w1r:l0/yard_stacks/c1", VillagePieceHome.LOT],
		["farming_hamlet", "w1l:l3/gap_stores/g", VillagePieceHome.LOT],
		["farming_hamlet", "w1l:l1/hero_lane/e0", VillagePieceHome.STREET],
		["farming_hamlet", "w1l:edge/hero_lane/e2", VillagePieceHome.STREET],
		["farming_hamlet", "w1l:edge/edge_sign/start", VillagePieceHome.STREET],
		["farming_hamlet", "w1l:j0/junction_sign/j", VillagePieceHome.STREET],
		["farming_hamlet", "f0:scarecrow", VillagePieceHome.FREE],
		["farming_hamlet", "w1l:l2/no_such_rule/d0r", VillagePieceHome.FREE],
	]
	for case: Array in table:
		assert_eq(
			VillagePieceHome.kind_of(str(case[0]), str(case[1])), case[2], "%s" % str(case[1])
		)


func test_every_planned_piece_stands_at_home_where_the_plan_put_it() -> void:
	for kit: String in ["farming_hamlet", "market_town"]:
		for seed_value in [5, 11]:
			before_each()
			var scene := _village(kit, seed_value)
			var editor: AuthoringEditor = scene["editor"]
			var held: Settlement = scene["held"]
			var counted := {}
			for row in VillageProps.rows_of(editor, scene["id"]):
				var item: Dictionary = row["item"]
				var slot := str(item["slot"])
				var home := VillagePieceHome.of(_doc, held, slot)
				var kind: StringName = home["kind"]
				counted[kind] = int(counted.get(kind, 0)) + 1
				assert_true(
					VillagePieceHome.holds(home, item["position"]),
					"%s seed %d: %s stands in its %s" % [kit, seed_value, slot, kind]
				)
			assert_gt(int(counted.get(VillagePieceHome.LOT, 0)), 0, "%s has lot pieces" % kit)
			assert_gt(int(counted.get(VillagePieceHome.STREET, 0)), 0, "%s has street pieces" % kit)


func test_a_refusal_table_for_plaza_lot_and_street_pieces() -> void:
	var scene := _village("market_town")
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var held: Settlement = scene["held"]
	var lot_piece := _piece_of(editor, id, VillagePieceHome.LOT)
	var street_piece := _piece_of(editor, id, VillagePieceHome.STREET)
	var plaza_piece := _piece_of(editor, id, VillagePieceHome.PLAZA)
	assert_false(lot_piece.is_empty() or street_piece.is_empty() or plaza_piece.is_empty())
	var lot_home := VillagePieceHome.of(_doc, held, str(lot_piece["slot"]))
	var street_home := VillagePieceHome.of(_doc, held, str(street_piece["slot"]))
	var plaza_home := VillagePieceHome.of(_doc, held, str(plaza_piece["slot"]))
	var fr: ProcgenFrontage = lot_home["frontage"]
	var own := (float(lot_home["s0"]) + float(lot_home["s1"])) * 0.5
	var other := -1.0
	for lot: Dictionary in fr.lots:
		var middle := (float(lot["s0"]) + float(lot["s1"])) * 0.5
		if middle < float(lot_home["s0"]) or middle > float(lot_home["s1"]):
			other = middle
	assert_gt(other, -1.0, "the side has another lot")
	var street_fr: ProcgenFrontage = street_home["bands"][0]["frontage"]
	var plaza: Dictionary = held.plazas[0]
	var table := [
		["lot piece on its own strip", lot_home, _on(fr, own, fr.gap_m * 0.5), &""],
		["lot piece in its own back yard", lot_home, _on(fr, own, -float(lot_home["back"]) + 1.0), &""],
		["lot piece on the next lot", lot_home, _on(fr, other, fr.gap_m * 0.5), &"off_lot"],
		["lot piece across the street", lot_home, _on(fr, own, fr.gap_m + 6.0), &"off_lot"],
		["lot piece far behind its yard", lot_home, _on(fr, own, -40.0), &"off_lot"],
		["street piece along the strip", street_home, _on(street_fr, 2.0, 0.5), &""],
		["street piece at the far end", street_home, _on(street_fr, street_fr.length(), 0.5), &""],
		["street piece behind the houses", street_home, _on(street_fr, 4.0, -20.0), &"off_street"],
		["street piece past the end", street_home, _past_end(street_fr, 12.0), &"off_street"],
		["plaza piece inside", plaza_home, plaza["at"], &""],
		["plaza piece outside", plaza_home, (plaza["at"] as Vector2) + Vector2(8.0, 0.0),
			&"outside"],
		["no home holds anything", VillagePieceHome.FREE_HOME, Vector2(500, 500), &""],
	]
	for case: Array in table:
		assert_eq(VillagePieceHome.refusal(case[1], case[2]), case[3], str(case[0]))


func test_a_drag_off_its_lot_or_street_is_refused_with_plain_words() -> void:
	var scene := _village("market_town")
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var held: Settlement = scene["held"]
	var rows := VillageProps.rows_of(editor, id)
	var plans := VillageFieldGround.footprints(_doc)
	var lot_piece := _piece_of(editor, id, VillagePieceHome.LOT)
	var street_piece := _piece_of(editor, id, VillagePieceHome.STREET)
	var lot_home := VillagePieceHome.of(_doc, held, str(lot_piece["slot"]))
	var street_fr: ProcgenFrontage = (
		VillagePieceHome.of(_doc, held, str(street_piece["slot"]))["bands"][0]["frontage"]
	)
	var fr: ProcgenFrontage = lot_home["frontage"]
	var away := _on(fr, (float(lot_home["s0"]) + float(lot_home["s1"])) * 0.5, -30.0)
	for case: Array in [
		[lot_piece, away, VillageFurnishings.OFF_LOT],
		[street_piece, _on(street_fr, 4.0, -25.0), VillageFurnishings.OFF_STREET],
	]:
		var item: Dictionary = case[0]
		var reason := VillageFurnishings.problem(
			_doc, id, rows, str(item["slot"]), str(item["prop"]), float(item["scale"]), case[1], plans
		)
		assert_eq(reason, case[2], str(item["slot"]))
	for reason: StringName in [VillageFurnishings.OFF_LOT, VillageFurnishings.OFF_STREET]:
		assert_string_contains(VillageFurnishings.reason_text(reason), "Keep it on its")
		assert_string_contains(VillageFurnishings.short_reason(reason), "Keep it on its")
	assert_ne(
		VillageFurnishings.reason_text(VillageFurnishings.OFF_LOT),
		VillageFurnishings.reason_text(VillageFurnishings.OFF_STREET)
	)


# --- the canopy cut round the picked piece -------------------------------------------------------


func test_the_cut_clears_the_ground_round_a_piece_and_never_less_than_the_floor() -> void:
	var barrel := {"prop": "barrel", "scale": 1.0, "slot": "w1l:l0/door_barrel/d0r"}
	var stall := {"prop": "market_stall", "scale": 1.0, "slot": "w1l:p0/square_stalls/r1"}
	for item: Dictionary in [barrel, stall]:
		var cut := VillageFurnishings.cut_radius(item)
		var drawn := VillageFurnishings.drawn_radius(item)
		assert_gte(cut, VillageFurnishings.CUT_FLOOR_M, "%s: at least the floor" % item["prop"])
		assert_gte(cut, drawn + VillageFurnishings.CUT_MARGIN_M - 0.0001, "%s: margin" % item["prop"])
	assert_gt(
		VillageFurnishings.cut_radius(stall),
		VillageFurnishings.cut_radius(barrel),
		"a bigger piece cuts wider"
	)


# --- the buttons beside the ring ---------------------------------------------------------------


func test_the_buttons_offered_follow_the_picked_piece() -> void:
	var table := [
		[{}, []],
		[{"picked": true}, [VillagePieceButtons.REMOVE]],
		[{"picked": true, "swappable": true}, [VillagePieceButtons.SWAP, VillagePieceButtons.REMOVE]],
		[
			{"picked": true, "swappable": true, "pinned": true},
			[VillagePieceButtons.SWAP, VillagePieceButtons.BACK, VillagePieceButtons.REMOVE]
		],
		[{"picked": true, "field": true, "swappable": true}, [VillagePieceButtons.REMOVE]],
	]
	for case: Array in table:
		var want: Array[StringName] = []
		want.assign(case[1])
		assert_eq(VillagePieceButtons.actions_for(case[0]), want, str(case[0]))


func test_the_row_stands_below_the_piece_then_above_then_beside_and_never_off_screen() -> void:
	var screen := Rect2(400, 0, 880, 650)
	var sizes: Array[Vector2] = [Vector2(52, 28), Vector2(50, 28), Vector2(70, 28)]
	var cases := [
		["middle", Rect2(800, 300, 60, 80), "below"],
		["near the bottom", Rect2(800, 560, 60, 80), "above"],
		["tall piece", Rect2(800, 30, 60, 590), "beside"],
		["at the left edge", Rect2(380, 300, 60, 80), "below"],
		["at the right edge", Rect2(1250, 300, 60, 80), "below"],
	]
	for case: Array in cases:
		var subject: Rect2 = case[1]
		var rects := VillagePieceButtons.layout(subject, sizes, screen)
		assert_eq(rects.size(), 3)
		var row := rects[0].merge(rects[2])
		assert_true(screen.grow(-VillagePieceButtons.MARGIN_PX).encloses(row), "%s: on screen" % case[0])
		assert_false(row.intersects(subject), "%s: clear of the piece" % case[0])
		assert_lt(rects[0].end.x, rects[1].position.x, "%s: pills apart" % case[0])
		match str(case[2]):
			"below":
				assert_gt(row.position.y, subject.end.y, "%s: below" % case[0])
			"above":
				assert_lt(row.end.y, subject.position.y, "%s: above" % case[0])
			"beside":
				assert_true(
					row.position.x > subject.end.x or row.end.x < subject.position.x,
					"%s: beside" % case[0]
				)
	# The row shows only while the piece is on the free board (not for one scrolled out of sight
	# or behind an open drawer, and not for one behind the camera).
	assert_true(VillagePieceButtons.shows(Rect2(800, 300, 60, 80), screen))
	assert_true(VillagePieceButtons.shows(Rect2(380, 300, 60, 80), screen), "half on the board")
	assert_false(VillagePieceButtons.shows(Rect2(800, -200, 60, 80), screen), "above the screen")
	assert_false(VillagePieceButtons.shows(Rect2(100, 300, 60, 80), screen), "behind the drawer")
	assert_false(VillagePieceButtons.shows(Rect2(), screen), "behind the camera")
	# A piece filling the screen leaves no clear place: the row still stays on the screen.
	var huge := VillagePieceButtons.layout(Rect2(300, -50, 1100, 800), sizes, screen)
	assert_true(screen.encloses(huge[0].merge(huge[2])), "a screen-filling piece: still on screen")


func test_a_pill_is_a_real_button_the_gui_takes_and_its_size_is_the_chip() -> void:
	var buttons := VillagePieceButtons.new()
	add_child_autofree(buttons)
	var pill: Button = buttons.pills[VillagePieceButtons.REMOVE]
	assert_eq(pill.name, &"PieceRemove")
	assert_eq(pill.mouse_filter, Control.MOUSE_FILTER_STOP, "a click on it is the GUI's")
	assert_eq(buttons.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the row lets the board through")
	var chip := MapOverlayUtils.chip_size(pill, "Remove", VillageProps.PILL_PX)
	assert_gt(chip.y, float(VillageProps.PILL_PX), "16 px words in the pill")
	var hit := GameMap.should_bypass_world_tool(InputEventMouseButton.new(), true, false)
	assert_true(hit, "a press over a control never reaches the brush")


func test_pressing_the_buttons_edits_the_picked_piece_and_keeps_it_picked() -> void:
	var scene := _village("market_town")
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item := _piece_of(editor, id, VillagePieceHome.LOT)
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	var mode := VillageBrush.new()
	tool.hit = Vector3((item["position"] as Vector2).x, 0.0, (item["position"] as Vector2).y)
	mode.frame(tool)
	mode.press(tool)
	mode.end(tool)
	assert_eq(mode.props.slot, str(item["slot"]))
	var entries := _history.undo_count()
	mode.rotate(tool, 1)
	assert_eq(_history.undo_count(), entries + 1)
	mode._act(VillagePieceButtons.BACK, tool)
	assert_eq(_history.undo_count(), entries + 2, "Back is one entry")
	assert_eq(mode.props.slot, str(item["slot"]), "still picked after Back")
	assert_eq(mode.props.gesture, &"", "a button starts no gesture")
	mode._act(VillagePieceButtons.SWAP, tool)
	assert_eq(mode.props.slot, str(item["slot"]), "still picked after Swap")
	var now := str(mode.props.item(editor)["prop"])
	mode._act(VillagePieceButtons.REMOVE, tool)
	assert_false(mode.props.has_picked(), "Remove takes the piece and its pick")
	assert_eq(mode.props.last_removed, VillageFurnishings.label_of(now).to_lower())
	assert_true(_doc.settlement(id).removed.has(str(item["slot"])))
