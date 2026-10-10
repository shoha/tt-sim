class_name HeightEditor
extends RefCounted

## AuthoringEditor's height edits (`AuthoringEditor.heights`): sculpt strokes (HeightStroke,
## rules in HeightBrush) on a map with an AuthoredTerrain, their undo and redo, and the ground
## machinery sculpt strokes, water edits (WaterEditor) and live edits (LiveEditCodec) share:
## the height queue, the per-frame snap of plants and props onto changed ground, rock keeping
## and the scatter regeneration. It is part of the editor, split out only to keep one class a
## readable size, and reaches into the editor for the document, the nodes and the history.
## Frames: world in, document inside, as the editor.
##
## Per frame of a stroke, flush() updates the terrain's chunks in place within
## TERRAIN_BUDGET_USEC and snaps the plants and props on the changed ground (GroundSnap,
## AuthoredScatter.move_rows) within SNAP_BUDGET_USEC, carrying leftovers through step(); the
## collision waits for the stroke's end (AuthoringEditor.raycast_ground() marches the
## document's triangles meanwhile). end_stroke() finishes the work, updates the collision,
## settles the chunks and regenerates the scatter over the stroke grown by what the slope,
## cliff and face rules read (regenerated_area); one history entry holds the heights diff and
## the props rows moved, and the rocks the regeneration would remove become props in it
## (RockKeeper).
##
## Undo and redo (apply_diff) put one side back. From history they do all of the work at once.
## A live edit passes `spread`: the heights go into the document and the queue, and the call
## returns; step() then drains the chunks and the snap within the same budgets, gives the
## collision a frame of its own and, on the frame after, lands the rest (after_work: props,
## kept rocks, the terrain's settle, the wet dressing, the regeneration). Anything that must see
## an edit whole calls finish_work() first; every edit and undo does.

## Per-frame main-thread budgets of height work: terrain chunk updates, and snapping plants
## and props to the new ground (docs/PERFORMANCE.md "Sculpting").
const TERRAIN_BUDGET_USEC := 4000
const SNAP_BUDGET_USEC := 2500
## History labels of the sculpt operations.
const LABELS := {
	HeightBrush.RAISE: "Raise",
	HeightBrush.LOWER: "Lower",
	HeightBrush.SMOOTH: "Smooth",
	HeightBrush.FLATTEN: "Flatten",
	HeightBrush.TIER: "Tier",
	HeightBrush.TIER_CUT: "Cut tier",
}

## Microseconds of the last frame of height work, by part, and rows moved, for measurement.
var last_terrain_usec: int = 0
var last_collision_usec: int = 0
var last_snap_usec: int = 0
var last_snap_rows: int = 0

var _stroke: HeightStroke = null
var _label: String = ""
## Heights the snap start rows stood on (the stroke's start heights; kept after the stroke
## until its snap work is done).
var _snap_before: PackedFloat32Array = PackedFloat32Array()
## cell -> Rect2 (map XZ) of ground changed since that cell's plants were last snapped.
var _snap_windows: Dictionary = {}
## cell -> {asset id -> rows} of scatter and of props as they were when the stroke began.
var _snap_start: Dictionary = {}
var _prop_start: Dictionary = {}
## Scatter asset ids placed normal-aligned (DressingGround.aligned_assets), per stroke.
var _aligned: Dictionary = {}
## Scatter asset id -> species rule of the rock species (RockKeep.rock_assets), per stroke.
var _rocks: Dictionary = {}
## Props asset id -> _prop_bedding() (cached).
var _prop_rules: Dictionary = {}
## True when heights changed since the collision was last updated (it is updated once no
## sculpt stroke is in progress; see AuthoringEditor.raycast_ground).
var _collision_dirty: bool = false
## False while an undo, a redo or a live edit sets props from its record instead of snapping.
var _snap_props: bool = true
var _worked_frame: int = -1
## What an apply does once its queued work has drained (after_work()), or none.
var _landing: Callable = Callable()
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> HeightEditor:
	var heights := HeightEditor.new()
	heights._owner = weakref(editor)
	return heights


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


