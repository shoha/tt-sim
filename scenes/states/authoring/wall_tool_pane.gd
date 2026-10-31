class_name WallToolPane
extends VBoxContainer

## The Wall tool's pane in AuthoringPanel: a Stone wall and a Fence tile (one per Wall.Kind) and a
## hint line saying the gesture. No numbers: a wall's height is Shift+wheel. Built in code; every
## interactive Control is named.

## A tile was picked: the wall kind (Wall.Kind).
signal kind_selected(kind: int)
## A species tile was picked (a street's Wall.preset).
signal preset_selected(preset: int)
## The picked street's buttons: split it into buildings, let go of it.
signal split_requested
signal done_requested
## The Dress this street section's requests, passed on from it (SettlementSection).
signal dress_requested(kit: String, wealth: float, density: float)
signal kit_requested(kit: String)
signal feel_requested(wealth: float, density: float)
signal clear_requested

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
const HINT := (
	"Drag along the ground to lay a wall or fence; start the next drag at its end to carry on, and"
	+ " end one at its first end to close the loop. Shift + scroll or [ and ] set the height. A"
	+ " street is dragged along its line: Q and E pick the side, R mixes the buildings afresh, and"
	+ " the height keys set how far back they stand. Click a street to pick it and split it into"
	+ " buildings you can move one by one. Ctrl and click removes one. Single buildings are the"
	+ " Building tool's."
)
const SELECTION_HINT := (
	"This street can be split into separate buildings, each of which you can then move, restyle or"
	+ " remove with the Building tool. The street itself goes. Undo puts it back."
)

var kind_field: TileField
## The species of a street; shown while the Street tile is picked.
var preset_field: TileField
## The picked street's bar: shown in place of nothing while a street is picked.
var selection_box: VBoxContainer
var split_button: Button
var done_button: Button
## The Dress this street section of the picked street's bar.
var settlement_section: SettlementSection


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
	# One tile per procgen street species, named and described by StreetSpeciesInfo.
	for tile in StreetSpeciesInfo.tiles():
		preset_field.tiles.add_tile(
			tile.id, String(tile.label), String(tile.icon), String(tile.tooltip)
		)
	preset_field.tiles.select(&"street_mixed")
	preset_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in StreetSpeciesInfo.tiles():
				if tile.id == id:
					preset_selected.emit(int(tile.preset))
	)
	preset_field.visible = false
	add_child(preset_field)
	_build_selection()


## Selects a kind tile without emitting kind_selected.
func select_kind(kind: int) -> void:
	for tile in KIND_TILES:
		if int(tile.kind) == kind:
			kind_field.tiles.select(tile.id)
	_show_for_kind(kind)


## Shows the fields that choose what the picked kind builds.
func _show_for_kind(kind: int) -> void:
	preset_field.visible = kind == Wall.Kind.ROW


## Shows the bar of the picked street (`wall`, a row of the open document), or with null hides it.
func show_selection(wall: Wall, settlement: Settlement = null) -> void:
	selection_box.visible = wall != null
	settlement_section.show_for(settlement)


## The picked street's bar: what splitting does, the Split button and Done.
func _build_selection() -> void:
	selection_box = VBoxContainer.new()
	selection_box.name = "WallSelection"
	selection_box.theme_type_variation = &"BoxContainerSnug"
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.visible = false
	settlement_section = SettlementSection.new()
	settlement_section.dress_requested.connect(dress_requested.emit)
	settlement_section.kit_requested.connect(kit_requested.emit)
	settlement_section.feel_requested.connect(feel_requested.emit)
	settlement_section.clear_requested.connect(clear_requested.emit)
	selection_box.add_child(settlement_section)
	selection_box.add_child(_caption("WallSelectionHint", SELECTION_HINT))
	split_button = Button.new()
	split_button.name = "WallSplit"
	split_button.text = "Split into buildings"
	split_button.tooltip_text = "Replace the street with its buildings, one Building each"
	split_button.focus_mode = Control.FOCUS_NONE
	split_button.pressed.connect(split_requested.emit)
	selection_box.add_child(split_button)
	done_button = Button.new()
	done_button.name = "WallSelectionDone"
	done_button.text = "Done"
	done_button.tooltip_text = "Let go of the street (Escape)"
	done_button.focus_mode = Control.FOCUS_NONE
	done_button.pressed.connect(done_requested.emit)
	selection_box.add_child(done_button)
	add_child(selection_box)


## Selects a species tile without emitting preset_selected.
func select_preset(preset: int) -> void:
	for tile in StreetSpeciesInfo.tiles():
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
