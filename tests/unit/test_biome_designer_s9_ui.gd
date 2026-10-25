extends GutTest

## The panels step S9 added to the biome designer, built over a model of the fixture library and a
## session with no map (nothing compiles or regenerates): the season controls of the header (the
## scrub, the Seasons and A/B menus), the rule inspector's Seasons section, the ground strip's
## "Applies to", the ground look editor, the lock words and the lock row, the picker's empty state
## with "Request asset", the A/B divider overlay, and the manager's "New biome from this..."
## button with the picker it opens. The live map is test_biome_designer_ab and the render jobs.

const Fixture := preload("res://tests/unit/designer_fixture.gd")
const FOLDER := "user://test_biome_designer_s9_ui/mini"

var _session: BiomeDesignerSession = null
var _ui: DesignerUI = null


func before_each() -> void:
	var made := Fixture.context(FOLDER, true)
	var def: Dictionary = made["read"]["biomes"][0]["def"]
	def["ground_look"] = {
		"zones": {"colors_linear": [[0.1, 0.2, 0.1], [0.2, 0.3, 0.1], [0.3, 0.3, 0.1]]}
	}
	var model := BiomeDesignerModel.from_context(made, "meadow")
	_session = BiomeDesignerSession.new()
	_session.debounce = 100000.0  # no compile: there is no map under this session
	add_child_autofree(_session)
	_session.setup(model, null)
	_ui = DesignerUI.new()
	_ui.setup(_session)
	_ui.size = Vector2(1600.0, 900.0)
	add_child_autofree(_ui)
	await get_tree().process_frame


func _model() -> BiomeDesignerModel:
	return _session.model


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


# ---- the header ----


func test_the_season_scrub_follows_the_seasons_and_the_dropdown_counts_changes() -> void:
	var scrub := _find(_ui.header, "SeasonScrub") as HSlider
	assert_true(scrub.visible, "two seasons can be scrubbed")
	assert_eq(scrub.max_value, 1.0)
	assert_eq(scrub.tick_count, 2)
	var season := _find(_ui.header, "Season") as OptionButton
	assert_eq(season.get_item_text(1), "Autumn")
	DesignerSeasonEdits.set_ground(_model(), "autumn", "surface", "sand_red")
	assert_eq(season.get_item_text(1), "Autumn (1)", "a season says how much it changes")
	DesignerSeasonEdits.remove_season(_model(), "autumn")
	assert_false(scrub.visible, "one season has nothing to scrub")
	assert_eq(season.item_count, 1)


func test_the_seasons_menu_adds_removes_and_clears() -> void:
	var menu := _find(_ui.header, "SeasonsMenu") as MenuButton
	var popup := menu.get_popup()
	popup.about_to_popup.emit()
	assert_true(popup.item_count >= 3)
	assert_eq(popup.get_item_text(0), "Add a season")
	assert_false(popup.is_item_disabled(0))
	_ui.header._on_add_season(DesignerHeader.MENU_ADD_BASE)  # the first unused name: winter
	assert_eq(_model().season_ids(), ["summer", "autumn", "winter"])
	assert_eq(_session.season_id(), "winter")
	popup.about_to_popup.emit()
	var clear_index := popup.get_item_index(DesignerHeader.MENU_CLEAR)
	assert_true(popup.is_item_disabled(clear_index), "nothing to clear yet")
	DesignerSeasonEdits.set_density_scale(_model(), "winter", "large", 0.5)
	popup.about_to_popup.emit()
	assert_false(popup.is_item_disabled(popup.get_item_index(DesignerHeader.MENU_CLEAR)))
	_ui.header._on_seasons_menu(DesignerHeader.MENU_CLEAR)
	assert_eq(DesignerSeasonEdits.summary(_model(), "winter")["total"], 0)
	_ui.header._on_seasons_menu(DesignerHeader.MENU_REMOVE)
	assert_eq(_model().season_ids(), ["summer", "autumn"])
	assert_eq(_session.season_index, 0, "the map falls back to the first season")


func test_the_compare_menu_lists_the_references_and_says_what_it_shows() -> void:
	var menu := _find(_ui.header, "CompareMenu") as MenuButton
	assert_eq(menu.text, "A/B: off")
	var popup := menu.get_popup()
	popup.about_to_popup.emit()
	assert_eq(popup.get_item_text(0), "Off")
	assert_true(popup.is_item_disabled(0), "nothing to turn off")
	var saved := false
	for i in popup.item_count:
		saved = saved or popup.get_item_text(i) == "Saved version of this biome"
	assert_true(saved)
	var refused := _session.compare.start({"kind": "biome", "runtime": "x"})
	assert_false(refused["ok"], "there is no map under this session")


