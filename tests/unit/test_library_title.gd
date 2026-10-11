extends GutTest

## The library's pieces (cards library-title and title-coherent): the facts the map panel shows
## (LibraryFacts), the grid's reveal of a selected card, the panel's actions per map and source,
## its fields read as text, edited in place and saved through update_meta with Escape
## reverting, New map's Advanced (size and seed), the import check panel on fixture GLBs, a .glb
## dropped on a card opening Replace and elsewhere opening Import (written into a
## _test_library_title_ folder, deleted after each test), and the pad's way into the panel.
## LevelManager.levels_dir, ImportSources.path and LibraryPlays.path are put back after each
## test.

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
	assert_eq(LibraryFacts.size_text(Vector2(150.0, 98.4)), "150 × 100 ft")
	assert_eq(LibraryFacts.size_text(Vector2.ZERO), "")
	assert_eq(LibraryFacts.tokens_text(0), "No tokens")
	assert_eq(LibraryFacts.tokens_text(1), "1 token")
	assert_eq(LibraryFacts.played_text(0, 1000), LibraryFacts.NEVER_PLAYED)
	var now := 1_760_000_000
	assert_eq(LibraryFacts.played_text(now - 3 * 86400, now), "Played 3 days ago")


## A library card says the date its order uses: the later of played and edited.
func test_a_card_caption_is_the_date_the_order_uses() -> void:
	var now := 1_760_000_000
	var played := {"played_at": now - 30 * 3600, "modified_at": now - 5 * 86400}
	assert_eq(LibraryFacts.touched_text(played, now), "Played yesterday")
	var edited := {"played_at": now - 9 * 86400, "modified_at": now - 3 * 86400}
	assert_eq(LibraryFacts.touched_text(edited, now), "Edited 3 days ago")
	assert_eq(LevelCard.caption_for(edited, now), "Edited 3 days ago", "a library entry")
	assert_eq(LevelCard.caption_for({"token_count": 1}, now), "1 token", "a picker's card")


func test_a_made_maps_size_is_read_from_its_manifest() -> void:
	var doc := NewMap.create(
		150, NewMap.BARE_BIOME, 3, PaletteLibrary.DEFAULT_ROOT, StartingLandform.FLAT, 100
	)
	var path := _root + "levels/made/map.ttmap"
	DirAccess.make_dir_recursive_absolute(_root + "levels/made/")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var feet := LibraryFacts.footprint_ft(_info("made", "", "map.ttmap"))
	assert_eq(LibraryFacts.size_text(feet), "150 × 100 ft")
	var glb := _source(Vector2(30.48, 15.24))
	var imported := MapImport.write_import(glb)
	var blender := LibraryFacts.footprint_ft(_info(imported.folder, "map.glb", ""))
	assert_eq(LibraryFacts.size_text(blender), "100 × 50 ft")


func test_plays_are_recorded_and_forgotten() -> void:
	assert_eq(LibraryPlays.record("camp", 1234), OK)
	assert_eq(LibraryPlays.all(), {"camp": 1234})
	LibraryPlays.forget("camp")
	assert_eq(LibraryPlays.all(), {})


# --- the grid's reveal -------------------------------------------------------------------------


## A selection scrolls as little as it can to show its card, the card's top first when it
## cannot all fit.
func test_a_selection_scrolls_its_card_into_view() -> void:
	assert_eq(LevelGrid.reveal_scroll(0.0, 300.0, 700.0, 500.0), 200.0, "down to the card")
	assert_eq(LevelGrid.reveal_scroll(400.0, 100.0, 300.0, 500.0), 100.0, "up to the card")
	assert_eq(LevelGrid.reveal_scroll(150.0, 200.0, 600.0, 500.0), 150.0, "already shown")
	assert_eq(LevelGrid.reveal_scroll(0.0, 300.0, 900.0, 500.0), 300.0, "too tall: its top")


# --- the map panel -----------------------------------------------------------------------------


func _panel(info: Dictionary, updated := false) -> MapPanel:
	var panel := MapPanel.new()
	panel.is_updated = func(_folder: String) -> bool: return updated
	panel.footprint = func(_info: Dictionary) -> Vector2: return Vector2(150, 150)
	add_child_autofree(panel)
	panel.show_map(info)
	return panel


