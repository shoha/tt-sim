extends RefCounted

## Render-job probe (`call` op) for the performance audit's system stream (topic perfaudit,
## 2026-11): what surrounds the frame (start-up, map loads, memory, idle work). Pairs with
## `perfaudit_boot.gd` (a runner that times the boot itself) and the `perfaudit_system*` jobs.
## Every result is one `RJ|` line (or a few), so a run's log is its table. step.action:
##   boot                 the boot timeline perfaudit_boot.gd stored on the root (meta
##                        "perfaudit_boot"): process start to _initialize, main scene load,
##                        frames to the first title frame, pipeline compiles on the way
##   serve {runs}         time FoliageLibrary.apply() (the start-up library serve) `runs` times
##   census {name, ws, textures}  nodes by class, processing nodes by script, UI and canvas
##                        counts, timers, tweens, particles, audio, multimesh instances and their
##                        buffer bytes, unique meshes and vertices, the engine monitors; with
##                        `textures` every unique texture the scene's materials reference, by
##                        user and format, with its estimated size
##   frames {name, s}     record every frame for `s` seconds: frame ms, pipeline compiles; logs
##                        the median, each frame over twice it, and the jank. Its "process"
##                        column is Performance.TIME_PROCESS, which is the MAX over the last
##                        second, not the frame's (a per-script knockout built on it measured
##                        nothing; per-script idle cost comes from `profiler`)
##   load {folder} or {new: {biome, size, seed, landform}}  time a map open frame by frame:
##                        wall, frames, main-thread busy, waits, what 60 Hz vsync would add,
##                        the worst frames with their pipeline compiles, memory before / after
##   save {folder}        save the open authoring map as a `_perfaudit_sys_` level
##   cleanup              delete every `_perfaudit_sys_` level
##   soak {minutes, folders, tokens}  cycles of: play each folder, spawn tokens, back to the
##                        title, a new 100 ft map with a hill and a path, back to the title; one
##                        memory and object line per cycle at the title
##   profiler {on}        the GDScript profiler (EngineDebugger "scripts"; the run needs -d);
##                        turning it off prints the accumulated table to stdout
##   cpu {name, s}        process CPU time over `s` seconds against wall time, frames drawn,
##                        window mode and focus, one nvidia-smi line
##   window {mode}        "minimized" or "windowed"
##   orphans              the orphan nodes by class, script and name
##   key                  time GraphicsWarmup.cache_key()
##   drop_caches          at the title: clear the static caches one by one, logging what each frees
##   await                does nothing; its blocker holds the job while a node above runs

const PREFIX := "_perfaudit_sys_"
const NODE_PREFIX := "PerfauditSys"
const SHAPES := preload("res://tools/render_jobs/probes/terrain_shapes.gd")
const WATER := preload("res://tools/render_jobs/probes/water.gd")


## Holds an `await` step while any of this probe's frame-spanning nodes is still running.
static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	for node in base.get_tree().root.get_children():
		if String(node.name).begins_with(NODE_PREFIX):
			return "%s running" % node.name
	return ""


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"boot":
			return _boot(base)
		"serve":
			return _serve(int(step.get("runs", 3)))
		"census":
			return _census(base, step)
		"frames":
			var rec := Frames.new()
			rec.label = String(step.get("name", "frames"))
			rec.seconds = float(step.get("s", 10.0))
			return _add(base, rec, "frames")
		"load":
			var watch := LoadWatch.new()
			watch.base = base
			watch.step = step
			return _add(base, watch, "load")
		"save":
			return _save(base, String(step.get("folder", PREFIX + "map")))
		"cleanup":
			return _cleanup()
		"soak":
			var soak := Soak.new()
			soak.base = base
			soak.step = step
			return _add(base, soak, "soak")
		"profiler":
			var on := bool(step.get("on", true))
			if not EngineDebugger.is_active():
				return "profiler: no debugger (run with -d)"
			EngineDebugger.profiler_enable("scripts", on)
			return "profiler scripts %s" % ("on" if on else "off (table printed)")
		"cpu":
			var cpu := CpuWindow.new()
			cpu.label = String(step.get("name", "cpu"))
			cpu.seconds = float(step.get("s", 10.0))
			return _add(base, cpu, "cpu")
		"window":
			var minimized := String(step.get("mode", "windowed")) == "minimized"
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_MINIMIZED if minimized else DisplayServer.WINDOW_MODE_WINDOWED
			)
			return "window %s" % step.get("mode", "windowed")
		"await":
			return "awaited"
		"orphans":
			return _orphans()
		"key":
			var t0 := Time.get_ticks_usec()
			var key := GraphicsWarmup.cache_key()
			return "warm-up cache_key %s in %.1f ms" % [key.left(8), (Time.get_ticks_usec() - t0) / 1000.0]
		"drop_caches":
			return _add(base, DropCaches.new(), "drop_caches")
	return "unknown action %s" % step.get("action", "")


