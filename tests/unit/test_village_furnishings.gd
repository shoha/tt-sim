extends GutTest

## Touching the furnishings of a village in the Village tool (topic villages4,
## docs/systems/villages.md section 14): the pure rules (VillageFurnishings: the pick, what a piece
## may be swapped for, where a piece may stand, the record a change leaves), SettlementEditor's
## remove, pin, swap, unpin and
## restore (one history entry each, a live-edit peer ending level, a re-dress keeping a pin and
## dropping a removal), VillageProps and VillageBrush's gestures on a BrushTool, and the pane's box.

const POND_BED := -1.25
const POND_LEVEL := -0.25

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


func _editor(doc: MapDocument = null, history: AuthoringHistory = null) -> AuthoringEditor:
	var use := doc if doc != null else _doc
	var root := _map
	if doc != null:
		root = Node3D.new()
		add_child_autofree(root)
	root.add_child(AuthoredTerrain.create(use))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	root.add_child(node)
	var editor := AuthoringEditor.create(use, root, history if history != null else _history)
	editor.scatter.attach_document(use)
	return editor


func _row(editor: AuthoringEditor, z: float, seed_value: int = 5) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, z),
		Vector3(12, 0, z),
		-1.0,
		{"seed": seed_value, "side": 2, "preset": 3}
	)


## A market town dressed on a street along z = 0 with a plaza, and the first standing piece.
func _scene() -> Dictionary:
	var editor := _editor()
	var id := editor.settlements.dress(_row(editor, 0.0), "market_town", 0.8, 1.0)
	assert_true(editor.settlements.add_plaza(id, Vector2(-6, 12), 5.0))
	var rows: Array[Dictionary] = []
	for row in VillageProps.rows_of(editor, id):
		# The plaza's well is the plaza's heart, not a touchable piece (is_centre_piece).
		if not VillageFurnishings.is_centre_piece("market_town", str(row["item"]["slot"])):
			rows.append(row)
	assert_gt(rows.size(), 6, "a dressed market town with a plaza has pieces")
	return {"editor": editor, "id": id, "rows": rows}


func _slots(editor: AuthoringEditor, id: int) -> PackedStringArray:
	var out := PackedStringArray()
	for row in VillageProps.rows_of(editor, id):
		out.append(str(row["item"]["slot"]))
	return out


## A piece that is not a field's and has other props that belong where it stands.
func _swappable(editor: AuthoringEditor, id: int) -> Dictionary:
	var kit := _doc.settlement(id).kit
	for row in VillageProps.rows_of(editor, id):
		if VillageFurnishings.swap_choices(kit, row["item"]).size() > 1:
			return row["item"]
	return {}


## A place near `item` where the piece may stand, found by looking round it.
func _free_place(item: Dictionary, editor: AuthoringEditor, id: int) -> Vector2:
	var rows := VillageProps.rows_of(editor, id)
	var plans := VillageFieldGround.footprints(_doc)
	for ring in [3.0, 4.5, 6.0, 8.0]:
		for k in 12:
			var at: Vector2 = (item["position"] as Vector2) + Vector2.from_angle(k * TAU / 12.0) * ring
			var problem := VillageFurnishings.problem(
				_doc, id, rows, str(item["slot"]), str(item["prop"]), float(item["scale"]), at, plans
			)
			if problem == &"":
				return at
	return Vector2.INF


# --- the pure rules --------------------------------------------------------------------------


func test_a_prop_is_named_in_sentence_case_and_a_field_piece_is_known_by_its_slot() -> void:
	assert_eq(VillageFurnishings.label_of("market_stall"), "Market stall")
	assert_eq(VillageFurnishings.label_of("barrel"), "Barrel")
	assert_true(VillageFurnishings.is_field_piece("f0:scarecrow"))
	assert_true(VillageFurnishings.is_field_piece("f12:haystack"))
	assert_false(VillageFurnishings.is_field_piece("w3l:l2/door_barrel/d0r"))
	assert_false(VillageFurnishings.is_field_piece("r:p0/square_well/c"))
	assert_eq(VillageFurnishings.rule_of("w3l:l2/door_barrel/d0r"), "door_barrel")
	assert_eq(VillageFurnishings.rule_of("f0:scarecrow"), "")


