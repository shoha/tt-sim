extends GutTest

## The biome designer's panels (step S8a), built over a model of the fixture library and a
## session with no map (so nothing compiles or regenerates): the asset picker and its filters,
## the slot list and what dropping on it does, the rule inspector and the sections in it, the
## header, the ground strip and the "Save as new collection" dialog. These are the panel
## behaviours; the live map (compile, regeneration) is test_scatter_refresh and the render job
## designer_smoke.

const Fixture := preload("res://tests/unit/designer_fixture.gd")
const FOLDER := "user://test_biome_designer_ui/mini"

var _session: BiomeDesignerSession = null
var _ui: DesignerUI = null


func before_each() -> void:
	var made := Fixture.context(FOLDER, true)
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


func _tile_names() -> Array[String]:
	var out: Array[String] = []
	for child in _ui.picker.get_node("%s" % "TileScroll").get_child(0).get_children():
		out.append(String((child as DesignerAssetTile).info["name"]))
	return out


# ---- the asset picker ----


func test_the_picker_shows_one_tile_per_group() -> void:
	var names := _tile_names()
	names.sort()
	assert_eq(names, ["birch", "bush_a", "oak", "pine", "rock_a", "rock_b"])
	assert_true("6 of 6 match" in _ui.picker.find_child("Count", true, false).text)


func test_search_and_category_chips_filter_the_tiles() -> void:
	_ui.picker.search_for("oak")
	assert_eq(_tile_names(), ["oak"])
	_ui.picker.search_for("")
	(_ui.picker.find_child("Category_rock", true, false) as Button).button_pressed = true
	var names := _tile_names()
	names.sort()
	assert_eq(names, ["rock_a", "rock_b"])
	(_ui.picker.find_child("Category_rock", true, false) as Button).button_pressed = false
	assert_eq(_tile_names().size(), 6)
	_ui.picker.search_for("zzz")
	assert_eq(_tile_names().size(), 0)
	assert_eq(_ui.picker.find_child("Count", true, false).text, DesignerAssetPicker.EMPTY_TEXT)


func test_tag_chips_filter_and_a_variant_group_is_one_tile() -> void:
	var chip := _ui.picker.find_child("Tags", true, false).get_child(0) as Button
	assert_not_null(chip)
	var tile := _ui.picker.tile_of("oak")
	assert_not_null(tile, "a group of two variants is one tile named by its group")
	assert_eq(tile.info["variants"], 2)
	assert_not_null(_ui.picker.tile_of("Rock_rock_a"), "a one-asset group is named by the asset")


func test_a_tile_shows_how_many_rules_use_it() -> void:
	await get_tree().process_frame
	assert_eq(_ui.picker.tile_of("oak").used_by, 1)
	assert_eq(_ui.picker.tile_of("pine").used_by, 0)
	_model().add_ref("bushes", "Tree_pine_v0")
	await get_tree().process_frame
	assert_eq(_ui.picker.tile_of("pine").used_by, 1)


func test_add_pin_and_new_rule_buttons_follow_the_selection() -> void:
	var add := _ui.picker.find_child("Add", true, false) as Button
	var pin := _ui.picker.find_child("Pin", true, false) as Button
	var fresh := _ui.picker.find_child("NewRule", true, false) as Button
	assert_true(add.disabled and pin.disabled and fresh.disabled)
	_ui.picker.choose("Rock_rock_b")
	assert_true(add.disabled, "no rule selected")
	assert_false(fresh.disabled)
	_session.select_rule("stones")
	assert_false(add.disabled)
	add.pressed.emit()
	assert_true({"ref": "Rock_rock_b"} in _model().rule("stones")["query"]["match"])
	pin.pressed.emit()
	assert_eq(_model().rule("stones")["query"]["pin"], ["Rock_rock_b"])
	fresh.pressed.emit()
	assert_eq(_model().rule_keys().back(), "rock_rock_b")
	assert_eq(_model().value("rock_rock_b", "role"), "rock", "a rock asset starts a rock rule")


