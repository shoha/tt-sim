extends GutTest

## AnimatedCanvasLayerPanel keeps a class-level stack of live panels and only
## the topmost one traps Tab, so a dialog opened over another panel (e.g.
## LevelPickerDialog over the pause menu) does not have Tab pulled back into
## the panel underneath it.


func _panel_with_buttons(names: Array) -> AnimatedCanvasLayerPanel:
	var panel := AnimatedCanvasLayerPanel.new()
	panel.play_sounds = false

	var backdrop := ColorRect.new()
	backdrop.name = "ColorRect"
	panel.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	panel.add_child(center)

	var panel_container := PanelContainer.new()
	panel_container.name = "PanelContainer"
	center.add_child(panel_container)

	var box := VBoxContainer.new()
	box.name = "Box"
	panel_container.add_child(box)

	for button_name in names:
		var button := Button.new()
		button.name = button_name
		box.add_child(button)

	return panel


func test_only_the_topmost_panel_traps_tab() -> void:
	var lower := _panel_with_buttons(["A", "B"])
	add_child_autofree(lower)
	var upper := _panel_with_buttons(["C", "D"])
	add_child_autofree(upper)
	await wait_frames(2)
	assert_false(lower.is_top_trap())
	assert_true(upper.is_top_trap())
	# Focus the last button of the upper panel and press Tab: the upper panel wraps to
	# its own first button; the lower panel must not grab focus.
	var upper_buttons := upper.get_node("CenterContainer/PanelContainer/Box").get_children()
	(upper_buttons[1] as Control).grab_focus()
	# Input.parse_input_event does not reach _input() in headless GUT, so drive
	# _input() directly in tree order (lower first, then upper) instead.
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	lower._input(tab)
	upper._input(tab)
	await wait_frames(2)
	assert_same(get_viewport().gui_get_focus_owner(), upper_buttons[0])


func test_freeing_the_top_panel_hands_the_trap_back() -> void:
	var lower := _panel_with_buttons(["A", "B"])
	add_child_autofree(lower)
	var upper := _panel_with_buttons(["C", "D"])
	add_child(upper)
	await wait_frames(1)
	upper.queue_free()
	await wait_frames(2)
	assert_true(lower.is_top_trap())
