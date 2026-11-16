extends GutTest

## The map tools' frame (card ui-authoring, docs/UI_TASTE.md 2026-11-15 "Map building"): the rail's
## groups and the tools it keeps, the drawer's material (paper by default, glass one constant away,
## both drawn by theme variations rather than code), the active tool's state, the option pane that
## follows the tool, the Undo, Redo and Save words and keys, the first-strokes card that goes once,
## and the drawer's motion under Reduce motion.

const TEMP_PATH := "user://test_authoring_ui.cfg"
## The 1280x720 window at Auto interface size: its canvas is 1371 x 771 virtual px.
const CANVAS_720P := Vector2(1371.0, 771.0)

var _host: Control


func before_each() -> void:
	UiPreferences.settings_path = TEMP_PATH
	UiMotion.user_reduce = false
	_host = Control.new()
	_host.size = CANVAS_720P
	add_child_autofree(_host)


func after_each() -> void:
	UiMotion.user_reduce = false
	UiPreferences.settings_path = Paths.SETTINGS_PATH
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _panel(theme: Theme = null) -> AuthoringPanel:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var panel := AuthoringPanel.new()
	panel.theme = theme if theme != null else AuthoringChrome.surface_theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	return panel


func _gaps(rail: Control) -> Array[Node]:
	return rail.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("Gap"))


# -- The rail ---------------------------------------------------------------------------------


func test_every_tool_is_still_on_the_rail_and_every_action_under_it() -> void:
	var panel := _panel()
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		assert_true(panel._rail.has_item(tool.id), "%s is on the rail" % tool.id)
	for action: Dictionary in AuthoringChrome.FOOTER_ITEMS:
		assert_true(panel._footer_rail.has_item(action["id"]), "%s is under it" % action["id"])


func test_the_rail_breaks_into_four_runs_of_related_tools() -> void:
	var panel := _panel()
	assert_eq(_gaps(panel._rail).size(), 3, "four runs have three breaks between them")
	var groups: Dictionary = {}
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		groups[ToolRegistry.GROUPS[tool.id]] = true
	assert_eq(groups.size(), 4, "land, shape, features and build")
	var previous := &""
	var changes := 0
	for item: Dictionary in ToolRegistry.rail_items(ToolDescriptor.AUTHORING):
		if previous != &"" and item["group"] != previous:
			changes += 1
		previous = item["group"]
	assert_eq(changes, 3, "runs are contiguous: each group is one run in rail order")


func test_the_rail_and_its_actions_fit_a_720p_window() -> void:
	var panel := _panel()
	await get_tree().process_frame
	var need := panel._rail_panel.get_combined_minimum_size().y + panel.tab_top_margin
	assert_lt(need, CANVAS_720P.y, "the whole rail, tools and actions, is %.0f px tall" % need)


func test_the_drawer_card_is_as_tall_as_its_pane_and_never_taller_than_the_window() -> void:
	_host.size = Vector2(1920.0, 1080.0)
	var panel := _panel()
	panel.reveal()
	panel.open()
	panel.show_tool_pane(AuthoringPanel.TOOL_SCULPT)
	await get_tree().create_timer(UiMotion.PANEL_IN_S + 0.2).timeout
	var short := panel._panel.size.y
	assert_lt(short, 0.6 * panel.size.y, "Sculpt is short: the board shows below its card")
	assert_almost_eq(panel._panel.position.y, panel.tab_top_margin, 0.5, "level with the rail's top")
	panel.show_tool_pane(AuthoringPanel.TOOL_PLACE)
	await get_tree().create_timer(0.3).timeout
	assert_gt(panel._panel.size.y, short, "Place has more to show")
	assert_lte(
		panel._panel.size.y, panel.size.y - 2.0 * panel.tab_top_margin + 0.5, "inside the window"
	)


func test_without_fit_the_panel_runs_the_whole_edge() -> void:
	_host.size = Vector2(1920.0, 1080.0)
	var panel := _panel()
	panel.fit_height = false
	panel.fit_panel_height(0.0)
	await get_tree().process_frame
	assert_almost_eq(panel._panel.size.y, panel.size.y, 0.5)
	assert_almost_eq(panel._panel.position.y, 0.0, 0.01)


