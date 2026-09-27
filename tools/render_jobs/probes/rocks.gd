extends RefCounted

## Render-job probe (`call` op) for "rocks survive terrain changes" (P3-7, RockKeep and
## RockKeeper), on the open authoring map:
## - `action: "survey"`: the 10 m cells within `within` metres (default 25) of the map centre
##   with the most rock rows (boulder-sized ones, with a footing, counted apart), `top` of
##   them (default 6), to aim strokes at a boulder field.
## - `action: "check"` (default): rock props (kept or placed): count, how far any stands above
##   its bed (GroundSnap.bed_under: its tilted base on the ground; floating), its tilt off
##   vertical (mean, max);
##   generated rocks inside a rock prop's footprint (twins); the last stroke's keeping
##   (rocks kept, main-thread and worker microseconds). With `near` ([x, z, r]) also the rock
##   scatter rows and rock props within r metres of (x, z).


static func run(root: Node, step: Dictionary) -> String:
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.editor == null:
		return "no authoring map"
	var doc := ctrl.document
	var rocks := RockKeep.rock_assets(doc.biome_ids, PaletteLibrary.DEFAULT_ROOT)
	if String(step.get("action", "check")) == "survey":
		return _survey(ctrl, rocks, float(step.get("within", 25.0)), int(step.get("top", 6)))
	return _check(ctrl, rocks, step.get("near", []))


static func _survey(
	ctrl: AuthoringController, rocks: Dictionary, within: float, top: int
) -> String:
	var counts := {}
	var rows: Dictionary = ctrl.scatter.rows_by_asset()
	for asset_id in rows:
		if not rocks.has(asset_id):
			continue
		var big := GroundSnap.footing_radius(rocks[asset_id]) > 0.0
		var flat: PackedFloat32Array = rows[asset_id]
		for r in range(0, flat.size(), MapDocument.ROW_STRIDE):
			var p := Vector2(flat[r], flat[r + 2])
			if p.length() > within:
				continue
			var cell := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
			var entry: Vector2i = counts.get(cell, Vector2i.ZERO)
			counts[cell] = entry + (Vector2i(1, 1) if big else Vector2i(1, 0))
	var cells := counts.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return counts[a].x > counts[b].x)
	var lines := PackedStringArray()
	for i in mini(top, cells.size()):
		var cell: Vector2i = cells[i]
		var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * 10.0
		lines.append(
			(
				"cell %s centre %s rocks %d boulders %d"
				% [cell, centre, counts[cell].x, counts[cell].y]
			)
		)
	return "\n".join(lines)


static func _check(ctrl: AuthoringController, rocks: Dictionary, near: Array) -> String:
	var doc := ctrl.document
	var grid := GroundSnap.grid_of(doc)
	var placed: Dictionary = ctrl.props.rows_by_asset()
	var count := 0
	var floating := 0
	var worst_float := 0.0
	var tilt_sum := 0.0
	var tilt_max := 0.0
	var near_props := 0
	var centre := Vector2.ZERO
	var reach := -1.0
	if near.size() >= 3:
		centre = Vector2(float(near[0]), float(near[1]))
		reach = float(near[2])
	for asset_id in placed:
		var rule := RockKeep.rule_for_asset(asset_id, PaletteLibrary.DEFAULT_ROOT)
		if not RockKeep.is_rock(rule):
			continue
		var radius := GroundSnap.footing_radius(rule)
		var flat: PackedFloat32Array = placed[asset_id]
		for r in range(0, flat.size(), MapDocument.ROW_STRIDE):
			var p := Vector2(flat[r], flat[r + 2])
			var q := Quaternion(flat[r + 3], flat[r + 4], flat[r + 5], flat[r + 6]).normalized()
			var bed := GroundSnap.bed_under(
				doc.heights, grid, p, radius * flat[r + 7], q * Vector3.UP
			)
			var above := flat[r + 1] - bed
			worst_float = maxf(worst_float, above)
			if above > 0.01:
				floating += 1
			var tilt := rad_to_deg((q * Vector3.UP).angle_to(Vector3.UP))
			tilt_sum += tilt
			tilt_max = maxf(tilt_max, tilt)
			count += 1
			if reach > 0.0 and p.distance_to(centre) <= reach:
				near_props += 1
	var blockers := RockKeep.blockers(placed, PaletteLibrary.DEFAULT_ROOT)
	var twins := 0
	var near_rows := 0
	var rows: Dictionary = ctrl.scatter.rows_by_asset()
	for asset_id in rows:
		if not rocks.has(asset_id):
			continue
		var flat: PackedFloat32Array = rows[asset_id]
		for r in range(0, flat.size(), MapDocument.ROW_STRIDE):
			var p := Vector2(flat[r], flat[r + 2])
			if RockKeep.blocked(blockers, p):
				twins += 1
			if reach > 0.0 and p.distance_to(centre) <= reach:
				near_rows += 1
	var keeper := ctrl.editor.rock_keeper
	return (
		(
			"rock props %d floating %d (worst %.3f m) tilt mean %.1f max %.1f deg twins %d; "
			+ "near: scatter rocks %d rock props %d; last keep: %d kept, %d us main, %d us worker"
		)
		% [
			count,
			floating,
			worst_float,
			tilt_sum / maxf(count, 1),
			tilt_max,
			twins,
			near_rows,
			near_props,
			keeper.last_kept,
			keeper.last_usec,
			keeper.last_worker_usec
		]
	)
