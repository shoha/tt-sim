extends RefCounted

## Render-job probe (`call` op) for the ground ship's frame timings (docs/PERFORMANCE.md
## "Ground look and grass masses (ground ship, 2026-10-15)"; jobs/ground_timing_build.json and
## ground_timing_play.json). It runs on main before the ship as well as after it, so the look's
## parts are reached by node name and dynamic calls (the script parses where GroundLookBake
## does not exist) and answer "no look bake" there. Pairs with perf.gd (start / stop sampling,
## info, mem, ground_std, skirt). `action`:
## - `save` (`name`): writes the open authoring map as `_timing_<build>_<name>`, `<build>` being
##   `head` where GroundLookBake exists and `base` where it does not, replacing an earlier one.
## - `play` / `dress` (`name`): perf.gd's timed `play` and `dress` of that build's level.
## - `cleanup`: deletes every `_timing_` level folder, and nothing else.
## - `sweep` (`name`, `configs`, `shared`, `settle` default 1.5, `s` default 4): inserts into the
##   driver, after this step, per config: `state` with `shared` merged under the config, a
##   `settle` wait, perf.gd `info` and a perf.gd `start` / `stop` window of `s` seconds, labelled
##   "<name> <config label>". A config with `"head": true` is skipped on the base build.
## - `state` (`scatter`, `look`, `tuft`, `code`, `base`, `std`, `skirt`): sets a configuration,
##   each field optional (absent keeps it). `std` / `skirt` (`on` / `off`) are perf.gd's
##   `ground_std` and `skirt`. `scatter`: `all`, `none`, or `nomass` (every MultiMesh
##   with custom data hidden: the massed grass assets, their unanchored rows included). `look`:
##   `on` (the bake's own binding), `off` (look_present 0, what a map with no looked biome
##   binds), `norim` (on, with the accent and path rims and the wet core widths at 0, so the rim
##   path is skipped), `plain` (on, every slot's accent shape PLAIN_SHAPE: no stretch or break),
##   `norim_plain` (both). `tuft`: `on` (the bake binds the grass) or `off` (zone_tuft_strength 0
##   on every bound grass material, what a Blender map's grass has). `code`: `new` (the res://
##   shaders), `old_ground` / `old_grass` / `old_both` (the ground's or the foliage's include
##   swapped, through Shader.code, for the one in the pre-ship checkout at `base`, which has no
##   look path at all). Logs what it set and how many scatter materials draw looked code.
## - `bake_info`: slots, bake size, bakes so far, the last sync's CPU ms, and timed rebinds of the
##   ground and the grass, warm and with the tuft reference cache cleared (the open's cost).
## - `rebake`: GroundLookBake.sync(true) now and its CPU ms (wrap it in `record` for its frames).
## - `bake_gpu` (`s`, `px`): renders every slot's viewport each frame for `s` seconds with
##   render-time measurement (an UPDATE_ONCE viewport reads 0), logs the GPU median per slot;
##   `px` renders at that square size instead (the 2048 px cap), then rebakes at the real size.
## - `bake_free`: frees the slot viewports (look off), for a memory delta between two `mem`s.
## - `regen_watch` (`name`): from now until the authoring scatter's regeneration is applied, and
##   until its growth ends: wall ms of each, frames and worst frame, the last worker and apply ms.
## - `compile` (`path`, default the bake shader): a salted copy of a canvas_item shader (so no
##   cache holds it) drawn once in a 64 px SubViewport; logs get_rid() ms and the ms from there to
##   the end of the frame that drew it (wrap it in `record` for the frame times).

const PREFIX := "_timing_"
const SELF := "res://tools/render_jobs/probes/ground_timing.gd"
const PERF := "res://tools/render_jobs/probes/perf.gd"
const BAKE_NODE := "GroundLookBake"
const BAKE_SHADER := "res://shaders/ground_light_field_bake.gdshader"
const UNIFORMS := "res://utils/ground_look_uniforms.gd"
const FOLIAGE_SHADERS := [
	"res://shaders/wind_foliage.gdshader",
	"res://shaders/wind_foliage_no_aa.gdshader",
	"res://shaders/wind_foliage_painted.gdshader",
	"res://shaders/wind_foliage_painted_no_aa.gdshader",
]
const FOLIAGE_INCLUDE := "shaders/wind_foliage_main.gdshaderinc"
const GROUND_SHADERS := [
	"res://shaders/authored_ground.gdshader",
	"res://shaders/authored_ground_skirt.gdshader",
]
const GROUND_INCLUDE := "shaders/authored_ground.gdshaderinc"
const PLAIN_SHAPE := Vector4(1.0, 0.0, 0.0, 1.0)
const WATCH := "TimingWatch"