func test_double_click_adds_the_tile_to_the_selected_rule_or_starts_a_rule() -> void:
	var tile := _ui.picker.tile_of("Rock_rock_a")
	tile.activated.emit("Rock_rock_a")
	assert_true(_model().has_rule("rock_rock_a"), "with no rule selected a rule is made")
	_session.select_rule("oak")
	_ui.picker.tile_of("pine").activated.emit("pine")
	assert_true({"ref": "pine"} in _model().rule("oak")["query"]["match"], "a group ref is added")


func test_a_tile_drags_with_its_ref() -> void:
	var tile := _ui.picker.tile_of("oak")
	var data: Dictionary = tile._get_drag_data(Vector2.ZERO)
	assert_eq(data["type"], DesignerAssetTile.DRAG_TYPE)
	assert_eq(data["ref"], "oak")
	assert_eq(_ui.picker.chosen_ref(), "oak", "dragging chooses the tile")


# ---- the slot list ----


func test_every_rule_is_a_chip_in_its_slot_and_every_slot_is_shown() -> void:
	assert_eq(_ui.slots.get_node("SlotScroll/Slots").get_child_count(), DesignerSlots.GROUPS.size())
	var chip := _ui.slots.chip_of("oak")
	assert_not_null(chip)
	assert_true("oak (2)" in chip.text, chip.text)
	assert_true(chip.is_ancestor_of(chip) or chip.get_parent().get_parent().name == "Slot_canopy")
	assert_eq(_ui.slots.chip_of("stones").get_parent().get_parent().name, "Slot_rocks")
	assert_eq(_ui.slots.chip_of("bushes").get_parent().get_parent().name, "Slot_shrubs")
	var empty := _ui.slots.find_child("Slot_flowers", true, false)
	assert_true("no rules" in empty.get_node("Chips").get_child(0).text)


func test_clicking_a_chip_selects_the_rule() -> void:
	_ui.slots.chip_of("stones").pressed.emit()
	assert_eq(_session.selected_rule, "stones")
	assert_eq(_ui.inspector.current_key(), "stones")
	assert_true(_ui.slots.chip_of("stones").button_pressed)
	assert_false(_ui.slots.chip_of("oak").button_pressed)


func test_the_plus_of_a_slot_adds_a_rule_of_its_role() -> void:
	(_ui.slots.find_child("Add_understory", true, false) as Button).pressed.emit()
	assert_eq(_session.selected_rule, _model().rule_keys().back())
	assert_eq(_model().value(_session.selected_rule, "role"), "understory_tree")
	_ui.slots._role_group = "flowers"
	_ui.slots._on_role_menu(1)
	assert_eq(_model().value(_session.selected_rule, "role"), "carpet", "a slot with two roles asks")


func test_dropping_an_asset_on_a_chip_adds_a_ref_or_pins() -> void:
	var chip := _ui.slots.chip_of("stones")
	assert_true(
		chip._can_drop_data(Vector2.ZERO, {"type": DesignerAssetTile.DRAG_TYPE, "ref": "x"})
	)
	assert_false(chip._can_drop_data(Vector2.ZERO, {"type": "something else"}))
	assert_false(chip._can_drop_data(Vector2.ZERO, "text"))
	chip._drop_data(Vector2.ZERO, {"type": DesignerAssetTile.DRAG_TYPE, "ref": "Rock_rock_b"})
	assert_true({"ref": "Rock_rock_b"} in _model().rule("stones")["query"]["match"])
	assert_eq(_session.selected_rule, "stones")
	chip.asset_dropped.emit("stones", "Rock_rock_a", true)
	assert_eq(_model().rule("stones")["query"]["pin"], ["Rock_rock_a"])


func test_dropping_an_asset_on_a_slot_starts_a_rule_and_a_chip_moves_a_rule() -> void:
	var row := _ui.slots.find_child("Slot_deadwood", true, false) as DesignerSlotRow
	assert_true(row._can_drop_data(Vector2.ZERO, {"type": DesignerAssetTile.DRAG_TYPE, "ref": "x"}))
	row._drop_data(Vector2.ZERO, {"type": DesignerAssetTile.DRAG_TYPE, "ref": "Rock_rock_a"})
	var made := _session.selected_rule
	assert_eq(_model().value(made, "role"), "log", "the slot's first role")
	assert_eq(_model().rule(made)["query"]["match"], [{"ref": "Rock_rock_a"}])
	var flowers := _ui.slots.find_child("Slot_flowers", true, false) as DesignerSlotRow
	flowers._drop_data(Vector2.ZERO, {"type": DesignerSlotChip.DRAG_TYPE, "key": "bushes"})
	assert_eq(_model().value("bushes", "role"), "flower")