## The nodes outside the tree that nothing has freed, counted by class, script and name.
static func _orphans() -> String:
	var counts := {}
	var total := 0
	for id: int in Node.get_orphan_node_ids():
		var node := instance_from_id(id) as Node
		if node == null:
			continue
		total += 1
		var script: Script = node.get_script()
		var key := (
			"%s %s %s"
			% [node.get_class(), script.resource_path.get_file() if script else "-", node.name]
		)
		counts[key] = int(counts.get(key, 0)) + 1
	return "orphans %d | %s" % [total, _top(counts, 30)]


static func _add(base: Node, node: Node, kind: String) -> String:
	node.name = "%s_%s_%d" % [NODE_PREFIX, kind, Time.get_ticks_msec()]
	base.get_tree().root.add_child(node)
	return "%s started" % kind


# --- boot and serve ----------------------------------------------------------------------------


static func _boot(base: Node) -> String:
	var meta: Variant = base.get_tree().root.get_meta("perfaudit_boot", {})
	if not meta is Dictionary or (meta as Dictionary).is_empty():
		return "boot: no timeline (run through perfaudit_boot.gd)"
	var d: Dictionary = meta
	var parts := PackedStringArray()
	for key: String in d:
		var v: Variant = d[key]
		parts.append("%s %s" % [key, ("%.1f" % v) if v is float else str(v)])
	return "boot | " + ", ".join(parts)


static func _serve(runs: int) -> String:
	var times := PackedFloat64Array()
	for i in runs:
		var t0 := Time.get_ticks_usec()
		FoliageLibrary.apply()
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	return "serve FoliageLibrary.apply x%d: %s ms" % [runs, _list(times)]


# --- census ------------------------------------------------------------------------------------