func test_the_panels_actions_follow_the_source() -> void:
	var blender := _panel(_info("harbour", "map.glb", ""))
	assert_true(blender.edit_button.visible)
	assert_eq(blender.source_label.text, "From Blender")
	assert_eq(blender.size_label.text, "150 × 150 ft")
	assert_eq(blender.tokens_label.text, "2 tokens")
	var items := [
		MapPanel.MENU_SET_UP,
		MapPanel.MENU_DUPLICATE,
		MapPanel.MENU_REPLACE,
		MapPanel.MENU_DELETE,
	]
	assert_eq(blender.menu_items(), items)
	assert_false(blender.reload_button.visible, "its source is not newer")
	var updated := _panel(_info("harbour", "map.glb", "map.ttmap"), true)
	assert_eq(updated.source_label.text, "Blender, edited here")
	assert_true(updated.updated_chip.visible, "Updated in Blender, in words")
	assert_true(updated.reload_button.visible, "Reload from Blender without the menu")
	watch_signals(updated)
	updated.reload_button.pressed.emit()
	assert_signal_emitted_with_parameters(
		updated, "action_requested", [updated.info, MapPanel.ACTION_RELOAD]
	)
	var made := _panel(_info("made", "", "map.ttmap"), true)
	assert_false(made.reload_button.visible, "nothing to reload")
	var bundled := _panel(_info("ship", "res://maps/x.glb", ""), true)
	assert_false(bundled.edit_button.visible, "a bundled map is not edited here")
	assert_false(bundled.reload_button.visible)
	assert_false(bundled.menu_items().has(MapPanel.MENU_REPLACE))
	assert_eq(bundled.source_label.text, "Bundled")
	assert_true(bundled.host_button.visible)
	assert_eq(bundled.host_button.text, "Host with this map")
	assert_false(bundled.is_editable(), "its words are plain text")
	assert_false(bundled.add_details_button.visible)
	assert_eq(bundled.name_label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var buttons := [
		blender.play_button, blender.host_button, blender.edit_button, blender.more_button
	]
	buttons.append(updated.reload_button)
	for button: Button in buttons:
		assert_eq(button.custom_minimum_size.y, MapPanel.ACTION_HEIGHT, "one height")
	assert_eq(blender.custom_minimum_size.x, MapPanel.WIDTH, "one width for every map")


## A map with no thumbnail shows its name's initial in the panel, as on its card, not its
## folder's (a folder such as "b7_harbour" drew a "B"); the picture is 16:9.
func test_the_panels_placeholder_shows_the_names_initial() -> void:
	var info := _info("b7_harbour", "", "map.ttmap")
	info.name = "Willow Green"
	var panel := _panel(info)
	var initial := panel.picture_well.get_node("Placeholder/Initial") as Label
	assert_eq(initial.text, LevelCard.initial_of("Willow Green"))
	panel.size = Vector2(MapPanel.WIDTH, 600)
	await wait_process_frames(3)
	var picture := panel.picture_well.size
	assert_almost_eq(picture.x / picture.y, MapPanel.PICTURE_ASPECT, 0.02, "16:9")


func test_a_field_saves_on_enter_through_update_meta_and_escape_reverts() -> void:
	var calls: Array = []
	var panel := _panel(_info("harbour", "map.glb", ""))
	panel.update_meta = func(folder: String, changes: Dictionary) -> bool:
		calls.append([folder, changes])
		return changes.get("name", "x") != ""
	watch_signals(panel)
	panel.begin_edit("name")
	assert_true(panel.name_edit.visible, "open for typing")
	assert_false(panel.name_label.visible)
	panel.name_edit.text = "  Harbour at Dusk "
	panel.name_edit.text_submitted.emit(panel.name_edit.text)
	assert_eq(calls, [["harbour", {"name": "Harbour at Dusk"}]])
	assert_eq(panel.info.name, "Harbour at Dusk")
	assert_signal_emitted(panel, "meta_saved")
	assert_false(panel.name_edit.visible, "closed again")
	assert_eq(panel.name_label.text, "Harbour at Dusk", "reads as the saved text")
	panel.begin_edit("description")
	assert_eq(panel.description_edit.placeholder_text, MapPanel.DESCRIPTION_HINT, "while open")
	panel.description_edit.text = "A cove"
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	panel.description_edit.gui_input.emit(escape)
	assert_eq(panel.description_edit.text, "", "Escape puts it back")
	assert_false(panel.description_label.visible, "an empty field takes no line")
	assert_eq(calls.size(), 1, "nothing saved")
	panel.name_edit.text = "   "
	panel.name_edit.text_submitted.emit(panel.name_edit.text)
	assert_eq(panel.name_edit.text, "Harbour at Dusk", "an empty name is refused")


func test_the_panels_menu_author_and_quiet_empty_fields() -> void:
	var info := _info("harbour", "map.glb", "")
	info.author = "Hannah"
	info.description = "A cove under the cliffs"
	var panel := _panel(info)
	assert_eq(panel.author_label.text, "by Hannah")
	assert_false(panel.add_details_button.visible, "nothing left to add")
	watch_signals(panel)
	panel._on_menu_id(MapPanel.MENU_REPLACE)
	assert_signal_emitted_with_parameters(
		panel, "action_requested", [panel.info, MapPanel.ACTION_REPLACE]
	)
	assert_eq(MapPanel.MENU_LABELS[MapPanel.MENU_REPLACE], "Replace map file...")
	assert_false(panel.cue_shown("description"), "reads as text at rest")
	panel.description_label.mouse_entered.emit()
	assert_true(panel.cue_shown("description"), "the field's well under the pointer")
	panel.description_label.mouse_exited.emit()
	assert_false(panel.cue_shown("description"))
	# Empty fields stay quiet: no line and no grey placeholder, one Add details.
	var bare := _panel(_info("x", "map.glb", ""))
	assert_false(bare.author_label.visible, "no author, no by")
	assert_false(bare.description_label.visible, "no description, no line")
	assert_eq(bare.description_edit.placeholder_text, "", "no hint at rest")
	assert_true(bare.add_details_button.visible)
	bare.add_details_button.pressed.emit()
	assert_true(bare.description_edit.visible, "Add details opens the description")


# --- New map -----------------------------------------------------------------------------------


func test_new_map_advanced_sizes_and_seeds() -> void:
	var card := NewMapCard.new()
	add_child_autofree(card)
	assert_false(card.advanced_popover.visible, "Advanced starts closed")
	var height := card.get_combined_minimum_size().y
	card.set_advanced(true)
	assert_true(card.advanced_popover.visible)
	card.seed_edit.text = "42"
	var drawn := card.spec()
	assert_eq(drawn.seed, 42)
	assert_eq(drawn.size_ft, NewMapCard.draw_size(42), "the seed picks the size")
	assert_true(NewMap.SIZES_FT.has(drawn.size_ft))
	card.size_field.tiles.selection_changed.emit(NewMapCard.SIZE_CUSTOM)
	assert_true(card.custom_row.visible)
	card.width_box.value = 300
	card.depth_box.value = 120
	assert_eq(card.spec(), {"seed": 42, "size_ft": 300, "depth_ft": 120})
	assert_true(card.size_note_row.visible, "a big map is warned")
	assert_false(card.generate_button.disabled, "warnings never block")
	card.width_box.value = 400
	assert_eq(card.refusal(), NewMapCard.side_refusal("Width", 400))
	assert_true(card.generate_button.disabled, "past the format's limit")
	assert_eq(card.generate_button.tooltip_text, card.refusal(), "Generate says why it waits")
	assert_eq(card.width_box.edit.theme_type_variation, &"FieldError", "the refused field")
	assert_eq(card.depth_box.edit.theme_type_variation, &"", "not the good one")
	card.width_box.get_child(2).pressed.emit()
	assert_eq(card.width_box.value, 405.0, "plus steps a 5 ft square")
	card.seed_edit.text = "forty"
	card.width_box.value = 150
	assert_eq(card.refusal(), NewMapCard.SEED_ERROR)
	card.set_advanced(false)
	assert_eq(card.get_combined_minimum_size().y, height, "Advanced never changes the card")


func test_new_map_size_notes() -> void:
	assert_eq(NewMapCard.size_note(200, 200), "")
	assert_eq(NewMapCard.size_note(220, 100), NewMapCard.SLOW_LINE % NewMapCard.WARN_ABOVE_FT)
	assert_eq(NewMapCard.size_note(260, 100), NewMapCard.BIG_LINE % NewMap.RECOMMENDED_MAX_FT)
	var too_big := NewMapCard.side_refusal("Width", NewMap.MAX_FT + 5)
	assert_string_contains(too_big, "Width %d ft" % (NewMap.MAX_FT + 5))
	assert_string_contains(too_big, "Set %d or less" % NewMap.MAX_FT)
	assert_ne(NewMapCard.side_refusal("Depth", 0), "")
	assert_eq(NewMapCard.side_refusal("Depth", 100), "")
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
	assert_string_contains(shown, "150 × 100 ft (45.7 × 30.5 m)")
	assert_string_contains(shown, "map.glb")
	assert_string_contains(shown, ImportCheckPanel.UNDER_TENTH_MB, "never 0.0 MB")
	assert_string_contains(shown, "Lowest point 1.5 m above Y = 0")
	assert_eq(panel.warnings_box.get_child_count(), 1, "the floor off Y = 0, one warning")
	assert_eq(panel.confirm_button.text, ImportCheckPanel.ADD, "warnings never block")
	assert_eq(panel.name_edit.text, "Harbour")
	assert_true(panel.confirm_button.disabled == false)


## The check's words: sizes in one unit style, the ground's place the same way above and below,
## the contents plain, and the floor warned past its threshold on either side, never inside.
func test_the_checks_words_and_the_floor_thresholds() -> void:
	assert_eq(ImportCheckPanel.mb_text(0.02), "under 0.1 MB")
	assert_eq(ImportCheckPanel.mb_text(2.44), "2.4 MB")
	assert_eq(ImportCheckPanel.floor_text(0.01), "Lowest point at Y = 0")
	assert_eq(ImportCheckPanel.floor_text(1.5), "Lowest point 1.5 m above Y = 0")
	assert_eq(ImportCheckPanel.floor_text(-1.5), "Lowest point 1.5 m below Y = 0")
	var holds := {"meshes": 3, "water_planes": 1, "extras": {"scatter_instances": 40}}
	holds.extras.scatter_species = 2
	holds.extras.ambient_light = true
	assert_eq(
		ImportCheckPanel.holds_text(holds),
		"The ground in 3 pieces, water, 40 plants and rocks of 2 kinds and its own light and sky"
	)
	assert_eq(ImportCheckPanel.holds_text({"meshes": 1}), "The ground")
	assert_eq(ImportCheckPanel.removed_words(1, 0), "1 prop sits")
	assert_eq(ImportCheckPanel.removed_words(1, 2), "1 prop and 2 plants sit")
	assert_eq(
		LibraryImports.replaced_text(0, 3), "Map replaced; 3 plants sat outside it and were removed"
	)
	var above := GlbCheck.FLOOR_ABOVE_M
	var below := GlbCheck.FLOOR_BELOW_M
	for case: Array in [
		[above - 0.1, 1.0, false],
		[above + 0.1, 1.0, true],
		[-below + 0.5, 1.0, false],
		[-below - 0.5, 1.0, true],
	]:
		var report := {
			"has_bounds": true,
			"footprint_m": Vector2(30, 30),
			"floor_m": case[0],
			"top_m": case[1],
			"mb": 1.0,
		}
		var floors := GlbCheck.warnings(report).filter(
			func(warning: Dictionary) -> bool: return warning.code == GlbCheck.WARN_FLOOR
		)
		assert_eq(floors.size() == 1, case[2], "floor at %.1f m" % case[0])
		if case[2]:
			assert_string_contains(String(floors[0].text), "In Blender, move the map", "a way on")


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
	assert_eq(panel.confirm_button.text, "Replace, keep edits")
	assert_eq(panel.fresh_button.text, "Replace, start fresh")
	assert_true(panel.choice_line.text.begins_with(ImportCheckPanel.keep_line(1)))
	assert_string_contains(panel.choice_line.text, "1 prop sits outside the new map")
	assert_false(panel.choice_line.text.contains(".bak"), "no file names")
	var labels := PackedStringArray()
	for child in panel.facts.get_children():
		labels.append((child as Label).text)
	assert_true(labels.has("Map size now"), "the current size beside the new one")
	assert_true(labels.has("New map size"))


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


func test_accept_selects_a_card_first_and_tab_reaches_the_panel() -> void:
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
	# The panel follows the grid in the tree, so Tab from the last card enters it, at the map's
	# name (its words take the focus on a map of the player's own).
	await wait_process_frames(2)
	var next := second.find_next_valid_focus()
	assert_true(title.map_panel.is_ancestor_of(next), "Tab enters the panel: %s" % next)
