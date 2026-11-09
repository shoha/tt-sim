extends RefCounted

## The foliage perf probe's `load` action (foliage_perf.gd's header has the step fields), split
## out to keep the probe under the line cap: the MultiMesh build of every (cell, asset) of the
## open map's scatter on the real renderer, four ways interleaved (the shipped path, the same
## without custom data, a GDScript-built 12-float buffer assigned at once, and that buffer
## prebuilt), then AuthoredScatter.build_all itself. Writes <dir>/<name>_load.txt.


## The MultiMesh build, four ways, then build_all. `dir` is the output folder (absolute).
static func run(base: Node, step: Dictionary, dir: String) -> String:
	var gm: GameMap = base.get("_game_map")
	var scatter: AuthoredScatter = null
	var most := -1
	for node in gm.find_children("*", "AuthoredScatter", true, false):
		var cells: Dictionary = node.get("_cells")
		if cells.size() > most:
			most = cells.size()
			scatter = node
	if scatter == null:
		return "load: no scatter"
	var cells: Dictionary = scatter.get("_cells")
	var species: Dictionary = scatter.get("_species")
	var anchors: Dictionary = scatter.mass_anchors
	var jobs: Array[Dictionary] = []
	var instances := 0
	for cell in cells:
		for asset_id in cells[cell]:
			var sp: Dictionary = species.get(asset_id, {})
			if sp.is_empty():
				continue
			var rows: PackedFloat32Array = cells[cell][asset_id]
			var n := rows.size() / MapDocument.ROW_STRIDE
			if n == 0:
				continue
			var order := PackedInt32Array()
			order.resize(n)
			for i in n:
				order[i] = i
			jobs.append({"rows": rows, "mesh": sp.mesh, "order": order, "n": n})
			instances += n
	for j in jobs:
		j["buffer"] = _buffer(j.rows, j.n)
	var reps := int(step.get("reps", 5))
	var methods: Array[String] = ["shipped", "shipped_nocustom", "gd_buffer", "prebuilt_buffer"]
	var times := {}
	for m in methods:
		times[m] = []
	var keys_ms: Array = []
	for r in reps:
		var order := methods.duplicate()
		for k in r % order.size():
			order.push_back(order.pop_front())
		if r % 2 == 1:
			order.reverse()
		for m in order:
			var hold: Array[MultiMesh] = []
			var t0 := Time.get_ticks_usec()
			for j in jobs:
				hold.append(_build_one(m, j, anchors))
			times[m].append((Time.get_ticks_usec() - t0) / 1000.0)
			hold.clear()
		var t1 := Time.get_ticks_usec()
		for j in jobs:
			var bits := (j.rows as PackedFloat32Array).to_byte_array().to_int32_array()
			var keys := ScatterRows.row_keys(bits)
			ScatterRows.instance_order(keys, j.order, "seed")
		keys_ms.append((Time.get_ticks_usec() - t1) / 1000.0)
	var rows_by_asset := scatter.rows_by_asset()
	var t2 := Time.get_ticks_usec()
	scatter.build_all(rows_by_asset)
	var build_all_ms := (Time.get_ticks_usec() - t2) / 1000.0
	var lines: Array[String] = []
	lines.append(
		(
			"load %s: %d (cell, asset) MultiMeshes, %d instances, %d reps, %d anchors"
			% [step.get("name", ""), jobs.size(), instances, reps, anchors.size()]
		)
	)
	for m in methods:
		var a: Array = times[m]
		a.sort()
		lines.append(
			(
				"load %-18s median %.2f ms [%.2f-%.2f], %.3f us per instance"
				% [m, a[a.size() / 2], a[0], a[-1], 1000.0 * a[a.size() / 2] / maxf(1.0, instances)]
			)
		)
	keys_ms.sort()
	lines.append("load row_keys+instance_order median %.2f ms" % keys_ms[keys_ms.size() / 2])
	lines.append("load AuthoredScatter.build_all (once, after) %.2f ms" % build_all_ms)
	var f := FileAccess.open(
		dir.path_join("%s_load.txt" % String(step.get("name", "load"))), FileAccess.WRITE
	)
	if f != null:
		for l in lines:
			f.store_line(l)
	for l in lines:
		print("RJ| " + l)
	return "load %s done" % step.get("name", "")


static func _build_one(method: String, j: Dictionary, anchors: Dictionary) -> MultiMesh:
	match method:
		"shipped":
			return ScatterGlbUtils.build_multimesh(
				j.mesh, ScatterRows.transforms_from_rows(j.rows, j.order), anchors
			)
		"shipped_nocustom":
			return ScatterGlbUtils.build_multimesh(
				j.mesh, ScatterRows.transforms_from_rows(j.rows, j.order), {}
			)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = j.mesh
	mm.instance_count = j.n
	mm.buffer = _buffer(j.rows, j.n) if method == "gd_buffer" else j.buffer
	return mm


## The 12-float MultiMesh rows (basis rows with the origin) of `n` instance rows.
static func _buffer(rows: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n * 12)
	var stride := MapDocument.ROW_STRIDE
	for r in n:
		var b := r * stride
		var q := Quaternion(rows[b + 3], rows[b + 4], rows[b + 5], rows[b + 6])
		q = q.normalized() if q.length_squared() > 0.0 else Quaternion()
		var basis := Basis(q).scaled(Vector3(rows[b + 7], rows[b + 8], rows[b + 9]))
		var o := r * 12
		out[o] = basis.x.x
		out[o + 1] = basis.y.x
		out[o + 2] = basis.z.x
		out[o + 3] = rows[b]
		out[o + 4] = basis.x.y
		out[o + 5] = basis.y.y
		out[o + 6] = basis.z.y
		out[o + 7] = rows[b + 1]
		out[o + 8] = basis.x.z
		out[o + 9] = basis.y.z
		out[o + 10] = basis.z.z
		out[o + 11] = rows[b + 2]
	return out
