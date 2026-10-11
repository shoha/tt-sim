extends GutTest

## The title is the library: the wordmark and its tools at the top bar's left, the Play together
## card at its right end; the maps as cards, the most recently played first, after the New map
## card; the selected map in the panel pinned at the grid's right, the same panel for a Bundled
## map, whose Play, Host with this map and Edit map reach Root through the title's signals. Host
## on the card opens a room with nothing on its shelf, over an empty library too, where New map
## is the only card.

const SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")

var _levels: Array[Dictionary] = []
var _plays: Dictionary = {}
var _sessions: Array[Dictionary] = []


func _info(folder: String, name: String, modified: int) -> Dictionary:
	return {
		"path": "user://x/%s/" % folder,
		"folder": folder,
		"is_folder_based": true,
		"name": name,
		"token_count": 3,
		"modified_at": modified,
		"environment_preset": "",
		"thumbnail": "",
		"map_path": "map.glb",
		"map_document": "",
	}


func _title() -> TitleScreen:
	var title: TitleScreen = SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]: return _levels
	title.plays_provider = func() -> Dictionary: return _plays
	title.session_provider = func() -> Array[Dictionary]: return _sessions
	add_child_autofree(title)
	return title


func before_each() -> void:
	_plays = {}


## Two columns from the top: at the left the wordmark with Avatars, Settings and Quit game beside
## it in one row of quiet labelled tools on the sky, then the sticky heading and the grid; at the
## right the Play together card on its paper, then the map panel, one width; Quit well away from
## Host; no plaque under the wordmark or the tools.
func test_two_columns_hold_the_tools_the_grid_the_card_and_the_panel() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	var bar := title.get_node("%TopBar") as HBoxContainer
	var library := title.get_node("%LibraryColumn") as Control
	var side := title.get_node("%SideColumn") as Control
	assert_eq(side.get_child(0), title.play_plaque, "the card at the top of the right column")
	assert_eq(side.get_child(1), title.panel_column, "the panel under it")
	assert_true(title.play_plaque.is_ancestor_of(title.play_together))
	assert_eq(bar.get_child(0), title.masthead)
	assert_true(library.is_ancestor_of(bar) and library.is_ancestor_of(title.grid))
	assert_true(library.is_ancestor_of(title.sticky_heading))
	assert_eq(side.custom_minimum_size.x, MapPanel.WIDTH, "one width")
	for button: Button in [title.avatars_button, title.settings_button, title.quit_button]:
		assert_true(title.masthead.is_ancestor_of(button), "%s by the wordmark" % button.text)
		assert_eq(button.theme_type_variation, &"SkyButton", "%s: a quiet tool" % button.text)
	assert_eq(title.settings_button.get_parent(), title.quit_button.get_parent(), "one row")
	assert_true(title.masthead.is_ancestor_of(title.version_label))
	assert_null(title.get_node_or_null("%LeftColumn"), "the column is gone")
	assert_eq(title.quit_button.text, TitleScreen.QUIT)
	assert_eq(title.quit_button.icon, IconButton.load_icon(TitleScreen.QUIT_ICON))
	await wait_process_frames(3)
	var gap := title.play_together.get_global_rect().position.x
	gap -= title.quit_button.get_global_rect().end.x
	assert_gt(gap, 200.0, "Quit away from Host")


