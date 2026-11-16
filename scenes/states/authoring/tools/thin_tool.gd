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
	on_rail = false
	hub = PlaceTool.ID
	contexts = AUTHORING | PLAY


## The pane: the header, the gestures and the Advanced foldout (size and strength).
func build_pane(panel: AuthoringPanel) -> Control:
	var pane := VBoxContainer.new()
	pane.name = "ThinPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "ThinHeader"
	header.setup(label, summary)
	pane.add_child(header)
	pane.add_child(panel.build_size_row("Thin"))
	pane.add_child(
		AuthoringChrome.help_label(
			"ThinHint", "Drag to thin trees and plants out; hold Ctrl to clear the ground completely."
		)
	)
	pane.add_child(panel.build_advanced("Thin"))
	return pane