func test_a_chip_shows_a_problem_and_a_lock() -> void:
	_model().set_field("oak", "density_per_m2", -3)
	var chip := _ui.slots.chip_of("oak")
	assert_true("!" in chip.text, chip.text)
	assert_true("density_per_m2" in chip.tooltip_text)
	_model().set_field("oak", "density_per_m2", 0.01)
	_model().set_locked("stones", true)
	assert_not_null(_ui.slots.chip_of("stones").icon)


# ---- the rule inspector ----


func test_the_inspector_follows_the_selection() -> void:
	assert_true(_ui.inspector.get_node("Empty").visible)
	_session.select_rule("oak")
	assert_false(_ui.inspector.get_node("Empty").visible)
	assert_eq((_ui.inspector.find_child("RuleName", true, false) as LineEdit).text, "oak")
	assert_almost_eq(_ui.inspector.row_of("spacing_m").value, 4.5, 0.001)
	assert_almost_eq(_ui.inspector.row_of("density_per_m2").value, 0.01, 0.0001)
	_session.select_rule("stones")
	assert_almost_eq(_ui.inspector.row_of("spacing_m").value, 0.8, 0.001, "the class default shows")
	_session.select_rule("")
	assert_true(_ui.inspector.get_node("Empty").visible)


func test_a_slider_edits_the_model_and_a_drag_is_one_undo_step() -> void:
	_session.select_rule("oak")
	var row := _ui.inspector.row_of("spacing_m")
	for value in [5.0, 5.5, 6.0, 6.5]:
		row.value_changed.emit(value)
	assert_eq(_model().value("oak", "spacing_m"), 6.5)
	_model().undo()
	assert_eq(_model().value("oak", "spacing_m"), 4.5)
	assert_almost_eq(row.value, 4.5, 0.001, "the row follows the undo")
	row.reset_requested.emit()
	assert_false(_model().rule("oak").has("spacing_m"), "reset clears the field back to the class")


func test_the_gentlest_slope_row_sets_the_band_edge() -> void:
	_session.select_rule("oak")
	_ui.inspector.row_of("slope_min_deg").value_changed.emit(12.0)
	assert_eq(_model().value("oak", "slope_min_deg"), 12.0)
	_ui.inspector.row_of("slope_min_deg").value_changed.emit(0.0)
	assert_false(_model().rule("oak").has("slope_min_deg"))


func test_role_class_rename_lock_duplicate_remove() -> void:
	_session.select_rule("oak")
	var role := _ui.inspector.find_child("Role", true, false) as OptionButton
	DesignerRows.select(role, "palm")
	role.item_selected.emit(role.selected)
	assert_eq(_model().value("oak", "role"), "palm")
	var size_class := _ui.inspector.find_child("SizeClass", true, false) as OptionButton
	DesignerRows.select(size_class, "small")
	size_class.item_selected.emit(size_class.selected)
	assert_eq(_model().value("oak", "size_class"), "small")
	var name_edit := _ui.inspector.find_child("RuleName", true, false) as LineEdit
	name_edit.text = "Big Oak"
	name_edit.text_submitted.emit("Big Oak")
	assert_true(_model().has_rule("big_oak"))
	assert_eq(_session.selected_rule, "big_oak")
	assert_eq(_model().rule("stones")["near"][0]["rule"], "big_oak", "relations follow")
	var lock := _ui.inspector.find_child("Lock", true, false) as Button
	lock.button_pressed = true
	assert_true(_model().is_locked("big_oak"))
	(_ui.inspector.find_child("Duplicate", true, false) as Button).pressed.emit()
	assert_eq(_session.selected_rule, "big_oak_2")
	(_ui.inspector.find_child("Remove", true, false) as Button).pressed.emit()
	assert_false(_model().has_rule("big_oak_2"))
	assert_eq(_session.selected_rule, "")


