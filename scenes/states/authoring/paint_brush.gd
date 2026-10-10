class_name PaintBrush
extends BrushMode

## The Paint tool's mode (PaintTool): an LMB drag paints `surface` with a soft falloff, and
## holding still builds it up to full cover; Ctrl at the press erases every painted surface
## back to the automatic ground (AuthoringEditor.begin_surface_stroke). A press the editor
## refuses (every paint slot holds paint) emits the brush's `refused` with
## AuthoringEditor.surface_refusal's reason. The ring is the surface's colour, red to erase.

## The palette surface the brush paints, and the ring's tint.
var surface: String = ""
var tint: Color = Color(0.9, 0.82, 0.66)


func _init() -> void:
	fades = true


func press(brush: BrushTool) -> bool:
	if brush.editor.begin_surface_stroke(surface, brush.press_ctrl):
		return true
	if not brush.press_ctrl:
		var reason := brush.editor.surface_refusal(surface)
		if reason != "":
			brush.refused.emit(reason)
	return false


## Red while erasing: Ctrl held at the press during a stroke, else Ctrl held now.
func cursor_tint(brush: BrushTool) -> Color:
	var erasing := brush.press_ctrl if brush.stroking else brush.ctrl
	return BrushCursor.CLEAR_TINT if erasing else tint
