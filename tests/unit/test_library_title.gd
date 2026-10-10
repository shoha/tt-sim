extends GutTest

## The library's pieces (card library-title): the facts the strip shows (LibraryFacts), the
## detail strip's row placement (LevelGrid.line_end) and its actions per map and source, its
## fields saved through update_meta with Escape reverting, New map's Advanced (size and seed),
## the import check panel on fixture GLBs, a .glb dropped on a card opening Replace and
## elsewhere opening Import (written into a _test_library_title_ folder, deleted after each
## test), and the pad's way into the strip. LevelManager.levels_dir, ImportSources.path and
## LibraryPlays.path are put back after each test.

const Fixtures := preload("res://tests/unit/glb_fixtures.gd")
const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")

var _root := ""
var _levels_dir := ""
var _sources_path := ""
var _plays_path := ""


func before_each() -> void:
	_root = Paths.DATA_ROOT + "_test_library_title/"
	_levels_dir = LevelManager.levels_dir
	_sources_path = ImportSources.path
	_plays_path = LibraryPlays.path
	_remove_tree(_root)
	DirAccess.make_dir_recursive_absolute(_root + "levels/")
	DirAccess.make_dir_recursive_absolute(_root + "blender/harbour/")
	LevelManager.levels_dir = _root + "levels/"
	ImportSources.path = _root + "import_sources.cfg"
	LibraryPlays.path = _root + "library_plays.cfg"


func after_each() -> void:
	_remove_tree(_root)
	LevelManager.levels_dir = _levels_dir
	ImportSources.path = _sources_path
	LibraryPlays.path = _plays_path
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


func _source(size: Vector2, file_name: String = "harbour/map.glb", top_y: float = 0.0) -> String:
	var path := _root + "blender/" + file_name
	assert_eq(Fixtures.write_map(path, size, top_y), OK)
	return path


func _info(folder: String, map_path: String, document: String, modified: int = 100) -> Dictionary:
	return {
		"path": "user://x/%s/" % folder,
		"folder": folder,
		"name": folder.capitalize(),
		"description": "",
		"author": "",
		"token_count": 2,
		"modified_at": modified,
		"environment_preset": "",
		"thumbnail": "",
		"map_path": map_path,
		"map_document": document,
	}


# --- facts -------------------------------------------------------------------------------------


func test_the_source_chip_comes_from_the_files() -> void:
	assert_eq(LibraryFacts.source_of(_info("a", "map.glb", "")), LibraryFacts.SOURCE_BLENDER)
	assert_eq(
		LibraryFacts.source_of(_info("a", "map.glb", "map.ttmap")), LibraryFacts.SOURCE_DRESSED
	)
	assert_eq(LibraryFacts.source_of(_info("a", "", "map.ttmap")), LibraryFacts.SOURCE_MADE)
	assert_eq(
		LibraryFacts.source_of(_info("a", "res://maps/x.glb", "")), LibraryFacts.SOURCE_BUNDLED
	)


func test_the_library_order_is_last_played_or_edited_with_bundled_last() -> void:
	var bundled := _info("bundled", "res://maps/x.glb", "", 900)
	var levels := [_info("edited", "map.glb", "", 500), bundled, _info("played", "map.glb", "", 50)]
	var ordered := LibraryFacts.ordered(levels, {"played": 700})
	var names: Array = ordered.map(func(info: Dictionary) -> String: return info.folder)
	assert_eq(names, ["played", "edited", "bundled"])
	assert_eq(ordered[0].played_at, 700)
	assert_eq(ordered[1].played_at, 0)


func test_facts_read_as_words() -> void:
	assert_eq(LibraryFacts.size_text(Vector2(150.0, 98.4)), "150 x 100 ft")
	assert_eq(LibraryFacts.size_text(Vector2.ZERO), "")
	assert_eq(LibraryFacts.tokens_text(0), "No tokens")
	assert_eq(LibraryFacts.tokens_text(1), "1 token")
	assert_eq(LibraryFacts.played_text(0, 1000), LibraryFacts.NEVER_PLAYED)
	var now := 1_760_000_000
	assert_eq(LibraryFacts.played_text(now - 3 * 86400, now), "Played 3 days ago")