## Room first: Host opens a room over an empty library, where New map is the only card,
## larger, centred, and captioned to make a first map or drop one in; no panel, the grid takes
## the whole width. New map has a map card's anatomy: a solid paper face with one ink glyph,
## its name line, and Generate and Import... in its caption band.
func test_an_empty_library_is_the_new_map_card_alone() -> void:
	_levels = []
	var title := _title()
	watch_signals(title)
	title.play_together.press(PlayTogetherCard.Face.HOST)
	title.play_together._host_flooded()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [{}])
	assert_eq(title.grid.card_count(), 0)
	assert_true(title.new_map_card.is_empty_library())
	assert_eq(title.new_map_card.caption.text, NewMapCard.EMPTY_CAPTION)
	assert_eq(title.new_map_card.custom_minimum_size.x, NewMapCard.EMPTY_WIDTH, "larger")
	assert_false(title.map_panel.is_visible_in_tree(), "no map, no panel")
	assert_false(title.panel_column.visible, "nothing under the card")
	assert_false(title.sticky_heading.is_visible_in_tree(), "no sticky heading over no maps")
	var flow := title.new_map_card.get_parent() as HFlowContainer
	assert_eq(flow.alignment, FlowContainer.ALIGNMENT_CENTER)
	var face := title.new_map_card.picture
	assert_null(face.get_node_or_null("Placeholder"), "a paper face, not a map")
	assert_eq(face.get_child_count(), 1, "one glyph on it")
	assert_eq(title.new_map_card.glyph.texture, IconButton.load_icon(NewMapCard.GLYPH))
	assert_eq(title.new_map_card.heading.theme_type_variation, &"Body", "a card's name line")
	assert_true(title.new_map_card.caption.visible, "the first-map line, alone")
	await wait_process_frames(3)
	var picture := face.size
	assert_almost_eq(picture.x / picture.y, NewMapCard.EMPTY_FACE_ASPECT, 0.02, "a low face")
	assert_eq(title.new_map_card.caption.get_line_count(), 1, "the first-map line on one line")
	title.new_map_card.generate()
	assert_signal_emitted(title, "build_map_requested")


## A first run with only the maps that come with the game: New map alone, larger and centred,
## the Bundled maps offered under it in a heading of their own, and none selected.
func test_a_library_of_bundled_maps_offers_them_under_new_map() -> void:
	var bundled := _info("ship", "Ship", 100)
	bundled.map_path = "res://maps/ship.glb"
	_levels = [bundled]
	var title := _title()
	assert_true(title.new_map_card.is_empty_library(), "no map of the player's own")
	assert_eq(title.grid.card_count(), 1)
	assert_eq(title.grid.own_card_count(), 0)
	var heading := title.grid._bundled_heading
	assert_true(heading.visible)
	assert_eq(title.grid._heading_words.text, LevelGrid.EMPTY_HEADING)
	assert_eq(title.grid._heading_words.theme_type_variation, &"Heading", "words, not a pill")
	assert_null(heading.get_node_or_null("Plaque"), "no plaque under the words")
	assert_eq(title.grid.headings().size(), 1, "no Your maps over an empty library")
	assert_gt(heading.get_index(), title.new_map_card.get_index())
	assert_eq(title.selected_level(), {}, "New map leads; nothing selected")
	assert_false(title.map_panel.is_visible_in_tree())


## The New map card leads the grid under "Your maps" (the sticky heading over the grid's clip);
## the maps follow the most recently played or edited first, and the head of the library is
## selected, shown in the panel under the Play together card (not in the grid, not a modal).
func test_the_library_orders_by_play_and_opens_the_head() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("mid", "Mid Camp", 200)]
	_plays = {"old": 300}
	var title := _title()
	var flow := title.new_map_card.get_parent()
	assert_false(title.grid._own_heading.visible, "Your maps is not in the flow")
	assert_eq(title.sticky_heading.text, LevelGrid.OWN_HEADING, "it stands over the grid")
	assert_true(title.sticky_heading.is_visible_in_tree())
	assert_eq(title.new_map_card.get_index(), 1, "New map first")
	assert_eq(title.grid._cards[0].level_info.name, "Old Camp", "played last, so first")
	assert_eq(title.selected_level()["name"], "Old Camp")
	assert_true(title.map_panel.is_visible_in_tree())
	assert_eq(title.map_panel.name_label.text, "Old Camp")
	assert_eq(title.map_panel.played_label.text.begins_with("Played"), true)
	assert_false(flow.is_ancestor_of(title.map_panel), "not in the grid")
	assert_eq(title.map_panel.get_parent(), title.panel_column)
	assert_eq(title.grid._cards[0]._caption.text.begins_with("Played"), true, "the sort's date")


