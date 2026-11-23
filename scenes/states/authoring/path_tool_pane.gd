class_name PathToolPane
extends VBoxContainer

## The Path tool's pane (the Paint hub's Path tab; PathTool): the gestures in a wrapped hint, a
## Width row of three tiles (Footpath, Track, Lane: the path's width in metres, PathBrush.width;
## Shift+wheel steps between and past them) and a line naming the surface the path paints, the
## Paint tab's pick. Built in code; every interactive Control is named.

## A width tile was picked: the path's width (world metres).
signal width_selected(width: float)

const TILE_SIZE := Vector2(64, 40)
const WIDTH_TILES: Array[Dictionary] = [
	{
		"width": 1.0,
		"id": &"path_footpath",
		"label": "Footpath",
		"tip": "Footpath: one walker wide (1 m)",
	},
	{
		"width": 1.6,
		"id": &"path_track",
		"label": "Track",
		"tip": "Track: two abreast (1.6 m)",
	},
	{
		"width": 3.0,
		"id": &"path_lane",
		"label": "Lane",
		"tip": "Lane: a cart's width (3 m)",
	},
]
const HINT := "Draw a path along the ground: it settles into the slope."
const HINT_MORE := (
	"Steep ground gets steps, and a path into a river wades it at a ford. Shift + scroll or [ and ]"
	+ " set the width. Hold Ctrl as you press to erase the paths the line crosses."
)
const SURFACE_TEXT := "Paints %s: pick another surface in the Paint tab."
const NO_SURFACE_TEXT := "Pick a surface in the Paint tab: the path paints it."

var width_field: TileField

var _surface_label: Label


func _init() -> void:
	name = "PathPane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "PathHeader"
	var tool := ToolRegistry.find(PathTool.ID)
	header.setup(tool.label, tool.summary)
	add_child(header)
	add_child(_caption("PathHint", HINT))
	add_child(AuthoringChrome.more_foldout("PathHintMore", HINT_MORE))
	width_field = TileField.new()
	width_field.name = "PathWidthField"
	width_field.caption = "Width"
	width_field.tiles.tile_min_size = TILE_SIZE
	width_field.tiles.columns = WIDTH_TILES.size()
	for tile in WIDTH_TILES:
		width_field.tiles.add_tile(tile.id, String(tile.label), "", String(tile.tip))
	width_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in WIDTH_TILES:
				if tile.id == id:
					width_selected.emit(float(tile.width))
	)
	add_child(width_field)
	_surface_label = _caption("PathSurface", NO_SURFACE_TEXT)
	add_child(_surface_label)
	select_width(1.6)


## Names the surface the path paints (a palette surface id; "" for none).
func show_surface(surface: String) -> void:
	_surface_label.text = (
		NO_SURFACE_TEXT
		if surface == ""
		else SURFACE_TEXT % AuthoringPanel.surface_label(surface).to_lower()
	)


## Selects the width tile of `width` metres without emitting width_selected (none when a
## Shift+wheel left it between tiles).
func select_width(width: float) -> void:
	var picked: StringName = &""
	for tile in WIDTH_TILES:
		if is_equal_approx(float(tile.width), width):
			picked = tile.id
	width_field.tiles.select(picked)


## The text the surface line shows (tests).
func surface_text() -> String:
	return _surface_label.text


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