# ---- the rule inspector ----


func test_the_seasons_section_edits_a_rules_changes_in_the_season_on_the_map() -> void:
	_session.select_rule("oak")
	var section := _find(_ui.inspector, "Seasons") as DesignerSeasonSection
	var autumn := section.check_of("autumn")
	assert_not_null(autumn)
	assert_true(autumn.button_pressed)
	autumn.button_pressed = false
	assert_false(DesignerSeasonEdits.is_present(_model(), "oak", "autumn"))
	autumn.button_pressed = true
	assert_true(DesignerSeasonEdits.is_present(_model(), "oak", "autumn"))
	_session.set_season(1)
	var density := section.row_of("density_factor")
	assert_true(density.visible)
	assert_eq(density.value, 1.0)
	density.value_changed.emit(0.5)
	assert_eq(DesignerSeasonEdits.rule_override(_model(), "oak", "autumn"), {"density_factor": 0.5})
	assert_true(density.overridden)
	density.value_changed.emit(1.0)
	assert_eq(DesignerSeasonEdits.rule_override(_model(), "oak", "autumn"), {}, "x1 is no change")
	section.row_of("spacing_m").value_changed.emit(6.0)
	section.row_of("spacing_m").reset_requested.emit()
	assert_eq(DesignerSeasonEdits.rule_override(_model(), "oak", "autumn"), {})
	DesignerSeasonEdits.set_present(_model(), "oak", "autumn", false)
	assert_false(density.visible, "a rule that is not in the season has nothing to change there")


func test_the_lock_words_follow_the_lock() -> void:
	_model().set_query("stones", {"match": [{"category": "rock"}], "count": 1, "order": "id"})
	_session.select_rule("stones")
	var words := _find(_ui.inspector, "LockWords") as Label
	assert_true("Not locked" in words.text)
	var again := _find(_ui.inspector, "LockAgain") as Button
	assert_false(again.visible)
	_model().set_locked("stones", true)
	assert_true("Locked to 1 picked asset" in words.text, words.text)
	assert_true("not saved" in words.text)
	_model().set_query_field("stones", "order", "hash")
	assert_true("query changed" in words.text, words.text)
	assert_true(again.visible)
	again.pressed.emit()
	assert_true("Locked to" in words.text)
	assert_false(again.visible)
	_session.select_rule("oak")
	_model().set_locked("oak", true)
	assert_true("names every asset" in words.text, "a rule of named assets has nothing to freeze")


func test_the_lock_row_counts_and_locks_everything() -> void:
	var words := _find(_ui.slots, "LockSummary") as Label
	assert_eq(words.text, "0 locked")
	(_find(_ui.slots, "LockAll") as Button).pressed.emit()
	assert_eq(words.text, "3 locked")
	assert_true("3 of 3 rules" in words.tooltip_text)
	assert_true("not saved" in words.tooltip_text)
	assert_true((_find(_ui.slots, "LockAll") as Button).disabled)
	assert_false((_find(_ui.slots, "UnlockAll") as Button).disabled)
	assert_true(_ui.slots.chip_of("oak").icon != null, "a locked chip carries its mark")
	(_find(_ui.slots, "UnlockAll") as Button).pressed.emit()
	assert_eq(words.text, "0 locked")
	assert_null(_ui.slots.chip_of("oak").icon)


func test_the_focus_toggle_follows_the_selection() -> void:
	_session.select_rule("oak")
	var focus := _find(_ui.inspector, "Focus") as Button
	assert_false(focus.button_pressed)
	focus.button_pressed = true
	assert_eq(_session.focus_rule, "oak")
	_session.select_rule("stones")
	assert_eq(_session.focus_rule, "stones", "the focus moves with the selection")
	_session.select_rule("")
	assert_eq(_session.focus_rule, "", "and ends with it")


# ---- the ground strip and the look ----


