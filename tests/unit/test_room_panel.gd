extends GutTest

## The room (RoomPanel, RoomModel, RoomDrawer): the GM's and a player's view of one session
## summary, the shelf's add and select, the one-fill rule (only a live action takes the accent),
## Set out held back with nothing selected, the drawer's Move the table here, the Tab that opens
## the drawer only at a table, and the room laid out on the 1280x720 canvas. Every panel here
## has connect_network false and is fed summaries directly.

const MAP_A := "_room_panel_a"
const MAP_B := "_room_panel_b"
const MAP_C := "_room_panel_c"
const GM := "enet-1"
const WREN := "enet-wren"
const CANVAS := Vector2(1280.0, 720.0)


func _sample(table := "") -> Dictionary:
	return {
		"open": table == "",
		"table": table,
		"shelf": [
			{"folder": MAP_A, "map_path": "", "hashes": {}, "name": "Mossy Hollow"},
			{"folder": MAP_B, "map_path": "", "hashes": {}, "name": "Old Mill"},
			{"folder": MAP_C, "map_path": "", "hashes": {}, "name": "Fen Crossing"},
		],
		"players": {
			GM: {"name": "Marigold", "peer_id": 1},
			"enet-ranger": {"name": "Ranger", "peer_id": 2},
			WREN: {"name": "Wren", "peer_id": 3},
			"enet-starling": {"name": "Starling", "peer_id": 4},
			"enet-gone": {"name": "Gone", "peer_id": 0},
		},
		"holdings":
		{
			GM: [MAP_A, MAP_B, MAP_C],
			"enet-ranger": [MAP_A],
			WREN: [MAP_A, MAP_B],
			"enet-starling": [MAP_A],
		},
	}


func _panel(in_drawer := false) -> RoomPanel:
	var panel := RoomPanel.new()
	panel.connect_network = false
	panel.in_drawer = in_drawer
	add_child_autofree(panel)
	return panel


func _row_names(panel: RoomPanel) -> Array:
	return panel.player_rows.get_children().map(
		func(row: Node) -> String: return (row.find_child("Name", true, false) as Label).text
	)


## Visible, live buttons wearing the accent fill.
func _fills(root: Node) -> Array:
	return root.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool:
			return b.is_visible_in_tree() and not b.disabled and b.theme_type_variation == &"Primary"
	)


