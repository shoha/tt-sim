extends GutTest

## The library core: update_meta, MapImport's import and Replace (Keep dressing and Start
## fresh), the import source index and "Updated in Blender", and the round trip the contract
## asks for (docs/ASSET_PIPELINE.md section 11): an imported and replaced level's map.glb
## loads through GlbUtils.load_map with the footprint the import check reported. Levels and
## the index live in a _test_library_ folder under the run's data root, deleted after each
## test; LevelManager.levels_dir and ImportSources.path are put back.

const Fixtures := preload("res://tests/unit/glb_fixtures.gd")

var _root := ""
var _levels_dir := ""
var _sources_path := ""


func before_each() -> void:
	_root = Paths.DATA_ROOT + "_test_library_import/"
	_levels_dir = LevelManager.levels_dir
	_sources_path = ImportSources.path
	_remove_tree(_root)
	DirAccess.make_dir_recursive_absolute(_root + "levels/")
	DirAccess.make_dir_recursive_absolute(_root + "blender/harbour/")
	LevelManager.levels_dir = _root + "levels/"
	ImportSources.path = _root + "import_sources.cfg"


func after_each() -> void:
	_remove_tree(_root)
	LevelManager.levels_dir = _levels_dir
	ImportSources.path = _sources_path
	LevelManager.current_level = null
	LevelManager.current_level_path = ""


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path + sub + "/")
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + file_name)
	DirAccess.remove_absolute(path.trim_suffix("/"))


func _source(size: Vector2, file_name: String = "harbour/map.glb") -> String:
	var path := _root + "blender/" + file_name
	assert_eq(Fixtures.write_map(path, size), OK)
	return path


func _import(size: Vector2) -> String:
	var result := MapImport.write_import(_source(size))
	assert_true(result.ok, "imported: %s" % result.error)
	return result.folder


func _row(x: float, z: float) -> PackedFloat32Array:
	return PackedFloat32Array([x, 0.0, z, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])


## A dressing document over a `size` map with two props and two generated rows (one of each
## near the far corner), painted at density 200 everywhere, saved into `folder`'s level.
func _dress(folder: String, size: Vector2) -> MapDocument:
	var bounds := AABB(Vector3(-size.x, 0.0, -size.y) * 0.5, Vector3(size.x, 1.0, size.y))
	var doc := NewMap.create_dressing(bounds, 9)
	var rock := "birch_woodland_summer_s1/Rock_Small"
	var props := _row(0.0, 0.0)
	props.append_array(_row(size.x * 0.45, size.y * 0.45))
	var scatter := _row(1.0, 1.0)
	scatter.append_array(_row(-size.x * 0.45, size.y * 0.45))
	doc.props = {rock: props}
	doc.scatter = {rock: scatter}
	doc.biome_ids = PackedStringArray(["birch_woodland_summer_s1"])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(1)
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(200)
	doc.biome_slots = slots
	doc.biome_density = density
	assert_eq(MapDocumentIO.write(doc, LevelManager.map_document_path(folder)), OK)
	var level := LevelManager.load_level_folder(folder, false)
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	assert_ne(LevelManager.save_level_folder(level, folder), "")
	return doc


func _read_document(folder: String) -> MapDocument:
	return MapDocumentIO.read(LevelManager.map_document_path(folder)).document


func _json(folder: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LevelManager.json_path(folder)))


func test_a_map_is_named_after_its_file_or_its_folder() -> void:
	assert_eq(MapImport.default_name("D:/maps/harbour/map.glb"), "Harbour")
	assert_eq(MapImport.default_name("D:/maps/harbour/Map.glb"), "Harbour")
	assert_eq(MapImport.default_name("D:/maps/oak_lab_v2.glb"), "Oak Lab V2")
	assert_eq(MapImport.default_name("D:/maps/sunken-keep/map.glb"), "Sunken Keep")


func test_import_writes_the_map_the_level_and_the_source() -> void:
	var source := _source(Vector2(30.0, 20.0))
	var result: Dictionary = await MapImport.import_glb(source)
	assert_true(result.ok)
	assert_eq(result.error, "")
	assert_eq(result.folder, "harbour")
	assert_false(result.thumbnail, "no offscreen render under the headless renderer")
	assert_almost_eq(result.report.footprint_m.x, 30.0, 0.001)
	var folder: String = result.folder
	assert_eq(
		FileAccess.get_file_as_bytes(LevelManager.map_path(folder)),
		FileAccess.get_file_as_bytes(source)
	)
	var data := _json(folder)
	assert_eq(data.level_name, "Harbour")
	assert_eq(data.map_path, Paths.LEVEL_MAP_NAME)
	assert_false(data.has("map_scale"), "legacy, never written for an import")
	assert_false(data.has("map_offset"))
	var listed := LevelManager.get_saved_levels()
	assert_eq(listed.size(), 1)
	assert_eq(listed[0].name, "Harbour")
	assert_eq(ImportSources.source_of(folder), source)
	assert_false(MapImport.is_updated_in_blender(folder), "the copy is as new as its source")
	assert_true(FileAccess.file_exists(ImportSources.path))
	assert_false(FileAccess.file_exists(LevelManager.levels_dir + Paths.IMPORT_SOURCES_NAME))


