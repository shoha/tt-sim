class_name AuthoringEditor
extends RefCounted

## What authoring's brushes do to the map, apart from the gestures (BrushTool): mask strokes
## on the MapDocument (MaskStroke), the ground, scatter and Blender-scatter updates each
## frame of a stroke, hand-placed props in the AuthoredProps node, and one AuthoringHistory
## entry per stroke or prop gesture. AuthoringController creates one per opened map.
##
## Frames. BrushTool hands over world-space points; the document, the scatter rows and the
## props are all in the map root's frame (LevelMap, which carries the level's map scale and
## offset on a dressed GLB), so every point is taken into that frame here, once.
##
## Per frame of a stroke, flush() takes the samples the frame's dabs changed and makes one
## update of each consumer: AuthoredTerrain.update_biome_region (the painted ground; none on
## a dressed GLB), AuthoredScatter.request_region (regeneration on workers, grown in), and
## BaseScatterEraser.refresh (a dressed GLB's own scatter under the erase mask, shrunk out).
##
## History. A stroke records MaskStroke's per-block compressed diff; a prop gesture records
## the rows of the one 10 m cell it changed, before and after. Undo and redo re-apply the
## stored side and refresh exactly the area it covers.
##
## Height strokes (sculpting; HeightStroke, rules in HeightBrush) edit doc.heights on a map
## with an AuthoredTerrain (not on a dressed GLB, whose ground is the GLB's). Per frame,
## flush() hands the changed samples to the terrain (in-place chunk updates within
## TERRAIN_BUDGET_USEC, AuthoredTerrain.process_heights) and snaps the plants and props
## standing on the changed ground (GroundSnap, applied with AuthoredScatter.move_rows:
## transforms rewritten in place, no regrowth) within SNAP_BUDGET_USEC; work a frame's
## budget leaves is carried to the next frames through tick(). The collision is not touched
## mid-stroke (rebuilding the heightfield costs 2.3 ms a frame in the running game): the
## brush finds the ground it is shaping with raycast_ground(), a CPU ray march of the
## document's triangles. end_stroke() finishes that work, updates the collision, queues the
## settling rebuild of the edited chunks, and asks the scatter to regenerate the stroke's
## area grown by one more
## sample step than request_region() adds (normals read a sample either side), so slope
## rules add and remove plants with the grow and shrink animation while every plant that
## stays keeps its place (AuthoredScatter.row_keys leaves Y out). One history entry per
## stroke holds the heights diff and the props rows it moved; generated rows are not
## stored: undo and redo snap them back at once and regenerate the area, and generation is
## a pure function of the document.

## Emitted after every change to the map (strokes, props, undo, redo), for dirty tracking.
signal edited

## Seconds after the last Shift+wheel notch on a prop before the scale edit is recorded.
const SCALE_COMMIT_SECONDS := 0.6
## A prop's footprint for picking and its hover ring: this fraction of its widest dimension.
const FOOTPRINT_FRACTION := 0.45
## Per-frame main-thread budgets of a sculpt stroke: terrain chunk updates, and snapping
## plants and props to the new ground (docs/PERFORMANCE.md "Sculpting").
const TERRAIN_BUDGET_USEC := 4000
const SNAP_BUDGET_USEC := 2500
const HEIGHT_LABELS := {
	HeightBrush.RAISE: "Raise",
	HeightBrush.LOWER: "Lower",
	HeightBrush.SMOOTH: "Smooth",
	HeightBrush.FLATTEN: "Flatten",
	HeightBrush.TIER: "Tier",
}

var document: MapDocument = null
var map_root: Node3D = null
var terrain: AuthoredTerrain = null
var scatter: AuthoredScatter = null
var props: AuthoredScatter = null
var eraser: BaseScatterEraser = null
var history: AuthoringHistory = null
var palette_root: String = PaletteLibrary.DEFAULT_ROOT
## Microseconds of the last flush() and of the last dab, for measurement.
var last_flush_usec: int = 0
var last_dab_usec: int = 0
## Microseconds of the last frame of height work, by part, and rows moved, for measurement.
var last_terrain_usec: int = 0
var last_collision_usec: int = 0
var last_snap_usec: int = 0
var last_snap_rows: int = 0