func _tab(shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	event.shift_pressed = shift
	return event


func test_the_gm_sees_the_players_here_gm_first_and_the_shelf() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	assert_eq(_row_names(panel), ["Marigold", "Ranger", "Starling", "Wren"], "who left is not here")
	var gm_row := panel.player_rows.get_child(0)
	assert_not_null(gm_row.find_child("GmBadge", true, false), "the GM chip")
	assert_not_null(gm_row.find_child("ChooseAvatar", true, false), "your row: Choose avatar")
	assert_null(panel.player_rows.get_child(1).find_child("ChooseAvatar", true, false))
	assert_eq(panel.shelf_rows.get_child_count(), 3)
	assert_true(panel.add_button.visible, "the GM adds maps")
	assert_eq(panel.leave_button.text, "End session")
	assert_eq(panel.title_label.text, "Your room")
	panel.select(MAP_A)
	assert_true(panel.action_button.visible)
	assert_eq(panel.action_button.text, "Set out this map")


func test_a_player_sees_the_shelf_read_only_and_no_action() -> void:
	var panel := _panel()
	panel.show_session(_sample(), WREN, false)
	assert_eq(panel.title_label.text, "Marigold's room")
	assert_false(panel.add_button.visible)
	assert_eq(panel.leave_button.text, "Leave session")
	assert_false(panel.action_button.visible)
	var wren_row := panel.player_rows.get_child(3)
	assert_not_null(wren_row.find_child("ChooseAvatar", true, false), "your row is Wren's")
	panel.select(MAP_B)
	assert_eq(panel.map_name_label.text, "Old Mill", "a player can look at a shelf map")
	assert_eq(_fills(panel).size(), 0, "and has no action to fill")


## Their own state first, and the count says what it counts.
func test_a_player_reads_their_own_download_state_first() -> void:
	var panel := _panel()
	panel.show_session(_sample(), WREN, false)
	panel.select(MAP_B)
	assert_eq(panel.readiness_label.text, "You and 1 other have it")
	panel.select(MAP_C)
	assert_eq(panel.readiness_label.text, "You get it at the table · 1 of 4 have it")
	panel.select(MAP_A)
	assert_eq(panel.readiness_label.text, "Everyone has it")
	var summary := _sample()
	# No holdings of the GM's: the counts are the players' alone (a GM's holdings that lack a
	# map would say the GM no longer has it).
	summary.holdings = {WREN: [MAP_A, MAP_B, MAP_C], "enet-ranger": [MAP_A, MAP_C]}
	panel.show_session(summary, WREN, false)
	panel.select(MAP_B)
	assert_eq(panel.readiness_label.text, "Only you have it")
	panel.select(MAP_C)
	assert_eq(panel.readiness_label.text, "You and 1 other have it")


## A player never reads the GM's copy: with nothing selected they are told what they can do
## here, and with an empty shelf that the GM is choosing the maps.
func test_a_player_reads_player_copy_with_nothing_selected() -> void:
	var panel := _panel()
	panel.show_session(_sample(), WREN, false)
	assert_eq(panel.map_name_label.text, "Look over the maps on the shelf")
	assert_false(panel.action_button.visible)
	var summary := _sample()
	summary.shelf = []
	panel.show_session(summary, WREN, false)
	assert_eq(panel.map_name_label.text, "The GM is choosing the maps")
	assert_true(panel.preview.get_node("Placeholder").visible, "over the painted placeholder")
	for shelf_size in [0, 3]:
		var copy := RoomModel.empty_stage(false, shelf_size)
		var text := ("%s %s" % [copy.title, copy.caption]).to_lower()
		assert_false(text.contains("set it out") or text.contains("add a map"), "not the GM's")


## The caption line holds the GM chip, You and the download state, in that order in every
## view, so the name has the row's full width.
func test_the_caption_line_is_gm_you_then_the_download_state() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	panel.select(MAP_B)
	var line := panel.player_rows.get_child(0).find_child("CaptionLine", true, false)
	var order := line.get_children().map(func(n: Node) -> String: return str(n.name))
	assert_eq(order, ["GmBadge", "You", "Download"])
	var name_label := panel.player_rows.get_child(0).find_child("Name", true, false) as Label
	assert_eq(name_label.get_parent().name, &"Info", "the name has a line of its own")
	var letter := panel.player_rows.get_child(0).find_child("Letter", true, false) as Label
	assert_eq(letter.theme_type_variation, &"H3", "a portrait initial in Inter semibold (T3)")


func test_header_copy_never_names_a_level_or_a_lobby() -> void:
	for is_gm in [true, false]:
		for shelf_size in [0, 3]:
			var text := RoomModel.header(false, is_gm, "Marigold", shelf_size, "")
			var copy := ("%s %s" % [text.title, text.caption]).to_lower()
			assert_false(copy.contains("level") or copy.contains("lobby") or copy.contains("host a"))
	var drawer := RoomModel.header(true, true, "Marigold", 3, "Old Mill")
	assert_eq(drawer.caption, "On the table: Old Mill")


func test_set_out_appears_only_once_a_shelf_map_is_selected() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	assert_eq(panel.selected_key(), "")
	assert_false(panel.action_button.visible, "no held-back Set out with nothing selected")
	assert_eq(_fills(panel).size(), 0)
	assert_true(panel.preview.visible, "the painted placeholder, never an empty box")
	assert_true(panel.preview.get_node("Placeholder").visible)
	assert_eq(panel.map_name_label.text, "Choose a map from the shelf")
	watch_signals(panel)
	panel._on_action_pressed()
	assert_signal_not_emitted(panel, "set_out_requested")


## An empty shelf: the centre paints a placeholder, says what goes there, and Add a map is the
## screen's one fill (not a quiet button in the side sheet beside a dead Set out).
func test_an_empty_room_offers_add_a_map_as_its_one_fill() -> void:
	var panel := _panel()
	var summary := _sample()
	summary.shelf = []
	panel.show_session(summary, GM, true)
	assert_true(panel.preview.visible)
	assert_eq(panel.map_name_label.text, "Add a map to the shelf")
	assert_eq(panel.action_button.text, "Add a map")
	assert_eq(_fills(panel), [panel.action_button], "Add a map is the one fill")
	assert_false(panel.add_button.visible, "no second Add a map in the side sheet")
	assert_true(panel.action_button.get_meta(&"adds"), "it opens the picker")
	panel.show_session(_sample(), GM, true)
	assert_true(panel.add_button.visible, "with maps on the shelf, Add a map moves to its head")


func test_selecting_a_shelf_map_shows_it_with_the_one_fill_under_it() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	(panel.shelf_rows.get_child(1) as Button).pressed.emit()
	assert_eq(panel.selected_key(), MAP_B)
	assert_true(panel.preview.visible)
	assert_eq(panel.map_name_label.text, "Old Mill")
	assert_eq(panel.readiness_label.text, "2 of 4 have it")
	var states: Array = panel.player_rows.get_children().map(
		func(row: Node) -> String: return (row.find_child("Word", true, false) as Label).text
	)
	var has := RoomRows.HAS_IT
	var gets := RoomRows.GETS_IT
	assert_eq(states, [has, gets, gets, has], "an icon and a word, never colour alone (C7)")
	assert_eq(_fills(panel), [panel.action_button], "exactly one fill, the action")
	assert_true((panel.shelf_rows.get_child(1) as Button).button_pressed, "the row shows selected")
	watch_signals(panel)
	panel.action_button.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "set_out_requested", [MAP_B])


