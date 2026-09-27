class_name WaterEditor
extends RefCounted

## AuthoringEditor's water edits (phase 4, P4-3; the Water tool, P4-4, calls them through
## `AuthoringEditor.water`): carving a river, painting a pond, erasing water. It owns the
## pond and erase strokes in progress and shares the editor's ground machinery with sculpt
## strokes (the height queue, the per-frame snap of plants and props, rock keeping, the
## scatter regeneration, history), reaching into the editor for it: it is part of the editor,
## split out only to keep one class a readable size. Frames: world in, document inside, as
## the editor. Summary and the rules: docs/ARCHITECTURE.md "Carving water".
##
## Each operation is one history entry (commit()): the heights diff (HeightStroke.lower_to,
## a one-shot carve recorded like a dab), the water model before and after
## (WaterEdit.model_of), the props cells it changed and the rocks it kept; undo and redo put
## either side back exactly (_apply()). After each (and after any sculpt stroke on a map with
## water, refresh()) the wet dressing is recomputed on this thread (WaterDressing.refresh:
## the scatter jobs that follow read it), the ground's copy of it and the water surface
## (AuthoredWater.refresh_map, on a worker) are rebuilt, and the scatter regrows over the
## area grown by the shore band.

## A pond stroke in progress: {"id", "depth", "before": WaterEdit.model_of(), "rect": Rect2i
## of samples painted}, or {}.
var _pond: Dictionary = {}
## A water erase in progress: {"before", "hits": WaterEdit.hit_rivers() marks, "area": Rect2
## map XZ swept, "ponds": bool (pond samples cleared)}, or {}.
var _erase: Dictionary = {}
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> WaterEditor:
	var water := WaterEditor.new()
	water._owner = weakref(editor)
	return water


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## True when water can be carved (a river or a pond): the map's ground is an AuthoredTerrain.
## Erasing water needs no carving and works on any map with water.
func can_carve() -> bool:
	return _editor().can_sculpt()


## True while a pond or erase stroke is in progress.
func is_stroking() -> bool:
	return not _pond.is_empty() or not _erase.is_empty()


## Carves a river along `points` (world XZ as Vector2(x, z), upstream first: the water flows
## toward the last point) with a half-width per point (`half_widths`, world metres; one
## value for all points works too), of depth class `depth_class` and flow `speed`: the line
## is split into flat reaches (WaterEdit.plan_river), their channel is carved (WaterCarve),
## the water, its dressing and flow are refreshed and the plants regrow around it; one
## history entry. Returns the id of the first (upstream) reach, or -1 when nothing was made
## (the map cannot be carved, the line is too short, or the document is full).
func carve_river(
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth_class: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED
) -> int:
	var e := _editor()
	_prepare()
	if not can_carve() or points.size() < 2:
		return -1
	var doc := e.document
	var line := PackedVector2Array()
	for p in points:
		line.append(e.to_map_xz(Vector3(p.x, 0.0, p.y)))
	var widths := PackedFloat32Array()
	for w in half_widths:
		widths.append(w / e.map_scale())
	if widths.size() == 1:
		var only := widths[0]
		widths.resize(line.size())
		widths.fill(only)
	var bodies := WaterEdit.plan_river(doc, line, widths, depth_class, speed)
	if bodies.is_empty():
		return -1
	var before := WaterEdit.model_of(doc)
	var stroke := HeightStroke.begin(doc, HeightBrush.LOWER)
	var goals := WaterCarve.river_goals(doc, bodies, stroke.start_heights)
	stroke.lower_to(goals.rect, goals.goals)
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	var area := WaterEdit.rivers_bounds(bodies, WaterCarve.BANK_REACH_M)
	commit("Carve river", stroke, before, _sample_rect_of(area))
	return bodies[0].id


## Starts painting a pond of depth class `depth_class`, pressed at world point `at`: a press
## inside a pond extends it (and gives it this depth), elsewhere a new pond begins. Dabs
## (paint_pond_dab, or the editor's stroke_dab) mark its area on the sample grid;
## paint_pond_end (or end_stroke) sets its level from the lowest ground on its rim, carves the
## basin and fills it. False when the map cannot be carved or holds MAX_WATER_BODIES bodies.
func paint_pond_begin(depth_class: WaterBody.Depth, at: Vector3) -> bool:
	var e := _editor()
	_prepare()
	if not can_carve():
		return false
	var doc := e.document
	var id := WaterEdit.pond_id_at(doc, e.to_map_xz(at))
	if id <= 0:
		return false
	var before := WaterEdit.model_of(doc)
	if doc.pond_mask.size() != doc.sample_count():
		var mask := PackedByteArray()
		mask.resize(doc.sample_count())
		doc.pond_mask = mask
	_pond = {"id": id, "depth": depth_class, "before": before, "rect": Rect2i()}
	return true


