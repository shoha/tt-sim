class_name ToolRegistry
extends RefCounted

## Every map tool, in rail order, as one ToolDescriptor each (scenes/states/authoring/tools/).
## The hubs read it instead of listing tools by hand: AuthoringPanel builds its rail items and
## panes from it, AuthoringController picks a tool and refreshes the rail through it, and the
## F1 help overlay lists each tool's rows from it. Adding a tool is one descriptor added to
## _make() below, its BrushMode class, its pane and a test (AGENTS.md "Adding Features",
## docs/systems/authoring.md "Tools").
##
## The rail lists seven tools (rail_tools: Biome, Place, Sculpt, Paint, Water, Build, Fire); the
## rest are tabs of one of them and keep their descriptors, brush modes and panes. A rail tool with
## `tabs` is a hub: Place (Add, Thin / Clear), Paint (Paint, Path), Water (River, Pond, Crossing)
## and Build (Walls, Buildings, Villages). A tab's tool says `hub` (hub_of maps a tool id to its
## rail id), so the controller, saves, tests and the F1 help keep every id.
##
## Contexts: a descriptor says whether it exists in authoring, in play, or in both
## (ToolDescriptor.AUTHORING, PLAY), and every list query takes the context it is for. Play
## lists Biome, Thin / Clear, Sculpt, Paint, Water and Bridge, the GM's live brushes in the
## Events pane (PlayEvents), each as its own brush as before (play has no rail, so the merged
## hubs change nothing there); the Build hub and Place are authoring's alone.
##
## The descriptors are stateless, so one set is made on first use and shared.

## The runs the rail breaks its seven tools into (a gap between runs, DrawerContainer.rail_items'
## "group" key): what the tool works on. Land is what grows on the ground (Biome, and Place with
## its Thin / Clear mode), Shape is the ground itself (Sculpt, Paint), Make is what is added to it
## (Water with its crossings, Build with its walls, buildings and villages, Fire). A tool that is
## a tab of a hub (Thin / Clear, Path, Bridge, Wall, Structure, Village) has no rail item and so no
## run.
const GROUPS := {
	&"biome": &"land",
	&"place": &"land",
	&"sculpt": &"shape",
	&"paint": &"shape",
	&"water": &"make",
	&"build": &"make",
	&"fire": &"make",
}

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


## The tool in `context` whose shortcut `event` presses, or null.
static func for_shortcut(event: InputEvent, context: int) -> ToolDescriptor:
	for tool in tools(context):
		if tool.matches_shortcut(event):
			return tool
	return null


## The tools the rail lists in `context`, in rail order: seven in authoring (the others are tabs of
## one of them).
static func rail_tools(context: int) -> Array[ToolDescriptor]:
	var listed: Array[ToolDescriptor] = []
	for tool in tools(context):
		if tool.on_rail:
			listed.append(tool)
	return listed


## The rail items of the tools in `context` (DrawerContainer.rail_items entries).
static func rail_items(context: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for tool in rail_tools(context):
		var item := tool.rail_item(context == ToolDescriptor.AUTHORING)
		item["group"] = GROUPS.get(tool.id, &"")
		items.append(item)
	return items


## The rail item that tool `id` lives under: its hub, or itself ("bridge" is under "water").
static func hub_of(id: StringName) -> StringName:
	var tool := find(id)
	return tool.hub if tool != null and tool.hub != &"" else id


## The tab of rail tool `rail_id` that runs tool `tool_id` (for Water's two shapes, the first of
## them): {} when the rail tool has no such tab.
static func tab_for(rail_id: StringName, tool_id: StringName) -> Dictionary:
	var rail_tool := find(rail_id)
	if rail_tool != null:
		for tab in rail_tool.tabs:
			if StringName(tab["tool"]) == tool_id:
				return tab
	return {}


## The F1 help rows of the tools in `context`, tool by tool in rail order.
static func help_rows(context: int) -> Array:
	var rows: Array = []
	for tool in tools(context):
		rows.append_array(tool.help_rows())
	return rows


static func _make() -> Array[ToolDescriptor]:
	return [
		BiomeTool.new(),
		PlaceTool.new(),
		ThinTool.new(),
		SculptTool.new(),
		PaintTool.new(),
		PathTool.new(),
		WaterTool.new(),
		BridgeTool.new(),
		BuildTool.new(),
		WallTool.new(),
		StructureTool.new(),
		VillageTool.new(),
		FireTool.new(),
	]
