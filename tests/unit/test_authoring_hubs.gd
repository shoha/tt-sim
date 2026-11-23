extends GutTest

## The map tools' rail of seven and its three hubs (card ui-authoring3, docs/UI_TASTE.md "2026-11-16
## map building 3"): the registry's order, groups and keys, a tab routing to the tool it was a rail
## item of (so every brush mode, pane and id still answers), the keys that open a hub on its last
## tab and step through its tabs, the actions pill, and the layout at 1280x720 and 1920x1080.

const TEMP_PATH := "user://test_authoring_hubs.cfg"
## The 1280x720 window at Auto interface size: its canvas is 1371 x 771 virtual px.
const CANVAS_720P := Vector2(1371.0, 771.0)
const CANVAS_1080P := Vector2(1920.0, 1080.0)
const RAIL_ORDER: Array[StringName] = [
	&"biome", &"place", &"sculpt", &"paint", &"water", &"build", &"fire"
]

var _host: Control


func before_each() -> void:
	UiPreferences.settings_path = TEMP_PATH
	UiMotion.user_reduce = true
	_host = Control.new()
	_host.size = CANVAS_720P
	add_child_autofree(_host)


func after_each() -> void:
	UiMotion.user_reduce = false
	UiPreferences.settings_path = Paths.SETTINGS_PATH
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _panel() -> AuthoringPanel:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var panel := AuthoringPanel.new()
	panel.theme = AuthoringChrome.surface_theme()
	layer.add_child(panel)
	# A canvas layer's children fill the test window, so the panel takes the host's size by hand.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = _host.size
	return panel


## What the controller does with the panel's pick: marks the tool active, as _select_tool does.
func _follow(panel: AuthoringPanel) -> void:
	panel.tool_selected.connect(func(id: StringName) -> void: panel.set_active_tool(id))
	panel.water_shape_selected.connect(
		func(_shape: int) -> void: panel.set_active_tool(AuthoringPanel.TOOL_WATER)
	)


## A panel revealed and open (under Reduce motion, so the card is where it stays after a frame).
func _open_panel() -> AuthoringPanel:
	var panel := _panel()
	panel.reveal()
	await get_tree().create_timer(UiMotion.FADE_ONLY_S + 0.1).timeout
	panel.open()
	await get_tree().create_timer(UiMotion.FADE_ONLY_S + 0.1).timeout
	return panel


func _key(keycode: Key, ctrl: bool = false) -> InputEventKey:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	press.ctrl_pressed = ctrl
	return press


# -- The registry ---------------------------------------------------------------------------------


func test_the_rail_lists_seven_tools_in_order_and_each_hub_tab_has_its_tool() -> void:
	var ids: Array[StringName] = []
	for tool in ToolRegistry.rail_tools(ToolDescriptor.AUTHORING):
		ids.append(tool.id)
	assert_eq(ids, RAIL_ORDER, "Biome, Place, Sculpt, Paint, Water, Build, Fire")
	var listed := ToolRegistry.rail_items(ToolDescriptor.AUTHORING)
	assert_eq(listed.size(), 7)
	for tab_tool: StringName in [
		ThinTool.ID, BridgeTool.ID, WallTool.ID, StructureTool.ID, VillageTool.ID
	]:
		var tool := ToolRegistry.find(tab_tool)
		assert_not_null(tool, "%s keeps its descriptor" % tab_tool)
		assert_false(tool.on_rail, "%s has no rail item" % tab_tool)
		assert_ne(tool.hub, &"", "%s is a tab of a hub" % tab_tool)
		assert_true(ids.has(tool.hub), "%s's hub is on the rail" % tab_tool)
		assert_eq(ToolRegistry.hub_of(tab_tool), tool.hub)
		assert_false(ToolRegistry.tab_for(tool.hub, tab_tool).is_empty(), "%s has a tab" % tab_tool)
	assert_eq(ToolRegistry.hub_of(WaterTool.ID), WaterTool.ID, "a rail tool is its own hub")


