class_name BuildTool
extends ToolDescriptor

## The Build hub: the one rail item for everything made of stone and timber. It has no brush of
## its own. Its card has top tabs, Walls, Buildings and Villages, and each is the old tool it
## stands for (WallTool, StructureTool, VillageTool), with that tool's own pane, brush mode and
## gestures; a tab picked switches the brush exactly as the rail item of that tool did before the
## 2026-11-16 map building 3 card. Their descriptors keep their ids (saves, tests and the F1 help
## use them) and list `hub = &"build"`; only the rail leaves them out. It exists in authoring
## alone: the GM's Events pane in play lists Wall and Buildings as their own brushes.

const ID := &"build"


func _init() -> void:
	id = ID
	label = "Build"
	summary = "Walls, buildings and villages."
	icon = "home"
	shortcut = KEY_U  # the second letter of Build (B is Biome's)
	slot = 6
	contexts = AUTHORING
	brush_mode = null
	unavailable_tooltip = "Build: not on a Blender map, whose ground is the map file's"
	tabs = [
		{
			"id": WallTool.ID,
			"label": "Walls",
			"tool": WallTool.ID,
			"tip": "Walls: a stone wall, a fence or a street of buildings",
		},
		{
			"id": StructureTool.ID,
			"label": "Buildings",
			"tool": StructureTool.ID,
			"tip": "Buildings: put a building down on the ground",
		},
		{
			"id": VillageTool.ID,
			"label": "Villages",
			"tool": VillageTool.ID,
			"tip": "Villages: open plazas and lay fields",
		},
	]


## Whether any of the hub's tools can work on the open map: all three need the document's own
## ground, so on a dressed Blender map the hub is off with a tooltip saying why.
func can_select(controller: AuthoringController) -> bool:
	for tab in tabs:
		var tool := ToolRegistry.find(StringName(tab["tool"]))
		if tool != null and tool.can_select(controller):
			return true
	return false