# ============================================================================
# Strokes
# ============================================================================


## Starts a sculpt stroke of HeightBrush operation `op` toward map height `target_y` (FLATTEN
## and TIER; world height, as AuthoringEditor.begin_height_stroke, which ends any other stroke
## first). False when the map cannot be sculpted.
func begin(op: int, target_y: float = 0.0) -> bool:
	var e := _editor()
	if not e.can_sculpt():
		return false
	finish_work()
	_stroke = HeightStroke.begin(e.document, op, e.to_map(Vector3(0.0, target_y, 0.0)).y)
	if _stroke == null:
		return false
	_label = LABELS.get(op, "Sculpt")
	begin_snap(_stroke.start_heights, true)
	return true


## True while a sculpt stroke is in progress.
func is_sculpting() -> bool:
	return _stroke != null


## The stroke's written height range (Vector2(min, max), map frame): chunks the terrain has
## not caught up with yet are not in its own range. Call only while is_sculpting().
func written_span() -> Vector2:
	return _stroke.written_span


## One frame's exposure of the stroke (world points and radius).
func dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if _stroke == null:
		return
	var e := _editor()
	var started := Time.get_ticks_usec()
	_stroke.dab(e.to_map_xz(from), e.to_map_xz(to), radius / e.map_scale(), seconds)
	e.last_dab_usec = Time.get_ticks_usec() - started


## Pushes this frame's height changes to the terrain, plants and props within the budgets.
func flush() -> void:
	var e := _editor()
	var started := Time.get_ticks_usec()
	queue_heights(_stroke.take_pending())
	work()
	e.last_flush_usec = Time.get_ticks_usec() - started


## Ends the stroke and records it (see the header). True when it changed anything.
func end_stroke() -> bool:
	var e := _editor()
	var stroke := _stroke
	_stroke = null
	# A tier finishes rising onto its goal (a quick stroke leaves a whole tier).
	stroke.complete()
	# The last frame's changes, then everything left, the collision included (no stroke now).
	queue_heights(stroke.take_pending())
	work(true)
	var diff := stroke.finish()
	if is_instance_valid(e.terrain):
		e.terrain.settle_heights()
	if diff.is_empty():
		return false
	var wet := e.document.water_dressing
	# The props side for history; kept rocks (RockKeeper) join it when their worker lands,
	# before anything can read it (finish_work); the regeneration waits for them.
	var record := {"props_before": {}, "props_after": {}, "kept": {}}
	var props_bytes := 0
	for cell in _prop_start:
		record.props_before[cell] = (_prop_start[cell] as Dictionary).duplicate(true)
		record.props_after[cell] = e.props.cell_rows(cell).duplicate(true)
		props_bytes += PropRows.rows_bytes(_prop_start[cell]) * 2
	var area := regenerated_area(stroke.changed)
	var changed_world := MaskBrush.sample_rect_to_world(e.document, stroke.changed)
	record["crossings"] = e.crossings.follow(changed_world)
	# The water follows the ground (P4-3); rocks and plants wait for its dressing's worker.
	e.water.refresh(
		func() -> void:
			if not e.rock_keeper.start(
				stroke.start_heights, stroke.changed, area, record, _rocks, wet
			):
				regenerate(stroke.changed)
	)
	(
		e
		. history
		. record(
			{
				"label": _label,
				"undo": apply_diff.bind(diff, false, record),
				"redo": apply_diff.bind(diff, true, record),
				"bytes": int(diff.bytes) + props_bytes,
			}
		)
	)
	e.edited.emit()
	return true


