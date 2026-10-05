extends GutTest

## Opening maps for authoring: MapSourceLoader with props kept apart (always two scatter
## nodes, even empty, and a GLB-only level loading as a dressing base), the camera zoom-out
## fit and the view-following shadow distance, Root's entry refusal, and the entry points on
## the level card, level grid and title.

const DIR := "user://test_authoring_open/"
const ROCK := "temperate_forest_summer_s1/Rock_Boulder_summer_04"
const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const ROOT_SCRIPT := preload("res://scenes/root.gd")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file_name)
	DirAccess.remove_absolute(DIR.trim_suffix("/"))


func _write_glb() -> String:
	var scene := Node3D.new()
	var box := MeshInstance3D.new()
	box.name = "Ground"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(12, 1, 8)
	box.mesh = mesh
	scene.add_child(box)
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	assert_eq(document.append_from_scene(scene, state), OK)
	var path := DIR + "map.glb"
	assert_eq(document.write_to_filesystem(state, path), OK)
	scene.free()
	return path


func _loader() -> MapSourceLoader:
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	return loader


func test_authoring_gets_scatter_and_props_nodes_apart() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 3)
	doc.props = {ROCK: PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])}
	var root := await _loader().build_async("", doc)
	assert_not_null(root.get_node_or_null("AuthoredTerrain"))
	var scatter := root.get_node_or_null(NodePath(MapSourceLoader.SCATTER_NODE)) as AuthoredScatter
	var props := root.get_node_or_null(NodePath(MapSourceLoader.PROPS_NODE)) as AuthoredScatter
	assert_not_null(scatter, "an empty scatter node exists for the brushes")
	assert_not_null(props)
	assert_true(scatter.rows_by_asset().is_empty())
	assert_eq(props.rows_by_asset().keys(), [ROCK], "props stay in their own node")
	root.free()


func test_cells_of_document_merges_for_play_and_splits_for_authoring() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 3)
	doc.scatter = {ROCK: PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])}
	doc.props = {ROCK: PackedFloat32Array([2, 0, 1, 0, 0, 0, 1, 1, 1, 1])}
	var merged := MapSourceLoader.cells_of_document(doc, false)
	assert_eq(merged.keys(), [MapSourceLoader.SCATTER_NODE])
	var cell_rows: Dictionary = merged[MapSourceLoader.SCATTER_NODE].values()[0]
	assert_eq(cell_rows[ROCK].size(), 20, "both rows in one node")
	var split := MapSourceLoader.cells_of_document(doc, true)
	assert_eq(split.size(), 2)


func test_a_glb_only_level_opens_as_a_dressing_base() -> void:
	var root := await _loader().build_async(_write_glb(), null)
	assert_not_null(root)
	assert_not_null(root.find_child("Ground", true, false), "the GLB is the base")
	assert_null(root.get_node_or_null("AuthoredTerrain"), "no authored ground over a GLB")
	assert_not_null(root.get_node_or_null(NodePath(MapSourceLoader.SCATTER_NODE)))
	add_child_autofree(root)
	var bounds := LevelEnvironmentManager.compute_map_bounds(root)
	var doc := NewMap.create_dressing(root.global_transform.affine_inverse() * bounds, 1)
	assert_true(doc.has_base_map)
	assert_true(doc.extent_m().x >= 12.0 and doc.extent_m().y >= 8.0, "covers the GLB")


func test_zoom_fit_for_a_200_ft_map_is_width_bound_at_16_9() -> void:
	var camera := Camera3D.new()
	camera.transform = Transform3D(
		Basis(
			Vector3(0.7071068, 0, -0.7071068),
			Vector3(-0.26030335, 0.9297765, -0.26030335),
			Vector3(0.6574513, 0.36812454, 0.6574513)
		),
		Vector3.ZERO
	)
	var extent := Vector2(40, 40) * LevelData.DEFAULT_GRID_CELL_SIZE
	var fit := CameraController.fit_size_for_extent(camera.transform.basis, extent, 0.0)
	var diagonal := extent.x * sqrt(2.0)
	assert_almost_eq(fit, diagonal / (16.0 / 9.0), 0.01, "the diagonal fills the width")
	assert_gt(fit, 20.0, "beyond the play camera's zoom-out")
	camera.free()


func test_shadow_distance_follows_the_view_only_past_the_play_range() -> void:
	assert_eq(LevelEnvironmentManager.shadow_distance_for_depth(50.0), 100.0)
	assert_eq(LevelEnvironmentManager.shadow_distance_for_depth(0.0), 100.0)
	var far := LevelEnvironmentManager.shadow_distance_for_depth(106.0)
	assert_gte(far * LevelEnvironmentManager.SUN_SHADOW_FADE_START, 106.0, "fade starts beyond")


func test_authoring_is_offline_only_and_needs_a_level_folder() -> void:
	assert_eq(ROOT_SCRIPT.authoring_refusal(null, false), "")
	assert_ne(ROOT_SCRIPT.authoring_refusal(null, true), "", "refused while networked")
	var builtin := LevelData.new()
	builtin.map_path = "res://assets/models/maps/x.glb"
	assert_ne(ROOT_SCRIPT.authoring_refusal(builtin, false), "")
	var folder := LevelData.new()
	folder.map_path = Paths.LEVEL_MAP_NAME
	assert_eq(ROOT_SCRIPT.authoring_refusal(folder, false), "")