func test_the_hubs_hold_the_tabs_the_owner_asked_for() -> void:
	var labels := func(rail_id: StringName) -> Array:
		return ToolRegistry.find(rail_id).tabs.map(func(tab: Dictionary) -> String: return tab["label"])
	assert_eq(labels.call(PlaceTool.ID), ["Add", "Thin / Clear"])
	assert_eq(labels.call(WaterTool.ID), ["River", "Pond", "Crossing"])
	assert_eq(labels.call(BuildTool.ID), ["Walls", "Buildings", "Villages"])
	# The Path tool joined Paint as its tab (card terraform-p2-paint-path).
	assert_eq(labels.call(PaintTool.ID), ["Paint", "Path"])
	for rail_id in [BiomeTool.ID, SculptTool.ID, FireTool.ID]:
		assert_true(ToolRegistry.find(rail_id).tabs.is_empty(), "%s has no tabs" % rail_id)


func test_play_keeps_every_live_brush_as_its_own_tool() -> void:
	var play: Array[StringName] = []
	for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
		play.append(tool.id)
	var ids: Array[StringName] = [
		BiomeTool.ID, ThinTool.ID, SculptTool.ID, PaintTool.ID, WaterTool.ID, BridgeTool.ID
	]
	for id: StringName in ids:
		assert_true(play.has(id), "%s is still a play brush" % id)
	assert_false(play.has(BuildTool.ID), "the Build hub is authoring's alone")
	assert_false(play.has(PlaceTool.ID))


func test_every_rail_tool_has_its_own_bare_key_that_nothing_else_owns() -> void:
	var seen: Dictionary = {}
	for tool in ToolRegistry.rail_tools(ToolDescriptor.AUTHORING):
		assert_ne(tool.shortcut, KEY_NONE, "%s has a key" % tool.id)
		assert_false(seen.has(tool.shortcut), "%s: the key is unique" % tool.id)
		seen[tool.shortcut] = tool.id
		assert_false(
			AuthoringChrome.TAKEN_LETTERS.has(tool.shortcut), "%s: not a camera or brush key" % tool.id
		)
		assert_true(tool.rail_tip().begins_with("%s (%s)" % [tool.label, tool.shortcut_label()]))
	# The final list, as the docs and the help overlay give it.
	var letters := ""
	for tool in ToolRegistry.rail_tools(ToolDescriptor.AUTHORING):
		letters += tool.shortcut_label()
	assert_eq(letters, "BPTKHUF", "Biome, Place, Terrain, Kolour, H2O, bUild, Fire")
	# Ctrl, Alt, Shift and Meta never trigger a tool.
	var biome := ToolRegistry.find(BiomeTool.ID)
	assert_true(biome.matches_shortcut(_key(KEY_B)))
	assert_false(biome.matches_shortcut(_key(KEY_B, true)), "Ctrl+B")
	var alt := _key(KEY_B)
	alt.alt_pressed = true
	assert_false(biome.matches_shortcut(alt), "Alt+B")


func test_no_rail_key_is_an_action_or_a_projects_input_event() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_filedialog"):
			continue  # A file dialog's own keys, never reached from the board.
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			# Engine defaults (ui_*) are Ctrl or Command chords: only a bare key could clash.
			if key.ctrl_pressed or key.alt_pressed or key.shift_pressed or key.meta_pressed:
				continue
			if key.command_or_control_autoremap:
				continue
			for tool in ToolRegistry.rail_tools(ToolDescriptor.AUTHORING):
				assert_ne(
					[key.keycode, key.physical_keycode].has(tool.shortcut),
					true,
					"%s: %s is the input map's %s" % [tool.id, tool.shortcut_label(), action]
				)


func test_the_help_names_each_tab_under_its_hub_and_each_rail_tool_with_its_key() -> void:
	var names: Array = []
	for row in ToolRegistry.help_rows(ToolDescriptor.AUTHORING):
		names.append(row[0])
	# The row says the letter, as the rail's tooltip does.
	for expect in ["Place (P)", "Place: Thin / Clear", "Water (H)", "Water: Crossing", "Build (U)"]:
		assert_true(names.has(expect), expect)
	assert_true(names.has("Build: Walls"), "Wall's help row is named under its hub")
	assert_true(names.has("Build: Villages"))
	assert_true(names.has("Biome (B)") and names.has("Sculpt (T)"))
	assert_true(names.has("Fire (F)") and names.has("Paint (K)"))


