extends GutTest

## CurveEditor, the designer's response-curve widget: pointer events become point lists (the
## rules are ResponseCurve's, tested apart): press and drag moves a point with snapping and one
## final emit on release, a double-click on empty plot adds a point on the curve, a right-click or
## Delete removes one, and a disabled editor takes nothing.

var _editor: CurveEditor = null
var _emitted: Array[Dictionary] = []


func before_each() -> void:
	_editor = CurveEditor.new()
	_editor.size = Vector2(320.0, 180.0)
	add_child_autofree(_editor)
	_emitted.clear()
	_editor.curve_changed.connect(
		func(points: Array, final: bool) -> void:
			_emitted.append({"points": points, "final": final})
	)


func _press(at: Vector2, button: int = MOUSE_BUTTON_LEFT, double: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = at
	event.double_click = double
	_editor._gui_input(event)


func _release(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	_editor._gui_input(event)


func _move(at: Vector2, shift: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.shift_pressed = shift
	_editor._gui_input(event)


func _pixel(x: float, y: float) -> Vector2:
	return _editor.to_plot(Vector2(x, y))


func test_the_plot_maps_both_ways() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [90.0, 1.0]])
	var at := _pixel(45.0, 0.5)
	var back := _editor.from_plot(at)
	assert_almost_eq(back.x, 45.0, 0.001)
	assert_almost_eq(back.y, 0.5, 0.001)
	var rect := _editor.plot_rect()
	assert_almost_eq(_pixel(0.0, 0.0).x, rect.position.x, 0.001)
	assert_almost_eq(_pixel(90.0, 1.0).y, rect.position.y, 0.001)


func test_dragging_a_point_moves_it_snapped_and_ends_with_one_final_emit() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [45.0, 1.0], [90.0, 0.0]])
	_press(_pixel(45.0, 1.0))
	assert_eq(_editor.selected, 1)
	_move(_pixel(52.3, 0.62))
	_move(_pixel(60.4, 0.58))
	assert_true(_editor.is_dragging())
	assert_eq(_emitted.size(), 2)
	assert_false(_emitted[0]["final"])
	assert_eq(_editor.points[1], [60.0, 0.6], "snapped to 1 degree and 0.05")
	_release(_pixel(60.4, 0.58))
	assert_false(_editor.is_dragging())
	assert_eq(_emitted.size(), 3)
	assert_true(_emitted[2]["final"])
	assert_eq(_emitted[2]["points"][1], [60.0, 0.6])


func test_a_press_without_a_move_changes_nothing() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [90.0, 1.0]])
	_press(_pixel(0.0, 0.0))
	_release(_pixel(0.0, 0.0))
	assert_true(_emitted.is_empty())
	assert_eq(_editor.selected, 0)


func test_shift_moves_a_point_freely() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [45.0, 1.0], [90.0, 0.0]])
	_press(_pixel(45.0, 1.0))
	_move(_pixel(52.3, 0.62), true)
	assert_almost_eq(float(_editor.points[1][0]), 52.3, 0.2)
	assert_almost_eq(float(_editor.points[1][1]), 0.62, 0.02)


func test_a_double_click_on_empty_plot_adds_a_point_on_the_curve() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [90.0, 1.0]])
	_press(_pixel(30.0, 0.9), MOUSE_BUTTON_LEFT, true)
	assert_eq(_editor.points.size(), 3)
	assert_true(_emitted[_emitted.size() - 1]["final"])
	assert_eq(_editor.points[1][0], 30.0)
	_press(_pixel(30.0, 0.9), MOUSE_BUTTON_LEFT, true)
	assert_eq(_editor.points.size(), 3, "a double-click on a point adds nothing")


func test_a_rule_without_a_curve_makes_one_on_the_first_edit() -> void:
	_editor.set_curve("wet", [])
	assert_true(_editor.points.is_empty())
	_press(_pixel(0.5, 0.3), MOUSE_BUTTON_LEFT, true)
	assert_eq(_editor.points.size(), 3, "the flat curve plus the new point")
	assert_eq(_emitted.size(), 1)


func test_a_right_click_removes_a_point_and_two_are_kept() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [45.0, 1.0], [90.0, 0.0]])
	_press(_pixel(45.0, 1.0), MOUSE_BUTTON_RIGHT)
	assert_eq(_editor.points.size(), 2)
	assert_true(_emitted[0]["final"])
	_press(_pixel(0.0, 0.0), MOUSE_BUTTON_RIGHT)
	assert_eq(_editor.points.size(), 2, "never fewer than two")


func test_delete_removes_the_selected_point() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [45.0, 1.0], [90.0, 0.0]])
	_press(_pixel(45.0, 1.0))
	_release(_pixel(45.0, 1.0))
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	_editor._gui_input(key)
	assert_eq(_editor.points.size(), 2)
	assert_eq(_editor.selected, -1)


func test_a_disabled_editor_ignores_the_pointer() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [45.0, 1.0], [90.0, 0.0]])
	_editor.disabled = true
	_press(_pixel(45.0, 1.0))
	_move(_pixel(60.0, 0.5))
	assert_true(_emitted.is_empty())
	assert_eq(_editor.points[1], [45.0, 1.0])


func test_point_at_finds_the_nearest_point_within_reach() -> void:
	_editor.set_curve("slope", [[0.0, 0.0], [45.0, 1.0], [90.0, 0.0]])
	assert_eq(_editor.point_at(_pixel(45.0, 1.0) + Vector2(5.0, 3.0)), 1)
	assert_eq(_editor.point_at(_pixel(20.0, 0.5)), -1)


func test_the_height_axis_widens_for_points_outside_the_usual_span() -> void:
	_editor.set_curve("height", [[-6.0, 0.0], [30.0, 1.0]])
	var left := _pixel(-6.0, 0.0)
	var right := _pixel(30.0, 1.0)
	var rect := _editor.plot_rect()
	assert_almost_eq(left.x, rect.position.x, 0.5)
	assert_almost_eq(right.x, rect.end.x, 0.5)
