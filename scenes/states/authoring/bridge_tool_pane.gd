class_name BridgeToolPane
extends VBoxContainer

## The Bridge tool's pane in AuthoringPanel (phase 4b, P4b-2): Plank bridge and Stepping
## stones tiles (room for a stone arch later) and a hint line saying the gesture. No numbers:
## a crossing sizes itself to the water it spans, and its width is Shift+wheel. On a map
## without water to cross the hint says to make some first (set_has_water). Built in code;
## every interactive Control is named.

## A tile was picked: the crossing kind (Crossing.Kind).
signal kind_selected(kind: int)

const TILE_SIZE := Vector2(64, 56)
const KIND_TILES: Array[Dictionary] = [
	{
		"kind": Crossing.Kind.PLANK,
		"id": &"bridge_plank",
		"label": "Planks",
		"icon": "bridge-plank",
		"tooltip": "A plank footbridge: arched boards on posts, bank to bank",
	},
	{
		"kind": Crossing.Kind.STONES,
		"id": &"bridge_stones",
		"label": "Stones",
		"icon": "stepping-stones",
		"tooltip": "Stepping stones: flat rocks one stride apart, just above the water",
	},
]
const HINT := (
	"Drag a line across a river or pond, from one bank to the other: the crossing finds the"
	+ " banks and sizes itself. Bridges cross calm water, not a waterfall. Shift+wheel or"
	+ " [ and ] set its width. Hold Ctrl and click a crossing to remove it. A crossing follows"
	+ " later edits to its banks and goes when its water does."
)
const NO_WATER_HINT := "Make a river or a pond with the Water tool first, then drag across it here."

var kind_field: TileField

var _hint: Label
var _water_hint: Label


func _init() -> void:
	name = "BridgePane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "BridgeHeader"
	header.setup("Bridge", "Cross water on planks or stones.")
	add_child(header)
	_hint = _caption("BridgeHint", HINT)
	add_child(_hint)
	kind_field = TileField.new()
	kind_field.name = "BridgeKindField"
	kind_field.caption = "Crossing"
	kind_field.tiles.tile_min_size = TILE_SIZE
	kind_field.tiles.columns = 3
	for tile in KIND_TILES:
		kind_field.tiles.add_tile(
			tile.id, String(tile.label), String(tile.icon), String(tile.tooltip)
		)
	kind_field.tiles.select(&"bridge_plank")
	kind_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			for tile in KIND_TILES:
				if tile.id == id:
					kind_selected.emit(int(tile.kind))
	)
	add_child(kind_field)
	_water_hint = _caption("BridgeWaterHint", NO_WATER_HINT)
	_water_hint.visible = false
	add_child(_water_hint)


## Selects a kind tile without emitting kind_selected.
func select_kind(kind: int) -> void:
	for tile in KIND_TILES:
		if int(tile.kind) == kind:
			kind_field.tiles.select(tile.id)


## Shows the line saying to make water first while the map has none.
func set_has_water(has_water: bool) -> void:
	_water_hint.visible = not has_water


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
