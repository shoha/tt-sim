extends GutTest

## BrushTool.decide() (scenes/states/authoring/brush_tool.gd): which input the brush takes,
## and what it means. Plain wheel stays the camera's; Shift+wheel sizes the brush (or scales
## a hovered prop); RMB cancels a stroke, removes a hovered prop, or puts the brush down.
## Then the host's dispatch: every registered tool's mode is a BrushMode the brush switches
## to, and a mode's fade focus reaches the occlusion fade.

## decide()'s `picks`: a mode that works the ground (Biome), or one that picks a target under
## the pointer (Place).
const GROUND := false
const PICKS := true
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


func test_only_place_picks_a_target() -> void:
	assert_true(PlaceBrush.new().picks)
	for mode in [BiomeBrush, ThinBrush, SculptBrush, PaintBrush, WaterBrush, BridgeBrush]:
		assert_false((mode.new() as BrushMode).picks)


func test_plain_wheel_is_left_to_the_camera() -> void:
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_WHEEL_UP, true), GROUND, false, false), A.NONE)
	assert_eq(
		BrushTool.decide(_button(MOUSE_BUTTON_WHEEL_DOWN, true), GROUND, true, false), A.NONE
	)


func test_shift_wheel_sizes_the_brush() -> void:
	var up := _button(MOUSE_BUTTON_WHEEL_UP, true, true)
	var down := _button(MOUSE_BUTTON_WHEEL_DOWN, true, true)
	assert_eq(BrushTool.decide(up, GROUND, false, false), A.GROW)
	assert_eq(BrushTool.decide(down, GROUND, true, false), A.SHRINK)
	assert_eq(
		BrushTool.decide(_button(MOUSE_BUTTON_WHEEL_UP, false, true), GROUND, false, false), A.NONE
	)


func test_shift_wheel_in_place_scales_only_a_hovered_prop() -> void:
	var up := _button(MOUSE_BUTTON_WHEEL_UP, true, true)
	assert_eq(BrushTool.decide(up, PICKS, false, true), A.GROW)
	assert_eq(BrushTool.decide(up, PICKS, false, false), A.NONE, "else the camera zooms")


func test_brackets_size_the_brush() -> void:
	assert_eq(BrushTool.decide(_key(KEY_BRACKETRIGHT), GROUND, false, false), A.GROW)
	assert_eq(BrushTool.decide(_key(KEY_BRACKETLEFT), GROUND, false, false), A.SHRINK)


func test_rmb_cancels_a_stroke_or_puts_the_brush_down() -> void:
	var rmb := _button(MOUSE_BUTTON_RIGHT, true)
	assert_eq(BrushTool.decide(rmb, GROUND, true, false), A.CANCEL)
	assert_eq(BrushTool.decide(rmb, GROUND, false, false), A.DESELECT)
	assert_eq(BrushTool.decide(rmb, PICKS, false, true), A.REMOVE)
	assert_eq(BrushTool.decide(rmb, PICKS, true, true), A.CANCEL, "a placement in progress")
	var release := _button(MOUSE_BUTTON_RIGHT, false)
	assert_eq(BrushTool.decide(release, GROUND, false, false), A.SWALLOW, "no context menu")


func test_lmb_begins_and_ends() -> void:
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_LEFT, true), GROUND, false, false), A.BEGIN)
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_LEFT, false), GROUND, true, false), A.END)
	assert_eq(
		BrushTool.decide(_button(MOUSE_BUTTON_LEFT, false), GROUND, false, false),
		A.NONE,
		"a release the brush did not start is not its own"
	)


func test_delete_removes_a_hovered_prop_in_place_only() -> void:
	assert_eq(BrushTool.decide(_key(KEY_DELETE), PICKS, false, true), A.REMOVE)
	assert_eq(BrushTool.decide(_key(KEY_DELETE), PICKS, false, false), A.NONE)
	assert_eq(BrushTool.decide(_key(KEY_DELETE), GROUND, false, true), A.NONE)


func test_motion_is_a_pointer_update_never_consumed() -> void:
	var motion := InputEventMouseMotion.new()
	assert_eq(BrushTool.decide(motion, GROUND, true, false), A.POINTER)