func test_tooltips_carry_the_keys() -> void:
	var panel := _panel()
	var save_button: Control = panel._footer_rail._buttons[AuthoringPanel.ACTION_SAVE]
	assert_string_contains(save_button.tooltip_text, "Ctrl+S")
	assert_string_contains(
		panel._footer_rail._buttons[AuthoringPanel.ACTION_LEAVE].tooltip_text, "Esc"
	)
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		var tip: String = panel._rail._buttons[tool.id].tooltip_text
		assert_true(tip.begins_with(tool.label), "%s names itself first: %s" % [tool.id, tip])


# -- The tool's state and its option pane ----------------------------------------------------


func test_the_active_tool_is_marked_and_only_one() -> void:
	var panel := _panel()
	panel.set_active_tool(AuthoringPanel.TOOL_SCULPT)
	assert_true(panel._rail._buttons[AuthoringPanel.TOOL_SCULPT].active, "sculpt is marked")
	panel.set_active_tool(AuthoringPanel.TOOL_WATER)
	assert_false(panel._rail._buttons[AuthoringPanel.TOOL_SCULPT].active, "sculpt let go")
	assert_true(panel._rail._buttons[AuthoringPanel.TOOL_WATER].active, "water is marked")
	assert_eq(panel.get_active_tool(), AuthoringPanel.TOOL_WATER)
	panel.set_active_tool(&"")
	assert_false(panel._rail._buttons[AuthoringPanel.TOOL_WATER].active, "none marked")


func test_the_option_pane_follows_the_tool() -> void:
	var panel := _panel()
	panel.show_tool_pane(AuthoringPanel.TOOL_SCULPT)
	assert_eq(panel._stack.current, AuthoringPanel.TOOL_SCULPT)
	panel.show_tool_pane(AuthoringPanel.TOOL_WATER)
	assert_eq(panel._stack.current, AuthoringPanel.TOOL_WATER)
	var asked: Array[StringName] = []
	panel.tool_selected.connect(func(id: StringName) -> void: asked.append(id))
	panel._on_rail_item_pressed(AuthoringPanel.TOOL_BIOME)
	assert_eq(panel._stack.current, AuthoringPanel.TOOL_BIOME)
	assert_eq(asked, [AuthoringPanel.TOOL_BIOME] as Array[StringName], "and the controller is told")


func test_the_name_field_is_named_without_a_caption_line() -> void:
	var panel := _panel()
	assert_ne(panel.name_edit.tooltip_text, "")
	assert_eq(panel.name_edit.accessibility_name, "Map name")
	var captions := panel.content_container.get_children().filter(
		func(child: Node) -> bool: return child is Label and (child as Label).text == "Map name"
	)
	assert_eq(captions.size(), 0, "the field says what it is itself")


# -- Undo, Redo, Save -----------------------------------------------------------------------


func test_undo_and_redo_say_what_they_act_on() -> void:
	var panel := _panel()
	panel.set_history_state(true, true, "Raise", "Flatten")
	var undo: Button = panel._footer_rail._buttons[AuthoringPanel.ACTION_UNDO]
	var redo: Button = panel._footer_rail._buttons[AuthoringPanel.ACTION_REDO]
	assert_eq(undo.tooltip_text, "Undo Raise (Ctrl+Z)")
	assert_eq(redo.tooltip_text, "Redo Flatten (Ctrl+Y)")
	assert_false(undo.disabled)
	panel.set_history_state(false, false)
	assert_eq(undo.tooltip_text, "Nothing to undo")
	assert_eq(redo.tooltip_text, "Nothing to redo")
	assert_true(undo.disabled and redo.disabled, "drawn off, not hidden")


func test_the_history_names_its_next_edits() -> void:
	var history := AuthoringHistory.new()
	assert_eq(history.next_undo_label(), "")
	history.record({"label": "Raise", "undo": Callable(), "redo": Callable()})
	history.record({"label": "Smooth", "undo": Callable(), "redo": Callable()})
	assert_eq(history.next_undo_label(), "Smooth")
	history.undo()
	assert_eq(history.next_undo_label(), "Raise")
	assert_eq(history.next_redo_label(), "Smooth")


func test_save_says_whether_there_is_anything_to_save() -> void:
	var panel := _panel()
	panel.set_dirty(true)
	var save: Button = panel._footer_rail._buttons[AuthoringPanel.ACTION_SAVE]
	assert_string_contains(save.tooltip_text, "unsaved changes")
	panel.set_dirty(false)
	assert_string_contains(save.tooltip_text, "all changes saved")