## res:// shader path -> its original code, kept from the first swap.
static var _original: Dictionary = {}
static var _code: String = "new"


## Wall-clock watch of a regeneration (`regen_watch`) or of a bake's GPU time (`bake_gpu`).
class Watch:
	extends Node
	var mode := ""
	var label := ""
	var scatter: Node = null
	var bake: Node = null
	var viewports: Array = []
	var resized := false
	var gpu: Array = []
	var start_us := 0
	var last_us := 0
	var until_us := 0
	var frames := PackedFloat64Array()
	var busy_seen := false
	var applied_ms := -1.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		start_us = Time.get_ticks_usec()
		last_us = start_us

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - last_us) / 1000.0)
		last_us = now
		if mode == "bake_gpu":
			_bake_frame(now)
		else:
			_regen_frame(now)

	func _bake_frame(now: int) -> void:
		if frames.size() > 5:
			for s in viewports.size():
				var rid: RID = (viewports[s] as SubViewport).get_viewport_rid()
				# A packed array in an Array is a copy when read: append, then store it back.
				var samples: PackedFloat64Array = gpu[s]
				samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
				gpu[s] = samples
		if now < until_us:
			return
		var parts := PackedStringArray()
		for s in viewports.size():
			var vp := viewports[s] as SubViewport
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), false)
			parts.append("slot %d %s %s" % [s, str(vp.size), _stats(gpu[s], "gpu")])
		if resized:
			bake.call("sync", true)
		_log("bake_gpu %s | %s | %s" % [label, " | ".join(parts), _stats(frames, "frame")])
		queue_free()

	func _regen_frame(now: int) -> void:
		var regen: bool = scatter.call("is_regenerating")
		var growing: bool = scatter.call("is_growing")
		busy_seen = busy_seen or regen
		var waited := (now - start_us) / 1000.0
		if applied_ms < 0.0 and not regen and (busy_seen or waited > 300.0):
			applied_ms = waited
		if (applied_ms >= 0.0 and not growing and not regen) or waited > 30000.0:
			_log(
				(
					(
						"regen %s: applied +%.0f ms (busy seen %s), growth done +%.0f ms, %s,"
						+ " last worker %.1f ms, last apply %.1f ms"
					)
					% [
						label,
						applied_ms,
						str(busy_seen),
						waited,
						_stats(frames, "frames"),
						float(scatter.get("last_worker_usec")) / 1000.0,
						float(scatter.get("last_apply_usec")) / 1000.0,
					]
				)
			)
			queue_free()

	func _log(s: String) -> void:
		for node in get_tree().root.get_children():
			if node.has_method("log_line"):
				node.call("log_line", s)
				return
		print("RJ| " + s)

	static func _stats(values: PackedFloat64Array, name: String) -> String:
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		if n == 0:
			return "%s n 0" % name
		return (
			"%s n %d median %.3f p10 %.3f p90 %.3f worst %.3f"
			% [name, n, s[n / 2], s[n / 10], s[mini(n - 1, n * 9 / 10)], s[n - 1]]
		)


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"save":
			return _save(base, _folder(String(step.get("name", ""))))
		"play", "dress":
			var perf := load(PERF) as GDScript
			var folder := _folder(String(step.get("name", "")))
			return perf.call("run", base, {"action": step.action, "folder": folder})
		"cleanup":
			return _cleanup()
		"sweep":
			return _sweep(base, step)
		"state":
			return _state(base, step)
		"bake_info":
			return _bake_info(base)
		"rebake":
			var bake := _bake(base)
			if bake == null:
				return "no look bake"
			bake.call("sync", true)
			var sync_ms: float = bake.get("last_bake_usec") / 1000.0
			return "rebake: sync %.2f ms CPU, bakes %d" % [sync_ms, bake.get("bakes")]
		"bake_gpu":
			return _bake_gpu(base, step)
		"bake_free":
			var bake := _bake(base)
			if bake == null:
				return "no look bake"
			bake.call("_unbind")
			return "bake viewports freed, look off"
		"regen_watch":
			var c: Node = base.get("_authoring_controller")
			var scatter: Node = c.get("scatter") if c != null else null
			if scatter == null:
				return "no authoring scatter"
			var watch := Watch.new()
			watch.mode = "regen"
			watch.label = String(step.get("name", ""))
			watch.scatter = scatter
			_add_watch(base, watch)
			return "watching regeneration %s" % watch.label
		"compile":
			return _compile(base, String(step.get("path", BAKE_SHADER)))
	return "unknown action %s" % step.get("action", "")


