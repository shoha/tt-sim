extends GutTest

## Placing over a selection (card place_flow): with a pick armed the ghost lot follows over bare
## ground even while a building is selected, a click there lays and selects the new building, a
## drag sizes a lot, handles and the body still win, Escape and Done keep the pick, and an undo
## gives the earlier selection back. docs/systems/structures.md "Placing flows on over a selection".

const COTTAGE := "core:cottage"
const CHIMNEYED := "core:cottage_chimneyed"

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


func _lay(editor: AuthoringEditor) -> int:
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	return editor.structures.add(editor.structures.lot(COTTAGE, plan, 100))


func _tool(editor: AuthoringEditor) -> BrushTool:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	return tool


func test_while_selected_the_ghost_follows_over_bare_ground_and_steps_aside_over_one() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	brush.track(editor, Vector3(10, 0, 8), 0.1)
	assert_ne(brush.ghost_centre, Vector2.INF, "selected, a lot still follows over bare ground")
	assert_eq(brush.selected_id, id, "and the selection stays")
	brush.track(editor, Vector3(0.4, 0, 0.3), 0.1)
	assert_eq(brush.hover_id, id)
	assert_eq(brush.ghost_centre, Vector2.INF, "over a building a click selects: no ghost")
	var corner: Vector2 = _doc.structure(id).footprint[0]
	brush.track(editor, Vector3(corner.x, 0, corner.y), 0.1)
	assert_eq(brush.ghost_centre, Vector2.INF, "nor over a handle")
	brush.track(editor, Vector3(10, 0, 8), 0.1)
	assert_ne(brush.ghost_centre, Vector2.INF, "back on bare ground it returns")


func test_five_clicks_on_bare_ground_lay_five_buildings_each_one_selected_in_turn() -> void:
	var editor := _editor()
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	var tool := _tool(editor)
	var spots: Array[Vector3] = [
		Vector3(-12, 0, -12),
		Vector3(-4, 0, -12),
		Vector3(4, 0, -12),
		Vector3(12, 0, -12),
		Vector3(-12, 0, 0)
	]
	for spot in spots:
		tool.hit = spot
		brush.track(editor, spot, 0.1)
		brush.press(tool)
		brush.end(tool)
		assert_eq(brush.selected_id, _doc.structures.back().id, "the newest is the selection")
	assert_eq(_doc.structures.size(), 5)
	assert_eq(_history.undo_count(), 5, "one entry each")


func test_undo_of_a_lot_laid_over_a_selection_gives_back_that_selection_and_the_list() -> void:
	var editor := _editor()
	var first := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(first)
	var tool := _tool(editor)
	tool.hit = Vector3(12, 0, 12)
	brush.press(tool)
	brush.end(tool)
	var second := brush.selected_id
	assert_ne(second, first)
	_history.undo()
	assert_eq(_doc.structures.size(), 1, "the list is as it was")
	brush.track(editor, Vector3(9, 0, -9), 0.0)
	assert_eq(brush.selected_id, first, "and the earlier selection is back")


func test_a_drag_from_bare_ground_sizes_a_new_lot_even_with_a_selection() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	var tool := _tool(editor)
	tool.hit = Vector3(8, 0, 8)
	brush.press(tool)
	assert_true(brush.drawing)
	brush.track(editor, Vector3(14, 0, 12), 0.1)
	tool.hit = Vector3(14, 0, 12)
	brush.end(tool)
	assert_eq(_doc.structures.size(), 2)
	var made := _doc.structure(brush.selected_id)
	assert_gt(StructureEdit.extent_of(made.footprint).x, 4.0, "sized by the drag")


func test_a_press_on_a_handle_or_the_body_of_the_selection_still_edits_it() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(COTTAGE)
	brush.select(id)
	var tool := _tool(editor)
	var corner: Vector2 = _doc.structure(id).footprint[0]
	tool.hit = Vector3(corner.x, 0, corner.y)
	brush.press(tool)
	assert_false(brush.drawing, "a press on a handle is the handle's")
	assert_eq(brush.edit["kind"], StructureEdit.CORNER)
	brush.abort_edit(editor)
	tool.hit = Vector3(0.4, 0, 0.3)
	brush.press(tool)
	assert_false(brush.drawing)
	assert_eq(brush.edit["kind"], &"move", "and on the body, a move")


func test_escape_and_done_let_go_but_keep_the_pick_armed() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var brush := StructureBrush.new()
	brush.pick(CHIMNEYED)
	brush.select(id)
	brush.cancel(_tool(editor))
	assert_eq(brush.selected_id, -1)
	assert_eq(brush.ref, CHIMNEYED, "Escape keeps the pick")
	brush.select(id)
	brush.deselect()
	assert_eq(brush.ref, CHIMNEYED, "Done too")


func test_the_hint_bar_names_the_clicks_for_a_selection() -> void:
	var rows := StructureHints.rows([], true)
	assert_eq(rows[0]["action"], "Bare ground: put another down")
	assert_eq(rows[1]["action"], "A building: select it")


