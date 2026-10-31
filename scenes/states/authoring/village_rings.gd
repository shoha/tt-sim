class_name VillageRings
extends RefCounted

## What the Village tool draws on the board (VillageBrush.draw_cursor calls draw): every plaza of
## the map as a soft ring on the ground, the ghost of the plaza a press would open, the flat
## paving preview of a held drag, a number chip on each village when there are two or more, and
## the pill that says what a press does. Four ring weights keep the states apart at a glance:
## the ghost is a thin line over a faint disc of the kit's paving, a calm plaza a quiet paper
## ring, the picked one the Wall tool's gold and heavier, the one under the pointer heavier still
## with larger handle dots. The colours of a disc are the kit's own paving (VillageSwatch), so the
## author sees the ground a release will lay before it is laid. Static drawing; no state.

## Ring tints: the picked plaza in the Wall tool's gold, the one under the pointer in warm chalk,
## the rest soft paper.
const TINT_PICKED := WallBrush.READOUT_COLOR
const TINT_HOVER := Color.IVORY
const TINT_CALM := Color.OLD_LACE
const TINT_REFUSED := BrushCursor.CLEAR_TINT
const SHADOW := BrushCursor.SHADOW_COLOR
const REFUSED_COLOR := WallBrush.REFUSED_COLOR
const READOUT_COLOR := WallBrush.READOUT_COLOR
const RING_POINTS := 56
## A calm ring's fill, and the paving tints of the ghost and of a held drag.
const FILL_ALPHA := 0.13
const GHOST_FILL_ALPHA := 0.5
const PREVIEW_FILL_ALPHA := 0.6
## Paving tints are lifted toward white this much, so a disc reads luminous over the ground rather
## than as a grey film (the round 2 drag capture).
const FILL_LIFT := 0.25
## Line weights (times the brush cursor's widths) and handle dot radii, in pixels.
const WEIGHT_GHOST := 0.55
const WEIGHT_CALM := 0.9
const WEIGHT_PICKED := 1.35
const WEIGHT_HOVER := 1.75
const HANDLE_PX := 5.5
const HANDLE_HOVER_PX := 8.0
## The gap between a ghost's rim and its pill, in pixels.
const PILL_GAP_PX := 6.0


## Draws the board for `mode` on `cursor`'s canvas.
static func draw(brush: BrushTool, cursor: BrushCursor, mode: VillageBrush) -> void:
	var editor := brush.editor
	var canvas := cursor.canvas
	var camera := cursor.camera
	var doc := editor.document
	for settlement in doc.settlements:
		for index in settlement.plazas.size():
			var plaza := settlement.plazas[index]
			var picked := settlement.id == mode.selected_village and index == mode.selected_plaza
			var hovered := (
				mode.gesture == &""
				and settlement.id == mode.hover_village
				and index == mode.hover_plaza
			)
			var radius := float(plaza["radius"])
			var style := ring_style(picked, hovered)
			if mode.gesture == VillageBrush.GESTURE_RESIZE and picked:
				radius = mode.preview_radius()
				style["fill"] = _paving(editor, settlement.kit, PREVIEW_FILL_ALPHA)
			draw_plaza(canvas, camera, editor, plaza["at"], radius, style)
	if doc.settlements.size() > 1:
		for settlement in doc.settlements:
			_draw_badge(canvas, camera, editor, settlement, settlement.id == mode.selected_village)
	var units := [brush.unit_cell_m, brush.unit_per_cell, brush.unit_label]
	if mode.gesture == VillageBrush.GESTURE_NEW or mode.gesture == VillageBrush.GESTURE_RESIZE:
		var radius := mode.preview_radius()
		if mode.gesture == VillageBrush.GESTURE_NEW:
			var style := ring_style(true, false)
			var kit := doc.settlement(mode.selected_village).kit
			style["fill"] = _paving(editor, kit, PREVIEW_FILL_ALPHA)
			draw_plaza(canvas, camera, editor, mode.centre(), radius, style)
		BridgeBrush.draw_pill(
			canvas,
			camera.unproject_position(brush.hit),
			readout(radius * editor.map_scale(), units),
			READOUT_COLOR
		)
		return
	if brush.hit == Vector3.INF or mode.gesture == VillageBrush.GESTURE_PICK:
		return
	var pill_at := camera.unproject_position(brush.hit)
	if mode.hover_plaza >= 0:
		var rim := mode.hover_part == VillagePlazas.PART_RIM
		var picked := (
			mode.hover_village == mode.selected_village and mode.hover_plaza == mode.selected_plaza
		)
		var text := VillageBrush.HOVER_RIM
		if not rim:
			text = VillageBrush.HOVER_PICKED if picked else VillageBrush.HOVER_INSIDE
		BridgeBrush.draw_pill(canvas, pill_at, text, READOUT_COLOR)
		return
	var p := editor.to_map_xz(brush.hit)
	var village := mode.ghost_village(editor, p)
	if village < 0:
		BridgeBrush.draw_marker(canvas, camera, brush.hit, TINT_REFUSED)
		BridgeBrush.draw_pill(canvas, pill_at, VillageBrush.NO_VILLAGE_SHORT, REFUSED_COLOR)
	elif doc.settlement(village).plazas.size() >= Settlement.MAX_PLAZAS:
		BridgeBrush.draw_marker(canvas, camera, brush.hit, TINT_REFUSED)
		BridgeBrush.draw_pill(canvas, pill_at, VillageBrush.FULL_SHORT, REFUSED_COLOR)
	else:
		var style := ghost_style(_paving(editor, doc.settlement(village).kit, GHOST_FILL_ALPHA))
		var ring := draw_plaza(canvas, camera, editor, p, VillagePlazas.DEFAULT_RADIUS_M, style)
		BridgeBrush.draw_pill(
			canvas, beside(ring, pill_at), VillageBrush.ghost_hint(doc, village), READOUT_COLOR
		)


