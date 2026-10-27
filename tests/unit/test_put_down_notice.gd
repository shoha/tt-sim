extends GutTest

## The notice a right click puts up in the authoring panel (AuthoringPanel.show_put_down): what
## happened to the brush and how to pick it up again.


func _panel() -> AuthoringPanel:
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	return panel


func test_the_notice_names_the_tool_and_offers_to_pick_it_up() -> void:
	var panel := _panel()
	assert_false(panel.is_put_down_shown(), "not before a right click")
	panel.show_put_down(WallTool.ID)
	assert_true(panel.is_put_down_shown())
	var button := panel.find_child("PutDownPickUp", true, false) as Button
	var text := panel.find_child("PutDownText", true, false) as Label
	assert_string_contains(button.text, "Wall")
	assert_string_contains(text.text, "Wall")
	watch_signals(panel)
	button.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "pick_up_requested", [WallTool.ID])


func test_the_tiles_clear_while_the_brush_is_down_and_come_back() -> void:
	var panel := _panel()
	var pane := panel.tool_pane(WallTool.ID) as WallToolPane
	assert_eq(pane.kind_field.tiles.selected, &"wall_stone", "Stone is picked")
	panel.show_put_down(WallTool.ID)
	assert_eq(pane.kind_field.tiles.selected, &"", "nothing picked while the brush is down")
	assert_false(pane.kind_field.tiles.is_on(&"wall_stone"), "and no tile drawn picked")
	panel.set_active_tool(WallTool.ID)
	assert_eq(pane.kind_field.tiles.selected, &"wall_stone", "the pick comes back with the brush")
	assert_true(pane.kind_field.tiles.is_on(&"wall_stone"))


func test_pressing_a_tile_keeps_the_new_pick_when_the_brush_comes_back() -> void:
	var panel := _panel()
	var pane := panel.tool_pane(WallTool.ID) as WallToolPane
	panel.show_put_down(WallTool.ID)
	pane.kind_field.tiles.selected = &"wall_fence"
	pane.kind_field.tiles.select(&"wall_fence")
	panel.set_active_tool(WallTool.ID)
	assert_eq(pane.kind_field.tiles.selected, &"wall_fence", "the tile just pressed stays picked")
	# The tile that was picked before can be pressed again: it counts as a change.
	panel.show_put_down(WallTool.ID)
	watch_signals(pane.kind_field.tiles)
	pane.kind_field.tiles.get_node("wall_fence").button_pressed = true
	assert_signal_emitted(pane.kind_field.tiles, "selection_changed")


func test_a_brush_coming_out_again_takes_the_notice_away() -> void:
	var panel := _panel()
	panel.show_put_down(FireTool.ID)
	assert_true(panel.is_put_down_shown())
	panel.set_active_tool(FireTool.ID)
	assert_false(panel.is_put_down_shown(), "the brush is out, nothing to say")
	panel.show_put_down(&"no_such_tool")
	assert_false(panel.is_put_down_shown(), "an unknown tool says nothing")