## `head` where the look bake exists, `base` on main before the ship.
static func _build() -> String:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if String(entry.get("class", "")) == BAKE_NODE:
			return "head"
	return "base"


static func _folder(name: String) -> String:
	return "%s%s_%s" % [PREFIX, _build(), name]


static func _terrain(base: Node) -> AuthoredTerrain:
	var gm: GameMap = base.get("_game_map")
	if gm == null:
		return null
	for node in gm.map_container.find_children("*", "Node3D", true, false):
		if node is AuthoredTerrain:
			return node
	return null


static func _bake(base: Node) -> Node:
	var terrain := _terrain(base)
	return terrain.get_node_or_null(BAKE_NODE) if terrain != null else null


static func _scatter_nodes(base: Node) -> Array[MultiMeshInstance3D]:
	var gm: GameMap = base.get("_game_map")
	var out: Array[MultiMeshInstance3D] = []
	for node in gm.map_container.find_children("*", "MultiMeshInstance3D", true, false):
		if not String(node.name).contains("PipelineWarm"):
			out.append(node as MultiMeshInstance3D)
	return out


static func _add_watch(base: Node, watch: Watch) -> void:
	var old := base.get_tree().root.get_node_or_null(WATCH)
	if old != null:
		old.name = WATCH + "_old"
		old.queue_free()
	watch.name = WATCH
	base.get_tree().root.add_child(watch)


## Inserts the sweep's steps into the driver's list after the current step (as expand_ab does).
static func _sweep(base: Node, step: Dictionary) -> String:
	var driver: Node = null
	for node in base.get_tree().root.get_children():
		if node.has_method("log_line") and node.get("steps") is Array:
			driver = node
	if driver == null:
		return "sweep: no driver"
	var steps: Array = driver.get("steps")
	var at: int = driver.get("_i")
	var shared: Dictionary = step.get("shared", {})
	var name := String(step.get("name", ""))
	var added: Array = []
	var skipped := PackedStringArray()
	for config: Dictionary in step.get("configs", []):
		var label := "%s %s" % [name, config.get("label", "")]
		if bool(config.get("head", false)) and _build() != "head":
			skipped.append(String(config.get("label", "")))
			continue
		var state := shared.duplicate()
		state.merge(config, true)
		state.merge({"op": "call", "script": SELF, "action": "state"}, true)
		added.append(state)
		added.append({"op": "wait", "s": float(step.get("settle", 1.5))})
		added.append({"op": "call", "script": PERF, "action": "info", "name": label})
		added.append({"op": "call", "script": PERF, "action": "start", "name": label})
		added.append({"op": "wait", "s": float(step.get("s", 4.0))})
		added.append({"op": "call", "script": PERF, "action": "stop"})
	for k in added.size():
		steps.insert(at + 1 + k, added[k])
	return "sweep %s: %d steps, skipped %s" % [name, added.size(), str(skipped)]


static func _state(base: Node, step: Dictionary) -> String:
	var parts := PackedStringArray()
	if step.has("code"):
		parts.append(_set_code(String(step.code), String(step.get("base", ""))))
	if step.has("scatter"):
		parts.append(_set_scatter(base, String(step.scatter)))
	var perf := load(PERF) as GDScript
	if step.has("std"):
		parts.append(perf.call("run", base, {"action": "ground_std", "on": step.std == "on"}))
	if step.has("skirt"):
		parts.append(perf.call("run", base, {"action": "skirt", "visible": step.skirt == "on"}))
	var bake := _bake(base)
	if bake != null and step.has("look"):
		parts.append(_set_look(base, bake, String(step.look)))
	if bake != null and step.has("tuft"):
		if String(step.tuft) == "on":
			bake.call("_bind_grass")
		else:
			for mat: ShaderMaterial in bake.get("_grass_bound"):
				mat.set_shader_parameter("zone_tuft_strength", 0.0)
		parts.append("tuft %s on %d materials" % [step.tuft, bake.get("_grass_bound").size()])
	parts.append(_looked_code(base))
	return "state | " + " | ".join(parts)


