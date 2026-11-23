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
## The tile Soften (TerraSculpt.SOFTEN), one of the terrain core's (tiles()).
const SOFTEN_TILE := {
	"label": "Soften",
	"icon": "eraser",
	"tooltip": "Soften or take away what was sculpted, and lower hills, under the brush",
}
## Why Terrace or Soften refused a press: a map whose ground is not terrain primitives.
const TERRA_ONLY := "%s needs a map made with the terrain core"

const TerraceTool := preload("res://utils/terraform/kinds/terrace/terrace_tool.gd")


## The pane's tiles: TILES, then with the terrain core on (TerraCore.enabled()) Terrace and Soften,
## which shape terrain primitives only (TerraSculpt).
static func tiles() -> Array[Dictionary]:
	return all_tiles() if TerraCore.enabled() else TILES.duplicate()


## Every Sculpt tile, the core's included (tile ids and lookups).
static func all_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = TILES.duplicate()
	out.append(TerraceTool.TILE.merged({"op": TerraSculpt.TERRACE}))
	out.append(SOFTEN_TILE.merged({"op": TerraSculpt.SOFTEN}))
	return out


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Shape the ground."
	icon = "mountain"
	brush_mode = SculptBrush
	shortcut = KEY_T  # T for terrain (the token roster's T is the play state's)
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
