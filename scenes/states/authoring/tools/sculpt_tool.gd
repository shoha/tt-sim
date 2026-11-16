class_name SculptTool
extends ToolDescriptor

## The Sculpt tool: raises, smooths, flattens and tiers the document's own ground
## (SculptBrush; HeightEditor runs the strokes). Its pane is AuthoringPanel's four tiles. A
## dressed Blender map's ground is the GLB's, so there the tool is disabled with a tooltip
## saying why. It exists in play too, in the GM's Events pane (PlayEvents).

const ID := &"sculpt"
const LABEL := "Sculpt"
const UNAVAILABLE_TOOLTIP := "Sculpt: not on a Blender map, whose ground is the map file's"
## The pane's tiles: id (the HeightBrush operation), label, icon, tooltip.
const TILES: Array[Dictionary] = [
	{
		"op": HeightBrush.RAISE,
		"label": "Raise",
		"icon": "arrow-bar-up",
		"tooltip": "Raise a mound; hold Ctrl as you press to lower",
	},
	{
		"op": HeightBrush.SMOOTH,
		"label": "Smooth",
		"icon": "wave-sine",
		"tooltip": "Soften slopes, edges and faces (Shift with any tile)",
	},
	{
		"op": HeightBrush.FLATTEN,
		"label": "Flatten",
		"icon": "fold",
		"tooltip": "Level the ground to the height where you press",
	},
	{
		"op": HeightBrush.TIER,
		"label": "Tier",
		"icon": "stairs-up",
		"tooltip": "Build a rock-faced level one tier up; hold Ctrl as you press to cut one down",
	},
]


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Shape the ground."
	icon = "mountain"
	brush_mode = SculptBrush
	shortcut = KEY_T  # T for terrain (the token roster's T is the play state's)
	slot = 3
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
