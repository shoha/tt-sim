extends GutTest

## Title hub: Host and Play Solo follow the selected card, are disabled with no
## levels, and the signals carry the selection. Join never needs a level.

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


func test_no_levels_disables_host_and_play_and_explains() -> void:
	_levels = []
	var title := _title()
	assert_true(title.host_button.disabled)
	assert_true(title.play_button.disabled)
	assert_false(title.join_button.disabled)
	assert_true(title.empty_caption.visible)
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


## The d20 turns only over an empty library: behind the cards it showed through the gutters.
func test_the_die_hides_behind_the_cards() -> void:
	_levels = [_info("new", "New Camp", 200)]
	var title := _title()
	var die := title.get_node("SubViewportContainer") as Control
	assert_false(die.visible, "hidden while the grid holds a card")
	title.grid.provider = func() -> Array: return []
	title.grid.refresh()
	assert_true(die.visible, "shown over an empty library")


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
	assert_true(title.host_button.disabled)
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
	var heading: Control = title.get_node("Hub/Columns/RightZone/Heading")
	assert_gt(
		title.grid.position.y,
		heading.position.y + heading.size.y - 1.0,
		"grid must sit below the heading, not on top of it"
	)
