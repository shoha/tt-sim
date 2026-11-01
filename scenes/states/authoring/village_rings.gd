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
const GHOST_FILL_ALPHA := 0.2
const PREVIEW_FILL_ALPHA := 0.24
## A disc the author carries or aims is a warm wash, not the paving's own grey: the kit's paving
## colour is pulled this far toward WASH_TINT (warm paper gold), so a faint fill lights the grass
## instead of turning it chalky olive (plazamove critic: the grey-khaki haze over bright grass,
## blue doubling while red and green stayed).
const WASH_TINT := Color("#FFE2A0")
const WASH_PULL := 0.7
## A refused place is washed in the one erase salmon at this alpha (the ring is the erase ring's
## own stroke, 5.5 px over ink).
const REFUSED_FILL_ALPHA := 0.28
## The ink outline round a handle dot, beyond its radius, in pixels.
const DOT_INK_PX := 2.5
## Line weights (times the brush cursor's widths) and handle dot radii, in pixels. The ghost and a
## calm ring take the brush ring's full stroke (an ink outline under the tint): at 0.55 and 0.9 with
## the ink thinned they were a pale 1-2 px hairline, about 1.2:1 over bright grass (fields round 4).
const WEIGHT_GHOST := 1.0
const WEIGHT_CALM := 1.0
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
	for group: StringName in [VillageFields.GROUP_FIELDS, VillageFields.GROUP_PLAZAS]:
		for settlement in doc.settlements:
			var discs: Array[Dictionary] = settlement.get(group)
			for index in discs.size():
				var plaza := discs[index]
				var picked := (
					settlement.id == mode.selected_village
					and index == mode.selected_plaza
					and group == mode.selected_group
				)
				var hovered := (
					mode.gesture == &""
					and settlement.id == mode.hover_village
					and index == mode.hover_plaza
					and group == mode.hover_group
				)
				var radius := float(plaza["radius"])
				var style := ring_style(picked, hovered)
				if mode.gesture == VillageBrush.GESTURE_RESIZE and picked:
					radius = mode.preview_radius()
					style["fill"] = _fill(editor, settlement.kit, str(plaza.get("kind", "")), PREVIEW_FILL_ALPHA)
				if mode.gesture == VillageBrush.GESTURE_MOVE and picked:
					# Where it stands stays a quiet ring, at full ink so it reads over cobbles; the
					# moving disc is drawn below.
					style = ring_style(false, false)
					style["strength"] = 1.0
				draw_plaza(canvas, camera, editor, plaza["at"], radius, style)
	if doc.settlements.size() > 1:
		for settlement in doc.settlements:
			_draw_badge(canvas, camera, editor, settlement, settlement.id == mode.selected_village)
	var units := [brush.unit_cell_m, brush.unit_per_cell, brush.unit_label]
	if mode.gesture == VillageBrush.GESTURE_MOVE:
		_draw_move(brush, cursor, mode)
		return
	if mode.gesture == VillageBrush.GESTURE_NEW or mode.gesture == VillageBrush.GESTURE_RESIZE:
		var radius := mode.preview_radius()
		var held_disc := mode.picked_disc(doc)
		var kind := (
			str(held_disc.get("kind", ""))
			if not held_disc.is_empty()
			else mode.laying_kind(doc, mode.selected_village)
		)
		if mode.gesture == VillageBrush.GESTURE_NEW:
			var style := ring_style(true, false)
			var kit := doc.settlement(mode.selected_village).kit
			style["fill"] = _fill(editor, kit, kind, PREVIEW_FILL_ALPHA)
			draw_plaza(canvas, camera, editor, mode.centre(), radius, style)
		var noun := "Plaza" if kind == "" else str(VillageFields.KIND_LABELS.get(kind, "Field"))
		BridgeBrush.draw_pill(
			canvas,
			camera.unproject_position(brush.hit),
			readout(radius * editor.map_scale(), units, noun),
			READOUT_COLOR
		)
		return
	if brush.hit == Vector3.INF or mode.gesture == VillageBrush.GESTURE_PICK:
		return
	var pill_at := camera.unproject_position(brush.hit)
	if mode.hover_plaza >= 0:
		BridgeBrush.draw_pill(canvas, pill_at, hover_text(doc, mode), READOUT_COLOR)
		return
	var p := editor.to_map_xz(brush.hit)
	var village := mode.ghost_village(editor, p)
	var refusal := mode.refusal_at(doc, village, p)
	if refusal == VillageBrush.ON_BUILDING:
		# The disc a click would lay, in the refusal's salmon: the author sees which house it covers.
		var refused_kind := mode.laying_kind(doc, village)
		var refused_style := ghost_style(
			_alpha(TINT_REFUSED, REFUSED_FILL_ALPHA), TINT_REFUSED
		)
		draw_plaza(
			canvas, camera, editor, p, VillageFields.radius_for_drag(p, p, refused_kind), refused_style
		)
	if refusal != "":
		BridgeBrush.draw_marker(canvas, camera, brush.hit, TINT_REFUSED)
		BridgeBrush.draw_pill(canvas, pill_at, short_refusal(refusal), REFUSED_COLOR)
	else:
		var kit := doc.settlement(village).kit
		var kind := mode.laying_kind(doc, village)
		var style := ghost_style(_fill(editor, kit, kind, GHOST_FILL_ALPHA))
		var radius := VillagePlazas.DEFAULT_RADIUS_M
		if kind != "":
			radius = VillageFields.radius_for_drag(p, p, kind)
		if VillagePlazas.overlaps_any(doc, p, radius):
			# No second disc across one that stands: the pointer is a dot and the pill speaks.
			BridgeBrush.draw_marker(canvas, camera, brush.hit, TINT_HOVER)
			BridgeBrush.draw_pill(
				canvas, pill_at, VillageBrush.ghost_hint(doc, village, kind), READOUT_COLOR
			)
			return
		var ring := draw_plaza(canvas, camera, editor, p, radius, style)
		BridgeBrush.draw_pill(
			canvas, beside(ring, pill_at), VillageBrush.ghost_hint(doc, village, kind), READOUT_COLOR
		)


