class_name PlaceTool
extends ToolDescriptor

## The Place tool: sets one hero tree, rock or log where the author clicks (PlaceBrush; props
## are PropRows rows in AuthoredProps). Its pane is AuthoringPanel's species tiles, one group
## per palette biome; a tile picked there is the rule the next click places
## (AuthoringController._on_place_selected). Removing and resizing the prop under the cursor
## are in the help overlay's shared rows.

const ID := &"place"
## The label of the first tab (the tool itself stays Place: rail tooltip, key P, pane title).
const ADD_LABEL := "Add"


func _init() -> void:
	id = ID
	label = "Place"
	summary = "Set a hero tree, rock or log."
	icon = "map-pin"
	brush_mode = PlaceBrush
	shortcut = KEY_P
	# Thin / Clear is Place's erase mode: its own tool and brush, a tab of this one on the rail. The
	# first tab says "Add", not "Place": a card titled Place whose tab is also Place read as the
	# same word twice (owner, 2026-11-16, on l21_hubs).
	tabs = [
		{
			"id": ID,
			"label": ADD_LABEL,
			"tool": ID,
			"tip": "Add: set a hero tree, rock or log where you click",
		},
		{
			"id": ThinTool.ID,
			"label": "Thin / Clear",
			"tool": ThinTool.ID,
			"tip": "Thin / Clear: brush away trees and plants (Ctrl: clear the ground)",
		},
	]


## The tool's mode on `brush`.
static func of(brush: BrushTool) -> PlaceBrush:
	return brush.mode_for(ToolRegistry.find(ID)) as PlaceBrush