func test_card_edit_map_reaches_the_title() -> void:
	var info := {
		"path": "user://x/a/",
		"folder": "a",
		"name": "A",
		"token_count": 0,
		"modified_at": 1,
		"thumbnail": "",
	}
	var title: TitleScreen = TITLE_SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]: return [info]
	add_child_autofree(title)
	watch_signals(title)
	var card: LevelCard = title.grid._cards[0]
	assert_eq(
		card._menu.get_item_text(card._menu.get_item_index(LevelCard.ACTION_EDIT_MAP)), "Edit map"
	)
	card._on_menu_id_pressed(LevelCard.ACTION_EDIT_MAP)
	assert_signal_emitted_with_parameters(title, "edit_map_requested", [info])
	title._on_build_map_pressed()
	assert_signal_emitted(title, "build_map_requested")


func test_new_map_dialog_spec_follows_the_tiles() -> void:
	var dialog := _dialog()
	assert_eq(dialog.current_spec()["size_ft"], NewMap.DEFAULT_SIZE_FT)
	dialog._on_size_selected(&"size_200")
	dialog._on_biome_selected(NewMapDialog.BARE_TILE)
	var spec := dialog.current_spec()
	assert_eq(spec["size_ft"], 200)
	assert_eq(spec["biome_id"], NewMap.BARE_BIOME)
	assert_eq(dialog.ground_caption.text, "Ground: grass")
	watch_signals(dialog)
	dialog._on_create_pressed()
	assert_signal_emitted(dialog, "map_chosen")


func _dialog() -> NewMapDialog:
	var dialog: NewMapDialog = (
		load("res://scenes/states/authoring/new_map_dialog.tscn").instantiate()
	)
	add_child_autofree(dialog)
	return dialog


func test_new_map_dialog_has_a_landform_tile_per_kind() -> void:
	var dialog := _dialog()
	var tiles := dialog.landform_field.tiles
	assert_eq(tiles.get_child_count(), StartingLandform.KINDS.size())
	assert_eq(tiles.columns, StartingLandform.KINDS.size())
	for kind in StartingLandform.KINDS:
		var tile := NewMapDialog.landform_tile(kind)
		assert_true(tiles.has_tile(tile), kind)
		var button: Button = tiles.get_node(String(tile))
		assert_eq(button.text, StartingLandform.NAMES[kind])
		assert_eq(button.tooltip_text, StartingLandform.CAPTIONS[kind])
		assert_not_null(button.icon, "icon for %s" % kind)


func test_new_map_dialog_landform_default_follows_the_biome() -> void:
	var dialog := _dialog()
	assert_ne(dialog.current_spec()["biome_id"], NewMap.BARE_BIOME)
	assert_eq(dialog.current_spec()["landform"], StartingLandform.DEFAULT)
	assert_eq(
		dialog.landform_field.tiles.selected, NewMapDialog.landform_tile(StartingLandform.DEFAULT)
	)
	assert_eq(dialog.landform_caption.text, StartingLandform.CAPTIONS[StartingLandform.DEFAULT])
	dialog._on_biome_selected(NewMapDialog.BARE_TILE)
	assert_eq(dialog.current_spec()["landform"], StartingLandform.FLAT)
	assert_eq(
		dialog.landform_field.tiles.selected, NewMapDialog.landform_tile(StartingLandform.FLAT)
	)
	assert_eq(dialog.landform_caption.text, StartingLandform.CAPTIONS[StartingLandform.FLAT])
	# Back to a biome: the landform shown before Bare ground returns.
	var biomes := PaletteLibrary.biomes(dialog.palette_root)
	if biomes.is_empty():
		return
	dialog._on_biome_selected(StringName(biomes[0]["id"]))
	assert_eq(dialog.current_spec()["landform"], StartingLandform.DEFAULT)


func test_new_map_dialog_landform_pick_sets_the_spec_and_caption() -> void:
	var dialog := _dialog()
	for kind in StartingLandform.KINDS:
		var button: Button = dialog.landform_field.tiles.get_node(
			String(NewMapDialog.landform_tile(kind))
		)
		button.button_pressed = true
		assert_eq(dialog.current_spec()["landform"], kind)
		assert_eq(dialog.landform_caption.text, StartingLandform.CAPTIONS[kind])
	# An author's own pick on Bare ground survives going back to a biome.
	dialog._on_biome_selected(NewMapDialog.BARE_TILE)
	dialog._on_landform_selected(NewMapDialog.landform_tile(StartingLandform.FLAT))
	var biomes := PaletteLibrary.biomes(dialog.palette_root)
	if not biomes.is_empty():
		dialog._on_biome_selected(StringName(biomes[0]["id"]))
	assert_eq(dialog.current_spec()["landform"], StartingLandform.FLAT)


func test_landform_icons_load() -> void:
	for kind in StartingLandform.KINDS:
		assert_not_null(IconButton.load_icon("landform-" + kind), kind)
	for kind in ["flat", "valley", "hilltop", "terraces", "lakeshore", "gorge"]:
		assert_true(ResourceLoader.exists("res://assets/icons/ui/landform-%s.svg" % kind), kind)


func test_opening_status_names_the_landform() -> void:
	assert_eq(NewMap.opening_status({}), "Building the map...")
	assert_eq(NewMap.opening_status({"landform": StartingLandform.FLAT}), "Building the map...")
	assert_eq(NewMap.opening_status({"landform": StartingLandform.VALLEY}), "Shaping the valley...")
