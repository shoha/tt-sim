extends RefCounted

## Profile of one ground-cover landing on the main thread (card native-cover round 2,
## 2026-10-20): takes the authoring scatter's densest cell, makes a "previous landing" of it
## with every eighth row of each asset missing, and times AuthoredScatter.set_cells from that
## to the cell's rows (the landing), complete_growth after it (the grow-in merge), a landing
## that changes nothing, and the per-row pieces of a settled node's rebuild over every asset
## of the cell: row_keys, instance_order, transforms_from_rows, ScatterMass.custom_data,
## ScatterGlbUtils.build_multimesh, and the packed alternative (one buffer per node). Times are
## medians of `repeats` (5) in ms. Run it in a real window: the dummy renderer makes the
## MultiMesh calls free.

const STRIDE := 10


static func run(root: Node, step: Dictionary) -> String:
	var c: AuthoringController = root.get("_authoring_controller")
	var scatter: AuthoredScatter = c.scatter
	var repeats := int(step.get("repeats", 5))
	scatter.lean_rebuild = bool(step.get("lean", true))
	var cells: Dictionary = scatter.get("_cells")
	var best := Vector2i.ZERO
	var most := -1
	for cell in cells:
		var n := 0
		for rows: PackedFloat32Array in (cells[cell] as Dictionary).values():
			n += rows.size() / STRIDE
		if n > most:
			most = n
			best = cell
	if most <= 0:
		return "no rows"
	var full: Dictionary = (cells[best] as Dictionary).duplicate()
	var older := {}
	for asset_id in full:
		var rows: PackedFloat32Array = full[asset_id]
		var kept := PackedFloat32Array()
		for r in rows.size() / STRIDE:
			if r % 8 != 3:
				kept.append_array(rows.slice(r * STRIDE, r * STRIDE + STRIDE))
		older[asset_id] = kept
	var t := {"land": [], "merge": [], "same": []}
	for i in repeats:
		scatter.set_cells({best: older}, false)
		scatter.set_cells({best: full}, true)
		t.land.append(scatter.last_apply_usec / 1000.0)
		var started := Time.get_ticks_usec()
		scatter.complete_growth()
		t.merge.append((Time.get_ticks_usec() - started) / 1000.0)
		scatter.set_cells({best: full}, true)
		t.same.append(scatter.last_apply_usec / 1000.0)
	var species: Dictionary = scatter.get("_species")
	var pieces := {"keys": [], "order": [], "xforms": [], "custom": [], "build": [], "packed": []}
	var anchors: Dictionary = scatter.mass_anchors
	for i in repeats:
		var sums := {}
		for k in pieces:
			sums[k] = 0.0
		for asset_id in full:
			var rows: PackedFloat32Array = full[asset_id]
			var mesh: Mesh = species.get(asset_id, {}).get("mesh")
			var s := Time.get_ticks_usec()
			var keys := ScatterRows.row_keys(rows.to_byte_array().to_int32_array())
			var a := Time.get_ticks_usec()
			var all := PackedInt32Array()
			for r in keys.size():
				all.append(r)
			var b := Time.get_ticks_usec()
			var order := ScatterRows.instance_order(keys, all, AuthoredScatter.node_name_for(asset_id, best))
			var d := Time.get_ticks_usec()
			var xforms := ScatterRows.transforms_from_rows(rows, order)
			var e := Time.get_ticks_usec()
			ScatterMass.custom_data(anchors, xforms)
			var f := Time.get_ticks_usec()
			if mesh != null:
				ScatterGlbUtils.build_multimesh(mesh, xforms, anchors)
			var g := Time.get_ticks_usec()
			if mesh != null:
				_packed(mesh, rows, order)
			var h := Time.get_ticks_usec()
			sums.keys += (a - s) / 1000.0
			sums.order += (d - b) / 1000.0
			sums.xforms += (e - d) / 1000.0
			sums.custom += (f - e) / 1000.0
			sums.build += (g - f) / 1000.0
			sums.packed += (h - g) / 1000.0
		for k in pieces:
			pieces[k].append(sums[k])
	var parts := PackedStringArray()
	for k in t:
		parts.append("%s %.2f" % [k, _median(t[k])])
	for k in pieces:
		parts.append("%s %.2f" % [k, _median(pieces[k])])
	return (
		"cell %s: %d rows in %d assets, anchors %d | %s"
		% [best, most, full.size(), anchors.size(), ", ".join(parts)]
	)


## One packed buffer for a node's MultiMesh in place of per-instance calls (transforms only).
static func _packed(mesh: Mesh, rows: PackedFloat32Array, order: PackedInt32Array) -> MultiMesh:
	var buffer := PackedFloat32Array()
	buffer.resize(order.size() * 12)
	for i in order.size():
		var x := ScatterRows.row_transform(rows, order[i])
		var o := i * 12
		buffer[o] = x.basis.x.x
		buffer[o + 1] = x.basis.y.x
		buffer[o + 2] = x.basis.z.x
		buffer[o + 3] = x.origin.x
		buffer[o + 4] = x.basis.x.y
		buffer[o + 5] = x.basis.y.y
		buffer[o + 6] = x.basis.z.y
		buffer[o + 7] = x.origin.y
		buffer[o + 8] = x.basis.x.z
		buffer[o + 9] = x.basis.y.z
		buffer[o + 10] = x.basis.z.z
		buffer[o + 11] = x.origin.z
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = order.size()
	multimesh.buffer = buffer
	return multimesh


static func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2]) if not sorted.is_empty() else 0.0
