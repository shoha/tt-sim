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


func test_labels_mode_wraps_items_in_a_column() -> void:
	var rail := IconRail.new()
	rail.show_labels = true
	add_child_autofree(rail)
	rail.add_item(&"audio", "volume", "Audio")
	assert_true(rail._items[&"audio"] is VBoxContainer)
	assert_eq(rail._items[&"audio"].get_child(1).text, "Audio")