func test_applies_to_sends_the_ground_pickers_to_one_season() -> void:
	var target := _ui.ground.target_picker()
	assert_true(target.get_parent().visible, "two seasons have a target to pick")
	assert_eq(target.get_item_text(0), "Every season")
	assert_eq(target.get_item_text(2), "Autumn only")
	var cliff := _ui.ground.picker_of("cliff")
	_session.set_edit_season("autumn")
	assert_eq(cliff.get_item_text(0), "As biome")
	cliff.select(1)
	cliff.item_selected.emit(1)
	var picked := String(cliff.get_item_metadata(1))
	assert_eq(DesignerSeasonEdits.ground_override(_model(), "autumn", "cliff"), picked)
	assert_eq(DesignerBiomeEdits.ground_value(_model(), "cliff"), null, "the biome's own is untouched")
	assert_true(_find(_ui.ground, "Hint_cliff").visible, "it says the season has its own")
	cliff.select(0)
	cliff.item_selected.emit(0)
	assert_false(DesignerSeasonEdits.has_ground_override(_model(), "autumn", "cliff"))
	_ui.ground._menu_target = "paths"
	_ui.ground._menu_names = ["dirt_road_packed"]
	_ui.ground._on_menu(0)
	assert_eq(DesignerSeasonEdits.ground_override(_model(), "autumn", "paths"), ["dirt_road_packed"])
	assert_true(_find(_ui.ground, "Same_paths").visible)
	_find(_ui.ground, "Same_paths").pressed.emit()
	assert_false(DesignerSeasonEdits.has_ground_override(_model(), "autumn", "paths"))


func test_the_density_popup_scales_a_class_for_the_biome_or_for_a_season() -> void:
	var popup := _ui.ground.density_popup()
	var large := popup.row_of("large")
	assert_eq(large.value, 1.0)
	large.value_changed.emit(0.5)
	assert_eq(_model().def["density_scale"], {"large": 0.5})
	assert_true(large.overridden)
	large.value_changed.emit(1.0)
	assert_false(_model().def.has("density_scale"), "x1 is no scale")
	large.value_changed.emit(0.5)
	_session.set_edit_season("autumn")
	assert_eq(large.value, 0.5, "the season starts from the biome's own")
	assert_false(large.overridden)
	large.value_changed.emit(0.25)
	assert_eq(
		BiomeSeasons.season_overrides(_model().def, "autumn")["density_scale"], {"large": 0.25}
	)
	assert_eq(_model().def["density_scale"], {"large": 0.5}, "the biome's own is untouched")
	assert_eq(popup.scale_of("large"), 0.25)
	large.reset_requested.emit()
	assert_eq(popup.scale_of("large"), 0.5)
	assert_true("Autumn only" in (popup.find_child("Target", true, false) as Label).text)


func test_the_look_button_opens_the_editor_in_the_inspectors_place() -> void:
	var look := _ui.ground.find_child("OpenLook", true, false) as Button
	assert_false(look.disabled)
	assert_false(_ui.look_open())
	look.button_pressed = true
	assert_true(_ui.look_open())
	assert_true(_ui.look_editor.is_visible_in_tree())
	assert_false(_ui.inspector.is_visible_in_tree())
	(_find(_ui.look_editor, "Close") as Button).pressed.emit()
	assert_false(_ui.look_open())
	assert_false(look.button_pressed)
	assert_true(_ui.inspector.is_visible_in_tree())


func test_the_look_editor_edits_fields_and_marks_what_differs_from_the_library() -> void:
	var editor := _ui.look_editor
	var strength := editor.rows_of("zones", "strength")[0] as PropertyRow
	assert_eq(strength.value, GroundLook.BASE.zones.strength)
	assert_false(strength.overridden)
	strength.value_changed.emit(0.4)
	assert_eq(_model().def["ground_look"]["zones"]["strength"], 0.4)
	assert_true(strength.overridden, "it differs from the library's")
	var cover := editor.rows_of("zones", "cover")
	assert_eq(cover.size(), 3)
	(cover[1] as PropertyRow).value_changed.emit(0.6)
	assert_eq(_model().def["ground_look"]["zones"]["cover"][1], 0.6)
	assert_eq(_model().def["ground_look"]["zones"]["cover"][0], GroundLook.BASE.zones.cover[0])
	strength.reset_requested.emit()
	assert_false(_model().def["ground_look"]["zones"].has("strength"), "back to the library's")
	assert_false(strength.overridden)
	var tint := editor.rows_of("rim", "color_linear")[0] as PropertyRow
	tint.color_changed.emit(Color("#336699"))
	var stored: Array = _model().def["ground_look"]["rim"]["color_linear"]
	assert_almost_eq(float(stored[2]), Color("#336699").srgb_to_linear().b, 0.0002)
	(_find(editor, "ResetAll") as Button).pressed.emit()
	assert_eq(_model().def["ground_look"], _model().saved_def()["ground_look"])