static func _census(base: Node, step: Dictionary) -> String:
	var tree := base.get_tree()
	var classes := {}
	var scripts := {}
	var counts := {
		"nodes": 0,
		"controls": 0,
		"controls_visible": 0,
		"canvas_items": 0,
		"timers_running": 0,
		"particles_emitting": 0,
		"audio_playing": 0,
		"lights": 0,
		"mesh_instances": 0,
		"multimesh_nodes": 0,
		"multimesh_instances": 0,
		"multimesh_buffer_mb": 0.0,
		"input_nodes": 0,
		"process_nodes": 0,
		"physics_nodes": 0,
	}
	var meshes := {}
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(true):
			stack.append(child)
		counts.nodes += 1
		var cls := node.get_class()
		classes[cls] = int(classes.get(cls, 0)) + 1
		var script: Script = node.get_script()
		var key := script.resource_path.get_file() if script != null else "(%s)" % cls
		var proc := node.is_processing()
		var phys := node.is_physics_processing()
		var inp := (
			node.is_processing_input()
			or node.is_processing_unhandled_input()
			or node.is_processing_unhandled_key_input()
		)
		if proc or phys or inp:
			var row: Array = scripts.get(key, [0, 0, 0])
			row[0] += int(proc)
			row[1] += int(phys)
			row[2] += int(inp)
			scripts[key] = row
		counts.process_nodes += int(proc)
		counts.physics_nodes += int(phys)
		counts.input_nodes += int(inp)
		if node is CanvasItem:
			counts.canvas_items += 1
			if node is Control:
				counts.controls += 1
				counts.controls_visible += int((node as Control).is_visible_in_tree())
		elif node is Timer:
			counts.timers_running += int(not (node as Timer).is_stopped())
		elif node is GPUParticles3D:
			counts.particles_emitting += int((node as GPUParticles3D).emitting)
		elif node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			counts.audio_playing += int(node.get("playing"))
		elif node is Light3D:
			counts.lights += int((node as Light3D).visible)
		elif node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			counts.multimesh_nodes += 1
			if mm != null:
				counts.multimesh_instances += mm.instance_count
				counts.multimesh_buffer_mb += mm.instance_count * _mm_stride(mm) / 1048576.0
				if mm.mesh != null:
					meshes[mm.mesh.get_rid()] = mm.mesh
		elif node is MeshInstance3D:
			counts.mesh_instances += 1
			var mesh := (node as MeshInstance3D).mesh
			if mesh != null:
				meshes[mesh.get_rid()] = mesh
	var verts := 0
	var indices := 0
	for mesh: Mesh in meshes.values():
		for s in mesh.get_surface_count():
			verts += _surface_len(mesh, s, false)
			indices += _surface_len(mesh, s, true)
	var lines := PackedStringArray()
	lines.append(
		(
			"census %s | %s | unique meshes %d, vertices %d, indices %d | %s"
			% [
				step.get("name", ""),
				_dict_text(counts),
				meshes.size(),
				verts,
				indices,
				Base._monitors(bool(step.get("ws", false)))
			]
		)
	)
	lines.append("census %s classes | %s" % [step.get("name", ""), _top(classes, 18)])
	var rows := PackedStringArray()
	var keys := scripts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return scripts[a][0] > scripts[b][0])
	for k: String in keys:
		var r: Array = scripts[k]
		rows.append("%s p%d f%d i%d" % [k, r[0], r[1], r[2]])
	lines.append("census %s callbacks | %s" % [step.get("name", ""), ", ".join(rows)])
	lines.append(
		(
			"census %s canvas | root canvas draws %d, objects %d"
			% [
				step.get("name", ""),
				tree.root.get_render_info(
					Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
				),
				tree.root.get_render_info(
					Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_OBJECTS_IN_FRAME
				)
			]
		)
	)
	if bool(step.get("textures", false)):
		lines.append_array(_texture_census(tree, String(step.get("name", ""))))
	for k in range(1, lines.size()):
		Base.log_line(tree, lines[k])
	return lines[0]


static func _mm_stride(mm: MultiMesh) -> int:
	var floats := 12 if mm.transform_format == MultiMesh.TRANSFORM_3D else 8
	floats += 4 if mm.use_colors else 0
	floats += 4 if mm.use_custom_data else 0
	return floats * 4


static func _surface_len(mesh: Mesh, s: int, index: bool) -> int:
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		return am.surface_get_array_index_len(s) if index else am.surface_get_array_len(s)
	var arrays := mesh.surface_get_arrays(s)
	var at := Mesh.ARRAY_INDEX if index else Mesh.ARRAY_VERTEX
	return (arrays[at] as Array).size() if arrays.size() > at and arrays[at] != null else 0