func test_ctrl_s_is_the_save_key_and_nothing_else_is() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_S
	press.pressed = true
	assert_false(AuthoringChrome.is_save_key(press), "S alone")
	press.ctrl_pressed = true
	assert_true(AuthoringChrome.is_save_key(press), "Ctrl+S")
	press.echo = true
	assert_false(AuthoringChrome.is_save_key(press), "a held key")
	press.echo = false
	press.pressed = false
	assert_false(AuthoringChrome.is_save_key(press), "the release")
	assert_false(AuthoringChrome.is_save_key(InputEventMouseMotion.new()))


# -- The material ---------------------------------------------------------------------------


func test_the_map_tools_are_paper_and_glass_is_one_constant_away() -> void:
	assert_true(AuthoringChrome.SURFACE_PAPER, "paper: building a map stops play")
	assert_eq(AuthoringChrome.surface_theme().resource_path, ThemeColors.PAPER_THEME_PATH)


func test_the_drawer_is_drawn_by_the_theme_and_follows_its_leaf() -> void:
	var panel := _panel()
	assert_false(panel._panel.has_theme_stylebox_override("panel"), "no panel style in code")
	assert_false(panel._rail_panel.has_theme_stylebox_override("panel"), "no rail style in code")
	assert_eq(panel._panel.theme_type_variation, &"DrawerCardLeft", "a card, as tall as its pane")
	assert_eq(panel._rail_panel.theme_type_variation, &"DrawerRailLeft")
	assert_eq(panel._margin.theme_type_variation, &"DrawerMarginRoomy")
	for leaf: Theme in [ThemeColors.paper_theme(), ThemeColors.glass_theme()]:
		panel.theme = leaf
		var box := panel._panel.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(box.bg_color, ThemeColors.of(panel, ThemeColors.SURFACE), "the leaf's surface")
		assert_eq(box.corner_radius_top_left, 0, "square against the screen's edge")
		assert_eq(box.corner_radius_top_right, 0, "square where it meets the rail: no notch")
		assert_eq(box.corner_radius_bottom_right, 0, "square where it meets the rail: no notch")
		assert_gt(box.corner_radius_bottom_left, 0, "its free corner is rounded")


func test_both_leaves_define_every_drawer_variation() -> void:
	for leaf: Theme in [ThemeColors.paper_theme(), ThemeColors.glass_theme()]:
		for side in ["Left", "Right"]:
			assert_true(leaf.has_stylebox("panel", "DrawerPanel" + side))
			assert_true(leaf.has_stylebox("panel", "DrawerCard" + side))
			assert_true(leaf.has_stylebox("panel", "DrawerRail" + side))
			for state in ["normal", "hover", "pressed"]:
				assert_true(leaf.has_stylebox(state, "DrawerTab" + side), "%s %s" % [side, state])
		for margin in ["DrawerMargin", "DrawerMarginRoomy"]:
			assert_true(leaf.has_constant("margin_left", margin))


# -- Round 2 (the critic's ranked fixes, 2026-11-16) ----------------------------------------


func test_rail_targets_are_46_wide_with_20_px_between_runs_and_still_fit_720p() -> void:
	var panel := _panel()
	await get_tree().process_frame
	for id: StringName in panel._rail._buttons:
		var button: Control = panel._rail._buttons[id]
		assert_gte(button.custom_minimum_size.x, 46.0, "%s is a large target" % id)
	for gap in _gaps(panel._rail):
		var step: float = (gap as Control).custom_minimum_size.y + 2.0 * IconRail.ITEM_GAP
		assert_gte(step, 20.0, "a run ends with a 20 px break")
	var actions := panel._footer_rail.get_parent()
	assert_eq(actions.name, "ActionColumn", "the actions stand in a column beside the tools")
	assert_true(panel._rail.chip, "the active tool wears a chip")
	assert_false(panel._footer_rail.chip, "actions are not tools: no chip")


