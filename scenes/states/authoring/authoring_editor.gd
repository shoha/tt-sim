class_name AuthoringEditor
extends RefCounted

## What authoring's brushes do to the map, apart from the gestures (BrushTool): mask strokes
## on the MapDocument (MaskStroke), the ground, scatter and Blender-scatter updates each
## frame of a stroke, hand-placed props in the AuthoredProps node, and one AuthoringHistory
## entry per stroke or prop gesture. AuthoringController creates one per opened map.
##
## Frames. BrushTool hands over world points; the document, scatter rows and props are in the
## map root's frame (LevelMap: the level's map scale and offset), taken into it here, once.
##
## Per frame of a stroke, flush() takes the samples the frame's dabs changed and makes one
## update of each consumer: AuthoredTerrain.update_ground_region (the painted ground; none on
## a dressed GLB), AuthoredScatter.request_region (regeneration on workers, grown in), and
## BaseScatterEraser.refresh (a dressed GLB's own scatter under the erase mask, shrunk out).
##
## History. A stroke records MaskStroke's per-block compressed diff, a prop gesture its 10 m
## cell's rows before and after; undo and redo re-apply a side and refresh exactly its area.
## The redo methods are public (apply_mask_diff, apply_surface_diff, set_prop_cell,
## HeightEditor.apply_diff, WaterEditor.apply_edit, CrossingEditor.apply_list): a live edit
## during play (LiveEditCodec) is one entry's after side, applied through them on a peer.
##
## Height strokes (Sculpt): `heights` (HeightEditor) runs them and owns the height work
## (terrain chunks, collision, plant and prop snapping within per-frame budgets) that sculpt
## strokes, water edits and live edits share; the stroke entry points here forward to it.
##
## Surface strokes (Paint; SurfaceStroke) paint or erase surfaces on an AuthoredTerrain; flush()
## blits the weight texels; scatter follows at the end only for surfaces that clear plants.
##
## Water (P4-3, P4-4): `water` (WaterEditor) carves, paints and erases water (stroke_dab etc.);
## crossings (P4b-1): `crossings` (CrossingEditor), following sculpt and water edits (P4b-2).

## Emitted after every change to the map (strokes, props, undo, redo), for dirty tracking.
signal edited

## Seconds after the last Shift+wheel notch on a prop before the scale edit is recorded.
const SCALE_COMMIT_SECONDS := 0.6

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
## Rocks survive terrain changes: the rocks a sculpt stroke keeps (made by create()).
var rock_keeper: RockKeeper = null
## The height (P3), water (P4-3) and crossing (P4b-1) edits, made by create().
var heights: HeightEditor = null
var water: WaterEditor = null
var crossings: CrossingEditor = null

var _stroke: MaskStroke = null
var _stroke_label: String = ""
var _surface: SurfaceStroke = null
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
		if is_instance_valid(editor.scatter) and is_instance_valid(editor.props):
			# Kept (and placed) rocks keep generated twins from growing inside them.
			editor.scatter.blocker_source = editor.props
	editor.rock_keeper = RockKeeper.create(doc, editor.scatter, editor.props, editor.palette_root)
	editor.heights = HeightEditor.create(editor)
	editor.water = WaterEditor.create(editor)
	editor.crossings = CrossingEditor.create(editor)
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
	# The last sculpt stroke's kept rocks first, so this stroke's regeneration sees them.
	heights.finish_keep(true)
	_stroke = MaskStroke.begin(document, mode, biome_id)
	if _stroke == null or not _stroke.writes_anything():
		_stroke = null
		return false
	_stroke_label = {
		MaskBrush.PAINT: "Paint biome", MaskBrush.THIN: "Thin", MaskBrush.CLEAR: "Clear"
	}[mode]
	return true


func is_stroking() -> bool:
	return (
		_stroke != null or heights.is_sculpting() or _surface != null or water.is_stroking()
	)


