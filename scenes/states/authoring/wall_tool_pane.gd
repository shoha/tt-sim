class_name WallToolPane
extends VBoxContainer

## The Wall tool's pane in AuthoringPanel: a Stone wall and a Fence tile (one per Wall.Kind) and a
## hint line saying the gesture. No numbers: a wall's height is Shift+wheel. Built in code; every
## interactive Control is named.

## A tile was picked: the wall kind (Wall.Kind).
signal kind_selected(kind: int)
## A species tile was picked (a street's Wall.preset).
signal preset_selected(preset: int)
## A building's walls or roof tile was picked: the style (Wall.preset) the two give together.
signal style_selected(style: int)

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
	{
		"kind": Wall.Kind.ROW,
		"id": &"wall_row",
		"label": "Street",
		"icon": "street",
		"tooltip":
		"A street of varied buildings, doors to the street: drag along where the street runs",
	},
]
## The streets' species, one tile each (ProcgenRow.PRESET_NAMES order).
const PRESET_TILES: Array[Dictionary] = [
	{
		"preset": 0,
		"id": &"street_mixed",
		"label": "Mixed",
		"icon": "street",
		"tooltip": "A bit of everything: houses of different sizes, a gap here and there",
	},
	{
		"preset": 1,
		"id": &"street_terrace",
		"label": "Terrace",
		"icon": "grid-dots",
		"tooltip": "A terrace: tall narrow houses wall to wall, no yards",
	},
	{
		"preset": 2,
		"id": &"street_guild",
		"label": "Guild",
		"icon": "chess",
		"tooltip": "Guild houses: wide, tall, gable-fronted, almost touching",
	},
	{
		"preset": 3,
		"id": &"street_village",
		"label": "Village",
		"icon": "fence",
		"tooltip": "A village: houses with fenced yards, gates to the street, gaps between",
	},
	{
		"preset": 4,
		"id": &"street_cottages",
		"label": "Cottages",
		"icon": "home",
		"tooltip": "Cottages: small low houses far apart, each with a low stone-walled yard",
	},
]
## A building's walls, in Wall.preset order (walls * Wall.BUILDING_ROOFS + roof).
const WALLS_TILES: Array[Dictionary] = [
	{
		"id": &"walls_stone",
		"label": "Stone",
		"icon": "wall",
		"tooltip": "Dry-stone walls of the biome's rock",
	},
	{
		"id": &"walls_timber",
		"label": "Timber",
		"icon": "fence",
		"tooltip": "Vertical boards: lighter and cheaper than stone",
	},
]
const ROOF_TILES: Array[Dictionary] = [
	{
		"id": &"roof_gable",
		"label": "Gable",
		"icon": "home",
		"tooltip": "Two slopes to a ridge, the ends closed in stone",
	},
	{
		"id": &"roof_hip",
		"label": "Hip",
		"icon": "grid-dots",
		"tooltip": "Four slopes meeting in a ridge",
	},
	{
		"id": &"roof_flat",
		"label": "Flat",
		"icon": "chess",
		"tooltip": "A single flat slab over the walls",
	},
]
const HINT := (
	"Drag along the ground to lay a wall or fence; start the next drag at its end to carry on, and"
	+ " end one at its first end to close the loop. Shift + scroll or [ and ] set the height. A"
	+ " street is dragged along its line: Q and E pick the side, R mixes the buildings afresh, and"
	+ " the height keys set how far back they stand. Ctrl and click removes one. Single buildings"
	+ " are the Building tool's."
)

var kind_field: TileField
## The species of a street; shown while the Street tile is picked.
var preset_field: TileField
## A building's walls and its roof; shown while the Building tile is picked.
var walls_field: TileField
var roof_field: TileField


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
					_show_for_kind(int(tile.kind))
					kind_selected.emit(int(tile.kind))
	)
	add_child(kind_field)
	preset_field = TileField.new()
	preset_field.name = "WallPresetField"
	preset_field.caption = "Street"
	preset_field.tiles.tile_min_size = TILE_SIZE
	preset_field.tiles.columns = 3
	for tile in PRESET_TILES:
		preset_field.tiles.add_tile(
			tile.id, String(tile.label), String(tile.icon), String(tile.tooltip)
		)
	preset_field.tiles.select(&"street_mixed")
	preset_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in PRESET_TILES:
				if tile.id == id:
					preset_selected.emit(int(tile.preset))
	)
	preset_field.visible = false
	add_child(preset_field)
	walls_field = _style_field("WallBuildingWalls", "Walls", WALLS_TILES, &"walls_stone")
	roof_field = _style_field("WallBuildingRoof", "Roof", ROOF_TILES, &"roof_gable")
	walls_field.visible = false
	roof_field.visible = false
	add_child(walls_field)
	add_child(roof_field)


## Selects a kind tile without emitting kind_selected.
func select_kind(kind: int) -> void:
	for tile in KIND_TILES:
		if int(tile.kind) == kind:
			kind_field.tiles.select(tile.id)
	_show_for_kind(kind)


## Shows the fields that choose what the picked kind builds.
func _show_for_kind(kind: int) -> void:
	preset_field.visible = kind == Wall.Kind.ROW
	walls_field.visible = kind == Wall.Kind.BUILDING
	roof_field.visible = kind == Wall.Kind.BUILDING


## Selects a building's style (walls * Wall.BUILDING_ROOFS + roof) without emitting.
func select_style(style: int) -> void:
	var walls := clampi(style / Wall.BUILDING_ROOFS, 0, WALLS_TILES.size() - 1)
	var roof := clampi(style % Wall.BUILDING_ROOFS, 0, ROOF_TILES.size() - 1)
	walls_field.tiles.select(WALLS_TILES[walls].id)
	roof_field.tiles.select(ROOF_TILES[roof].id)


## The style the two building fields give together.
func current_style() -> int:
	var walls := 0
	var roof := 0
	for k in WALLS_TILES.size():
		if walls_field.tiles.selected == WALLS_TILES[k].id:
			walls = k
	for k in ROOF_TILES.size():
		if roof_field.tiles.selected == ROOF_TILES[k].id:
			roof = k
	return walls * Wall.BUILDING_ROOFS + roof


func _style_field(
	field_name: String, caption: String, tiles: Array[Dictionary], first: StringName
) -> TileField:
	var field := TileField.new()
	field.name = field_name
	field.caption = caption
	field.tiles.tile_min_size = TILE_SIZE
	field.tiles.columns = tiles.size()
	for tile in tiles:
		field.tiles.add_tile(tile.id, String(tile.label), String(tile.icon), String(tile.tooltip))
	field.tiles.select(first)
	field.tiles.selection_changed.connect(
		func(_id: StringName) -> void: style_selected.emit(current_style())
	)
	return field


## Selects a species tile without emitting preset_selected.
func select_preset(preset: int) -> void:
	for tile in PRESET_TILES:
		if int(tile.preset) == preset:
			preset_field.tiles.select(tile.id)


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