func _words(panel: RoomPanel) -> Array:
	return panel.player_rows.get_children().map(
		func(row: Node) -> String: return (row.find_child("Word", true, false) as Label).text
	)


## Progress is lake and a word, never a bar (C5, C7, W4): Getting it with its percent while a
## map comes, Waiting to get it while it waits its turn, and the player's own first.
func test_a_map_on_its_way_reads_getting_it_with_its_percent() -> void:
	var panel := _panel()
	var summary := _sample()
	summary["progress"] = {WREN: {MAP_C: 40}, "enet-ranger": {MAP_C: 0}}
	panel.show_session(summary, WREN, false)
	panel.select(MAP_C)
	var getting := RoomRows.GETTING_IT % 40
	assert_eq(getting, "Getting it · 40%")
	assert_eq(_words(panel), [RoomRows.HAS_IT, RoomRows.WAITING, RoomRows.GETS_IT, getting])
	assert_eq(panel.readiness_label.text, "You are getting it · 40% · 1 of 4 have it")
	assert_eq(panel.find_children("*", "ProgressBar", true, false), [], "no bars")
	summary.progress = {WREN: {MAP_C: 0}}
	panel.show_session(summary, WREN, false)
	assert_eq(panel.readiness_label.text, "You are waiting to get it · 1 of 4 have it")


## The percent moves in place: the rows are not rebuilt, so a hovered or focused control
## keeps its state, and the lake tint follows the state.
func test_progress_moves_in_place() -> void:
	var panel := _panel()
	var summary := _sample()
	summary["progress"] = {WREN: {MAP_C: 0}}
	panel.show_session(summary, WREN, false)
	panel.select(MAP_C)
	var row := panel.player_rows.get_child(3)
	var icon := row.find_child("Icon", true, false) as TextureRect
	assert_eq(icon.get_meta(&"role"), ThemeColors.TEXT_SOFT, "waiting is not yet state")
	summary.progress = {WREN: {MAP_C: 72}}
	panel.show_progress(summary)
	assert_eq(panel.player_rows.get_child(3), row, "the same row")
	assert_eq((row.find_child("Word", true, false) as Label).text, "Getting it · 72%")
	assert_eq(icon.get_meta(&"role"), ThemeColors.STATE, "lake while it comes")
	assert_eq(panel.readiness_label.text, "You are getting it · 72% · 1 of 4 have it")
	summary.holdings[WREN] = [MAP_A, MAP_B, MAP_C]
	summary.progress = {}
	panel.show_progress(summary)
	assert_eq((row.find_child("Word", true, false) as Label).text, RoomRows.HAS_IT)


