extends GutTest

## IconRail keeps exactly one item active, reports clicks separately from
## selection changes, and forwards badge/enabled/visible to its buttons.


func _rail() -> IconRail:
	var rail := IconRail.new()
	rail.vertical = true
	add_child_autofree(rail)
	rail.add_item(&"sun", "sun", "Sun")
	rail.add_item(&"sky", "haze", "Sky")
	return rail


func test_select_marks_only_that_item_active() -> void:
	var rail := _rail()
	rail.select(&"sun")
	assert_true(rail._buttons[&"sun"].active)
	assert_false(rail._buttons[&"sky"].active)
	rail.select(&"sky")
	assert_false(rail._buttons[&"sun"].active)
	assert_true(rail._buttons[&"sky"].active)
	assert_eq(rail.selected, &"sky")


func test_selection_changed_emits_once_per_change() -> void:
	var rail := _rail()
	watch_signals(rail)
	rail.select(&"sun")
	rail.select(&"sun")
	assert_signal_emit_count(rail, "selection_changed", 1)


func test_click_emits_item_pressed_and_auto_selects() -> void:
	var rail := _rail()
	watch_signals(rail)
	rail._on_item_pressed(&"sky")
	assert_signal_emitted_with_parameters(rail, "item_pressed", [&"sky"])
	assert_eq(rail.selected, &"sky")


func test_click_on_active_item_reports_press_only() -> void:
	var rail := _rail()
	rail.select(&"sun")
	watch_signals(rail)
	rail._on_item_pressed(&"sun")
	assert_signal_emitted(rail, "item_pressed")
	assert_signal_not_emitted(rail, "selection_changed")


func test_auto_select_off_leaves_selection_to_host() -> void:
	var rail := _rail()
	rail.auto_select = false
	rail._on_item_pressed(&"sky")
	assert_eq(rail.selected, &"")


func test_deselect_clears_active() -> void:
	var rail := _rail()
	rail.select(&"sun")
	rail.deselect()
	assert_eq(rail.selected, &"")
	assert_false(rail._buttons[&"sun"].active)


func test_badge_enabled_visible_reach_the_item() -> void:
	var rail := _rail()
	rail.set_badge(&"sun", true)
	assert_true(rail._buttons[&"sun"].badge)
	rail.set_enabled(&"sky", false)
	assert_true(rail._buttons[&"sky"].disabled)
	rail.set_item_visible(&"sky", false)
	assert_false(rail._items[&"sky"].visible)
	assert_true(rail.has_item(&"sun"))
	assert_false(rail.has_item(&"nope"))


func _horizontal_rail() -> IconRail:
	var rail := IconRail.new()
	rail.show_labels = true
	add_child_autofree(rail)
	rail.add_item(&"audio", "volume", "Audio")
	rail.add_item(&"graphics", "photo", "Graphics")
	rail.add_item(&"grid", "grid-dots", "Grid")
	return rail


func _item_centre_x(rail: IconRail, id: StringName) -> float:
	var item: Control = rail._items[id]
	return item.position.x + item.size.x / 2.0


## A rail resizes before it sorts its children, so a selection made before the
## first layout (the Settings menu selects in _ready) read every item at x = 0
## and left the underline at x = 18 under no item. It must land after the sort.
func test_indicator_lands_on_the_selected_item_after_the_first_sort() -> void:
	var rail := _horizontal_rail()
	rail.select(&"grid")
	await wait_process_frames(2)
	assert_gt(rail._items[&"grid"].position.x, 0.0, "items are laid out")
	assert_almost_eq(rail._indicator_pos, _item_centre_x(rail, &"grid"), 0.5)


func test_indicator_follows_its_item_when_the_rail_resorts() -> void:
	var rail := _horizontal_rail()
	rail.select(&"grid")
	await wait_process_frames(2)
	var before := rail._indicator_pos
	rail.set_item_visible(&"audio", false)
	await wait_process_frames(2)
	assert_lt(rail._indicator_pos, before, "the item moved left, and the indicator with it")
	assert_almost_eq(rail._indicator_pos, _item_centre_x(rail, &"grid"), 0.5)


func test_selection_change_slides_to_the_new_item() -> void:
	var rail := _horizontal_rail()
	rail.select(&"audio")
	await wait_process_frames(2)
	rail.select(&"graphics")
	assert_true(rail._indicator_tween != null and rail._indicator_tween.is_running())
	await wait_seconds(Constants.ANIM_PANE_SWAP + 0.1)
	assert_almost_eq(rail._indicator_pos, _item_centre_x(rail, &"graphics"), 0.5)


func test_labels_mode_wraps_items_in_a_column() -> void:
	var rail := IconRail.new()
	rail.show_labels = true
	add_child_autofree(rail)
	rail.add_item(&"audio", "volume", "Audio")
	assert_true(rail._items[&"audio"] is VBoxContainer)
	assert_eq(rail._items[&"audio"].get_child(1).text, "Audio")
