extends GutTest

## FoliageLibrary (utils/foliage_library.gd): the runtime choice between the installed palette
## (treecube) and a built plantgen package laid over it. Switching clears the palette and wind
## caches, the overlay goes away when treecube is chosen again, an unknown library or package is
## refused without touching anything, the choice round-trips through the settings file, and a
## map saved under the other library has its scatter regenerated from the biome painting.
##
## Fixture, built on the fly under user://: an installed palette with a meadow (Bell, Daisy, Old)
## and a forest (Oak), and a package with the meadow only: Bell byte-identical, Daisy rebuilt,
## Old gone, New added (the model is test_palette_overlay.gd).

const ROOT := "user://test_foliage_library"
const BASE := ROOT + "/base"
const PACKAGE := ROOT + "/package"
const SETTINGS := ROOT + "/settings.cfg"
const MEADOW := "meadow_summer_s1"
const FOREST := "forest_summer_s1"

var _saved_settings_path: String = ""


func before_all() -> void:
	_write_glb(BASE, MEADOW, "Bell", _card_mesh(1))
	_write_glb(BASE, MEADOW, "Daisy", _card_mesh(1))
	_write_glb(BASE, MEADOW, "Old", _card_mesh(1))
	_write_glb(BASE, FOREST, "Oak", _card_mesh(1))
	_write_document(BASE, [_biome(MEADOW, ["Bell", "Daisy", "Old"]), _biome(FOREST, ["Oak"])])
	DirAccess.make_dir_recursive_absolute(PACKAGE.path_join("assets").path_join(MEADOW))
	var bell := "assets/%s/Bell.glb" % MEADOW
	DirAccess.copy_absolute(BASE.path_join(bell), PACKAGE.path_join(bell))
	_write_glb(PACKAGE, MEADOW, "Daisy", _card_mesh(2))
	_write_glb(PACKAGE, MEADOW, "New", _card_mesh(3))
	_write_document(PACKAGE, [_biome(MEADOW, ["Bell", "Daisy", "New"])])
	_saved_settings_path = FoliageLibrary.settings_path
	FoliageLibrary.settings_path = SETTINGS


func after_all() -> void:
	FoliageLibrary.settings_path = _saved_settings_path
	FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	PaletteLibrary.clear_cache()
	_remove_tree(ROOT)


func before_each() -> void:
	FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	DirAccess.remove_absolute(SETTINGS)


func _card_mesh(surface_count: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in surface_count:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(0.5, 0, 0.2), Vector3(0, 2, 0.1)]
		)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0, 0)])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(
			[Color(0, 0, 0.2), Color(0, 0, 0.4), Color(1, 1, 0.6)]
		)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, StandardMaterial3D.new())
	return mesh


func _write_glb(root_path: String, biome_id: String, object_name: String, mesh: Mesh) -> void:
	DirAccess.make_dir_recursive_absolute(root_path.path_join("assets").path_join(biome_id))
	var root := Node3D.new()
	root.name = "Root"
	var node := MeshInstance3D.new()
	node.name = object_name
	node.mesh = mesh
	root.add_child(node)
	node.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	document.write_to_filesystem(
		state, root_path.path_join("assets/%s/%s.glb" % [biome_id, object_name])
	)
	root.free()


func _biome(biome_id: String, names: Array) -> Dictionary:
	var ids: Array = names.map(func(n: String) -> String: return "%s/%s" % [biome_id, n])
	return {
		"id": biome_id,
		"biome": biome_id.get_slice("_", 0),
		"season": "summer",
		"seed": 1,
		"name": biome_id,
		"climate": "temperate",
		"thumbnail": "thumbnails/%s.jpg" % biome_id,
		"ground_surface": "grass",
		"species":
		[
			{
				"key": "flower",
				"kind": "flower",
				"size_class": "small",
				"density_per_m2": 0.5,
				"min_spacing_m": 0.3,
				"slope_max_deg": 35.0,
				"scale_spread": 0.3,
				"yaw_random_deg": 360.0,
				"align": "upright",
				"near": [],
				"avoid": [],
				"assets": ids,
			}
		],
	}


