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

## Emitted after every change to the map (strokes, props, undo, redo), for dirty tracking.
signal edited

## Seconds after the last Shift+wheel notch on a prop before the scale edit is recorded.
const SCALE_COMMIT_SECONDS := 0.6
## A prop's footprint for picking and its hover ring: this fraction of its widest dimension.
const FOOTPRINT_FRACTION := 0.45

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

var _stroke: MaskStroke = null
var _stroke_label: String = ""
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
	if _stroke != null:
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
	return _stroke != null


## Exposes the capsule from `from` to `to` (world space) of world radius `radius` for
## `seconds`. Call flush() once after the frame's dabs.
func stroke_dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if _stroke == null:
		return
	var started := Time.get_ticks_usec()
	_stroke.dab(to_map_xz(from), to_map_xz(to), radius / map_scale(), seconds)
	last_dab_usec = Time.get_ticks_usec() - started


## Pushes this frame's mask changes to the ground, the scatter and the Blender scatter.
func flush() -> void:
	if _stroke == null:
		return
	_refresh(_stroke.take_pending())


## Ends the stroke and records it for undo. True when it changed anything.
func end_stroke() -> bool:
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


## Advances the idle timer of a scale gesture; commits it after SCALE_COMMIT_SECONDS.
func tick(delta: float) -> void:
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
