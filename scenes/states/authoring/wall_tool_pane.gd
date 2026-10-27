class_name WallToolPane
extends VBoxContainer

## The Wall tool's pane in AuthoringPanel: a Stone wall and a Fence tile (one per Wall.Kind) and a
## hint line saying the gesture. No numbers: a wall's height is Shift+wheel. Built in code; every
## interactive Control is named.

## A tile was picked: the wall kind (Wall.Kind).
signal kind_selected(kind: int)

const TILE_SIZE := Vector2(64, 56)
const KIND_TILES: Array[Dictionary] = [
	{
		"kind": Wall.Kind.STONE,
		"id": &"wall_stone",
		"label": "Stone",
		"icon": "wall",
		"tooltip": "A dry-stone wall of the biome's rock, topped with coping stones",
	},
	{
		"kind": Wall.Kind.FENCE,
		"id": &"wall_fence",
		"label": "Fence",
		"icon": "fence",
		"tooltip": "A post and rail fence: posts every couple of metres, two rails between",
	},
]
const HINT := (
	"Drag along the ground to lay a side. Start the next drag at the end of a wall to carry on, and"
	+ " end one at the wall's first end to close the loop. Shift + scroll or [ and ] set the"
	+ " height. Hold Ctrl and click a wall to remove it. A wall follows later edits to the ground"
	+ " under it."
)

var kind_field: TileField


func _init() -> void:
	name = "WallPane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SPACE_2, the step every tool pane keeps between its parts.
	theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "WallHeader"
	var tool := ToolRegistry.find(WallTool.ID)
	header.setup(tool.label, tool.summary)
	add_child(header)
	add_child(_caption("WallHint", HINT))
	kind_field = TileField.new()
	kind_field.name = "WallKindField"
	kind_field.caption = "Kind"
	kind_field.tiles.tile_min_size = TILE_SIZE
	kind_field.tiles.columns = KIND_TILES.size()
	for tile in KIND_TILES:
		kind_field.tiles.add_tile(
			tile.id, String(tile.label), String(tile.icon), String(tile.tooltip)
		)
	kind_field.tiles.select(&"wall_stone")
	kind_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in KIND_TILES:
				if tile.id == id:
					kind_selected.emit(int(tile.kind))
	)
	add_child(kind_field)


## Selects a kind tile without emitting kind_selected.
func select_kind(kind: int) -> void:
	for tile in KIND_TILES:
		if int(tile.kind) == kind:
			kind_field.tiles.select(tile.id)


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
