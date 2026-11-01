extends RefCounted

## Render-job probe (`call` op) for the token toon probe (TokenToonProbe, jobs/toonprobe_look.json,
## docs/plans/2026-11-01-default-tokens/toonprobe.md). Positions are map XZ metres. `action`:
## - `spawn_row` (`from` [x, z], `to` [x, z], `items`, `count` default items.size(), `yaw`
##   degrees default 0, `zig` metres default 0): tokens evenly along the line, cycling `items`.
##   An item is `avatar:<preset>`, `chunky:<0|1>` (a synthetic flat-shaded vertex-coloured model,
##   like the free chunky game art), or `<pack>:<file>:<height m>` (a GLB read from the developer's
##   own user_assets folder, read-only, scaled to that height; local-only packs, never copied).
## - `mode` (`mode` off|ramp|ink|screen): TokenToonProbe.set_mode.
## - `hide` (`index`, `hidden` default true): the GM-hidden state of the index-th row token.
## - `scan` (`xs`, `zs`): ground heights at the grid, to find open ground among the houses.
## - `report`: the mode, the swapped mesh count, the tokens and their heights.
## - `save` / `cleanup`: the `_toonprobe_` test level.

const PREFIX := "_toonprobe_"
const PACKS_ROOT := "C:/Users/hshore/AppData/Roaming/Godot/app_userdata/TTSim/user_assets/"

static var _row: Array[BoardToken] = []


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var lpc: LevelPlayController = base.get("_level_play_controller")
	match String(step.get("action", "report")):
		"spawn_row":
			return _spawn_row(gm, lpc, step)
		"mode":
			var m := TokenToonProbe.mode_named(String(step.get("mode", "off")))
			TokenToonProbe.set_mode(m, gm.get_tree(), gm.viewport_container)
			return "mode %s, %d meshes swapped" % [step.get("mode", "off"), _swapped(gm)]
		"hide":
			var i := int(step.get("index", 0))
			if i >= _row.size() or not is_instance_valid(_row[i]):
				return "no token %d" % i
			_row[i].set_visible_to_players(not bool(step.get("hidden", true)))
			return "token %d (%s) hidden %s" % [i, _row[i].token_name, step.get("hidden", true)]
		"report":
			return _report(gm)
		"scan":
			# The height the ground raycast finds at each of `zs` for each of `xs` (a roof reads high).
			var out := PackedStringArray()
			for z in step.get("zs", []):
				var row := PackedStringArray()
				for x in step.get("xs", []):
					row.append("%.1f" % _ground(gm, Vector2(float(x), float(z))).y)
				out.append("z%s: %s" % [z, " ".join(row)])
			return " | ".join(out)
		"save":
			return _save(base, step)
		"cleanup":
			return _cleanup()
	return "unknown action %s" % step.get("action", "")


static func _swapped(gm: GameMap) -> int:
	return TokenToonProbe.swapped_meshes(gm.get_tree())


static func _vec2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _ground(gm: GameMap, xz: Vector2) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
	return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)


