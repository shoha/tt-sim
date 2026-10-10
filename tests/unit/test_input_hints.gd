extends GutTest

## The input hint bar stays anchored to the bottom edge (its slide is a draw
## offset, never a position change), and hint changes are diffed by key: kept
## chips stay the same nodes, new ones fade in, dropped ones fade out and go.

const HINTS_SCENE := preload("res://scenes/ui/input_hints.tscn")
## Longer than every fade and the bar's slide (0.25 s).
const SETTLE_S := 0.4

var _hints: InputHints


func before_each() -> void:
	_hints = HINTS_SCENE.instantiate()
	add_child_autofree(_hints)


func _bar() -> MarginContainer:
	return _hints._bar


func _row_keys() -> Array:
	var keys := []
	for chip in _hints.hints_container.get_children():
		keys.append(String(chip.name).trim_prefix("Hint_"))
	return keys


func _show_grid_and_measure() -> void:
	_hints.set_hints([{"key": "G", "action": "Grid"}, {"key": "M", "action": "Measure"}])
	await wait_seconds(SETTLE_S)


## Tweening position.y on the bottom-anchored bar rewrote its offsets against
## the top anchor and left it at the top of the screen.
func test_bar_slides_in_without_leaving_the_bottom_edge() -> void:
	assert_eq(_bar().modulate.a, 0.0, "starts hidden")
	await _show_grid_and_measure()
	assert_eq(_bar().anchor_top, 1.0)
	assert_eq(_bar().anchor_bottom, 1.0)
	assert_eq(_bar().offset_top, -52.0)
	assert_eq(_bar().offset_bottom, 0.0)
	assert_eq(_bar().offset_transform_position, Vector2.ZERO)
	assert_almost_eq(_bar().modulate.a, 1.0, 0.001)


func test_chips_use_the_key_chip_style() -> void:
	await _show_grid_and_measure()
	var chip: Control = _hints.chip_for("G")
	assert_eq(chip.get_child(0).theme_type_variation, &"KeyChip")
	assert_eq(_hints._action_label(chip).text, "Grid")


func test_adding_a_hint_keeps_the_other_chips_and_fades_in_only_the_new_one() -> void:
	await _show_grid_and_measure()
	var grid_chip := _hints.chip_for("G")
	var measure_chip := _hints.chip_for("M")
	_hints.add_hint("Shift", "Free Move")
	assert_same(_hints.chip_for("G"), grid_chip)
	assert_same(_hints.chip_for("M"), measure_chip)
	assert_eq(grid_chip.modulate.a, 1.0, "kept chips do not animate")
	assert_eq(_hints.chip_for("Shift").modulate.a, 0.0, "the new chip fades in")
	assert_eq(_bar().offset_transform_position, Vector2.ZERO, "the bar does not re-slide")
	assert_eq(_row_keys(), ["G", "M", "Shift"])
	await wait_seconds(SETTLE_S)
	assert_almost_eq(_hints.chip_for("Shift").modulate.a, 1.0, 0.001)


func test_removing_a_hint_fades_out_only_that_chip() -> void:
	await _show_grid_and_measure()
	_hints.add_hint("Shift", "Free Move")
	await wait_seconds(SETTLE_S)
	var grid_chip := _hints.chip_for("G")
	_hints.remove_hint("Shift")
	assert_true(_hints._leaving.has("Shift"), "the dropped chip fades out in place")
	assert_eq(_row_keys().size(), 3)
	await wait_seconds(SETTLE_S)
	assert_eq(_row_keys(), ["G", "M"])
	assert_null(_hints.chip_for("Shift"))
	assert_same(_hints.chip_for("G"), grid_chip)
	assert_eq(grid_chip.modulate.a, 1.0)
	assert_almost_eq(_bar().modulate.a, 1.0, 0.001, "the bar stays up")


func test_a_key_readded_while_fading_out_takes_its_chip_back() -> void:
	await _show_grid_and_measure()
	var measure_chip := _hints.chip_for("M")
	_hints.remove_hint("M")
	_hints.add_hint("M", "Measure")
	assert_same(_hints.chip_for("M"), measure_chip)
	assert_false(_hints._leaving.has("M"))
	await wait_seconds(SETTLE_S)
	assert_eq(_row_keys(), ["G", "M"])
	assert_almost_eq(measure_chip.modulate.a, 1.0, 0.001)


