extends GutTest

## AuthoringEditor (scenes/states/authoring/authoring_editor.gd): brush strokes and prop
## gestures recorded as history entries whose undo and redo restore the document's masks
## and the props exactly. Uses the built-in palette's temperate forest (like
## test_authored_scatter.gd); MultiMesh transforms read back as identity headless, so props
## are checked through their rows.

const BIOME := "temperate_forest_summer_s1"
const MEADOW := "alpine_meadow_summer_s1"

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func _editor(with_props: bool = false) -> AuthoringEditor:
	if with_props:
		var props := AuthoredScatter.create()
		props.name = MapSourceLoader.PROPS_NODE
		props.budget = 1_000_000_000
		props.grow_seconds = 0.0
		_map.add_child(props)
	return AuthoringEditor.create(_doc, _map, _history)


func _masks() -> Dictionary:
	return {
		"ids": _doc.biome_ids.duplicate(),
		"slots": _doc.biome_slots.duplicate(),
		"density": _doc.biome_density.duplicate(),
	}


func _stroke(editor: AuthoringEditor, mode: int, biome: String, at: Vector3) -> void:
	assert_true(editor.begin_stroke(mode, biome))
	editor.stroke_dab(at, at + Vector3(4, 0, 1), 3.0, 0.4)
	editor.flush()
	editor.end_stroke()


func test_strokes_undo_and_redo_exactly() -> void:
	var editor := _editor()
	var edits := [0]
	editor.edited.connect(func() -> void: edits[0] += 1)
	var empty := _masks()
	_stroke(editor, MaskBrush.PAINT, BIOME, Vector3(-2, 0, 0))
	var painted := _masks()
	_stroke(editor, MaskBrush.PAINT, MEADOW, Vector3(0, 0, 0))
	var replaced := _masks()
	_stroke(editor, MaskBrush.THIN, "", Vector3(-1, 0, 1))
	var thinned := _masks()
	assert_eq(edits[0], 3)
	assert_eq(_history.undo_count(), 3)
	_history.undo()
	assert_eq(_masks(), replaced)
	_history.undo()
	assert_eq(_masks(), painted)
	_history.undo()
	assert_eq(_masks(), empty)
	_history.redo()
	_history.redo()
	_history.redo()
	assert_eq(_masks(), thinned)


func test_a_cancelled_stroke_leaves_no_trace() -> void:
	var editor := _editor()
	_stroke(editor, MaskBrush.PAINT, BIOME, Vector3.ZERO)
	var before := _masks()
	assert_true(editor.begin_stroke(MaskBrush.PAINT, MEADOW))
	editor.stroke_dab(Vector3.ZERO, Vector3(5, 0, 0), 4.0, 1.0)
	editor.flush()
	editor.cancel_stroke()
	assert_eq(_masks(), before)
	assert_eq(_history.undo_count(), 1)


func test_strokes_follow_the_map_root_frame() -> void:
	_map.scale = Vector3(2, 2, 2)
	_map.position = Vector3(10, 0, 0)
	var editor := _editor()
	assert_true(editor.begin_stroke(MaskBrush.PAINT, BIOME))
	# World (10, 0, 0) is the document origin; a 4 m world brush is 2 m of document.
	editor.stroke_dab(Vector3(10, 0, 0), Vector3(10, 0, 0), 4.0, 1.0)
	editor.end_stroke()
	var centre := _doc.world_to_sample(Vector2.ZERO).round()
	var past := _doc.world_to_sample(Vector2(2.2, 0)).round()
	assert_gt(_doc.biome_density[_doc.sample_index(int(centre.x), int(centre.y))], 200)
	assert_eq(_doc.biome_density[_doc.sample_index(int(past.x), int(past.y))], 0)


func test_placing_turning_and_removing_a_prop_round_trips() -> void:
	var editor := _editor(true)
	var rule := editor.species_rule(BIOME, "oak")
	assert_false(rule.is_empty(), "the palette's temperate oak")
	var handle := editor.place_prop(rule, Vector3(3, 0, 4), Vector3.UP)
	assert_false(handle.is_empty())
	handle = editor.turn_prop(handle, 1.0)
	editor.commit_prop_edit()
	assert_eq(_history.undo_count(), 1, "place and turn are one gesture")
	var placed := editor.props.rows_by_asset()
	assert_eq(MapDocument.row_count(placed), 1)
	var row := PropRows.row_at(placed[handle.asset_id], 0)
	assert_almost_eq(PropRows.row_yaw(row), 1.0, 1e-4)
	assert_almost_eq(Vector3(row[0], row[1], row[2]), Vector3(3, 0, 4), Vector3.ONE * 1e-5)
	var found := editor.prop_at(Vector3(3.2, 0, 4.1))
	assert_eq(found.get("row"), row, "picked under the pointer")
	editor.remove_prop(found)
	assert_eq(MapDocument.row_count(editor.props.rows_by_asset()), 0)
	_history.undo()
	assert_eq(editor.props.rows_by_asset(), placed, "undo of the removal")
	_history.undo()
	assert_eq(MapDocument.row_count(editor.props.rows_by_asset()), 0, "undo of the placement")
	_history.redo()
	assert_eq(editor.props.rows_by_asset(), placed)


func test_scaling_stays_in_the_species_range_and_records_once() -> void:
	var editor := _editor(true)
	var rule := editor.species_rule(BIOME, "boulder")
	var handle := editor.place_prop(rule, Vector3(-5, 0, -5), Vector3.UP)
	editor.commit_prop_edit()
	for i in 20:
		handle = editor.scale_prop(handle, 1.0, rule)
	var limits := PropRows.scale_range(rule)
	assert_almost_eq((handle.row as PackedFloat32Array)[7], limits.y, 1e-5)
	editor.tick(AuthoringEditor.SCALE_COMMIT_SECONDS + 0.1)
	assert_eq(_history.undo_count(), 2, "the scale notches are one entry")
	_history.undo()
	var rows := editor.props.rows_by_asset()
	assert_almost_eq(rows[handle.asset_id][7], 1.0, 1e-6)


func test_a_cancelled_placement_is_not_recorded() -> void:
	var editor := _editor(true)
	var rule := editor.species_rule(BIOME, "boulder")
	editor.place_prop(rule, Vector3(1, 0, 1), Vector3.UP)
	editor.cancel_prop_edit()
	assert_eq(MapDocument.row_count(editor.props.rows_by_asset()), 0)
	assert_eq(_history.undo_count(), 0)


func test_rule_for_asset_finds_the_species() -> void:
	var editor := _editor()
	var rule := editor.species_rule(BIOME, "boulder")
	var asset_id := String(rule.assets[0])
	assert_eq(editor.rule_for_asset(asset_id).get("key"), "boulder")
	assert_true(editor.rule_for_asset("nope/nothing").is_empty())
