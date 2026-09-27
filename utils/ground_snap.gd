class_name GroundSnap
extends RefCounted

## Keeping instance rows on the ground while the ground moves under them: generated scatter
## rows and hand-placed props, during and after a sculpt stroke. Pure functions over flat
## rows (MapDocument.ROW_STRIDE floats each) and height grids; AuthoringEditor applies the
## results with AuthoredScatter.move_rows().
##
## Every function works from the rows as they were when the stroke began (`start`) and the
## heights then (`before`) against the heights now (`after`), never from the previous
## frame, so nothing accumulates frame after frame and a row whose ground came back to
## where it was is exactly where it was. Heights and normals are read with the terrain's
## own triangles (ScatterGenerator.triangle_height / triangle_normal), the surface the
## ground is drawn and collided with.
##
## Scatter rows (snap_rows): Y becomes the ground height now; a normal-aligned species turns
## by the arc from the old ground normal to the new one, which keeps its yaw and its random
## lean (the same rule as DressingGround.snap_rows). Props (rebed_props): Y likewise; a
## normal-aligned prop stands on the new normal with its own yaw (PropRows), the rule the
## Place brush beds it by.

## A row whose ground moved less than this (and did not tilt) keeps its row.
const TOLERANCE_M := 0.0005
## Normal changes below this angle (radians) do not turn a row.
const TILT_TOLERANCE_RAD := 0.0005


## The grid description the snap functions take for `doc`: {"columns", "rows", "step",
## "half"} (see MapDocument).
static func grid_of(doc: MapDocument) -> Dictionary:
	return {
		"columns": doc.samples_x(),
		"rows": doc.samples_z(),
		"step": doc.sample_step(),
		"half": doc.extent_m() * 0.5,
	}


## Generated rows moved onto the ground `after`. `start` are the rows when the ground was
## `before`, `current` the rows as they are drawn now (same rows, same order), `tilt` true
## for a normal-aligned species; only rows whose XZ lies in `window` (map-frame XZ) are
## looked at, the rest keep `current`. Returns {"rows": PackedFloat32Array (a copy, or
## `current` itself when nothing moved), "moved": PackedInt32Array of the rows that now
## differ from `current`}.
@warning_ignore("integer_division")
static func snap_rows(
	start: PackedFloat32Array,
	current: PackedFloat32Array,
	before: PackedFloat32Array,
	after: PackedFloat32Array,
	grid: Dictionary,
	tilt: bool,
	window: Rect2
) -> Dictionary:
	var stride := MapDocument.ROW_STRIDE
	var columns: int = grid.columns
	var rows_count: int = grid.rows
	var step: Vector2 = grid.step
	var half: Vector2 = grid.half
	var out := current
	var copied := false
	var moved := PackedInt32Array()
	for r in start.size() / stride:
		var b := r * stride
		var p := Vector2(start[b], start[b + 2])
		if not window.has_point(p):
			continue
		var at := (p + half) / step
		var y := ScatterGenerator.triangle_height(after, columns, rows_count, at)
		var q := Quaternion(start[b + 3], start[b + 4], start[b + 5], start[b + 6])
		if tilt:
			var from := ScatterGenerator.triangle_normal(before, columns, rows_count, at, step)
			var to := ScatterGenerator.triangle_normal(after, columns, rows_count, at, step)
			if from.angle_to(to) > TILT_TOLERANCE_RAD and q.length_squared() > 0.0:
				q = (Quaternion(from, to) * q.normalized()).normalized()
		if (
			absf(y - current[b + 1]) <= 1e-6
			and is_equal_approx(q.x, current[b + 3])
			and is_equal_approx(q.y, current[b + 4])
			and is_equal_approx(q.z, current[b + 5])
			and is_equal_approx(q.w, current[b + 6])
		):
			continue
		if not copied:
			out = current.duplicate()
			copied = true
		out[b + 1] = y
		out[b + 3] = q.x
		out[b + 4] = q.y
		out[b + 5] = q.z
		out[b + 6] = q.w
		moved.append(r)
	return {"rows": out, "moved": moved}


## Props re-bedded on the ground `after`: like snap_rows(), but a prop whose ground did not
## change (height within TOLERANCE_M and normal within TILT_TOLERANCE_RAD of `before`)
## keeps its start row, so a prop placed on the collision is not nudged by the smoothing of
## a normal it never stood on; one whose ground changed takes Y from `after` and, when
## `align` (its species stands on the ground normal), the new normal with its own yaw.
@warning_ignore("integer_division")
static func rebed_props(
	start: PackedFloat32Array,
	current: PackedFloat32Array,
	before: PackedFloat32Array,
	after: PackedFloat32Array,
	grid: Dictionary,
	align: bool,
	window: Rect2
) -> Dictionary:
	var stride := MapDocument.ROW_STRIDE
	var columns: int = grid.columns
	var rows_count: int = grid.rows
	var step: Vector2 = grid.step
	var half: Vector2 = grid.half
	var out := current
	var copied := false
	var moved := PackedInt32Array()
	for r in start.size() / stride:
		var b := r * stride
		var p := Vector2(start[b], start[b + 2])
		if not window.has_point(p):
			continue
		var at := (p + half) / step
		var was := ScatterGenerator.triangle_height(before, columns, rows_count, at)
		var now := ScatterGenerator.triangle_height(after, columns, rows_count, at)
		var from := ScatterGenerator.triangle_normal(before, columns, rows_count, at, step)
		var to := ScatterGenerator.triangle_normal(after, columns, rows_count, at, step)
		var row := PropRows.row_at(start, r)
		if absf(now - was) > TOLERANCE_M or (align and from.angle_to(to) > TILT_TOLERANCE_RAD):
			var position := Vector3(row[0], now, row[2])
			row = PropRows.make_row(position, to, align, PropRows.row_yaw(row), row[7])
			# Keep a non-uniform scale as it was.
			row[8] = start[b + 8]
			row[9] = start[b + 9]
		if row == PropRows.row_at(current, r):
			continue
		if not copied:
			out = current.duplicate()
			copied = true
		for k in stride:
			out[b + k] = row[k]
		moved.append(r)
	return {"rows": out, "moved": moved}