func test_relabel_updates_the_chip_in_place() -> void:
	await _show_grid_and_measure()
	var grid_chip := _hints.chip_for("G")
	_hints.add_hint("G", "Hide grid")
	assert_same(_hints.chip_for("G"), grid_chip)
	assert_eq(_hints._action_label(grid_chip).text, "Hide grid")


func test_set_hints_keeps_chips_and_follows_the_new_order() -> void:
	await _show_grid_and_measure()
	var grid_chip := _hints.chip_for("G")
	var measure_chip := _hints.chip_for("M")
	_hints.set_hints(
		[
			{"key": "Scroll", "action": "Height"},
			{"key": "G", "action": "Grid"},
			{"key": "M", "action": "Measure"},
		]
	)
	assert_eq(_row_keys(), ["Scroll", "G", "M"])
	assert_same(_hints.chip_for("G"), grid_chip)
	assert_same(_hints.chip_for("M"), measure_chip)


func test_clear_slides_the_bar_out_and_frees_the_chips() -> void:
	await _show_grid_and_measure()
	_hints.clear_hints()
	await wait_seconds(SETTLE_S)
	assert_almost_eq(_bar().modulate.a, 0.0, 0.001)
	assert_eq(_bar().offset_transform_position.y, InputHints.SLIDE_DISTANCE)
	assert_eq(_bar().offset_top, -52.0, "still anchored at the bottom")
	assert_eq(_hints.hints_container.get_child_count(), 0)


## A tool's keys lead while it is active and the camera keys step out (Help stays); when the
## tool ends the base hints come back in their own order, not with Measure and Grid last.
func test_a_tool_layer_leads_and_the_base_row_returns_in_order() -> void:
	var base := [
		{"key": "Esc", "action": "Pause"},
		{"key": "WASD", "action": "Pan"},
		{"key": "M", "action": "Measure"},
		{"key": "G", "action": "Grid"},
		{"key": "F1", "action": "Help"},
	]
	_hints.set_hints(base)
	await wait_seconds(SETTLE_S)
	_hints.set_tool_hints([{"key": "LMB", "action": "Place point"}, {"key": "M", "action": "Done"}])
	await wait_seconds(SETTLE_S)
	assert_eq(_row_keys(), ["LMB", "M", "F1"])
	assert_eq(_hints._action_label(_hints.chip_for("M")).text, "Done")
	_hints.clear_tool_hints()
	await wait_seconds(SETTLE_S)
	assert_eq(_row_keys(), ["Esc", "WASD", "M", "G", "F1"])
	assert_eq(_hints._action_label(_hints.chip_for("M")).text, "Measure")


## A row that must wrap is held to the narrowest width that keeps its line count, so its
## lines come out even and the last chip (Help) is never left alone on a line.
func test_a_wrapped_row_balances_its_lines() -> void:
	var widths: Array[float] = [100.0, 100.0, 100.0, 100.0, 100.0, 60.0]
	# One line is 560 + 5 * 10 = 610; in 600 the greedy wrap leaves the 60 alone.
	assert_eq(InputHints.wrapped_lines(widths, 10.0, 600.0), 2)
	var width := InputHints.balanced_width(widths, 10.0, 600.0)
	assert_eq(InputHints.wrapped_lines(widths, 10.0, width), 2)
	assert_true(width <= 331.0, "three chips a line, not five and one: %.0f" % width)
	assert_eq(InputHints.balanced_width(widths, 10.0, 700.0), 610.0, "one line fits")
	assert_eq(InputHints.balanced_width([] as Array[float], 10.0, 600.0), 0.0)


func test_hints_set_while_hidden_arrive_with_the_bar() -> void:
	_hints.set_hints([{"key": "G", "action": "Grid"}])
	assert_eq(_hints.chip_for("G").modulate.a, 1.0, "the bar's entrance carries the chip")
	assert_true(_hints._bar_shown)
