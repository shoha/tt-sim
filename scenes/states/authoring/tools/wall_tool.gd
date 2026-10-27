class_name WallTool
extends ToolDescriptor

## The Wall tool: a drag across the ground lays a side of a dry-stone wall or a post and rail
## fence, and the next drag from its end carries on; Ctrl+click removes one (WallBrush does the
## gesture, WallEditor the edit, AuthoredWalls the nodes). The geometry is the shared procgen
## module's wall and fence recipes (WallGeometry, docs/systems/walls.md). Its pane is
## WallToolPane. A dressed Blender map's ground is the GLB's, so there the tool is disabled with
## a tooltip saying why, as Paint is.

const ID := &"wall"
const LABEL := "Wall"
const UNAVAILABLE_TOOLTIP := "Wall: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Build a stone wall or a fence along a line."
	icon = "wall"
	brush_mode = WallBrush
	contexts = AUTHORING
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		[
			"Left Drag (Wall)",
			"Lay a side of a wall or fence; start the next drag at its end to carry on",
		],
		["Close (Wall)", "End a drag at the first end of an open wall to close the loop"],
		["Ctrl + Click (Wall)", "Remove the wall under the cursor"],
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> WallBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as WallBrush


## Only where the ground is the document's (a wall follows the document's heights).
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_paint()


func build_pane(_panel: AuthoringPanel) -> Control:
	return WallToolPane.new()


## The kind tiles set the brush's kind.
func connect_pane(controller: AuthoringController, pane: Control) -> void:
	var wall_pane := pane as WallToolPane
	if wall_pane == null:
		return
	wall_pane.kind_selected.connect(
		func(value: int) -> void:
			if controller.brush != null:
				of(controller.brush).kind = value
				controller.brush.redraw()
	)
