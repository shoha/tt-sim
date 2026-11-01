extends RefCounted

## Render-job probe (`call` op) for the build-hitch pass (topic hitches, docs/PERFORMANCE.md "Build
## hitches, round 1"). It measures what a player feels: the worst frames while an edit lands, not
## the mean. step.action:
##   rec {mode: begin|end, name}   a frame recorder (every frame's wall time, vsync off): `end` logs the
##                                 frame count, total, the worst six frames, how many exceed 33 ms and the
##                                 "jank" (the sum of the milliseconds past 16.7 ms)
##   place {count, per_frame, lots}  adds `count` structures through the editor, `per_frame` a frame
##                                 (the way a player places them, never flushed), and logs each add
##   split                         the cost of making a structure node from the cached builds, by part
##   dress {id, kit, wealth, density, ground}  one Dress call, timed; no flush (the layer bakes in its
##                                 own frames, as in play)
##   redress / clear {id}          the Re-dress and Clear buttons, timed the same way
##   paint_split {id}              the phases of laying and taking back settlement `id`'s ground strokes
##                                 (dab, finish, apply, ground update, scatter), put back afterwards
##   info                          the decor info a structure refresh reads, by part (old and new count)
##   save / cleanup                writes the open map as the test level `_hitches_load` / deletes it
## Every action returns the line the job log prints.

const STRUCT := preload("res://tools/render_jobs/probes/structures.gd")
const FOLDER := "_hitches_load"
const REC_NAME := "HitchRec"
const PLACER_NAME := "HitchPlacer"
const JANK_FLOOR_MS := 16.7


## The frame recorder: one wall-clock sample per frame.
class Rec:
	extends Node
	var label := ""
	var frames := PackedFloat64Array()
	var last_us := 0
	var first_frame := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -99
		last_us = Time.get_ticks_usec()
		first_frame = Engine.get_process_frames()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - last_us) / 1000.0)
		last_us = now

	## The line `end` logs.
	func summary() -> String:
		var sorted := frames.duplicate()
		sorted.sort()
		var total := 0.0
		var jank := 0.0
		var over := 0
		var over_25 := 0
		for ms in frames:
			total += ms
			if ms > JANK_FLOOR_MS:
				jank += ms - JANK_FLOOR_MS
			if ms > 33.4:
				over += 1
			if ms > 25.0:
				over_25 += 1
		var worst := PackedStringArray()
		for k in mini(6, sorted.size()):
			worst.append("%.1f" % sorted[sorted.size() - 1 - k])
		# Where in the recording the frames over 25 ms fell (frame index: ms).
		var late := PackedStringArray()
		for k in frames.size():
			if frames[k] > 25.0 and late.size() < 12:
				late.append("%d:%.0f" % [k, frames[k]])
		if not late.is_empty():
			worst.append("at " + " ".join(late))
		return (
			"hitch %s (from f%d) | frames %d total %.0f ms | median %.1f | worst [%s] | over 25 ms: %d | over 33 ms: %d | jank %.0f ms"
			% [
				label,
				first_frame,
				sorted.size(),
				total,
				sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0,
				", ".join(worst),
				over_25,
				over,
				jank
			]
		)