## Abandons the stroke, putting every sample, plant and prop back exactly.
func cancel_stroke() -> void:
	var e := _editor()
	var stroke := _stroke
	_stroke = null
	_snap_windows.clear()
	var rect := stroke.revert()
	for cell in _snap_start:
		var start: Dictionary = _snap_start[cell]
		var current: Dictionary = e.scatter.cell_rows(cell) if is_instance_valid(e.scatter) else {}
		for asset_id in start:
			var rows: PackedFloat32Array = current.get(asset_id, PackedFloat32Array())
			if rows.size() == (start[asset_id] as PackedFloat32Array).size():
				e.scatter.move_rows(cell, asset_id, start[asset_id], PropRows.all_rows(rows))
	for cell in _prop_start:
		e.set_prop_cell(cell, _prop_start[cell])
	_snap_start.clear()
	_prop_start.clear()
	# The collision was never updated during the stroke, so it already has these heights.
	_collision_dirty = false
	if rect.has_area() and is_instance_valid(e.terrain):
		e.terrain.queue_heights(rect)
	work(true)
	if is_instance_valid(e.terrain):
		e.terrain.settle_heights()


# ============================================================================
# Undo, redo and live edits
# ============================================================================


## Undo (`redo` false) or redo of a sculpt stroke: the heights side, the terrain and collision,
## generated plants snapped to the restored ground and their area regenerated, props set to the
## rows recorded for that side (`record`: {"props_before", "props_after": {cell: props rows},
## "kept": {cell: {asset id: scatter rows at the stroke's start}}, "crossings": a
## CrossingEditor.follow() record}). The rocks the stroke kept go back into the scatter on undo
## and leave it again on redo, without animation, as the props swap. All at once, or with
## `spread` queued for step() (see the header).
func apply_diff(diff: Dictionary, redo: bool, record: Dictionary, spread: bool = false) -> void:
	finish_work()
	var e := _editor()
	var before := e.document.heights.duplicate()
	var rect := HeightStroke.apply_diff(e.document, diff, redo)
	e.crossings.restore(record.get("crossings", {}), redo)
	if not rect.has_area():
		return
	# Props take their recorded rows, not a snap.
	begin_snap(before, false)
	queue_heights(rect)
	var prop_rows: Dictionary = record.props_after if redo else record.props_before
	after_work(_land_diff.bind(rect, prop_rows, record.kept, redo))
	if not spread:
		work(true)


## apply_diff()'s rest once the ground has caught up.
func _land_diff(rect: Rect2i, prop_rows: Dictionary, kept: Dictionary, redo: bool) -> void:
	var e := _editor()
	# Unanimated: a kept rock changes hands between the scatter and the props in place.
	for cell in prop_rows:
		e.set_prop_cell(cell, prop_rows[cell], false)
	e.rock_keeper.swap(kept, redo)
	if is_instance_valid(e.terrain):
		e.terrain.settle_heights()
	e.water.refresh(regenerate.bind(rect))


## Starts snapping rows onto ground that stood at heights `before` (a stroke's start, or the
## document before an undo): each cell's rows are taken as they are when it is first snapped.
## `snap_props` false leaves the props to the rows an undo, redo or live edit records.
func begin_snap(before: PackedFloat32Array, snap_props: bool) -> void:
	var e := _editor()
	_snap_before = before
	_snap_windows.clear()
	_snap_start.clear()
	_prop_start.clear()
	_snap_props = snap_props
	_aligned = DressingGround.aligned_assets(e.document.biome_ids, e.palette_root)
	_rocks = RockKeep.rock_assets(e.document.biome_ids, e.palette_root)


## Runs `then` once the queued work has drained: at the end of work(true), or on a frame of
## its own after the collision's (step()). The snap ends there (props snap again, start rows
## are dropped).
func after_work(then: Callable) -> void:
	_landing = then


## The props cells the current snap changed, as they were before it (cell -> rows).
func props_started() -> Dictionary:
	return _prop_start


## The rock assets of the current snap (RockKeep.rock_assets).
func rocks() -> Dictionary:
	return _rocks


# ============================================================================
# The queue
# ============================================================================


## True while terrain, collision, snapping or a landing from a sculpt stroke, an undo or a live
## edit is still being spread over frames, a stroke's rock keeping is still running, or a water
## edit is computing or landing.
func has_work() -> bool:
	var e := _editor()
	return (
		not _snap_windows.is_empty()
		or (_collision_dirty and _stroke == null)
		or (is_instance_valid(e.terrain) and e.terrain.has_height_work())
		or e.rock_keeper.is_running()
		or e.water.is_working()
		or _landing.is_valid()
	)


