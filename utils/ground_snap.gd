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
##
## Footing (P3-7). A row stands at the ground height under its one origin point, so a tree
## or a boulder whose origin lies just on a tier's rim hung its trunk or its underside over
## the drop. footing_radius() gives a species' base radius (0 for ground cover, which keeps
## following the slope); footing_sag() measures how far the ground under that footprint falls
## away below the plane through the origin (the largest of h(p) - (h(p + r d) + h(p - r d)) / 2
## over FOOTING_DIRECTIONS directions: zero on flat ground and on an even slope, large on a
## convex rim; and a one-sided drop steeper than FOOTING_SLOPE_TAN); ScatterGenerator
## rejects a candidate whose sag passes FOOTING_SAG_M, and props
## (placed and re-bedded after a sculpt stroke) bed at lowest_under(), the lowest ground under
## their footprint, so nothing floats.

## A row whose ground moved less than this (and did not tilt) keeps its row.
const TOLERANCE_M := 0.0005
## Footprint sampling: the origin plus this many directions (each both ways) at the radius.
const FOOTING_DIRECTIONS := 4
## A generated tree, shrub or rock is not placed where its footprint sags more than this.
const FOOTING_SAG_M := 0.06
## A one-sided drop under the footprint counts as sag beyond the fall of a 50 degree slope
## (tan 50), so an origin in the middle of a steep face (where the ground is planar and the
## convex term is zero) is caught too, while an even hill flank is not.
const FOOTING_SLOPE_TAN := 1.19
## Base radius per species (footing_radius): a fraction of the widest asset, clamped.
const TREE_BASE_FRACTION := 0.08
const TREE_BASE_MIN_M := 0.3
const TREE_BASE_MAX_M := 0.6
const SHRUB_BASE_FRACTION := 0.15
const SHRUB_BASE_MAX_M := 0.5
## Palette species kind of fallen logs, which rest on the ground like rocks.
const DEADWOOD_KIND := "deadwood"
## Rocks and deadwood (logs) at least this wide keep a footing of this share of
## their width; smaller stones follow the slope.
const BULK_MIN_WIDTH_M := 0.5
const BULK_BASE_FRACTION := 0.3
const BULK_BASE_MAX_M := 0.9
## Normal changes below this angle (radians) do not turn a row.
const TILT_TOLERANCE_RAD := 0.0005


## The base radius (metres, at scale 1) of a species rule for footing: trees a trunk, shrubs
## a stem cluster, rocks and deadwood (logs) a share of their width, ground cover and small
## plants 0. Reads the rule's `width_m` (PaletteLibrary.species).
static func footing_radius(rule: Dictionary) -> float:
	var width := float(rule.get("width_m", 0.0))
	var size_class := String(rule.get("size_class", ""))
	if size_class == "large":
		return clampf(width * TREE_BASE_FRACTION, TREE_BASE_MIN_M, TREE_BASE_MAX_M)
	var kind := String(rule.get("kind", ""))
	if kind == ScatterGround.ROCK_KIND or kind == DEADWOOD_KIND:
		if width < BULK_MIN_WIDTH_M:
			return 0.0
		return minf(width * BULK_BASE_FRACTION, BULK_BASE_MAX_M)
	if size_class == "medium":
		return clampf(width * SHRUB_BASE_FRACTION, TREE_BASE_MIN_M, SHRUB_BASE_MAX_M)
	return 0.0