static func _set_scatter(base: Node, mode: String) -> String:
	var shown := 0
	var hidden := 0
	for mmi in _scatter_nodes(base):
		var mass := mmi.multimesh != null and mmi.multimesh.use_custom_data
		mmi.visible = mode == "all" or (mode == "nomass" and not mass)
		shown += 1 if mmi.visible else 0
		hidden += 0 if mmi.visible else 1
	return "scatter %s: shown %d hidden %d" % [mode, shown, hidden]


static func _set_look(base: Node, bake: Node, mode: String) -> String:
	var terrain := _terrain(base)
	var mats := [terrain.get_material(), terrain.get_skirt_material()]
	if mode == "off":
		for mat: ShaderMaterial in mats:
			if mat != null:
				mat.set_shader_parameter("look_present", 0)
		return "look off"
	bake.call("_bind_ground")
	for mat: ShaderMaterial in mats:
		if mat == null:
			continue
		if mode.contains("norim"):
			var rim := PackedVector4Array(mat.get_shader_parameter("look_rim"))
			var more := PackedVector4Array(mat.get_shader_parameter("look_rim_more"))
			for i in rim.size():
				rim[i] = Vector4(0.0, 0.0, rim[i].z, rim[i].w)
			for i in more.size():
				more[i] = Vector4(more[i].x, more[i].y, 0.0, more[i].w)
			mat.set_shader_parameter("look_rim", rim)
			mat.set_shader_parameter("look_rim_more", more)
		if mode.contains("plain"):
			var shape := PackedVector4Array(mat.get_shader_parameter("look_shape"))
			for i in shape.size():
				shape[i] = PLAIN_SHAPE
			mat.set_shader_parameter("look_shape", shape)
	var present: Variant = mats[0].get_shader_parameter("look_present")
	return "look %s (look_present %s)" % [mode, str(present)]


## The foliage's and the ground's include, each either the res:// one or the pre-ship one read
## from `base_dir`, through Shader.code on the shared Shader resources.
static func _set_code(code: String, base_dir: String) -> String:
	var old_grass := code == "old_grass" or code == "old_both"
	var old_ground := code == "old_ground" or code == "old_both"
	var grass := _swap(FOLIAGE_SHADERS, FOLIAGE_INCLUDE, old_grass, base_dir)
	var ground := _swap(GROUND_SHADERS, GROUND_INCLUDE, old_ground, base_dir)
	_code = code
	return "code %s: foliage %s, ground %s" % [code, grass, ground]


static func _swap(paths: Array, include_rel: String, old: bool, base_dir: String) -> String:
	var line := '#include "res://%s"' % include_rel
	var include := ""
	if old:
		include = FileAccess.get_file_as_string(base_dir.path_join(include_rel))
		if include == "":
			return "no %s under '%s'" % [include_rel, base_dir]
	var changed := 0
	for path: String in paths:
		var shader := load(path) as Shader
		if not _original.has(path):
			_original[path] = shader.code
		var original := String(_original[path])
		var want := original.replace(line, include) if old else original
		if shader.code != want:
			shader.code = want
			changed += 1
	return "%s (%d recompiled)" % ["old" if old else "new", changed]


## How many scatter surface materials draw one of the swappable foliage Shader resources and
## how many of those include the res:// foliage include (the new code), and the same for the
## terrain's material: a swap reaches only materials that share those resources.
static func _looked_code(base: Node) -> String:
	var shared := {}
	for path: String in FOLIAGE_SHADERS:
		shared[load(path)] = true
	var new_line := '#include "res://%s"' % FOLIAGE_INCLUDE
	var on_shared := 0
	var new_code := 0
	var total := 0
	var seen := {}
	for mmi in _scatter_nodes(base):
		var mesh: Mesh = mmi.multimesh.mesh if mmi.multimesh != null else null
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat: Material = mmi.material_override
			if mat == null:
				mat = mesh.surface_get_material(s)
			if mat is ShaderMaterial and not seen.has(mat):
				seen[mat] = true
				total += 1
				var shader := (mat as ShaderMaterial).shader
				if shared.has(shader):
					on_shared += 1
					new_code += 1 if shader.code.contains(new_line) else 0
	var terrain := _terrain(base)
	var ground := "no terrain"
	if terrain != null and terrain.get_material() != null:
		var shader := terrain.get_material().shader
		ground = (
			"shared %s, new %s"
			% [
				str(shader == load(GROUND_SHADERS[0])),
				str(shader.code.contains('#include "res://%s"' % GROUND_INCLUDE))
			]
		)
	return (
		"foliage materials %d of %d on the shared shaders, %d with the new include; ground %s"
		% [on_shared, total, new_code, ground]
	)