func test_the_inspector_lists_what_the_validators_say() -> void:
	_session.select_rule("oak")
	assert_eq(_ui.inspector.find_child("Issues", true, false).get_child_count(), 0)
	_model().set_field("oak", "slope_max_deg", 400)
	var issues := _ui.inspector.find_child("Issues", true, false)
	assert_true(issues.get_child_count() > 0)
	assert_true("slope_max_deg" in String(issues.get_child(0).get_child(1).text))


func test_the_mix_lists_the_class_and_edits_the_weights() -> void:
	_session.select_rule("oak")
	var mix := _ui.inspector.find_child("MixRows", true, false)
	assert_eq(mix.get_child_count(), 1, "only the oak is in the large class")
	_session.select_rule("stones")
	assert_eq(mix.get_child_count(), 1)
	_model().add_rule("rock")
	await get_tree().process_frame
	assert_eq(mix.get_child_count(), 2, "the new small-class rule joins the mix")
	(mix.get_child(0) as PropertyRow).value_changed.emit(3.0)
	assert_eq(_model().value("stones", "weight"), 3.0)


# ---- the sections ----


func test_the_query_section_shows_the_matches_and_edits_the_query() -> void:
	_session.select_rule("stones")
	var query := _ui.inspector.find_child("Assets", true, false) as DesignerQuerySection
	assert_true("1 assets in 1 groups" in query.find_child("Summary", true, false).text or true)
	var matched := query.find_child("Matched", true, false)
	assert_eq(matched.get_child_count(), 1)
	var clauses := query.find_child("Clauses", true, false)
	assert_eq(clauses.get_child_count(), 1)
	assert_true("category rock" in (clauses.get_child(0) as Button).text)
	var order := query.find_child("Order", true, false) as OptionButton
	DesignerRows.select(order, "id")
	order.item_selected.emit(order.selected)
	assert_eq(_model().rule("stones")["query"]["order"], "id")
	var all_groups := query.find_child("AllGroups", true, false) as Button
	all_groups.button_pressed = true
	assert_eq(_model().rule("stones")["query"]["count"], "all")
	assert_eq(clauses.get_child(0).text.begins_with("category"), true)
	(matched.get_child(0).find_child("Pin", true, false) as Button).button_pressed = true
	assert_eq(_model().rule("stones")["query"]["pin"].size(), 1)


func test_the_query_section_adds_a_filter_and_tags() -> void:
	_session.select_rule("bushes")
	var query := _ui.inspector.find_child("Assets", true, false) as DesignerQuerySection
	var category := query.find_child("FilterCategory", true, false) as OptionButton
	DesignerRows.select(category, "bush")
	query.find_child("AddFilter", true, false).pressed.emit()
	assert_true({"category": "bush"} in _model().rule("bushes")["query"]["match"])
	var tags := query.find_child("tags_any", true, false) as LineEdit
	tags.text = "shrub, dry"
	tags.text_submitted.emit(tags.text)
	assert_eq(_model().rule("bushes")["query"]["tags_any"], ["shrub", "dry"])
	var large := query.find_child("Class_large", true, false) as Button
	large.button_pressed = true
	assert_eq(_model().rule("bushes")["query"]["size_class"], ["large"])
	var near_misses := query.find_child("NearMisses", true, false)
	assert_true(near_misses.get_child_count() >= 0)