## Every unique texture the scene's materials and the global shader parameters reference:
## totals by user (the material's first node, by its top map child) and by format, and the
## 12 largest. Sizes come from the texture's own image (a GPU read-back for an ImageTexture),
## so this is slow on a big map and is never inside a timed window.
static func _texture_census(tree: SceneTree, label: String) -> PackedStringArray:
	var users := {}
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(true):
			stack.append(child)
		var mats: Array[Material] = []
		if node is GeometryInstance3D:
			var gi := node as GeometryInstance3D
			mats.append(gi.material_override)
			mats.append(gi.material_overlay)
			var mesh: Mesh = null
			if node is MeshInstance3D:
				mesh = (node as MeshInstance3D).mesh
				for s in (node as MeshInstance3D).get_surface_override_material_count():
					mats.append((node as MeshInstance3D).get_surface_override_material(s))
			elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh:
				mesh = (node as MultiMeshInstance3D).multimesh.mesh
			if mesh != null:
				for s in mesh.get_surface_count():
					mats.append(mesh.surface_get_material(s))
		elif node is CanvasItem:
			mats.append((node as CanvasItem).material)
			if node is TextureRect and (node as TextureRect).texture:
				_note(users, (node as TextureRect).texture, "ui")
		for mat in mats:
			_material_textures(mat, users, _owner_label(node))
	for name: StringName in RenderingServer.global_shader_parameter_get_list():
		var v: Variant = RenderingServer.global_shader_parameter_get(name)
		if v is Texture:
			_note(users, v, "global")
	var by_user := {}
	var by_format := {}
	var biggest: Array = []
	var total := 0.0
	for tex: Texture in users.keys():
		var info := _texture_info(tex)
		var mb: float = info.mb
		total += mb
		var user := String(users[tex])
		by_user[user] = float(by_user.get(user, 0.0)) + mb
		by_format[info.format] = float(by_format.get(info.format, 0.0)) + mb
		biggest.append([mb, "%s %s %s" % [user, info.desc, tex.resource_path.get_file()]])
	biggest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top := PackedStringArray()
	for k in mini(12, biggest.size()):
		top.append("%.1f %s" % biggest[k])
	return PackedStringArray(
		[
			(
				"textures %s | %d unique, %.1f MB | by user %s | by format %s"
				% [label, users.size(), total, _top_f(by_user, 12), _top_f(by_format, 12)]
			),
			"textures %s largest | %s" % [label, ", ".join(top)],
		]
	)


static func _owner_label(node: Node) -> String:
	var path := String(node.get_path())
	for key in ["Scatter", "Terrain", "Water", "Structure", "Token", "Skirt", "Weather", "Fire"]:
		if path.contains(key):
			return key.to_lower()
	var parts := path.split("/", false)
	return parts[mini(3, parts.size() - 1)] if parts.size() > 0 else "?"


static func _material_textures(mat: Material, users: Dictionary, user: String) -> void:
	if mat == null:
		return
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader != null:
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				var v: Variant = sm.get_shader_parameter(u.name)
				if v is Texture:
					_note(users, v, user)
	elif mat is BaseMaterial3D:
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var t := (mat as BaseMaterial3D).get_texture(slot)
			if t != null:
				_note(users, t, user)
	if mat.next_pass != null:
		_material_textures(mat.next_pass, users, user)


static func _note(users: Dictionary, tex: Texture, user: String) -> void:
	if not users.has(tex):
		users[tex] = user


static func _texture_info(tex: Texture) -> Dictionary:
	var img: Image = null
	var layers := 1
	if tex is Texture2D:
		img = (tex as Texture2D).get_image()
	elif tex is TextureLayered:
		layers = (tex as TextureLayered).get_layers()
		img = (tex as TextureLayered).get_layer_data(0)
	elif tex is Texture3D:
		var data := (tex as Texture3D).get_data()
		layers = data.size()
		img = data[0] if layers > 0 else null
	if img == null:
		return {"mb": 0.0, "format": "?", "desc": tex.get_class()}
	var fmt := String(ClassDB.class_get_enum_constants("Image", "Format")[img.get_format()])
	var desc := (
		"%dx%d%s %s%s"
		% [
			img.get_width(),
			img.get_height(),
			"x%d" % layers if layers > 1 else "",
			fmt.trim_prefix("FORMAT_"),
			" mip" if img.has_mipmaps() else " nomip"
		]
	)
	return {
		"mb": img.get_data_size() * layers / 1048576.0,
		"format": fmt.trim_prefix("FORMAT_") + (" mip" if img.has_mipmaps() else " nomip"),
		"desc": desc,
	}


# --- levels ------------------------------------------------------------------------------------


