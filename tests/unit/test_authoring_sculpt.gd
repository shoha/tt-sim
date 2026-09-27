extends GutTest

## AuthoringEditor's height strokes (phase 3, P3-3a): a sculpt stroke changes the document's
## heights, the terrain and collision follow it, generated plants and placed props stay on
## the ground, and one history entry undoes and redoes all of it; a cancelled stroke leaves
## no trace. Uses the built-in palette (temperate forest), like test_authoring_editor.gd.
## MultiMesh transforms read back as identity headless, so rows are checked, not nodes.

const BIOME := "temperate_forest_summer_s1"
const GRASS := BIOME + "/Grass_Short_summer_19"

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _ground(p: Vector2) -> float:
	return ScatterGenerator.document_fields(_doc, "").height_at.call(p)


func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p in points:
		rows.append_array([p.x, _ground(p), p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _raise(editor: AuthoringEditor, at: Vector3, seconds: float = 1.0) -> void:
	assert_true(editor.begin_height_stroke(HeightBrush.RAISE))
	editor.stroke_dab(at, at + Vector3(1, 0, 0), 4.0, seconds)
	editor.flush()


func test_a_sculpt_stroke_moves_plants_and_props_and_undoes_as_one() -> void:
	var editor := _editor()
	var rule := editor.species_rule(BIOME, "boulder")
	var handle := editor.place_prop(rule, Vector3(1, 0, 1), Vector3.UP)
	editor.commit_prop_edit()
	var near := Vector2(2.0, 0.5)
	var far := Vector2(8.5, 8.5)
	editor.scatter.set_cells({Vector2i.ZERO: {GRASS: _rows([near, far])}}, false)
	var start_heights := _doc.heights.duplicate()
	var start_props := editor.props.rows_by_asset()
	_raise(editor, Vector3.ZERO)
	assert_true(editor.end_stroke())
	assert_eq(_history.undo_count(), 2, "the placement and the stroke")
	assert_ne(_doc.heights, start_heights)
	var raised_heights := _doc.heights.duplicate()
	var rows: PackedFloat32Array = editor.scatter.cell_rows(Vector2i.ZERO)[GRASS]
	assert_gt(rows[1], 1.0, "the plant on the hill rose with it")
	assert_almost_eq(rows[1], _ground(near), 1e-5, "onto the ground")
	assert_almost_eq(rows[11], 0.0, 1e-6, "the plant off the hill did not move")
	var prop: PackedFloat32Array = editor.props.rows_by_asset()[handle.asset_id]
	assert_almost_eq(prop[1], _ground(Vector2(1, 1)), 1e-5, "the prop is re-bedded")
	var raised_props := editor.props.rows_by_asset()
	editor.finish_height_work()
	assert_false(editor.has_height_work())
	_history.undo()
	assert_eq(_doc.heights, start_heights, "undo restores the heights")
	assert_eq(editor.props.rows_by_asset(), start_props, "and the prop")
	rows = editor.scatter.cell_rows(Vector2i.ZERO)[GRASS]
	assert_almost_eq(rows[1], 0.0, 1e-6, "and puts the plant back on the ground")
	_history.redo()
	assert_eq(_doc.heights, raised_heights, "redo")
	assert_eq(editor.props.rows_by_asset(), raised_props)
	rows = editor.scatter.cell_rows(Vector2i.ZERO)[GRASS]
	assert_almost_eq(rows[1], _ground(near), 1e-5)


func test_a_cancelled_sculpt_leaves_no_trace() -> void:
	var editor := _editor()
	var rows := _rows([Vector2(1.0, 1.0)])
	editor.scatter.set_cells({Vector2i.ZERO: {GRASS: rows}}, false)
	var start := _doc.heights.duplicate()
	_raise(editor, Vector3.ZERO)
	assert_gt((editor.scatter.cell_rows(Vector2i.ZERO)[GRASS] as PackedFloat32Array)[1], 0.5)
	editor.cancel_stroke()
	assert_eq(_doc.heights, start)
	assert_eq(editor.scatter.cell_rows(Vector2i.ZERO)[GRASS], rows, "the plant is back")
	assert_eq(_history.undo_count(), 0)
	assert_false(editor.is_stroking())


func test_the_brush_finds_the_new_ground_mid_stroke_and_the_collision_at_the_end() -> void:
	var editor := _editor()
	await wait_physics_frames(2)
	_raise(editor, Vector3.ZERO)
	assert_true(editor.is_sculpting())
	var down := Vector3(0.4, -1.0, 0.3).normalized()
	var ground := editor.raycast_ground(Vector3(0.3, 0, 0.2) - down * 40.0, down)
	assert_false(ground.is_empty(), "the march finds the ground")
	var at: Vector3 = ground.get("position", Vector3.ZERO)
	assert_almost_eq(at.y, _ground(Vector2(at.x, at.z)), 0.001, "on the surface")
	assert_gt(at.y, 1.0, "the raised surface")
	var space := _map.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(0.3, 50, 0.2), Vector3(0.3, -50, 0.2), 1
	)
	var stale := space.intersect_ray(query)
	assert_almost_eq(float(stale.get("position", Vector3.ONE).y), 0.0, 0.001, "not mid-stroke")
	editor.end_stroke()
	var hit := space.intersect_ray(query)
	assert_false(hit.is_empty())
	if not hit.is_empty():
		assert_almost_eq(hit.position.y, _ground(Vector2(0.3, 0.2)), 0.01, "collision at the end")


func test_sculpting_is_refused_on_a_dressed_map() -> void:
	_doc.has_base_map = true
	var editor := _editor()
	assert_false(editor.can_sculpt())
	assert_false(editor.begin_height_stroke(HeightBrush.RAISE))
	assert_false(editor.is_stroking())


func test_flatten_holds_the_height_under_the_press() -> void:
	var editor := _editor()
	_raise(editor, Vector3.ZERO, 2.0)
	editor.end_stroke()
	var target := editor.ground_height_at(Vector3(0.5, 0, 0.0))
	assert_gt(target, 1.0)
	assert_true(editor.begin_height_stroke(HeightBrush.FLATTEN, target))
	for _frame in 40:
		editor.stroke_dab(Vector3(3, 0, 0), Vector3(3, 0, 0), 3.0, 0.1)
	editor.flush()
	editor.end_stroke()
	assert_almost_eq(editor.ground_height_at(Vector3(3, 0, 0)), target, 0.02)
	assert_eq(_history.undo_count(), 2)


func test_leftover_work_drains_over_frames() -> void:
	var editor := _editor()
	_raise(editor, Vector3(-10, 0, -10))
	editor.stroke_dab(Vector3(-10, 0, -10), Vector3(12, 0, 12), 8.0, 1.0)
	editor.flush()
	editor.end_stroke()
	var frames := 0
	while editor.has_height_work() and frames < 200:
		await wait_process_frames(1)
		editor.step_height_work()
		frames += 1
	assert_false(editor.has_height_work(), "drained in %d frames" % frames)
	var terrain := _map.get_node("AuthoredTerrain") as AuthoredTerrain
	assert_false(terrain.has_unsettled_chunks(), "every edited chunk settled")
