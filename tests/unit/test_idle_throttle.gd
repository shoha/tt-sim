extends GutTest

## IdleThrottle (utils/idle_throttle.gd, perf audit sysidle S4): the cap policy, the settings key,
## the focus notifications, and the two things it must never undo: a load behind the sheet
## (LoadPacing) and the player's own frame cap.

var _saved_fps := 0
var _saved_enabled := true


func before_each() -> void:
	_saved_fps = Engine.max_fps
	_saved_enabled = IdleThrottle.enabled
	Engine.max_fps = 0
	IdleThrottle.enabled = true
	IdleThrottle.focused = true
	IdleThrottle.minimized = false


func after_each() -> void:
	IdleThrottle.focus_source = Callable()
	IdleThrottle.busy = false
	IdleThrottle.focused = true
	IdleThrottle.minimized = false
	IdleThrottle.release()
	IdleThrottle.enabled = _saved_enabled
	Engine.max_fps = _saved_fps


func test_the_policy_caps_only_a_window_in_the_background() -> void:
	assert_eq(IdleThrottle.cap_for(true, true, false, false), 0, "focused: no cap")
	assert_eq(IdleThrottle.cap_for(true, false, false, false), IdleThrottle.UNFOCUSED_FPS)
	assert_eq(IdleThrottle.cap_for(true, false, true, false), IdleThrottle.MINIMIZED_FPS)
	assert_eq(IdleThrottle.cap_for(false, false, true, false), 0, "switched off: no cap")
	assert_eq(
		IdleThrottle.cap_for(true, true, true, false),
		IdleThrottle.MINIMIZED_FPS,
		"minimised without a focus change (a script minimise) still gets the minimised cap"
	)
	assert_eq(IdleThrottle.UNFOCUSED_FPS, 15)
	assert_eq(IdleThrottle.MINIMIZED_FPS, 5)


## A first launch's warm-up behind the title holds the throttle off while it runs.
func test_busy_work_holds_the_cap_off_and_it_returns_after() -> void:
	IdleThrottle.focused = false
	IdleThrottle.set_busy(true)
	assert_eq(Engine.max_fps, 0, "no cap while busy, unfocused or not")
	IdleThrottle.set_busy(false)
	assert_eq(Engine.max_fps, IdleThrottle.UNFOCUSED_FPS, "the cap returns when the work is done")


func test_a_host_with_peers_keeps_a_floor() -> void:
	assert_eq(IdleThrottle.cap_for(true, false, false, true), IdleThrottle.HOSTING_FPS)
	assert_eq(IdleThrottle.cap_for(true, false, true, true), IdleThrottle.HOSTING_FPS)
	assert_eq(IdleThrottle.cap_for(true, true, false, true), 0, "focused host: no cap")
	assert_gte(IdleThrottle.HOSTING_FPS, 30, "60 Hz physics needs 2 steps a frame at most")


func test_the_setting_defaults_on_and_ignores_a_stale_value() -> void:
	var config := ConfigFile.new()
	assert_true(IdleThrottle.DEFAULT)
	assert_true(IdleThrottle.stored(config))
	config.set_value("graphics", IdleThrottle.KEY, false)
	assert_false(IdleThrottle.stored(config))
	config.set_value("graphics", IdleThrottle.KEY, "off")
	assert_true(IdleThrottle.stored(config), "a non-bool value falls back to the default")


func test_focus_out_caps_and_focus_in_restores_the_cap_that_stood() -> void:
	Engine.max_fps = 0
	var node := IdleThrottle.new()
	add_child_autofree(node)
	IdleThrottle.focused = true
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var expected := IdleThrottle.UNFOCUSED_FPS
	assert_eq(Engine.max_fps, expected)
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(Engine.max_fps, 0, "the uncapped state stood before")
	Engine.max_fps = 144
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(Engine.max_fps, expected)
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(Engine.max_fps, 144, "the player's own cap is put back")


## The launch case (card arrivalchop): Root installs the throttle before the window's activation is
## handled, so the install reads no focus, and the activation sends no application focus-in. The
## next frame's read of the window lifts the cap; losing the window's focus later caps again.
func test_a_window_focused_after_the_install_is_uncapped_without_a_notification() -> void:
	var window_focused := [false]
	IdleThrottle.focus_source = func() -> bool: return window_focused[0]
	var node := IdleThrottle.new()
	add_child_autofree(node)
	assert_false(IdleThrottle.focused, "the install read the window before its activation")
	assert_eq(Engine.max_fps, IdleThrottle.UNFOCUSED_FPS)
	window_focused[0] = true
	node._process(0.016)
	assert_true(IdleThrottle.focused, "the window's own focus is read every frame")
	assert_eq(Engine.max_fps, 0, "a focused window runs uncapped")
	node.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(Engine.max_fps, 0, "the window's own state wins over a notification it contradicts")
	window_focused[0] = false
	node.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_eq(Engine.max_fps, IdleThrottle.UNFOCUSED_FPS, "a window that loses the focus is capped")


func test_a_lower_player_cap_stands_in_the_background() -> void:
	Engine.max_fps = 10
	IdleThrottle.focused = false
	IdleThrottle.reapply()
	assert_eq(Engine.max_fps, 10, "the throttle never raises a cap")
	IdleThrottle.focused = true
	IdleThrottle.reapply()
	assert_eq(Engine.max_fps, 10)


func test_minimised_takes_the_lower_cap_and_switching_off_releases() -> void:
	IdleThrottle.focused = false
	IdleThrottle.minimized = true
	IdleThrottle.reapply()
	assert_eq(Engine.max_fps, IdleThrottle.MINIMIZED_FPS)
	IdleThrottle.set_enabled(false)
	assert_eq(Engine.max_fps, 0, "off puts the cap back at once")
	IdleThrottle.set_enabled(true)
	assert_eq(Engine.max_fps, IdleThrottle.MINIMIZED_FPS, "and on applies it at once")


func test_a_load_sheet_runs_at_its_own_cap_and_the_throttle_returns_after_it() -> void:
	var owner := Node.new()
	add_child_autofree(owner)
	IdleThrottle.focused = false
	IdleThrottle.reapply()
	assert_eq(Engine.max_fps, IdleThrottle.UNFOCUSED_FPS)
	LoadPacing.cover(owner)
	assert_eq(Engine.max_fps, LoadPacing.COVERED_MAX_FPS, "a load in the background is not slowed")
	IdleThrottle.reapply()
	assert_eq(Engine.max_fps, LoadPacing.COVERED_MAX_FPS, "and a refresh leaves the sheet's cap")
	LoadPacing.uncover(owner)
	assert_eq(Engine.max_fps, IdleThrottle.UNFOCUSED_FPS, "the throttle holds again")
	IdleThrottle.focused = true
	IdleThrottle.reapply()
	assert_eq(Engine.max_fps, 0, "and focus puts the exact earlier cap back")


func test_focus_during_a_load_leaves_the_player_cap_exact_after_it() -> void:
	var owner := Node.new()
	add_child_autofree(owner)
	Engine.max_fps = 144
	IdleThrottle.focused = false
	IdleThrottle.reapply()
	LoadPacing.cover(owner)
	assert_eq(Engine.max_fps, 144, "the sheet saw the player's cap, not the throttled one")
	IdleThrottle.focused = true
	IdleThrottle.reapply()
	LoadPacing.uncover(owner)
	assert_eq(Engine.max_fps, 144)


func test_no_node_is_installed_in_a_headless_run() -> void:
	assert_false(IdleThrottle.runs_here(), "headless and scripted runs are left alone")
	assert_null(IdleThrottle.install(self))
