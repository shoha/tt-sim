extends RefCounted

## Render-job probe (`call` op) for crossings (phase 4b, P4b-1), placed through the
## AuthoringEditor crossing API (CrossingEditor.place: a line drawn across water, snapped to the
## banks); the Bridge tool (P4b-2) is driven with the driver's `gesture` and `input` ops and
## read back here with `list` and `timing`. Positions are world XZ metres. step.action:
##   place {kind, from, to, width}  kind "plank" or "stones"; logs the id or the refusal, the
##                                  anchors, span, levels, style and the refresh time, and
##                                  names the crossing's middle, ends and first stone
##                                  "found:c<id>_mid", "found:c<id>_a", "found:c<id>_b",
##                                  "found:c<id>_stone<k>" for `look` / `tokens`.
##   report                         every crossing and its node.
##   list                           every crossing of the document (id, kind, anchors, levels,
##                                  width), naming its found: points as `place` does (P4b-2).
##   timing                         the Bridge tool's last plan (the preview per pointer move)
##                                  and the last crossing edit's refresh, build and node swap.
##   bench {from, to, kind, runs}   plan() `runs` times for that line (median / min), then one
##                                  place and its undo, each timed, with the refresh's parts.
##   undo                           AuthoringController.undo() (logs the label).
##   save {folder}                  writes the open document and level as user://levels/<folder>
##                                  (a _p4b1_ test level only).
##   cleanup                        deletes every user://levels/_p4b1_* folder (test levels).
##   look {at}                      pans so the screen centre looks at `at` ([x, z] or found:).
##   tokens {points, assets}        in play: water.gd's `tokens` with found: points resolved.
##   points {points}                in play: water.gd's `points` (bed, surface, landing, grid
##                                  field, drag resolver) with found: points resolved.

const TEST_PREFIX := "_p4b1_"
const WATER := preload("res://tools/render_jobs/probes/water.gd")

static var _found: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	var gm := base.get("_game_map") as GameMap
	match String(step.get("action", "")):
		"place":
			return _place(base, step)
		"report":
			return _report(base)
		"list":
			return _list(base)
		"timing":
			return _timing(base)
		"bench":
			return _bench(base, step)
		"first_use":
			return _first_use(base, step)
		"undo":
			var ctrl: AuthoringController = base.get("_authoring_controller")
			return "undo: %s" % str(ctrl.call("undo")) if ctrl else "no authoring controller"
		"save":
			return _save(base, String(step.get("folder", "")))
		"cleanup":
			return _cleanup()
		"look":
			return WATER.run(base, {"action": "look", "at": _resolve(step.get("at"))})
		"tokens":
			return (
				WATER
				. run(
					base,
					{
						"action": "tokens",
						"points": _resolve_all(step.get("points", [])),
						"assets": step.get("assets", []),
					}
				)
			)
		"points":
			return WATER.run(
				base, {"action": "points", "points": _resolve_all(step.get("points", []))}
			)
	return "unknown action %s (game map %s)" % [step.get("action", ""), str(gm != null)]


static func _resolve(value: Variant) -> Variant:
	if value is String and String(value).begins_with("found:"):
		var p: Vector2 = _found.get(String(value).trim_prefix("found:"), Vector2.ZERO)
		return [p.x, p.y]
	return value


static func _resolve_all(points: Array) -> Array:
	var out: Array = []
	for p in points:
		out.append(_resolve(p))
	return out


