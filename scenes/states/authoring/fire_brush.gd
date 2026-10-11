class_name FireBrush
extends BrushMode

## The Fire tool's mode (FireTool): an LMB drag lays persistent ground fire with Paint's
## falloff and dwell, the fire mask approaching the pane's intensity; Ctrl at the press puts
## fire out, leaving its ash and snags (AuthoringEditor.begin_fire_stroke, FireEditor). Area is
## the only shape so far; the Line shape and Tab come with card F5 (design section 2). The ring
## is ember orange, red to put out.

const ERASE_TEXT := "Put out fire"
## The pane's intensity tiles, as mask bytes (design section 2).
const EMBERS := 96
const FLAMES := 176
const BLAZE := 255
const TINT := ThemeColors.EMBER

## The mask byte a lay approaches (EMBERS, FLAMES or BLAZE).
var intensity: int = FLAMES


func _init() -> void:
	fades = true


func press(brush: BrushTool) -> bool:
	return brush.editor.begin_fire_stroke(intensity / 255.0, brush.press_ctrl)


## Red while putting out: Ctrl held at the press during a stroke, else Ctrl held now.
func cursor_tint(brush: BrushTool) -> Color:
	return BrushCursor.CLEAR_TINT if _erasing(brush) else TINT


## The red ring names its erase under it ("Put out fire"), as Paint's "Erase paint".
func cursor_text(brush: BrushTool) -> String:
	return ERASE_TEXT if _erasing(brush) else ""


func _erasing(brush: BrushTool) -> bool:
	return brush.press_ctrl if brush.stroking else brush.ctrl
