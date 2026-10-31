extends GutTest

## The Decorate row in the GM's Events pane (check G5, 2026-10-31): with the Buildings brush out in
## play and a building selected, the pane's bar shows the Decorate row (nine ornament toggles and
## Surprise me), and a toggle edits the building's record and rebuilds the standing structure.
## Wired as PlayEvents wires it (StructureTool.connect_selection on the Events pane's own Building
## pane). Unselected, the row is hidden and the palette shows instead.

const COTTAGE := "core:cottage"

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


func _mesh_names(nodes: Node) -> Array[String]:
	var out: Array[String] = []
	for mesh in nodes.find_children("*", "MeshInstance3D", true, false):
		out.append(String(mesh.name))
	return out


func test_the_row_appears_with_a_selected_building_and_a_toggle_rebuilds_it() -> void:
	var editor := _editor()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	var id := editor.structures.add(editor.structures.lot(COTTAGE, plan, 100))
	var pane := EventsPane.new()
	add_child_autofree(pane)
	pane.show_tool(StructureTool.ID)
	var bar := pane.structure_pane
	assert_not_null(bar, "the Events pane has the Building pane")
	var section := bar.ornaments_section
	assert_not_null(section)
	var brush := BrushTool.new()
	add_child_autofree(brush)
	brush.editor = editor
	var tool := ToolRegistry.find(StructureTool.ID) as StructureTool
	tool.connect_selection(brush, bar, func() -> void: pass)
	assert_false(section.is_visible_in_tree(), "no building selected: no Decorate row")
	StructureTool.of(brush).select(id)
	assert_true(bar.selection_box.is_visible_in_tree(), "a selected building shows its bar")
	assert_true(section.is_visible_in_tree(), "with the Decorate row in it")
	var title := section.find_child("OrnamentsTitle", true, false) as Label
	assert_eq(title.text, "Decorate")
	assert_true(title.is_visible_in_tree())
	var expected: Array[String] = []
	for item: Dictionary in StructureOrnaments.CHIPS:
		expected.append(String(item["kind"]))
	var labels: Array[String] = []
	for kind in expected:
		var chip := section.chips[kind] as Button
		assert_true(chip.is_visible_in_tree(), "%s toggle is shown" % kind)
		labels.append(chip.text)
	assert_eq(section.chips.size(), 9, "nine toggles")
	assert_true(section.surprise_button.is_visible_in_tree(), "Surprise me is shown")
	assert_eq(section.surprise_button.text, "Surprise me")
	gut.p("Decorate toggles: %s" % ", ".join(labels))
	# A toggle edits the record (one history entry) and the standing building follows.
	var nodes := AuthoredStructures.of_map(_map)
	nodes.flush()
	var plain := _mesh_names(nodes)
	var entries := _history.undo_count()
	(section.chips["banner"] as Button).button_pressed = true
	assert_eq(
		StructureOrnaments.kinds_of(_doc.structure(id).params),
		["banner"] as Array[String],
		"the record carries the banner"
	)
	assert_eq(_history.undo_count(), entries + 1, "one history entry")
	nodes.flush()
	var dressed := _mesh_names(nodes)
	assert_true("ornament_cloth" in dressed, "the standing building rebuilt with its banner")
	assert_false("ornament_cloth" in plain, "which it did not have before")
	section.surprise_button.pressed.emit()
	assert_ne(_doc.structure(id).params, {} as Dictionary, "Surprise me dresses it")
	StructureTool.of(brush).deselect()
	assert_false(section.is_visible_in_tree(), "deselected: the row goes")
