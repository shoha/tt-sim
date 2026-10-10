class_name ThinTool
extends ToolDescriptor

## The Thin / Clear tool: thins trees and plants out, or with Ctrl at the press clears the
## ground completely (ThinBrush; MaskBrush.THIN and CLEAR). It works on a Blender map's own
## scatter too, so it is always available. Its pane is AuthoringPanel's.

const ID := &"thin_clear"


func _init() -> void:
	id = ID
	label = "Thin / Clear"
	summary = "Open up what grows."
	icon = "eraser"
	brush_mode = ThinBrush
	contexts = AUTHORING | PLAY