## Marks the capsule from `from` to `to` (world) of world radius `radius` as the pond's area
## (samples of no other pond).
func paint_pond_dab(from: Vector3, to: Vector3, radius: float) -> void:
	if _pond.is_empty():
		return
	var e := _editor()
	var rect := WaterEdit.stamp(
		e.document,
		e.document.pond_mask,
		e.to_map_xz(from),
		e.to_map_xz(to),
		radius / e.map_scale(),
		int(_pond.id),
		PackedByteArray([0])
	)
	_pond.rect = MaskBrush.merge_rect(_pond.rect, rect)


## Ends the pond stroke: level, basin carve, water, dressing, plants; one history entry.
## False when the stroke painted nothing.
func paint_pond_end() -> bool:
	var pond := _pond
	_pond = {}
	if pond.is_empty():
		return false
	var doc := _editor().document
	var painted: Rect2i = pond.rect
	if not painted.has_area():
		WaterEdit.apply_model(doc, pond.before)
		return false
	var id: int = pond.id
	var body := WaterBody.pond(id, pond.depth, WaterGeometry.pond_rim_level(doc, id))
	var bodies: Array[WaterBody] = []
	for other in doc.water_bodies:
		if other.id != id:
			bodies.append(other)
	bodies.append(body)
	doc.water_bodies = bodies
	var stroke := HeightStroke.begin(doc, HeightBrush.LOWER)
	var goals := WaterCarve.pond_goals(doc, body, stroke.start_heights)
	stroke.lower_to(goals.rect, goals.goals)
	var region: Rect2i = goals.rect if (goals.rect as Rect2i).has_area() else painted
	commit("Paint pond", stroke, pond.before, region.merge(painted))
	return true


## Starts erasing water: dabs (erase_water_dab, or stroke_dab) remove pond area and river
## control points under the brush; erase_water_end (or end_stroke) cuts the rivers and drops
## emptied ponds. The ground stays as carved. False when the map has no water.
func erase_water_begin() -> bool:
	var doc := _editor().document
	_prepare()
	if doc.water_bodies.is_empty():
		return false
	_erase = {"before": WaterEdit.model_of(doc), "hits": {}, "area": Rect2(), "ponds": false}
	return true


## Erases the water under the capsule from `from` to `to` (world) of world radius `radius`.
func erase_water_dab(from: Vector3, to: Vector3, radius: float) -> void:
	if _erase.is_empty():
		return
	var e := _editor()
	var a := e.to_map_xz(from)
	var b := e.to_map_xz(to)
	var r := radius / e.map_scale()
	var any_pond := PackedByteArray()
	for id in range(1, WaterBody.MAX_ID + 1):
		any_pond.append(id)
	if WaterEdit.stamp(e.document, e.document.pond_mask, a, b, r, 0, any_pond).has_area():
		_erase.ponds = true
	WaterEdit.hit_rivers(e.document, _erase.hits, a, b, r)
	var swept := Rect2(a, Vector2.ZERO).expand(b).grow(r)
	var area: Rect2 = _erase.area
	_erase.area = swept if not area.has_area() else area.merge(swept)


## Ends the water erase; one history entry. False when nothing was erased.
func erase_water_end() -> bool:
	var erase := _erase
	_erase = {}
	if erase.is_empty():
		return false
	var doc := _editor().document
	var before_rivers: Array[WaterBody] = []
	for body in doc.water_bodies:
		var marks: PackedByteArray = erase.hits.get(body.id, PackedByteArray())
		if body.is_river() and marks.count(1) > 0:
			before_rivers.append(body)
	if before_rivers.is_empty() and not erase.ponds:
		return false
	doc.water_bodies = WaterEdit.erased_bodies(doc, erase.hits)
	var area: Rect2 = erase.area
	var rivers := WaterEdit.rivers_bounds(before_rivers, WaterGeometry.RIVER_BANK_M)
	if rivers.has_area():
		area = area.merge(rivers) if area.has_area() else rivers
	commit("Erase water", null, erase.before, _sample_rect_of(area))
	return true