func test_the_pick_takes_the_nearest_piece_in_reach_and_the_pad_widens_it() -> void:
	var a := {"item": {"prop": "barrel", "scale": 1.0, "slot": "a", "position": Vector2(0, 0)}}
	var b := {"item": {"prop": "barrel", "scale": 1.0, "slot": "b", "position": Vector2(1.0, 0)}}
	var rows: Array[Dictionary] = [a, b]
	assert_eq(VillageFurnishings.pick(rows, Vector2(0.1, 0), 0.0)["item"]["slot"], "a")
	assert_eq(VillageFurnishings.pick(rows, Vector2(0.9, 0), 0.0)["item"]["slot"], "b")
	assert_true(VillageFurnishings.pick(rows, Vector2(0, 3), 0.0).is_empty(), "bare ground")
	assert_true(VillageFurnishings.pick(rows, Vector2(0, 1.2), 0.0).is_empty())
	assert_false(VillageFurnishings.pick(rows, Vector2(0, 1.2), 1.0).is_empty(), "a pad reaches")


func test_a_piece_is_under_the_pointer_by_where_it_is_drawn_and_a_hidden_one_is_not() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	add_child_autofree(camera)
	camera.global_position = Vector3(0, 10, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	var front := {
		"item": {"prop": "barrel", "scale": 1.0, "slot": "front", "position": Vector2(0, 0)},
		"village": 1,
		"y": 0.0,
	}
	var behind := {
		"item": {"prop": "barrel", "scale": 1.0, "slot": "behind", "position": Vector2(0.05, 0)},
		"village": 1,
		"y": 0.0,
	}
	var all: Array[Dictionary] = [behind, front]
	var props := VillageProps.new()
	var pointer := camera.unproject_position(Vector3(0.05, 0, 0))
	# Nothing in the way: the piece nearest the pointer's own drawn centre wins.
	props.set_view(camera, pointer, Callable())
	assert_eq(props._pick_drawn(all)["item"]["slot"], "behind")
	# A building between the camera and `behind`: the pointer is on what is drawn, the piece in front.
	props.set_view(camera, pointer, func(_from: Vector3, to: Vector3) -> bool: return to.x > 0.02)
	assert_eq(props._pick_drawn(all)["item"]["slot"], "front")
	# Both hidden: no piece is under the pointer.
	props.set_view(camera, pointer, func(_from: Vector3, _to: Vector3) -> bool: return true)
	assert_true(props._pick_drawn(all).is_empty())
	# Far from either: none.
	props.set_view(camera, pointer + Vector2(400, 0), Callable())
	assert_true(props._pick_drawn(all).is_empty())


func test_the_furnish_box_names_its_two_put_back_buttons_apart() -> void:
	var box := VillageFurnishBox.new()
	add_child_autofree(box)
	box.show_state({"picked": true, "label": "Barrel", "pinned": true, "removed": 1})
	assert_eq(box.title.text, "Barrel", "no 'placed by hand' tag")
	assert_eq(box.unpin_button.text, "Back to its spot")
	assert_eq(box.restore_button.text, "Put back 1 removed piece")
	box.show_state({"picked": true, "label": "Barrel", "pinned": false, "removed": 3})
	assert_eq(box.restore_button.text, "Put back 3 removed pieces")
	assert_false(box.unpin_button.visible)


func test_the_swap_choices_are_the_kits_own_props_of_that_kind_of_place() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item := _swappable(editor, id)
	assert_false(item.is_empty(), "some piece has company")
	var choices := VillageFurnishings.swap_choices("market_town", item)
	assert_true(choices.has(str(item["prop"])), "its own prop is in the list, so a caller can cycle")
	for prop in choices:
		assert_true(ProcgenProps.NAMES.has(prop), prop)
	var field_piece := {"slot": "f0:scarecrow", "prop": "scarecrow"}
	assert_eq(VillageFurnishings.swap_choices("market_town", field_piece).size(), 0)
	assert_eq(VillageFurnishings.swap_choices("no_such_kit", item).size(), 0)


func test_the_next_choice_wraps_and_skips_what_does_not_fit() -> void:
	var choices: Array[String] = ["barrel", "crate_stack", "bench"]
	var all := func(_p: String) -> bool: return true
	var none := func(_p: String) -> bool: return false
	assert_eq(VillageFurnishings.next_choice(choices, "barrel", all), "crate_stack")
	assert_eq(VillageFurnishings.next_choice(choices, "bench", all), "barrel")
	var no_crates := func(p: String) -> bool: return p != "crate_stack"
	assert_eq(VillageFurnishings.next_choice(choices, "barrel", no_crates), "bench")
	assert_eq(VillageFurnishings.next_choice(choices, "barrel", none), "")


func test_the_record_helpers_keep_the_caps_and_forget_what_a_removal_replaces() -> void:
	var held := Settlement.make(1, "market_town", 1, 5)
	held.swapped["a"] = "bench"
	held.pinned["a"] = {"prop": "barrel", "at": Vector2(1, 2), "yaw": 0.0, "scale": 1.0, "seed": 0}
	var removed := VillageFurnishings.with_removed(held, "a")
	assert_eq(removed.removed, PackedStringArray(["a"]))
	assert_false(removed.swapped.has("a"))
	assert_false(removed.pinned.has("a"))
	assert_null(VillageFurnishings.with_removed(removed, "a"), "already gone")
	assert_null(VillageFurnishings.with_unpinned(removed, "a"), "not pinned")
	assert_null(VillageFurnishings.with_restored(held), "nothing was removed")
	assert_eq(VillageFurnishings.with_restored(removed).removed.size(), 0)
	var pin := {"prop": "barrel", "at": Vector2(1.234, 2.0), "yaw": 7.0, "scale": 1.0, "seed": 1}
	var pinned := VillageFurnishings.with_pin(held, "b", pin)
	assert_eq(pinned.pinned["b"]["at"], Vector2(1.23, 2.0), "a hundredth")
	assert_true(absf(float(pinned.pinned["b"]["yaw"])) <= PI, "the yaw wraps into range")
	assert_eq(MapSettlementIO.settlement_problem(pinned), "")
	var full := held.copy()
	for k in Settlement.MAX_OVERRIDES:
		full.pinned["s%d" % k] = pin
	assert_null(VillageFurnishings.with_pin(full, "extra", pin), "the 65th pin is refused")
	assert_not_null(VillageFurnishings.with_pin(full, "s0", pin), "an existing pin may change")


func test_a_place_far_from_the_village_over_water_or_on_another_piece_is_refused() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var rows := VillageProps.rows_of(editor, id)
	var item: Dictionary = rows[0]["item"]
	var plans := VillageFieldGround.footprints(_doc)
	var ask := func(at: Vector2) -> StringName:
		return VillageFurnishings.problem(
			_doc, id, rows, str(item["slot"]), str(item["prop"]), float(item["scale"]), at, plans
		)
	assert_eq(ask.call(Vector2(0, 150)), VillageFurnishings.REACH)
	var other: Dictionary = rows[1]["item"]
	assert_eq(ask.call(other["position"]), VillageFurnishings.CROWDED)
	assert_ne(ask.call(Vector2(0, 0)), &"", "the street itself is a house or a crowd, not free")
	var free := _free_place(item, editor, id)
	assert_true(free.is_finite(), "somewhere beside it is free")
	assert_eq(ask.call(free), &"")
	# A pond under the place wets it.
	var heights := _doc.heights.duplicate()
	var mask := PackedByteArray()
	mask.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if _doc.sample_to_world(Vector2(x, z)).distance_to(free) <= 4.0:
				heights[_doc.sample_index(x, z)] = POND_BED
				mask[_doc.sample_index(x, z)] = 2
	_doc.heights = heights
	_doc.pond_mask = mask
	_doc.water_bodies.append(WaterBody.pond(2, WaterBody.Depth.DEEP, POND_LEVEL))
	assert_eq(ask.call(free), VillageFurnishings.WET)


# --- the editor ----------------------------------------------------------------------------------


func test_a_removed_piece_is_gone_in_one_entry_and_undo_brings_it_back() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var slot := str(scene["rows"][0]["item"]["slot"])
	var entries := _history.undo_count()
	assert_true(editor.settlements.remove_furnishing(id, slot))
	assert_eq(_history.undo_count(), entries + 1)
	assert_false(_slots(editor, id).has(slot))
	assert_true(_doc.settlement(id).removed.has(slot))
	assert_false(editor.settlements.remove_furnishing(id, slot), "already gone")
	_history.undo()
	assert_true(_slots(editor, id).has(slot))
	_history.redo()
	assert_false(_slots(editor, id).has(slot))
	assert_true(editor.settlements.restore_furnishings(id))
	assert_true(_slots(editor, id).has(slot), "put back")
	assert_false(editor.settlements.restore_furnishings(id), "nothing left to put back")


func test_a_pinned_piece_stands_where_it_was_put_and_a_pin_lets_go() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item: Dictionary = scene["rows"][0]["item"]
	var slot := str(item["slot"])
	var free := _free_place(item, editor, id)
	assert_true(free.is_finite())
	var moved := item.duplicate()
	moved["position"] = free
	assert_true(editor.settlements.pin_furnishing(id, slot, SettlementPlan.pin_of(moved)))
	var now := _row_of(editor, id, slot)
	assert_true(now["pinned"])
	assert_lt((now["position"] as Vector2).distance_to(free), 0.02, "at the hundredth")
	assert_true(editor.settlements.unpin_furnishing(id, slot))
	assert_false(_row_of(editor, id, slot)["pinned"])
	assert_lt((_row_of(editor, id, slot)["position"] as Vector2).distance_to(item["position"]), 0.001)
	assert_false(editor.settlements.unpin_furnishing(id, slot), "not pinned any more")


func _row_of(editor: AuthoringEditor, id: int, slot: String) -> Dictionary:
	for row in VillageProps.rows_of(editor, id):
		if str(row["item"]["slot"]) == slot:
			return row["item"]
	return {}


func test_a_swapped_piece_takes_the_prop_and_a_pinned_one_changes_its_pin() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item := _swappable(editor, id)
	var slot := str(item["slot"])
	var choices := VillageFurnishings.swap_choices("market_town", item)
	var other := ""
	for prop in choices:
		if prop != str(item["prop"]):
			other = prop
	assert_true(editor.settlements.swap_furnishing(id, slot, other))
	assert_eq(_doc.settlement(id).swapped[slot], other)
	assert_eq(_row_of(editor, id, slot)["prop"], other)
	assert_false(editor.settlements.swap_furnishing(id, slot, "no_such_prop"))
	var now := _row_of(editor, id, slot)
	assert_true(editor.settlements.pin_furnishing(id, slot, SettlementPlan.pin_of(now)))
	assert_true(editor.settlements.swap_furnishing(id, slot, str(item["prop"])))
	assert_eq(_doc.settlement(id).pinned[slot]["prop"], str(item["prop"]))
	assert_eq(_row_of(editor, id, slot)["prop"], str(item["prop"]))


func test_a_redress_keeps_what_the_author_placed_and_a_new_character_forgets_it() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item: Dictionary = scene["rows"][0]["item"]
	var slot := str(item["slot"])
	var gone := str(scene["rows"][1]["item"]["slot"])
	var free := _free_place(item, editor, id)
	var moved := item.duplicate()
	moved["position"] = free
	assert_true(editor.settlements.pin_furnishing(id, slot, SettlementPlan.pin_of(moved)))
	assert_true(editor.settlements.remove_furnishing(id, gone))
	assert_true(editor.settlements.redress(id))
	assert_true(_doc.settlement(id).pinned.has(slot), "a pin survives a re-dress")
	assert_true(_doc.settlement(id).removed.is_empty(), "a removal named a slot of the old draw")
	assert_true(editor.settlements.set_kit(id, "farming_hamlet"))
	assert_true(_doc.settlement(id).pinned.is_empty(), "a new character forgets it")


func test_a_peer_ends_level_through_a_removal_a_move_and_their_undos() -> void:
	var host := _editor()
	var peer_doc := MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var street := _row(host, 0.0)
	peer_doc.walls = _doc.walls.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := host.settlements.dress(street, "market_town", 0.8, 1.0)
	var item: Dictionary = VillageProps.rows_of(host, id)[0]["item"]
	var free := _free_place(item, host, id)
	var moved := item.duplicate()
	moved["position"] = free
	assert_true(host.settlements.pin_furnishing(id, str(item["slot"]), SettlementPlan.pin_of(moved)))
	var second: Dictionary = VillageProps.rows_of(host, id)[1]["item"]
	assert_true(host.settlements.remove_furnishing(id, str(second["slot"])))
	for entry in entries:
		for op in LiveEditCodec.ops_of(entry, host, false):
			var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
			assert_eq(decoded["problem"], "")
			LiveEditCodec.apply(decoded["op"], peer)
	var mine := _doc.settlement(id)
	var theirs := peer_doc.settlement(id)
	assert_eq(theirs.removed, mine.removed)
	assert_eq(theirs.pinned.keys(), mine.pinned.keys())
	assert_eq(
		JSON.stringify(MapSettlementIO.settlement_json(theirs), "", true, true),
		JSON.stringify(MapSettlementIO.settlement_json(mine), "", true, true),
		"the same record byte for byte"
	)


# --- the gestures --------------------------------------------------------------------------------


func _tool(editor: AuthoringEditor) -> BrushTool:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	return tool


func _frame(mode: VillageBrush, tool: BrushTool, at: Vector2) -> void:
	tool.hit = Vector3(at.x, 0.0, at.y)
	mode.frame(tool)


func test_hover_press_and_a_short_click_pick_a_piece_without_moving_it() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item: Dictionary = scene["rows"][0]["item"]
	var tool := _tool(editor)
	var mode := VillageBrush.new()
	var entries := _history.undo_count()
	_frame(mode, tool, item["position"])
	assert_eq(mode.props.hover_slot, str(item["slot"]))
	assert_true(mode.has_target(), "Delete and the wheel see a piece as a target")
	mode.press(tool)
	assert_eq(mode.props.gesture, VillageProps.GESTURE_PICK)
	assert_true(mode.took_press())
	_frame(mode, tool, (item["position"] as Vector2) + Vector2(0.3, 0))
	assert_eq(mode.props.gesture, VillageProps.GESTURE_PICK, "under the threshold it is a click")
	mode.end(tool)
	assert_eq(mode.props.slot, str(item["slot"]))
	assert_eq(mode.props.village, id)
	assert_eq(mode.selected_village, id)
	assert_eq(_history.undo_count(), entries, "a click edits nothing")
	assert_true(mode.has_selection(), "Escape lets go of it")
	mode.cancel(tool)
	assert_false(mode.props.has_picked())


func test_a_drag_moves_the_piece_and_pins_it_at_the_release_as_one_entry() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item: Dictionary = scene["rows"][0]["item"]
	var free := _free_place(item, editor, id)
	var tool := _tool(editor)
	var mode := VillageBrush.new()
	var entries := _history.undo_count()
	_frame(mode, tool, item["position"])
	mode.press(tool)
	_frame(mode, tool, free)
	assert_true(mode.props.moving())
	assert_eq(mode.props.refusal(), &"")
	assert_eq(_history.undo_count(), entries, "nothing is edited while it is carried")
	mode.end(tool)
	assert_eq(_history.undo_count(), entries + 1)
	var now := _row_of(editor, id, str(item["slot"]))
	assert_true(now["pinned"])
	assert_lt((now["position"] as Vector2).distance_to(free), 0.15, "at the tenth the drag snaps to")


func test_a_drag_to_a_refused_place_changes_nothing_and_says_why() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item: Dictionary = scene["rows"][0]["item"]
	var tool := _tool(editor)
	var mode := VillageBrush.new()
	var toasts: Array[String] = []
	tool.refused.connect(func(words: String) -> void: toasts.append(words))
	var entries := _history.undo_count()
	_frame(mode, tool, item["position"])
	mode.press(tool)
	_frame(mode, tool, Vector2(0, 200))
	assert_true(mode.props.moving())
	assert_eq(mode.props.refusal(), VillageFurnishings.REACH)
	mode.end(tool)
	assert_eq(_history.undo_count(), entries)
	assert_eq(toasts.size(), 1)
	assert_false(_row_of(editor, id, str(item["slot"]))["pinned"])


func test_delete_removes_the_piece_under_the_pointer_and_q_and_r_pin_it() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item: Dictionary = scene["rows"][0]["item"]
	var tool := _tool(editor)
	var mode := VillageBrush.new()
	_frame(mode, tool, item["position"])
	assert_true(mode.rotates() and mode.rerolls())
	mode.rotate(tool, 1)
	var turned := _row_of(editor, id, str(item["slot"]))
	assert_true(turned["pinned"])
	assert_almost_eq(
		wrapf(float(turned["yaw"]) - float(item["yaw"]), -PI, PI), VillageFurnishings.TURN_STEP, 0.01
	)
	mode.reroll(tool)
	var next_draw := (int(item["seed"]) + 1) % ProcgenSettlement.VARIANTS
	assert_eq(_row_of(editor, id, str(item["slot"]))["seed"], next_draw)
	_frame(mode, tool, item["position"])
	mode.remove_target(tool)
	assert_false(_slots(editor, id).has(str(item["slot"])))
	assert_false(mode.props.has_hover() and mode.props.hover_slot == str(item["slot"]))


func test_the_pane_swap_cycles_to_a_prop_that_fits_and_the_box_shows_the_pick() -> void:
	var scene := _scene()
	var editor: AuthoringEditor = scene["editor"]
	var id: int = scene["id"]
	var item := _swappable(editor, id)
	var tool := _tool(editor)
	var mode := VillageBrush.new()
	_frame(mode, tool, item["position"])
	mode.press(tool)
	mode.end(tool)
	_frame(mode, tool, Vector2(0, 200))
	var state := VillageTool.state_for(_doc, mode)
	assert_true(state["prop"]["picked"])
	assert_eq(state["prop"]["label"], VillageFurnishings.label_of(str(item["prop"])))
	assert_true(state["prop"]["swappable"])
	var words := mode.props.swap(editor)
	assert_true(words == "" or words == "Nothing else fits here.", words)
	if words == "":
		assert_ne(_row_of(editor, id, str(item["slot"]))["prop"], str(item["prop"]))
	var box := VillageFurnishBox.new()
	add_child_autofree(box)
	box.show_state(state["prop"])
	assert_true(box.visible and box.row.visible)
	assert_false(box.restore_button.visible, "nothing was taken away")
	assert_true(editor.settlements.remove_furnishing(id, str(item["slot"])))
	_frame(mode, tool, Vector2(0, 200))
	box.show_state(VillageTool.state_for(_doc, mode)["prop"])
	assert_false(box.row.visible, "the picked piece is gone")
	assert_true(box.restore_button.visible)
	assert_string_contains(box.restore_button.text, "1")
	box.show_state({})
	assert_false(box.visible, "nothing picked, nothing taken away: no box")