func _write_document(root_path: String, biomes: Array) -> void:
	var assets := {}
	for biome: Dictionary in biomes:
		for asset_id: String in biome["species"][0]["assets"]:
			assets[asset_id] = {
				"file": "assets/%s.glb" % asset_id,
				"node": asset_id.get_slice("/", 1),
				"wind_category": "grass",
				"size_class": "small",
				"dimensions_m": [0.5, 2.0, 0.1],
			}
	var surface := {
		"albedo": "surfaces/grass/grass_albedo.png",
		"normal": "surfaces/grass/grass_normal.png",
		"orm": "surfaces/grass/grass_orm.png",
		"height": "surfaces/grass/grass_height.png",
		"tile_m": 2.0,
		"kind": "grass",
		"role": "ground",
	}
	var document := {
		"format": 1,
		"palette_version": root_path.get_file(),
		"surfaces": {"grass": surface},
		"biomes": biomes,
		"assets": assets,
	}
	var file := FileAccess.open(root_path.path_join("palette.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_tree(path: String) -> void:
	if LibraryPaths.verify(path) != "":  # "" and "." mean the working directory (the project)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


## A document painted all with the meadow, whose scatter holds one row of each of `asset_ids`.
func _document(asset_ids: Array) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "", "", 7)
	doc.biome_ids = PackedStringArray([MEADOW])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(1)
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(255)
	doc.biome_slots = slots
	doc.biome_density = density
	for asset_id: String in asset_ids:
		doc.scatter[asset_id] = PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	return doc


func _asset_ids(root: String) -> Array:
	return (PaletteLibrary.get_palette(root)["assets"] as Dictionary).keys()


func test_plantgen_lays_the_package_over_every_biome_and_treecube_takes_it_off() -> void:
	var result := FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	assert_true(result["ok"], str(result["error"]))
	assert_eq(FoliageLibrary.current(), FoliageLibrary.PLANTGEN)
	assert_eq(FoliageLibrary.active_package(), PACKAGE)
	var ids := _asset_ids(BASE)
	assert_has(ids, MEADOW + "/New", "the package's asset")
	assert_does_not_have(ids, MEADOW + "/Old", "the installed meadow's own asset went")
	assert_has(ids, FOREST + "/Oak", "a biome the package lacks is left alone")
	var back := FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	assert_true(back["ok"])
	assert_eq(FoliageLibrary.current(), FoliageLibrary.TREECUBE)
	assert_eq(FoliageLibrary.active_package(), "")
	ids = _asset_ids(BASE)
	assert_has(ids, MEADOW + "/Old", "the installed palette is back")
	assert_does_not_have(ids, MEADOW + "/New", "the overlay is gone")


func test_a_switch_drops_the_cached_meshes_of_the_other_library() -> void:
	var before := PaletteLibrary.resolve(MEADOW + "/Daisy", BASE)["mesh"] as Mesh
	assert_eq(before.get_surface_count(), 1)
	FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	var rebuilt := PaletteLibrary.resolve(MEADOW + "/Daisy", BASE)["mesh"] as Mesh
	assert_eq(rebuilt.get_surface_count(), 2, "the package's rebuilt daisy")
	FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	var again := PaletteLibrary.resolve(MEADOW + "/Daisy", BASE)["mesh"] as Mesh
	assert_eq(again.get_surface_count(), 1, "the installed daisy again")


func test_a_switch_resets_the_wind_representatives() -> void:
	WindFoliage.representative_assets()
	assert_false(WindFoliage._representative_ids.is_empty(), "primed from the installed palette")
	FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	assert_true(WindFoliage._representative_ids.is_empty(), "forgotten on a switch")
	assert_true(WindFoliage._representative_formats.is_empty())


func test_an_unknown_library_or_package_changes_nothing() -> void:
	FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	var served := PaletteLibrary.get_palette(BASE)
	var unknown := FoliageLibrary.apply("speedtree", PACKAGE, BASE)
	assert_false(unknown["ok"])
	assert_string_contains(String(unknown["error"]), "speedtree")
	var missing := FoliageLibrary.apply(FoliageLibrary.PLANTGEN, ROOT + "/nowhere", BASE)
	assert_false(missing["ok"])
	assert_string_contains(String(missing["error"]), "nowhere")
	var empty := FoliageLibrary.apply(FoliageLibrary.PLANTGEN, "", BASE)
	assert_false(empty["ok"], "no folder given and none saved")
	assert_eq(FoliageLibrary.current(), FoliageLibrary.PLANTGEN, "still serving what it did")
	assert_same(PaletteLibrary.get_palette(BASE), served, "the cache was not touched")


func test_a_package_that_cannot_be_laid_over_falls_back_to_treecube() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/empty_package")
	var file := FileAccess.open(ROOT + "/empty_package/palette.json", FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	var result := FoliageLibrary.apply(FoliageLibrary.PLANTGEN, ROOT + "/empty_package", BASE)
	assert_false(result["ok"])
	assert_eq(FoliageLibrary.current(), FoliageLibrary.TREECUBE)
	assert_has(_asset_ids(BASE), MEADOW + "/Old", "the installed palette serves")


func test_the_choice_round_trips_through_the_settings_file() -> void:
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.TREECUBE, "the default")
	assert_eq(FoliageLibrary.package_path(), "")
	assert_false(FoliageLibrary.available(), "no folder, nothing to offer")
	FoliageLibrary.save_settings(FoliageLibrary.PLANTGEN, PACKAGE)
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.PLANTGEN)
	assert_eq(FoliageLibrary.package_path(), PACKAGE)
	assert_true(FoliageLibrary.available())
	FoliageLibrary.save_settings(FoliageLibrary.TREECUBE)
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.TREECUBE)
	assert_eq(FoliageLibrary.package_path(), PACKAGE, "the folder is kept")
	FoliageLibrary.save_settings("nonsense", ROOT + "/nowhere")
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.TREECUBE, "unknown reads as treecube")
	assert_false(FoliageLibrary.available(), "a folder without a palette is not offered")