## The plaza a held move carries: a disc of the kit's paving at the place it would stand, in the
## picked gold with its handles, and the pill that says it can go there; over a refused place the
## disc is the refusal's salmon and the pill says why (VillageBrush.short_reason).
static func _draw_move(brush: BrushTool, cursor: BrushCursor, mode: VillageBrush) -> void:
	var editor := brush.editor
	var doc := editor.document
	var held := doc.settlement(mode.selected_village)
	var disc := mode.picked_disc(doc)
	if held == null or disc.is_empty():
		return
	var at := mode.move_destination()
	var radius := float(disc["radius"])
	var reason := mode.move_reason()
	var style := ring_style(true, false)
	if reason == &"":
		style["fill"] = _fill(editor, held.kit, "", PREVIEW_FILL_ALPHA)
	else:
		style = ghost_style(_alpha(TINT_REFUSED, REFUSED_FILL_ALPHA), TINT_REFUSED)
		style["handles"] = HANDLE_PX
	var ring := draw_plaza(cursor.canvas, cursor.camera, editor, at, radius, style)
	var text := VillageBrush.short_reason(reason)
	var colour := REFUSED_COLOR
	if reason == &"":
		colour = READOUT_COLOR
		text = VillageBrush.MOVE_HINT
		if mode.move_village() != mode.selected_village and mode.move_village() > 0:
			text = VillageBrush.MOVE_HINT_IN % VillagePlazas.village_name(mode.move_village()).to_lower()
	BridgeBrush.draw_pill(
		cursor.canvas, beside(ring, cursor.camera.unproject_position(brush.hit)), text, colour
	)