static func _save(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var held := WATER.save_blocker(ctrl.scatter)
	if held != "":
		return "NOT saved %s: %s" % [folder, held]
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path):
		LevelManager.delete_level_folder(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	var ttmap := FileAccess.get_file_as_bytes(path.path_join("map.ttmap")).size()
	return "saved %s: %s, map.ttmap %.2f MB" % [folder, str(ok), ttmap / 1048576.0]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			if LevelManager.delete_level_folder(LevelManager.folder_path(folder)):
				removed.append(folder)
	return "removed %s" % str(removed)


# --- helpers -----------------------------------------------------------------------------------


static func _list(values: PackedFloat64Array) -> String:
	var out := PackedStringArray()
	for v in values:
		out.append("%.1f" % v)
	return ", ".join(out)


static func _dict_text(d: Dictionary) -> String:
	var out := PackedStringArray()
	for k: String in d:
		var v: Variant = d[k]
		out.append("%s %s" % [k, ("%.1f" % v) if v is float else str(v)])
	return ", ".join(out)


static func _top(d: Dictionary, n: int) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return d[a] > d[b])
	var out := PackedStringArray()
	for k in mini(n, keys.size()):
		out.append("%s %s" % [keys[k], d[keys[k]]])
	return ", ".join(out)


static func _top_f(d: Dictionary, n: int) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return d[a] > d[b])
	var out := PackedStringArray()
	for k in mini(n, keys.size()):
		out.append("%s %.1f" % [keys[k], d[keys[k]]])
	return ", ".join(out)


# --- frame-spanning nodes ----------------------------------------------------------------------


## The helpers the nodes below and the static actions above share (an inner class cannot call
## the outer script's static functions, so they live here and the nodes extend it).
class Base:
	extends Node

	static func log_line(tree: SceneTree, s: String) -> void:
		for node in tree.root.get_children():
			if node.has_method("log_line"):
				node.call("log_line", s)
				return
		print("RJ| " + s)

	static func _monitors(ws: bool) -> String:
		var out := (
			(
				"static %.1f MB (peak %.1f), video %.1f MB (tex %.1f, buf %.1f), "
				+ "objects %d, resources %d, nodes %d, orphans %d"
			)
			% [
				OS.get_static_memory_usage() / 1048576.0,
				OS.get_static_memory_peak_usage() / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			]
		)
		if ws:
			var p := _process_stats()
			out += (
				", working set %.0f MB (peak %.0f), private %.0f MB"
				% [p.get("ws", 0.0), p.get("peak", 0.0), p.get("private", 0.0)]
			)
		return out

	## One powershell call: working set, peak working set, private bytes (MB), CPU time (ms).
	static func _process_stats() -> Dictionary:
		var cmd := (
			(
				"$p = Get-Process -Id %d; '{0} {1} {2} {3}' -f $p.WorkingSet64, "
				+ "$p.PeakWorkingSet64, $p.PrivateMemorySize64, "
				+ "$p.TotalProcessorTime.TotalMilliseconds"
			)
			% OS.get_process_id()
		)
		var res: Array = []
		OS.execute("powershell", ["-NoProfile", "-Command", cmd], res, true)
		var parts := String(res[0] if not res.is_empty() else "").strip_edges().split(" ")
		if parts.size() != 4:
			return {}
		return {
			"ws": float(parts[0]) / 1048576.0,
			"peak": float(parts[1]) / 1048576.0,
			"private": float(parts[2]) / 1048576.0,
			"cpu_ms": float(parts[3].replace(",", ".")),
		}

	static func stats(values: PackedFloat64Array) -> Dictionary:
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		if n == 0:
			return {"n": 0, "median": 0.0, "p95": 0.0, "worst": 0.0, "sum": 0.0}
		var total := 0.0
		for v in s:
			total += v
		return {
			"n": n,
			"median": s[n / 2],
			"p95": s[clampi(ceili(0.95 * n) - 1, 0, n - 1)],
			"worst": s[n - 1],
			"sum": total,
		}

	static func compiles() -> PackedInt64Array:
		return PackedInt64Array(
			[
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),
			]
		)

	static func compile_text(a: PackedInt64Array, b: PackedInt64Array) -> String:
		var names := ["cv", "me", "su", "dr", "sp"]
		var out := PackedStringArray()
		for k in a.size():
			if b[k] != a[k]:
				out.append("%s%d" % [names[k], b[k] - a[k]])
		return "+".join(out) if not out.is_empty() else "-"

	## Frame times with their pipeline compiles: the median, every frame over twice it (worst
	## first, at most `cap`), the jank above 16.7 ms and what 60 Hz vsync would make of it.
	static func frame_report(ms: PackedFloat64Array, comp: Array, cap: int = 12) -> String:
		var st := stats(ms)
		var jank := 0.0
		var vsync := 0.0
		var spikes: Array = []
		for k in ms.size():
			jank += maxf(0.0, ms[k] - 16.667)
			vsync += maxf(16.667, ms[k])
			if ms[k] > 2.0 * float(st.median) and ms[k] > 8.0:
				spikes.append([ms[k], k, comp[k] if k < comp.size() else "-"])
		spikes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var top := PackedStringArray()
		for k in mini(cap, spikes.size()):
			top.append("%.1f@%d[%s]" % spikes[k])
		return (
			(
				"n %d, sum %.0f ms, median %.2f, p95 %.2f, worst %.1f, over 2x median %d, "
				+ "jank %.0f ms, at 60 Hz %.0f ms | %s"
			)
			% [st.n, st.sum, st.median, st.p95, st.worst, spikes.size(), jank, vsync, " ".join(top)]
		)


