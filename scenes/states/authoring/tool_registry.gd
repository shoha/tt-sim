class_name ToolRegistry
extends RefCounted

## Every map tool, in rail order, as one ToolDescriptor each (scenes/states/authoring/tools/).
## The hubs read it instead of listing tools by hand: AuthoringPanel builds its rail items and
## panes from it, AuthoringController picks a tool, refreshes the rail and maps the brush's
## mode back to a tool through it, and the F1 help overlay lists each tool's rows from it.
## Adding a tool is one descriptor added to _make() below, its gesture handler, its pane and
## a test (AGENTS.md "Adding Features", docs/systems/authoring.md "Tools").
##
## Contexts: a descriptor says whether it exists in authoring, in play, or in both
## (ToolDescriptor.AUTHORING, PLAY), and every list query takes the context it is for. The
## seven tools of 2026-10 are all authoring tools; play lists none yet.
##
## The descriptors are stateless, so one set is made on first use and shared.

static var _tools: Array[ToolDescriptor] = []


## Every registered tool, in rail order.
static func all() -> Array[ToolDescriptor]:
	if _tools.is_empty():
		_tools = _make()
	return _tools


## The tools that exist in `context` (ToolDescriptor.AUTHORING or PLAY), in rail order.
static func tools(context: int) -> Array[ToolDescriptor]:
	var listed: Array[ToolDescriptor] = []
	for tool in all():
		if tool.exists_in(context):
			listed.append(tool)
	return listed


## The tool with id `id`, or null.
static func find(id: StringName) -> ToolDescriptor:
	for tool in all():
		if tool.id == id:
			return tool
	return null


## The authoring tool whose gestures run in BrushTool mode `mode`, or null.
static func for_mode(mode: int) -> ToolDescriptor:
	for tool in tools(ToolDescriptor.AUTHORING):
		if tool.brush_mode == mode:
			return tool
	return null


## The tool in `context` whose shortcut `event` presses, or null.
static func for_shortcut(event: InputEvent, context: int) -> ToolDescriptor:
	for tool in tools(context):
		if tool.matches_shortcut(event):
			return tool
	return null


## The rail items of the tools in `context` (DrawerContainer.rail_items entries).
static func rail_items(context: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for tool in tools(context):
		items.append(tool.rail_item())
	return items


## The F1 help rows of the tools in `context`, tool by tool in rail order.
static func help_rows(context: int) -> Array:
	var rows: Array = []
	for tool in tools(context):
		rows.append_array(tool.help_rows())
	return rows


static func _make() -> Array[ToolDescriptor]:
	return [
		BiomeTool.new(),
		ThinTool.new(),
		PlaceTool.new(),
		SculptTool.new(),
		PaintTool.new(),
		WaterTool.new(),
		BridgeTool.new(),
	]
