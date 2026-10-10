class_name BridgeTool
extends ToolDescriptor

## The Bridge tool: a line dragged across water, bank to bank, lays planks, stepping stones,
## an arch or a ford, and Ctrl+click removes one (BridgeBrush does the gesture,
## CrossingEditor the plan). Its pane is BridgeToolPane, which AuthoringPanel builds
## and relays. Crossings snap to the document's water, so the tool works wherever the Water
## tool does (WaterTool.has_water_work) and is disabled with a tooltip elsewhere.

const ID := &"bridge"
const LABEL := "Bridge"
const UNAVAILABLE_TOOLTIP := (
	"Bridge: crosses water made with the Water tool; a Blender map's own water is part of the"
	+ " map file"
)


func _init() -> void:
	id = ID
	label = LABEL
	summary = "Cross water on planks, stones, an arch or a ford."
	icon = "building-bridge"
	brush_mode = BridgeBrush
	contexts = AUTHORING | PLAY
	unavailable_tooltip = UNAVAILABLE_TOOLTIP
	help = [
		[
			"Left Drag (Bridge)",
			"Drag across calm water, bank to bank: planks, stones, an arch or a ford",
		],
		["Arch (Bridge)", "A stone arch crosses like planks: the biome's rock, a paved deck"],
		[
			"Ford (Bridge)",
			"A gravel bar for wading: needs wadeable water; its width runs along the river",
		],
		["Ctrl + Click (Bridge)", "Remove the crossing under the cursor"],
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> BridgeBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as BridgeBrush


## Where water can be made or the document has some.
func can_select(controller: AuthoringController) -> bool:
	return WaterTool.has_water_work(controller)


func works_on(editor: AuthoringEditor) -> bool:
	return WaterTool.has_water_work_on(editor)


## Starts the open map's crossing textures and materials once (AuthoringController
## .warm_crossings), so the first placement pays for neither.
func prepare(controller: AuthoringController) -> void:
	controller.warm_crossings()


## Enabled where crossings can snap to water; the pane says to make water first while the
## document has none.
func refresh(controller: AuthoringController) -> void:
	controller.panel.set_bridge_available(
		can_select(controller), not controller.document.water_bodies.is_empty()
	)