## The pill over the disc under the pointer: what a press on its rim or inside does.
static func hover_text(doc: MapDocument, mode: VillageBrush) -> String:
	var rim := mode.hover_part == VillagePlazas.PART_RIM
	var picked := (
		mode.hover_village == mode.selected_village
		and mode.hover_plaza == mode.selected_plaza
		and mode.hover_group == mode.selected_group
	)
	if mode.hover_group == VillageFields.GROUP_FIELDS:
		var held := doc.settlement(mode.hover_village)
		var kind := str(held.fields[mode.hover_plaza]["kind"]) if held != null else ""
		if rim:
			return VillageBrush.FIELD_HOVER_RIM
		if picked:
			return VillageBrush.HOVER_PICKED_FIELD
		return VillageBrush.FIELD_HOVER_INSIDE % str(VillageFields.KIND_LABELS.get(kind, "Field"))
	if rim:
		return VillageBrush.HOVER_RIM
	return VillageBrush.HOVER_PICKED if picked else VillageBrush.HOVER_INSIDE


## The short pill for a refusal (VillageBrush.refusal_at's words).
static func short_refusal(refusal: String) -> String:
	match refusal:
		VillageBrush.FULL:
			return VillageBrush.FULL_SHORT
		VillageBrush.FIELDS_FULL:
			return VillageBrush.FIELDS_FULL_SHORT
		VillageBrush.NO_FIELDS:
			return VillageBrush.NO_FIELDS_SHORT
		VillageBrush.ON_BUILDING:
			return VillageBrush.ON_BUILDING_SHORT
	return VillageBrush.NO_VILLAGE_SHORT


## The look of a placed plaza's ring: picked, under the pointer, both or neither.
static func ring_style(picked: bool, hovered: bool) -> Dictionary:
	var weight := WEIGHT_CALM
	if picked:
		weight = WEIGHT_PICKED
	if hovered:
		weight = WEIGHT_HOVER
	return {
		"tint": TINT_PICKED if picked else (TINT_HOVER if hovered else TINT_CALM),
		"strength": 1.0 if (picked or hovered) else 0.85,
		"weight": weight,
		"fill": Color.TRANSPARENT,
		"handles": HANDLE_HOVER_PX if hovered else (HANDLE_PX if picked else 0.0),
	}


## The ghost's look: the brush ring's chalk stroke over a disc of `fill` (the kit's paving or the
## field kind's tint), in `tint` (salmon for a disc a press would be refused).
static func ghost_style(fill: Color, tint: Color = TINT_HOVER) -> Dictionary:
	return {
		"tint": tint,
		"strength": 1.0,
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


## The readout of a plaza (or the `noun` named disc) `radius_world` metres in radius: its width
## across in the level's units.
static func readout(radius_world: float, units: Array, noun: String = "Plaza") -> String:
	var across := roundi(
		ScaleUtils.world_to_display(2.0 * radius_world, float(units[0]), float(units[1]))
	)
	return "%s  %d %s across" % [noun, across, str(units[2])]


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
	# The brush ring's own stroke (glow, ink, line), the one every line tool and plaza shares.
	for stroke: Array in BrushCursor.ring_strokes(_alpha(tint, strength)):
		canvas.draw_polyline(ring, stroke[0], float(stroke[1]) * weight, true)
	var dot_px := float(style["handles"])
	if dot_px <= 0.0:
		return ring
	for point in VillagePlazas.handle_points(at, radius):
		var dot: Vector2 = screen.call(point)
		var ink := ThemeColors.INK
		ink.a = BrushCursor.INK_ALPHA * tint.a
		canvas.draw_circle(dot, dot_px + DOT_INK_PX, ink)
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


## The tint a disc of field `kind` (VillageFields.KIND_TINTS), or of kit `kit`'s paving when `kind`
## is "", is previewed in, at `alpha`.
static func _fill(editor: AuthoringEditor, kit: String, kind: String, alpha: float) -> Color:
	if kind != "" and VillageFields.KIND_TINTS.has(kind):
		return _alpha(VillageFields.KIND_TINTS[kind], alpha)
	return _paving(editor, kit, alpha)


## Kit `kit`'s paving colour at `alpha`, from the editor's palette.
static func _paving(editor: AuthoringEditor, kit: String, alpha: float) -> Color:
	var paving := VillageSwatch.paving_color(kit, editor.palette_root)
	return _alpha(paving.lerp(WASH_TINT, WASH_PULL), alpha)


## `color` with alpha `alpha`.
static func _alpha(color: Color, alpha: float) -> Color:
	var out := color
	out.a = alpha
	return out
