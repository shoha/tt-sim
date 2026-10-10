extends GutTest

## ToolRegistry (2026-10-09): the hubs read the tools from it, so every registered tool is on
## the authoring rail with its icon and tooltip, has a pane titled from its descriptor, is in
## the F1 help with its shortcut, and owns one brush mode; ids and shortcuts are unique.

const HelpOverlayScript := preload("res://scenes/ui/help_overlay.gd")


func _panel() -> AuthoringPanel:
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	return panel


## The rows of one F1 help section, each [keys, what].
func _help_section(header: String) -> Array:
	var overlay: Node = HelpOverlayScript.new()
	var sections: Array = overlay.call("_get_shortcut_data")
	overlay.free()
	for section in sections:
		if section.header == header:
			return section.entries
	return []


func _row_index(rows: Array, row: Array) -> int:
	for i in rows.size():
		if rows[i][0] == row[0] and rows[i][1] == row[1]:
			return i
	return -1


func test_the_seven_tools_are_registered_once_each() -> void:
	var tools := ToolRegistry.tools(ToolDescriptor.AUTHORING)
	var ids: Array[StringName] = []
	for tool in tools:
		assert_false(tool.id in ids, "%s registered once" % tool.id)
		ids.append(tool.id)
		assert_eq(ToolRegistry.find(tool.id), tool)
	for id in [
		AuthoringPanel.TOOL_BIOME,
		AuthoringPanel.TOOL_THIN,
		AuthoringPanel.TOOL_PLACE,
		AuthoringPanel.TOOL_SCULPT,
		AuthoringPanel.TOOL_PAINT,
		AuthoringPanel.TOOL_WATER,
		AuthoringPanel.TOOL_BRIDGE,
	]:
		assert_true(id in ids, "%s is a registered tool" % id)
	assert_null(ToolRegistry.find(&"no_such_tool"))


func test_every_tool_is_on_the_rail_in_registry_order() -> void:
	var panel := _panel()
	var tools := ToolRegistry.tools(ToolDescriptor.AUTHORING)
	var rail_ids: Array = panel.rail_items.map(func(item: Dictionary) -> StringName: return item.id)
	var tool_ids: Array = tools.map(func(tool: ToolDescriptor) -> StringName: return tool.id)
	assert_eq(rail_ids, tool_ids, "the rail lists the registry, in its order")
	var buttons: Dictionary = (panel.get("_rail") as IconRail).get("_buttons")
	for tool in tools:
		assert_true(buttons.has(tool.id), "%s has a rail item" % tool.id)
		var button: IconButton = buttons[tool.id]
		assert_eq(button.icon_name, tool.icon)
		assert_true(
			ResourceLoader.exists("res://assets/icons/ui/%s.svg" % tool.icon),
			"%s's icon exists" % tool.id
		)
		assert_eq(button.tooltip_text, tool.rail_tooltip())


func test_every_tool_has_a_pane_titled_from_its_descriptor() -> void:
	var panel := _panel()
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		var pane := panel.tool_pane(tool.id)
		assert_not_null(pane, "%s has a pane" % tool.id)
		if pane == null:
			continue
		var headers := pane.find_children("*", "MenuHeader", true, false)
		assert_false(headers.is_empty(), "%s's pane has a header" % tool.id)
		if headers.is_empty():
			continue
		var header := headers[0] as MenuHeader
		assert_eq(header.title_label.text, tool.label)
		assert_eq(header.caption_label.text, tool.summary)


func test_every_tool_is_in_help_with_its_shortcut() -> void:
	var building := _help_section("Map building")
	var last := -1
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		var rows := tool.help_rows()
		assert_eq(rows[0][0], tool.rail_tooltip(), "%s's help row is named for it" % tool.id)
		if tool.shortcut != KEY_NONE:
			assert_string_contains(rows[0][0], tool.shortcut_label())
		for row in rows:
			var index := _row_index(building, row)
			assert_gt(index, last, "%s's row %s is in help, after the tool before" % [tool.id, row])
			last = index
	# A play tool that is a map-building tool too has its rows there; the Tools section names
	# the GM's Events pane once, and lists a play-only tool's own rows.
	var tools := _help_section("Tools")
	assert_gt(_row_index(tools, [PlayEvents.HELP_KEYS, PlayEvents.HELP_TEXT]), -1, "Events row")
	for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
		var section := building if tool.exists_in(ToolDescriptor.AUTHORING) else tools
		for row in tool.help_rows():
			assert_gt(_row_index(section, row), -1, "%s's row %s is in help" % [tool.id, row])


func test_shortcuts_are_unique() -> void:
	var keys: Array[Key] = []
	var seen := {}
	for tool in ToolRegistry.all():
		if tool.shortcut != KEY_NONE:
			keys.append(tool.shortcut)
			seen[tool.shortcut] = tool.id
	assert_eq(seen.size(), keys.size(), "no two tools share a shortcut: %s" % [seen])


func test_a_shortcut_is_a_bare_key_press() -> void:
	var tool := ToolDescriptor.new()
	tool.label = "Test"
	var press := InputEventKey.new()
	press.keycode = KEY_B
	press.pressed = true
	assert_false(tool.matches_shortcut(press), "no shortcut matches nothing")
	tool.shortcut = KEY_B
	assert_true(tool.matches_shortcut(press))
	assert_eq(tool.rail_tooltip(), "Test (B)")
	assert_eq(tool.help_rows()[0][0], "Test (B)")
	var held := press.duplicate() as InputEventKey
	held.ctrl_pressed = true
	assert_false(tool.matches_shortcut(held), "Ctrl+B is not the shortcut")
	var echo := press.duplicate() as InputEventKey
	echo.echo = true
	assert_false(tool.matches_shortcut(echo), "a repeat is not a press")
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	assert_false(tool.matches_shortcut(release))
	assert_null(
		ToolRegistry.for_shortcut(press, ToolDescriptor.AUTHORING),
		"no registered tool has B (none has a shortcut yet)"
	)


func test_every_tool_brings_its_own_brush_mode() -> void:
	var modes := {}
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		assert_not_null(tool.brush_mode, "%s has a brush mode" % tool.id)
		if tool.brush_mode == null:
			continue
		assert_true(tool.brush_mode.new() is BrushMode, "%s's mode is a BrushMode" % tool.id)
		assert_false(modes.has(tool.brush_mode), "%s runs its own brush mode" % tool.id)
		modes[tool.brush_mode] = tool.id


func test_a_tool_with_an_unavailable_tooltip_says_why_on_the_rail() -> void:
	var panel := _panel()
	var buttons: Dictionary = (panel.get("_rail") as IconRail).get("_buttons")
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		if tool.unavailable_tooltip == "":
			continue
		var button: IconButton = buttons[tool.id]
		panel.set_tool_available(tool.id, false)
		assert_true(button.disabled)
		assert_eq(button.tooltip_text, tool.unavailable_tooltip)
		panel.set_tool_available(tool.id, true)
		assert_false(button.disabled)
		assert_eq(button.tooltip_text, tool.rail_tooltip())