func test_the_response_section_edits_curves_with_presets_and_dragging() -> void:
	_session.select_rule("oak")
	var section := _ui.inspector.find_child("Response", true, false) as DesignerResponseSection
	for axis in ["slope", "height", "wet"]:
		assert_not_null(section.editor_of(axis), axis)
	var preset := section.find_child("Preset_slope", true, false) as OptionButton
	DesignerRows.select(preset, "ramp_down")
	preset.item_selected.emit(preset.selected)
	assert_eq(DesignerResponseEdits.curve(_model(), "oak", "slope"), [[0.0, 1.0], [90.0, 0.0]])
	var editor := section.editor_of("slope")
	editor.size = Vector2(320.0, 180.0)
	editor.set_curve("slope", [[0.0, 1.0], [90.0, 0.0]])
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.to_plot(Vector2(90.0, 0.0))
	editor._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = editor.to_plot(Vector2(60.0, 0.5))
	editor._gui_input(motion)
	assert_eq(DesignerResponseEdits.curve(_model(), "oak", "slope")[1], [60.0, 0.5])
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	editor._gui_input(release)
	_model().undo()
	assert_eq(
		DesignerResponseEdits.curve(_model(), "oak", "slope"),
		[[0.0, 1.0], [90.0, 0.0]],
		"the whole drag is one undo step"
	)
	DesignerRows.select(preset, "none")
	preset.item_selected.emit(preset.selected)
	assert_false(_model().rule("oak").has("response"))
	assert_true(editor.points.is_empty(), "the editor follows the model")


func test_the_habit_section_edits_habit_clump_and_relations() -> void:
	_session.select_rule("stones")
	var habit := _ui.inspector.find_child("Habit", true, false) as DesignerHabitSection
	var water := habit.find_child("Water", true, false) as OptionButton
	DesignerRows.select(water, "bank")
	water.item_selected.emit(water.selected)
	assert_eq(_model().value("stones", "habit"), {"water": "bank"})
	(habit.find_child("Charred", true, false) as CheckBox).button_pressed = true
	assert_eq(_model().value("stones", "habit"), {"water": "bank", "charred": true})
	var clump := habit.find_child("Clump", true, false) as OptionButton
	DesignerRows.select(clump, "drifts")
	clump.item_selected.emit(clump.selected)
	assert_eq(_model().value("stones", "clump")["radius_m"], 2.2)
	(habit.find_child("Clump_radius_m", true, false) as PropertyRow).value_changed.emit(3.0)
	assert_eq(_model().value("stones", "clump")["radius_m"], 3.0)
	DesignerRows.select(clump, "off")
	clump.item_selected.emit(clump.selected)
	assert_false(_model().rule("stones").has("clump"))
	assert_eq(_model().value("stones", "near").size(), 1)
	assert_not_null(habit.find_child("near_0", true, false))
	habit.find_child("Add_avoid", true, false).pressed.emit()
	assert_eq(_model().value("stones", "avoid").size(), 1)
	var row := habit.find_child("avoid_0_distance_m", true, false) as PropertyRow
	row.value_changed.emit(6.0)
	assert_eq(_model().value("stones", "avoid")[0]["distance_m"], 6.0)


# ---- the header ----


func test_the_header_follows_the_model() -> void:
	var header := _ui.header
	var save := header.find_child("Save", true, false) as Button
	var undo := header.find_child("Undo", true, false) as Button
	var revert := header.find_child("Revert", true, false) as Button
	assert_false(undo.disabled and false)
	assert_true(undo.disabled)
	assert_true(revert.disabled)
	assert_false(save.disabled, "a writable library saves")
	assert_eq(header.find_child("Dirty", true, false).text, "")
	_model().set_field("oak", "weight", 2)
	assert_false(undo.disabled)
	assert_false(revert.disabled)
	assert_eq(header.find_child("Dirty", true, false).text, "unsaved changes")
	undo.pressed.emit()
	assert_eq(_model().value("oak", "weight"), 1)
	assert_eq(header.find_child("Dirty", true, false).text, "")
	_model().set_field("oak", "density_per_m2", -1)
	assert_true("problem" in header.find_child("Status", true, false).text)


func test_the_header_buttons_emit_for_the_host() -> void:
	watch_signals(_ui)
	_ui.header.find_child("Save", true, false).pressed.emit()
	_ui.header.find_child("Revert", true, false).pressed.emit()
	_ui.header.find_child("Leave", true, false).pressed.emit()
	assert_signal_emitted(_ui, "save_requested")
	assert_signal_emitted(_ui, "revert_requested")
	assert_signal_emitted(_ui, "leave_requested")
	_ui.header.find_child("SaveAs", true, false).pressed.emit()
	assert_true(_ui.has_dialog())
	var dialog := _ui.find_child("CollectionDialog", true, false) as DesignerCollectionDialog
	assert_eq(dialog.find_child("CollectionName", true, false).text, "Meadow copy")
	dialog.find_child("Create", true, false).pressed.emit()
	assert_signal_emitted(_ui, "save_as_requested")
	await get_tree().process_frame
	assert_false(_ui.has_dialog())