func test_the_rail_corner_shows_the_letter_only_and_the_welcome_card_names_the_letters() -> void:
	var panel := _panel()
	var item := ToolRegistry.find(WaterTool.ID).rail_item(true)
	assert_eq(item["key"], "H")
	assert_false(item.has("digit"), "the letters are the only keys (owner, 2026-11-16)")
	assert_eq(AuthoringWelcome.keys_line(), "Keys B P T K H U F pick a tool; F1 lists all.")
	var key := panel._rail._buttons[WaterTool.ID].get_node_or_null("ItemKey") as Label
	assert_not_null(key)
	assert_eq(key.text, "H")
	assert_null(panel._rail._buttons[WaterTool.ID].get_node_or_null("ItemDigit"), "no digit corner")


# -- Tabs route to the tool they were -----------------------------------------------------


func test_selecting_a_tab_leaves_only_that_tab_pressed() -> void:
	# Round 1 of the captures showed two tabs drawn pressed: select() did not unpress the others.
	var strip := SegmentedTabs.new()
	add_child_autofree(strip)
	strip.add_tab(&"a", "A")
	strip.add_tab(&"b", "B")
	strip.add_tab(&"c", "C")
	strip.select(&"c")
	assert_false(strip.tab(&"a").button_pressed, "the first tab let go")
	assert_false(strip.tab(&"b").button_pressed)
	assert_true(strip.tab(&"c").button_pressed)


func test_a_rail_press_on_a_hub_opens_its_first_tab_and_picks_that_tool() -> void:
	var panel := _panel()
	var asked: Array[StringName] = []
	panel.tool_selected.connect(func(id: StringName) -> void: asked.append(id))
	panel._on_rail_item_pressed(BuildTool.ID)
	assert_eq(asked, [WallTool.ID] as Array[StringName], "Build opens on Walls")
	assert_eq(panel._stack.current, WallTool.ID, "with the Wall tool's own pane")
	assert_eq(panel.current_tab(BuildTool.ID), WallTool.ID)
	assert_true(panel.hub_tabs(BuildTool.ID).visible, "the tabs show")
	assert_false(panel.hub_tabs(WaterTool.ID).visible, "and only Build's")


func test_each_tab_shows_its_old_pane_and_picks_its_old_tool() -> void:
	var panel := _panel()
	var asked: Array = []
	panel.tool_selected.connect(func(id: StringName) -> void: asked.append(id))
	panel.water_shape_selected.connect(func(shape: int) -> void: asked.append(shape))
	panel._on_rail_item_pressed(PlaceTool.ID)
	panel.hub_tabs(PlaceTool.ID).tab(ThinTool.ID).button_pressed = true
	assert_eq(panel._stack.current, ThinTool.ID, "Thin / Clear's own pane")
	for tab: StringName in [StructureTool.ID, VillageTool.ID, WallTool.ID]:
		panel._on_rail_item_pressed(BuildTool.ID)
		panel.hub_tabs(BuildTool.ID).tab(tab).button_pressed = true
		assert_eq(panel._stack.current, tab, "%s shows its pane" % tab)
		assert_eq(asked.back(), tab, "and picks it")
	panel._on_rail_item_pressed(WaterTool.ID)
	panel.hub_tabs(WaterTool.ID).tab(&"pond").button_pressed = true
	assert_eq(asked.back(), WaterBrush.Shape.POND, "Pond sets the Water brush's shape")
	assert_eq(panel._stack.current, WaterTool.ID)
	panel.hub_tabs(WaterTool.ID).tab(BridgeTool.ID).button_pressed = true
	assert_eq(asked.back(), BridgeTool.ID, "Crossing is the Bridge tool")
	assert_eq(panel._stack.current, BridgeTool.ID, "with its own tiles")
	panel.hub_tabs(WaterTool.ID).tab(&"river").button_pressed = true
	assert_eq(asked.back(), WaterBrush.Shape.RIVER)
	assert_eq(asked.slice(0, 2), [PlaceTool.ID, ThinTool.ID], "Place first, then its erase mode")


