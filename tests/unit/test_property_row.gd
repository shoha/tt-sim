extends GutTest

## PropertyRow: slider and value chip stay in sync, programmatic sets are
## silent, the chip rejects garbage and clamps unless allowed, the override
## tint and right-click reset work, and ticks map values to fractions.


func _row() -> PropertyRow:
	var row := PropertyRow.new()
	row.label = "Exposure"
	row.min_value = 0.1
	row.max_value = 4.0
	row.step = 0.01
	row.value = 1.0
	add_child_autofree(row)
	return row


func test_set_value_no_signal_updates_both_controls_silently() -> void:
	var row := _row()
	watch_signals(row)
	row.set_value_no_signal(2.5)
	assert_eq(row.value, 2.5)
	assert_eq(row._slider.value, 2.5)
	assert_eq(row._chip.text, "2.50")
	assert_signal_not_emitted(row, "value_changed")


func test_slider_drag_emits_and_updates_chip() -> void:
	var row := _row()
	watch_signals(row)
	row._slider.value = 3.0
	assert_signal_emitted_with_parameters(row, "value_changed", [3.0])
	assert_eq(row._chip.text, "3.00")


func test_chip_commit_parses_and_emits() -> void:
	var row := _row()
	watch_signals(row)
	row._chip.text = "1.75"
	row._commit_chip()
	assert_eq(row.value, 1.75)
	assert_signal_emitted_with_parameters(row, "value_changed", [1.75])


func test_chip_rejects_non_numeric_and_reverts() -> void:
	var row := _row()
	watch_signals(row)
	row._chip.text = "abc"
	row._commit_chip()
	assert_eq(row.value, 1.0)
	assert_eq(row._chip.text, "1.00")
	assert_signal_not_emitted(row, "value_changed")


func test_chip_clamps_unless_allow_greater() -> void:
	var row := _row()
	row._chip.text = "9"
	row._commit_chip()
	assert_eq(row.value, 4.0)
	row.allow_greater = true
	row._chip.text = "9"
	row._commit_chip()
	assert_eq(row.value, 9.0)
	assert_eq(row._slider.value, 4.0, "slider clamps to its range")


func test_decimals_follow_step() -> void:
	var row := _row()
	row.step = 1.0
	row.set_value_no_signal(2.0)
	assert_eq(row._chip.text, "2")
	row.step = 0.0001
	row.set_value_no_signal(0.0035)
	assert_eq(row._chip.text, "0.0035")


func test_overridden_tints_label_and_right_click_resets() -> void:
	var row := _row()
	watch_signals(row)
	row.overridden = true
	assert_eq(row._label.theme_type_variation, &"BodyState")
	var state := ThemeColors.of(row._label, ThemeColors.STATE)
	assert_eq(row._label.get_theme_color("font_color"), state, "a changed value reads as state")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	row._on_label_gui_input(click)
	assert_signal_emitted(row, "reset_requested")
	row.overridden = false
	assert_false(row._label.has_theme_color_override("font_color"))


func test_check_and_color_slots() -> void:
	var row := PropertyRow.new()
	row.label = "Fog"
	row.show_check = true
	row.show_color = true
	add_child_autofree(row)
	watch_signals(row)
	row.set_checked_no_signal(true)
	assert_true(row.checked)
	row.set_color_no_signal(Color.RED)
	assert_eq(row.color, Color.RED)
	assert_signal_not_emitted(row, "toggled")
	assert_signal_not_emitted(row, "color_changed")
	row._check.button_pressed = false
	assert_signal_emitted_with_parameters(row, "toggled", [false])


func _stacked(label: String, opts: Dictionary = {}) -> PropertyRow:
	var row := PropertyRow.new()
	row.label = label
	row.stacked = true
	row.show_check = opts.get("check", false)
	row.show_color = opts.get("color", false)
	row.hint_low = "Thin"
	row.hint_high = "Thick"
	return row


## The toggle variant (Fog, Glow): stacked, the check ends the label's line where other rows
## show their value, and the slider starts and ends where a plain stacked row's does. A colour
## swatch goes there too.
func test_a_stacked_check_ends_the_label_line_and_leaves_the_slider_full_width() -> void:
	var box := VBoxContainer.new()
	box.size = Vector2(300, 400)
	add_child_autofree(box)
	var plain := _stacked("Ambient")
	var toggled := _stacked("Fog", {"check": true})
	var swatch := _stacked("Ambient", {"color": true})
	for row in [plain, toggled, swatch]:
		box.add_child(row)
	await wait_process_frames(2)
	assert_eq(toggled._check.get_parent(), toggled._head, "the check is on the label's line")
	assert_eq(toggled._check.get_index(), toggled._head.get_child_count() - 1, "at its end")
	assert_eq(swatch._picker.get_parent(), swatch._head, "the swatch is on the label's line")
	for row: PropertyRow in [toggled, swatch]:
		var slider := row._slider.get_global_rect()
		var reference := plain._slider.get_global_rect()
		assert_almost_eq(slider.position.x, reference.position.x, 0.5, "%s starts" % row.label)
		assert_almost_eq(slider.end.x, reference.end.x, 0.5, "%s ends" % row.label)
	watch_signals(toggled)
	toggled._check.button_pressed = true
	assert_signal_emitted_with_parameters(toggled, "toggled", [true])


