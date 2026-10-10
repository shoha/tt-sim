extends GutTest

## Save equals reload: a map edited through AuthoringEditor (a sculpted hill, a Paint stroke,
## a biome stroke whose plants generate, a placed prop), written to map.ttmap and loaded back
## through MapSourceLoader the way play loads it, matches the session on every MapFingerprint
## key. Generated rows are snapped to the saved precision (MapDocumentIO.snap_rows), so a
## regenerated cell and the same cell read back are bit-equal. Uses the built-in palette's
## temperate forest, like test_authoring_sculpt.gd.

const BIOME := "temperate_forest_summer_s1"
const FOLDER := "user://_authparity_save_reload/"
const PATH := FOLDER + "map.ttmap"
## Frames the biome stroke's regeneration may take before the test gives up.
const REGEN_FRAMES := 600


func after_all() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(FOLDER.trim_suffix("/"))


func _session_root(doc: MapDocument) -> Node3D:
	var root := MapSourceLoader.create_authored_root(doc)
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		root.add_child(node)
	add_child_autofree(root)
	return root


func test_a_saved_map_reloads_as_the_session_showed_it() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var root := _session_root(doc)
	var editor := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	editor.scatter.attach_document(doc)
	assert_true(editor.begin_height_stroke(HeightBrush.RAISE))
	editor.stroke_dab(Vector3(-4, 0, 3), Vector3(-3, 0, 3), 4.0, 4.0)
	editor.flush()
	assert_true(editor.end_stroke())
	editor.finish_height_work()
	assert_true(editor.begin_surface_stroke("cobblestone", false))
	editor.stroke_dab(Vector3(3, 0, -4), Vector3(7, 0, -3), 2.0, 1.0)
	editor.flush()
	assert_true(editor.end_stroke())
	assert_true(editor.begin_stroke(MaskBrush.PAINT, BIOME))
	editor.stroke_dab(Vector3(-6, 0, 0), Vector3(2, 0, 4), 5.0, 1.0)
	editor.flush()
	editor.end_stroke()
	var frames := 0
	while editor.scatter.is_regenerating() and frames < REGEN_FRAMES:
		await get_tree().process_frame
		frames += 1
	assert_false(editor.scatter.is_regenerating(), "the biome's plants generated")
	var rule := editor.species_rule(BIOME, "boulder")
	assert_false(editor.place_prop(rule, Vector3(-4, 0, 3), Vector3.UP).is_empty())
	editor.commit_prop_edit()
	doc.scatter = editor.scatter.rows_by_asset()
	doc.props = editor.props.rows_by_asset()
	assert_false(doc.scatter.is_empty(), "plants to compare")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	assert_eq(MapDocumentIO.write(doc, PATH), OK)
	var session := MapFingerprint.of(root, doc)

	var loader := MapSourceLoader.new(get_tree())
	var loaded := await loader.load_async("", PATH)
	assert_not_null(loaded, "the saved map loads")
	if loaded == null:
		return
	add_child_autofree(loaded)
	var reloaded := MapFingerprint.of(loaded, loader.document)
	assert_eq(MapFingerprint.diff(session, reloaded), [] as Array[String], "every key matches")
	assert_eq(session.scatter_hash, reloaded.scatter_hash)
