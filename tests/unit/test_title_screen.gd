extends GutTest

## Title hub: Play Solo follows the selected card and its signal carries the selection; Host on
## the Play together card opens a room with nothing on its shelf, and Join in place and Resume
## reach Root through the title's signals. Play Solo is disabled with no levels; Host and Join
## never need one.

const SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")

var _levels: Array[Dictionary] = []
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
	}


func _title() -> TitleScreen:
	var title: TitleScreen = SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]: return _levels
	title.session_provider = func() -> Array[Dictionary]: return _sessions
	add_child_autofree(title)
	return title


## Room first: a room needs no map, so the card's Host opens one over an empty library; the
## plaque offers New map, in fewer words than a line.
func test_no_levels_keeps_host_and_offers_a_new_map() -> void:
	_levels = []
	var title := _title()
	watch_signals(title)
	var card := title.play_together
	assert_true(title.get_node("%LeftColumn").is_ancestor_of(card), "the card leads the column")
	assert_eq(card.get_index(), 2, "under the wordmark and its gap")
	card.press(PlayTogetherCard.Face.HOST)
	card._host_flooded()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [{}])
	assert_true(title.play_button.disabled)
	assert_true(title.empty_caption.visible)
	assert_lt(title.empty_caption.text.length(), 60, "a short line")
	assert_false(title.empty_caption.text.contains(TitleScreen.SET_UP_TOKENS))
	assert_true(title.empty_action.visible)
	assert_eq(title.empty_action.text, TitleScreen.EMPTY_ACTION)
	assert_true(title.heading_plaque.is_ancestor_of(title.empty_action))
	title.empty_action.pressed.emit()
	assert_signal_emitted(title, "build_map_requested")
	# Said once: "No maps yet" with no count of 0 above it, beside a painted picture (I5).
	assert_false(title.heading_count.visible)
	var picture := title.heading_plaque.find_child("Picture", true, false) as Control
	assert_not_null(picture)
	assert_true(picture.is_visible_in_tree())
	assert_true(picture.get_node("Placeholder").visible, "a painted map to come")
	# Set up tokens stays open with nothing selected: it is how a Blender map comes in, and
	# its line says so.
	assert_false(title.editor_button.disabled)
	assert_true(title.editor_subtitle.visible)
	assert_eq(title.editor_subtitle.text, TitleScreen.SET_UP_TOKENS_EMPTY_LINE)


func test_most_recent_level_is_preselected_and_named_in_subtitles() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	assert_eq(title.selected_level()["name"], "New Camp")
	# Play solo and Set up tokens name the map the same way.
	assert_eq(title.play_subtitle.text, "New Camp")
	assert_eq(title.editor_subtitle.text, "New Camp")
	assert_eq(title.heading_count.text, "2")


## Quit reads as the pause menu's, and Set up tokens has an icon of its own.
func test_quit_and_set_up_tokens_match_the_pause_menu() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	assert_eq(title.quit_button.text, TitleScreen.QUIT)
	assert_eq(title.quit_button.icon, IconButton.load_icon(TitleScreen.QUIT_ICON))
	assert_eq(title.editor_button.icon, IconButton.load_icon(TitleScreen.SET_UP_TOKENS_ICON))
	assert_ne(title.editor_button.icon, IconButton.load_icon("wand"))


## The hub stands on the painted backdrop in the selected map's mood, morning with none and
## over an empty library; the d20 is gone.
func test_the_backdrop_takes_the_selected_maps_mood() -> void:
	var night := _info("night", "Night Camp", 200)
	night["environment_preset"] = "outdoor_night"
	_levels = [_info("old", "Old Camp", 100), night]
	var title := _title()
	assert_eq(title.backdrop.mood(), PaintedBackdrop.Mood.NIGHT, "the preselected newest map")
	assert_eq(title.backdrop.key(), "night", "over its own land, keyed as its card's picture")
	title.grid._cards[0]._on_pressed()
	assert_eq(title.backdrop.mood(), PaintedBackdrop.Mood.MORNING, "a map with no preset")
	assert_eq(title.backdrop.key(), "old")
	title.grid.provider = func() -> Array: return []
	title.grid.refresh()
	assert_eq(title.backdrop.mood(), PaintedBackdrop.Mood.MORNING, "an empty library")
	assert_null(title.get_node_or_null("SubViewportContainer"), "no die")
	assert_eq(title.backdrop.get_index(), 0, "behind the hub")