## Exposes the capsule from `from` to `to` (world space) of world radius `radius` for
## `seconds`, for whichever stroke is in progress (mask, height, surface, or water's pond or
## erase). Call flush() once after the frame's dabs.
func stroke_dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if water.is_stroking():
		water.dab(from, to, radius)
		return
	if heights.is_sculpting():
		heights.dab(from, to, radius, seconds)
		return
	if _surface != null:
		var began := Time.get_ticks_usec()
		_surface.dab(to_map_xz(from), to_map_xz(to), radius / map_scale(), seconds)
		last_dab_usec = Time.get_ticks_usec() - began
		return
	if _stroke == null:
		return
	var started := Time.get_ticks_usec()
	_stroke.dab(to_map_xz(from), to_map_xz(to), radius / map_scale(), seconds)
	last_dab_usec = Time.get_ticks_usec() - started


## Pushes this frame's changes to their consumers: mask changes to the ground, the scatter
## and the Blender scatter; height changes to the terrain, collision, plants and props.
func flush() -> void:
	if heights.is_sculpting():
		heights.flush()
		return
	if _surface != null:
		_refresh_ground(_surface.take_pending())
		return
	if _stroke == null:
		return
	_refresh(_stroke.take_pending())


## Ends the stroke and records it for undo. True when it changed anything.
func end_stroke() -> bool:
	if water.is_stroking():
		return water.end_stroke()
	if heights.is_sculpting():
		return heights.end_stroke()
	if _surface != null:
		return _end_surface_stroke()
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
				"undo": apply_mask_diff.bind(diff, false),
				"redo": apply_mask_diff.bind(diff, true),
				"bytes": int(diff.bytes),
			}
		)
	)
	edited.emit()
	return true


## Abandons the stroke in progress, putting every sample back.
func cancel_stroke() -> void:
	if water.is_stroking():
		water.cancel_stroke()
		return
	if heights.is_sculpting():
		heights.cancel_stroke()
		return
	if _surface != null:
		var reverted := _surface.revert()
		_surface = null
		_refresh_ground(reverted)
		return
	if _stroke == null:
		return
	var rect := _stroke.revert()
	_stroke = null
	_refresh(rect)


## Undo (`redo` false) or redo of a mask stroke (its MaskStroke diff), and a live mask edit.
func apply_mask_diff(diff: Dictionary, redo: bool) -> void:
	_refresh(MaskStroke.apply_diff(document, diff, redo))


## One update of every consumer for the samples of `sample_rect`.
func _refresh(sample_rect: Rect2i) -> void:
	if not sample_rect.has_area():
		return
	var started := Time.get_ticks_usec()
	if is_instance_valid(terrain):
		terrain.update_ground_region(sample_rect.grow(1))
	var world := MaskBrush.sample_rect_to_world(document, sample_rect)
	if is_instance_valid(scatter):
		scatter.request_region(world)
	if eraser != null:
		eraser.refresh(document, world.grow(document.sample_step().x))
	last_flush_usec = Time.get_ticks_usec() - started


# ============================================================================
# Surface strokes (the Paint tool)
# ============================================================================


## True when surfaces can be painted: the map's ground is an AuthoredTerrain (a dressed
## GLB's ground is the GLB's own, drawn by its own materials).
func can_paint() -> bool:
	return can_sculpt()


## "" when palette surface `surface` can be painted now, else why not (the Paint tile's
## tooltip and the toast a refused press shows): the map cannot be painted, or every slot
## holds paint (SurfaceStroke.slot_refusal).
func surface_refusal(surface: String) -> String:
	if not can_paint():
		return AuthoringPanel.PAINT_UNAVAILABLE_TOOLTIP
	return SurfaceStroke.slot_refusal(document, surface)