static func _vec(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _place(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var kind := (
		Crossing.Kind.STONES if step.get("kind", "plank") == "stones" else Crossing.Kind.PLANK
	)
	var from := _vec(step.get("from"))
	var to := _vec(step.get("to"))
	var editor := ctrl.editor
	var started := Time.get_ticks_usec()
	var id := editor.crossings.place(
		kind, Vector3(from.x, 0, from.y), Vector3(to.x, 0, to.y), float(step.get("width", -1.0))
	)
	var usec := Time.get_ticks_usec() - started
	if id < 0:
		return "refused: %s" % editor.crossings.last_refusal
	var crossing := editor.crossings.get_crossing(id)
	var a := editor.to_world(Vector3(crossing.start.x, 0, crossing.start.y))
	var b := editor.to_world(Vector3(crossing.end.x, 0, crossing.end.y))
	_found["c%d_a" % id] = Vector2(a.x, a.z)
	_found["c%d_b" % id] = Vector2(b.x, b.z)
	_found["c%d_mid" % id] = Vector2(a.x + b.x, a.z + b.z) * 0.5
	var stones := CrossingGeometry.stone_layout(editor.document, crossing)
	if not crossing.is_plank():
		for k in stones.size():
			var at: Vector2 = stones[k].at
			var world := editor.to_world(Vector3(at.x, 0, at.y))
			_found["c%d_stone%d" % [id, k]] = Vector2(world.x, world.z)
	return (
		(
			"placed %d %s: %s -> %s span %.2f levels %s width %.2f style '%s' stones %d;"
			+ " place %.2f ms (refresh %.2f ms)"
		)
		% [
			id,
			Crossing.KIND_NAMES[kind],
			str(crossing.start.snapped(Vector2.ONE * 0.01)),
			str(crossing.end.snapped(Vector2.ONE * 0.01)),
			crossing.span_m(),
			str(crossing.levels.snapped(Vector3.ONE * 0.01)),
			crossing.width_m,
			crossing.style,
			stones.size() if not crossing.is_plank() else 0,
			usec / 1000.0,
			editor.crossings.last_refresh_usec / 1000.0,
		]
	)


static func _report(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var gm := base.get("_game_map") as GameMap
	var root: Node = ctrl.map_root if ctrl and ctrl.map_root else null
	if root == null and gm != null and gm.map_container.get_child_count() > 0:
		root = gm.map_container.get_child(0)
	if root == null:
		return "no map"
	var node := root.get_node_or_null(AuthoredCrossings.NODE_NAME) as AuthoredCrossings
	if node == null:
		return "no AuthoredCrossings"
	var out := PackedStringArray()
	for child in node.get_children():
		var meshes := PackedStringArray()
		for part in child.get_children():
			if part is MeshInstance3D:
				var mesh := (part as MeshInstance3D).mesh
				meshes.append(
					"%s %d verts" % [part.name, mesh.surface_get_array_len(0) if mesh else 0]
				)
		out.append("%s [%s]" % [child.name, ", ".join(meshes)])
	return (
		"crossings: %s; decks %s top %.2f version %d build %.2f ms swap %.2f ms"
		% [
			"; ".join(out),
			str(node.has_decks()),
			node.top_y,
			node.version,
			node.last_build_usec / 1000.0,
			node.last_swap_usec / 1000.0,
		]
	)


static func _name_points(editor: AuthoringEditor, crossing: Crossing) -> void:
	var id := crossing.id
	var a := editor.to_world(Vector3(crossing.start.x, 0, crossing.start.y))
	var b := editor.to_world(Vector3(crossing.end.x, 0, crossing.end.y))
	_found["c%d_a" % id] = Vector2(a.x, a.z)
	_found["c%d_b" % id] = Vector2(b.x, b.z)
	_found["c%d_mid" % id] = Vector2(a.x + b.x, a.z + b.z) * 0.5


static func _list(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var out := PackedStringArray()
	for crossing in ctrl.editor.crossings.list():
		_name_points(ctrl.editor, crossing)
		(
			out
			. append(
				(
					"%d %s %s -> %s span %.2f levels %s width %.2f"
					% [
						crossing.id,
						Crossing.KIND_NAMES[crossing.kind],
						str(crossing.start.snapped(Vector2.ONE * 0.01)),
						str(crossing.end.snapped(Vector2.ONE * 0.01)),
						crossing.span_m(),
						str(crossing.levels.snapped(Vector3.ONE * 0.01)),
						crossing.width_m,
					]
				)
			)
		)
	return "crossings (%d): %s" % [out.size(), "; ".join(out)]


static func _timing(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var node := ctrl.map_root.get_node_or_null(AuthoredCrossings.NODE_NAME) as AuthoredCrossings
	return (
		"last plan %.2f ms; last refresh %.2f ms (build %.2f, swap %.2f)"
		% [
			ctrl.brush.bridge.last_plan_usec / 1000.0,
			ctrl.editor.crossings.last_refresh_usec / 1000.0,
			node.last_build_usec / 1000.0 if node else -1.0,
			node.last_swap_usec / 1000.0 if node else -1.0,
		]
	)


static func _bench(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var editor := ctrl.editor
	var kind := (
		Crossing.Kind.STONES if step.get("kind", "plank") == "stones" else Crossing.Kind.PLANK
	)
	var from := _vec(step.get("from"))
	var to := _vec(step.get("to"))
	var a := Vector3(from.x, 0, from.y)
	var b := Vector3(to.x, 0, to.y)
	var runs := int(step.get("runs", 20))
	var times := PackedFloat64Array()
	for _i in runs:
		var started := Time.get_ticks_usec()
		editor.crossings.plan(kind, a, b)
		times.append((Time.get_ticks_usec() - started) / 1000.0)
	times.sort()
	var started := Time.get_ticks_usec()
	var id := editor.crossings.place(kind, a, b)
	var place_ms := (Time.get_ticks_usec() - started) / 1000.0
	var node := ctrl.map_root.get_node_or_null(AuthoredCrossings.NODE_NAME) as AuthoredCrossings
	var parts := (
		"refresh %.2f (build %.2f swap %.2f)"
		% [
			editor.crossings.last_refresh_usec / 1000.0,
			node.last_build_usec / 1000.0,
			node.last_swap_usec / 1000.0,
		]
	)
	started = Time.get_ticks_usec()
	var label := ctrl.history.undo()
	var undo_ms := (Time.get_ticks_usec() - started) / 1000.0
	return (
		"plan x%d median %.2f min %.2f max %.2f ms; place id %d %.2f ms, %s; undo '%s' %.2f ms"
		% [runs, times[int(runs * 0.5)], times[0], times[-1], id, place_ms, parts, label, undo_ms]
	)


## The first-use cost of a crossing node's parts for style `style` (default: rocky badlands,
## which a forest map has not used): its material made, its RID asked for (the shader
## built), the mesh, the collision body and the nodes entering the tree, each timed.
static func _first_use(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var editor := ctrl.editor
	var style := String(step.get("style", "rocky_badlands_summer_s1"))
	var from := _vec(step.get("from"))
	var to := _vec(step.get("to"))
	var kind := (
		Crossing.Kind.STONES if step.get("kind", "plank") == "stones" else Crossing.Kind.PLANK
	)
	var crossing := editor.crossings.plan(kind, Vector3(from.x, 0, from.y), Vector3(to.x, 0, to.y))
	if crossing == null:
		return "refused: %s" % editor.crossings.last_refusal
	crossing.style = style
	var parts := CrossingGeometry.build_one(editor.document, crossing)
	var node := AuthoredCrossings.of_map(ctrl.map_root)
	var times := PackedStringArray()
	var t := Time.get_ticks_usec()
	var material: BaseMaterial3D = node.call(
		"_stone_material" if kind == Crossing.Kind.STONES else "_wood_material", style
	)
	times.append("material %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	material.get_rid()
	times.append("rid %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	var arrays: Array = parts.stone if kind == Crossing.Kind.STONES else parts.wood
	# The script as a value: its private static helpers are only callable that way.
	var script: Script = load("res://scenes/terrain/authored_crossings.gd")
	var mesh := script.call("_mesh_instance", "Probe", arrays, material) as Node3D
	times.append("mesh %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	var body := script.call("_body", parts.collision, 999) as Node3D
	times.append("body %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	var holder := Node3D.new()
	holder.name = "FirstUseProbe"
	t = Time.get_ticks_usec()
	holder.add_child(mesh)
	holder.add_child(body)
	ctrl.map_root.add_child(holder)
	times.append("enter tree %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	holder.queue_free()
	return "first use of %s %s: %s ms" % [Crossing.KIND_NAMES[kind], style, ", ".join(times)]


static func _save(base: Node, folder: String) -> String:
	if not folder.begins_with(TEST_PREFIX):
		return "not a %s folder" % TEST_PREFIX
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null:
		return "no authoring controller"
	if DirAccess.dir_exists_absolute(LevelManager.folder_path(folder)):
		return "folder %s exists; not touching it" % folder
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder))
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if not folder.begins_with(TEST_PREFIX):
			continue
		_remove_tree(LevelManager.folder_path(folder))
		removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
