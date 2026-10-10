class_name BiomeTool
extends ToolDescriptor

## The Biome tool: paints a palette biome onto the map (BiomeBrush; MaskStroke on the
## document's masks). Its pane is AuthoringPanel's biome tiles, and a tile picked there
## becomes the brush's paint (AuthoringController._use_biome). Until one is picked the brush
## has nothing to paint with, so picking the tool leaves it put down.

const ID := &"biome"


func _init() -> void:
	id = ID
	label = "Biome"
	summary = "Paint a place onto the map."
	icon = "trees"
	brush_mode = BiomeBrush
	contexts = AUTHORING | PLAY


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> BiomeBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as BiomeBrush


## Armed once a biome is picked.
func armed(controller: AuthoringController) -> bool:
	return controller.selected_biome != ""
