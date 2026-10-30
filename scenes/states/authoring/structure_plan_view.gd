class_name StructurePlanView
extends RefCounted

## The Structure tool's footprint drawing (StructureBrush's ghost lot and hovered building,
## StructureSelectionView's selected one): one plan on the map's canvas. Split out of the brush so
## the brush holds the gesture and this the picture.

## The chips' offset from the cursor (as BridgeBrush.draw_pill's) and the gap between two.
const PILL_OFFSET := Vector2(16.0, 14.0)
const PILL_GAP_PX := 4.0


## A footprint (map XZ) on `canvas`: its outline on the ground, faintly filled, a ring `height`
## (document metres) above it joined by a pole at each corner, and the door marked on its front
## edge (edge 0: a bar the door width and a tick out from it). Every point sits on the
## document's ground.
static func draw_plan(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	plan: PackedVector2Array,
	height: float,
	tint: Color,
	strength: float
) -> void:
	var count := plan.size()
	if count < 3:
		return
	var doc := editor.document
	var screen := func(p: Vector2, lift: float) -> Vector2:
		var y := WaterGeometry.ground_at(doc, p) + lift
		return camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y)))
	var base := PackedVector2Array()
	var top := PackedVector2Array()
	var corners := PackedVector2Array()
	for k in count:
		var a := plan[k]
		var b := plan[(k + 1) % count]
		var pieces := maxi(1, ceili(a.distance_to(b) / StructureBrush.LINE_STEP_M))
		corners.append(screen.call(a, 0.04))
		for s in pieces:
			var xz := a.lerp(b, float(s) / pieces)
			base.append(screen.call(xz, 0.04))
			top.append(screen.call(xz, height))
	base.append(base[0])
	top.append(top[0])
	var fill := Geometry2D.triangulate_polygon(plan)
	if not fill.is_empty():
		var vertices := PackedVector2Array()
		for p in plan:
			vertices.append(screen.call(p, 0.04))
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		colors.fill(StructureBrush.faded(tint, StructureBrush.FOOTPRINT_ALPHA * strength))
		RenderingServer.canvas_item_add_triangle_array(
			canvas.get_canvas_item(), fill, vertices, colors
		)
	if height > 0.0:
		for k in count:
			var pole_base: Vector2 = screen.call(plan[k], 0.04)
			var pole_top: Vector2 = screen.call(plan[k], height)
			canvas.draw_line(pole_base, pole_top, StructureBrush.faded(tint, 0.3 * strength), 1.0, true)
		canvas.draw_polyline(top, StructureBrush.faded(WallBrush.SHADOW, 0.6 * strength), 3.0, true)
		canvas.draw_polyline(top, StructureBrush.faded(tint, 0.7 * strength), 1.5, true)
	canvas.draw_polyline(base, StructureBrush.faded(WallBrush.SHADOW, 0.6 * strength), 3.5, true)
	canvas.draw_polyline(base, StructureBrush.faded(tint, 0.95 * strength), 1.75, true)
	for p in corners:
		canvas.draw_circle(p, 4.5, StructureBrush.faded(WallBrush.SHADOW, 0.7 * strength))
		canvas.draw_circle(p, 3.0, StructureBrush.faded(tint, strength))
	var scale := editor.map_scale()
	var door := StructureBrush.DOOR_MARK_M / scale
	var middle := ProcgenPlan.edge_middle(plan, 0)
	var along := (ProcgenPlan.edge_end(plan, 0) - ProcgenPlan.edge_start(plan, 0)).normalized()
	var out := ProcgenPlan.outward(plan, 0)
	var left: Vector2 = screen.call(middle - along * door * 0.5, 0.05)
	var right: Vector2 = screen.call(middle + along * door * 0.5, 0.05)
	var step: Vector2 = screen.call(middle + out * door * 0.6, 0.05)
	var centre: Vector2 = screen.call(middle, 0.05)
	var white := StructureBrush.faded(Color.WHITE, strength)
	canvas.draw_line(left, right, StructureBrush.faded(WallBrush.SHADOW, 0.8 * strength), 7.0, true)
	canvas.draw_line(left, right, white, 4.0, true)
	canvas.draw_line(centre, step, StructureBrush.faded(WallBrush.SHADOW, 0.8 * strength), 5.0, true)
	canvas.draw_line(centre, step, white, 2.5, true)


## A stack of readout chips beside the cursor at screen point `at`, one per line ({"text",
## "color"}), under one another on one side: the widest line decides whether the stack sits right of
## `at` or, near the free board's edge, left of it, so the lines never part.
static func draw_pills(canvas: Control, at: Vector2, lines: Array[Dictionary]) -> void:
	var view := canvas.get_viewport_rect().size
	var span := DrawerContainer.free_span(canvas.get_viewport())
	var widest := 0.0
	var height := 0.0
	var sizes: Array[Vector2] = []
	for line in lines:
		var box := MapOverlayUtils.chip_size(canvas, String(line["text"]))
		sizes.append(box)
		widest = maxf(widest, box.x)
		height += box.y + PILL_GAP_PX
	var x := at.x + PILL_OFFSET.x
	if x + widest > span.y - 4.0:
		x = at.x - PILL_OFFSET.x - widest
	x = maxf(x, span.x + 4.0)
	var y := at.y + PILL_OFFSET.y
	if y + height > view.y - 4.0:
		y = at.y - PILL_OFFSET.y - height
	for k in lines.size():
		MapOverlayUtils.draw_chip(canvas, Vector2(x, y), String(lines[k]["text"]), lines[k]["color"])
		y += sizes[k].y + PILL_GAP_PX