## How far the ground under a footprint of `radius` around `p` sags below the plane through
## its origin (see the header). `height_at` is Callable(Vector2) -> float in the same frame.
static func footing_sag(height_at: Callable, p: Vector2, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var h: float = height_at.call(p)
	var sag := 0.0
	var allowance := radius * FOOTING_SLOPE_TAN
	for k in FOOTING_DIRECTIONS:
		var d := Vector2.from_angle(PI * k / FOOTING_DIRECTIONS) * radius
		var a: float = height_at.call(p + d)
		var b: float = height_at.call(p - d)
		sag = maxf(sag, maxf(h - (a + b) * 0.5, h - minf(a, b) - allowance))
	return sag


## How far (metres, >= 0) the lowest ground under a footprint of `radius` around map-frame
## `p` lies below the ground at `p`, on `doc`'s heights (0 without them): what a placed prop is
## sunk by (AuthoringEditor.place_prop) and the Place cursor's warning.
static func footing_drop(doc: MapDocument, p: Vector2, radius: float) -> float:
	if doc == null or doc.heights.size() != doc.sample_count() or radius <= 0.0:
		return 0.0
	var grid := grid_of(doc)
	var here := lowest_under(doc.heights, grid, p, 0.0)
	return maxf(here - lowest_under(doc.heights, grid, p, radius), 0.0)


## True when a footprint of `radius` > 0 at `p` sags past FOOTING_SAG_M (footing_sag): a
## generated tree, shrub or rock is not placed there.
static func unfooted(height_at: Callable, p: Vector2, radius: float) -> bool:
	return radius > 0.0 and footing_sag(height_at, p, radius) > FOOTING_SAG_M


## The lowest ground height under a footprint of `radius` around map-frame XZ `p` of the
## height grid `heights` (grid_of layout): the origin and FOOTING_DIRECTIONS * 2 points on
## the circle, on the terrain's triangles.
static func lowest_under(
	heights: PackedFloat32Array, grid: Dictionary, p: Vector2, radius: float
) -> float:
	var half: Vector2 = grid.half
	var step: Vector2 = grid.step
	var at := (p + half) / step
	var lowest := ScatterGenerator.triangle_height(heights, grid.columns, grid.rows, at)
	if radius <= 0.0:
		return lowest
	for k in FOOTING_DIRECTIONS * 2:
		var q := p + Vector2.from_angle(PI * k / FOOTING_DIRECTIONS) * radius
		lowest = minf(
			lowest,
			ScatterGenerator.triangle_height(heights, grid.columns, grid.rows, (q + half) / step)
		)
	return lowest


## The height a row standing on up axis `up` is bedded at so no part of its base floats: the
## base is the plane through the ground at map-frame `p` square to `up`, sunk until it lies
## nowhere above the ground at the origin and FOOTING_DIRECTIONS * 2 points at `radius`.
## With `up` +Y this is lowest_under(); a rock tilted with an even slope does not sink at
## all, and one tilted less than a face (RockKeep's cap) or lying over a rim sinks by what
## its base would otherwise overhang.
static func bed_under(
	heights: PackedFloat32Array, grid: Dictionary, p: Vector2, radius: float, up: Vector3
) -> float:
	var half: Vector2 = grid.half
	var step: Vector2 = grid.step
	var h := ScatterGenerator.triangle_height(heights, grid.columns, grid.rows, (p + half) / step)
	if radius <= 0.0:
		return h
	var n := up.normalized() if up.y > 0.01 else Vector3.UP
	var sink := 0.0
	for k in FOOTING_DIRECTIONS * 2:
		var d := Vector2.from_angle(PI * k / FOOTING_DIRECTIONS) * radius
		var q := p + d
		var ground := ScatterGenerator.triangle_height(
			heights, grid.columns, grid.rows, (q + half) / step
		)
		var plane := h - (n.x * d.x + n.z * d.y) / n.y
		sink = maxf(sink, plane - ground)
	return h - sink


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
## differ from `current`}. A tilted row whose ground turned stands at most `max_tilt`
## radians off vertical (RockKeep.capped_rotation; rocks pass RockKeep.MAX_TILT_RAD).
@warning_ignore("integer_division")
static func snap_rows(
	start: PackedFloat32Array,
	current: PackedFloat32Array,
	before: PackedFloat32Array,
	after: PackedFloat32Array,
	grid: Dictionary,
	tilt: bool,
	window: Rect2,
	max_tilt: float = PI
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
				if max_tilt < PI:
					q = RockKeep.capped_rotation(q, max_tilt)
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
## `align` (its species stands on the ground normal), the new normal with its own yaw. With
## `radius` > 0 (footing_radius of its species) the heights compared and taken are the lowest
## under that footprint (lowest_under, scaled by the row's scale), so a prop left on a new
## rim sinks to the ground instead of hanging over the drop. An aligned prop given a
## `max_tilt` (rock props: RockKeep.MAX_TILT_RAD) stands at most that far off vertical and
## beds on its tilted base (bed_under).
@warning_ignore("integer_division")
static func rebed_props(
	start: PackedFloat32Array,
	current: PackedFloat32Array,
	before: PackedFloat32Array,
	after: PackedFloat32Array,
	grid: Dictionary,
	align: bool,
	window: Rect2,
	radius: float = 0.0,
	max_tilt: float = PI
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
		var footprint := radius * absf(start[b + 7])
		var was := lowest_under(before, grid, p, footprint)
		var now := lowest_under(after, grid, p, footprint)
		var from := ScatterGenerator.triangle_normal(before, columns, rows_count, at, step)
		var to := ScatterGenerator.triangle_normal(after, columns, rows_count, at, step)
		var row := PropRows.row_at(start, r)
		if absf(now - was) > TOLERANCE_M or (align and from.angle_to(to) > TILT_TOLERANCE_RAD):
			var position := Vector3(row[0], now, row[2])
			var up := RockKeep.capped_up(to, max_tilt) if max_tilt < PI else to
			if align and max_tilt < PI:
				# A tilted rock beds on its own tilted base (bed_under), not the lowest ground.
				position.y = bed_under(after, grid, p, footprint, up)
			row = PropRows.make_row(position, up, align, PropRows.row_yaw(row), row[7])
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