func test_the_look_editor_follows_the_target_and_warns_about_the_slots() -> void:
	var editor := _ui.look_editor
	assert_true("at most 4 biomes" in (_find(editor, "SlotsNote") as Label).text)
	assert_true("every season shares" in (_find(editor, "Target") as Label).text)
	_session.set_edit_season("autumn")
	assert_true("Autumn only" in (_find(editor, "Target") as Label).text)
	(editor.rows_of("light", "shade")[0] as PropertyRow).value_changed.emit(0.7)
	assert_eq(DesignerSeasonEdits.look_override(_model(), "autumn"), {"light": {"shade": 0.7}})
	assert_false(_model().def["ground_look"].has("light"), "the biome's look is untouched")
	_session.set_edit_season("")


func test_the_look_editor_offers_a_look_to_a_biome_without_one() -> void:
	_model().def.erase("ground_look")
	_model().changed.emit("test")
	var editor := _ui.look_editor
	assert_true(_find(editor, "NoLook").visible)
	assert_true(_find(editor, "AddLook").visible)
	assert_false(_find(editor, "Groups").visible)
	(_find(editor, "AddLook") as Button).pressed.emit()
	assert_true(_model().def.has("ground_look"))
	assert_true(_find(editor, "Groups").visible)
	assert_false(_find(editor, "NoLook").visible)


func test_the_look_editor_lists_a_value_outside_its_range() -> void:
	_model().def["ground_look"]["zones"]["strength"] = 3.0
	_model().changed.emit("test")
	var issues := _find(_ui.look_editor, "Issues")
	assert_true(issues.get_child_count() > 0)
	var text := ""
	for row in issues.get_children():
		text += (row.get_child(1) as Label).text
	assert_true("zones.strength" in text, text)


# ---- the picker's empty state ----


func test_an_empty_search_suggests_what_to_relax_and_a_request() -> void:
	_ui.picker.search_for("zzz")
	var hint := _find(_ui.picker, "EmptyHint") as DesignerPickerHint
	assert_true(hint.visible)
	assert_true("Try dropping one" in (_find(hint, "HintWords") as Label).text)
	var chips := _find(hint, "Suggestions").get_child_count()
	assert_true(chips >= 1, "the search itself can be dropped")
	assert_true(hint.request_text().begins_with("Wanted: a"))
	assert_true("zzz" in hint.request_text())
	(_find(hint, "Suggestions").get_child(0) as Button).pressed.emit()
	assert_false(hint.visible, "dropping the search brings the tiles back")
	assert_true(_ui.picker.shown_count() > 0)


func test_a_tag_that_empties_the_picker_is_named_with_the_count_without_it() -> void:
	var catalog := DesignerCatalog.groups(_model().catalog())
	var found := DesignerCatalog.relax(catalog, "", [], ["deciduous", "mineral"])
	assert_eq(found.size(), 2)
	assert_eq(found[0]["count"], 3, "without 'mineral' the three tree groups are left")
	assert_eq(found[1]["count"], 2, "without 'deciduous' the two rock groups")
	var request := DesignerCatalog.request_text("", [], ["deciduous", "mineral"])
	assert_eq(request, "Wanted: a asset tagged deciduous, mineral")
	assert_eq(DesignerCatalog.relax(catalog, "", [], []), [])


# ---- the divider ----


func test_the_divider_overlay_waits_for_the_view() -> void:
	var overlay := _ui.compare_overlay
	assert_not_null(overlay)
	assert_false(overlay.visible)
	assert_eq(overlay.line_x(), -1.0)
	assert_false(overlay.is_dragging())


# ---- the manager's button ----


func test_the_manager_card_offers_a_new_biome_when_the_library_can_be_designed() -> void:
	var info := {
		"status": LibraryResolver.OK, "folder": "user://x", "biome_count": 2, "received": false
	}
	assert_true(LibraryDetail.can_design(info))
	for change in [
		{"status": LibraryResolver.ERROR}, {"folder": ""}, {"biome_count": 0}, {"received": true}
	]:
		var other := info.duplicate()
		other.merge(change, true)
		assert_false(LibraryDetail.can_design(other), str(change))
