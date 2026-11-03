extends RefCounted

## Render-job probe for the eye-level windows (card eyewindows). Same probe camera as
## eye_probe.gd (controller process off, perspective fov 60, KEEP_HEIGHT, eye 1.6 m above the
## terrain, near 0.05). Pitch and yaw come from looking at the window's centre.
##   list {dir, street_x, z0}    logs the window panes west of the street line x = street_x
##                               (facing +x) nearest z0: centre, normal, size. Reports to
##                               report_list.txt.
##   shots {dir, tag, windows, dists, ortho}
##                               per window {name, c:[x,y,z], n:[nx,nz]}: one still per distance
##                               (eye `dist` m out along the normal, 1.6 m up, looking at the
##                               centre) named <tag>_<name>_d<dist>.png, and with `ortho` one
##                               home-zoom still (the saved ortho camera, centred on the window)
##                               <tag>_<name>_home.png. Full viewport frames.
##   sheet {dir, tags, windows, dists, cell}
##                               one sheet per window: rows = views, columns = tags.
##   await                       holds the job while a rig runs.

const GROUP := "eye_windows_rig"
const PANE_SHADER := "res://shaders/structure_pane.gdshader"


static func blocker(base: Node, _step: Dictionary) -> String:
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the eye windows rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var rig := Rig.new()
	rig.gm = base.get("_game_map")
	rig.step = step
	rig.mode = action
	rig.process_priority = 1000
	base.get_tree().root.add_child(rig)
	return "%s started" % action