## Forwards the editor's generic stroke calls to the pond or erase stroke in progress.
func dab(from: Vector3, to: Vector3, radius: float) -> void:
	if not _pond.is_empty():
		paint_pond_dab(from, to, radius)
	elif not _erase.is_empty():
		erase_water_dab(from, to, radius)


func end_stroke() -> bool:
	return paint_pond_end() if not _pond.is_empty() else erase_water_end()


## Abandons a pond or water erase stroke, putting the water model back.
func cancel_stroke() -> void:
	var stroke := _pond if not _pond.is_empty() else _erase
	_pond = {}
	_erase = {}
	if not stroke.is_empty():
		WaterEdit.apply_model(_editor().document, stroke.before)


## The wet dressing and the water surface from the document as it is now (see the header).
func refresh() -> void:
	var e := _editor()
	WaterDressing.refresh(e.document)
	if is_instance_valid(e.terrain):
		e.terrain.refresh_water_dressing()
	if is_instance_valid(e.map_root):
		AuthoredWater.refresh_map(e.map_root, e.document)


## Ends whatever is in progress before a water edit, so it starts from settled ground.
func _prepare() -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()


## Records and follows up one water edit (see the header): `stroke` the carve (null: none),
## `before` the water model before it (the document holds the one after), `region` the
## samples whose water, dressing or ground changed. The terrain, collision, plants and props
## follow the carve as after a sculpt stroke; the dressing and the water surface are
## rebuilt; rock props under the water or blocking a channel go (WaterCarve.keeps_rock), and
## so do the generated rocks the carve would otherwise keep; the scatter regrows.
func commit(label: String, stroke: HeightStroke, before: Dictionary, region: Rect2i) -> void:
	var e := _editor()
	var doc := e.document
	var dressing_before := doc.water_dressing
	var diff := {}
	if stroke != null:
		e._snap_before = stroke.start_heights
		e._snap_windows.clear()
		e._snap_start.clear()
		e._prop_start.clear()
		e._aligned = DressingGround.aligned_assets(doc.biome_ids, e.palette_root)
		e._rocks = RockKeep.rock_assets(doc.biome_ids, e.palette_root)
		e._queue_heights(stroke.take_pending())
		e._work(true)
		diff = stroke.finish()
		if is_instance_valid(e.terrain):
			e.terrain.settle_heights()
		region = region.merge(stroke.changed) if stroke.changed.has_area() else region
	# The shore band reaches past the water's area.
	var step := doc.sample_step()
	var shore := WaterDressing.SHORE_FAR_M + WaterDressing.SHORE_NOISE_M + 0.5
	region = region.grow(ceili(shore / minf(step.x, step.y))).intersection(
		Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	)
	var after := WaterEdit.model_of(doc)
	refresh()
	var record := {
		"props_before": {},
		"props_after": {},
		"kept": {},
		"water_before": before,
		"water_after": after,
		"region": region,
	}
	for cell in e._prop_start:
		record.props_before[cell] = (e._prop_start[cell] as Dictionary).duplicate(true)
	var keep := _wet_rock_rule()
	_drop_wet_rocks(region, keep, record)
	var props_bytes := 0
	for cell in record.props_before:
		record.props_after[cell] = e.props.cell_rows(cell).duplicate(true)
		props_bytes += PropRows.rows_bytes(record.props_before[cell]) * 2
	var started := false
	if stroke != null and not diff.is_empty():
		var area: Rect2 = e._regenerated_area(region)
		started = e.rock_keeper.start(
			stroke.start_heights, region, area, record, e._rocks, dressing_before, keep
		)
	if not started:
		e._regenerate(region)
	var bytes := int(diff.get("bytes", 0)) + props_bytes
	bytes += WaterEdit.model_bytes(before) + WaterEdit.model_bytes(after)
	(
		e
		. history
		. record(
			{
				"label": label,
				"undo": _apply.bind(diff, false, record),
				"redo": _apply.bind(diff, true, record),
				"bytes": bytes,
			}
		)
	)
	e.edited.emit()