static func _spawn_row(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var items: Array = step.get("items", [])
	var count := int(step.get("count", items.size()))
	var from := _vec2(step.get("from", [-10, 0]))
	var to := _vec2(step.get("to", [10, 0]))
	_row.clear()
	var out := PackedStringArray()
	for k in count:
		var item := String(items[k % items.size()])
		var t := 0.5 if count == 1 else float(k) / float(count - 1)
		var xz := from.lerp(to, t)
		# Every other token steps toward the camera so wide ones do not overlap in the view.
		xz.y += float(step.get("zig", 0.0)) * float(k % 2)
		var at := _ground(gm, xz)
		var token := _make_token(lpc, item, at, deg_to_rad(float(step.get("yaw", 0.0))))
		if token == null:
			out.append("%s FAILED" % item)
			continue
		_row.append(token)
		out.append("%s" % item)
	return "spawned %d: %s" % [_row.size(), ", ".join(out)]


## One token for an item string at `at` (see the header), or null.
static func _make_token(
	lpc: LevelPlayController, item: String, at: Vector3, yaw: float
) -> BoardToken:
	var parts := item.split(":")
	if parts[0] == "avatar":
		var index := int(parts[1]) % AvatarPresets.PRESETS.size()
		var avatar := lpc.spawn_avatar(
			AvatarPresets.recipe(index), String(AvatarPresets.PRESETS[index].name), at
		)
		if avatar != null:
			avatar.set_transform_immediate(at, Vector3(0, yaw, 0), Vector3.ONE)
			avatar.transform_changed.emit()
		return avatar
	var model: Node3D = null
	var height := 1.0
	if parts[0] == "chunky":
		model = _chunky(int(parts[1]))
		height = 1.0
	else:
		model = GlbUtils.load_glb_with_processing(PACKS_ROOT + parts[0] + "/models/" + parts[1] + ".glb")
		height = float(parts[2])
	if model == null:
		return null
	var natural := _height_of(model)
	var token := BoardTokenFactory.create_from_scene(model)
	if token == null:
		return null
	token.name = item
	token.token_name = item
	lpc.get("_token_spawner").call("_place_new_token", token, "toonprobe", item, "default", at, false)
	var s := height / maxf(natural, 0.01)
	token.set_transform_immediate(at, Vector3(0, yaw, 0), Vector3.ONE * s)
	token.transform_changed.emit()
	return token


## The height of a model's meshes in its own frame (rest pose).
static func _height_of(root: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh == null:
			continue
		var rel := Transform3D.IDENTITY
		var node: Node = mesh
		while node != null and node != root:
			rel = (node as Node3D).transform * rel
			node = node.get_parent()
		var box := mesh.get_aabb()
		for i in 8:
			var y := (rel * box.get_endpoint(i)).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return hi - lo if hi > lo else 1.0


## A synthetic chunky character: boxes with a colour per vertex and flat normals, in one
## surface with a StandardMaterial3D that reads vertex colour, as the free chunky game art
## imports (0: a bear-like animal, 1: a helmeted knight).
static func _chunky(kind: int) -> Node3D:
	var parts: Array = []
	if kind == 0:
		parts = [
			[Vector3(0, 0.45, 0), Vector3(0.7, 0.5, 1.0), Color(0.62, 0.38, 0.22)],
			[Vector3(0, 0.75, 0.62), Vector3(0.5, 0.45, 0.45), Color(0.70, 0.45, 0.27)],
			[Vector3(0, 0.68, 0.9), Vector3(0.22, 0.16, 0.16), Color(0.95, 0.85, 0.7)],
			[Vector3(-0.2, 1.05, 0.55), Vector3(0.14, 0.14, 0.1), Color(0.5, 0.3, 0.18)],
			[Vector3(0.2, 1.05, 0.55), Vector3(0.14, 0.14, 0.1), Color(0.5, 0.3, 0.18)],
			[Vector3(-0.25, 0.12, 0.35), Vector3(0.2, 0.24, 0.2), Color(0.45, 0.27, 0.16)],
			[Vector3(0.25, 0.12, 0.35), Vector3(0.2, 0.24, 0.2), Color(0.45, 0.27, 0.16)],
			[Vector3(-0.25, 0.12, -0.35), Vector3(0.2, 0.24, 0.2), Color(0.45, 0.27, 0.16)],
			[Vector3(0.25, 0.12, -0.35), Vector3(0.2, 0.24, 0.2), Color(0.45, 0.27, 0.16)],
		]
	else:
		parts = [
			[Vector3(0, 0.8, 0), Vector3(0.5, 0.6, 0.3), Color(0.35, 0.45, 0.75)],
			[Vector3(0, 1.28, 0), Vector3(0.34, 0.34, 0.34), Color(0.92, 0.72, 0.58)],
			[Vector3(0, 1.42, 0), Vector3(0.4, 0.2, 0.4), Color(0.75, 0.78, 0.85)],
			[Vector3(-0.17, 0.25, 0), Vector3(0.18, 0.5, 0.2), Color(0.28, 0.22, 0.4)],
			[Vector3(0.17, 0.25, 0), Vector3(0.18, 0.5, 0.2), Color(0.28, 0.22, 0.4)],
			[Vector3(-0.36, 0.8, 0), Vector3(0.14, 0.5, 0.16), Color(0.35, 0.45, 0.75)],
			[Vector3(0.36, 0.8, 0), Vector3(0.14, 0.5, 0.16), Color(0.35, 0.45, 0.75)],
			[Vector3(0.5, 0.85, 0.1), Vector3(0.06, 0.6, 0.3), Color(0.8, 0.7, 0.3)],
		]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var box := BoxMesh.new()
		box.size = p[1]
		var arr := box.surface_get_arrays(0)
		var base := verts.size()
		for v in arr[Mesh.ARRAY_VERTEX]:
			verts.append((v as Vector3) + (p[0] as Vector3))
			cols.append(p[2] as Color)
		norms.append_array(arr[Mesh.ARRAY_NORMAL])
		for i in arr[Mesh.ARRAY_INDEX]:
			idx.append(base + (i as int))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh.surface_set_material(0, mat)
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	model.add_child(mi)
	var body := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.get_aabb().size
	body.shape = shape
	body.position = mesh.get_aabb().get_center()
	model.add_child(body)
	return model


static func _report(gm: GameMap) -> String:
	var out := PackedStringArray()
	for token in _row:
		if is_instance_valid(token):
			var meshes := TokenGhost.meshes_of(token.rigid_body)
			var surfaces := 0
			var detail := ""
			for mi in meshes:
				surfaces += mi.mesh.get_surface_count()
				if token.token_name.begins_with("chunky"):
					var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
					detail = (
						" vcolor format %s material vcol %s"
						% [
							(mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0,
							m.vertex_color_use_as_albedo if m != null else "no material"
						]
					)
			out.append(
				"%s (%d meshes, %d surfaces%s)" % [token.token_name, meshes.size(), surfaces, detail]
			)
	return "mode %d, %d swapped | %s" % [TokenToonProbe.mode, _swapped(gm), " | ".join(out)]


# --- test level ------------------------------------------------------------------------------


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", PREFIX + "village"))
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	SafeDelete.tree(path, LevelManager.levels_dir)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	# The marker SafeDelete needs to remove the test level again.
	SafeDelete.mark(path, "toonprobe-level", LevelManager.levels_dir)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			var result := SafeDelete.tree(LevelManager.folder_path(folder), LevelManager.levels_dir)
			removed.append("%s:%s" % [folder, result["ok"]])
	return "removed %s" % str(removed)
