extends GutTest

## The title is the library: the Play together card at the top bar's right end with Avatars,
## Settings and Quit beside it; the maps as cards, the most recently played first, after the
## New map card; the selected map's detail strip under its row, whose Play, Host with this map
## and Edit map reach Root through the title's signals. Host on the card opens a room with
## nothing on its shelf, over an empty library too, where New map is the only card.

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


## The top bar: the wordmark at the left, and at the right end Avatars, Settings, Quit and the
## Play together card on one plaque (the card moved out of the old column); no left column.
func test_the_top_bar_holds_the_card_and_the_tools() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	var bar := title.get_node("%TopBar") as HBoxContainer
	assert_eq(bar.get_child(bar.get_child_count() - 1), title.tools_plaque, "at the right end")
	assert_true(title.tools_plaque.is_ancestor_of(title.play_together))
	assert_true(title.tools_plaque.is_ancestor_of(title.quit_button))
	assert_true(title.tools_plaque.is_ancestor_of(title.settings_button))
	assert_eq(bar.get_child(0), title.wordmark_plaque)
	assert_true(title.wordmark_plaque.is_ancestor_of(title.version_label))
	assert_null(title.get_node_or_null("%LeftColumn"), "the column is gone")
	assert_eq(title.quit_button.text, TitleScreen.QUIT)
	assert_eq(title.quit_button.icon, IconButton.load_icon(TitleScreen.QUIT_ICON))


## Room first: Host opens a room over an empty library, where New map is the only card,
## larger, centred, and captioned to make a first map or drop one in; no strip.
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
	assert_false(title.strip.is_visible_in_tree(), "no map, no strip")
	var flow := title.new_map_card.get_parent() as HFlowContainer
	assert_eq(flow.alignment, FlowContainer.ALIGNMENT_CENTER)
	var sketch := title.new_map_card.picture
	assert_null(sketch.get_node_or_null("Placeholder"), "a sketch on blank paper, not a map")
	assert_eq(title.new_map_card.heading.theme_type_variation, &"H2", "the heading's face")
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
	assert_eq(title.grid._heading_words.theme_type_variation, &"H2", "a heading, not a pill")
	assert_gt(heading.get_index(), title.new_map_card.get_index())
	assert_eq(title.selected_level(), {}, "New map leads; nothing selected")
	assert_false(title.strip.is_visible_in_tree())


## The New map card leads the grid; the maps follow the most recently played or edited first,
## and the head of the library is selected with its strip open directly under its row.
func test_the_library_orders_by_play_and_opens_the_head() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("mid", "Mid Camp", 200)]
	_plays = {"old": 300}
	var title := _title()
	var flow := title.new_map_card.get_parent()
	assert_eq(title.new_map_card.get_index(), 0, "New map first")
	assert_eq(title.grid._cards[0].level_info.name, "Old Camp", "played last, so first")
	assert_eq(title.selected_level()["name"], "Old Camp")
	assert_true(title.strip.is_visible_in_tree())
	assert_eq(title.strip.name_edit.text, "Old Camp")
	assert_eq(title.strip.played_label.text.begins_with("Played"), true)
	var line := title.strip.get_parent()
	assert_eq(line.get_parent(), flow, "on a line of the grid, not a modal")
	assert_gt(line.get_index(), title.grid._cards[0].get_index())
	assert_eq(title.grid._cards[0]._caption.text.begins_with("Played"), true, "the sort's date")


## The strip's actions reach Root as the column's did: Play solo with the map, Host with this
## map with it (a room with the map on its shelf), Edit map with it.
func test_the_strip_acts_on_the_selected_map() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid._cards[1]._on_pressed()
	var info := title.selected_level()
	assert_eq(info.name, "Old Camp")
	title.strip.play_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "play_solo_requested", [title.strip.info])
	title.strip.host_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [title.strip.info])
	title.strip.edit_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "edit_map_requested", [title.strip.info])
	var opened: Array[String] = []
	var on_open := func(path: String) -> void: opened.append(path)
	EventBus.open_editor_requested.connect(on_open)
	title.strip.action_requested.emit(title.strip.info, MapDetailStrip.ACTION_SET_UP)
	EventBus.open_editor_requested.disconnect(on_open)
	assert_eq(opened, [String(info.path)] as Array[String], "Set up tokens from its menu")


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


## The grid sits under the top bar once the entrance has run.
func test_grid_lands_below_the_top_bar_after_the_entrance() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	var settle := TitleScreen.ENTRANCE_DURATION + 6 * TitleScreen.ENTRANCE_STAGGER + 0.1
	await wait_seconds(settle)
	var bar := title.get_node("%TopBar") as Control
	assert_gt(title.grid.global_position.y, bar.global_position.y + bar.size.y - 1.0)