## The panel's actions reach Root as the strip's did: Play solo with the map, Host with this
## map with it (a room with the map on its shelf), Edit map with it.
func test_the_panel_acts_on_the_selected_map() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid._cards[1]._on_pressed()
	var info := title.selected_level()
	assert_eq(info.name, "Old Camp")
	var panel := title.map_panel
	panel.play_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "play_solo_requested", [panel.info])
	panel.host_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [panel.info])
	panel.edit_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "edit_map_requested", [panel.info])
	var opened: Array[String] = []
	var on_open := func(path: String) -> void: opened.append(path)
	EventBus.open_editor_requested.connect(on_open)
	panel.action_requested.emit(panel.info, MapPanel.ACTION_SET_UP)
	EventBus.open_editor_requested.disconnect(on_open)
	assert_eq(opened, [String(info.path)] as Array[String], "Set up tokens from its menu")


## One place and one shape for a map's details, whatever its source: a Bundled map selected
## shows the same panel in the same place and width, the same fields in the same order as plain
## text (no empty field, no Add details), and none of the actions it cannot take.
func test_a_bundled_map_shows_the_same_panel_with_no_edit_actions() -> void:
	var bundled := _info("ship", "Ship", 100)
	bundled.map_path = "res://maps/ship.glb"
	_levels = [_info("camp", "Camp", 300), bundled]
	var title := _title()
	await wait_seconds(TitleScreen.ENTRANCE_DURATION + 6 * TitleScreen.ENTRANCE_STAGGER + 0.1)
	var panel := title.map_panel
	assert_true(panel.is_editable(), "the player's own map")
	var own := panel.get_global_rect()
	title.grid.card_for(String(bundled.path))._on_pressed()
	await wait_process_frames(4)
	assert_eq(title.selected_level().folder, "ship")
	assert_true(panel.is_visible_in_tree(), "the same panel")
	assert_eq(panel.get_global_rect().position, own.position, "in the same place")
	assert_eq(panel.size.x, own.size.x, "at the same width")
	assert_eq(panel.size.x, MapPanel.WIDTH)
	assert_false(panel.is_editable())
	assert_eq(panel.name_label.text, "Ship")
	assert_eq(panel.name_label.focus_mode, Control.FOCUS_NONE, "plain text")
	assert_false(panel.description_label.visible, "no empty field")
	assert_false(panel.add_details_button.visible, "nothing to add to")
	assert_false(panel.edit_button.visible, "no Edit map")
	assert_false(panel.reload_button.visible, "no Reload from Blender")
	assert_false(panel.menu_items().has(MapPanel.MENU_REPLACE), "no Replace map file...")
	assert_eq(panel.source_label.text, "Bundled")
	assert_true(panel.play_button.visible and panel.host_button.visible)
	assert_eq(panel.more_button.get_parent(), panel.play_button.get_parent(), "... on Play's line")
	assert_false(panel._second_row.visible, "no line of its own for ...")
	var card := title.grid.card_for(String(bundled.path))
	assert_eq(card._caption.text, LibraryFacts.NEVER_PLAYED, "not the day it was edited")
	assert_eq(panel.played_label.text, card._caption.text, "the card and the panel agree")


## The hub stands on the painted backdrop in the selected map's mood, morning with none and
## over an empty library.
func test_the_backdrop_takes_the_selected_maps_mood() -> void:
	var night := _info("night", "Night Camp", 200)
	night["environment_preset"] = "outdoor_night"
	_levels = [_info("old", "Old Camp", 100), night]
	var title := _title()
	assert_eq(title.backdrop.mood(), PaintedBackdrop.Mood.NIGHT, "the preselected newest map")
	assert_eq(title.backdrop.key(), "night", "over its own land, keyed as its card's picture")
	title.grid._cards[1]._on_pressed()
	assert_eq(title.backdrop.mood(), PaintedBackdrop.Mood.MORNING, "a map with no preset")
	assert_eq(title.backdrop.key(), "old")
	title.grid.provider = func() -> Array: return []
	title.grid.refresh()
	assert_eq(title.backdrop.mood(), PaintedBackdrop.Mood.MORNING, "an empty library")
	assert_eq(title.backdrop.get_index(), 0, "behind the hub")


