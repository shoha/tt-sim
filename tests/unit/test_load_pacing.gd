extends GutTest

## LoadPacing (perfaudit F-system-3): a map load's sheet covering the screen raises the loaders'
## per-frame budgets and turns vsync off; covers are counted by owner, so the last one out puts
## the budgets (and the vsync mode) back, an uncover twice is harmless, and the harness switch
## turns the whole policy off.

var _a: RefCounted
var _b: RefCounted


func before_each() -> void:
	LoadPacing.enabled = true
	_a = RefCounted.new()
	_b = RefCounted.new()


func after_each() -> void:
	LoadPacing.uncover(_a)
	LoadPacing.uncover(_b)
	LoadPacing.enabled = true


func test_uncovered_budget_is_the_callers_own() -> void:
	assert_false(LoadPacing.is_covered())
	assert_eq(LoadPacing.budget_usec(4000), 4000)
	assert_eq(LoadPacing.budget_usec(8000), 8000)


func test_covered_budget_rises_but_never_falls() -> void:
	LoadPacing.cover(_a)
	assert_true(LoadPacing.is_covered())
	assert_eq(LoadPacing.budget_usec(4000), LoadPacing.COVERED_BUDGET_USEC)
	assert_eq(LoadPacing.budget_usec(50000), 50000, "a larger own budget stands")


func test_last_owner_out_uncovers() -> void:
	LoadPacing.cover(_a)
	LoadPacing.cover(_b)
	LoadPacing.uncover(_a)
	assert_true(LoadPacing.is_covered(), "the second cover still holds")
	LoadPacing.uncover(_a)
	assert_true(LoadPacing.is_covered(), "a second uncover by the same owner changes nothing")
	LoadPacing.uncover(_b)
	assert_false(LoadPacing.is_covered())
	assert_eq(LoadPacing.budget_usec(4000), 4000)


func test_vsync_mode_and_frame_cap_are_put_back() -> void:
	var before := DisplayServer.window_get_vsync_mode()
	var fps_before := Engine.max_fps
	Engine.max_fps = 0
	LoadPacing.cover(_a)
	assert_eq(Engine.max_fps, LoadPacing.COVERED_MAX_FPS, "an uncapped frame rate is capped")
	LoadPacing.uncover(_a)
	assert_eq(DisplayServer.window_get_vsync_mode(), before)
	assert_eq(Engine.max_fps, 0)
	Engine.max_fps = 30
	LoadPacing.cover(_a)
	assert_eq(Engine.max_fps, 30, "a lower player cap stands")
	LoadPacing.uncover(_a)
	Engine.max_fps = fps_before


func test_switched_off_ignores_covers() -> void:
	LoadPacing.enabled = false
	LoadPacing.cover(_a)
	assert_false(LoadPacing.is_covered())
	assert_eq(LoadPacing.budget_usec(4000), 4000)


func test_overlay_covers_for_a_map_load_only() -> void:
	var overlay := (load("res://scenes/ui/loading_overlay.tscn") as PackedScene).instantiate()
	add_child_autofree(overlay)
	overlay.show_indeterminate("Opening a room...")
	assert_false(LoadPacing.is_covered(), "a wait over a live screen is paced as usual")
	overlay.show_loading()
	assert_true(LoadPacing.is_covered())
	overlay.hide_loading()
	assert_false(LoadPacing.is_covered(), "the reveal is paced by the display again")
	overlay.show_loading()
	remove_child(overlay)
	assert_false(LoadPacing.is_covered(), "an overlay leaving the tree uncovers")
	add_child(overlay)