## The look of a placed plaza's ring: picked, under the pointer, both or neither.
static func ring_style(picked: bool, hovered: bool) -> Dictionary:
	var weight := WEIGHT_CALM
	if picked:
		weight = WEIGHT_PICKED
	if hovered:
		weight = WEIGHT_HOVER
	return {
		"tint": TINT_PICKED if picked else (TINT_HOVER if hovered else TINT_CALM),
		"strength": 1.0 if (picked or hovered) else 0.55,
		"weight": weight,
		"fill": Color.TRANSPARENT,
		"handles": HANDLE_HOVER_PX if hovered else (HANDLE_PX if picked else 0.0),
	}


## The ghost's look: a thin chalk line over a faint disc of `fill` (the kit's paving).
static func ghost_style(fill: Color) -> Dictionary:
	return {
		"tint": TINT_HOVER,
		"strength": 0.75,
		"weight": WEIGHT_GHOST,
		"fill": fill,
		"handles": 0.0,
	}


## Where the ghost's pill goes: just past the right of `ring` (its screen points), level with the
## pointer `at`, so the words never cover the disc they describe.
static func beside(ring: PackedVector2Array, at: Vector2) -> Vector2:
	var right := at.x
	for point in ring:
		right = maxf(right, point.x)
	return Vector2(right + PILL_GAP_PX - 16.0, at.y - 14.0)


## The readout of a plaza `radius_world` metres in radius: its width across in the level's units.
static func readout(radius_world: float, units: Array) -> String:
	var across := roundi(
		ScaleUtils.world_to_display(2.0 * radius_world, float(units[0]), float(units[1]))
	)
	return "Plaza  %d %s across" % [across, str(units[2])]


## A plaza ring on `canvas` in `style` (ring_style, ghost_style): the disc filled on the ground
## (the style's `fill`, else the tint faintly), a soft glow under a dark keyline under a bright
## line, all `weight` times the cursor's widths, and with `handles` above zero four dots of that
## radius on the rim (VillagePlazas.handle_points) that say it can be dragged. Each point sits on
## the document's ground. Returns the ring's screen points.
static func draw_plaza(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	at: Vector2,
	radius: float,
	style: Dictionary
) -> PackedVector2Array:
	var doc := editor.document
	var screen := func(p: Vector2) -> Vector2:
		var y := WaterGeometry.ground_at(doc, p) + 0.06
		return camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y)))
	var tint: Color = style["tint"]
	var strength := float(style["strength"])
	var weight := float(style["weight"])
	var fill: Color = style["fill"]
	var ring := PackedVector2Array()
	for k in RING_POINTS:
		ring.append(screen.call(at + Vector2.from_angle(TAU * k / RING_POINTS) * radius))
	ring.append(ring[0])
	var fan := ring.duplicate()
	fan.append(screen.call(at))
	var colors := PackedColorArray()
	colors.resize(fan.size())
	colors.fill(fill if fill.a > 0.0 else _alpha(tint, FILL_ALPHA * strength))
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), BrushCursor.fan_indices(ring.size()), fan, colors
	)
	var glow := _alpha(tint, BrushCursor.GLOW_ALPHA * strength)
	var ink := _alpha(SHADOW, BrushCursor.INK_ALPHA * 0.6 * strength)
	canvas.draw_polyline(ring, glow, BrushCursor.GLOW_WIDTH * weight, true)
	canvas.draw_polyline(ring, ink, BrushCursor.INK_WIDTH * weight, true)
	canvas.draw_polyline(ring, _alpha(tint, strength), BrushCursor.LINE_WIDTH * weight, true)
	var dot_px := float(style["handles"])
	if dot_px <= 0.0:
		return ring
	for point in VillagePlazas.handle_points(at, radius):
		var dot: Vector2 = screen.call(point)
		canvas.draw_circle(dot, dot_px + 1.5, _alpha(SHADOW, 0.8))
		canvas.draw_circle(dot, dot_px, tint)
	return ring


## The village's number in a glass chip at its anchor (VillagePlazas.anchor_of), gold when picked.
static func _draw_badge(
	canvas: Control, camera: Camera3D, editor: AuthoringEditor, settlement: Settlement, picked: bool
) -> void:
	var anchor := VillagePlazas.anchor_of(editor.document, settlement)
	if anchor == Vector2.INF:
		return
	var y := WaterGeometry.ground_at(editor.document, anchor) + 0.5
	var at := camera.unproject_position(editor.to_world(Vector3(anchor.x, y, anchor.y)))
	var text := VillagePlazas.village_name(settlement.id)
	var box := MapOverlayUtils.chip_size(canvas, text)
	MapOverlayUtils.draw_chip(
		canvas, at - box * 0.5, text, TINT_PICKED if picked else Color.TRANSPARENT
	)


## Kit `kit`'s paving colour at `alpha`, from the editor's palette.
static func _paving(editor: AuthoringEditor, kit: String, alpha: float) -> Color:
	var paving := VillageSwatch.paving_color(kit, editor.palette_root)
	return _alpha(paving.lerp(Color.WHITE, FILL_LIFT), alpha)


## `color` with alpha `alpha`.
static func _alpha(color: Color, alpha: float) -> Color:
	var out := color
	out.a = alpha
	return out