## The column stands on a paper sheet that ends at its content, the version beside the
## wordmark on it; "Your maps" (and the empty library's caption) on a plaque that ends at its
## words, its top edge in line with the sheet's.
func test_the_words_stand_on_paper() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	# Past the entrance (UiMotion.stagger_in lifts each target 12 px in after two process
	# frames; wait_frames counts physics frames, several of which can pass in one process frame
	# headless): the measures are of the screen at rest.
	await wait_process_frames(4)
	for tween in get_tree().get_processed_tweens():
		tween.custom_step(10.0)
	await wait_process_frames(2)
	var sheet := title.get_node("%ColumnSheet") as PanelContainer
	assert_eq(sheet.theme_type_variation, &"Sheet")
	assert_true(title.get_node("%LeftColumn").is_ancestor_of(title.version_label))
	assert_eq(title.version_label.text, "v" + UpdateVersion.get_current())
	assert_eq(title.heading_plaque.theme_type_variation, &"Plaque")
	assert_true(title.heading_plaque.is_ancestor_of(title.heading_count))
	assert_true(title.heading_plaque.is_ancestor_of(title.empty_caption))
	assert_almost_eq(title.heading_plaque.global_position.y, sheet.global_position.y, 0.5)
	var right := title.get_node("%RightZone") as Control
	assert_lt(title.heading_plaque.size.x, right.size.x * 0.6, "the plaque ends at its words")


## The two map actions name what differs: Set up tokens acts on the selected map, New map
## starts one and says how.
func test_set_up_tokens_and_new_map_name_what_they_act_on() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	assert_eq(title.editor_button.text, "Set up tokens")
	assert_eq(title.build_map_button.text, "New map")
	var caption := UiActions.subtitle_of(title.build_map_button)
	assert_true(caption.visible)
	assert_eq(caption.text, TitleScreen.NEW_MAP_CAPTION)
	var opened: Array[String] = []
	var on_open := func(path: String) -> void: opened.append(path)
	EventBus.open_editor_requested.connect(on_open)
	title._on_editor_pressed()
	EventBus.open_editor_requested.disconnect(on_open)
	assert_eq(opened, [String(_levels[0]["path"])] as Array[String])


func test_selection_changes_subtitles_and_signals_carry_it() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid._cards[0]._on_pressed()
	# Host acts on nothing selected.
	title._on_host_pressed()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [{}])
	title._on_play_pressed()
	assert_signal_emitted_with_parameters(title, "play_solo_requested", [_levels[0]])
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
	assert_eq(entry.caption.text, "Old Mill and 2 more")
	assert_true(entry.older_button.visible, "an older session to choose")
	assert_eq(entry.older_button.get_popup().item_count, 1)
	entry.resume_button.pressed.emit()
	assert_signal_emitted_with_parameters(title, "resume_requested", ["s2"])
	entry.older_button.get_popup().id_pressed.emit(1)
	assert_signal_emitted_with_parameters(title, "resume_requested", ["s1"])
	_sessions = []


func test_activating_a_card_plays_solo() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid.level_activated.emit(_levels[0])
	assert_signal_emitted_with_parameters(title, "play_solo_requested", [_levels[0]])


func test_grid_refresh_notifies_actions_when_the_list_changes() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	title.grid.provider = func() -> Array: return []
	title.grid.refresh()
	assert_false(title.heading_count.visible, "no count of 0")
	assert_true(title.empty_caption.visible)
	assert_true(title.empty_action.visible)
	assert_true(title.play_together.visible, "a room needs no map")
	assert_true(title.play_button.disabled)


func test_level_saved_refreshes_the_grid() -> void:
	_levels = [_info("old", "Old Camp", 100)]
	var title := _title()
	assert_eq(title.grid.card_count(), 1)
	_levels.append(_info("new", "New Camp", 200))
	LevelManager.level_saved.emit("user://x/")
	assert_eq(title.grid.card_count(), 2)


func test_grid_lands_below_the_heading_after_the_entrance() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	var settle := TitleScreen.ENTRANCE_DURATION + 12 * TitleScreen.ENTRANCE_STAGGER + 0.1
	await wait_seconds(settle)
	var heading: Control = title.heading_plaque
	assert_gt(
		title.grid.position.y,
		heading.position.y + heading.size.y - 1.0,
		"grid must sit below the heading, not on top of it"
	)