## Starts a Paint stroke: painting palette surface `surface`, or with `erase` fading every
## painted surface back to the automatic ground. False when the map cannot be painted, there
## is no paint to erase, or every slot holds paint (surface_refusal() says which).
func begin_surface_stroke(surface: String, erase: bool) -> bool:
	commit_prop_edit()
	if is_stroking():
		end_stroke()
	if not can_paint():
		return false
	finish_height_work()
	_surface = SurfaceStroke.begin(document, surface, erase)
	if _surface == null:
		return false
	var label := AuthoringPanel.surface_label(surface).to_lower()
	_stroke_label = "Erase paint" if erase else "Paint " + label
	return true


func _end_surface_stroke() -> bool:
	var stroke := _surface
	_surface = null
	_refresh_ground(stroke.take_pending())
	var diff := stroke.finish()
	if diff.is_empty():
		# Nothing painted; a slot the stroke claimed is given back (the list changed).
		_refresh_ground(Rect2i(0, 0, 1, 1))
		return false
	# A trimmed slot list re-plans the layer table on this update.
	_refresh_ground(diff.rect)
	_regenerate_paint(diff)
	(
		history
		. record(
			{
				"label": _stroke_label,
				"undo": apply_surface_diff.bind(diff, false),
				"redo": apply_surface_diff.bind(diff, true),
				"bytes": int(diff.bytes),
			}
		)
	)
	edited.emit()
	return true


## Undo (`redo` false) or redo of a Paint stroke (its SurfaceStroke diff), and a live paint edit.
func apply_surface_diff(diff: Dictionary, redo: bool) -> void:
	_refresh_ground(SurfaceStroke.apply_diff(document, diff, redo))
	_regenerate_paint(diff)


## The ground's weight maps for the samples of `sample_rect` (no scatter: see the header).
func _refresh_ground(sample_rect: Rect2i) -> void:
	if not sample_rect.has_area() or not is_instance_valid(terrain):
		return
	var started := Time.get_ticks_usec()
	terrain.update_ground_region(sample_rect.grow(1))
	last_flush_usec = Time.get_ticks_usec() - started


## Regenerates the scatter over a paint diff's area, grown by the painted edge warp and the
## path fringe (ScatterGround reads the weights that far off), when the diff involves a
## surface whose paint changes what grows (SurfaceStroke.changes_plants).
func _regenerate_paint(diff: Dictionary) -> void:
	var rect: Rect2i = diff.get("rect", Rect2i())
	if not is_instance_valid(scatter) or not rect.has_area():
		return
	if not SurfaceStroke.changes_plants(diff, PaletteLibrary.surfaces(palette_root)):
		return
	var step := document.sample_step()
	var reach := TerrainRules.PAINT_EDGE_WARP_M + ScatterGround.FRINGE_RADIUS_M
	scatter.request_region(
		MaskBrush.sample_rect_to_world(document, rect).grow(maxf(step.x, step.y) + reach)
	)


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
	return heights.begin(op, target_y)


## One frame's exposure of the sculpt stroke (as stroke_dab(), which forwards here while a
## height stroke is in progress). Call flush() once after the frame's dabs.
func height_dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	heights.dab(from, to, radius, seconds)


## True while a sculpt (height) stroke is in progress.
func is_sculpting() -> bool:
	return heights.is_sculpting()


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
	if heights.is_sculpting():
		# Chunks the terrain has not caught up with yet are not in its range.
		var written := heights.written_span()
		span = Vector2(minf(span.x, written.x), maxf(span.y, written.y))
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
	var ground := TerrainMeshBuilder.collision_heights(document)
	var y := ScatterGenerator.triangle_height(ground, document.samples_x(), document.samples_z(), at)
	return to_world(Vector3(local.x, y, local.z)).y