func test_an_import_takes_the_name_given_and_never_overwrites_a_level() -> void:
	var source := _source(Vector2(10.0, 10.0))
	var first := MapImport.write_import(source, "  Sunken Keep ")
	var second := MapImport.write_import(source, "Sunken Keep")
	assert_eq(first.folder, "sunken_keep")
	assert_eq(second.folder, "sunken_keep_1")
	assert_eq(_json(first.folder).level_name, "Sunken Keep")


func test_a_refused_file_writes_nothing() -> void:
	var result := MapImport.write_import(_root + "blender/harbour/map.gltf")
	assert_false(result.ok)
	assert_eq(result.error, GlbCheck.REFUSE_GLTF)
	assert_eq(DirAccess.get_directories_at(LevelManager.levels_dir).size(), 0)
	assert_false(FileAccess.file_exists(ImportSources.path))


func test_updated_in_blender_once_the_source_is_newer_than_the_copy() -> void:
	var folder := _import(Vector2(30.0, 20.0))
	assert_false(MapImport.is_updated_in_blender(folder))
	assert_true(ImportSources.is_newer(1001, 1000))
	assert_false(ImportSources.is_newer(1000, 1000))
	# File times are whole seconds: export again in a later one.
	await wait_seconds(1.1)
	_source(Vector2(30.0, 24.0))
	assert_true(MapImport.is_updated_in_blender(folder))
	var reload := MapImport.write_replace(
		folder, ImportSources.source_of(folder), MapImport.KEEP_DRESSING
	)
	assert_true(reload.ok)
	assert_false(MapImport.is_updated_in_blender(folder), "reloaded")


func test_keep_dressing_drops_the_rows_off_a_smaller_map() -> void:
	var folder := _import(Vector2(40.0, 40.0))
	var before := _dress(folder, Vector2(40.0, 40.0))
	var smaller := _source(Vector2(20.0, 20.0), "harbour_v2.glb")
	var result: Dictionary = await MapImport.replace_map(folder, smaller, MapImport.KEEP_DRESSING)
	assert_true(result.ok, result.error)
	assert_eq(result.props_dropped, 1)
	assert_eq(result.scatter_dropped, 1)
	assert_eq(result.backup, "")
	var doc := _read_document(folder)
	assert_eq(doc.size_cells, before.size_cells, "a smaller map keeps the document's grid")
	assert_eq(MapDocument.row_count(doc.props), 1)
	assert_eq(MapDocument.row_count(doc.scatter), 1)
	assert_eq(doc.biome_density[doc.sample_index(0, 0)], 0, "no cover over the void")
	var centre := doc.sample_index(doc.samples_x() >> 1, doc.samples_z() >> 1)
	assert_eq(doc.biome_density[centre], 200)
	assert_eq(_json(folder).map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)
	assert_eq(
		FileAccess.get_file_as_bytes(LevelManager.map_path(folder)),
		FileAccess.get_file_as_bytes(smaller)
	)
	assert_eq(ImportSources.source_of(folder), smaller, "Replace remembers the new file")


func test_keep_dressing_grows_the_document_over_a_larger_map() -> void:
	var folder := _import(Vector2(20.0, 20.0))
	var before := _dress(folder, Vector2(20.0, 20.0))
	var larger := _source(Vector2(40.0, 30.0), "harbour_v3.glb")
	var result := MapImport.write_replace(folder, larger, MapImport.KEEP_DRESSING)
	assert_true(result.ok, result.error)
	assert_eq(result.props_dropped, 0)
	var doc := _read_document(folder)
	assert_eq(doc.size_cells, NewMap.dressing_cells(result.report.bounds))
	assert_true(doc.size_cells.x > before.size_cells.x)
	assert_eq(doc.heights.size(), doc.sample_count())
	var centre := doc.sample_index(doc.samples_x() >> 1, doc.samples_z() >> 1)
	assert_eq(doc.biome_density[centre], 200, "the painting carries over by position")
	assert_eq(doc.biome_density[doc.sample_index(0, 0)], 0, "new ground starts unpainted")
	assert_eq(MapDocument.row_count(doc.props), 2)