## Undo (`redo` false) or redo of a water edit (commit()'s record): the heights, the water
## model, props as recorded, kept rocks swapped, then the dressing, surface and plants.
func _apply(diff: Dictionary, redo: bool, record: Dictionary) -> void:
	var e := _editor()
	var doc := e.document
	e.finish_height_work()
	WaterEdit.apply_model(doc, record.water_after if redo else record.water_before)
	var prop_rows: Dictionary = record.props_after if redo else record.props_before
	if not diff.is_empty():
		var before := doc.heights.duplicate()
		var rect := HeightStroke.apply_diff(doc, diff, redo)
		e._snap_before = before
		e._snap_start.clear()
		e._prop_start.clear()
		e._aligned = DressingGround.aligned_assets(doc.biome_ids, e.palette_root)
		e._rocks = RockKeep.rock_assets(doc.biome_ids, e.palette_root)
		e._queue_heights(rect)
		# Props take their recorded rows, not a snap.
		e._snap_props = false
		e._work(true)
		e._snap_props = true
		e._snap_start.clear()
	for cell in prop_rows:
		e._set_prop_cell(cell, prop_rows[cell], false)
	e.rock_keeper.swap(record.kept, redo)
	if is_instance_valid(e.terrain):
		e.terrain.settle_heights()
	refresh()
	e._regenerate(record.region)


## WaterCarve.keeps_rock() for the document's water as it is now, as Callable(asset id,
## row) -> bool: the level and channel width at the row's sample (its owning body,
## WaterMeshBuilder.sample_owners, computed when a rock first asks).
func _wet_rock_rule() -> Callable:
	var cache := {}
	var doc := _editor().document
	var root := _editor().palette_root
	return func(asset_id: String, row: PackedFloat32Array) -> bool:
		if not cache.has("owners"):
			cache["owners"] = WaterMeshBuilder.sample_owners(doc)
		var owners: PackedInt32Array = cache["owners"]
		var p := Vector2(row[0], row[2])
		var s := doc.world_to_sample(p).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		var owner := owners[doc.sample_index(x, z)]
		if owner < 0:
			return true
		var body := doc.water_bodies[owner]
		var channel := 0.0
		if body.is_river():
			var course := WaterGeometry.river_course(body)
			var near := WaterGeometry.nearest_on_polyline(course[0], p)
			if near.y >= 0:
				channel = 2.0 * WaterGeometry.width_at(course[1], int(near.y), near.z)
		var size: Variant = PaletteLibrary.asset(asset_id, root).get("dimensions_m")
		var tall: float = (size as Vector3).y if size is Vector3 else 0.5
		var radius := RockKeep.footprint_radius(asset_id, root)
		return WaterCarve.keeps_rock(row, tall, radius, body.level_m, channel)


## Removes the rock props of the cells over `region` (samples) that `keep` refuses (they
## shrink away), recording each changed cell's rows before in `record.props_before` (unless
## a snap already did).
func _drop_wet_rocks(region: Rect2i, keep: Callable, record: Dictionary) -> void:
	var e := _editor()
	if not is_instance_valid(e.props) or not region.has_area():
		return
	var rock_rules := {}
	var world := MaskBrush.sample_rect_to_world(e.document, region)
	for cell in ScatterGenerator.cells_in_bounds(world):
		var rows: Dictionary = e.props.cell_rows(cell).duplicate(true)
		var changed := false
		for asset_id: String in rows.keys():
			if not rock_rules.has(asset_id):
				rock_rules[asset_id] = RockKeep.is_rock(e.rule_for_asset(asset_id))
			if not rock_rules[asset_id]:
				continue
			var flat: PackedFloat32Array = rows[asset_id]
			var kept := PackedFloat32Array()
			@warning_ignore("integer_division")
			for r in flat.size() / MapDocument.ROW_STRIDE:
				var row := PropRows.row_at(flat, r)
				if keep.call(asset_id, row):
					kept.append_array(row)
			if kept.size() != flat.size():
				changed = true
				if kept.is_empty():
					rows.erase(asset_id)
				else:
					rows[asset_id] = kept
		if not changed:
			continue
		if not record.props_before.has(cell):
			record.props_before[cell] = e.props.cell_rows(cell).duplicate(true)
		e.props.set_cells({cell: rows}, true)


## The sample rectangle covering map rectangle `area` (clipped to the grid).
func _sample_rect_of(area: Rect2) -> Rect2i:
	var doc := _editor().document
	if not area.has_area():
		return Rect2i()
	var first := Vector2i(doc.world_to_sample(area.position).floor())
	var last := Vector2i(doc.world_to_sample(area.end).ceil())
	var rect := Rect2i(first, last - first + Vector2i.ONE)
	return rect.intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