func test_the_active_tool_has_a_chip_not_only_a_stripe() -> void:
	var panel := _panel()
	panel.reveal()
	panel.open()
	await get_tree().create_timer(UiMotion.PANEL_IN_S + 0.2).timeout
	panel._rail.select(AuthoringPanel.TOOL_SCULPT)
	await get_tree().process_frame
	var chip := panel._rail.chip_rect()
	assert_gt(chip.size.x, 40.0, "the chip spans the item")
	assert_almost_eq(chip.size.y, 46.0, 0.01)
	var item: Control = panel._rail._buttons[AuthoringPanel.TOOL_SCULPT]
	assert_true(chip.has_point(item.get_rect().get_center()), "it sits behind the icon")


func test_the_longest_help_has_a_two_line_lead_and_the_rest_behind_more() -> void:
	var panel := _panel()
	var panes := {
		&"BiomeHint": panel._stack.get_pane(AuthoringPanel.TOOL_BIOME),
		&"PlaceHint": panel._stack.get_pane(AuthoringPanel.TOOL_PLACE),
		&"WaterHint": panel._stack.get_pane(AuthoringPanel.TOOL_WATER),
	}
	for hint_name: StringName in panes:
		var pane: Control = panes[hint_name]
		var lead := pane.get_node(String(hint_name)) as Label
		assert_lt(lead.text.length(), 95, "%s: a lead of two short lines" % hint_name)
		var more := pane.get_node(String(hint_name) + "More") as Foldout
		assert_false(more.expanded, "%s: the rest is behind More" % hint_name)
		assert_eq(more.title, "More")


func test_place_tiles_name_species_by_picture_and_the_biome_rows_read_in_ink() -> void:
	var oak := AuthoringChrome.place_icon("oak", "tree")
	var birch := AuthoringChrome.place_icon("birch", "tree")
	var pine := AuthoringChrome.place_icon("dwarf_pine", "tree")
	assert_ne(oak, birch)
	assert_ne(oak, pine)
	assert_ne(birch, pine)
	for icon in [oak, birch, pine, "plant", "stone", "cactus"]:
		assert_not_null(IconButton.load_icon(icon), "%s exists" % icon)
	assert_eq(AuthoringChrome.place_icon("boulder", "grain"), "stone")
	assert_eq(AuthoringChrome.place_icon("moss", "grain"), "grain", "no word: the kind's icon")
	var panel := _panel()
	var place := panel._stack.get_pane(AuthoringPanel.TOOL_PLACE)
	var foldouts := place.get_children().filter(
		func(c: Node) -> bool: return c is Foldout and c.name.begins_with("Place_")
	)
	assert_gt(foldouts.size(), 0)
	for foldout: Foldout in foldouts:
		assert_eq(foldout.title_variation, &"FoldoutTitle", "ink, not the soft grey")
		assert_lte(foldout.title.split(" ").size(), 2, "the same short name as the Biome tile")


func test_the_unsaved_cue_is_a_word_as_well_as_a_dot() -> void:
	var panel := _panel()
	var save: Button = panel._footer_rail._buttons[AuthoringPanel.ACTION_SAVE]
	panel.set_dirty(true)
	var word := save.get_node("ItemCaption") as Label
	assert_eq(word.text, AuthoringChrome.UNSAVED_WORD)
	assert_true(word.visible)
	assert_true(save.badge)
	panel.set_dirty(false)
	assert_false(word.visible, "saved: the word goes")


func test_the_empty_village_pane_has_one_action_that_goes_to_the_street_tool() -> void:
	var pane := VillageToolPane.new()
	add_child_autofree(pane)
	assert_true(pane.empty_card.visible)
	assert_false(pane.hint.visible, "no plaza gesture before there is a village")
	assert_false(pane.empty_note.text.contains("Dress"), "plain words")
	watch_signals(pane)
	pane.street_button.pressed.emit()
	assert_signal_emitted(pane, "street_requested")


func test_the_card_steps_back_under_a_stroke_and_returns() -> void:
	UiMotion.user_reduce = true
	var card := PanelContainer.new()
	var rail := PanelContainer.new()
	_host.add_child(card)
	_host.add_child(rail)
	card.size = Vector2(200, 200)
	rail.position = Vector2(200, 0)
	rail.size = Vector2(50, 200)
	var dimmer := CardDimmer.new()
	dimmer.card = card
	dimmer.rail = rail
	dimmer.is_open = func() -> bool: return true
	add_child_autofree(dimmer)
	dimmer.dim(true)
	assert_almost_eq(card.modulate.a, AuthoringChrome.STROKE_DIM, 0.001)
	dimmer.dim(false)
	assert_almost_eq(card.modulate.a, 1.0, 0.001)
	assert_true(dimmer._over_chrome(Vector2(10, 10)), "a press on the card is the drawer's")
	assert_true(dimmer._over_chrome(Vector2(220, 10)), "and so is the rail's")
	assert_false(dimmer._over_chrome(Vector2(600, 400)), "the board is not")