func test_download_states_from_holdings_and_progress() -> void:
	var player := {"holds": [MAP_A], "progress": {MAP_B: 12, MAP_C: 0}}
	assert_eq(RoomModel.download_state(player, MAP_A).state, RoomModel.HAS)
	assert_eq(RoomModel.download_state(player, MAP_B), {"state": RoomModel.GETTING, "percent": 12})
	assert_eq(RoomModel.download_state(player, MAP_C).state, RoomModel.WAITING)
	assert_eq(RoomModel.download_state(player, "elsewhere").state, RoomModel.TABLE)
	player.holds = [MAP_A, MAP_B]
	assert_eq(RoomModel.download_state(player, MAP_B).state, RoomModel.HAS, "held wins")


func test_a_map_without_a_thumbnail_paints_its_placeholder() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	panel.select(MAP_A)
	var placeholder := panel.preview.get_node("Placeholder") as MapPlaceholder
	assert_eq(panel.preview.theme_type_variation, &"CardThumb")
	assert_true(placeholder.visible)
	# On a card of its own with its name, a picture on paper rather than a hole in the sky.
	var card := panel.find_child("PreviewCard", true, false) as PanelContainer
	assert_eq(card.theme_type_variation, &"PictureCard")
	assert_true(card.is_ancestor_of(panel.preview))
	assert_true(card.is_ancestor_of(panel.map_name_label))
	var paint := placeholder.material as ShaderMaterial
	assert_eq(paint.get_shader_parameter(&"seed"), MapPlaceholder.seed_of(MAP_A))
	var row := panel.shelf_rows.get_child(0)
	var row_paint := row.find_child("Placeholder", true, false).material as ShaderMaterial
	assert_eq(row_paint.get_shader_parameter(&"seed"), paint.get_shader_parameter(&"seed"))
	assert_null(row.find_child("Letter", true, false), "no initial over a map")
	assert_eq((row as Button).theme_type_variation, &"ListRow", "a plain row, not a tile")


## A shelf row's picture is in its map's light whenever the map is selected: what is known of
## the map now (its preset read after the row was built), the same as the preview's.
func test_a_shelf_row_takes_its_maps_mood_with_the_preview() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	panel._pictures[MAP_C] = {"texture": null, "mood": "outdoor_night"}
	panel.select(MAP_C)
	var preview := panel.preview.get_node("Placeholder") as MapPlaceholder
	assert_eq(preview.mood(), PaintedBackdrop.Mood.NIGHT)
	var row := panel.shelf_rows.get_node("Map_%s" % MAP_C)
	var picture := row.find_child("Placeholder", true, false) as MapPlaceholder
	assert_eq(picture.mood(), PaintedBackdrop.Mood.NIGHT, "the row in the preview's light")


func test_adding_a_map_reports_the_pick_and_the_new_map_can_be_selected() -> void:
	var panel := _panel()
	var summary := _sample()
	summary.shelf = summary.shelf.slice(0, 2)
	panel.show_session(summary, GM, true)
	watch_signals(panel)
	var info := {"path": "user://levels/%s/" % MAP_C, "folder": MAP_C, "name": "Fen Crossing"}
	panel._on_level_picked(info)
	assert_signal_emitted_with_parameters(panel, "map_picked", [info])
	panel.show_session(_sample(), GM, true)
	panel.select(MAP_C)
	assert_eq(panel.shelf_rows.get_child_count(), 3)
	assert_eq(panel.map_name_label.text, "Fen Crossing")
	assert_false(panel.action_button.disabled)


func test_the_selection_survives_a_refresh_while_its_map_is_on_the_shelf() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	panel.select(MAP_C)
	panel.show_session(_sample(), GM, true)
	assert_eq(panel.selected_key(), MAP_C)
	var summary := _sample()
	summary.shelf = summary.shelf.slice(0, 2)
	panel.show_session(summary, GM, true)
	assert_eq(panel.selected_key(), "", "a map gone from the shelf is no longer selected")