## Adds structures a few a frame, so the recorder sees what a run of placements does to the frames.
class Placer:
	extends Node
	var editor: AuthoringEditor
	var lots: Array = []
	var next := 0
	var count := 0
	var per_frame := 1
	var seed_base := 100
	var adds := PackedFloat64Array()
	var refused := 0
	var report: Callable

	func _process(_delta: float) -> void:
		for step in per_frame:
			if next >= count:
				break
			var lot: Array = lots[next % lots.size()]
			var columns := int(ceil(sqrt(float(count))))
			var at := Vector2(
				(float(next % columns) - (columns - 1) * 0.5) * 14.0,
				(float(next / columns) - (columns - 1) * 0.5) * 14.0
			)
			var plan := STRUCT._rect(float(lot[3]), float(lot[4]), float(lot[5]) + next * 7.0, at)
			var structure := Structure.make(0, String(lot[0]), plan, seed_base + next)
			if String(lot[0]) == "core:townhouse":
				structure.footprint = STRUCT._l_shape(at)
			var started := Time.get_ticks_usec()
			var id := editor.structures.add(structure)
			adds.append((Time.get_ticks_usec() - started) / 1000.0)
			if id < 0:
				refused += 1
			next += 1
		if next >= count:
			var sorted := adds.duplicate()
			sorted.sort()
			var total := 0.0
			for ms in adds:
				total += ms
			report.call(
				(
					"placed %d (%d refused): add call mean %.1f ms, median %.1f, worst %.1f"
					% [
						count,
						refused,
						total / maxf(adds.size(), 1),
						sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0,
						sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0
					]
				)
			)
			queue_free()


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	match String(step.get("action", "")):
		"rec":
			return _rec(base, step)
		"save":
			return _save(ctrl)
		"cleanup":
			return _cleanup()
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	match String(step.get("action", "")):
		"info":
			return _info_cost()
		"cold":
			return _cold_cost(ctrl)
		"place":
			return _place(base, ctrl.editor, step)
		"split":
			return _split(ctrl)
		"warm_report":
			return _warm_report()
		"dress":
			return _dress(ctrl.editor, step)
		"paint_split":
			return _paint_split(ctrl.editor, step)
		"redress":
			var started := Time.get_ticks_usec()
			var ok := ctrl.editor.settlements.redress(int(step.get("id", 1)))
			return _timed("redress", ctrl.editor, started, str(ok))
		"clear":
			var started := Time.get_ticks_usec()
			var ok := ctrl.editor.settlements.clear(int(step.get("id", 1)))
			return _timed("clear", ctrl.editor, started, str(ok))
	return "unknown action %s" % step.get("action", "")


## The decor info a refresh reads, by part, 20 calls each (ms per call): the whole of
## StructureLoadInfo.info_of, the rows alone, the triangle count the old way (a copy of every
## surface's arrays) and the way StructureDecor.triangles_of counts now, and the signature hash.
static func _info_cost() -> String:
	var root := PaletteLibrary.DEFAULT_ROOT
	var runs := 20
	var rows := AssetStore.decor_rows(root)
	var meshes: Array[Mesh] = []
	for row in rows:
		meshes.append(AssetStore.mesh(str(row.library), str(row.id), root))
	var t := Time.get_ticks_usec()
	for k in runs:
		StructureLoadInfo.info_of(root)
	var whole := (Time.get_ticks_usec() - t) / 1000.0 / runs
	t = Time.get_ticks_usec()
	for k in runs:
		AssetStore.decor_rows(root)
	var rows_ms := (Time.get_ticks_usec() - t) / 1000.0 / runs
	t = Time.get_ticks_usec()
	var old_total := 0
	for k in runs:
		old_total = 0
		for mesh in meshes:
			if mesh == null:
				continue
			for surface in mesh.get_surface_count():
				var index: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				if index is PackedInt32Array:
					old_total += (index as PackedInt32Array).size() / 3
	var old_ms := (Time.get_ticks_usec() - t) / 1000.0 / runs
	t = Time.get_ticks_usec()
	var new_total := 0
	for k in runs:
		new_total = 0
		for mesh in meshes:
			new_total += StructureDecor.triangles_of(mesh)
	var new_ms := (Time.get_ticks_usec() - t) / 1000.0 / runs
	var cost := {}
	for k in rows.size():
		cost[rows[k].id] = StructureDecor.triangles_of(meshes[k])
	t = Time.get_ticks_usec()
	for k in runs:
		hash([rows, cost])
	var hash_ms := (Time.get_ticks_usec() - t) / 1000.0 / runs
	return (
		"info_of %.2f ms: rows %.2f (%d), triangles old %.2f (%d tris) new %.2f (%d tris), hash %.2f"
		% [whole, rows_ms, rows.size(), old_ms, old_total, new_ms, new_total, hash_ms]
	)


