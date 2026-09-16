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


func test_change_relays_the_picked_level() -> void:
	var lobby = SCENE.instantiate()
	lobby.start_hosting = false
	add_child_autofree(lobby)
	watch_signals(lobby)
	var info := {"path": "user://x/a/", "name": "Alpha"}
	lobby._on_level_picked(info)
	assert_signal_emitted_with_parameters(lobby, "level_change_requested", [info])
