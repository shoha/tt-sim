class_name WaterTool
extends ToolDescriptor

## The Water tool: rivers drawn the way they flow and ponds painted as areas, carved into the
## document's own ground, and Ctrl to erase (BrushTool.Mode.WATER; WaterBrush does the
## gestures, WaterEditor the carve). Its pane is WaterToolPane, which AuthoringPanel builds and
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
	brush_mode = BrushTool.Mode.WATER
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


## Where water can be carved, or the document has water to erase.
func can_select(controller: AuthoringController) -> bool:
	return has_water_work(controller)


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
	if controller.editor == null:
		return false
	return controller.editor.water.can_carve() or not controller.document.water_bodies.is_empty()