class Rig:
	extends Node

	var gm: GameMap = null
	var step: Dictionary = {}
	var mode := ""
	var _cam: Camera3D = null
	var _saved := {}
	var _eye_on := false
	var _pos := Vector3.ZERO
	var _basis := Basis.IDENTITY
	var _dir := ""
	var _lines: Array[String] = []

	func _ready() -> void:
		add_to_group(GROUP)
		_dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/ew")))
		DirAccess.make_dir_recursive_absolute(_dir)
		_cam = gm.camera_node
		_main()

	func _process(_delta: float) -> void:
		if _eye_on:
			_cam.global_transform = Transform3D(_basis, _pos)

	func _main() -> void:
		match mode:
			"list":
				_list()
			"shots":
				await _shots()
			"sheet":
				_sheet()
			_:
				_log("unknown action %s" % mode)
		_leave()
		var f := FileAccess.open(_dir.path_join("report_%s.txt" % mode), FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| eye_windows %s done, %d lines, %s" % [mode, _lines.size(), _dir])
		queue_free()

	func _log(text: String) -> void:
		_lines.append(text)
		print("RJ| " + text)

	# ---- camera ----

	func _enter() -> void:
		if _saved.is_empty():
			gm.get_camera_controller().set_process(false)
			_saved = {
				"proj": _cam.projection,
				"size": _cam.size,
				"near": _cam.near,
				"far": _cam.far,
				"xf": _cam.global_transform,
				"keep": _cam.keep_aspect,
				"fov": _cam.fov,
			}
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.fov = 60.0
		_cam.near = 0.05
		_cam.far = 600.0
		_eye_on = true

	func _home(c: Vector3) -> void:
		_eye_on = false
		_cam.projection = _saved.proj
		_cam.size = _saved.size
		_cam.near = _saved.near
		_cam.far = _saved.far
		_cam.keep_aspect = _saved.keep
		_cam.fov = _saved.fov
		var xf: Transform3D = _saved.xf
		_cam.global_transform = Transform3D(xf.basis, c + xf.basis.z * 40.0)

	func _leave() -> void:
		if _saved.is_empty():
			return
		_eye_on = false
		_cam.projection = _saved.proj
		_cam.size = _saved.size
		_cam.near = _saved.near
		_cam.far = _saved.far
		_cam.keep_aspect = _saved.keep
		_cam.fov = _saved.fov
		_cam.global_transform = _saved.xf
		gm.get_camera_controller().set_process(true)

	func _look(pos: Vector3, target: Vector3) -> void:
		_pos = pos
		_basis = Basis.looking_at(target - pos, Vector3.UP)
		_cam.global_transform = Transform3D(_basis, _pos)

	func _ground_y(x: float, z: float) -> float:
		var space := gm.world_viewport.find_world_3d().direct_space_state
		var hit := DragPlaceController.raycast_terrain_down(space, Vector3(x, 0.0, z))
		return hit.y if hit != Vector3.INF else 0.0

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _shot(name: String) -> void:
		await _frames(6)
		await RenderingServer.frame_post_draw
		gm.world_viewport.get_texture().get_image().save_png(_dir.path_join(name + ".png"))

	# ---- list ----

	## Every pane-sized quad of the pane material, as {c, n (outward, horizontal), w, h}.
	func _panes() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s) as ShaderMaterial
				if mat == null or mat.shader == null or mat.shader.resource_path != PANE_SHADER:
					continue
				var arr := mi.mesh.surface_get_arrays(s)
				var raw: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				if idx.is_empty():
					idx = PackedInt32Array(range(raw.size()))
				# Quads rebuilt from the index buffer: two consecutive triangles over four
				# distinct vertices, listed in order round the quad.
				var v := PackedVector3Array()
				for t in range(0, idx.size() - 5, 6):
					var extra := -1
					for k in range(3, 6):
						if not [idx[t], idx[t + 1], idx[t + 2]].has(idx[t + k]):
							extra = idx[t + k]
					if extra >= 0:
						v.append_array([raw[idx[t]], raw[idx[t + 1]], raw[idx[t + 2]], raw[extra]])
				_log("pane surface of %s: %d vertices" % [mi.get_path(), v.size()])
				for q in range(0, v.size() - 3, 4):
					var a := mi.global_transform * v[q]
					var b := mi.global_transform * v[q + 1]
					var c := mi.global_transform * v[q + 2]
					var d := mi.global_transform * v[q + 3]
					# Godot's front faces are clockwise: this is the outward normal.
					var n := (d - a).cross(b - a)
					if n.length() < 1e-6:
						continue
					n = n.normalized()
					if absf(n.y) > 0.05 or absf((c - a).dot(n)) > 0.02:
						continue
					var ctr := (a + b + c + d) * 0.25
					var w := maxf((b - a).length(), (c - d).length())
					var h := maxf((d - a).length(), (c - b).length())
					var low := minf(minf(a.y, b.y), minf(c.y, d.y))
					if w < 0.45 or w > 1.6 or h < 0.6 or h > 1.6:
						continue
					# The ground is read 2.5 m out in front (under the house itself a ray hits its roof).
					if low < _ground_y(ctr.x + n.x * 2.5, ctr.z + n.z * 2.5) + 0.45:
						continue
					out.append({"c": ctr, "n": n, "w": w, "h": h})
		return out

	func _list() -> void:
		var sx := float(step.get("street_x", 0.0))
		var z0 := float(step.get("z0", 0.0))
		var rows: Array[Dictionary] = []
		var every := _panes()
		_log("pane-sized quads anywhere: %d" % every.size())
		for i in mini(every.size(), 12):
			_log("  any c %s n %s %.2f x %.2f" % [str(every[i].c), str(every[i].n), every[i].w, every[i].h])
		for p in every:
			var c: Vector3 = p.c
			var n: Vector3 = p.n
			if n.x < 0.0:
				n = -n
			if n.x < 0.9 or c.x > sx - 1.5 or c.x < sx - 9.0:
				continue
			p.n = n
			rows.append(p)
		rows.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return absf(a.c.z - z0) < absf(b.c.z - z0)
		)
		_log("panes west of x=%.1f facing +x, nearest z=%.1f: %d" % [sx, z0, rows.size()])
		for i in mini(rows.size(), 40):
			var p: Dictionary = rows[i]
			_log(
				(
					"  c [%.2f, %.2f, %.2f] n [%.2f, %.2f] %.2f x %.2f"
					% [p.c.x, p.c.y, p.c.z, p.n.x, p.n.z, p.w, p.h]
				)
			)

	# ---- shots ----

	func _shots() -> void:
		_enter()
		var tag := String(step.get("tag", "x"))
		for w in step.get("windows", []):
			var c := Vector3(float(w.c[0]), float(w.c[1]), float(w.c[2]))
			var n := Vector3(float(w.n[0]), 0.0, float(w.n[1])).normalized()
			for dist in step.get("dists", [2.0, 3.5, 6.0]):
				var at := c + n * float(dist)
				at.y = _ground_y(at.x, at.z) + 1.6
				_look(at, c)
				_enter()
				_pos = at
				await _shot("%s_%s_d%s" % [tag, w.name, str(dist)])
				_log("%s %s d%s eye %s" % [tag, w.name, str(dist), str(at)])
			if bool(step.get("ortho", true)):
				_home(c)
				await _shot("%s_%s_home" % [tag, w.name])
				_enter()

	# ---- sheet ----

	func _sheet() -> void:
		var cell := Vector2i(int(step.get("cell", 640)), int(step.get("cell", 640)) * 9 / 16)
		var tags: Array = step.get("tags", [])
		var views: Array[String] = []
		for dist in step.get("dists", [2.0, 3.5, 6.0]):
			views.append("d%s" % str(dist))
		if bool(step.get("ortho", true)):
			views.append("home")
		for w in step.get("windows", []):
			var sheet := Image.create(
				cell.x * tags.size(), cell.y * views.size(), false, Image.FORMAT_RGB8
			)
			for r in views.size():
				for k in tags.size():
					var path := _dir.path_join("%s_%s_%s.png" % [tags[k], w.name, views[r]])
					var img := Image.load_from_file(path)
					if img == null:
						_log("missing %s" % path)
						continue
					img.convert(Image.FORMAT_RGB8)
					img.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
					sheet.blit_rect(img, Rect2i(0, 0, cell.x, cell.y), Vector2i(k * cell.x, r * cell.y))
			sheet.save_png(_dir.path_join("sheet_%s.png" % w.name))
			_log("sheet_%s.png: columns %s, rows %s" % [w.name, str(tags), str(views)])
