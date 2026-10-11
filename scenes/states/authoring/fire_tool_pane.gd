class_name FireToolPane
extends VBoxContainer

## The Fire tool's pane in AuthoringPanel: the gestures in a wrapped hint, an intensity row of
## three tiles (Embers, Flames, Blaze: the mask byte a lay approaches, FireBrush) with a line
## saying what the picked one looks like, and the panel's Advanced foldout (size and strength,
## kept in step with the brush by AuthoringPanel.set_brush_values). The Area / Line shape row
## comes with the Line shape (card F5). Built in code; every interactive Control is named.

## An intensity tile was picked: its mask byte.
signal intensity_selected(intensity: int)

const TILE_SIZE := Vector2(64, 56)
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
	"Drag to lay fire; it keeps burning where you paint it and never spreads. Trees under it"
	+ " burn to snags and the ground to ash. Ctrl+drag puts it out; the ash stays. Shift +"
	+ " scroll or [ and ] set the size."
)

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
