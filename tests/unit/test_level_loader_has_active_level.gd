extends GutTest

## Regression test for a real crash: opening the Level Editor from the title screen
## (before any game/level session exists) called has_active_level() on a
## LevelPlayLoader whose setup(level_play_controller) had never run --
## _level_play_controller was still null, and the old implementation dereferenced it
## unconditionally ("Invalid access to property or key 'active_level_data' on a base
## object of type 'Nil'"). app_menu_controller.gd hands its LevelPlayController
## reference to the app menu at Root startup (_setup_app_menu()), well before Root
## ever enters State.PLAYING (the point where LevelPlayController.setup(game_map) --
## and therefore LevelPlayLoader.setup() -- actually runs), so this is a real,
## reachable state, not just a hypothetical one.


func test_has_active_level_is_false_before_setup_is_called() -> void:
	var loader := LevelPlayLoader.new()

	# Must not crash, and must correctly report "no active level" -- setup() was
	# never called, so there is no LevelPlayController to have one.
	assert_false(loader.has_active_level())
