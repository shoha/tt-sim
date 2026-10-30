extends GutTest

## The Building tool's second UI round (topic building_ui2): the palette's filter chips and tile
## measures (StructurePalette), the hint bar's keys and their fade (StructureHints), the live note
## beside the ghost lot (StructureNote and the brush's cache), the hover card's words, and the
## pane's chips and columns. docs/systems/structures.md "The tool".

const TEMP_SETTINGS := "user://test_building_ui2_settings.cfg"

var _saved_path: String = ""


func before_each() -> void:
	StructureRecipes.ensure_served()
	_saved_path = UiPreferences.settings_path
	UiPreferences.settings_path = TEMP_SETTINGS
	StructureHints.reset()


func after_each() -> void:
	UiPreferences.settings_path = _saved_path
	StructureHints.reset()
	if FileAccess.file_exists(TEMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))


func _rows() -> Array[Dictionary]:
	return [
		{"name": "Cottage", "family": "cottage", "tags": ["stone", "regional"], "library": "t"},
		{"name": "Thatched cottage", "family": "cottage", "tags": ["thatch"], "library": "t"},
		{"name": "Barn", "family": "farm", "tags": ["barn", "timber", "regional"], "library": "t"},
		{"name": "Old inn", "family": "inn", "tags": ["tavern", "timber"], "library": "t"},
		{"name": "Ruined tower", "family": "ruin", "tags": ["stone", "ruin"], "library": "t"},
		{"name": "Toon shop", "family": "toon", "tags": ["shop", "toon"], "library": "t"},
	]


func _names(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> String: return String(row["name"]))


# --- chips ---------------------------------------------------------------------------------


func test_a_chip_matches_by_family_or_tag() -> void:
	var rows := _rows()
	assert_true(StructurePalette.chip_matches(rows[0], "home"), "cottage family is Home")
	assert_true(StructurePalette.chip_matches(rows[2], "farm"), "family farm, tag barn")
	assert_true(StructurePalette.chip_matches(rows[3], "inn"), "family inn or tag tavern")
	assert_true(StructurePalette.chip_matches(rows[4], "ruin"))
	assert_true(StructurePalette.chip_matches(rows[5], "shop"), "by tag alone")
	assert_false(StructurePalette.chip_matches(rows[0], "farm"))
	assert_false(StructurePalette.chip_matches(rows[0], "no_such_chip"))


func test_chips_of_one_group_widen_and_of_two_groups_narrow() -> void:
	var rows := _rows()
	var kinds := StructurePalette.filtered(rows, "", ["farm", "inn"])
	assert_eq(_names(kinds), ["Barn", "Old inn"], "Farm and Inn: either")
	var narrowed := StructurePalette.filtered(rows, "", ["farm", "inn", "timber"])
	assert_eq(_names(narrowed), ["Barn", "Old inn"], "timber of either")
	var stone_home := StructurePalette.filtered(rows, "", ["home", "stone"])
	assert_eq(_names(stone_home), ["Cottage"], "different groups both hold")
	assert_eq(StructurePalette.filtered(rows, "", []).size(), rows.size(), "no chip, no filter")


func test_chips_work_with_the_search_words() -> void:
	var found := StructurePalette.filtered(_rows(), "cottage", ["thatch"])
	assert_eq(_names(found), ["Thatched cottage"])
	assert_true(StructurePalette.filtered(_rows(), "barn", ["home"]).is_empty())
	var sections := StructurePalette.sections(_rows(), "", ["timber"])
	assert_eq(sections.size(), 2, "farm and inn sections")


func test_a_chips_count_is_what_it_would_show() -> void:
	var rows := _rows()
	var counts := StructurePalette.chip_counts(rows, "", [])
	assert_eq(counts["home"], 2)
	assert_eq(counts["timber"], 2)
	assert_eq(counts["church"], 0, "no church in this set")
	var with_stone := StructurePalette.chip_counts(rows, "", ["stone"])
	assert_eq(with_stone["home"], 1, "Home counts the homes of stone")
	assert_eq(with_stone["stone"], 2, "a chip of the group on counts what it would add alone")
	assert_eq(with_stone["thatch"], 1, "thatch beside stone would add the thatched cottage")
	var searched := StructurePalette.chip_counts(rows, "toon", [])
	assert_eq(searched["shop"], 1)
	assert_eq(searched["home"], 0)


