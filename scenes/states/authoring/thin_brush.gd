class_name ThinBrush
extends BrushMode

## The Thin / Clear tool's mode (ThinTool): an LMB drag thins what grows; with Ctrl held at
## the press it clears the ground completely (AuthoringEditor.begin_stroke, MaskBrush.THIN or
## CLEAR). The ring is warm white to thin and red to clear, and the canopy over it fades so
## the ground being thinned stays in view.

const THIN_TINT := Color(0.98, 0.93, 0.82)


func _init() -> void:
	fades = true


func press(brush: BrushTool) -> bool:
	return brush.editor.begin_stroke(MaskBrush.CLEAR if brush.press_ctrl else MaskBrush.THIN)


## Red while clearing: Ctrl held at the press during a stroke, else Ctrl held now.
func cursor_tint(brush: BrushTool) -> Color:
	var clearing := brush.press_ctrl if brush.stroking else brush.ctrl
	return BrushCursor.CLEAR_TINT if clearing else THIN_TINT
