extends GutTest

## A dressed GLB (a map document with has_base_map over a map.glb) loads in play as authoring
## opens it: the document's heights are sampled from the GLB's collision and the generated
## rows that stood on the old flat ground are set down onto it
## (MapSourceLoader.fit_dressing_ground_async), while hand-placed props, kept in their own
## AuthoredProps node for a dressed document, stay where the Place brush bedded them.
##
## The play path runs through the real LevelPlayController and GameMap (wired as
## Root._enter_playing_state wires them). The GLB is one 8 x 8 m box with a collision twin
## whose top is at Y = GROUND_Y; the document is 4 x 4 cells, flat at 0, inside it. The level
## folder is under the real user://levels/ with a name no real level can have; it is removed
## after each test.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const FOLDER := "_authparity_dressed_gut"
const ROCK := "temperate_forest_summer_s1/Rock_Boulder_summer_04"
const GROUND_Y := 2.0
const LOAD_TIMEOUT := 30.0

var _controller: LevelPlayController
var _game_map: GameMap


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))
	_controller = LevelPlayController.new()
	add_child_autofree(_controller)
	_game_map = GAME_MAP_SCENE.instantiate()
	# DragAndDrop3D awaits the current scene's ready signal, and GUT's runner has no current
	# scene: a stand-in whose ready has already fired lets that wait sit harmlessly.
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(_game_map)
	get_tree().current_scene = null
	stand_in.free()
	_controller.setup(_game_map)
	_game_map.setup(_controller)


func after_each() -> void:
	var folder := Paths.get_level_folder(FOLDER)
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder.trim_suffix("/"))


func _write_glb() -> void:
	var scene := Node3D.new()
	var box := MeshInstance3D.new()
	box.name = "Ground-col"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 1.0, 8.0)
	box.mesh = mesh
	box.position = Vector3(0.0, GROUND_Y - 0.5, 0.0)
	scene.add_child(box)
	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	assert_eq(gltf.append_from_scene(scene, state), OK)
	assert_eq(gltf.write_to_filesystem(state, Paths.get_level_map_path(FOLDER)), OK)
	scene.free()


func _row(x: float, y: float, z: float) -> PackedFloat32Array:
	return PackedFloat32Array([x, y, z, 0, 0, 0, 1, 1, 1, 1])


func _write_document() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "", "v", 7)
	doc.has_base_map = true
	doc.scatter = {ROCK: _row(1.0, 0.0, 1.0)}
	doc.props = {ROCK: _row(-1.0, GROUND_Y, -1.0)}
	assert_eq(MapDocumentIO.write(doc, Paths.get_level_map_document_path(FOLDER)), OK)


func _level() -> LevelData:
	var level := LevelData.new()
	level.level_name = FOLDER
	level.level_folder = FOLDER
	level.map_path = Paths.LEVEL_MAP_NAME
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	return level


func _row_y(node_name: String) -> float:
	var root := _controller.loaded_map_instance
	var node := root.get_node_or_null(NodePath(node_name)) as AuthoredScatter
	assert_not_null(node, node_name)
	if node == null:
		return NAN
	var rows: PackedFloat32Array = node.rows_by_asset().get(ROCK, PackedFloat32Array())
	assert_eq(rows.size(), MapDocument.ROW_STRIDE, node_name + " holds its one row")
	return rows[1] if rows.size() == MapDocument.ROW_STRIDE else NAN


func test_a_dressed_glb_settles_its_plants_and_leaves_its_props() -> void:
	_write_glb()
	_write_document()
	_controller.play_level(_level())
	assert_true(await wait_for_signal(_controller.level_loading_completed, LOAD_TIMEOUT))
	var fit := _controller._level_loader.grid_ground_fit
	assert_eq(fit.get("settled_rows"), 1, "the generated row was set down")
	assert_eq(fit.get("missed"), 0, "every sample hit the GLB")
	assert_almost_eq(_row_y(MapSourceLoader.SCATTER_NODE), GROUND_Y, 0.01, "on the GLB ground")
	assert_eq(_row_y(MapSourceLoader.PROPS_NODE), GROUND_Y, "the bedded prop did not move")
	var heights := _controller.loaded_map_document.heights
	assert_almost_eq(heights[0], GROUND_Y, 0.01, "the document took the sampled ground")


func test_play_merges_props_only_for_a_document_without_a_base_map() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "", "v", 7)
	assert_false(MapSourceLoader.props_apart(doc, false), "play merges an authored map's props")
	assert_true(MapSourceLoader.props_apart(doc, true), "authoring keeps them apart")
	doc.has_base_map = true
	assert_true(MapSourceLoader.props_apart(doc, false), "and play does over a dressed GLB")
