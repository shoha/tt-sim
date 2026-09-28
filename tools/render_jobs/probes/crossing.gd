extends RefCounted

## Render-job probe (`call` op) for crossings (phase 4b, P4b-1). There is no Bridge tool yet
## (P4b-2), so crossings are placed through the AuthoringEditor crossing API
## (CrossingEditor.place: a line drawn across water, snapped to the banks). Positions are world
## XZ metres. step.action:
##   place {kind, from, to, width}  kind "plank" or "stones"; logs the id or the refusal, the
##                                  anchors, span, levels, style and the refresh time, and
##                                  names the crossing's middle, ends and first stone
##                                  "found:c<id>_mid", "found:c<id>_a", "found:c<id>_b",
##                                  "found:c<id>_stone<k>" for `look` / `tokens`.
##   report                         every crossing and its node.
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