## Records `seconds` of frames, then logs frame_report.
class Frames:
	extends Base
	var label := ""
	var seconds := 10.0
	var ms := PackedFloat64Array()
	var proc := PackedFloat64Array()
	var comp: Array = []
	var last_us := 0
	var start_us := 0
	var last_comp := PackedInt64Array()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -100
		last_us = Time.get_ticks_usec()
		start_us = last_us
		last_comp = compiles()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		ms.append((now - last_us) / 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		var c := compiles()
		comp.append(compile_text(last_comp, c))
		last_comp = c
		last_us = now
		if (now - start_us) / 1e6 < seconds:
			return
		var p := stats(proc)
		log_line(
			get_tree(),
			(
				"frames %s | %s | process median %.2f p95 %.2f"
				% [label, frame_report(ms, comp), p.median, p.p95]
			)
		)
		queue_free()


## Times one map open, frame by frame, from the request to the map landing (play) or the
## loading screen dropping and the scatter settling (authoring).
class LoadWatch:
	extends Base
	var base: Node = null
	var step: Dictionary = {}
	var ms := PackedFloat64Array()
	var comp: Array = []
	var start_us := 0
	var last_us := 0
	var last_comp := PackedInt64Array()
	var mem_before := ""
	var label := ""
	var mode := ""
	var open_us := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -100
		mem_before = _monitors(false)
		var new_map: Dictionary = step.get("new", {})
		if not new_map.is_empty():
			mode = "author"
			label = "new %s %s ft" % [new_map.get("biome", ""), new_map.get("size", 100)]
			base.call(
				"_begin_authoring",
				{
					"level": null,
					"new_map":
					{
						"size_ft": int(new_map.get("size", 100)),
						"biome_id": String(new_map.get("biome", "")),
						"seed": int(new_map.get("seed", 1234)),
						"landform": String(new_map.get("landform", StartingLandform.FLAT)),
						"depth_ft": -1,
					},
					"return_to": &"title"
				}
			)
		else:
			label = String(step.get("folder", ""))
			mode = String(step.get("mode", "play"))
			var level := LevelManager.load_level_folder(label, false)
			if mode == "play":
				base.call("_on_play_level_requested", level)
			else:
				base.call("_begin_authoring", {"level": level, "return_to": &"title"})
		start_us = Time.get_ticks_usec()
		last_us = start_us
		last_comp = compiles()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		ms.append((now - last_us) / 1000.0)
		var c := compiles()
		comp.append(compile_text(last_comp, c))
		last_comp = c
		last_us = now
		if not _landed():
			if (now - start_us) / 1e6 > float(step.get("timeout", 90.0)):
				log_line(get_tree(), "load %s: TIMEOUT" % label)
				queue_free()
			return
		var busy := 0.0
		var waits := 0
		for f in ms:
			if f > 2.0:
				busy += f
			else:
				waits += 1
		log_line(
			get_tree(),
			(
				(
					"load %s %s: wall %.0f ms%s, frames over 2 ms sum %.0f ms, "
					+ "short frames (waiting) %d | %s | before %s | after %s"
				)
				% [
					mode,
					label,
					(now - start_us) / 1000.0,
					(", loading screen %.0f ms" % ((open_us - start_us) / 1000.0)) if open_us else "",
					busy,
					waits,
					frame_report(ms, comp),
					mem_before,
					_monitors(bool(step.get("ws", false)))
				]
			)
		)
		queue_free()

	func _landed() -> bool:
		if mode == "play":
			var gm: Node = base.get("_game_map")
			var lpc: Node = base.get("_level_play_controller")
			if gm == null or not is_instance_valid(gm) or lpc == null or gm.call("_is_level_loading"):
				return false
			var map: Variant = lpc.get("loaded_map_instance")
			return map != null and is_instance_valid(map)
		var c: Node = base.get("_authoring_controller")
		if c == null or not is_instance_valid(c) or not c.get("_is_open"):
			return false
		if open_us == 0:
			open_us = Time.get_ticks_usec()
		var scatter: Node = c.get("scatter")
		if scatter == null or not is_instance_valid(scatter):
			return false
		return (
			not scatter.call("has_prepared_species")
			and not scatter.call("is_regenerating")
			and not scatter.call("is_growing")
		)


## What the static caches hold: clears them one at a time (four frames apart, so freed RIDs
## are gone from the monitors) and logs the texture, buffer and static memory each released.
## Run at the title after a map; the next map rebuilds whatever it needs.
class DropCaches:
	extends Base
	var steps: Array = [
		["SurfaceStore.clear_memory", func() -> void: SurfaceStore.clear_memory()],
		["AssetStore.clear_meshes", func() -> void: AssetStore.clear_meshes()],
		["AssetThumbnails.clear", func() -> void: AssetThumbnails.clear()],
		["WindFoliage.reset_caches", func() -> void: WindFoliage.reset_caches()],
		["PaletteLibrary.clear_cache", func() -> void: PaletteLibrary.clear_cache()],
	]
	var index := -1
	var wait := 4
	var last := Vector3.ZERO
	var rows := PackedStringArray()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		last = _read()
		rows.append("start tex %.1f buf %.1f static %.1f MB" % [last.x, last.y, last.z])

	func _process(_delta: float) -> void:
		wait -= 1
		if wait > 0:
			return
		wait = 4
		if index >= 0:
			var now := _read()
			var d := now - last
			rows.append(
				"%s tex %+.1f buf %+.1f static %+.1f" % [steps[index][0], d.x, d.y, d.z]
			)
			last = now
		index += 1
		if index < steps.size():
			(steps[index][1] as Callable).call()
			return
		rows.append("end tex %.1f buf %.1f static %.1f MB" % [last.x, last.y, last.z])
		log_line(get_tree(), "drop_caches | " + ", ".join(rows))
		queue_free()

	static func _read() -> Vector3:
		return Vector3(
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
			OS.get_static_memory_usage() / 1048576.0
		)


## Process CPU time against wall time over `seconds`, with frames drawn and an nvidia-smi line.
class CpuWindow:
	extends Base
	var label := ""
	var seconds := 10.0
	var start_us := 0
	var start_cpu := 0.0
	var start_frames := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		start_cpu = float(_process_stats().get("cpu_ms", 0.0))
		start_us = Time.get_ticks_usec()
		start_frames = Engine.get_frames_drawn()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if (now - start_us) / 1e6 < seconds:
			return
		var frames := Engine.get_frames_drawn() - start_frames
		var p := _process_stats()
		var wall := (now - start_us) / 1000.0
		var cpu := float(p.get("cpu_ms", 0.0)) - start_cpu
		var res: Array = []
		OS.execute(
			"nvidia-smi",
			["--query-gpu=utilization.gpu,pstate,clocks.gr", "--format=csv,noheader"],
			res,
			true
		)
		log_line(
			get_tree(),
			(
				(
					"cpu %s | wall %.0f ms, process cpu %.0f ms (%.2f cores), "
					+ "frames drawn %d (%.1f fps), mode %d, focused %s, gpu %s"
				)
				% [
					label,
					wall,
					cpu,
					cpu / wall,
					frames,
					frames * 1000.0 / wall,
					DisplayServer.window_get_mode(),
					str(DisplayServer.window_is_focused()),
					String(res[0] if not res.is_empty() else "").strip_edges()
				]
			)
		)
		queue_free()


## Cycles of play (each folder, tokens spawned), title, a new 100 ft map with a hill and a
## path, title; a memory line at the title after each cycle, until `minutes` have passed.
class Soak:
	extends Base
	var base: Node = null
	var step: Dictionary = {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_cycle_all.call_deferred()

	func _cycle_all() -> void:
		var end_us := Time.get_ticks_usec() + int(float(step.get("minutes", 5.0)) * 60e6)
		var folders: Array = step.get("folders", [])
		var cycle := 0
		await _settle(1.0)
		log_line(get_tree(), "soak start | %s" % _monitors(true))
		while Time.get_ticks_usec() < end_us:
			cycle += 1
			var t0 := Time.get_ticks_usec()
			for folder: String in folders:
				base.call("_on_play_level_requested", LevelManager.load_level_folder(folder, false))
				await _until(_playing)
				await _settle(1.0)
				var points: Array = []
				for k in int(step.get("tokens", 8)):
					points.append([-6.0 + 1.5 * k, 2.0])
				WATER.run(base, {"action": "tokens", "points": points})
				await _settle(1.0)
				base.call("change_state", 0)
				await _settle(0.5)
			base.call(
				"_begin_authoring",
				{
					"level": null,
					"new_map":
					{
						"size_ft": 100,
						"biome_id": "temperate_forest_summer_s1",
						"seed": 1000 + cycle,
						"landform": StartingLandform.FLAT,
						"depth_ft": -1,
					},
					"return_to": &"title"
				}
			)
			await _until(_authoring_ready)
			SHAPES.run(base, {"action": "hill", "at": [3, 3], "radius": 8, "height": 4})
			SHAPES.run(base, {"action": "path", "points": [[-10, 0], [10, 2]], "width": 2})
			await _until(_authoring_ready)
			base.call("change_state", 0)
			await _settle(1.5)
			log_line(
				get_tree(),
				(
					"soak cycle %d (%.1f s) | %s"
					% [cycle, (Time.get_ticks_usec() - t0) / 1e6, _monitors(true)]
				)
			)
		queue_free()

	func _settle(s: float) -> void:
		var until := Time.get_ticks_usec() + int(s * 1e6)
		while Time.get_ticks_usec() < until:
			await get_tree().process_frame

	func _until(done: Callable) -> void:
		var limit := Time.get_ticks_usec() + 120 * 1000000
		while not done.call() and Time.get_ticks_usec() < limit:
			await get_tree().process_frame

	func _playing() -> bool:
		var gm: Node = base.get("_game_map")
		var lpc: Node = base.get("_level_play_controller")
		if gm == null or not is_instance_valid(gm) or lpc == null or gm.call("_is_level_loading"):
			return false
		var map: Variant = lpc.get("loaded_map_instance")
		return map != null and is_instance_valid(map)

	func _authoring_ready() -> bool:
		var c: Node = base.get("_authoring_controller")
		if c == null or not is_instance_valid(c) or not c.get("_is_open"):
			return false
		var scatter: Node = c.get("scatter")
		return (
			scatter != null
			and is_instance_valid(scatter)
			and not scatter.call("is_regenerating")
			and not scatter.call("is_growing")
		)
