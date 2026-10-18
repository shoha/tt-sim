class_name FireToolPane
extends VBoxContainer

## The Fire tool's pane in AuthoringPanel: the gestures in a wrapped hint, the Shape field
## (ShapeField: Line, then Area; Tab switches them too, and select_shape() follows it), an
## intensity row of three tiles (Embers, Flames, Blaze: the mask byte a lay approaches,
## FireBrush) with a line saying what the picked one looks like, and the panel's Advanced
## foldout (size and strength, kept in step with the brush by AuthoringPanel.set_brush_values).
## Built in code; every interactive Control is named.

## A shape tile was picked: its FireBrush.Shape.
signal shape_selected(shape: int)
## An intensity tile was picked: its mask byte.
signal intensity_selected(intensity: int)

const TILE_SIZE := Vector2(64, 56)
## The Shape field's tiles (ShapeField: the line shape first, its icons ShapeField's).
const SHAPE_TILES: Array[Dictionary] = [
	{
		"shape": FireBrush.Shape.LINE,
		"id": &"fire_line",
		"label": "Line",
		"tooltip": "Draw a line of fire: it burns evenly along the line you draw",
	},
	{
		"shape": FireBrush.Shape.AREA,
		"id": &"fire_area",
		"label": "Area",
		"tooltip": "Paint fire over an area: linger to build it up",
	},
]
const INTENSITY_TILES: Array[Dictionary] = [
	{
		"intensity": FireBrush.EMBERS,
		"id": &"fire_embers",
		"label": "Embers",
		"icon": "sparkles",
		"hint": "Embers: a low smoulder, glowing and sparking.",
	},
	{
		"intensity": FireBrush.FLAMES,
		"id": &"fire_flames",
		"label": "Flames",
		"icon": "flame",
		"hint": "Flames: a fire burning steadily.",
	},
	{
		"intensity": FireBrush.BLAZE,
		"id": &"fire_blaze",
		"label": "Blaze",
		"icon": "campfire",
		"hint": "Blaze: tall flames at the heart of a fire.",
	},
]
const HINT := (
	"Line: drag a line of fire. Area: paint it; linger to build it up. Shift + scroll or"
	+ " [ and ] set the width. Hold Ctrl as you press to put fire out; the ash stays. Tab"
	+ " switches the shape."
)

var shape_field: TileField
var intensity_field: TileField

var _intensity_hint: Label


func _init(panel: AuthoringPanel = null) -> void:
	name = "FirePane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SPACE_2, the step every tool pane keeps between its parts.
	theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "FireHeader"
	var tool := ToolRegistry.find(FireTool.ID)
	header.setup(tool.label, tool.summary)
	add_child(header)
	add_child(_caption("FireHint", HINT))
	shape_field = ShapeField.build("FireShapeField", SHAPE_TILES[0], SHAPE_TILES[1])
	select_shape(FireBrush.Shape.AREA)
	shape_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in SHAPE_TILES:
				if tile.id == id:
					shape_selected.emit(int(tile.shape))
	)
	add_child(shape_field)
	intensity_field = TileField.new()
	intensity_field.name = "FireIntensityField"
	intensity_field.caption = "Intensity"
	intensity_field.tiles.tile_min_size = TILE_SIZE
	intensity_field.tiles.columns = INTENSITY_TILES.size()
	for tile in INTENSITY_TILES:
		intensity_field.tiles.add_tile(
			tile.id, String(tile.label), String(tile.icon), String(tile.hint)
		)
	intensity_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in INTENSITY_TILES:
				if tile.id == id:
					_intensity_hint.text = String(tile.hint)
					intensity_selected.emit(int(tile.intensity))
	)
	add_child(intensity_field)
	_intensity_hint = _caption("FireIntensityHint", "")
	add_child(_intensity_hint)
	select_intensity(FireBrush.FLAMES)
	if panel != null:
		add_child(panel.build_advanced("Fire"))


## Selects a shape tile (FireBrush.Shape) without emitting shape_selected.
func select_shape(shape: int) -> void:
	for tile in SHAPE_TILES:
		if int(tile.shape) == shape:
			shape_field.tiles.select(tile.id)


## Selects an intensity tile (and its hint) without emitting intensity_selected.
func select_intensity(intensity: int) -> void:
	for tile in INTENSITY_TILES:
		if int(tile.intensity) == intensity:
			intensity_field.tiles.select(tile.id)
			_intensity_hint.text = String(tile.hint)


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
