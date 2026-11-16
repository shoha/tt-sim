class_name WaterTool
extends ToolDescriptor

## The Water tool: rivers drawn the way they flow and ponds painted as areas, carved into the
## document's own ground, and Ctrl to erase (WaterBrush does the gestures, WaterEditor the
## carve). Its pane is WaterToolPane, which AuthoringPanel builds and
## relays. On a dressed Blender map it only erases water painted over it, and with none to
## erase it is disabled (AuthoringPanel.set_water_available).

const ID := &"water"
const LABEL := "Water"
const UNAVAILABLE_TOOLTIP := "Water: not on a Blender map, whose ground is the map file's"


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Rivers, streams and ponds."
	icon = "droplet"
	brush_mode = WaterBrush
	shortcut = KEY_H  # H for H2O (W is the camera's)
	slot = 5
	contexts = AUTHORING | PLAY
	# River and Pond are the one tool's two shapes; Crossing is the Bridge tool.
	tabs = [
		{
			"id": &"river",
			"label": "River",
			"tool": ID,
			"shape": WaterBrush.Shape.RIVER,
			"tip": "River: draw it the way it flows, always downhill; a steep drop makes a waterfall",
		},
		{
			"id": &"pond",
			"label": "Pond",
			"tool": ID,
			"shape": WaterBrush.Shape.POND,
			"tip": "Pond: paint a pond or a lake, still water in a basin",
		},
		{
			"id": BridgeTool.ID,
			"label": "Crossing",
			"tool": BridgeTool.ID,
			"tip": "Crossing: a bridge, stepping stones, an arch or a ford over water",
		},
	]
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		["Left Drag (Water)", "River: draw it the way it flows. Pond: paint its area"],
		[
			"Waterfall",
			(
				"A river over a steep drop falls there by itself. Sculpting never makes or moves"
				+ " a fall: erase the river and draw it again"
			),
		],
		["Dry channel", "Erased water leaves its channel: Sculpt's Smooth fills it"],
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> WaterBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as WaterBrush


## Where water can be carved, or the document has water to erase.
func can_select(controller: AuthoringController) -> bool:
	return has_water_work(controller)


func works_on(editor: AuthoringEditor) -> bool:
	return has_water_work_on(editor)


## The falls material and the flow carrier's build now, so the first waterfall drawn and the
## first river's swap pay no shader build (P4c-4; the Bridge tool warms its crossing
## materials the same way).
func prepare(_controller: AuthoringController) -> void:
	AuthoredWater.warm_fall_material()
	AuthoredWater.warm_flow_carrier()


## Fully enabled where water can be carved; erase-only on a dressed map with water painted
## over it; otherwise disabled.
func refresh(controller: AuthoringController) -> void:
	controller.panel.set_water_available(
		controller.editor.water.can_carve(), not controller.document.water_bodies.is_empty()
	)


## True when the open map can be given water (its ground is the document's) or already has
## some in its document. The Bridge tool works on the same maps.
static func has_water_work(controller: AuthoringController) -> bool:
	return controller.editor != null and has_water_work_on(controller.editor)


## has_water_work() of the map `editor` edits.
static func has_water_work_on(editor: AuthoringEditor) -> bool:
	return editor.water.can_carve() or not editor.document.water_bodies.is_empty()