func test_start_fresh_keeps_the_old_document_as_a_backup() -> void:
	var folder := _import(Vector2(30.0, 30.0))
	_dress(folder, Vector2(30.0, 30.0))
	var source := _source(Vector2(30.0, 30.0), "harbour_v2.glb")
	var result := MapImport.write_replace(folder, source, MapImport.START_FRESH)
	assert_true(result.ok, result.error)
	var document := LevelManager.map_document_path(folder)
	assert_eq(result.backup, document + MapImport.BACKUP_SUFFIX)
	assert_false(FileAccess.file_exists(document))
	assert_not_null(MapDocumentIO.read(result.backup).document, "the backup is the old document")
	assert_eq(_json(folder).map_document, "")
	assert_eq(LevelManager.get_saved_levels().size(), 1, "still a level: it has its map.glb")
	assert_eq(Paths.get_level_map_file_for_variant(folder, "bak"), "", "never streamed")


func test_replace_refuses_without_touching_the_level() -> void:
	var folder := _import(Vector2(30.0, 30.0))
	var map_bytes := FileAccess.get_file_as_bytes(LevelManager.map_path(folder))
	var source := _source(Vector2(10.0, 10.0), "other.glb")
	assert_eq(MapImport.write_replace(folder, source, "maybe").error, MapImport.ERROR_MODE)
	var scene := MapImport.write_replace(folder, "D:/maps/x.tscn", MapImport.START_FRESH)
	assert_eq(scene.error, GlbCheck.REFUSE_SCENE)
	var missing := MapImport.write_replace("_no_such_level", source, MapImport.START_FRESH)
	assert_eq(missing.error, MapImport.ERROR_NO_LEVEL)
	assert_eq(FileAccess.get_file_as_bytes(LevelManager.map_path(folder)), map_bytes)


func test_keep_dressing_refuses_ground_built_in_tt_sim() -> void:
	var folder := _import(Vector2(30.0, 30.0))
	var doc := _dress(folder, Vector2(30.0, 30.0))
	doc.has_base_map = false
	doc.base_surface = "grass"
	assert_eq(MapDocumentIO.write(doc, LevelManager.map_document_path(folder)), OK)
	var source := _source(Vector2(30.0, 30.0), "other.glb")
	var result := MapImport.write_replace(folder, source, MapImport.KEEP_DRESSING)
	assert_eq(result.error, MapImport.ERROR_NOT_DRESSING)


func test_an_imported_and_replaced_map_loads_through_glb_utils() -> void:
	var folder := _import(Vector2(40.0, 40.0))
	_dress(folder, Vector2(40.0, 40.0))
	var source := _source(Vector2(24.0, 16.0), "harbour_v2.glb")
	var result := MapImport.write_replace(folder, source, MapImport.KEEP_DRESSING)
	assert_true(result.ok, result.error)
	var map := GlbUtils.load_map(LevelManager.map_path(folder))
	assert_not_null(map)
	if map == null:
		return
	add_child_autofree(map)
	var extras: Dictionary = map.get_meta(GlbUtils.SCENE_EXTRAS_META, {})
	assert_true(extras.has("tt_scatter_instances"))
	var bounds := LevelEnvironmentManager.compute_map_bounds(map)
	assert_almost_eq(bounds.size.x, result.report.footprint_m.x, 0.01, "check matches the load")
	assert_almost_eq(bounds.size.z, result.report.footprint_m.y, 0.01)
	assert_not_null(GlbUtils.find_node_of_type(map, "StaticBody3D"), "the colonly ground")
	var doc := _read_document(folder)
	assert_not_null(doc, "the kept dressing still reads")
	assert_true(doc.has_base_map)


func test_update_meta_edits_name_description_and_author_in_place() -> void:
	var folder := _import(Vector2(10.0, 10.0))
	LevelManager.current_level = LevelManager.load_level_folder(folder, false)
	LevelManager.current_level_path = "user://elsewhere/"
	var changes := {"name": "  Dusty Hollow ", "description": "A dry ford.", "author": "Ana"}
	assert_true(LevelManager.update_meta(folder, changes))
	var data := _json(folder)
	assert_eq(data.level_name, "Dusty Hollow")
	assert_eq(data.level_description, "A dry ford.")
	assert_eq(data.author, "Ana")
	assert_eq(data.level_folder, folder)
	assert_eq(LevelManager.current_level.level_name, "Dusty Hollow", "the loaded level follows")
	assert_eq(LevelManager.current_level_path, "user://elsewhere/")
	assert_true(LevelManager.update_meta(folder, {"author": "Bo"}))
	assert_eq(_json(folder).level_name, "Dusty Hollow", "fields not named stay")
	assert_false(LevelManager.update_meta(folder, {"name": "   "}), "a card never goes blank")
	assert_false(LevelManager.update_meta(folder, {"colour": "red"}))
	assert_false(LevelManager.update_meta(folder, {"name": 7}))
	assert_eq(_json(folder).author, "Bo")


func test_deleting_a_level_forgets_its_source() -> void:
	var folder := _import(Vector2(10.0, 10.0))
	assert_ne(ImportSources.source_of(folder), "")
	assert_true(LevelManager.delete_level_folder(LevelManager.folder_path(folder)))
	assert_eq(ImportSources.source_of(folder), "")
