extends GutTest

## Root's boot (the title first; a first launch's graphics warm-up runs behind it, and the doors
## into a map wait for it) and the startup update check, which waits for the title screen.

const RootScript := preload("res://scenes/root.gd")


func test_only_the_offline_doors_into_a_map_wait_for_the_warm_up() -> void:
	assert_true(RootScript.waits_for_warmup(RootScript.State.PLAYING, false), "solo play")
	assert_true(RootScript.waits_for_warmup(RootScript.State.AUTHORING, false), "map building")
	assert_false(RootScript.waits_for_warmup(RootScript.State.TITLE_SCREEN, false))
	assert_false(RootScript.waits_for_warmup(RootScript.State.PAUSED, false))
	assert_false(
		RootScript.waits_for_warmup(RootScript.State.ROOM, false), "a session waits at the title"
	)
	assert_false(
		RootScript.waits_for_warmup(RootScript.State.PLAYING, true),
		"a session's table never waits on a state change (the network does not wait)"
	)


func test_a_title_action_runs_at_once_without_a_warm_up() -> void:
	var root: Node = autofree(RootScript.new())
	var ran := [0]
	root.call("_when_warm", func() -> void: ran[0] += 1)
	assert_eq(ran[0], 1)


func test_a_title_action_waits_for_the_warm_up_and_the_latest_runs() -> void:
	var root: Node = autofree(RootScript.new())
	root.set("_warmup_pending", true)
	var ran: Array[String] = []
	root.call("_when_warm", func() -> void: ran.append("first"))
	root.call("_when_warm", func() -> void: ran.append("second"))
	assert_eq(ran.size(), 0, "nothing runs while the warm-up is on")
	root.call("_on_warmup_finished")
	assert_eq(ran, ["second"] as Array[String], "the latest action runs once, when it is done")
	assert_false(root.get("_warmup_pending"))
	root.call("_when_warm", func() -> void: ran.append("after"))
	assert_eq(ran, ["second", "after"] as Array[String], "later actions run at once")


func test_state_numbers_hold() -> void:
	assert_eq(RootScript.State.TITLE_SCREEN, 0)
	assert_eq(RootScript.State.ROOM, 1, "the validation bridge's state names")
	assert_eq(RootScript.State.PLAYING, 3, "UIManager.ROOT_STATE_PLAYING")
	assert_eq(RootScript.State.PAUSED, 4, "UIManager.ROOT_STATE_PAUSED")
	assert_eq(RootScript.State.AUTHORING, 5)


func test_the_startup_update_check_is_taken_once() -> void:
	var root: Node = autofree(RootScript.new())
	root.set("_update_check_on_title", true)
	assert_true(root.call("_take_startup_update_check"), "the first title entry checks")
	assert_false(root.call("_take_startup_update_check"), "later title entries do not")


func test_no_update_check_when_it_was_not_wanted() -> void:
	var root: Node = autofree(RootScript.new())
	root.set("_update_check_on_title", false)
	assert_false(root.call("_take_startup_update_check"), "Steam builds never check")
