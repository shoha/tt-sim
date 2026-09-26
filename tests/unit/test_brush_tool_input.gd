extends GutTest

## BrushTool.decide() (scenes/states/authoring/brush_tool.gd): which input the brush takes,
## and what it means. Plain wheel stays the camera's; Shift+wheel sizes the brush (or scales
## a hovered prop); RMB cancels a stroke, removes a hovered prop, or puts the brush down.

const BIOME := BrushTool.Mode.BIOME
const PLACE := BrushTool.Mode.PLACE
const A := BrushTool.Action


func _button(index: MouseButton, pressed: bool, shift: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.shift_pressed = shift
	return event


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func test_plain_wheel_is_left_to_the_camera() -> void:
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_WHEEL_UP, true), BIOME, false, false), A.NONE)
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_WHEEL_DOWN, true), BIOME, true, false), A.NONE)


func test_shift_wheel_sizes_the_brush() -> void:
	var up := _button(MOUSE_BUTTON_WHEEL_UP, true, true)
	var down := _button(MOUSE_BUTTON_WHEEL_DOWN, true, true)
	assert_eq(BrushTool.decide(up, BIOME, false, false), A.GROW)
	assert_eq(BrushTool.decide(down, BrushTool.Mode.THIN, true, false), A.SHRINK)
	assert_eq(
		BrushTool.decide(_button(MOUSE_BUTTON_WHEEL_UP, false, true), BIOME, false, false), A.NONE
	)


func test_shift_wheel_in_place_scales_only_a_hovered_prop() -> void:
	var up := _button(MOUSE_BUTTON_WHEEL_UP, true, true)
	assert_eq(BrushTool.decide(up, PLACE, false, true), A.GROW)
	assert_eq(BrushTool.decide(up, PLACE, false, false), A.NONE, "else the camera zooms")


func test_brackets_size_the_brush() -> void:
	assert_eq(BrushTool.decide(_key(KEY_BRACKETRIGHT), BIOME, false, false), A.GROW)
	assert_eq(BrushTool.decide(_key(KEY_BRACKETLEFT), BIOME, false, false), A.SHRINK)


func test_rmb_cancels_a_stroke_or_puts_the_brush_down() -> void:
	var rmb := _button(MOUSE_BUTTON_RIGHT, true)
	assert_eq(BrushTool.decide(rmb, BIOME, true, false), A.CANCEL)
	assert_eq(BrushTool.decide(rmb, BIOME, false, false), A.DESELECT)
	assert_eq(BrushTool.decide(rmb, PLACE, false, true), A.REMOVE)
	assert_eq(BrushTool.decide(rmb, PLACE, true, true), A.CANCEL, "a placement in progress")
	var release := _button(MOUSE_BUTTON_RIGHT, false)
	assert_eq(BrushTool.decide(release, BIOME, false, false), A.SWALLOW, "no context menu")


func test_lmb_begins_and_ends() -> void:
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_LEFT, true), BIOME, false, false), A.BEGIN)
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_LEFT, false), BIOME, true, false), A.END)
	assert_eq(
		BrushTool.decide(_button(MOUSE_BUTTON_LEFT, false), BIOME, false, false),
		A.NONE,
		"a release the brush did not start is not its own"
	)


func test_delete_removes_a_hovered_prop_in_place_only() -> void:
	assert_eq(BrushTool.decide(_key(KEY_DELETE), PLACE, false, true), A.REMOVE)
	assert_eq(BrushTool.decide(_key(KEY_DELETE), PLACE, false, false), A.NONE)
	assert_eq(BrushTool.decide(_key(KEY_DELETE), BIOME, false, true), A.NONE)


func test_motion_is_a_pointer_update_never_consumed() -> void:
	var motion := InputEventMouseMotion.new()
	assert_eq(BrushTool.decide(motion, BIOME, true, false), A.POINTER)


func test_other_buttons_are_not_the_brush_s() -> void:
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_MIDDLE, true), BIOME, false, false), A.NONE)


func test_dwell_builds_strength_up_to_a_cap() -> void:
	assert_almost_eq(BrushTool.dwell_gain(0.0), 1.0, 1e-6)
	assert_gt(BrushTool.dwell_gain(1.0), BrushTool.dwell_gain(0.5))
	assert_almost_eq(BrushTool.dwell_gain(99.0), BrushTool.dwell_gain(BrushTool.DWELL_MAX), 1e-6)


func test_radius_steps_are_multiplicative_and_clamped() -> void:
	var grown := BrushTool.stepped_radius(4.0, 1)
	assert_almost_eq(grown, 4.0 * BrushTool.RADIUS_STEP, 1e-5)
	assert_almost_eq(BrushTool.stepped_radius(11.5, 3), BrushTool.MAX_RADIUS, 1e-6)
	assert_almost_eq(BrushTool.stepped_radius(1.05, -2), BrushTool.MIN_RADIUS, 1e-6)
