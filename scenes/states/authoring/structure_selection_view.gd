class_name StructureSelectionView
extends RefCounted

## How the Structure tool draws its selected building (StructureBrush.draw): the tint and outline
## with the height ring and door mark, a round dot at each corner and a diamond tab beside each
## side (StructureEdit's handles), the readout of a dragged size, the hint over a side tab that
## would take the door, and the gentle cue of a stopped drag: the handle turns warm and a thin line
## runs from it to where the pointer is asking. Under a drag the outline is the drag's plan. Pure
## drawing over the brush's state; docs/systems/structures.md "Editing a building".


## Draws the selection of `brush` on `canvas`; `units` is [metres per cell, display units per cell,
## label] (the readout's).
static func draw(
	brush: StructureBrush, canvas: Control, camera: Camera3D, editor: AuthoringEditor, units: Array
) -> void:
	var held := brush.selected(editor)
	if held == null:
		return
	var edit := brush.edit
	var hover := brush.hover_handle
	var scale := editor.map_scale()
	var editing := not edit.is_empty()
	var dragging: bool = editing and bool(edit["dragged"])
	var plan: PackedVector2Array = edit["plan"] if dragging else held.footprint
	var stopped: bool = dragging and bool(edit["clamped"])
	var tint := StructureBrush.CUE_TINT if stopped else StructureBrush.SELECT_TINT
	StructureBrush.draw_plan(
		canvas, camera, editor, plan, brush.height_of(held.recipe) / scale, tint, 1.0
	)
	var active: Dictionary = edit["handle"] if editing else hover
	var moving: bool = editing and edit["kind"] == &"move"
	if not moving:
		for handle in StructureEdit.handles(plan):
			var lit: bool = (
				not active.is_empty()
				and active["kind"] == handle["kind"]
				and active["index"] == handle["index"]
			)
			_draw_handle(canvas, camera, editor, plan, handle, lit, lit and stopped)
	if stopped:
		var from_point := StructureEdit.centre_of(plan)
		if not active.is_empty() and not moving:
			from_point = StructureEdit.handles(plan)[_handle_slot(plan, active)]["at"]
		var a := project(editor, camera, from_point, 0.06)
		var b := project(editor, camera, edit["at"], 0.06)
		canvas.draw_line(a, b, StructureBrush.faded(StructureBrush.CUE_TINT, 0.7), 1.5, true)
		canvas.draw_circle(b, 4.0, StructureBrush.faded(StructureBrush.CUE_TINT, 0.5))
	if dragging and not moving:
		var size := StructureEdit.extent_of(plan)
		var name_text := String(
			LibraryStructureStore.structure(held.recipe).get("name", "Building")
		)
		BridgeBrush.draw_pill(
			canvas,
			project(editor, camera, StructureEdit.centre_of(plan), 0.1),
			StructureBrush.readout(
				name_text, size.x * scale, size.y * scale, units[0], units[1], units[2]
			),
			WallBrush.READOUT_COLOR
		)
	elif (
		not editing
		and not hover.is_empty()
		and hover["kind"] == StructureEdit.EDGE
		and int(hover["index"]) > 0
	):
		BridgeBrush.draw_pill(
			canvas,
			project(editor, camera, hover["at"], 0.1) + Vector2(0, -22),
			StructureBrush.DOOR_HINT,
			WallBrush.READOUT_COLOR
		)


## The index of `handle` in StructureEdit.handles(plan).
static func _handle_slot(plan: PackedVector2Array, handle: Dictionary) -> int:
	return int(handle["index"]) + (plan.size() if handle["kind"] == StructureEdit.EDGE else 0)


## A map point on the canvas, on the document's ground plus `lift` metres.
static func project(editor: AuthoringEditor, camera: Camera3D, p: Vector2, lift: float) -> Vector2:
	var y := WaterGeometry.ground_at(editor.document, p) + lift
	return camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y)))


## One handle of `plan`: a round dot at a corner, a diamond tab joined by a stem to its side.
## `lit` (hovered or held) is larger and filled with the selection's tint; `stopped` is warm.
static func _draw_handle(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	plan: PackedVector2Array,
	handle: Dictionary,
	lit: bool,
	stopped: bool
) -> void:
	var at := project(editor, camera, handle["at"], 0.06)
	var radius := StructureBrush.HANDLE_RADIUS + (2.0 if lit else 0.0)
	var fill := (
		StructureBrush.CUE_TINT if stopped else (StructureBrush.SELECT_TINT if lit else Color.WHITE)
	)
	var shadow := StructureBrush.faded(WallBrush.SHADOW, 0.8)
	if handle["kind"] == StructureEdit.CORNER:
		canvas.draw_circle(at, radius + 1.5, shadow)
		canvas.draw_circle(at, radius, fill)
		return
	var side := project(editor, camera, ProcgenPlan.edge_middle(plan, int(handle["index"])), 0.06)
	canvas.draw_line(side, at, shadow, 4.0, true)
	canvas.draw_line(side, at, StructureBrush.faded(fill, 0.9), 2.0, true)
	var diamond := PackedVector2Array(
		[
			at + Vector2(0, -radius - 1.0),
			at + Vector2(radius + 1.0, 0),
			at + Vector2(0, radius + 1.0),
			at + Vector2(-radius - 1.0, 0)
		]
	)
	canvas.draw_colored_polygon(diamond, shadow)
	var inner := PackedVector2Array()
	for p in diamond:
		inner.append(at + (p - at) * 0.72)
	canvas.draw_colored_polygon(inner, fill)