func test_join_in_place_reaches_root() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	var card := title.play_together
	card.open_join()
	card.code_edit.text = "  2kq9xw  "
	card.join_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "join_requested", ["2kq9xw"])
	title.show_join_status(SessionFlow.JOIN_CONNECTING)
	assert_true(card.busy)
	card.close_join()
	assert_signal_emitted(title, "join_cancel_requested", "going back drops the join")
	title.show_join_status(SessionFlow.JOIN_FAILED, SessionFlow.NO_ROOM)
	assert_true(card.joining, "a failure reopens Join with the code to correct")
	assert_eq(card.status_label.text, SessionFlow.NO_ROOM)


## Resume shows only with saved sessions, names the newest by its day and its maps, and asks
## Root to resume the one chosen, the newest or an older one from its menu.
func test_resume_lists_saved_sessions_and_asks_for_one() -> void:
	_levels = [_info("new", "New Camp", 200)]
	_sessions = []
	var bare := _title()
	assert_false(bare.resume_entry.visible, "no saved session, no Resume")
	_sessions = [
		{"id": "s2", "name": "Old Mill", "last_played": 1000, "maps": 3},
		{"id": "s1", "name": "Oak's Lab", "last_played": 500, "maps": 1},
	]
	var title := _title()
	watch_signals(title)
	var entry := title.resume_entry
	assert_true(entry.visible)
	assert_eq(entry.caption.text, "Old Mill and 2 more maps")
	entry.resume_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "resume_requested", ["s2"])
	entry.older_button.get_popup().id_pressed.emit(1)
	assert_signal_emitted_with_parameters(title, "resume_requested", ["s1"])
	_sessions = []


## A double click (the grid's activation) plays solo.
func test_activating_a_card_plays_solo() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid.level_activated.emit(title.grid._cards[0].level_info)
	assert_signal_emitted_with_parameters(
		title, "play_solo_requested", [title.grid._cards[0].level_info]
	)


func test_level_saved_refreshes_the_grid() -> void:
	_levels = [_info("old", "Old Camp", 100)]
	var title := _title()
	assert_eq(title.grid.card_count(), 1)
	_levels.append(_info("new", "New Camp", 200))
	LevelManager.level_saved.emit("user://x/")
	assert_eq(title.grid.card_count(), 2)
	assert_eq(title.selected_level()["name"], "New Camp", "the newest selected")


## The grid sits under the wordmark row once the entrance has run.
func test_grid_lands_below_the_top_bar_after_the_entrance() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	var settle := TitleScreen.ENTRANCE_DURATION + 6 * TitleScreen.ENTRANCE_STAGGER + 0.1
	await wait_seconds(settle)
	var bar := title.get_node("%TopBar") as Control
	assert_gt(title.grid.global_position.y, bar.global_position.y + bar.size.y - 1.0)


## The sticky heading names the section at the grid's top: Your maps, then Bundled with TTSim
## once that heading's words have scrolled up to the clip.
func test_the_sticky_heading_follows_the_scroll() -> void:
	_levels = []
	for i in 9:
		_levels.append(_info("own_%d" % i, "Camp %d" % i, 100 + i))
	for i in 24:
		var bundled := _info("ship_%d" % i, "Ship %d" % i, 10 + i)
		bundled.map_path = "res://maps/ship_%d.glb" % i
		_levels.append(bundled)
	var host := SubViewport.new()
	host.size = Vector2i(1280, 720)
	add_child_autofree(host)
	var title: TitleScreen = SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]: return _levels
	title.session_provider = func() -> Array[Dictionary]: return _sessions
	host.add_child(title)
	await wait_process_frames(4)
	assert_eq(title.sticky_heading.text, LevelGrid.OWN_HEADING)
	var heading := title.grid._bundled_heading
	var words := heading.get_node("Words") as Control
	var past := int(heading.position.y + words.position.y) + 1
	title.grid.scroll_vertical = past
	await wait_process_frames(2)
	assert_eq(title.grid.scroll_vertical, past, "scrolled past the heading")
	assert_eq(title.grid.top_section(), LevelGrid.BUNDLED_HEADING)
	assert_eq(title.sticky_heading.text, LevelGrid.BUNDLED_HEADING)
	title.grid.scroll_vertical = 0
	await wait_process_frames(2)
	assert_eq(title.sticky_heading.text, LevelGrid.OWN_HEADING)