## The drawer opens on the table's map with no action, a caption saying what moves the table;
## selecting another map shows the action naming it. The selected row is the selection's only
## picture: there is no second preview in the drawer.
func test_the_drawer_starts_on_the_table_and_moves_it_elsewhere() -> void:
	var panel := _panel(true)
	panel.show_session(_sample(MAP_A), GM, true)
	assert_eq(panel.selected_key(), MAP_A, "the map on the table")
	assert_false(panel.action_button.visible, "the table is already here: nothing to do")
	assert_eq(panel.hint_label.text, "Choose a map on the shelf to move the table there")
	assert_eq(_fills(panel).size(), 0)
	assert_null(panel.preview, "no second picture of the selected map")
	assert_null(panel.find_child("Preview", true, false))
	panel.select(MAP_C)
	assert_eq(panel.action_button.text, "Move the table to Fen Crossing", "named for its map")
	assert_eq(panel.action_button.tooltip_text, panel.action_button.text)
	assert_false(panel.hint_label.visible)
	assert_eq(_fills(panel), [panel.action_button])
	var mill := panel.shelf_rows.get_child(1).find_child("Caption", true, false) as Label
	assert_eq(mill.text, "2 of 4 have it", "the drawer's shelf keeps its readiness")
	watch_signals(panel)
	panel.action_button.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "move_table_requested", [MAP_C])
	panel.show_session(_sample(MAP_A), WREN, false)
	assert_false(panel.action_button.visible, "a player has no action")
	assert_eq(panel.hint_label.text, "The GM moves the table to the next map")