## The leads a pane shows: its header's summary and any "...Hint" caption that is a direct child
## (not the depth line under Water's tiles, which says what the pick means, not what to do).
func _leads(pane: Control) -> Array[String]:
	var leads: Array[String] = []
	for child in pane.get_children():
		if child is MenuHeader and (child as MenuHeader).caption_label.visible:
			leads.append((child as MenuHeader).caption_label.text)
		elif (
			child is Label
			and String(child.name).ends_with("Hint")
			and not String(child.name).ends_with("DepthHint")
			and (child as Label).visible
		):
			leads.append((child as Label).text)
	return leads


func test_every_hub_tab_shows_exactly_one_lead() -> void:
	var panel := _panel()
	panel._on_rail_item_pressed(PlaceTool.ID)
	var shown: Array = [[PlaceTool.ID, PlaceTool.ID]]
	for tab: Array in [
		[PlaceTool.ID, ThinTool.ID],
		[WaterTool.ID, &"river"],
		[WaterTool.ID, &"pond"],
		[WaterTool.ID, BridgeTool.ID],
		[BuildTool.ID, WallTool.ID],
		[BuildTool.ID, StructureTool.ID],
		[BuildTool.ID, VillageTool.ID],
	]:
		shown.append(tab)
	for entry: Array in shown:
		var rail: StringName = entry[0]
		var tab: StringName = entry[1]
		panel._on_rail_item_pressed(rail)
		if tab != PlaceTool.ID:
			panel.hub_tabs(rail).tab(tab).button_pressed = true
		var leads := _leads(panel._stack.get_pane(panel._stack.current))
		assert_eq(leads.size(), 1, "%s / %s shows one lead, not %s" % [rail, tab, leads])
		var pane: Control = panel._stack.get_pane(panel._stack.current)
		var first_label := ""
		var headed := false  # the lead is the header's summary (Buildings, Villages)
		for child in pane.get_children():
			if child is MenuHeader:
				headed = (child as MenuHeader).caption_label.visible
			elif child is Control and (child as Control).visible:
				first_label = "Label" if child is Label else "other"
				break
		if not headed:
			assert_eq(first_label, "Label", "%s / %s: the lead comes first" % [rail, tab])
	# With no water the Crossing tab's lead is the line saying so, above its More and picker.
	panel.bridge_pane.set_has_water(false)
	var bridge: Control = panel._stack.get_pane(BridgeTool.ID)
	var first: Node = null
	for child in bridge.get_children():
		if child is Control and (child as Control).visible and not child is MenuHeader:
			first = child
			break
	assert_eq(String(first.name), "BridgeWaterHint", "the no-water line leads the Crossing tab")
	for tile in panel.bridge_pane.kind_field.tiles.get_children():
		if tile is Button:
			assert_true((tile as Button).disabled, "a crossing tile waits while there is no water")
	panel.bridge_pane.set_has_water(true)
	for tile in panel.bridge_pane.kind_field.tiles.get_children():
		if tile is Button:
			assert_false((tile as Button).disabled, "and is live once there is")


func test_a_hub_reopens_on_the_tab_it_last_showed() -> void:
	var panel := _panel()
	_follow(panel)
	panel._on_rail_item_pressed(BuildTool.ID)
	panel.hub_tabs(BuildTool.ID).tab(VillageTool.ID).button_pressed = true
	panel._rail.select(&"")
	panel._on_rail_item_pressed(BiomeTool.ID)
	assert_false(panel.hub_tabs(BuildTool.ID).visible, "a tool without tabs shows none")
	panel._on_rail_item_pressed(BuildTool.ID)
	assert_eq(panel._stack.current, VillageTool.ID, "back on Villages")
	assert_eq(panel.get_active_tool(), VillageTool.ID)


func test_the_rail_chip_is_the_hubs_while_a_tab_s_tool_is_out() -> void:
	var panel := _panel()
	panel.set_active_tool(BridgeTool.ID)
	assert_true(panel._rail._buttons[WaterTool.ID].active, "Water holds the Bridge tool")
	assert_eq(panel.get_active_tool(), BridgeTool.ID, "the controller still hears the real id")
	panel.set_active_tool(WallTool.ID)
	assert_false(panel._rail._buttons[WaterTool.ID].active, "Water let go")
	assert_true(panel._rail._buttons[BuildTool.ID].active)
	assert_eq(panel.current_tab(BuildTool.ID), WallTool.ID)