## Beside its label (a sheet row), the check still sits before the slider.
func test_an_unstacked_check_sits_before_the_slider() -> void:
	var row := PropertyRow.new()
	row.label = "Fog"
	row.show_check = true
	add_child_autofree(row)
	assert_eq(row._check.get_parent(), row._row)
	assert_lt(row._check.get_index(), row._slider.get_index())


## Stacked rows read apart: the space from one row's hint line to the next row's label is one
## spacing step (8 px) more than the space inside a row, from its slider to its hint line.
func test_stacked_rows_keep_a_step_more_between_them_than_inside() -> void:
	var box := VBoxContainer.new()
	box.size = Vector2(300, 400)
	box.add_theme_constant_override("separation", LevelEditPane.ROW_SEPARATION)
	add_child_autofree(box)
	var first := _stacked("Energy")
	var second := _stacked("Softness")
	box.add_child(first)
	box.add_child(second)
	await wait_process_frames(2)
	var inside := first._ticks.get_global_rect().position.y - first._slider.get_global_rect().end.y
	var between := second._label.get_global_rect().position.y - first._ticks.get_global_rect().end.y
	assert_eq(PropertyRow.STACKED_ROW_GAP, 8.0)
	assert_gte(between - inside, PropertyRow.STACKED_ROW_GAP, "a step more between rows")
	var unstacked := _row()
	assert_null(unstacked.get_node_or_null("Gap"), "a sheet row keeps its own pitch")


func test_checked_property_setter_is_silent() -> void:
	var row := PropertyRow.new()
	row.label = "Fog"
	row.show_check = true
	add_child_autofree(row)
	watch_signals(row)
	row.checked = true
	assert_true(row.checked)
	assert_signal_not_emitted(row, "toggled")


func test_ticks_map_values_to_fractions() -> void:
	var row := PropertyRow.new()
	row.label = "Time of day"
	row.min_value = 0.0
	row.max_value = 24.0
	row.step = 0.5
	row.ticks = [{"value": 6.0, "icon": "sunrise"}, {"value": 18.0, "icon": "sunset"}]
	add_child_autofree(row)
	assert_true(row._ticks.visible)
	assert_almost_eq(row._tick_fraction(6.0), 0.25, 0.001)
	assert_almost_eq(row._tick_fraction(18.0), 0.75, 0.001)


func test_custom_control_replaces_slider() -> void:
	var row := PropertyRow.new()
	row.label = "Tonemap"
	row.show_slider = false
	add_child_autofree(row)
	var dropdown := OptionButton.new()
	row.set_control(dropdown)
	assert_eq(dropdown.get_parent(), row._row)
	assert_false(row._slider.visible)
	assert_false(row._chip.visible)


func test_chip_hidden_by_default_and_shown_by_values_visible() -> void:
	var row := _row()
	assert_false(row._chip.visible, "numbers hide until the drawer toggle")
	row.values_visible = true
	assert_true(row._chip.visible)
	row.values_visible = false
	assert_false(row._chip.visible)


func test_values_visible_never_shows_a_chip_on_a_sliderless_row() -> void:
	var row := PropertyRow.new()
	row.label = "Sky"
	row.show_slider = false
	add_child_autofree(row)
	row.values_visible = true
	assert_false(row._chip.visible)


func test_hints_show_the_strip_only_when_set() -> void:
	var row := _row()
	assert_false(row._ticks.visible)
	row.hint_low = "Dim"
	row.hint_high = "Blazing"
	assert_true(row._ticks.visible)
	row.hint_low = ""
	row.hint_high = ""
	assert_false(row._ticks.visible)


func test_formatter_drives_chip_text_and_tooltip() -> void:
	var row := _row()
	row.formatter = func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	row.set_value_no_signal(0.5)
	assert_eq(row._chip.text, "50%")
	assert_eq(row._slider.tooltip_text, "50%")


func test_chip_typing_still_parses_native_units_with_a_formatter() -> void:
	var row := _row()
	row.values_visible = true
	row.formatter = func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	watch_signals(row)
	row._chip.text = "0.75"
	row._commit_chip()
	assert_eq(row.value, 0.75)
	assert_eq(row._chip.text, "75%")
	assert_signal_emitted_with_parameters(row, "value_changed", [0.75])


func test_formatter_widens_the_chip() -> void:
	var row := _row()
	assert_eq(row._chip.custom_minimum_size.x, PropertyRow.CHIP_WIDTH)
	row.formatter = func(v: float) -> String: return "%.2f m" % v
	assert_eq(row._chip.custom_minimum_size.x, PropertyRow.CHIP_WIDTH_FORMATTED)
	row.formatter = Callable()
	assert_eq(row._chip.custom_minimum_size.x, PropertyRow.CHIP_WIDTH)
