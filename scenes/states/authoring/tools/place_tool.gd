class_name PlaceTool
extends ToolDescriptor

## The Place tool: sets one hero tree, rock or log where the author clicks (BrushTool.Mode.PLACE;
## props are PropRows rows in AuthoredProps). Its pane is AuthoringPanel's species tiles, one
## group per palette biome; a tile picked there is the rule the next click places
## (AuthoringController._on_place_selected). Removing and resizing the prop under the cursor
## are in the help overlay's shared rows.

const ID := &"place"


func _init() -> void:
	id = ID
	label = "Place"
	summary = "Set a hero tree, rock or log."
	icon = "tree"
	brush_mode = BrushTool.Mode.PLACE
