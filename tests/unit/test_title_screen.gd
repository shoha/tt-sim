extends GutTest

## Title hub: Host and Play Solo follow the selected card, and the signals carry the
## selection. Play Solo is disabled with no levels; Host and Join never need one.

const SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")

var _levels: Array[Dictionary] = []


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
	add_child_autofree(title)
	return title


## Room first: a room needs no map, so Host stays the screen's fill over an empty library and
## says maps are added there; the plaque offers New map, in fewer words than a line.
func test_no_levels_keeps_host_and_offers_a_new_map() -> void:
	_levels = []
	var title := _title()
	watch_signals(title)
	assert_false(title.host_button.disabled, "a room needs no map")
	assert_eq(title.host_button.theme_type_variation, &"Primary")
	assert_eq(title.host_caption.text, TitleScreen.HOST_EMPTY_LINE)
	assert_false(title.host_subtitle.visible, "one line under Host")
	title._on_host_pressed()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [{}])
	assert_true(title.play_button.disabled)
	assert_false(title.join_button.disabled)
	assert_true(title.empty_caption.visible)
	assert_lt(title.empty_caption.text.length(), 60, "a short line")
	assert_false(title.empty_caption.text.contains(TitleScreen.SET_UP_TOKENS))
	assert_true(title.empty_action.visible)
	assert_eq(title.empty_action.text, TitleScreen.EMPTY_ACTION)
	assert_true(title.heading_plaque.is_ancestor_of(title.empty_action))
	title.empty_action.pressed.emit()
	assert_signal_emitted(title, "build_map_requested")
	assert_eq(title.heading_count.text, "0")
	# Set up tokens stays open with nothing selected (a new map, a Blender file), unnamed.
	assert_false(title.editor_button.disabled)
	assert_false(title.editor_subtitle.visible)


func test_most_recent_level_is_preselected_and_named_in_subtitles() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	assert_eq(title.selected_level()["name"], "New Camp")
	# Host opens a room with the map on its shelf; all three name it the same way.
	assert_eq(title.host_subtitle.text, "New Camp goes on the shelf")
	assert_eq(title.play_subtitle.text, "New Camp")
	assert_eq(title.editor_subtitle.text, "New Camp")
	assert_eq(title.heading_count.text, "2")
	assert_false(title.host_button.disabled)


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
	assert_eq(title.host_subtitle.text, "Old Camp goes on the shelf")
	title._on_host_pressed()
	assert_signal_emitted_with_parameters(title, "host_game_requested", [_levels[0]])
	title._on_play_pressed()
	assert_signal_emitted_with_parameters(title, "play_solo_requested", [_levels[0]])
	title._on_join_pressed()
	assert_signal_emitted(title, "join_game_requested")


func test_activating_a_card_plays_solo() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid.level_activated.emit(_levels[0])
	assert_signal_emitted_with_parameters(title, "play_solo_requested", [_levels[0]])


func test_grid_refresh_notifies_actions_when_the_list_changes() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	assert_false(title.host_button.disabled)
	title.grid.provider = func() -> Array: return []
	title.grid.refresh()
	assert_eq(title.heading_count.text, "0")
	assert_true(title.empty_caption.visible)
	assert_true(title.empty_action.visible)
	assert_false(title.host_button.disabled, "a room needs no map")
	assert_eq(title.host_caption.text, TitleScreen.HOST_EMPTY_LINE)
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