func test_a_pane_button_that_asks_for_walls_changes_the_tab_and_never_closes_the_card() -> void:
	var panel := await _open_panel()
	_follow(panel)
	panel._on_rail_item_pressed(BuildTool.ID)
	panel.hub_tabs(BuildTool.ID).tab(VillageTool.ID).button_pressed = true
	assert_eq(panel._rail.selected, BuildTool.ID)
	panel.request_tool(WallTool.ID)
	assert_true(panel.is_open, "the card stays")
	assert_eq(panel._stack.current, WallTool.ID, "and goes to Walls")
	assert_eq(panel.current_tab(BuildTool.ID), WallTool.ID)


func test_a_disabled_tab_says_why_and_a_hub_skips_it() -> void:
	var panel := _panel()
	_follow(panel)
	panel.set_tool_available(BridgeTool.ID, false)
	var tab := panel.hub_tabs(WaterTool.ID).tab(BridgeTool.ID)
	assert_true(tab.disabled)
	assert_eq(tab.tooltip_text, BridgeTool.UNAVAILABLE_TOOLTIP)
	panel.set_tool_available(BridgeTool.ID, true)
	assert_false(tab.disabled)
	panel.set_tool_available(WallTool.ID, false)
	panel._on_rail_item_pressed(BuildTool.ID)
	assert_eq(panel._stack.current, StructureTool.ID, "Build opens on the first tab that works")


# -- Keys ---------------------------------------------------------------------------------


func test_a_key_opens_the_hubs_last_tab_and_pressed_again_steps_through_the_tabs() -> void:
	var panel := _panel()
	_follow(panel)
	panel.pick_rail_tool(BuildTool.ID)
	assert_eq(panel.get_active_tool(), WallTool.ID, "the first press: the last tab (Walls)")
	panel.pick_rail_tool(BuildTool.ID)
	assert_eq(panel.get_active_tool(), StructureTool.ID, "again: Buildings")
	panel.pick_rail_tool(BuildTool.ID)
	assert_eq(panel.get_active_tool(), VillageTool.ID, "again: Villages")
	panel.pick_rail_tool(BuildTool.ID)
	assert_eq(panel.get_active_tool(), WallTool.ID, "and round to Walls")
	panel.pick_rail_tool(WaterTool.ID)
	assert_eq(panel.get_active_tool(), WaterTool.ID, "River")
	assert_eq(panel.current_tab(WaterTool.ID), &"river")
	panel.pick_rail_tool(WaterTool.ID)
	assert_eq(panel.current_tab(WaterTool.ID), &"pond", "again: Pond")
	panel.pick_rail_tool(WaterTool.ID)
	assert_eq(panel.get_active_tool(), BridgeTool.ID, "again: Crossing")
	panel.pick_rail_tool(BuildTool.ID)
	assert_eq(panel.get_active_tool(), WallTool.ID, "another hub opens on its last tab, no step")
	panel.pick_rail_tool(PlaceTool.ID)
	panel.pick_rail_tool(PlaceTool.ID)
	assert_eq(panel.get_active_tool(), ThinTool.ID, "P twice is the erase mode")


func test_a_plain_tool_s_key_shows_its_pane_and_the_controller_hears_it() -> void:
	var panel := _panel()
	var asked: Array[StringName] = []
	panel.tool_selected.connect(func(id: StringName) -> void: asked.append(id))
	panel.pick_rail_tool(SculptTool.ID)
	assert_eq(asked, [SculptTool.ID] as Array[StringName])
	assert_eq(panel._stack.current, SculptTool.ID)
	panel.pick_rail_tool(FireTool.ID)
	assert_eq(asked.back(), FireTool.ID)


func test_the_water_tabs_follow_a_shape_switched_by_tab_on_the_board() -> void:
	var panel := _panel()
	panel.pick_rail_tool(WaterTool.ID)
	panel.select_water_shape(WaterBrush.Shape.POND)
	assert_eq(panel.current_tab(WaterTool.ID), &"pond")
	panel.select_water_shape(WaterBrush.Shape.RIVER)
	assert_eq(panel.current_tab(WaterTool.ID), &"river")


