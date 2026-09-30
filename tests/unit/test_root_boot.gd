extends GutTest

## Root's boot choice (the graphics warm-up or the title screen) and the startup update
## check, which waits for the title screen.

const RootScript := preload("res://scenes/root.gd")


func test_boot_goes_through_the_warm_up_only_when_needed() -> void:
	assert_eq(RootScript.boot_state(true), RootScript.State.WARMING_UP)
	assert_eq(RootScript.boot_state(false), RootScript.State.TITLE_SCREEN)


func test_warming_up_is_appended_so_existing_state_numbers_hold() -> void:
	assert_eq(RootScript.State.TITLE_SCREEN, 0)
	assert_eq(RootScript.State.PLAYING, 3, "UIManager.ROOT_STATE_PLAYING")
	assert_eq(RootScript.State.PAUSED, 4, "UIManager.ROOT_STATE_PAUSED")
	assert_eq(RootScript.State.AUTHORING, 5)
	assert_eq(RootScript.State.WARMING_UP, 6)


func test_the_startup_update_check_is_taken_once() -> void:
	var root: Node = autofree(RootScript.new())
	root.set("_update_check_on_title", true)
	assert_true(root.call("_take_startup_update_check"), "the first title entry checks")
	assert_false(root.call("_take_startup_update_check"), "later title entries do not")


func test_no_update_check_when_it_was_not_wanted() -> void:
	var root: Node = autofree(RootScript.new())
	root.set("_update_check_on_title", false)
	assert_false(root.call("_take_startup_update_check"), "Steam builds never check")