## The first-use costs of a structure on a fresh map, each timed once (hitches2): the decor info
## (parses the decor GLBs), the baked masonry textures, then one material of each common kind for
## the map's first biome, twice (the second pass shows what a cache keeps).
static func _cold_cost(ctrl: AuthoringController) -> String:
	var root := PaletteLibrary.DEFAULT_ROOT
	var style := ctrl.document.biome_ids[0] if not ctrl.document.biome_ids.is_empty() else ""
	var parts := PackedStringArray()
	var t := Time.get_ticks_usec()
	StructureLoadInfo.info_of(root)
	parts.append("info_of %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	MasonryTextures.textures()
	parts.append("masonry_textures %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	var combos := [
		["masonry", "wall"],
		["wood", "roof"],
		["boards", "wall"],
		["tile", "roof"],
		["plaster", "wall"],
		["thatch", "roof"],
		["stone", "trim"],
		["glass", "opening"],
		["leaf", "ornament"],
	]
	for pass_index in 2:
		for combo: Array in combos:
			t = Time.get_ticks_usec()
			StructureMaterials.make(combo[0], combo[1], style, root)
			parts.append(
				"%s:%s#%d %.1f" % [combo[0], combo[1], pass_index, (Time.get_ticks_usec() - t) / 1000.0]
			)
	return "cold (%s) ms: %s" % [style, ", ".join(parts)]


## The structure warm-up's units (StructureWarmup.last_log): process frame, kind:role, M(ake),
## D(raw) or S(hadow draw), main-thread ms.
static func _warm_report() -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in StructureWarmup.last_log:
		var pair: Array = StructureWarmup.COMBOS[int(entry.combo)]
		parts.append(
			(
				"f%d %s:%s %s %.1f"
				% [
					int(entry.frame),
					pair[0],
					pair[1],
					"MDS"[int(entry.phase)],
					float(entry.ms)
				]
			)
		)
	return "warm-up units (%d): %s" % [parts.size(), ", ".join(parts)]


static func _fmt(values: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in values:
		parts.append("%s %.1f" % [key, float(values[key])])
	return "{" + ", ".join(parts) + "}"


static func _log(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for node in tree.root.get_children():
		if node.has_method("log_line"):
			node.call("log_line", text)
			return
	print("RJ| " + text)


static func _rec(base: Node, step: Dictionary) -> String:
	var root := base.get_tree().root
	var old := root.get_node_or_null(REC_NAME) as Rec
	if String(step.get("mode", "begin")) == "begin":
		if old != null:
			old.name = REC_NAME + "_old"
			old.queue_free()
		var rec := Rec.new()
		rec.name = REC_NAME
		rec.label = String(step.get("name", ""))
		root.add_child(rec)
		return "recording %s" % rec.label
	if old == null:
		return "no recorder"
	var text := old.summary()
	old.queue_free()
	return text


static func _place(base: Node, editor: AuthoringEditor, step: Dictionary) -> String:
	var placer := Placer.new()
	placer.name = PLACER_NAME
	placer.editor = editor
	placer.lots = STRUCT.BASIC_LOTS
	placer.count = int(step.get("count", 1))
	placer.per_frame = int(step.get("per_frame", 1))
	placer.seed_base = int(step.get("seed", 100))
	placer.report = _log
	base.get_tree().root.add_child(placer)
	return "placing %d, %d a frame" % [placer.count, placer.per_frame]


## The cost of each part of making a structure node, from the builds the node cache holds (two
## passes: the first may pay a material or a mesh made for the first time).
static func _split(ctrl: AuthoringController) -> String:
	var nodes := AuthoredStructures.of_map(ctrl.map_root)
	var lines := PackedStringArray()
	for pass_index in 2:
		var sums := {"meshes": 0.0, "dressing": 0.0, "decor": 0.0, "body": 0.0, "enter": 0.0, "free": 0.0}
		var worst := 0.0
		var count := 0
		var triangles := 0
		for key: int in nodes._cache.keys():
			var parts: Dictionary = nodes._cache[key]
			if (parts.get("meshes", []) as Array).is_empty():
				continue
			var node := Node3D.new()
			var style: String = parts.get("style", "")
			var tone: String = parts.get("stone_tone", "")
			var t := Time.get_ticks_usec()
			for mesh: Dictionary in parts.get("meshes", []):
				node.add_child(nodes._mesh_instance(mesh, "", style, tone))
				triangles += (mesh.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			sums.meshes += (Time.get_ticks_usec() - t) / 1000.0
			t = Time.get_ticks_usec()
			nodes._add_dressing(node, parts.get("dressing", {}))
			sums.dressing += (Time.get_ticks_usec() - t) / 1000.0
			t = Time.get_ticks_usec()
			nodes._add_decor(node, parts)
			sums.decor += (Time.get_ticks_usec() - t) / 1000.0
			t = Time.get_ticks_usec()
			var faces: PackedVector3Array = parts.get("collision", PackedVector3Array())
			faces = faces + (parts.get("walkable", PackedVector3Array()) as PackedVector3Array)
			if not faces.is_empty():
				node.add_child(AuthoredStructures._body(faces, 999))
			var body_ms := (Time.get_ticks_usec() - t) / 1000.0
			sums.body += body_ms
			t = Time.get_ticks_usec()
			nodes.add_child(node)
			var enter_ms := (Time.get_ticks_usec() - t) / 1000.0
			sums.enter += enter_ms
			t = Time.get_ticks_usec()
			nodes.remove_child(node)
			node.free()
			sums.free += (Time.get_ticks_usec() - t) / 1000.0
			count += 1
		var parts_text := PackedStringArray()
		var total := 0.0
		for part: String in sums:
			parts_text.append("%s %.2f" % [part, sums[part] / maxf(count, 1)])
			total += sums[part]
		worst = total / maxf(count, 1)
		lines.append(
			"split pass %d over %d builds (%d triangles): mean ms per structure: %s; total %.2f"
			% [pass_index, count, triangles, ", ".join(parts_text), worst]
		)
	return "\n".join(lines)


## The phases of laying and of taking back a settlement's recorded ground strokes, timed on the
## open document and put back afterwards (the paint is undone through its own diffs).
static func _paint_split(editor: AuthoringEditor, step: Dictionary) -> String:
	var doc := editor.document
	var held := doc.settlement(int(step.get("id", 1)))
	if held == null or held.ground.is_empty():
		return "no ground strokes"
	var strokes: Array[Dictionary] = []
	strokes.assign(held.ground)
	var us := {"begin": 0, "dab": 0, "finish": 0, "apply_diff": 0, "update_ground": 0, "scatter": 0}
	var diffs: Array[Dictionary] = []
	var run: SurfaceStroke = null
	var surface := ""
	for stroke in strokes:
		if run == null or str(stroke["surface"]) != surface:
			if run != null:
				var t := Time.get_ticks_usec()
				diffs.append(run.finish())
				us.finish += Time.get_ticks_usec() - t
			surface = str(stroke["surface"])
			var t := Time.get_ticks_usec()
			run = SurfaceStroke.begin(doc, surface, false)
			us.begin += Time.get_ticks_usec() - t
		var t := Time.get_ticks_usec()
		run.dab(stroke["from"], stroke["to"], stroke["radius"], stroke["seconds"])
		us.dab += Time.get_ticks_usec() - t
	var t := Time.get_ticks_usec()
	diffs.append(run.finish())
	us.finish += Time.get_ticks_usec() - t
	for diff in diffs:
		if diff.is_empty():
			continue
		t = Time.get_ticks_usec()
		var rect := SurfaceStroke.apply_diff(doc, diff, true)
		us.apply_diff += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		editor._refresh_ground(rect)
		us.update_ground += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		editor._regenerate_paint(diff)
		us.scatter += Time.get_ticks_usec() - t
	var lay_text := _ms(us)
	for k in range(diffs.size() - 1, -1, -1):
		if not diffs[k].is_empty():
			editor.apply_surface_diff(diffs[k], false)
	# Taking back.
	var un := {"replay": 0, "capture": 0, "remove_total": 0, "apply_diff": 0, "update_ground": 0, "scatter": 0}
	t = Time.get_ticks_usec()
	SettlementUnpaint._replay(doc, strokes)
	un.replay = Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	SettlementUnpaint._capture(doc, strokes)
	un.capture = Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	var diff := SettlementUnpaint.remove(doc, strokes)
	un.remove_total = Time.get_ticks_usec() - t
	var extra := ""
	if not diff.is_empty():
		t = Time.get_ticks_usec()
		var rect := SurfaceStroke.apply_diff(doc, diff, true)
		un.apply_diff = Time.get_ticks_usec() - t
		var terrain: AuthoredTerrain = editor.terrain
		var retable := terrain._layers.needs_retable(terrain._has_water())
		t = Time.get_ticks_usec()
		editor._refresh_ground(rect)
		un.update_ground = Time.get_ticks_usec() - t
		extra = (
			"retable %s, ids %s -> %s, weights %d bytes, broad %.1f ms, rect %s"
			% [
				str(retable),
				str(diff.get("ids_before", [])),
				str(diff.get("ids_after", [])),
				doc.surface_weights.size(),
				terrain.last_broad_update_usec / 1000.0,
				str(rect)
			]
		)
		t = Time.get_ticks_usec()
		editor._regenerate_paint(diff)
		un.scatter = Time.get_ticks_usec() - t
		editor.apply_surface_diff(diff, false)
	return (
		"lay ms %s; unpaint ms %s (diff blocks %d; %s)"
		% [lay_text, _ms(un), (diff.get("blocks", []) as Array).size(), extra]
	)


static func _ms(values: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in values:
		parts.append("%s %.1f" % [key, float(values[key]) / 1000.0])
	return "{" + ", ".join(parts) + "}"


static func _dress(editor: AuthoringEditor, step: Dictionary) -> String:
	var street := int(step.get("id", -1))
	if street < 0 and not editor.document.walls.is_empty():
		street = editor.document.walls[0].id
	editor.settlements.lays_ground = bool(step.get("ground", true))
	var started := Time.get_ticks_usec()
	var id := editor.settlements.dress(
		street,
		String(step.get("kit", "farming_hamlet")),
		float(step.get("wealth", -1.0)),
		float(step.get("density", -1.0))
	)
	editor.settlements.lays_ground = true
	return _timed("dress street %d -> settlement %d" % [street, id], editor, started, "")


static func _timed(head: String, editor: AuthoringEditor, started_us: int, tail: String) -> String:
	var ms := (Time.get_ticks_usec() - started_us) / 1000.0
	var g: Dictionary = editor.settlements.last_ground
	var layer := _layer_of(editor)
	var refresh_ms := layer.last_refresh_usec / 1000.0 if layer != null else -1.0
	return (
		(
			"%s %s: call %.1f ms; strokes %d, plan %.1f ms, paint %.1f ms, taken back %d in %.1f ms;"
			+ " settlement layer refresh %.1f ms"
		)
		% [
			head,
			tail,
			ms,
			int(g.get("strokes", 0)),
			float(g.get("plan_ms", 0.0)),
			float(g.get("paint_ms", 0.0)),
			int(g.get("unpaved", 0)),
			float(g.get("unpaint_ms", 0.0)),
			refresh_ms
		]
	)


static func _layer_of(editor: AuthoringEditor) -> AuthoredSettlements:
	if not is_instance_valid(editor.map_root):
		return null
	return editor.map_root.get_node_or_null(AuthoredSettlements.NODE_NAME) as AuthoredSettlements


static func _save(ctrl: AuthoringController) -> String:
	if ctrl == null:
		return "no authoring controller"
	var path := LevelManager.folder_path(FOLDER)
	_remove_folder(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = FOLDER
	saved.level_folder = FOLDER
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [FOLDER, str(ok)]


static func _cleanup() -> String:
	_remove_folder(LevelManager.folder_path(FOLDER))
	return "removed %s" % FOLDER


## Deletes the one test level (a flat folder of files) by its exact name.
static func _remove_folder(path: String) -> void:
	if not path.get_file() == FOLDER:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)