func test_the_card_height_eases_when_the_pane_changes_and_cuts_under_reduce_motion() -> void:
	_host.size = Vector2(1920.0, 1080.0)
	var panel := _panel()
	panel.reveal()
	await get_tree().create_timer(UiMotion.PANEL_IN_S + 0.1).timeout
	panel.open()
	panel.show_tool_pane(AuthoringPanel.TOOL_SCULPT)
	await get_tree().create_timer(UiMotion.PANEL_IN_S + 0.2).timeout
	panel.fit_panel_height(600.0)
	assert_lt(panel._panel.size.y, 600.0, "on its way, not there")
	await get_tree().create_timer(UiMotion.STATE_S + 0.1).timeout
	assert_almost_eq(panel._panel.size.y, 600.0, 0.5)
	UiMotion.user_reduce = true
	panel.fit_panel_height(300.0)
	assert_almost_eq(panel._panel.size.y, 300.0, 0.5, "a cut")


# -- The first-strokes card -----------------------------------------------------------------


func test_the_first_strokes_card_shows_once_and_goes_for_good() -> void:
	var card := AuthoringWelcome.new()
	add_child_autofree(card)
	assert_false(card.visible, "hidden until asked")
	assert_true(card.show_once(), "shown to a newcomer")
	assert_true(card.visible)
	watch_signals(card)
	card.dismiss()
	assert_signal_emitted(card, "dismissed")
	assert_true(UiPreferences.load_authoring_welcome_done(), "remembered")
	var again := AuthoringWelcome.new()
	add_child_autofree(again)
	assert_false(again.show_once(), "never shown again")
	assert_false(again.visible)


func test_dismissing_a_card_that_is_not_showing_saves_nothing() -> void:
	var card := AuthoringWelcome.new()
	add_child_autofree(card)
	card.dismiss()
	assert_false(UiPreferences.load_authoring_welcome_done())


func test_the_card_fades_and_never_moves_under_reduce_motion() -> void:
	UiMotion.user_reduce = true
	var card := AuthoringWelcome.new()
	add_child_autofree(card)
	var rest := card.position
	card.show_once()
	await get_tree().create_timer(UiMotion.FADE_ONLY_S + 0.1).timeout
	assert_almost_eq(card.modulate.a, 1.0, 0.01, "faded in within the fade-only time")
	assert_eq(card.position, rest, "no travel")
	assert_eq(card.scale, Vector2.ONE, "no scale")


func test_the_card_stays_clear_of_the_drawer_at_720p() -> void:
	var card := AuthoringWelcome.new()
	_host.add_child(card)
	card.show_once()
	await get_tree().process_frame
	await get_tree().process_frame
	var rect := card.get_global_rect()
	var drawer_edge := AuthoringPanel.DRAWER_WIDTH + 104.0
	assert_gt(rect.position.x, drawer_edge, "right of the open drawer and its rail")
	assert_lt(rect.end.x, CANVAS_720P.x, "inside the window")


# -- Motion ----------------------------------------------------------------------------------


func test_the_drawer_slides_normally_and_does_not_travel_under_reduce_motion() -> void:
	var panel := _panel()
	panel.reveal()
	await get_tree().create_timer(UiMotion.PANEL_IN_S + 0.1).timeout
	panel.open()
	assert_lt(panel._sled.position.x, 0.0, "it is still on its way in")
	UiMotion.user_reduce = true
	var calm := _panel()
	calm.reveal()
	await get_tree().create_timer(UiMotion.FADE_ONLY_S + 0.1).timeout
	calm.open()
	assert_almost_eq(calm._sled.position.x, 0.0, 0.01, "it is where it stays: only a fade")
	assert_almost_eq(calm._sled.modulate.a, 0.0, 0.01, "and fades in from clear")
