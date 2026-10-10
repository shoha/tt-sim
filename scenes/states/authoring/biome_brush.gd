class_name BiomeBrush
extends BrushMode

## The Biome tool's mode (BiomeTool): an LMB drag paints `biome_id` onto the document's masks
## (AuthoringEditor.begin_stroke, MaskBrush.PAINT); holding still builds it up. The ring is
## the biome's own colour. AuthoringController._use_biome sets both from the picked tile.

## The biome the brush paints, and the ring's tint (the biome's colour).
var biome_id: String = ""
var tint: Color = Color(0.7, 0.9, 0.6)


func press(brush: BrushTool) -> bool:
	return brush.editor.begin_stroke(MaskBrush.PAINT, biome_id)


func cursor_tint(_brush: BrushTool) -> Color:
	return tint
