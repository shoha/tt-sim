extends RefCounted

## The foliage perf probe's `load` action (foliage_perf.gd's header has the step fields), split
## out to keep the probe under the line cap: the MultiMesh build of every (cell, asset) of the
## open map's scatter on the real renderer, four ways interleaved (the shipped path, the same
## without custom data, a GDScript-built 12-float buffer assigned at once, and that buffer
## prebuilt), then the shipped path split into its steps (row keys, instance order, rows to
## transforms, the MultiMesh build), and the play-time load itself as MapSourceLoader spreads it
## (begin_build, one build_cells per cell within the loader's 8 ms frame budget, end_build): the
## total, the frames it takes and the longest frame. Where the native chunk call is loaded (card
## scatterload) also: the chunk path natively and in GDScript (ScatterRows.chunk, then
## multimesh_from_chunk) among the build methods, the native call alone, the spread load with
## the chunks forced into GDScript (`spread_gd`), and `parity`: every chunk's native buffer
## against the buffer the per-instance path leaves in a MultiMesh on the real renderer, byte for
## byte.
## Writes <dir>/<name>_load.txt.

## MapSourceLoader.FRAME_BUDGET_USEC: the cells one frame of the spread load builds.
const FRAME_BUDGET_USEC := 8000


## The MultiMesh build, four ways, the split and the spread load. `dir` is the output folder.
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
	# clear() empties the table in place: keep a copy for every rebuild below.
	var anchors: Dictionary = scatter.mass_anchors.duplicate()
	var rows_by_cell := AuthoredScatter.rows_by_cell_of(scatter.rows_by_asset())
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
			var seed_source := AuthoredScatter.node_name_for(asset_id, cell)
			jobs.append({"rows": rows, "mesh": sp.mesh, "order": order, "n": n, "seed": seed_source})
			instances += n
	for j in jobs:
		j["buffer"] = _buffer(j.rows, j.n)
	var reps := int(step.get("reps", 6))
	var methods: Array[String] = ["shipped", "shipped_nocustom", "gd_buffer", "prebuilt_buffer"]
	if ScatterNative.chunk_active():
		methods.append_array(["native_chunk", "gd_chunk"])
	var times := {}
	for m in methods + ["keys", "order", "transforms", "multimesh", "native_call"]:
		times[m] = []
	var spread := {"total": [], "frames": [], "max_frame": [], "max_cell": [], "end": []}
	var spread_gd := {"total": [], "frames": [], "max_frame": [], "max_cell": [], "end": []}
	var parity := _parity(jobs, anchors) if ScatterNative.chunk_active() else ""
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
		_split(jobs, anchors, times)
		if ScatterNative.chunk_active():
			var t0 := Time.get_ticks_usec()
			for j in jobs:
				ScatterNative.chunk(j.rows, null, ScatterRows.order_seed(j.seed), anchors)
			times.native_call.append((Time.get_ticks_usec() - t0) / 1000.0)
		# The spread load natively and with chunks forced into GDScript, alternating which first;
		# without the chunk call (main) only the shipped path runs.
		var native_first := r % 2 == 0 or not ScatterNative.chunk_active()
		for pass_native in [native_first, not native_first]:
			if not ScatterNative.chunk_active() and not pass_native:
				continue
			ScatterNative.force_gdscript_chunks = not pass_native
			var s := _spread(scatter, rows_by_cell, anchors)
			ScatterNative.force_gdscript_chunks = false
			var into: Dictionary = spread if pass_native else spread_gd
			for key in into:
				into[key].append(s[key])
	var lines: Array[String] = []
	lines.append(
		(
			"load %s: %d (cell, asset) MultiMeshes, %d instances, %d cells, %d reps, %d anchors"
			% [step.get("name", ""), jobs.size(), instances, rows_by_cell.size(), reps, anchors.size()]
		)
	)
	for m in methods:
		lines.append("load %-18s %s ms, %s" % [m, _stat(times[m]), _per(times[m], instances)])
	for m in ["keys", "order", "transforms", "multimesh", "native_call"]:
		if not (times[m] as Array).is_empty():
			lines.append("load split %-12s %s ms" % [m, _stat(times[m])])
	for pair in [["spread", spread], ["spread_gd", spread_gd]]:
		var s: Dictionary = pair[1]
		if (s.total as Array).is_empty():
			continue
		lines.append("load %-9s total     %s ms" % [pair[0], _stat(s.total)])
		lines.append("load %-9s frames    %s" % [pair[0], _stat(s.frames)])
		lines.append("load %-9s max frame %s ms" % [pair[0], _stat(s.max_frame)])
		lines.append("load %-9s max cell  %s ms" % [pair[0], _stat(s.max_cell)])
		lines.append("load %-9s end_build %s ms" % [pair[0], _stat(s.end)])
	if parity != "":
		lines.append("load parity %s" % parity)
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
		"native_chunk":
			var seed_value := ScatterRows.order_seed(j.seed)
			var built := ScatterNative.chunk(j.rows, null, seed_value, anchors)
			return ScatterGlbUtils.multimesh_from_chunk(j.mesh, built)
		"gd_chunk":
			var seed_value := ScatterRows.order_seed(j.seed)
			var built := ScatterRows.chunk_gdscript(j.rows, null, seed_value)
			return ScatterGlbUtils.multimesh_from_chunk(j.mesh, built, anchors)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = j.mesh
	mm.instance_count = j.n
	mm.buffer = _buffer(j.rows, j.n) if method == "gd_buffer" else j.buffer
	return mm


