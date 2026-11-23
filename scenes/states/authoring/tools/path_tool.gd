class_name PathTool
extends ToolDescriptor

## The Path tool, the Paint hub's Path tab (card terraform-p2-paint-path): a line drawn across the
## ground becomes a walkable path of the Paint tab's surface, benched and graded into the slope
## with steps where it climbs and a ford where it meets water (with the terrain core on;
## PathBrush). Ctrl erases the paths the line touches. Its pane is PathToolPane: the width tiles
## and the surface it paints. Only where the ground is the document's, as Paint.

const ID := &"path"
const LABEL := "Path"
const UNAVAILABLE_TOOLTIP := "Path: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Draw a path; it settles into the slope."
	icon = "walk"
	brush_mode = PathBrush
	on_rail = false
	hub = PaintTool.ID
	contexts = AUTHORING
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		[
			"Left Drag (Path)",
			"Draw a path: it is graded into the slope, with steps where it climbs and a ford at water",
		],
		["Ctrl + Drag (Path)", "Erase the paths the line crosses"],
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> PathBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as PathBrush


## Only where the ground is the document's.
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_paint()


## The pane names the surface the path will paint (the Paint tab's pick).
func prepare(controller: AuthoringController) -> void:
	controller.panel.ensure_paint_tiles()
	var pane := controller.panel.tool_pane(ID) as PathToolPane
	if pane != null and controller.brush != null:
		pane.show_surface(PathBrush.surface_of(controller.brush))
		pane.select_width(of(controller.brush).width)


func build_pane(_panel: AuthoringPanel) -> Control:
	return PathToolPane.new()


## A width tile sets the brush's width and picks the tool again (a brush put down comes back).
func connect_pane(controller: AuthoringController, pane: Control) -> void:
	var path_pane := pane as PathToolPane
	if path_pane == null:
		return
	path_pane.width_selected.connect(
		func(value: float) -> void:
			if controller.brush != null:
				of(controller.brush).width = value
				controller.pick_tool(ID)
	)
