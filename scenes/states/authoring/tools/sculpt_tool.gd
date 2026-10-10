class_name SculptTool
extends ToolDescriptor

## The Sculpt tool: raises, smooths, flattens and tiers the document's own ground
## (SculptBrush; HeightEditor runs the strokes). Its pane is AuthoringPanel's four tiles. A
## dressed Blender map's ground is the GLB's, so there the tool is disabled with a tooltip
## saying why. It exists in play too, in the GM's Events pane (PlayEvents).

const ID := &"sculpt"
const LABEL := "Sculpt"
const UNAVAILABLE_TOOLTIP := "Sculpt: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Shape the ground."
	icon = "mountain"
	brush_mode = SculptBrush
	contexts = AUTHORING | PLAY
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [["Shift + Left Drag", "Smooth the ground (Sculpt, any tile)"]]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> SculptBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as SculptBrush


## Only where the ground is the document's.
func can_select(controller: AuthoringController) -> bool:
	return controller.editor != null and works_on(controller.editor)


func works_on(editor: AuthoringEditor) -> bool:
	return editor.can_sculpt()
