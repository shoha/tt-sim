class_name ShapeField
extends RefCounted

## The Shape field of every brush with two shapes (Water's River and Pond, Fire's Line and
## Area, Start a fire's Path and Circle): a TileField captioned "Shape" over one row of two
## icon tiles at TILE_SIZE, the line shape first with the river's icon and the area shape
## second with the pond's, each tile's tooltip saying what its shape does. Tab switches between
## them (BrushMode.toggle_shape). One builder for every pane, so they cannot drift (UI_TASTE
## "Fewer UI and UX primitives"; design: docs/plans/2026-10-11-fire-features/design.md
## section 2, "One Shape field").

const CAPTION := "Shape"
const TILE_SIZE := Vector2(64, 56)
## A line shape's picture (Water's River, Fire's Line), and an area shape's.
const LINE_ICON := "ripple"
const AREA_ICON := "circle-dashed"


## A Shape field named `node_name`: `line` and `area` are {"id", "label", "tooltip"} for the
## line shape's tile and the area shape's. Nothing is selected; the pane selects its mode's
## shape.
static func build(node_name: String, line: Dictionary, area: Dictionary) -> TileField:
	var field := TileField.new()
	field.name = node_name
	field.caption = CAPTION
	field.tiles.tile_min_size = TILE_SIZE
	field.tiles.columns = 2
	field.tiles.add_tile(line.id, String(line.label), LINE_ICON, String(line.tooltip))
	field.tiles.add_tile(area.id, String(area.label), AREA_ICON, String(area.tooltip))
	return field