func test_toggling_a_chip_keeps_the_chip_order() -> void:
	var on := StructurePalette.toggled(["stone"], "home", true)
	assert_eq(on, ["home", "stone"] as Array[String])
	var off := StructurePalette.toggled(on, "home", false)
	assert_eq(off, ["stone"] as Array[String])
	assert_eq(StructurePalette.toggled(off, "stone", true), ["stone"] as Array[String])
	assert_eq(StructurePalette.tally(14, 72, true), "14 of 72")
	assert_eq(StructurePalette.tally(72, 72, false), "")


func test_every_chip_names_a_real_group_and_nothing_is_empty_in_the_core_library() -> void:
	var served := LibraryStructureStore.structures()
	var counts := StructurePalette.chip_counts(served, "", [])
	var ids := {}
	for item in StructurePalette.CHIPS:
		assert_false(ids.has(item["id"]), "chip ids are unique")
		ids[item["id"]] = true
		assert_true(item["group"] in ["kind", "look", "material"])
		assert_gt(int(counts[item["id"]]), 0, "%s has buildings in core" % item["id"])


# --- tile measures and the card ------------------------------------------------------------


func test_tile_columns_follow_the_pane_width_and_the_size_choice() -> void:
	var large := StructurePalette.tile_metrics(false, 196.0)
	assert_eq(large["thumb"], StructurePalette.LARGE_THUMB_PX)
	assert_gte(int(large["thumb"]), 80)
	assert_eq(large["columns"], 2, "the drawer's width holds two large tiles")
	assert_eq(StructurePalette.tile_metrics(false, 320.0)["columns"], 3)
	assert_eq(StructurePalette.tile_metrics(false, 60.0)["columns"], 2, "never fewer than two")
	var small := StructurePalette.tile_metrics(true, 196.0)
	assert_eq(small["thumb"], StructurePalette.SMALL_THUMB_PX)
	assert_gt(int(small["columns"]), int(large["columns"]), "small tiles fit more across")
	assert_gt((large["tile"] as Vector2).y, (small["tile"] as Vector2).y)


func test_the_card_names_the_family_and_a_few_tags_without_repeating() -> void:
	var card := StructurePalette.card(
		{
			"name": "Saltbox house",
			"family": "house",
			"tags": ["house", "regional", "gable", "timber", "chimney", "porch", "trim"],
			"default_size_m": [6.0, 4.0],
		}
	)
	assert_eq(card["title"], "Saltbox house")
	assert_eq(card["detail"], "House: gable, timber, chimney, porch")
	assert_string_contains(String(card["size"]), "6 x 4 m")


# --- hint bar keys -------------------------------------------------------------------------


func test_the_hint_rows_drop_the_gestures_done_once() -> void:
	var fresh := StructureHints.rows([], false)
	assert_eq(fresh.size(), StructureHints.PLACING.size())
	assert_eq(fresh[0]["key"], "Click")
	var after := StructureHints.rows(["click", "turn"], false)
	assert_eq(after.size(), StructureHints.PLACING.size() - 2)
	for hint in after:
		assert_ne(hint["key"], "Click")
		assert_ne(hint["key"], "Q / E")
	assert_eq(StructureHints.rows(["click"], true).size(), StructureHints.SELECTED.size(), "apart")
	var everything: Array[String] = []
	for gesture in StructureHints.PLACING:
		everything.append(String(gesture["id"]))
	assert_true(StructureHints.rows(everything, false).is_empty(), "all done: the bar steps aside")


func test_progress_counts_the_gestures_done() -> void:
	assert_eq(StructureHints.progress([], false), {"done": 0, "total": 5})
	assert_eq(StructureHints.progress(["click", "again", "edit"], false), {"done": 2, "total": 5})
	assert_eq(StructureHints.progress(["edit", "copy"], true), {"done": 2, "total": 6})


func test_marking_a_gesture_is_once_and_remembered_in_the_settings_file() -> void:
	assert_eq(StructureHints.done(), [] as Array[String])
	assert_true(StructureHints.mark(&"click"), "a new gesture")
	assert_false(StructureHints.mark(&"click"), "twice is nothing new")
	assert_true(StructureHints.mark(&"turn"))
	StructureHints.reset()
	assert_eq(StructureHints.done(), ["click", "turn"] as Array[String], "read back from the file")
	StructureHints.reset(true)
	assert_eq(StructureHints.done(), [] as Array[String], "forgotten on request")
	assert_eq(StructureHints.marked(["a"], &"a"), ["a"] as Array[String])


