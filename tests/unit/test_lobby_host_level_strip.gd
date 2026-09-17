extends GutTest

## The host lobby shows the pending level and asks for a change through a
## signal the root answers. NetworkManager.host_game is stubbed by not being
## reachable in headless tests: the lobby's _ready guards on a `start_hosting`
## flag that tests turn off.

const SCENE := preload("res://scenes/states/lobby/lobby_host.tscn")


func _level(name: String, tokens: int) -> LevelData:
	var level := LevelData.new()
	level.level_name = name
	level.level_folder = "camp"
	for i in range(tokens):
		level.token_placements.append(TokenPlacement.new())
	return level


func test_strip_shows_name_and_token_count() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	lobby.set_level(_level("Sandy Clearing", 2))
	assert_eq(lobby.level_name.text, "Sandy Clearing")
	assert_eq(lobby.level_caption.text, "2 tokens")
	lobby.set_level(_level("Solo", 1))
	assert_eq(lobby.level_caption.text, "1 token")


func test_locked_level_path_matches_the_saved_levels_path() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	lobby.set_level(_level("Sandy Clearing", 2))
	assert_eq(lobby.locked_level_path(), LevelManager.folder_path("camp"))


func test_change_relays_the_picked_level() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	watch_signals(lobby)
	var info := {"path": "user://x/a/", "name": "Alpha"}
	lobby._on_level_picked(info)
	assert_signal_emitted_with_parameters(lobby, "level_change_requested", [info])


func test_header_reads_as_a_sentence() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	assert_eq(lobby.header.title_label.text, "Host a game")
	assert_eq(
		lobby.header.caption_label.text, "Share the code, pick a level, start when everyone is in"
	)


func test_start_is_the_only_accent_action() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	assert_eq(lobby.start_button.theme_type_variation, &"")
	assert_eq(lobby.cancel_button.theme_type_variation, &"Secondary")
	assert_eq(lobby.change_level_button.theme_type_variation, &"Secondary")
	assert_eq(lobby.copy_button.theme_type_variation, &"IconButton")
	assert_eq(lobby.invite_button.theme_type_variation, &"IconButton")


func test_footer_puts_the_primary_last_and_hugs_the_right() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	var footer := lobby.start_button.get_parent() as HBoxContainer
	assert_eq(footer.alignment, BoxContainer.ALIGNMENT_END)
	assert_lt(lobby.cancel_button.get_index(), lobby.start_button.get_index())


func test_copying_the_code_leaves_the_button_alone() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	lobby._on_copy_code_pressed()
	assert_eq(lobby.copy_button.theme_type_variation, &"IconButton")
	assert_eq(lobby.copy_button.tooltip_text, "Copy code")