func test_apply_saved_serves_the_saved_library() -> void:
	FoliageLibrary.apply_saved()
	assert_eq(FoliageLibrary.current(), FoliageLibrary.TREECUBE)
	FoliageLibrary.save_settings(FoliageLibrary.PLANTGEN, ROOT + "/nowhere")
	FoliageLibrary.apply_saved()
	assert_eq(FoliageLibrary.current(), FoliageLibrary.TREECUBE, "a missing package is warned about")
	assert_engine_error("no plantgen package")


func test_switch_persists_and_announces_only_a_change_that_worked() -> void:
	watch_signals(EventBus)
	var failed := FoliageLibrary.switch(FoliageLibrary.PLANTGEN, ROOT + "/nowhere")
	assert_false(failed["ok"])
	assert_engine_error("no plantgen package")
	assert_signal_not_emitted(EventBus, "foliage_library_changed")
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.TREECUBE, "nothing persisted")
	var worked := FoliageLibrary.switch(FoliageLibrary.PLANTGEN, PACKAGE)
	assert_true(worked["ok"], str(worked["error"]))
	assert_signal_emit_count(EventBus, "foliage_library_changed", 1)
	assert_eq(get_signal_parameters(EventBus, "foliage_library_changed"), ["plantgen"])
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.PLANTGEN)
	FoliageLibrary.switch(FoliageLibrary.TREECUBE, "", false)
	assert_eq(FoliageLibrary.saved_library(), FoliageLibrary.PLANTGEN, "persist false leaves it")
	assert_signal_emit_count(EventBus, "foliage_library_changed", 2)


func test_analyse_names_the_assets_the_library_lacks() -> void:
	FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	var doc := _document([MEADOW + "/Old", MEADOW + "/Bell"])
	doc.props[MEADOW + "/Old"] = PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	var report := FoliageLibrary.analyse(doc, BASE)
	assert_eq(report["missing_ids"], PackedStringArray([MEADOW + "/Old"]))
	assert_eq(report["missing_rows"], 1)
	assert_eq(report["props_missing"], 1)
	assert_eq(FoliageLibrary.describe(report), "", "analysis alone says nothing")


func test_rows_the_library_lacks_are_regenerated_from_the_biome_painting() -> void:
	FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	var doc := _document([MEADOW + "/Old"])
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), BASE)
	assert_true(report["regenerated"])
	assert_gt(report["rows"], 0, "the painted meadow grows plants")
	var ids := _asset_ids(BASE)
	for asset_id: String in doc.scatter:
		assert_has(ids, asset_id, "every row now names an asset the library has")
	assert_does_not_have(doc.scatter.keys(), MEADOW + "/Old")
	assert_string_contains(FoliageLibrary.describe(report), "plantgen")
	assert_true(FoliageLibrary.analyse(doc, BASE)["missing_ids"].is_empty())
	var rows := _row_count(doc)
	var again: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), BASE)
	assert_false(again["regenerated"], "nothing missing the second time")
	assert_eq(_row_count(doc), rows, "and the rows stay")


func test_regeneration_is_deterministic() -> void:
	FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	var first := _document([MEADOW + "/Old"])
	var second := _document([MEADOW + "/Old"])
	await FoliageLibrary.adapt_async(first, get_tree(), BASE)
	await FoliageLibrary.adapt_async(second, get_tree(), BASE)
	assert_eq(first.scatter.keys(), second.scatter.keys())
	for asset_id: String in first.scatter:
		assert_eq(first.scatter[asset_id], second.scatter[asset_id])


func test_a_document_that_resolves_is_left_alone() -> void:
	var doc := _document([MEADOW + "/Old"])
	var before: PackedFloat32Array = doc.scatter[MEADOW + "/Old"].duplicate()
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), BASE)
	assert_false(report["regenerated"], "the installed palette has Old")
	assert_eq(doc.scatter[MEADOW + "/Old"], before)


func test_rows_with_no_painting_to_regenerate_from_are_left_alone() -> void:
	FoliageLibrary.apply(FoliageLibrary.PLANTGEN, PACKAGE, BASE)
	var doc := _document([MEADOW + "/Old"])
	doc.biome_ids = PackedStringArray()
	var report: Dictionary = await FoliageLibrary.adapt_async(doc, get_tree(), BASE)
	assert_false(report["regenerated"])
	assert_eq(report["missing_ids"], PackedStringArray([MEADOW + "/Old"]))
	assert_has(doc.scatter.keys(), MEADOW + "/Old", "the build skips it with its usual warning")


func _row_count(doc: MapDocument) -> int:
	var total := 0
	for asset_id: String in doc.scatter:
		total += doc.scatter[asset_id].size() / MapDocument.ROW_STRIDE
	return total
