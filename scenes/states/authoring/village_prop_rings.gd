class_name VillagePropRings
extends RefCounted

## What the Village tool draws for the furnishings (VillageRings.draw calls draw first): a ring
## round the piece under the pointer (chalk, heavier), one round the picked piece (the Wall tool's
## gold), and while a piece is carried a ring at the place it would stand, gold where it may go and
## the erase salmon where it may not, with the place it left a calm ring and a pill that says what
## the release does or why it will not. The rings are VillageRings.draw_plaza's, a few handle-less
## discs a hand wide, so a piece reads in the same language as the plazas it stands in. Static
## drawing; no state.

## The ring stands this far outside a piece's drawn radius, and never gets smaller than the floor,
## in metres.
const RING_GROW_M := 0.2
const RING_FLOOR_M := 0.55


## Draws the pieces' rings and pill for `mode`. True when it drew a pill (a piece is under the
## pointer or carried), so the plaza and ghost pills that VillageRings would draw are left out.
static func draw(brush: BrushTool, cursor: BrushCursor, mode: VillageBrush) -> bool:
	var editor := brush.editor
	var props := mode.props
	var picked := props.item(editor) if props.has_picked() else {}
	var hovered := (
		props.item(editor, props.hover_village, props.hover_slot) if props.has_hover() else {}
	)
	if not picked.is_empty() or not hovered.is_empty():
		_rings(editor, cursor, props, picked, hovered)
	var camera := cursor.camera
	if brush.hit == Vector3.INF:
		return false
	var pill_at := camera.unproject_position(brush.hit)
	if props.moving():
		var reason := props.refusal()
		var text := VillageProps.MOVE_HINT
		var colour := VillageRings.READOUT_COLOR
		if reason != &"":
			text = VillageFurnishings.short_reason(reason)
			colour = VillageRings.REFUSED_COLOR
			# The erase cross at the pointer, so a refusal reads on any ground or roof colour.
			BridgeBrush.draw_marker(cursor.canvas, camera, brush.hit, VillageRings.TINT_REFUSED)
		BridgeBrush.draw_pill(cursor.canvas, pill_at + Vector2(18, -22), text, colour)
		return true
	if props.gesture != &"" or hovered.is_empty() or mode.gesture != &"":
		return props.gesture != &""
	var words := VillageProps.HOVER
	if VillageFurnishings.is_field_piece(str(hovered["slot"])):
		words = VillageProps.HOVER_FIELD
	elif not picked.is_empty() and str(picked["slot"]) == str(hovered["slot"]):
		words = VillageProps.HOVER_PICKED
	BridgeBrush.draw_pill(cursor.canvas, pill_at + Vector2(18, -22), words, VillageRings.READOUT_COLOR)
	return true


static func _rings(
	editor: AuthoringEditor,
	cursor: BrushCursor,
	props: VillageProps,
	picked: Dictionary,
	hovered: Dictionary
) -> void:
	var canvas := cursor.canvas
	var camera := cursor.camera
	if not hovered.is_empty() and (picked.is_empty() or hovered["slot"] != picked["slot"]):
		if not props.moving():
			var style := VillageRings.ring_style(false, true)
			style["handles"] = 0.0
			_ring(canvas, camera, editor, hovered["position"], hovered, style)
	if picked.is_empty():
		return
	var at: Vector2 = picked["position"]
	if props.moving():
		# The place it left stays a quiet ring; the carried one is gold, or salmon where refused.
		var calm := VillageRings.ring_style(false, false)
		calm["strength"] = 1.0
		_ring(canvas, camera, editor, at, picked, calm)
		var carried := VillageRings.ring_style(true, false)
		if props.refusal() != &"":
			var wash := VillageRings.TINT_REFUSED
			wash.a = VillageRings.REFUSED_FILL_ALPHA
			carried = VillageRings.ghost_style(wash, VillageRings.TINT_REFUSED)
		carried["handles"] = 0.0
		_ring(canvas, camera, editor, props.destination(), picked, carried)
		return
	var under_pointer: bool = not hovered.is_empty() and hovered["slot"] == picked["slot"]
	var style := VillageRings.ring_style(true, under_pointer)
	style["handles"] = 0.0
	_ring(canvas, camera, editor, at, picked, style)


static func _ring(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	at: Vector2,
	item: Dictionary,
	style: Dictionary
) -> void:
	var radius := maxf(VillageFurnishings.drawn_radius(item) + RING_GROW_M, RING_FLOOR_M)
	VillageRings.draw_plaza(canvas, camera, editor, at, radius, style)