func test_other_buttons_are_not_the_brush_s() -> void:
	assert_eq(BrushTool.decide(_button(MOUSE_BUTTON_MIDDLE, true), GROUND, false, false), A.NONE)


func test_dwell_builds_strength_up_to_a_cap() -> void:
	assert_almost_eq(BrushTool.dwell_gain(0.0), 1.0, 1e-6)
	assert_gt(BrushTool.dwell_gain(1.0), BrushTool.dwell_gain(0.5))
	assert_almost_eq(BrushTool.dwell_gain(99.0), BrushTool.dwell_gain(BrushTool.DWELL_MAX), 1e-6)


func test_the_brush_runs_each_tool_s_own_mode_and_keeps_it() -> void:
	var brush := BrushTool.new()
	add_child_autofree(brush)
	assert_null(brush.tool, "no tool before one is picked")
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		brush.use_tool(tool)
		assert_eq(brush.tool, tool)
		assert_true(is_instance_of(brush.mode, tool.brush_mode), "%s runs its mode" % tool.id)
		assert_eq(brush.mode, brush.mode_for(tool), "one mode per tool")
	var sculpt := SculptTool.of(brush)
	sculpt.tile = HeightBrush.TIER
	brush.use_tool(ToolRegistry.find(BiomeTool.ID))
	brush.use_tool(ToolRegistry.find(SculptTool.ID))
	assert_eq(brush.mode, sculpt, "switching away and back keeps the mode")
	assert_eq(SculptTool.of(brush).tile, HeightBrush.TIER, "and what its pane picked")
	var without := ToolDescriptor.new()
	brush.use_tool(without)
	assert_eq(brush.tool, ToolRegistry.find(SculptTool.ID), "a tool with no mode is ignored")


func test_thin_ring_is_the_canopy_brush_window() -> void:
	var brush := BrushTool.new()
	add_child_autofree(brush)
	var thin := ToolRegistry.find(ThinTool.ID)
	brush.use_tool(thin)
	brush.activate()
	brush.hit = Vector3(3.0, 0.5, -2.0)
	brush._update_fade()
	var radius := BrushTool.session_radius * BrushTool.FADE_RADIUS_FACTOR
	assert_eq(
		CanopyFade.brush_asked(), Vector4(3.0, 0.5, -2.0, radius), "ring centre, widened radius"
	)
	brush.use_tool(ToolRegistry.find(BiomeTool.ID))
	brush._update_fade()
	assert_eq(CanopyFade.brush_asked(), Vector4.ZERO, "the Biome brush does not fade the canopy")
	brush.use_tool(thin)
	brush._update_fade()
	brush.hit = Vector3.INF
	brush._update_fade()
	assert_eq(CanopyFade.brush_asked(), Vector4.ZERO, "no ground under the pointer")
	brush.hit = Vector3.ZERO
	brush.fade_held_only = true
	brush._update_fade()
	assert_eq(CanopyFade.brush_asked(), Vector4.ZERO, "the play brush: not before a press")
	brush.pressed = true
	brush._update_fade()
	assert_gt(CanopyFade.brush_asked().w, 0.0, "the play brush: while the press is held")
	brush.pressed = false
	brush._update_fade()
	assert_eq(CanopyFade.brush_asked(), Vector4.ZERO, "and closing once it is let go")
	brush.fade_held_only = false
	brush._update_fade()
	brush.deactivate()
	assert_eq(CanopyFade.brush_asked(), Vector4.ZERO, "putting the brush down clears it")
	CanopyFade.step_brush(1.0)


func test_radius_steps_are_multiplicative_and_clamped() -> void:
	var grown := BrushTool.stepped_radius(4.0, 1)
	assert_almost_eq(grown, 4.0 * BrushTool.RADIUS_STEP, 1e-5)
	assert_almost_eq(BrushTool.stepped_radius(11.5, 3), BrushTool.MAX_RADIUS, 1e-6)
	assert_almost_eq(BrushTool.stepped_radius(1.05, -2), BrushTool.MIN_RADIUS, 1e-6)