## One frame's share of the height work (a landing water edit's first, WaterEditor.step()), at
## most once per frame whoever calls (AuthoringEditor.tick(), AuthoringController every frame, a
## live edit's driver).
func step() -> void:
	_editor().water.step()
	if Engine.get_process_frames() != _worked_frame and has_work():
		work()
		finish_keep(false)


## Does every piece of height work still waiting (a water edit still computing or landing,
## terrain, collision, snapping, settling rebuilds, an apply's landing, a stroke's rock
## keeping), at once.
func finish_work() -> void:
	var e := _editor()
	e.water.finish_work()
	if has_work():
		work(true)
	if has_work():
		# An apply's landing settled the terrain (rebuilds queued) and refreshed the wet dressing.
		e.water.finish_work()
		work(true)
	finish_keep(true)


## Queues the chunks, collision and plant snap over the samples of `sample_rect`.
func queue_heights(sample_rect: Rect2i) -> void:
	if not sample_rect.has_area():
		return
	var e := _editor()
	var doc := e.document
	# Without a terrain there is no collision to update (nor would it ever be marked clean).
	if is_instance_valid(e.terrain):
		e.terrain.queue_heights(sample_rect)
		_collision_dirty = true
	var grid := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	# A row's height reads its triangle's corners and its normal their neighbours: two samples.
	var reach := sample_rect.grow(2).intersection(grid)
	var window := MaskBrush.sample_rect_to_world(doc, reach)
	for cell in ScatterGenerator.cells_in_bounds(window):
		var queued: Rect2 = _snap_windows.get(cell, Rect2())
		_snap_windows[cell] = window if queued.size == Vector2.ZERO else queued.merge(window)


## One frame of height work within the budgets (at most once per frame; step() calls it on
## frames without a dab so the work drains). `everything` ignores the budgets. Spread over
## frames, the collision (the whole heightfield: 2.3 ms on a 200 ft map in the running game)
## waits for a frame the chunks and the snap left free, and a landing for the frame after.
func work(everything: bool = false) -> void:
	var e := _editor()
	_worked_frame = Engine.get_process_frames()
	var busy := (
		not _snap_windows.is_empty()
		or (is_instance_valid(e.terrain) and e.terrain.has_height_work())
	)
	var started := Time.get_ticks_usec()
	if is_instance_valid(e.terrain):
		e.terrain.process_heights(-1 if everything else TERRAIN_BUDGET_USEC)
	last_terrain_usec = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	# Not mid-stroke: the brush reads the document meanwhile (raycast_ground).
	var collide := (
		_collision_dirty and _stroke == null and is_instance_valid(e.terrain)
		and (everything or not busy)
	)
	if collide:
		e.terrain.update_collision()
		_collision_dirty = false
	last_collision_usec = Time.get_ticks_usec() - started
	_snap(-1 if everything else SNAP_BUDGET_USEC)
	if _landing.is_valid() and (everything or not (busy or collide)):
		var landing := _landing
		_landing = Callable()
		_snap_props = true
		_snap_start.clear()
		landing.call()


## Applies the last stroke's kept rocks once their worker is done (`wait`: waits), then
## requests the stroke's regeneration.
func finish_keep(wait: bool) -> void:
	regenerate(_editor().rock_keeper.finish(wait, _rocks, _aligned, _snap_start))


## Regenerates the scatter over the sample rectangle `rect` of a height edit.
func regenerate(rect: Rect2i) -> void:
	var e := _editor()
	if not is_instance_valid(e.scatter) or not rect.has_area():
		return
	e.scatter.request_region(regenerated_area(rect))


## The map XZ rectangle whose density-side inputs a height edit of sample rectangle `rect`
## changes; request_region() then grows it by each species' reach plus one step.
func regenerated_area(rect: Rect2i) -> Rect2:
	var doc := _editor().document
	var step := doc.sample_step()
	# Normals need one step more than request_region() adds, the rules read curvature
	# CURVATURE_RADIUS_M out and face proximity FACE_NEAR_RADIUS_M more.
	var reach := TerrainRules.CURVATURE_RADIUS_M + ScatterGround.FACE_NEAR_RADIUS_M
	return MaskBrush.sample_rect_to_world(doc, rect).grow(maxf(step.x, step.y) * 2.0 + reach)