func test_a_made_maps_size_is_read_from_its_manifest() -> void:
	var doc := NewMap.create(
		150, NewMap.BARE_BIOME, 3, PaletteLibrary.DEFAULT_ROOT, StartingLandform.FLAT, 100
	)
	var path := _root + "levels/made/map.ttmap"
	DirAccess.make_dir_recursive_absolute(_root + "levels/made/")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var feet := LibraryFacts.footprint_ft(_info("made", "", "map.ttmap"))
	assert_eq(LibraryFacts.size_text(feet), "150 x 100 ft")
	var glb := _source(Vector2(30.48, 15.24))
	var imported := MapImport.write_import(glb)
	var blender := LibraryFacts.footprint_ft(_info(imported.folder, "map.glb", ""))
	assert_eq(LibraryFacts.size_text(blender), "100 x 50 ft")


func test_plays_are_recorded_and_forgotten() -> void:
	assert_eq(LibraryPlays.record("camp", 1234), OK)
	assert_eq(LibraryPlays.all(), {"camp": 1234})
	LibraryPlays.forget("camp")
	assert_eq(LibraryPlays.all(), {})


# --- the strip's row ---------------------------------------------------------------------------


func test_the_strip_goes_after_the_last_item_of_the_selected_row() -> void:
	var cards := [false, false, false, false, false, false, false]
	assert_eq(LevelGrid.line_end(cards, 0, 4), 3, "the lead's row")
	assert_eq(LevelGrid.line_end(cards, 5, 4), 6, "a short last row")
	assert_eq(LevelGrid.line_end(cards, 4, 1), 4)
	# A heading on its own line ends the row before it.
	var with_heading := [false, false, true, false]
	assert_eq(LevelGrid.line_end(with_heading, 0, 4), 1)
	assert_eq(LevelGrid.line_end(with_heading, 3, 4), 3)


# --- the strip ---------------------------------------------------------------------------------


func _strip(info: Dictionary, updated := false) -> MapDetailStrip:
	var strip := MapDetailStrip.new()
	strip.is_updated = func(_folder: String) -> bool: return updated
	strip.footprint = func(_info: Dictionary) -> Vector2: return Vector2(150, 150)
	add_child_autofree(strip)
	strip.show_map(info)
	return strip


func test_the_strips_actions_follow_the_source() -> void:
	var blender := _strip(_info("harbour", "map.glb", ""))
	assert_true(blender.edit_button.visible)
	assert_eq(blender.source_label.text, "From Blender")
	assert_eq(blender.size_label.text, "150 x 150 ft")
	assert_eq(blender.tokens_label.text, "2 tokens")
	assert_eq(
		blender.menu_items(),
		[MapDetailStrip.MENU_SET_UP, MapDetailStrip.MENU_DUPLICATE, MapDetailStrip.MENU_DELETE]
	)
	var updated := _strip(_info("harbour", "map.glb", "map.ttmap"), true)
	assert_true(updated.menu_items().has(MapDetailStrip.MENU_RELOAD), "Reload from Blender")
	var made := _strip(_info("made", "", "map.ttmap"), true)
	assert_false(made.menu_items().has(MapDetailStrip.MENU_RELOAD), "nothing to reload")
	var bundled := _strip(_info("ship", "res://maps/x.glb", ""))
	assert_false(bundled.edit_button.visible, "a bundled map is not edited here")
	assert_eq(bundled.source_label.text, "Bundled")
	assert_true(bundled.host_button.visible)
	assert_eq(bundled.host_button.text, "Host with this map")


func test_a_field_saves_on_enter_through_update_meta_and_escape_reverts() -> void:
	var calls: Array = []
	var strip := _strip(_info("harbour", "map.glb", ""))
	strip.update_meta = func(folder: String, changes: Dictionary) -> bool:
		calls.append([folder, changes])
		return changes.get("name", "x") != ""
	watch_signals(strip)
	strip.name_edit.text = "  Harbour at Dusk "
	strip.name_edit.text_submitted.emit(strip.name_edit.text)
	assert_eq(calls, [["harbour", {"name": "Harbour at Dusk"}]])
	assert_eq(strip.info.name, "Harbour at Dusk")
	assert_signal_emitted(strip, "meta_saved")
	strip.description_edit.text = "A cove"
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	strip.description_edit.gui_input.emit(escape)
	assert_eq(strip.description_edit.text, "", "Escape puts it back")
	assert_eq(calls.size(), 1, "nothing saved")
	strip.name_edit.text = "   "
	strip.name_edit.text_submitted.emit(strip.name_edit.text)
	assert_eq(strip.name_edit.text, "Harbour at Dusk", "an empty name is refused")


