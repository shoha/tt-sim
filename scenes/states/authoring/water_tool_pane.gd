class_name WaterToolPane
extends VBoxContainer

## The Water tool's pane in AuthoringPanel (phase 4, P4-4): River and Pond tiles, Ankle /
## Waist / Deep tiles with a hint line saying what the depth means for tokens, and an Advanced
## foldout with the exact width and flow speed (values hidden, like the other panes). No
## numbers in the main flow: the width is Shift+wheel, and the depth a tile. On a dressed
## Blender map (set_carves(false)) the tiles are disabled and the hint says why: the tool only
## erases the water painted over it. Built in code; every interactive Control is named.

## A tile was picked: the shape (WaterBrush.Shape) or the depth (WaterBody.Depth).
signal shape_selected(shape: int)
signal depth_selected(depth: int)
## An Advanced row moved: the full width (metres) or the flow speed (WaterBody speed).
signal width_changed(width: float)
signal speed_changed(speed: float)

const TILE_SIZE := Vector2(64, 56)
const SHAPE_TILES: Array[Dictionary] = [
	{
		"shape": WaterBrush.Shape.RIVER,
		"id": &"water_river",
		"label": "River",
		"icon": "ripple",
		"tooltip":
		"Draw a river: it flows the way you draw it, always downhill; a steep drop makes a waterfall",
	},
	{
		"shape": WaterBrush.Shape.POND,
		"id": &"water_pond",
		"label": "Pond",
		"icon": "circle-dashed",
		"tooltip": "Paint a pond or a lake: still water in a basin",
	},
]
const DEPTH_TILES: Array[Dictionary] = [
	{
		"depth": WaterBody.Depth.ANKLE,
		"id": &"water_ankle",
		"label": "Ankle",
		"icon": "shoe",
		"hint": "Ankle deep: a stream tokens wade across.",
	},
	{
		"depth": WaterBody.Depth.WAIST,
		"id": &"water_waist",
		"label": "Waist",
		"icon": "walk",
		"hint": "Waist deep: tokens wade, slowly.",
	},
	{
		"depth": WaterBody.Depth.DEEP,
		"id": &"water_deep",
		"label": "Deep",
		"icon": "swimming",
		"hint": "Deep: tokens swim, floating at the surface.",
	},
]
const HINT := (
	"River: draw its line from where the water comes to where it goes; over a steep drop it"
	+ " falls by itself. Pond: paint an area; start inside a pond to grow it. Shift+wheel or"
	+ " [ and ] set the width. Hold Ctrl as you press to erase water; the ground stays carved"
	+ " (Sculpt's Smooth fills a dry channel). Sculpting never makes or moves a waterfall:"
	+ " erase the river and draw it again."
)
const ERASE_ONLY_HINT := (
	"Rivers and ponds carve the map's own ground, which a Blender map's is not."
	+ " Ctrl+drag still erases the water painted over it."
)

var shape_field: TileField
var depth_field: TileField

var _hint: Label
var _depth_hint: Label
var _width_row: PropertyRow
var _speed_row: PropertyRow


func _init() -> void:
	name = "WaterPane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "WaterHeader"
	header.setup("Water", "Rivers, streams and ponds.")
	add_child(header)
	_hint = _caption("WaterHint", HINT)
	add_child(_hint)
	shape_field = _tiles("WaterShapeField", "Shape", SHAPE_TILES, "tooltip")
	shape_field.tiles.select(&"water_river")
	shape_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in SHAPE_TILES:
				if tile.id == id:
					shape_selected.emit(int(tile.shape))
	)
	add_child(shape_field)
	depth_field = _tiles("WaterDepthField", "Depth", DEPTH_TILES, "hint")
	depth_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in DEPTH_TILES:
				if tile.id == id:
					_depth_hint.text = String(tile.hint)
					depth_selected.emit(int(tile.depth))
	)
	add_child(depth_field)
	_depth_hint = _caption("WaterDepthHint", "")
	add_child(_depth_hint)
	select_depth(WaterBody.Depth.WAIST)
	add_child(_advanced())


## Selects a shape tile without emitting shape_selected.
func select_shape(shape: int) -> void:
	for tile in SHAPE_TILES:
		if int(tile.shape) == shape:
			shape_field.tiles.select(tile.id)


## Selects a depth tile (and its hint) without emitting depth_selected.
func select_depth(depth: int) -> void:
	for tile in DEPTH_TILES:
		if int(tile.depth) == depth:
			depth_field.tiles.select(tile.id)
			_depth_hint.text = String(tile.hint)


## Shows the exact width (metres, the full channel) and flow, without signals.
func set_values(width: float, speed: float) -> void:
	_width_row.set_value_no_signal(width)
	_speed_row.set_value_no_signal(speed)


## Whether water can be carved here: the tiles and the hint follow (see the header).
func set_carves(carves: bool) -> void:
	for field in [shape_field, depth_field]:
		for child in (field as TileField).tiles.get_children():
			if child is Button:
				(child as Button).disabled = not carves
	_hint.text = HINT if carves else ERASE_ONLY_HINT


func _tiles(node_name: String, caption: String, tiles: Array[Dictionary], tip: String) -> TileField:
	var field := TileField.new()
	field.name = node_name
	field.caption = caption
	field.tiles.tile_min_size = TILE_SIZE
	field.tiles.columns = tiles.size()
	for tile in tiles:
		field.tiles.add_tile(tile.id, String(tile.label), String(tile.icon), String(tile[tip]))
	return field


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## The Advanced foldout: exact width (the full channel, twice the brush radius) and flow.
func _advanced() -> Foldout:
	var foldout := Foldout.new()
	foldout.name = "WaterAdvanced"
	foldout.title = "Advanced"
	_width_row = PropertyRow.new()
	_width_row.name = "WaterWidth"
	_width_row.label = "Width"
	_width_row.min_value = 2.0 * WaterBody.MIN_HALF_WIDTH_M
	_width_row.max_value = 2.0 * WaterBody.MAX_HALF_WIDTH_M
	_width_row.step = 0.1
	_width_row.value = 2.0 * BrushTool.session_radius
	_width_row.hint_low = "Stream"
	_width_row.hint_high = "River"
	_width_row.formatter = func(value: float) -> String: return "%.1f m" % value
	_width_row.value_changed.connect(func(value: float) -> void: width_changed.emit(value))
	foldout.add_child(_width_row)
	_speed_row = PropertyRow.new()
	_speed_row.name = "WaterFlow"
	_speed_row.label = "Flow"
	_speed_row.min_value = 0.0
	_speed_row.max_value = WaterBody.MAX_SPEED
	_speed_row.step = 0.05
	_speed_row.value = WaterBody.DEFAULT_SPEED
	_speed_row.hint_low = "Still"
	_speed_row.hint_high = "Rushing"
	_speed_row.value_changed.connect(func(value: float) -> void: speed_changed.emit(value))
	foldout.add_child(_speed_row)
	return foldout
