extends GutTest

## LevelPlayLoader's map-source branch: which files a level loads from (GLB, document,
## both, or what is missing), and what load_map_sources_async() builds for each: a bare
## root with AuthoredTerrain and the authored-map lighting for a document-only map, the GLB
## root for a GLB, and one AuthoredScatter under the root for the document's rows.
##
## Fixtures are small (a 4 x 4 cell document, a one-box GLB) and live in a level folder
## under Paths.LEVELS_DIR (the GUT run's own test data root, where LevelData resolves paths);
## it is removed after each test.

const FOLDER := "_gut_t4_loader"
const ROCK := "temperate_forest_summer_s1/Rock_Boulder_summer_04"


class FakeStreamer:
	extends Node
	var cached: Dictionary = {}

	func get_cached_map_file(level_folder: String, variant_id: String, _hash: String) -> String:
		return cached.get(level_folder + "/" + variant_id, "")


var _controller: LevelPlayController
var _loader: LevelPlayLoader


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))
	_controller = LevelPlayController.new()
	add_child_autofree(_controller)
	_loader = _controller._level_loader
	_loader.setup(_controller)
	var streamer := FakeStreamer.new()
	add_child_autofree(streamer)
	_controller._map_download_coordinator.streamer = streamer


func after_each() -> void:
	for path in [Paths.get_level_map_path(FOLDER), Paths.get_level_map_document_path(FOLDER)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(Paths.get_level_folder(FOLDER).trim_suffix("/"))


func _level(glb: bool, document: bool) -> LevelData:
	var level := LevelData.new()
	level.level_folder = FOLDER
	level.map_path = Paths.LEVEL_MAP_NAME if glb else ""
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME if document else ""
	return level


func _write_document(rows: PackedFloat32Array = PackedFloat32Array()) -> String:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 7)
	if not rows.is_empty():
		doc.scatter = {ROCK: rows}
	var path := Paths.get_level_map_document_path(FOLDER)
	assert_eq(MapDocumentIO.write(doc, path), OK)
	return path


func _write_glb() -> String:
	var scene := Node3D.new()
	var box := MeshInstance3D.new()
	box.name = "Ground"
	box.mesh = BoxMesh.new()
	scene.add_child(box)
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	assert_eq(document.append_from_scene(scene, state), OK)
	var path := Paths.get_level_map_path(FOLDER)
	assert_eq(document.write_to_filesystem(state, path), OK)
	scene.free()
	return path


func _write_bytes(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_sources_for_each_combination() -> void:
	var glb := _write_glb()
	var document := _write_document()
	var sources := _loader._resolve_map_sources(_level(true, false))
	assert_eq(sources["found"], {"map": glb})
	sources = _loader._resolve_map_sources(_level(false, true))
	assert_eq(sources["found"], {"ttmap": document})
	sources = _loader._resolve_map_sources(_level(true, true))
	assert_eq(sources["found"], {"map": glb, "ttmap": document})
	assert_eq(sources["missing"], [])


func test_missing_files_are_reported_and_the_cache_is_consulted() -> void:
	var sources := _loader._resolve_map_sources(_level(true, true))
	assert_eq(sources["found"], {})
	assert_eq(sources["missing"], ["map", "ttmap"])
	var streamer: FakeStreamer = _controller._map_download_coordinator.streamer
	streamer.cached = {FOLDER + "/ttmap": "user://asset_cache/x/ttmap.ttmap"}
	sources = _loader._resolve_map_sources(_level(true, true))
	assert_eq(sources["found"], {"ttmap": "user://asset_cache/x/ttmap.ttmap"})
	assert_eq(sources["missing"], ["map"])


func test_document_only_map_gets_terrain_and_authored_lighting() -> void:
	var root := await _loader.load_map_sources_async("", _write_document())
	assert_not_null(root)
	assert_not_null(root.get_node_or_null("AuthoredTerrain"))
	# Empty, but there for the table's live edits (MapSourceLoader.keep_props_apart).
	assert_not_null(root.get_node_or_null(MapSourceLoader.SCATTER_NODE), "a scatter node")
	assert_not_null(root.get_node_or_null(MapSourceLoader.PROPS_NODE), "a props node")
	var extras: Dictionary = root.get_meta(GlbUtils.SCENE_EXTRAS_META, {})
	assert_eq(extras, LevelPlayLoader.AUTHORED_MAP_LIGHTING)
	var lighting := GlbUtils.extract_lighting_config(root)
	assert_true(lighting.has("ambient_light_color"))
	assert_true(lighting.has("ambient_light_energy"))
	assert_eq(lighting.get("background_mode"), Environment.BG_COLOR, "a flat haze backdrop")
	assert_true(lighting.has("background_color"))
	assert_not_null(_controller.loaded_map_document)
	root.free()


func test_document_rows_become_one_authored_scatter() -> void:
	var rows := PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2.5, 0, -1, 0, 0, 0, 1, 1, 1, 1])
	var root := await _loader.load_map_sources_async("", _write_document(rows))
	var scatter := root.get_node_or_null("AuthoredScatter") as AuthoredScatter
	assert_not_null(scatter)
	var built := 0
	for child in scatter.get_children():
		if child is MultiMeshInstance3D:
			built += (child as MultiMeshInstance3D).multimesh.instance_count
	assert_eq(built, 2)
	assert_false(scatter.has_prepared_species(), "every species resolved before the build")
	root.free()


func test_glb_with_document_keeps_the_glb_root_and_adds_scatter() -> void:
	var rows := PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	var root := await _loader.load_map_sources_async(_write_glb(), _write_document(rows))
	assert_not_null(root)
	assert_not_null(root.find_child("Ground", true, false), "the GLB's own nodes")
	assert_null(root.get_node_or_null("AuthoredTerrain"), "a GLB brings its own ground")
	assert_not_null(root.get_node_or_null("AuthoredScatter"))
	assert_false(root.has_meta(GlbUtils.SCENE_EXTRAS_META), "no authored lighting over a GLB")
	root.free()


func test_unreadable_document_beside_a_glb_still_loads_the_glb() -> void:
	var glb := _write_glb()
	var broken := Paths.get_level_map_document_path(FOLDER)
	_write_bytes(broken, "not a zip")
	var root := await _loader.load_map_sources_async(glb, broken)
	assert_not_null(root)
	assert_not_null(root.find_child("Ground", true, false))
	assert_null(_controller.loaded_map_document)
	root.free()
	# One warning from the reader, one saying the GLB loads without its document.
	assert_engine_error(2)


func test_unreadable_document_alone_fails() -> void:
	var broken := Paths.get_level_map_document_path(FOLDER)
	_write_bytes(broken, "not a zip")
	var root := await _loader.load_map_sources_async("", broken)
	assert_null(root)
	assert_engine_error(1)
	assert_push_error(1)