# -- The actions pill ---------------------------------------------------------------------


func test_the_pill_buttons_emit_the_same_signals_and_hold_the_same_states() -> void:
	var panel := _panel()
	var pill := panel.actions()
	watch_signals(panel)
	for pair: Array in [
		[AuthoringChrome.ACTION_UNDO, "undo_pressed"],
		[AuthoringChrome.ACTION_REDO, "redo_pressed"],
		[AuthoringChrome.ACTION_SAVE, "save_pressed"],
		[AuthoringChrome.ACTION_LEAVE, "leave_pressed"],
	]:
		var button := pill.button(pair[0])
		assert_not_null(button, "%s is in the pill" % pair[0])
		button.disabled = false
		button.pressed.emit()
		assert_signal_emitted(panel, pair[1], "%s says %s" % [pair[0], pair[1]])
	assert_true(pill.button(AuthoringChrome.ACTION_UNDO).disabled == false)
	panel.set_history_state(false, false)
	assert_true(pill.button(AuthoringChrome.ACTION_UNDO).disabled, "Undo is off with nothing to undo")
	panel.set_dirty(true)
	assert_true(pill.button(AuthoringChrome.ACTION_SAVE).badge, "the dirty dot")
	assert_eq(
		(pill.button(AuthoringChrome.ACTION_SAVE).get_node("ItemCaption") as Label).text,
		AuthoringChrome.UNSAVED_WORD
	)
	for id: StringName in [AuthoringChrome.ACTION_UNDO, AuthoringChrome.ACTION_SAVE]:
		assert_ne(pill.button(id).focus_mode, Control.FOCUS_NONE, "%s takes focus" % id)


func test_a_digit_picks_no_tool_in_authoring() -> void:
	# Owner, 2026-11-16: "just keep the letters". The digits stay the play state's F3 toggles.
	assert_eq(ToolRegistry.rail_tools(ToolDescriptor.AUTHORING).size(), 7)
	for i in 8:
		for context in [ToolDescriptor.AUTHORING, ToolDescriptor.PLAY]:
			assert_null(ToolRegistry.for_shortcut(_key(KEY_1 + i), context), "digit %d" % (i + 1))


func test_leave_is_set_apart_from_save_by_a_gap() -> void:
	var panel := await _open_panel()
	var pill := panel.actions()
	var save := pill.button(AuthoringChrome.ACTION_SAVE)
	var leave := pill.button(AuthoringChrome.ACTION_LEAVE)
	var step := leave.get_global_rect().position.x - save.get_global_rect().end.x
	assert_gte(step, AuthoringActions.LEAVE_GAP, "a wide step, not a neighbour, before Leave")
	assert_not_null(pill.find_child("Divider*", true, false), "a rule across the step")
	assert_eq(
		(leave.get_node("ItemCaption") as Label).text, AuthoringChrome.LEAVE_WORD, "the word Leave"
	)


## Leave on an Unsaved map asks first (save and leave, discard, or cancel) and stays in the map
## until the author answers; a saved map leaves at once.
func test_leave_on_an_unsaved_map_asks_first() -> void:
	var panel := await _open_panel()
	var ctrl := AuthoringController.new()
	add_child_autofree(ctrl)
	ctrl.panel = panel
	ctrl.saving = autofree(AuthoringSaving.new())
	ctrl._is_open = true
	ctrl.session.mark_edited()
	watch_signals(ctrl)
	ctrl.request_leave()
	assert_not_null(ctrl._leave_prompt, "an unsaved map asks before it leaves")
	assert_signal_not_emitted(ctrl, "exit_requested")
	assert_true(panel._leave_pending, "the panel shows the leave is pending")
	(ctrl._leave_prompt as ConfirmationDialogUI)._on_cancel_pressed()
	await wait_seconds(0.4)
	assert_false(panel._leave_pending, "Cancel keeps the author in the map")
	assert_signal_not_emitted(ctrl, "exit_requested")


# -- Layout -------------------------------------------------------------------------------


func _layout_rects(panel: AuthoringPanel) -> Dictionary:
	return {
		"rail": panel._rail_panel.get_global_rect(),
		"card": panel._panel.get_global_rect(),
		"pill": panel.actions().get_global_rect(),
	}


