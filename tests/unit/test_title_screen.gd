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
	assert_eq(title.heading_count.text, "0 levels")


func test_most_recent_level_is_preselected_and_named_in_subtitles() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	assert_eq(title.selected_level()["name"], "New Camp")
	assert_eq(title.host_subtitle.text, "with New Camp")
	assert_eq(title.play_subtitle.text, "New Camp")
	assert_eq(title.heading_count.text, "2 levels")
	assert_false(title.host_button.disabled)


func test_selection_changes_subtitles_and_signals_carry_it() -> void:
	_levels = [_info("old", "Old Camp", 100), _info("new", "New Camp", 200)]
	var title := _title()
	watch_signals(title)
	title.grid._cards[0]._on_pressed()
	assert_eq(title.host_subtitle.text, "with Old Camp")
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
	assert_eq(title.heading_count.text, "0 levels")
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