## The drawer's action follows its content: right under the shelf while the column fits (no
## empty glass between the shelf and the action), pinned to the foot over a scrolling column
## when it does not, with the selected row scrolled into view.
func test_the_drawer_action_follows_the_shelf_and_pins_only_on_overflow() -> void:
	for height in [1080, 720]:
		var host := SubViewport.new()
		host.size = Vector2i(RoomPanel.SIDE_WIDTH, height)
		host.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child_autofree(host)
		var panel := RoomPanel.new()
		panel.connect_network = false
		panel.in_drawer = true
		host.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var summary := _sample(MAP_A)
		if height == 720:
			for i in 6:
				var folder := "_room_panel_extra_%d" % i
				summary.shelf.append(
					{"folder": folder, "map_path": "", "hashes": {}, "name": "Extra %d" % i}
				)
				(summary.holdings[GM] as Array).append(folder)
		panel.show_session(summary, GM, true)
		var last := "_room_panel_extra_5" if height == 720 else MAP_C
		panel.select(last)
		await wait_process_frames(4)
		var action := panel.action_button.get_global_rect()
		var shelf := panel.shelf_rows.get_global_rect()
		var foot := panel.leave_button.get_global_rect()
		var view := Rect2(Vector2.ZERO, Vector2(host.size))
		assert_true(view.encloses(action), "%d: the action is on screen" % height)
		if height == 1080:
			assert_eq(panel.column_scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
			assert_lt(action.position.y - shelf.end.y, 40.0, "1080: the action follows the shelf")
			assert_gt(foot.position.y - action.end.y, 200.0, "the rest of the height is below it")
		else:
			assert_eq(panel.column_scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO)
			assert_lt(foot.position.y - action.end.y, 40.0, "720: pinned to the foot")
			var row := panel.shelf_rows.get_child(panel.shelf_rows.get_child_count() - 1) as Control
			var clip := panel.column_scroll.get_global_rect().grow(0.5)
			assert_true(clip.encloses(row.get_global_rect()), "the selected row scrolled into view")


## Player rows and shelf rows share one left edge: a portrait and a map picture line up.
func test_player_and_shelf_rows_share_one_left_edge() -> void:
	for in_drawer in [false, true]:
		var host := SubViewport.new()
		host.size = Vector2i(int(RoomPanel.SIDE_WIDTH), 1000) if in_drawer else Vector2i(1280, 1000)
		host.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child_autofree(host)
		var panel := RoomPanel.new()
		panel.connect_network = false
		panel.in_drawer = in_drawer
		host.add_child(panel)
		if in_drawer:
			panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.show_session(_sample(MAP_A), GM, true)
		await wait_process_frames(3)
		var face := panel.player_rows.get_child(0).find_child("Well", true, false) as Control
		var picture := panel.shelf_rows.get_child(0).find_child("Well", true, false) as Control
		assert_almost_eq(face.global_position.x, picture.global_position.x, 0.5)
		var avatar := panel.player_rows.get_child(0).find_child("ChooseAvatar", true, false)
		assert_eq((avatar as Button).text, "Avatar", "the button says what it opens")


func test_tab_opens_the_drawer_only_at_a_table() -> void:
	assert_true(RoomDrawer.tab_toggles(_tab(), true, true, false), "at a table")
	assert_false(RoomDrawer.tab_toggles(_tab(), false, true, false), "not in the room or paused")
	assert_false(RoomDrawer.tab_toggles(_tab(), true, false, false), "not offline (no tab)")
	assert_false(RoomDrawer.tab_toggles(_tab(), true, true, true), "not under a sheet or a tool")
	assert_false(RoomDrawer.tab_toggles(_tab(true), true, true, false), "Shift+Tab is focus")
	var released := _tab()
	released.pressed = false
	assert_false(RoomDrawer.tab_toggles(released, true, true, false))
	var m_key := InputEventKey.new()
	m_key.keycode = KEY_M
	m_key.pressed = true
	assert_false(RoomDrawer.tab_toggles(m_key, true, true, false))


func test_the_drawer_toggles_on_tab_at_a_table() -> void:
	var drawer := RoomDrawer.new()
	drawer.connect_network = false
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(drawer)
	# Shown in a session, without the reveal slide (open() waits out a running slide).
	drawer.is_revealed = true
	# Nothing over the board: set aside what earlier tests in the run may have left registered.
	var saved_overlays: Array[Control] = UIManager._overlay_stack.duplicate()
	var saved_panels: Array[AnimatedCanvasLayerPanel] = (
		AnimatedCanvasLayerPanel._trap_stack.duplicate()
	)
	UIManager._overlay_stack.clear()
	AnimatedCanvasLayerPanel._trap_stack.clear()
	get_viewport().gui_release_focus()
	assert_false(drawer._board_busy(), "nothing over the board")
	var saved: int = UIManager._current_state
	UIManager._current_state = UIManager.ROOT_STATE_PLAYING
	drawer._input(_tab())
	assert_true(drawer.is_open, "Tab at a table opens it")
	UIManager._current_state = UIManager.ROOT_STATE_PAUSED
	drawer._input(_tab())
	UIManager._current_state = saved
	UIManager._overlay_stack.assign(saved_overlays)
	AnimatedCanvasLayerPanel._trap_stack.assign(saved_panels)
	assert_true(drawer.is_open, "paused, Tab leaves it alone")
	assert_eq(drawer.drawer_width, RoomPanel.SIDE_WIDTH)
	assert_eq(drawer._rail.selected, RoomDrawer.RAIL_ID, "open is the rail's state, as elsewhere")


func test_the_room_fits_the_1280x720_canvas() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(CANVAS)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child_autofree(host)
	var screen := RoomScreen.new()
	screen.connect_network = false
	host.add_child(screen)
	screen.panel.set_code(LobbyCode.encode(109775244321098765))
	screen.panel.show_session(_sample(), GM, true)
	screen.panel.select(MAP_B)
	await wait_process_frames(4)
	var canvas := Rect2(Vector2.ZERO, CANVAS).grow(0.5)
	var outside := PackedStringArray()
	for control: Control in screen.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or _in_scroll(control, screen):
			continue
		var rect := control.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not canvas.encloses(rect):
			outside.append("%s at %s" % [screen.get_path_to(control), rect])
	assert_eq(outside.size(), 0, "the room lies on the canvas: %s" % "; ".join(outside))
	assert_gte(screen.panel.preview.size.x, RoomPanel.PREVIEW_MIN_WIDTH, "a large preview")


## At 1080 a short shelf ends the side sheet at its content, with no empty paper under it.
func test_the_side_sheet_ends_at_its_content() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(1920, 1080)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child_autofree(host)
	var screen := RoomScreen.new()
	screen.connect_network = false
	host.add_child(screen)
	screen.panel.show_session(_sample(), GM, true)
	await wait_process_frames(4)
	var panel := screen.panel
	assert_lt(panel.side.size.y, panel.body.size.y - 100.0, "the sheet ends at its content")
	assert_eq(panel.shelf_scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)


## After Resume the GM's shelf rows say what Resume found (SessionKeeper.notes()) on a line of
## their own, so the caption keeps its words whole: a map whose files changed since, and one
## gone from the library, its picture faded and no caption under the note; a row with a note
## grows by its line; a player's rows say nothing of it.
func test_resumed_shelf_rows_say_changed_or_missing() -> void:
	var notes := {MAP_B: SessionFile.CHANGED, MAP_C: SessionFile.MISSING}
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	panel.show_notes(notes)
	assert_eq(_line_of(panel, MAP_A, "Note"), "")
	assert_eq(_caption_of(panel, MAP_A), "Everyone has it")
	assert_eq(_line_of(panel, MAP_B, "Note"), RoomModel.SINCE_CHANGED)
	assert_eq(_caption_of(panel, MAP_B), "2 of 4 have it")
	assert_eq(_line_of(panel, MAP_C, "Note"), RoomModel.MISSING)
	assert_eq(_caption_of(panel, MAP_C), "", "missing says all there is")
	var row_a := _row(panel, MAP_A)
	var row_b := _row(panel, MAP_B)
	assert_eq(
		row_b.custom_minimum_size.y, row_a.custom_minimum_size.y + RoomRows.NOTE_LINE, "a note line"
	)
	var faded := _row(panel, MAP_C).get_node("Inner/Well/Placeholder") as Control
	assert_almost_eq(faded.modulate.a, RoomRows.MUTED_PICTURE, 0.001, "a missing map's picture faded")
	assert_eq((row_a.get_node("Inner/Well/Placeholder") as Control).modulate.a, 1.0)
	panel.show_changes({MAP_B: true})
	assert_eq(_caption_of(panel, MAP_B), "Changed this session · 2 of 4 have it")
	var player := _panel()
	player.show_session(_sample(), WREN, false)
	player.show_notes(notes)
	assert_eq(_line_of(player, MAP_C, "Note"), "", "the GM's library alone")


## Selected, a map missing from the GM's library has Remove from shelf on a line under its row
## and cannot be set out; the stage says why. Selecting another map takes the line away.
func test_a_missing_map_offers_remove_from_shelf() -> void:
	var panel := _panel()
	panel.show_session(_sample(), GM, true)
	panel.show_notes({MAP_C: SessionFile.MISSING})
	watch_signals(panel)
	panel.select(MAP_C)
	var line := panel.shelf_rows.get_node_or_null("Missing_%s" % MAP_C.validate_node_name())
	assert_not_null(line, "a line under the row")
	assert_eq(line.get_index(), _row(panel, MAP_C).get_index() + 1)
	var remove := line.find_child("RemoveFromShelf", true, false) as Button
	assert_eq(remove.text, RoomRows.REMOVE)
	assert_true(panel.action_button.disabled, "a missing map cannot be set out")
	assert_eq(_fills(panel).size(), 0, "no fill for an action that cannot happen")
	assert_eq(panel.readiness_label.text, RoomModel.MISSING)
	remove.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "remove_requested", [MAP_C])
	panel.select(MAP_A)
	await wait_process_frames(1)
	assert_null(panel.shelf_rows.get_node_or_null("Missing_%s" % MAP_C.validate_node_name()))
	assert_false(panel.action_button.disabled)