func _assert_layout(canvas: Vector2) -> void:
	_host.size = canvas
	var panel := await _open_panel()
	panel.show_tool_pane(AuthoringPanel.TOOL_BIOME)
	for i in 4:
		await get_tree().process_frame
	var rects := _layout_rects(panel)
	var rail: Rect2 = rects["rail"]
	var card: Rect2 = rects["card"]
	var pill: Rect2 = rects["pill"]
	assert_almost_eq(card.position.x - rail.end.x, DrawerContainer.FLOAT_GAP, 0.6, "a 12 px gap")
	assert_almost_eq(rail.position.x, DrawerContainer.FLOAT_MARGIN, 0.6, "the rail floats in")
	assert_false(rail.intersects(card), "rail and card do not touch")
	assert_false(pill.intersects(card), "the pill does not overlap the card")
	assert_false(pill.intersects(rail), "or the rail")
	var clear := pill.position.x - card.end.x
	assert_gte(clear, DrawerContainer.FLOAT_GAP - 0.6, "it stands clear of the card")
	assert_lte(card.end.y, canvas.y, "the card is in the window")
	assert_lte(rail.end.y, canvas.y, "and so is the rail")
	assert_gt(pill.end.x, 0.0)
	assert_lt(pill.end.x, canvas.x, "the pill is in the window")


func test_the_rail_card_and_pill_do_not_overlap_at_720p() -> void:
	await _assert_layout(CANVAS_720P)


func test_the_rail_card_and_pill_do_not_overlap_at_1080p() -> void:
	await _assert_layout(CANVAS_1080P)


func test_the_pill_follows_the_card_shut_and_clears_the_roster_drawer_when_both_are_open() -> void:
	_host.size = CANVAS_720P
	var panel := _panel()
	panel.reveal()
	await get_tree().create_timer(UiMotion.FADE_ONLY_S + 0.1).timeout
	var shut_x := panel.actions().position.x
	assert_almost_eq(
		shut_x, DrawerContainer.FLOAT_MARGIN + panel.tab_width + DrawerContainer.FLOAT_GAP, 0.6,
		"with the card shut it stands beside the rail"
	)
	panel.open()
	await get_tree().create_timer(UiMotion.FADE_ONLY_S + 0.1).timeout
	assert_gt(panel.actions().position.x, shut_x + panel.drawer_width - 1.0, "open: beside the card")
	# The token roster is a right-edge drawer: its open span starts well right of the pill.
	var roster_left := CANVAS_720P.x - 304.0 - 36.0
	assert_lt(panel.actions().position.x + panel.actions().size.x, roster_left, "clear of the roster")
	var free := DrawerContainer.free_span(_host.get_viewport())
	var card_end := panel._panel.get_global_rect().end.x
	assert_gte(free.x, card_end, "the board's free span starts past the card")


func test_the_basics_fit_above_the_fold_of_every_pane_at_720p() -> void:
	var panel := await _open_panel()
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		if tool.brush_mode == null:
			continue
		panel.show_tool_pane(tool.id)
		for i in 4:
			await get_tree().process_frame
		var pane := panel._stack.get_pane(tool.id)
		var card := panel._panel.get_global_rect()
		var foot := _basics_bottom(pane)
		assert_lt(
			foot,
			card.end.y - 8.0,
			"%s: its picker and size end at %.0f, the card at %.0f" % [tool.id, foot, card.end.y]
		)


## The global y of the foot of the pane's basics: its size row (when it has one) and the first
## row of its picker, which may be a long catalogue that scrolls (Paint's surfaces, the buildings).
func _basics_bottom(pane: Control) -> float:
	var bottom := 0.0
	for row: Node in pane.find_children("*", "PropertyRow", true, false):
		if row.name.ends_with("BrushSize") or row.name == "WaterWidth":
			bottom = maxf(bottom, (row as Control).get_global_rect().end.y)
	for node: Node in pane.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		if control is TileRow and control.get_child_count() > 0:
			bottom = maxf(bottom, (control.get_child(0) as Control).get_global_rect().end.y)
			break
		if control is Foldout and control.name.begins_with("Place_"):
			bottom = maxf(bottom, control.get_global_rect().end.y)
			break
	return bottom