# ============================================================================
# Snapping plants and props
# ============================================================================


## Snaps plants and props in the queued cells until `budget_usec` is spent (at least one
## cell; negative: all).
func _snap(budget_usec: int) -> void:
	var started := Time.get_ticks_usec()
	var rows := 0
	var cells := 0
	for cell in _snap_windows.keys():
		if cells > 0 and budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
		var window: Rect2 = _snap_windows[cell]
		_snap_windows.erase(cell)
		rows += _snap_cell(cell, window)
		cells += 1
	last_snap_usec = Time.get_ticks_usec() - started
	last_snap_rows = rows


## Moves the scatter rows and props of `cell` whose XZ lies in `window` onto the current
## ground. Returns how many rows moved.
func _snap_cell(cell: Vector2i, window: Rect2) -> int:
	var e := _editor()
	var grid := GroundSnap.grid_of(e.document)
	var after := e.document.heights
	var moved := 0
	if is_instance_valid(e.scatter):
		var current: Dictionary = e.scatter.cell_rows(cell)
		if not _snap_start.has(cell):
			_snap_start[cell] = current.duplicate(true)
		var start: Dictionary = _snap_start[cell]
		for asset_id in current.keys():
			var rows: PackedFloat32Array = current[asset_id]
			var from: PackedFloat32Array = start.get(asset_id, PackedFloat32Array())
			if from.size() != rows.size():
				# Regenerated since the stroke began: start from what is drawn.
				from = rows.duplicate()
				start[asset_id] = from
			var tilt := _aligned.has(asset_id)
			var cap := RockKeep.MAX_TILT_RAD if _rocks.has(asset_id) else PI
			var snapped := GroundSnap.snap_rows(
				from, rows, _snap_before, after, grid, tilt, window, cap
			)
			moved += _apply_moved(e.scatter, cell, asset_id, snapped)
	if _snap_props and is_instance_valid(e.props):
		var placed: Dictionary = e.props.cell_rows(cell)
		if not placed.is_empty() and not _prop_start.has(cell):
			_prop_start[cell] = placed.duplicate(true)
		var start_props: Dictionary = _prop_start.get(cell, {})
		for asset_id in placed.keys():
			var rows: PackedFloat32Array = placed[asset_id]
			var from: PackedFloat32Array = start_props.get(asset_id, PackedFloat32Array())
			if from.size() != rows.size():
				continue
			var bed := _prop_bedding(asset_id)
			var cap := RockKeep.MAX_TILT_RAD if bed.z > 0.0 else PI
			var snapped := GroundSnap.rebed_props(
				from, rows, _snap_before, after, grid, bed.x > 0.0, window, bed.y, cap
			)
			moved += _apply_moved(e.props, cell, asset_id, snapped)
	return moved


static func _apply_moved(
	node: AuthoredScatter, cell: Vector2i, asset_id: String, snapped: Dictionary
) -> int:
	var moved: PackedInt32Array = snapped.moved
	if moved.is_empty():
		return 0
	if not node.move_rows(cell, asset_id, snapped.rows, moved):
		var rows: Dictionary = node.cell_rows(cell).duplicate()
		rows[asset_id] = snapped.rows
		node.set_cells({cell: rows}, false)
	return moved.size()


## Prop `asset_id`'s bedding: x 1 when normal-aligned, y its footing, z 1 for a (tilt-capped) rock.
func _prop_bedding(asset_id: String) -> Vector3:
	if not _prop_rules.has(asset_id):
		var rule := _editor().rule_for_asset(asset_id)
		var align := 1.0 if rule.get("align", "") == "normal" else 0.0
		var rock := 1.0 if RockKeep.is_rock(rule) else 0.0
		_prop_rules[asset_id] = Vector3(align, GroundSnap.footing_radius(rule), rock)
	return _prop_rules[asset_id]
