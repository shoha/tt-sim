extends GutTest

## Unit tests for GameMap.should_bypass_world_tool.
##
## GameMap._input() offers every event to the active modal world tool (sun
## gizmo, measure tool) before the GUI sees it, so the tool has to be told to
## keep its hands off input that belongs to a UI control.
##
## The regression these guard: the bypass used to test `event.pressed`, so only
## presses over the UI were spared. A mouse *release* over the Visuals drawer
## went to SunGizmoTool.handle_input(), which consumes every left-button event,
## and GameMap then marked it handled. Godot's Slider clears its drag grab only
## when its own gui_input() sees the button-up (scene/gui/slider.cpp), so the
## slider stayed glued to the pointer after the button came up -- right-clicking
## it was the only way to shake it loose.


func _button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func test_a_press_over_the_gui_bypasses_the_world_tool() -> void:
	assert_true(GameMap.should_bypass_world_tool(_button(true), true, false))


func test_a_release_over_the_gui_bypasses_the_world_tool() -> void:
	# The regression guard. A release is as much the UI control's as the press.
	assert_true(GameMap.should_bypass_world_tool(_button(false), true, false))


func test_a_release_over_the_gui_still_reaches_a_tool_that_is_mid_drag() -> void:
	# A gizmo drag that began out on the 3D view owns the whole gesture: it has
	# to see the button-up even if the pointer has since crossed over a panel,
	# or the gizmo itself is the thing left stuck dragging.
	assert_false(GameMap.should_bypass_world_tool(_button(false), true, true))


func test_buttons_over_the_3d_view_reach_the_world_tool() -> void:
	assert_false(GameMap.should_bypass_world_tool(_button(true), false, false))
	assert_false(GameMap.should_bypass_world_tool(_button(false), false, false))


func test_mouse_motion_is_never_bypassed() -> void:
	# Motion drives the gizmo ring and the measure preview, and is not consumed
	# by either tool, so it always falls through to the tool first.
	assert_false(GameMap.should_bypass_world_tool(InputEventMouseMotion.new(), true, false))
	assert_false(GameMap.should_bypass_world_tool(InputEventMouseMotion.new(), true, true))


func test_non_mouse_events_are_never_bypassed() -> void:
	# Tab cycles the measure mode and Escape cancels it while the pointer sits
	# anywhere, including over the drawer.
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true

	assert_false(GameMap.should_bypass_world_tool(key, true, false))
