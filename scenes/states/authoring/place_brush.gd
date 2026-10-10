class_name PlaceBrush
extends BrushMode

## The Place tool's mode (PlaceTool): a click places a prop of `rule`, bedded on the ground
## and turned at random; dragging while pressed turns it toward the pointer once the pointer
## has moved TURN_START_PX. Over a placed prop, Shift+wheel scales it and RMB or Delete
## removes it (`picks`); a press over one places nothing. Props are AuthoringEditor's
## (place_prop, turn_prop, scale_prop, remove_prop; an edit stays open until end() commits it).
##
## Cursor: the hovered prop's footprint, the prop being placed, or a small marker that turns
## red where the prop's base would straddle a drop of more than PLACE_DROP_WARN_M (it would be
## sunk that far to stand).

## Pointer travel (px) after a press before the drag turns the prop.
const TURN_START_PX := 10.0
const PLACE_MARKER_M := 0.6
## The marker turns red where the prop's base footprint straddles a drop of more than this
## (AuthoringEditor.footing_drop, metres).
const PLACE_DROP_WARN_M := 0.25

## The species rule a click places (AuthoringEditor.species_rule), or {}.
var rule: Dictionary = {}

## The prop being placed and turned, and the prop under the pointer.
var _placing: Dictionary = {}
var _turning: bool = false
var _hover: Dictionary = {}


func _init() -> void:
	picks = true


func has_target() -> bool:
	return not _hover.is_empty()


func press(brush: BrushTool) -> bool:
	# The hover is from the last frame; the pointer may have jumped since (a press that
	# arrives with its own motion), so look again at the press point.
	_update_hover(brush)
	if _hover.is_empty() and not rule.is_empty():
		_placing = brush.editor.place_prop(rule, brush.bedded(brush.hit), brush.hit_normal)
	return false


func frame(brush: BrushTool) -> void:
	if not _placing.is_empty():
		_turn_placing(brush)
	elif not brush.pressed:
		_update_hover(brush)


## Commits the prop edit in progress (a placement, a turn or a scale).
func end(brush: BrushTool) -> void:
	if brush.editor != null:
		brush.editor.commit_prop_edit()
	_placing = {}
	_turning = false


func cancel(brush: BrushTool) -> void:
	if brush.editor != null and not _placing.is_empty():
		brush.editor.cancel_prop_edit()
	_placing = {}
	_turning = false


func leave(_brush: BrushTool) -> void:
	_hover = {}


## Scales the hovered prop by `steps` notches, within its species' range.
func step(brush: BrushTool, steps: int) -> void:
	var editor := brush.editor
	if editor == null or _hover.is_empty():
		return
	var scale_rule := rule
	var asset_rule := editor.rule_for_asset(String(_hover.asset_id))
	if not asset_rule.is_empty():
		scale_rule = asset_rule
	_hover = editor.scale_prop(_hover, steps, scale_rule)
	var new_scale: float = (_hover.row as PackedFloat32Array)[7]
	var radius := editor.pick_radius(String(_hover.asset_id))
	_hover["radius"] = PropRows.pick_extent(radius, new_scale) * editor.map_scale()
	brush.redraw()


func remove_target(brush: BrushTool) -> void:
	if brush.editor != null and not _hover.is_empty():
		brush.editor.remove_prop(_hover)
		_hover = {}
		brush.redraw()


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	var editor := brush.editor
	if not _hover.is_empty() and _placing.is_empty():
		var centre := editor.prop_position(_hover)
		cursor.draw_flat_ring(centre, float(_hover.get("radius", 1.0)), BrushCursor.PLACE_TINT, 2.5)
		return
	if not _placing.is_empty():
		var at := editor.prop_position(_placing)
		cursor.draw_flat_ring(at, PLACE_MARKER_M, BrushCursor.PLACE_TINT, 2.0)
		return
	var tint := BrushCursor.PLACE_TINT
	if not rule.is_empty() and editor.footing_drop(rule, brush.hit) > PLACE_DROP_WARN_M:
		tint = BrushCursor.CLEAR_TINT
	cursor.draw_flat_ring(brush.hit, PLACE_MARKER_M, Color(tint, 0.8), 1.5)


## Once the pointer has moved TURN_START_PX from the press, the prop turns to face it.
func _turn_placing(brush: BrushTool) -> void:
	var editor := brush.editor
	if brush.hit == Vector3.INF or editor == null:
		return
	if not _turning and brush.pointer.distance_to(brush.press_position) < TURN_START_PX:
		return
	_turning = true
	var centre := editor.prop_position(_placing)
	var toward := brush.hit - centre
	if Vector2(toward.x, toward.z).length() < 0.05:
		return
	_placing = editor.turn_prop(_placing, atan2(-toward.x, -toward.z))


func _update_hover(brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null or brush.hit == Vector3.INF:
		_hover = {}
		return
	var found := editor.prop_at(brush.hit)
	if found.get("row") != _hover.get("row"):
		editor.commit_prop_edit()
	_hover = found