# --- New map -----------------------------------------------------------------------------------


func test_new_map_advanced_sizes_and_seeds() -> void:
	var card := NewMapCard.new()
	add_child_autofree(card)
	assert_false(card.advanced_body.visible, "Advanced starts closed")
	card.set_advanced(true)
	assert_true(card.advanced_body.visible)
	card.seed_edit.text = "42"
	var drawn := card.spec()
	assert_eq(drawn.seed, 42)
	assert_eq(drawn.size_ft, NewMapCard.draw_size(42), "the seed draws the size")
	assert_true(NewMap.SIZES_FT.has(drawn.size_ft))
	card.size_field.tiles.selection_changed.emit(NewMapCard.SIZE_CUSTOM)
	assert_true(card.custom_row.visible)
	card.width_box.value = 300
	card.depth_box.value = 120
	assert_eq(card.spec(), {"seed": 42, "size_ft": 300, "depth_ft": 120})
	assert_true(card.size_line.visible, "a big map is warned")
	assert_false(card.generate_button.disabled, "warnings never block")
	card.width_box.value = 400
	assert_eq(card.refusal(), NewMap.size_error(400, 120))
	assert_true(card.generate_button.disabled, "past the format's limit")
	card.seed_edit.text = "forty"
	card.width_box.value = 150
	assert_eq(card.refusal(), NewMapCard.SEED_ERROR)


func test_new_map_size_notes() -> void:
	assert_eq(NewMapCard.size_note(200, 200), "")
	assert_eq(NewMapCard.size_note(220, 100), NewMapCard.SLOW_LINE % NewMapCard.WARN_ABOVE_FT)
	assert_eq(NewMapCard.size_note(260, 100), NewMapCard.BIG_LINE % NewMap.RECOMMENDED_MAX_FT)
	assert_eq(NewMapCard.size_note(NewMap.MAX_FT + 5, 100), NewMap.size_error(NewMap.MAX_FT + 5))
	assert_eq(NewMapCard.parse_seed(""), -1)
	assert_eq(NewMapCard.parse_seed(" 7 "), 7)
	assert_eq(NewMapCard.parse_seed("-3"), -2)


func test_generate_hands_the_preset_to_the_new_map_dialog() -> void:
	var dialog: NewMapDialog = (
		preload("res://scenes/states/authoring/new_map_dialog.tscn").instantiate()
	)
	dialog.preset = {"size_ft": 300, "depth_ft": 120, "seed": 9}
	add_child_autofree(dialog)
	assert_false(dialog.size_field.visible, "the size was chosen on the card")
	var spec := dialog.current_spec()
	assert_eq([spec.size_ft, spec.depth_ft, spec.seed], [300, 120, 9])
	assert_eq(dialog.header.caption_label.text, NewMapDialog.preset_caption(dialog.preset))
	UIManager.unregister_overlay(dialog.get_node("ColorRect") as Control)


# --- import and replace ------------------------------------------------------------------------


func _imports() -> LibraryImports:
	var imports := LibraryImports.new()
	imports.render_thumbnails = false
	add_child_autofree(imports)
	imports.host = imports
	return imports


func test_the_check_panel_shows_the_report_and_its_warnings() -> void:
	var path := _source(Vector2(45.72, 30.48), "harbour/map.glb", 2.0)
	var panel := _imports().check_import(path)
	assert_not_null(panel)
	var labels := PackedStringArray()
	for child in panel.facts.get_children():
		labels.append((child as Label).text)
	var shown := " | ".join(labels)
	assert_string_contains(shown, "(150 x 100 ft)")
	assert_string_contains(shown, "map.glb")
	assert_eq(panel.warnings_box.get_child_count(), 1, "the floor off Y = 0, one warning")
	assert_eq(panel.confirm_button.text, ImportCheckPanel.ADD, "warnings never block")
	assert_eq(panel.name_edit.text, "Harbour")
	assert_true(panel.confirm_button.disabled == false)


func test_a_gltf_is_refused_in_one_sentence() -> void:
	var panel := _imports().check_import(_root + "blender/harbour/map.gltf")
	assert_null(panel.confirm_button, "nothing to confirm")
	assert_eq(panel.cancel_button.text, "Close")
	assert_null(panel.facts)
	assert_eq(panel.report.error, GlbCheck.REFUSE_GLTF)