func test_the_brush_says_which_gesture_it_saw() -> void:
	var brush := StructureBrush.new()
	brush.pick("core:cottage")
	watch_signals(brush)
	brush.turn(1)
	assert_signal_emitted_with_parameters(brush, "gesture_done", [&"turn"])
	brush.reroll_at(null, -1)
	assert_signal_emitted_with_parameters(brush, "gesture_done", [&"again"])


func test_the_tool_offers_the_rows_for_what_the_player_has_not_done() -> void:
	var tool := ToolRegistry.find(StructureTool.ID) as StructureTool
	var brush := BrushTool.new()
	add_child_autofree(brush)
	assert_eq(tool.key_hints(brush).size(), StructureHints.PLACING.size())
	StructureHints.mark(&"click")
	assert_eq(tool.key_hints(brush).size(), StructureHints.PLACING.size() - 1)


func test_the_selection_bar_wires_to_any_brush_and_tells_the_hint_bar() -> void:
	# The GM's Events pane wires its own Building pane through the same call as authoring's.
	var tool := ToolRegistry.find(StructureTool.ID) as StructureTool
	var brush := BrushTool.new()
	add_child_autofree(brush)
	var pane := _pane()
	var told: Array[int] = [0]
	tool.connect_selection(brush, pane, func() -> void: told[0] += 1)
	var mode := StructureTool.of(brush)
	mode.gesture_done.emit(&"click")
	assert_eq(told[0], 1, "a gesture done once changes the bar's rows")
	mode.gesture_done.emit(&"click")
	assert_eq(told[0], 1, "and only the first time")
	mode.select(5)
	assert_eq(told[0], 2, "a selection changes them too")
	assert_eq(StructureHints.done(), ["click"] as Array[String])
	# A second connection (a rebuilt pane) replaces the first rather than doubling it.
	tool.connect_selection(brush, _pane(), func() -> void: told[0] += 10)
	mode.select(-1)
	assert_eq(told[0], 12)


# --- the live note -------------------------------------------------------------------------


func test_a_blocked_lot_says_why_in_red_words() -> void:
	var water := StructureNote.live(StructurePlacement.WATER, StructurePlacement.WATER, false, "")
	assert_eq(water["level"], StructureNote.Level.BLOCKED)
	assert_eq(water["text"], StructureBrush.WATER_TEXT)
	var steep := StructureNote.live(StructurePlacement.STEEP, "", false, "")
	assert_eq(steep["text"], StructureBrush.STEEP_TEXT)
	var odd := StructureNote.live("odd", "", false, "")
	assert_eq(odd["text"], StructureBrush.INVALID_TEXT, "an unknown reason still says something")
	assert_ne(StructureNote.colour(StructureNote.Level.BLOCKED), StructureNote.colour(0))


func test_a_moved_lot_says_what_it_moved_off_in_amber() -> void:
	for why in [
		StructurePlacement.WATER,
		StructurePlacement.STEEP,
		StructurePlacement.OFF_MAP,
		StructurePlacement.OCCUPIED,
	]:
		var made := StructureNote.live("", why, true, "")
		assert_eq(made["level"], StructureNote.Level.NOTE)
		assert_true(String(made["text"]).begins_with("Moved"), String(made["text"]))
	assert_eq(StructureNote.live("", "", false, "")["level"], StructureNote.Level.NONE)
	assert_eq(StructureNote.live("", "", false, "")["text"], "")


func test_a_held_size_is_stated_with_its_units_and_beats_a_move() -> void:
	var big := StructureNote.clamp_text(Vector2(40, 30), Vector2(12, 9), 1.0, 3.0, "ft")
	assert_eq(big, "Biggest size this building goes: 36 x 27 ft.")
	var small := StructureNote.clamp_text(Vector2(1, 1), Vector2(4, 3), 1.0, 3.0, "ft")
	assert_string_contains(small, "Smallest size")
	assert_eq(StructureNote.clamp_text(Vector2(6, 4), Vector2(6, 4), 1.0, 3.0, "ft"), "")
	var both := StructureNote.live("", StructurePlacement.WATER, true, big)
	assert_eq(both["text"], big, "the size stop leads a move")
	var blocked := StructureNote.live(StructurePlacement.WATER, "", false, big)
	assert_eq(blocked["level"], StructureNote.Level.BLOCKED, "a block leads all")