## The tier a Tier stroke pressed at world point `point` with a brush of world radius
## `radius` builds toward (HeightBrush.tier_target_level; `down` for a Ctrl stroke):
## {"level": int, "y": world height of that tier, "press_level": the tier the press stands
## on (the nearest)}.
func tier_target(point: Vector3, radius: float, down: bool) -> Dictionary:
	var tier_m := document.tier_height_m
	var local := to_map(point)
	var press := to_map(Vector3(point.x, ground_height_at(point), point.z)).y
	var on_level := HeightBrush.tier_level(press, tier_m)
	var near := HeightBrush.tier_neighbours(
		document,
		Vector2(local.x, local.z),
		radius / map_scale(),
		HeightBrush.tier_height(on_level, tier_m),
		tier_m
	)
	var level := HeightBrush.tier_target_level(press, tier_m, down, near.x == 1, near.y == 1)
	var y := to_world(Vector3(local.x, HeightBrush.tier_height(level, tier_m), local.z)).y
	return {"level": level, "y": y, "press_level": on_level}


## True while height work from a sculpt stroke, its undo, a water edit or a live edit is still
## being spread over frames (HeightEditor.has_work).
func has_height_work() -> bool:
	return heights.has_work()


## One frame's share of the height work, at most once per frame whoever calls (tick(), and
## AuthoringController every frame; HeightEditor.step).
func step_height_work() -> void:
	heights.step()


## Does every piece of height work still waiting at once (HeightEditor.finish_work).
func finish_height_work() -> void:
	heights.finish_work()


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
	# A prop gesture records its cell's rows: the last stroke's kept rocks must be in them.
	heights.finish_keep(true)
	if not is_instance_valid(props):
		return {}
	var assets: Array = rule.get("assets", [])
	if assets.is_empty():
		return {}
	var asset_id := String(assets[_rng.randi_range(0, assets.size() - 1)])
	var local_normal := (map_root.global_transform.basis.inverse() * normal).normalized()
	var bed := to_map(hit) - Vector3(0.0, footing_drop(rule, hit), 0.0)
	var row := PropRows.make_row(
		bed, local_normal, rule.get("align", "upright") == "normal", _rng.randf_range(-PI, PI), 1.0
	)
	var cell := PropRows.cell_of(row)
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
	heights.finish_keep(true)
	var cell := PropRows.cell_of(handle.row)
	var rows := _cell_rows(cell)
	var index := PropRows.index_of(rows, handle)
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
	var hit := PropRows.pick(rows_by_asset, local, pick_radius)
	if hit.is_empty():
		return {}
	var row := PropRows.row_at(rows_by_asset[hit.asset_id], hit.index)
	return {
		"asset_id": hit.asset_id,
		"row": row,
		"radius": PropRows.pick_extent(pick_radius(hit.asset_id), row[7]) * map_scale(),
	}


## Pick radius of a palette asset at scale 1 (document metres; PropRows.pick_radius).
func pick_radius(asset_id: String) -> float:
	return PropRows.pick_radius(asset_id, palette_root)


## GroundSnap.footing_drop of species `rule`'s base at world `point` (map metres).
func footing_drop(rule: Dictionary, point: Vector3) -> float:
	return GroundSnap.footing_drop(document, to_map_xz(point), GroundSnap.footing_radius(rule))


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
	if PropRows.same_rows(before, after):
		return
	(
		history
		. record(
			{
				"label": label,
				"undo": set_prop_cell.bind(cell, before),
				"redo": set_prop_cell.bind(cell, after),
				"bytes": PropRows.rows_bytes(before) + PropRows.rows_bytes(after),
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
	set_prop_cell(cell, before)


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
	heights.finish_keep(true)
	var cell := PropRows.cell_of(handle.row)
	var rows := _cell_rows(cell)
	var index := PropRows.index_of(rows, handle)
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


## Sets props cell `cell` to `rows` (asset id -> rows; a copy is kept): the undo and redo of a
## prop gesture, a live props edit, and the props side of a sculpt's or water edit's.
func set_prop_cell(cell: Vector2i, rows: Dictionary, animate: bool = true) -> void:
	if is_instance_valid(props):
		props.set_cells({cell: rows.duplicate(true)}, animate)


## A deep copy of a props cell's rows (asset id -> rows): history must not alias live arrays.
func _cell_rows(cell: Vector2i) -> Dictionary:
	return props.cell_rows(cell).duplicate(true) if is_instance_valid(props) else {}
