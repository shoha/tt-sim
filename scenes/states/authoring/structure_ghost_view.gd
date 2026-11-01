class_name StructureGhostView
extends RefCounted

## How the Structure tool draws its cursor (StructureBrush.draw_cursor): the ghost lot (its
## footprint, door mark and height ring in the note's tint, the two corners of a lot being sized)
## with the readout pill and the amber or red note beneath it, the building under the pointer
## tinted for a click or red with Ctrl, a plain marker when nothing can be laid, and over a
## selection StructureSelectionView first, the ghost stepping aside over a building or a handle.
## Pure drawing over the brush's state (bar the note, which the brush caches); docs/systems/
## structures.md "The tool".


## The cursor and previews of `brush` on `canvas` (see StructureBrush's header), for the pointer's
## ground point `hit` with Ctrl `erasing`; `units` is [metres per cell, display units per cell,
## label] (the readout's).
static func draw(
	brush: StructureBrush,
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	hit: Vector3,
	erasing: bool,
	units: Array
) -> void:
	var cell_m: float = units[0]
	var per_cell: float = units[1]
	var label: String = units[2]
	var scale := editor.map_scale()
	var drawing := brush.drawing
	var hover_id := brush.hover_id
	var selecting := brush.selected_id >= 0 and not drawing
	if selecting:
		StructureSelectionView.draw(brush, canvas, camera, editor, units)
		# The ghost lot follows over bare ground; it steps aside over a building or a handle.
		if hover_id >= 0 and hover_id != brush.selected_id:
			_draw_hovered(brush, canvas, camera, editor, hit, erasing)
		if not brush.edit.is_empty() or hover_id >= 0 or not brush.hover_handle.is_empty():
			return
		if erasing:
			if hit != Vector3.INF:
				BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.ERASE_TINT)
			return
	elif not drawing and hover_id >= 0:
		_draw_hovered(brush, canvas, camera, editor, hit, erasing)
		# A click on a building selects it, so no lot follows the pointer over one.
		return
	elif erasing and not drawing:
		if hit != Vector3.INF:
			BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.ERASE_TINT)
		return
	if brush.row().is_empty():
		if selecting:
			return
		if hit != Vector3.INF:
			BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.STONE_TINT)
			BridgeBrush.draw_pill(
				canvas,
				camera.unproject_position(hit),
				StructureBrush.NONE_PICKED,
				WallBrush.REFUSED_COLOR
			)
		return
	var plan := brush.ghost_plan()
	if plan.is_empty():
		return
	var ok := brush.problem == "" and (not drawing or brush.preview != null)
	brush.refresh_note(scale, units, ok)
	var note := brush.note
	var level: int = note["level"]
	var tint := StructureNote.ghost_tint(level)
	var high := brush.height_of(brush.ref) / scale
	StructurePlanView.draw_plan(canvas, camera, editor, plan, high, tint, 1.0 if drawing else 0.8)
	if drawing:
		for corner in [brush.from, brush.to]:
			BridgeBrush.draw_marker(canvas, camera, corner, tint)
	var centre := brush.ghost_centre
	var size := brush.ghost_size
	var ground := WaterGeometry.ground_at(editor.document, centre)
	var anchor := editor.to_world(Vector3(centre.x, ground, centre.y))
	var at := camera.unproject_position(anchor)
	var text := StructureBrush.readout(
		brush.title(), size.x * scale, size.y * scale, cell_m, per_cell, label
	)
	# The name and size always; a note (amber) or the reason a lot cannot stand (red) beneath.
	var lines: Array[Dictionary] = [{"text": text, "color": WallBrush.READOUT_COLOR}]
	if StructureNote.shown(level, String(note["text"]), brush.note_rest.rested()):
		lines.append({"text": note["text"], "color": StructureNote.colour(level)})
	StructurePlanView.draw_pills(canvas, at, lines)


## The building under the pointer, tinted (a click selects it), or with Ctrl `erasing` red with a
## pill saying what a click removes.
static func _draw_hovered(
	brush: StructureBrush,
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	hit: Vector3,
	erasing: bool
) -> void:
	var hovered := editor.document.structure(brush.hover_id)
	if hovered == null:
		return
	var strength := 1.0 if erasing else StructureNote.HOVER_STRENGTH
	var tint := WallBrush.ERASE_TINT if erasing else WallBrush.STONE_TINT
	StructurePlanView.draw_plan(canvas, camera, editor, hovered.footprint, 0.0, tint, strength)
	if erasing:
		BridgeBrush.draw_pill(
			canvas,
			camera.unproject_position(hit),
			"Remove " + String(hovered.recipe.get_slice(":", 1)).replace("_", " "),
			WallBrush.REFUSED_COLOR
		)