func test_nearest_legal_says_what_the_pointers_own_spot_failed_on() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var legal := StructurePlacement.nearest_legal(doc, Vector2(0, 0), Vector2(6, 4), 0.0)
	assert_eq(legal["why"], "")
	assert_false(legal["moved"])
	var off := StructurePlacement.nearest_legal(doc, Vector2(400, 0), Vector2(6, 4), 0.0)
	assert_eq(off["problem"], StructurePlacement.OFF_MAP)
	assert_eq(off["why"], StructurePlacement.OFF_MAP)
	var rim := Vector2(doc.extent_m().x * 0.5, 0.0)
	var edge := StructurePlacement.nearest_legal(doc, rim, Vector2(6, 4), 0.0)
	assert_true(edge["moved"], "eased back from the map's edge")
	assert_eq(edge["why"], StructurePlacement.OFF_MAP)


# --- the pane ------------------------------------------------------------------------------


func _pane() -> StructureToolPane:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	return pane


func test_the_pane_has_a_chip_per_filter_with_counts_and_filters_the_tiles() -> void:
	var pane := _pane()
	var all := pane.refs().size()
	assert_eq(pane.chip_buttons.size(), StructurePalette.CHIPS.size())
	var home: Button = pane.chip_buttons["home"]
	assert_string_contains(home.text, "Home ")
	assert_true(pane.clear_button.disabled, "nothing to clear yet")
	pane.set_chip("ruin", true)
	assert_lt(pane.refs().size(), all)
	assert_gt(pane.refs().size(), 0)
	assert_true((pane.chip_buttons["ruin"] as Button).button_pressed)
	assert_false(pane.clear_button.disabled)
	assert_string_contains(pane.clear_button.text, " of %d" % all)
	pane.set_chip("ruin", false)
	assert_eq(pane.refs().size(), all)


func test_chips_and_search_work_together_and_clear_resets_both() -> void:
	var pane := _pane()
	var all := pane.refs().size()
	pane.set_chip("stone", true)
	var stone := pane.refs().size()
	pane.search_edit.text = "tower"
	pane.search_edit.text_changed.emit("tower")
	assert_lt(pane.refs().size(), stone)
	pane.clear_filters()
	assert_eq(pane.refs().size(), all)
	assert_eq(pane.search_edit.text, "")
	assert_true(pane.active_chips().is_empty())
	assert_true(pane.clear_button.disabled)


func test_two_chips_with_no_common_building_say_so_and_keep_the_chips() -> void:
	var pane := _pane()
	pane.set_chip("toon", true)
	pane.set_chip("church", true)
	assert_true(pane.refs().is_empty(), "no toon building is a church")
	assert_true((pane.get_node("StructureNoMatch") as Label).visible)
	assert_eq((pane.get_node("StructureNoMatch") as Label).text, StructureToolPane.NO_MATCH_CHIPS)
	assert_true((pane.chip_buttons["toon"] as Button).button_pressed, "the chips stay to switch off")
	assert_false((pane.chip_buttons["home"] as Button).button_pressed)


func test_the_tiles_are_large_and_the_columns_follow_the_pane_width() -> void:
	var pane := _pane()
	pane.small_tiles_button.button_pressed = false
	pane.size = Vector2(pane.size.x, 600)
	var tiles: TileRow = pane.family_fields[0].tiles
	assert_gte(tiles.tile_min_size.x, 92.0)
	assert_gte(tiles.tile_min_size.y, 112.0)
	assert_eq(tiles.columns, StructurePalette.tile_metrics(false, pane.size.x)["columns"])
	pane.size = Vector2(700, 600)
	var wide: int = StructurePalette.tile_metrics(false, 700.0)["columns"]
	assert_eq(pane.family_fields[0].tiles.columns, wide)
	assert_gt(pane.family_fields[0].tiles.columns, 2, "a wide drawer takes more columns")


func test_the_small_tiles_switch_shrinks_the_pictures_and_is_remembered() -> void:
	var pane := _pane()
	pane.size = Vector2(196, 600)
	pane.small_tiles_button.button_pressed = true
	var tiles: TileRow = pane.family_fields[0].tiles
	assert_lt(tiles.tile_min_size.y, 100.0)
	assert_true(UiPreferences.load_structure_tiles_small(), "saved in the settings file")
	pane.small_tiles_button.button_pressed = false
	assert_false(UiPreferences.load_structure_tiles_small())


func test_the_pane_no_longer_carries_the_keys_as_prose() -> void:
	var pane := _pane()
	var hint := pane.get_node("StructureHint") as Label
	assert_false(hint.text.contains("Q and E"), "the keys are key caps on the hint bar")
	assert_lt(hint.text.length(), 90)