var _stroke: MaskStroke = null
var _stroke_label: String = ""
var _height: HeightStroke = null
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
## Props asset id -> true when its species stands on the ground normal (cached).
var _prop_aligned: Dictionary = {}
## True when heights changed since the collision was last updated (it is updated once no
## sculpt stroke is in progress; see raycast_ground).
var _collision_dirty: bool = false
## False while an undo sets props from history instead of snapping them.
var _snap_props: bool = true
var _worked_frame: int = -1
## An in-progress prop gesture: {"cell", "before": cell rows, "label", "handle"}.
var _prop_edit: Dictionary = {}
var _prop_edit_age: float = 0.0
var _rng := RandomNumberGenerator.new()


static func create(
	doc: MapDocument, root: Node3D, hist: AuthoringHistory, root_path: String = ""
) -> AuthoringEditor:
	var editor := AuthoringEditor.new()
	editor.document = doc
	editor.map_root = root
	editor.history = hist
	if root_path != "":
		editor.palette_root = root_path
	if root:
		editor.terrain = root.get_node_or_null("AuthoredTerrain") as AuthoredTerrain
		editor.scatter = root.get_node_or_null(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
		editor.props = root.get_node_or_null(MapSourceLoader.PROPS_NODE) as AuthoredScatter
		if doc.has_base_map:
			editor.eraser = BaseScatterEraser.create(root, doc)
	editor._rng.randomize()
	return editor


## Loads a biome's assets and ground surface in the background, so its first dab does not
## wait on them.
func prepare_biome(biome_id: String) -> void:
	if is_instance_valid(scatter):
		scatter.prepare_biome(biome_id)
	if is_instance_valid(terrain):
		terrain.warm_biome_surface(biome_id)


# ============================================================================
# Mask strokes
# ============================================================================


## Starts a stroke (MaskBrush.PAINT with `biome_id`, THIN or CLEAR). False when there is
## nothing it could change.
func begin_stroke(mode: int, biome_id: String = "") -> bool:
	commit_prop_edit()
	if is_stroking():
		end_stroke()
	_stroke = MaskStroke.begin(document, mode, biome_id)
	if _stroke == null or not _stroke.writes_anything():
		_stroke = null
		return false
	_stroke_label = {
		MaskBrush.PAINT: "Paint biome", MaskBrush.THIN: "Thin", MaskBrush.CLEAR: "Clear"
	}[mode]
	return true


func is_stroking() -> bool:
	return _stroke != null or _height != null


## Exposes the capsule from `from` to `to` (world space) of world radius `radius` for
## `seconds`, for whichever stroke is in progress (mask or height). Call flush() once after
## the frame's dabs.
func stroke_dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if _height != null:
		height_dab(from, to, radius, seconds)
		return
	if _stroke == null:
		return
	var started := Time.get_ticks_usec()
	_stroke.dab(to_map_xz(from), to_map_xz(to), radius / map_scale(), seconds)
	last_dab_usec = Time.get_ticks_usec() - started


## Pushes this frame's changes to their consumers: mask changes to the ground, the scatter
## and the Blender scatter; height changes to the terrain, collision, plants and props.
func flush() -> void:
	if _height != null:
		var started := Time.get_ticks_usec()
		_queue_heights(_height.take_pending())
		_work()
		last_flush_usec = Time.get_ticks_usec() - started
		return
	if _stroke == null:
		return
	_refresh(_stroke.take_pending())


## Ends the stroke and records it for undo. True when it changed anything.
func end_stroke() -> bool:
	if _height != null:
		return _end_height_stroke()
	if _stroke == null:
		return false
	flush()
	var diff := _stroke.finish()
	_stroke = null
	if diff.is_empty():
		return false
	(
		history
		. record(
			{
				"label": _stroke_label,
				"undo": _apply_diff.bind(diff, false),
				"redo": _apply_diff.bind(diff, true),
				"bytes": int(diff.bytes),
			}
		)
	)
	edited.emit()
	return true


## Abandons the stroke in progress, putting every sample back.
func cancel_stroke() -> void:
	if _height != null:
		_cancel_height_stroke()
		return
	if _stroke == null:
		return
	var rect := _stroke.revert()
	_stroke = null
	_refresh(rect)


func _apply_diff(diff: Dictionary, redo: bool) -> void:
	_refresh(MaskStroke.apply_diff(document, diff, redo))


## One update of every consumer for the samples of `sample_rect`.
func _refresh(sample_rect: Rect2i) -> void:
	if not sample_rect.has_area():
		return
	var started := Time.get_ticks_usec()
	if is_instance_valid(terrain):
		terrain.update_biome_region(sample_rect.grow(1))
	var world := MaskBrush.sample_rect_to_world(document, sample_rect)
	if is_instance_valid(scatter):
		scatter.request_region(world)
	if eraser != null:
		eraser.refresh(document, world.grow(document.sample_step().x))
	last_flush_usec = Time.get_ticks_usec() - started


# ============================================================================
# Height strokes
# ============================================================================


## True when the map's ground can be sculpted: it is an AuthoredTerrain (a dressed GLB's
## ground is the GLB's own).
func can_sculpt() -> bool:
	return (
		is_instance_valid(terrain)
		and not document.has_base_map
		and document.heights.size() == document.sample_count()
	)


## Starts a sculpt stroke of HeightBrush operation `op`. `target_y` (world height) is the
## goal of FLATTEN and TIER (the height under the press, or a tier height; see
## ground_height_at and HeightBrush.tier_height). False when the map cannot be sculpted.
func begin_height_stroke(op: int, target_y: float = 0.0) -> bool:
	commit_prop_edit()
	if is_stroking():
		end_stroke()
	if not can_sculpt():
		return false
	finish_height_work()
	_height = HeightStroke.begin(document, op, to_map(Vector3(0.0, target_y, 0.0)).y)
	if _height == null:
		return false
	_stroke_label = HEIGHT_LABELS.get(op, "Sculpt")
	_snap_before = _height.start_heights
	_snap_windows.clear()
	_snap_start.clear()
	_prop_start.clear()
	_aligned = DressingGround.aligned_assets(document.biome_ids, palette_root)
	return true


## One frame's exposure of the sculpt stroke (as stroke_dab(), which forwards here while a
## height stroke is in progress). Call flush() once after the frame's dabs.
func height_dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if _height == null:
		return
	var started := Time.get_ticks_usec()
	_height.dab(to_map_xz(from), to_map_xz(to), radius / map_scale(), seconds)
	last_dab_usec = Time.get_ticks_usec() - started


## True while a sculpt (height) stroke is in progress.
func is_sculpting() -> bool:
	return _height != null


## Where a ray (world space) meets the ground of the document as it is now: {"position",
## "normal"} in world space, or {} for a miss. The collision is only brought up to date
## when a sculpt stroke ends (rebuilding the whole heightfield costs 2.3 ms on a 200 ft map
## in the running game, too much for every frame), so while one is in progress the brush
## finds the ground it is shaping here: TerrainMeshBuilder.raycast over the same triangles.
func raycast_ground(
	origin: Vector3, direction: Vector3, max_distance: float = 1000.0
) -> Dictionary:
	var inverse := (
		map_root.global_transform.affine_inverse()
		if is_instance_valid(map_root)
		else Transform3D.IDENTITY
	)
	var span := terrain.height_range() if is_instance_valid(terrain) else Vector2.ZERO
	if _height != null:
		# Chunks the terrain has not caught up with yet are not in its range.
		span = Vector2(minf(span.x, _height.written_span.x), maxf(span.y, _height.written_span.y))
	var hit := TerrainMeshBuilder.raycast(
		document, inverse * origin, inverse.basis * direction, max_distance / map_scale(), span
	)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.normal
	if is_instance_valid(map_root):
		normal = (map_root.global_transform.basis.inverse().transposed() * normal).normalized()
	return {"position": to_world(hit.position), "normal": normal}


## The ground height (world Y) under world point `point`, on the terrain's own triangles:
## the height Flatten holds and the one a Tier steps from.
func ground_height_at(point: Vector3) -> float:
	var local := to_map(point)
	var at := document.world_to_sample(Vector2(local.x, local.z))
	var heights := TerrainMeshBuilder.collision_heights(document)
	var y := ScatterGenerator.triangle_height(
		heights, document.samples_x(), document.samples_z(), at
	)
	return to_world(Vector3(local.x, y, local.z)).y


## True while terrain, collision or snapping work from a sculpt stroke (or its undo) is
## still being spread over frames.
func has_height_work() -> bool:
	return (
		not _snap_windows.is_empty()
		or (_collision_dirty and _height == null)
		or (is_instance_valid(terrain) and terrain.has_height_work())
	)


## One frame's share of the height work still waiting, at most once per frame whoever calls
## (tick(), and AuthoringController every frame, so the work drains after the brush is put
## away too).
func step_height_work() -> void:
	if Engine.get_process_frames() != _worked_frame and has_height_work():
		_work()


func _queue_heights(sample_rect: Rect2i) -> void:
	if not sample_rect.has_area():
		return
	if is_instance_valid(terrain):
		terrain.queue_heights(sample_rect)
	_collision_dirty = true
	var grid := Rect2i(0, 0, document.samples_x(), document.samples_z())
	# A row's height reads its triangle's corners and its normal their neighbours: two samples.
	var reach := sample_rect.grow(2).intersection(grid)
	var window := MaskBrush.sample_rect_to_world(document, reach)
	for cell in ScatterGenerator.cells_in_bounds(window):
		var queued: Rect2 = _snap_windows.get(cell, Rect2())
		_snap_windows[cell] = window if queued.size == Vector2.ZERO else queued.merge(window)


## One frame of height work within the budgets (at most once per frame; tick() calls it on
## frames without a dab so the work drains). `everything` ignores the budgets.
func _work(everything: bool = false) -> void:
	_worked_frame = Engine.get_process_frames()
	var started := Time.get_ticks_usec()
	if is_instance_valid(terrain):
		terrain.process_heights(-1 if everything else TERRAIN_BUDGET_USEC)
	last_terrain_usec = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	# Not mid-stroke: the whole heightfield is rebuilt (2.3 ms on a 200 ft map in the running
	# game), and the brush reads the document meanwhile (raycast_ground).
	if _collision_dirty and _height == null and is_instance_valid(terrain):
		terrain.update_collision()
		_collision_dirty = false
	last_collision_usec = Time.get_ticks_usec() - started
	_snap(-1 if everything else SNAP_BUDGET_USEC)


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
	var grid := GroundSnap.grid_of(document)
	var after := document.heights
	var moved := 0
	if is_instance_valid(scatter):
		var current: Dictionary = scatter.cell_rows(cell)
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
			var snapped := GroundSnap.snap_rows(from, rows, _snap_before, after, grid, tilt, window)
			moved += _apply_moved(scatter, cell, asset_id, snapped)
	if _snap_props and is_instance_valid(props):
		var placed: Dictionary = props.cell_rows(cell)
		if not placed.is_empty() and not _prop_start.has(cell):
			_prop_start[cell] = placed.duplicate(true)
		var start_props: Dictionary = _prop_start.get(cell, {})
		for asset_id in placed.keys():
			var rows: PackedFloat32Array = placed[asset_id]
			var from: PackedFloat32Array = start_props.get(asset_id, PackedFloat32Array())
			if from.size() != rows.size():
				continue
			var snapped := GroundSnap.rebed_props(
				from, rows, _snap_before, after, grid, _prop_aligns(asset_id), window
			)
			moved += _apply_moved(props, cell, asset_id, snapped)
	return moved


func _apply_moved(
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


## True when prop asset `asset_id` stands on the ground normal (its species' "align").
func _prop_aligns(asset_id: String) -> bool:
	if not _prop_aligned.has(asset_id):
		_prop_aligned[asset_id] = rule_for_asset(asset_id).get("align", "upright") == "normal"
	return _prop_aligned[asset_id]


## Does every piece of height work still waiting (terrain, collision, snapping, settling
## rebuilds), at once.
func finish_height_work() -> void:
	if has_height_work():
		_work(true)


func _end_height_stroke() -> bool:
	var stroke := _height
	_height = null
	# The last frame's changes, then everything left, the collision included (no stroke now).
	_queue_heights(stroke.take_pending())
	_work(true)
	var diff := stroke.finish()
	if is_instance_valid(terrain):
		terrain.settle_heights()
	if diff.is_empty():
		return false
	var props_before := {}
	var props_after := {}
	for cell in _prop_start:
		props_before[cell] = (_prop_start[cell] as Dictionary).duplicate(true)
		props_after[cell] = props.cell_rows(cell).duplicate(true)
	_regenerate(stroke.changed)
	var props_bytes := 0
	for cell in props_before:
		props_bytes += _rows_bytes(props_before[cell]) + _rows_bytes(props_after[cell])
	(
		history
		. record(
			{
				"label": _stroke_label,
				"undo": _apply_height_diff.bind(diff, false, props_before),
				"redo": _apply_height_diff.bind(diff, true, props_after),
				"bytes": int(diff.bytes) + props_bytes,
			}
		)
	)
	edited.emit()
	return true


func _cancel_height_stroke() -> void:
	var stroke := _height
	_height = null
	_snap_windows.clear()
	var rect := stroke.revert()
	# Every row goes back to exactly where it stood.
	for cell in _snap_start:
		var start: Dictionary = _snap_start[cell]
		var current: Dictionary = scatter.cell_rows(cell) if is_instance_valid(scatter) else {}
		for asset_id in start:
			var rows: PackedFloat32Array = current.get(asset_id, PackedFloat32Array())
			if rows.size() == (start[asset_id] as PackedFloat32Array).size():
				scatter.move_rows(cell, asset_id, start[asset_id], _all_rows(rows))
	for cell in _prop_start:
		_set_prop_cell(cell, _prop_start[cell])
	_snap_start.clear()
	_prop_start.clear()
	# The collision was never updated during the stroke, so it already has these heights.
	_collision_dirty = false
	if rect.has_area() and is_instance_valid(terrain):
		terrain.queue_heights(rect)
	_work(true)
	if is_instance_valid(terrain):
		terrain.settle_heights()


## Undo (`redo` false) or redo of a sculpt stroke: the heights side, the terrain and
## collision at once, generated plants snapped to the restored ground and their area
## regenerated, props set to the rows recorded for that side.
func _apply_height_diff(diff: Dictionary, redo: bool, prop_rows: Dictionary) -> void:
	finish_height_work()
	var before := document.heights.duplicate()
	var rect := HeightStroke.apply_diff(document, diff, redo)
	if not rect.has_area():
		return
	_snap_before = before
	_snap_start.clear()
	_prop_start.clear()
	_aligned = DressingGround.aligned_assets(document.biome_ids, palette_root)
	_queue_heights(rect)
	# Props take their recorded rows, not a snap.
	_snap_props = false
	_work(true)
	_snap_props = true
	_snap_start.clear()
	for cell in prop_rows:
		_set_prop_cell(cell, prop_rows[cell])
	if is_instance_valid(terrain):
		terrain.settle_heights()
	_regenerate(rect)


## Regenerates the scatter over the sample rectangle `rect` of a height edit.
func _regenerate(rect: Rect2i) -> void:
	if not is_instance_valid(scatter) or not rect.has_area():
		return
	var step := document.sample_step()
	# request_region() grows by each species' reach plus one step; normals need one more.
	scatter.request_region(
		MaskBrush.sample_rect_to_world(document, rect).grow(maxf(step.x, step.y))
	)


static func _all_rows(rows: PackedFloat32Array) -> PackedInt32Array:
	var all := PackedInt32Array()
	@warning_ignore("integer_division")
	for r in rows.size() / MapDocument.ROW_STRIDE:
		all.append(r)
	return all


# ============================================================================
# Frames
# ============================================================================


## World point -> document-local XZ.
func to_map_xz(world: Vector3) -> Vector2:
	var local := to_map(world)
	return Vector2(local.x, local.z)


func to_map(world: Vector3) -> Vector3:
	if not is_instance_valid(map_root):
		return world
	return map_root.global_transform.affine_inverse() * world


func to_world(local: Vector3) -> Vector3:
	if not is_instance_valid(map_root):
		return local
	return map_root.global_transform * local


## The map root's horizontal scale (world metres per document metre).
func map_scale() -> float:
	if not is_instance_valid(map_root):
		return 1.0
	return maxf(map_root.global_transform.basis.get_scale().x, 0.0001)


# ============================================================================
# Props
# ============================================================================


## The species rule `species_key` of palette biome `biome_id`, or {}.
func species_rule(biome_id: String, species_key: String) -> Dictionary:
	for rule in PaletteLibrary.species(biome_id, palette_root):
		if rule.get("key", "") == species_key:
			return rule
	return {}


## The species rule that places palette asset `asset_id` (its biome is the id's first path
## segment), or {}.
func rule_for_asset(asset_id: String) -> Dictionary:
	var biome_id := asset_id.get_slice("/", 0)
	for rule in PaletteLibrary.species(biome_id, palette_root):
		if asset_id in rule.get("assets", []):
			return rule
	return {}


## Places one of the species' assets at world point `hit` on ground with world normal
## `normal`, random yaw and scale 1. Returns the prop's handle {"asset_id", "row"}, or {}.
## The gesture is recorded when commit_prop_edit() runs (BrushTool calls it on release).
func place_prop(rule: Dictionary, hit: Vector3, normal: Vector3) -> Dictionary:
	commit_prop_edit()
	if not is_instance_valid(props):
		return {}
	var assets: Array = rule.get("assets", [])
	if assets.is_empty():
		return {}
	var asset_id := String(assets[_rng.randi_range(0, assets.size() - 1)])
	var local_normal := (map_root.global_transform.basis.inverse() * normal).normalized()
	var row := PropRows.make_row(
		to_map(hit),
		local_normal,
		rule.get("align", "upright") == "normal",
		_rng.randf_range(-PI, PI),
		1.0
	)
	var cell := cell_of(row)
	_begin_prop_edit(cell, "Place")
	var rows := _cell_rows(cell)
	var joined: PackedFloat32Array = rows.get(asset_id, PackedFloat32Array()).duplicate()
	joined.append_array(row)
	rows[asset_id] = joined
	props.set_cells({cell: rows}, true)
	var handle := {"asset_id": asset_id, "row": row}
	_prop_edit.handle = handle
	return handle


## Turns a prop to `yaw` radians. Returns its new handle.
func turn_prop(handle: Dictionary, yaw: float) -> Dictionary:
	return _edit_prop(handle, PropRows.with_yaw(handle.row, yaw), "Turn")


## Scales a prop by `notches` wheel steps within its species' range (rule from
## species_rule). Returns its new handle.
func scale_prop(handle: Dictionary, notches: float, rule: Dictionary) -> Dictionary:
	var row: PackedFloat32Array = handle.row
	var scale := PropRows.stepped_scale(row[7], notches, PropRows.scale_range(rule))
	var edited_handle := _edit_prop(handle, PropRows.with_scale(row, scale), "Scale")
	_prop_edit_age = 0.0
	return edited_handle


## Removes a prop (it shrinks away) and records the removal.
func remove_prop(handle: Dictionary) -> void:
	commit_prop_edit()
	var cell := cell_of(handle.row)
	var rows := _cell_rows(cell)
	var index := _index_in(rows, handle)
	if index < 0:
		return
	_begin_prop_edit(cell, "Remove")
	rows[handle.asset_id] = PropRows.removed(rows[handle.asset_id], index)
	props.set_cells({cell: rows}, true)
	commit_prop_edit()


## The prop under world point `point`, as a handle plus "radius" (world metres, for the
## hover ring), or {}.
func prop_at(point: Vector3) -> Dictionary:
	if not is_instance_valid(props):
		return {}
	var local := to_map_xz(point)
	var rows_by_asset := {}
	var cell := Vector2i(
		floori(local.x / ScatterChunker.CHUNK_SIZE_WORLD_UNITS),
		floori(local.y / ScatterChunker.CHUNK_SIZE_WORLD_UNITS)
	)
	# A prop's footprint never reaches past the neighbouring cells.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var rows: Dictionary = props.cell_rows(cell + Vector2i(dx, dz))
			for asset_id in rows:
				var joined: PackedFloat32Array = rows_by_asset.get(asset_id, PackedFloat32Array())
				joined.append_array(rows[asset_id])
				rows_by_asset[asset_id] = joined
	var hit := PropRows.pick(rows_by_asset, local, footprint_radius)
	if hit.is_empty():
		return {}
	var row := PropRows.row_at(rows_by_asset[hit.asset_id], hit.index)
	return {
		"asset_id": hit.asset_id,
		"row": row,
		"radius": footprint_radius(hit.asset_id) * row[7] * map_scale(),
	}


## Footprint radius of a palette asset at scale 1 (document metres).
func footprint_radius(asset_id: String) -> float:
	var dimensions: Variant = PaletteLibrary.asset(asset_id, palette_root).get("dimensions_m")
	if dimensions is Array and (dimensions as Array).size() >= 3:
		return maxf(float(dimensions[0]), float(dimensions[2])) * FOOTPRINT_FRACTION
	return 0.5


## World position of a prop handle.
func prop_position(handle: Dictionary) -> Vector3:
	var row: PackedFloat32Array = handle.row
	return to_world(Vector3(row[0], row[1], row[2]))


## Records the prop gesture in progress, if any.
func commit_prop_edit() -> void:
	if _prop_edit.is_empty():
		return
	var cell: Vector2i = _prop_edit.cell
	var before: Dictionary = _prop_edit.before
	var after := _cell_rows(cell)
	var label: String = _prop_edit.label
	_prop_edit = {}
	if _same_rows(before, after):
		return
	(
		history
		. record(
			{
				"label": label,
				"undo": _set_prop_cell.bind(cell, before),
				"redo": _set_prop_cell.bind(cell, after),
				"bytes": _rows_bytes(before) + _rows_bytes(after),
			}
		)
	)
	edited.emit()


## Drops the prop gesture in progress, putting its cell back as it was (a cancelled
## placement: the new prop shrinks away and nothing is recorded).
func cancel_prop_edit() -> void:
	if _prop_edit.is_empty():
		return
	var cell: Vector2i = _prop_edit.cell
	var before: Dictionary = _prop_edit.before
	_prop_edit = {}
	_set_prop_cell(cell, before)


## Once per frame (BrushTool calls it): carries height work a frame's budget left over
## (terrain, collision, snapping, the settling rebuilds after a stroke) and advances the idle
## timer of a scale gesture, committing it after SCALE_COMMIT_SECONDS.
func tick(delta: float) -> void:
	step_height_work()
	if _prop_edit.get("label", "") != "Scale":
		return
	_prop_edit_age += delta
	if _prop_edit_age >= SCALE_COMMIT_SECONDS:
		commit_prop_edit()


func _edit_prop(handle: Dictionary, row: PackedFloat32Array, label: String) -> Dictionary:
	var cell := cell_of(handle.row)
	var rows := _cell_rows(cell)
	var index := _index_in(rows, handle)
	if index < 0:
		return handle
	if _prop_edit.is_empty() or _prop_edit.cell != cell:
		commit_prop_edit()
		_begin_prop_edit(cell, label)
	props.complete_growth()
	rows[handle.asset_id] = PropRows.replaced(rows[handle.asset_id], index, row)
	props.set_cells({cell: rows}, false)
	var edited_handle := {"asset_id": handle.asset_id, "row": row}
	_prop_edit.handle = edited_handle
	return edited_handle


func _begin_prop_edit(cell: Vector2i, label: String) -> void:
	if not _prop_edit.is_empty() and _prop_edit.cell == cell:
		return
	commit_prop_edit()
	_prop_edit = {"cell": cell, "before": _cell_rows(cell), "label": label}
	_prop_edit_age = 0.0


func _set_prop_cell(cell: Vector2i, rows: Dictionary) -> void:
	if is_instance_valid(props):
		props.set_cells({cell: rows.duplicate(true)}, true)


## A deep copy of a props cell's rows (asset id -> flat rows). Deep, because packed arrays
## are shared by reference in GDScript and history must not alias the live rows.
func _cell_rows(cell: Vector2i) -> Dictionary:
	return props.cell_rows(cell).duplicate(true) if is_instance_valid(props) else {}


## The 10 m cell a row's origin falls in.
static func cell_of(row: PackedFloat32Array) -> Vector2i:
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	return Vector2i(floori(row[0] / size), floori(row[2] / size))


static func _index_in(rows: Dictionary, handle: Dictionary) -> int:
	var flat: PackedFloat32Array = rows.get(handle.asset_id, PackedFloat32Array())
	var row: PackedFloat32Array = handle.row
	@warning_ignore("integer_division")
	for r in flat.size() / PropRows.STRIDE:
		if PropRows.row_at(flat, r) == row:
			return r
	return -1


static func _same_rows(a: Dictionary, b: Dictionary) -> bool:
	var keys := {}
	keys.merge(a)
	keys.merge(b)
	for asset_id in keys:
		var left: PackedFloat32Array = a.get(asset_id, PackedFloat32Array())
		var right: PackedFloat32Array = b.get(asset_id, PackedFloat32Array())
		if left != right:
			return false
	return true


static func _rows_bytes(rows: Dictionary) -> int:
	var total := 0
	for asset_id in rows:
		total += (rows[asset_id] as PackedFloat32Array).size() * 4
	return total