## A map gone from the GM's library as every peer's summary carries it after Resume: the host
## does not hold it (SessionChannel.get_holdings()), so nobody does and nobody waits for it.
func _gone_sample() -> Dictionary:
	var summary := _sample()
	for id: String in summary.holdings:
		(summary.holdings[id] as Array).erase(MAP_C)
	summary["progress"] = {WREN: {MAP_B: 40}}
	return summary


func _word_of(panel: RoomPanel, index: int) -> String:
	var box := panel.player_rows.get_child(index).find_child("Download", true, false)
	return (box.get_node("Word") as Label).text


## What each peer's rows say for a map the GM no longer has: the GM's row never says Has it,
## no player waits for it, the GM's own room says Missing from your library without the
## notes (the holdings say it), a player's says the GM no longer has it; neither can set it
## out, and only the GM has the line with its ways on.
func test_a_map_the_gm_no_longer_has_reads_so_on_every_peer() -> void:
	var gm_view := _panel()
	gm_view.show_session(_gone_sample(), GM, true)
	gm_view.select(MAP_C)
	assert_eq(_word_of(gm_view, 0), RoomRows.NO_LONGER, "the GM's own row, not Has it")
	for index in range(1, gm_view.player_rows.get_child_count()):
		assert_eq(_word_of(gm_view, index), RoomRows.CANNOT_GET, "nobody waits for it")
	assert_eq(_line_of(gm_view, MAP_C, "Note"), RoomModel.MISSING)
	assert_eq(_caption_of(gm_view, MAP_C), "")
	assert_eq(gm_view.readiness_label.text, RoomModel.MISSING)
	assert_true(gm_view.action_button.disabled, "Set out stays disabled")
	assert_not_null(gm_view.shelf_rows.get_node_or_null("Missing_%s" % MAP_C.validate_node_name()))
	var player := _panel()
	player.show_session(_gone_sample(), WREN, false)
	player.select(MAP_C)
	var words := {}
	for index in player.player_rows.get_child_count():
		var name_label := player.player_rows.get_child(index).find_child("Name", true, false)
		words[(name_label as Label).text] = _word_of(player, index)
	assert_eq(words["Marigold"], RoomRows.NO_LONGER)
	assert_eq(words["Wren"], RoomRows.CANNOT_GET, "your own row: not waiting")
	assert_false(words.values().has(RoomRows.WAITING) or words.values().has(RoomRows.HAS_IT))
	assert_eq(_caption_of(player, MAP_C), RoomModel.GM_LACKS)
	assert_eq(player.readiness_label.text, RoomModel.GM_LACKS)
	assert_eq(_line_of(player, MAP_C, "Note"), "", "the note is the GM's")
	assert_null(player.shelf_rows.get_node_or_null("Missing_%s" % MAP_C.validate_node_name()))
	var faded := _row(player, MAP_C).get_node("Inner/Well/Placeholder") as Control
	assert_almost_eq(faded.modulate.a, RoomRows.MUTED_PICTURE, 0.001, "faded for a player too")
	player.select(MAP_B)
	assert_eq(_word_of(player, 0), RoomRows.HAS_IT, "a map the GM has reads as before")
	player.show_progress(_gone_sample())
	assert_eq(_caption_of(player, MAP_B), "2 of 4 have it")