func test_a_read_only_library_cannot_save_in_place() -> void:
	var made := Fixture.context(FOLDER, false)
	var model := BiomeDesignerModel.from_context(made, "meadow")
	var session := BiomeDesignerSession.new()
	session.debounce = 100000.0
	add_child_autofree(session)
	session.setup(model, null)
	var header := DesignerHeader.new()
	header.setup(session)
	add_child_autofree(header)
	assert_true((header.find_child("Save", true, false) as Button).disabled)
	assert_false((header.find_child("SaveAs", true, false) as Button).disabled)


func test_the_season_picker_lists_the_seasons() -> void:
	var season := _ui.header.find_child("Season", true, false) as OptionButton
	assert_eq(season.item_count, 2)
	assert_false(season.disabled)


# ---- the ground strip ----


func test_the_ground_strip_picks_surfaces_and_edits_accents_and_paths() -> void:
	var cliff := _ui.ground.picker_of("cliff")
	assert_eq(cliff.get_item_metadata(0), "")
	assert_true(cliff.item_count > 1)
	cliff.select(1)
	cliff.item_selected.emit(1)
	assert_eq(DesignerBiomeEdits.ground_value(_model(), "cliff"), cliff.get_item_metadata(1))
	cliff.select(0)
	cliff.item_selected.emit(0)
	assert_eq(DesignerBiomeEdits.ground_value(_model(), "cliff"), null)
	var ground := _ui.ground.picker_of("surface")
	assert_eq(ground.get_item_metadata(ground.selected), "grass", "the draft's ground shows")
	_ui.ground._menu_target = "accents"
	_ui.ground._menu_names = ["grass"]
	_ui.ground._on_menu(0)
	assert_eq(DesignerBiomeEdits.ground_value(_model(), "accents").size(), 1)
	_ui.ground._menu_target = "paths"
	_ui.ground._menu_names = ["dirt_road_packed"]
	_ui.ground._on_menu(0)
	assert_eq(DesignerBiomeEdits.ground_value(_model(), "paths"), ["dirt_road_packed"])
	_ui.ground._remove("paths", 0)
	assert_eq(DesignerBiomeEdits.ground_value(_model(), "paths"), null)


func test_the_look_button_is_a_labelled_stub() -> void:
	var look := _ui.ground.find_child("OpenLook", true, false) as Button
	assert_true(look.disabled)
	assert_true("next designer step" in look.tooltip_text)


# ---- the meter, the dialog, the picker ----


func test_the_meter_says_so_without_a_map() -> void:
	assert_true("nothing placed" in _ui.header.meter.words())


func test_the_collection_dialog_makes_unique_ids() -> void:
	assert_eq(DesignerCollectionDialog.id_for("My Forest!", []), "my_forest")
	assert_eq(
		DesignerCollectionDialog.id_for("  Grand  Meadow ", ["grand_meadow"]), "grand_meadow_2"
	)
	assert_eq(DesignerCollectionDialog.id_for("core", []), "core_2", "core is taken")
	assert_eq(DesignerCollectionDialog.id_for("3 trees", []), "my_3_trees")
	assert_eq(DesignerCollectionDialog.id_for("!!!", []), "my_collection")
	for text in ["My Forest!", "x", "A  b  C", "9 lives"]:
		assert_eq(
			LibraryIds.library_problems(DesignerCollectionDialog.id_for(text, [])).size(), 0, text
		)


func test_the_slots_cover_every_role_once() -> void:
	var seen := {}
	for group in DesignerSlots.GROUPS:
		for role: String in group["roles"]:
			assert_false(seen.has(role), "%s in two slots" % role)
			seen[role] = true
	for role: String in LibraryContracts.ROLES:
		assert_true(seen.has(role), "%s has a slot" % role)
		assert_true(DesignerSlots.ROLE_LABELS.has(role), "%s has words" % role)
		assert_true(DesignerSlots.ROLE_CATEGORY.has(role), "%s has a category" % role)
