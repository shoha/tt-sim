class_name SculptBrush
extends BrushMode

## The Sculpt tool's mode (SculptTool): an LMB drag runs the picked tile's operation
## (sculpt_op(): Raise, Smooth, Flatten, Tier) on the document's heights
## (AuthoringEditor.begin_height_stroke). Ctrl at the press lowers (Raise) or cuts a tier down
## (Tier); Shift at the press smooths whichever tile is picked. Flatten holds the ground height
## under the press; Tier builds toward the tier AuthoringEditor.tier_target() picks at the
## press.
##
## Cursor. The ring follows the document's own heights every frame (the ground under a still
## ring moves while sculpting) and is tinted sand to raise, blue-grey to lower, pale green to
## smooth and ember to flatten. Tier and Flatten show a small readout under it: the tier the
## stroke builds and its elevation in the level's units ("Tier 1  +5 ft"), or the height
## Flatten holds. Hovering, the tier a press would build is looked up once per brush sample.

const RAISE_TINT := Color(1.0, 0.86, 0.62)
const LOWER_TINT := Color(0.66, 0.78, 1.0)
const SMOOTH_TINT := Color(0.86, 0.96, 0.9)

## The tile picked: HeightBrush.RAISE, SMOOTH, FLATTEN or TIER (sculpt_op() applies the
## modifiers).
var tile: int = HeightBrush.RAISE

## The stroke in progress: its HeightBrush operation (-1: none) and target (world Y; tier
## level for Tier), for the tint and the readout.
var _stroke_op: int = -1
var _stroke_target_y: float = 0.0
var _stroke_level: int = 0
## Tier readout while hovering, recomputed when the sample under the brush, the radius or
## Ctrl change: {"key": Array, "level": int}.
var _tier_hover: Dictionary = {}


func _init() -> void:
	fades = true


## The HeightBrush operation a Sculpt press makes with tile `tile_op` picked and Ctrl / Shift
## held at the press: Shift smooths from any tile; Ctrl lowers with Raise and cuts with Tier
## (Smooth and Flatten have no Ctrl variant). Pure.
static func sculpt_op(tile_op: int, ctrl: bool, shift: bool) -> int:
	if shift:
		return HeightBrush.SMOOTH
	match tile_op:
		HeightBrush.RAISE, HeightBrush.LOWER:
			return HeightBrush.LOWER if ctrl else HeightBrush.RAISE
		HeightBrush.TIER, HeightBrush.TIER_CUT:
			return HeightBrush.TIER_CUT if ctrl else HeightBrush.TIER
		HeightBrush.FLATTEN:
			return HeightBrush.FLATTEN
	return HeightBrush.SMOOTH


## A height (metres above the map's base ground) in the level's display units, signed:
## "+5 ft", "0 ft", "-10 ft". Pure.
static func format_elevation(
	height_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var value := roundi(ScaleUtils.world_to_display(height_m, cell_m, per_cell))
	if value == 0:
		return "0 %s" % label
	return "%+d %s" % [value, label]


## The readout under the ring for a Tier stroke toward tier `level` of height `height_m`
## ("Tier 1  +5 ft"; level 0 reads "Ground"), in the given units. Pure.
static func tier_readout(
	level: int, height_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var title := "Ground" if level == 0 else "Tier %d" % level
	return "%s  %s" % [title, format_elevation(height_m, cell_m, per_cell, label)]


## Starts the stroke of the picked tile and the press's modifiers, with its target: the
## ground height under the press for Flatten, the tier tier_target() picks for Tier.
func press(brush: BrushTool) -> bool:
	var editor := brush.editor
	var op := sculpt_op(tile, brush.press_ctrl, brush.press_shift)
	var target_y := 0.0
	_stroke_level = 0
	if op == HeightBrush.FLATTEN:
		target_y = editor.ground_height_at(brush.hit)
	elif HeightBrush.is_tier(op):
		var tier := editor.tier_target(brush.hit, brush.get_radius(), op == HeightBrush.TIER_CUT)
		target_y = tier.y
		_stroke_level = tier.level
	if not editor.begin_height_stroke(op, target_y):
		return false
	_stroke_op = op
	_stroke_target_y = target_y
	return true


func end(_brush: BrushTool) -> void:
	_stroke_op = -1


func cancel(_brush: BrushTool) -> void:
	_stroke_op = -1


func cursor_tint(brush: BrushTool) -> Color:
	match _cursor_op(brush):
		HeightBrush.RAISE, HeightBrush.TIER:
			return RAISE_TINT
		HeightBrush.LOWER, HeightBrush.TIER_CUT:
			return LOWER_TINT
		HeightBrush.FLATTEN:
			return BrushCursor.PLACE_TINT
	return SMOOTH_TINT


## The Tier or Flatten readout for the cursor now, or "" (other operations show none).
func cursor_text(brush: BrushTool) -> String:
	var op := _cursor_op(brush)
	if HeightBrush.is_tier(op):
		var level := _stroke_level if _stroke_op >= 0 else _hover_tier_level(brush, op)
		var tier_m := brush.editor.document.tier_height_m if brush.editor != null else brush.unit_cell_m
		return tier_readout(
			level,
			HeightBrush.tier_height(level, tier_m),
			brush.unit_cell_m,
			brush.unit_per_cell,
			brush.unit_label
		)
	if op == HeightBrush.FLATTEN:
		var y := _stroke_target_y if _stroke_op >= 0 else brush.hit.y
		return (
			"Flatten  "
			+ format_elevation(y, brush.unit_cell_m, brush.unit_per_cell, brush.unit_label)
		)
	return ""


## The ring on the document's heights where the ground is the document's.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	var live := brush.editor != null and brush.editor.can_sculpt()
	cursor.draw_ring(brush, cursor_tint(brush), cursor_text(brush), live)


## The operation the cursor stands for: the stroke's while one is held, else what a press
## would make now (the modifiers held at this moment).
func _cursor_op(brush: BrushTool) -> int:
	if _stroke_op >= 0:
		return _stroke_op
	return sculpt_op(tile, brush.ctrl, brush.shift)


## The tier a press here would build (cached per brush sample, radius and Ctrl).
func _hover_tier_level(brush: BrushTool, op: int) -> int:
	var editor := brush.editor
	if editor == null:
		return 0
	var at := editor.document.world_to_sample(editor.to_map_xz(brush.hit)).round()
	var key := [at, brush.get_radius(), op]
	if _tier_hover.get("key") != key:
		var tier := editor.tier_target(brush.hit, brush.get_radius(), op == HeightBrush.TIER_CUT)
		_tier_hover = {"key": key, "level": tier.level}
	return int(_tier_hover.level)
