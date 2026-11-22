class_name WaterWetRocks
extends RefCounted
## The wet-rock rule of a water edit's landing (docs/systems/water.md "Carving"): rock props
## under the new water that the carve's keep rule refuses shrink away, and their cells' rows
## before go into the edit's record so undo brings them back. Split out of WaterEditor
## (_finish(), for an edit and for an external landing, land_external) to keep that class a
## readable size; static, reaching into the AuthoringEditor it is given.


## WaterCarve.keeps_rock() for `editor`'s document water as it is now, as Callable(asset id,
## row) -> bool: the level and channel width at the row's sample (its owning body, `owners`:
## WaterMeshBuilder.sample_owners of the document after the edit).
static func rule(editor: AuthoringEditor, owners: PackedInt32Array) -> Callable:
	var doc := editor.document
	var root := editor.palette_root
	return func(asset_id: String, row: PackedFloat32Array) -> bool:
		var p := Vector2(row[0], row[2])
		var s := doc.world_to_sample(p).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		var at := doc.sample_index(x, z)
		var owner := owners[at] if at < owners.size() else -1
		if owner < 0 or owner >= doc.water_bodies.size():
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


## Removes the rock props of `editor`'s cells over `region` (samples) that `keep` refuses (they
## shrink away), recording each changed cell's rows before in `record.props_before` (unless a
## snap already did).
static func drop(
	editor: AuthoringEditor, region: Rect2i, keep: Callable, record: Dictionary
) -> void:
	var e := editor
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
