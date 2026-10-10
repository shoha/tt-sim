extends GutTest

## One camera model for play and authoring (MapViewFit): a play-time load of an authored
## level gets authoring's whole-map zoom-out and pan bounds, and the sun's shadows follow the
## zoomed-out view past the fixed 100 m; clearing the map puts the zoom limit back.
##
## The play path runs through the real LevelPlayController and GameMap (wired as
## Root._enter_playing_state wires them). The level is a 200 ft map document in a level
## folder under Paths.LEVELS_DIR (the GUT run's own test data root); it is removed after each
## test.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const FOLDER := "_authparity_view_fit_gut"
const CELLS := Vector2i(40, 40)
const LOAD_TIMEOUT := 30.0

var _controller: LevelPlayController
var _game_map: GameMap


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 7)
	assert_eq(MapDocumentIO.write(doc, Paths.get_level_map_document_path(FOLDER)), OK)
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


func _level() -> LevelData:
	var level := LevelData.new()
	level.level_name = FOLDER
	level.level_folder = FOLDER
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	return level


func test_view_bounds_span_the_ground_range_over_the_extent() -> void:
	var local := AABB(Vector3(-10.0, 0.0, -5.0), Vector3(20.0, 0.0, 10.0))
	var to_world := Transform3D(Basis.from_scale(Vector3(2.0, 1.0, 2.0)), Vector3(1.0, 0.0, 0.0))
	var bounds := MapViewFit.view_bounds(local, to_world, Vector2(-1.5, 4.0))
	assert_eq(bounds.position, Vector3(-19.0, -1.5, -10.0))
	assert_eq(bounds.size, Vector3(40.0, 5.5, 20.0))


func test_play_gets_the_whole_map_zoom_and_the_view_following_shadows() -> void:
	_controller.play_level(_level())
	assert_true(await wait_for_signal(_controller.level_loading_completed, LOAD_TIMEOUT))
	var cc := _game_map.get_camera_controller()
	var extent := Vector2(CELLS) * LevelData.DEFAULT_GRID_CELL_SIZE
	var fit := (
		CameraController.fit_size_for_extent(
			_game_map.camera_node.global_basis, extent, MapViewFit.CONTENT_HEIGHT_M
		)
		* MapViewFit.ZOOM_FIT_MARGIN
	)
	assert_gt(fit, MapViewFit.PLAY_MAX_ZOOM, "a 200 ft map needs more than the old 20")
	assert_almost_eq(cc.max_zoom, fit, 0.01, "play reaches the whole map, as authoring does")
	var pan: AABB = cc.get("_map_bounds")
	assert_almost_eq(pan.size.x, extent.x, 0.001, "an authored map pans within its extent")
	var sun := _controller.get_environment_manager().get_sun_light()
	assert_not_null(sun)
	cc.adjust_zoom(1000.0)
	var wide: float = cc.call("_corrected_size", cc.max_zoom)
	var zoomed_out := func() -> bool: return absf(_game_map.camera_node.size - wide) < 0.05
	assert_true(await wait_until(zoomed_out, 5.0), "zoomed all the way out")
	await wait_process_frames(2)
	assert_gt(
		sun.directional_shadow_max_distance,
		LevelEnvironmentManager.SUN_SHADOW_MAX_DISTANCE,
		"the shadows reach the far side of the whole-map view"
	)
	_controller.clear_level_map()
	assert_eq(cc.max_zoom, MapViewFit.PLAY_MAX_ZOOM, "a cleared map gives the limit back")