func test_the_shelf_caption_leaves_the_resume_note_to_its_line() -> void:
	var changed := SessionFile.CHANGED
	assert_eq(RoomModel.shelf_caption(true, false, "", changed), "On the table")
	assert_eq(RoomModel.shelf_caption(false, false, "", SessionFile.MISSING), "")
	assert_eq(RoomModel.shelf_caption(false, false, "3 of 4 have it"), "3 of 4 have it")
	assert_eq(RoomModel.note_text(changed), RoomModel.SINCE_CHANGED)
	assert_eq(RoomModel.note_text(SessionFile.MISSING), RoomModel.MISSING)
	assert_eq(RoomModel.note_text(&""), "")


## A selected row's words read on the lake fill at 4.5:1 on both leaves: name, note and caption
## take ON_SELECTED (paper, chalk), never the soft text role (chalk_soft is 3.7:1 on lake).
func test_selected_row_words_keep_contrast_on_lake() -> void:
	for path: String in [ThemeColors.PAPER_THEME_PATH, ThemeColors.GLASS_THEME_PATH]:
		var theme := load(path) as Theme
		var holder := Control.new()
		holder.theme = theme
		add_child_autofree(holder)
		var entry := {"key": MAP_B, "name": "Old Mill", "folder": MAP_B}
		var note := RoomModel.SINCE_CHANGED
		var row := RoomRows.shelf_row(entry, null, "", "3 of 4 have it", true, note)
		holder.add_child(row)
		RoomRows.show_shelf_selected(row, true)
		var fill := theme.get_color(ThemeColors.SELECTED, ThemeColors.TYPE)
		for line: String in ["Name", "Note", "Caption"]:
			var label := row.get_node("Inner/Text/" + line) as Label
			var ratio := _contrast(label.get_theme_color(&"font_color"), fill)
			assert_gt(ratio, 4.5, "%s on the selected fill, %s: %.2f" % [line, path, ratio])


func _row(panel: RoomPanel, key: String) -> Control:
	return panel.shelf_rows.get_node("Map_%s" % key.validate_node_name()) as Control


func _caption_of(panel: RoomPanel, key: String) -> String:
	return _line_of(panel, key, "Caption")


func _line_of(panel: RoomPanel, key: String, line: String) -> String:
	var label := _row(panel, key).get_node("Inner/Text/" + line) as Label
	return label.text if label.visible else ""


## WCAG 2.x contrast ratio of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


## Inside a scroll region (what it holds may run past it; the player scrolls to it).
func _in_scroll(control: Control, stop: Node) -> bool:
	var node := control.get_parent()
	while node != null and node != stop:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false