static func _bake_info(base: Node) -> String:
	var bake := _bake(base)
	if bake == null:
		return "no look bake"
	var viewports: Array = bake.get("_viewports")
	var px: Vector2i = bake.get("_px")
	var t0 := Time.get_ticks_usec()
	bake.call("_bind_ground")
	var t1 := Time.get_ticks_usec()
	bake.call("_bind_grass")
	var t2 := Time.get_ticks_usec()
	var cache: Variant = (load(UNIFORMS) as GDScript).get("_tuft_refs")
	var cleared := cache is Dictionary
	if cleared:
		(cache as Dictionary).clear()
	var t3 := Time.get_ticks_usec()
	bake.call("_bind_grass")
	var t4 := Time.get_ticks_usec()
	return (
		(
			"bake_info: slots %d, %s px each (%.1f MB RGBA8 per slot), bakes %d,"
			+ " last sync %.2f ms CPU | bind ground %.2f ms, bind grass warm %.2f ms,"
			+ " cold %.2f ms (cache cleared %s, %d materials)"
		)
		% [
			viewports.size(),
			str(px),
			px.x * px.y * 4.0 / 1048576.0,
			bake.get("bakes"),
			bake.get("last_bake_usec") / 1000.0,
			(t1 - t0) / 1000.0,
			(t2 - t1) / 1000.0,
			(t4 - t3) / 1000.0,
			str(cleared),
			bake.get("_grass_bound").size(),
		]
	)


static func _bake_gpu(base: Node, step: Dictionary) -> String:
	var bake := _bake(base)
	if bake == null:
		return "no look bake"
	var watch := Watch.new()
	watch.mode = "bake_gpu"
	watch.bake = bake
	watch.viewports = bake.get("_viewports")
	var px := int(step.get("px", 0))
	watch.resized = px > 0
	watch.label = "%s px" % (str(px) if px > 0 else "real")
	for vp: SubViewport in watch.viewports:
		if px > 0:
			vp.size = Vector2i(px, px)
			(vp.get_node("Rect") as ColorRect).size = Vector2(px, px)
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		watch.gpu.append(PackedFloat64Array())
	watch.until_us = Time.get_ticks_usec() + int(float(step.get("s", 2.0)) * 1e6)
	_add_watch(base, watch)
	return "bake_gpu %s on %d slots" % [watch.label, watch.viewports.size()]


static func _compile(base: Node, path: String) -> String:
	if not ResourceLoader.exists(path):
		return "compile: no %s" % path
	var source := (load(path) as Shader).code
	var salt := 1.0 + float(Time.get_ticks_usec() % 997 + 1) * 1e-3
	var target := "vec4(1.0)))"
	if not source.contains(target):
		return "compile: no salt point in %s" % path
	var t0 := Time.get_ticks_usec()
	var shader := Shader.new()
	shader.code = source.replace(target, "vec4(%.4f)))" % salt)
	shader.get_rid()
	var t1 := Time.get_ticks_usec()
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(64, 64)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	vp.add_child(rect)
	base.get_tree().root.add_child(vp)
	var log_drawn := func() -> void:
		var ms := (Time.get_ticks_usec() - t1) / 1000.0
		print("RJ| compile %s salt %.4f: drawn %.1f ms after get_rid" % [path, salt, ms])
		vp.queue_free()
	RenderingServer.frame_post_draw.connect(log_drawn, CONNECT_ONE_SHOT)
	return "compile %s salt %.4f: get_rid %.2f ms" % [path, salt, (t1 - t0) / 1000.0]


static func _save(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller"
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
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
		if folder.begins_with(PREFIX):
			if not LevelManager.delete_level_folder(LevelManager.folder_path(folder)):
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