func test_a_glb_dropped_on_a_card_replaces_that_map() -> void:
	var first := MapImport.write_import(_source(Vector2(30.0, 30.0)))
	assert_true(first.ok)
	var imports := _imports()
	watch_signals(imports)
	var newer := _source(Vector2(40.0, 40.0), "harbour/newer.glb")
	var panel := imports.drop(PackedStringArray([newer]), first.folder)
	assert_eq(panel._folder, first.folder, "Replace for that map")
	assert_eq(panel.confirm_button.text, ImportCheckPanel.REPLACE, "no dressing to keep")
	assert_null(panel.name_edit, "a replace keeps the map's name")
	panel.confirm_button.pressed.emit()
	await wait_for_signal(imports.replaced, 2.0)
	assert_signal_emitted(imports, "replaced")
	assert_eq(ImportSources.source_of(first.folder), newer)


func test_a_dressed_maps_replace_offers_keep_dressing_with_its_count() -> void:
	var first := MapImport.write_import(_source(Vector2(40.0, 40.0)))
	var bounds := AABB(Vector3(-20, 0, -20), Vector3(40, 1, 40))
	var doc := NewMap.create_dressing(bounds, 3)
	var rock := "birch_woodland_summer_s1/Rock_Small"
	doc.props = {rock: PackedFloat32Array([18.0, 0, 18.0, 0, 0, 0, 1, 1, 1, 1])}
	assert_eq(MapDocumentIO.write(doc, LevelManager.map_document_path(first.folder)), OK)
	var level := LevelManager.load_level_folder(first.folder, false)
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	assert_ne(LevelManager.save_level_folder(level, first.folder), "")
	var smaller := _source(Vector2(20.0, 20.0), "harbour/smaller.glb")
	var panel := _imports().check_replace(first.folder, smaller)
	assert_eq(panel.confirm_button.text, ImportCheckPanel.KEEP)
	assert_eq(panel.fresh_button.text, ImportCheckPanel.FRESH)
	assert_true(panel.choice_line.text.begins_with(ImportCheckPanel.keep_line(1)))


func test_a_glb_dropped_between_cards_is_a_new_map() -> void:
	var imports := _imports()
	watch_signals(imports)
	var panel := imports.drop(PackedStringArray([_source(Vector2(30.0, 30.0))]), "")
	assert_eq(panel.confirm_button.text, ImportCheckPanel.ADD)
	panel.confirm_button.pressed.emit()
	await wait_for_signal(imports.imported, 2.0)
	assert_signal_emitted(imports, "imported")
	assert_eq(LevelManager.get_saved_levels().size(), 1)


func test_the_title_routes_a_drop_by_the_card_under_it() -> void:
	var first := MapImport.write_import(_source(Vector2(30.0, 30.0)))
	var title: TitleScreen = TITLE_SCENE.instantiate()
	title.session_provider = func() -> Array[Dictionary]: return []
	add_child_autofree(title)
	await wait_process_frames(3)
	var card := title.grid._cards[0]
	assert_eq(title.card_at(card.get_global_rect().get_center()).folder, first.folder)
	assert_eq(title.card_at(Vector2(-50, -50)), {}, "between cards: a new map")
	for node in get_tree().root.get_children():
		if node is ImportCheckPanel:
			node.queue_free()


# --- the pad's way in --------------------------------------------------------------------------


func test_accept_selects_a_card_first_and_tab_reaches_the_strip() -> void:
	var title: TitleScreen = TITLE_SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]:
		return [_info("a", "map.glb", "", 300), _info("b", "map.glb", "", 200)]
	title.plays_provider = func() -> Dictionary: return {}
	title.session_provider = func() -> Array[Dictionary]: return []
	var host := SubViewport.new()
	host.size = Vector2i(1280, 720)
	add_child_autofree(host)
	host.add_child(title)
	await wait_process_frames(3)
	watch_signals(title.grid)
	var second := title.grid._cards[1]
	second.grab_focus()
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	second.gui_input.emit(accept)
	assert_signal_not_emitted(title.grid, "level_activated", "the first Accept only selects")
	second._on_pressed()
	assert_eq(title.selected_level().folder, "b")
	second.gui_input.emit(accept)
	assert_signal_emitted(title.grid, "level_activated", "Accept on the selected card plays")
	# The strip follows the selected row in the tree, so Tab from the row's last item enters it.
	await wait_process_frames(2)
	var next := second.find_next_valid_focus()
	assert_true(title.strip.is_ancestor_of(next), "Tab enters the strip: %s" % next)