## On the real renderer, every job's MultiMesh as the per-instance path builds it
## (build_multimesh: instance_order, transforms, custom data, set_instance_transform) read back
## through MultiMesh.buffer, against the native chunk's buffer and against a MultiMesh built from
## it: "<same> of <jobs> byte-identical (<custom> with custom data), <readback> read back equal".
static func _parity(jobs: Array[Dictionary], anchors: Dictionary) -> String:
	var same := 0
	var custom := 0
	var readback := 0
	var first_bad := ""
	for j in jobs:
		var built := ScatterNative.chunk(j.rows, null, ScatterRows.order_seed(j.seed), anchors)
		var keys := ScatterRows.row_keys((j.rows as PackedFloat32Array).to_byte_array().to_int32_array())
		var order := ScatterRows.instance_order(keys, j.order, j.seed)
		var old := ScatterGlbUtils.build_multimesh(
			j.mesh, ScatterRows.transforms_from_rows(j.rows, order), anchors
		)
		var old_bytes := old.buffer.to_byte_array()
		var new_bytes := (built.buffer as PackedFloat32Array).to_byte_array()
		var ok: bool = old_bytes == new_bytes and built.order == order and built.keys == keys
		ok = ok and old.use_custom_data == built.custom
		same += 1 if ok else 0
		custom += 1 if built.custom else 0
		if not ok and first_bad == "":
			first_bad = " first mismatch %s (%d vs %d bytes)" % [j.seed, old_bytes.size(), new_bytes.size()]
		var back := ScatterGlbUtils.multimesh_from_chunk(j.mesh, built).buffer.to_byte_array()
		readback += 1 if back == old_bytes else 0
	return (
		"%d of %d byte-identical (%d with custom data), %d read back equal%s"
		% [same, jobs.size(), custom, readback, first_bad]
	)


## The shipped settled-node path of every job, one step at a time across all jobs: row keys,
## instance order (seeded by the node name), rows to transforms, then the MultiMesh build
## (custom data and the set_instance_transform loop). Appends each step's ms to `times`.
static func _split(jobs: Array[Dictionary], anchors: Dictionary, times: Dictionary) -> void:
	var keys: Array[PackedInt64Array] = []
	var orders: Array[PackedInt32Array] = []
	var transforms: Array = []
	var t0 := Time.get_ticks_usec()
	for j in jobs:
		keys.append(ScatterRows.row_keys((j.rows as PackedFloat32Array).to_byte_array().to_int32_array()))
	var t1 := Time.get_ticks_usec()
	for i in jobs.size():
		orders.append(ScatterRows.instance_order(keys[i], jobs[i].order, jobs[i].seed))
	var t2 := Time.get_ticks_usec()
	for i in jobs.size():
		transforms.append(ScatterRows.transforms_from_rows(jobs[i].rows, orders[i]))
	var t3 := Time.get_ticks_usec()
	var hold: Array[MultiMesh] = []
	for i in jobs.size():
		hold.append(ScatterGlbUtils.build_multimesh(jobs[i].mesh, transforms[i], anchors))
	var t4 := Time.get_ticks_usec()
	times.keys.append((t1 - t0) / 1000.0)
	times.order.append((t2 - t1) / 1000.0)
	times.transforms.append((t3 - t2) / 1000.0)
	times.multimesh.append((t4 - t3) / 1000.0)


## The play-time load as MapSourceLoader._build_authored_scatter_async runs it, timed
## synchronously: per frame, cells while the frame's time is under the budget (so the last cell
## of a frame may overrun it). Leaves the scatter fully built with `anchors`.
static func _spread(
	scatter: AuthoredScatter, rows_by_cell: Dictionary, anchors: Dictionary
) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	scatter.begin_build()
	scatter.mass_anchors = anchors.duplicate()
	var frames := 0
	var max_frame := 0
	var max_cell := 0
	var frame_start := -1
	for cell in rows_by_cell:
		var now := Time.get_ticks_usec()
		if frame_start < 0 or now - frame_start >= FRAME_BUDGET_USEC:
			if frame_start >= 0:
				max_frame = maxi(max_frame, now - frame_start)
			frames += 1
			frame_start = now
		scatter.build_cells({cell: rows_by_cell[cell]})
		max_cell = maxi(max_cell, Time.get_ticks_usec() - now)
	max_frame = maxi(max_frame, Time.get_ticks_usec() - frame_start)
	var t1 := Time.get_ticks_usec()
	scatter.end_build()
	var t2 := Time.get_ticks_usec()
	return {
		"total": (t2 - t0) / 1000.0,
		"frames": float(frames),
		"max_frame": max_frame / 1000.0,
		"max_cell": max_cell / 1000.0,
		"end": (t2 - t1) / 1000.0,
	}


## "median M [min-max]" of a list of numbers.
static func _stat(values: Array) -> String:
	var a := values.duplicate()
	a.sort()
	return "median %.2f [%.2f-%.2f]" % [a[a.size() / 2], a[0], a[-1]]


static func _per(values: Array, instances: int) -> String:
	var a := values.duplicate()
	a.sort()
	return "%.3f us per instance" % (1000.0 * a[a.size() / 2] / maxf(1.0, instances))


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
