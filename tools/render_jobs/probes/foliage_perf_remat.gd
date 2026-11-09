extends RefCounted

## Render-job probe (card matcopy, topic perfaudit): why copies of the built wind materials draw
## faster than the built materials on the same shader (docs/PERFORMANCE.md "Ground-cover
## lighting", "Material copies"). One `call` step per action:
##   {action: "dump", name, dir}  per class of the open map's scatter: the wind materials by
##       shader, and for the first built material of each class beside its copy (`make` "copy"):
##       render priority, next pass, local-to-scene, metadata, the material and shader RIDs, and
##       every uniform as the material and as the RenderingServer hold it. Then the built
##       materials' uniforms are read again after 60 frames, so a parameter written every frame
##       with a new value shows. Writes <dir>/<name>_dump.txt.
##   {action: "parity", name, dir, classes, modes: [mode], settle}  the shader clock frozen (the
##       job's ground_parity `freeze`), the world viewport read back with the built materials,
##       with each mode's materials on `classes` ("all" or class names), and built again; the
##       pixels that differ from the first built frame, the largest channel difference and the
##       mean. Writes <dir>/<name>_parity.txt (and <dir>/<name>_<mode>.png when `save`).
##   {action: "await"}  holds the job while a parity rig runs.
## foliage_perf.gd's `remat` variant key {class: mode} draws that class's wind materials as
## `make` returns them, for its in-run A/B.

const GROUP := "foliage_remat_rig"
const FP_PATH := "res://tools/render_jobs/probes/foliage_perf.gd"
const SELF_PATH := "res://tools/render_jobs/probes/foliage_perf_remat.gd"


## foliage_perf.gd's scatter nodes (loaded, not preloaded: that file preloads this one).
static func scatter_nodes(gm: GameMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(load(FP_PATH).call("scatter_nodes", gm))
	return out


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the remat parity rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "")):
		"await":
			return "idle"
		"dump":
			var rig := DumpRig.new()
			rig.gm = gm
			rig.step = step
			rig.r = load(SELF_PATH)
			base.get_tree().root.add_child(rig)
			return "dump started"
		"parity":
			var rig := ParityRig.new()
			rig.gm = gm
			rig.step = step
			rig.r = load(SELF_PATH)
			base.get_tree().root.add_child(rig)
			return "parity started"
	return "unknown action"


static func dir_of(step: Dictionary) -> String:
	var dir := ProjectSettings.globalize_path(
		String(step.get("dir", "user://render_jobs/matcopy"))
	)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## The material `mode` draws in place of the built wind material `src`:
## "copy" a new ShaderMaterial on src's own shader with every uniform src returns carried over
## (the foliage swap's copy, same shader); "dup" src.duplicate(); "same" src itself;
## "copy_prio" the copy with src's render priority and next pass; "copy_rs" the copy with each
## uniform read from the RenderingServer's side of src; "lean_old" a material built on the lean
## ground-cover shader (WindFoliage.META_GROUND) copied onto the plain wind shader of the same
## antialiasing, any other src itself (what the ground cover cost before card foliagelight).
static func make(src: ShaderMaterial, mode: String) -> Material:
	match mode:
		"same":
			return src
		"dup":
			return src.duplicate()
		"lean_old":
			if not src.has_meta(WindFoliage.META_GROUND):
				return src
	var copy := ShaderMaterial.new()
	copy.shader = src.shader
	if mode == "lean_old":
		var aa := src.shader == WindFoliage.get_shader_ground()
		copy.shader = WindFoliage.get_shader() if aa else WindFoliage.get_shader_no_aa()
	for u: Dictionary in copy.shader.get_shader_uniform_list():
		var value: Variant = src.get_shader_parameter(u.name)
		if mode == "copy_rs":
			value = RenderingServer.material_get_param(src.get_rid(), u.name)
		if value != null:
			copy.set_shader_parameter(u.name, value)
	if mode == "uncapped_flower":
		# Card foliagefix: a flower's authored shade floor and the shader's cast shadow pull, the
		# state before FoliageLight.flower_shade.
		copy.set_shader_parameter("foliage_paint_shade", Vector3(0.431, 0.42, 0.513))
		copy.set_shader_parameter("foliage_paint_shadow", FoliageLight.PAINT_SHADOW_DEFAULT)
	if mode == "copy_prio":
		copy.render_priority = src.render_priority
		copy.next_pass = src.next_pass
	return copy


## What a `swap` or `remat` variant redraws: per class, source shader and target, how many
## distinct wind materials; "" for a variant with neither key. A class key falls back to the
## size class, so "ground" also takes the flowers (size class ground) and the painted ground
## cover: the trap behind card foliagelight's copy offset (card matcopy).
static func census(nodes: Array[Dictionary], v: Dictionary) -> String:
	var swap: Dictionary = v.get("swap", {})
	var remat: Dictionary = v.get("remat", {})
	if swap.is_empty() and remat.is_empty():
		return ""
	var moves := {}
	for n in nodes:
		var mode := picks(n, remat)
		var path := picks(n, swap)
		if mode == "" and path == "":
			continue
		var mesh: Mesh = n.mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as ShaderMaterial
			if src == null or not WindFoliage.is_wind_shader(src.shader):
				continue
			if mode == "lean_old" and not src.has_meta(WindFoliage.META_GROUND):
				continue
			var to := mode if mode != "" else path.get_file()
			var key := "%s: %s -> %s" % [n.cls, src.shader.resource_path.get_file(), to]
			if not moves.has(key):
				moves[key] = {}
			(moves[key] as Dictionary)[src] = true
	var parts: Array[String] = []
	for key in moves:
		parts.append("%s x%d" % [key, (moves[key] as Dictionary).size()])
	return "%s redraws %s" % [String(v.get("name", "")), "; ".join(parts)]


## The class key of a scatter node (foliage_perf.gd's scatter_nodes) as `keys` names it, or "".
static func picks(n: Dictionary, keys: Dictionary) -> String:
	return String(keys.get(n.cls, keys.get(n.size_class, keys.get("all", ""))))


static func write(path: String, lines: Array[String]) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	for l in lines:
		f.store_line(l)


## Reads the uniforms of `mat` as the material and the RenderingServer hold them.
static func uniforms(mat: ShaderMaterial) -> Dictionary:
	var out := {}
	for u: Dictionary in mat.shader.get_shader_uniform_list():
		out[String(u.name)] = [
			mat.get_shader_parameter(u.name), RenderingServer.material_get_param(mat.get_rid(), u.name)
		]
	return out


class DumpRig:
	extends Node
	var gm: GameMap
	var step: Dictionary
	## This script, for its static functions (an inner class cannot call them unqualified).
	var r: GDScript
	var _lines: Array[String] = []

	func _ready() -> void:
		add_to_group(GROUP)
		_main()

	func _main() -> void:
		var nodes: Array[Dictionary] = []
		nodes.assign(r.call("scatter_nodes", gm))
		var firsts := {}
		var by_class := {}
		for n in nodes:
			var mesh: Mesh = (n.mmi as MultiMeshInstance3D).multimesh.mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				var key := "%s/%s" % [n.cls, n.size_class]
				if not by_class.has(key):
					by_class[key] = {}
				var tag := mat.get_class() if mat != null else "null"
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
					tag = (mat as ShaderMaterial).shader.resource_path.get_file()
					if WindFoliage.is_wind_shader((mat as ShaderMaterial).shader):
						if not firsts.has(key):
							firsts[key] = mat
				var seen: Dictionary = by_class[key]
				if not seen.has(tag):
					seen[tag] = {}
				(seen[tag] as Dictionary)[mat] = true
		for key in by_class:
			var parts: Array[String] = []
			for tag in by_class[key]:
				parts.append("%s x%d" % [tag, (by_class[key][tag] as Dictionary).size()])
			_lines.append("class %s: %s" % [key, ", ".join(parts)])
		var before := {}
		for key in firsts:
			var src: ShaderMaterial = firsts[key]
			var copy := r.call("make", src, "copy") as ShaderMaterial
			_lines.append("")
			_lines.append("== %s: built %s vs copy" % [key, src.shader.resource_path])
			_lines.append(_props(src, "built"))
			_lines.append(_props(copy, "copy "))
			var a: Dictionary = r.call("uniforms", src)
			var b: Dictionary = r.call("uniforms", copy)
			before[src] = a
			for name in a:
				var va: Array = a[name]
				var vb: Array = b.get(name, [null, null])
				var same := str(va) == str(vb)
				_lines.append(
					(
						"  %s %s: built %s / rs %s | copy %s / rs %s"
						% ["  " if same else "!=", name, str(va[0]), str(va[1]), str(vb[0]), str(vb[1])]
					)
				)
			for p: Dictionary in src.get_property_list():
				var pn := String(p.name)
				if pn.begins_with("shader_parameter/") or p.usage & PROPERTY_USAGE_STORAGE == 0:
					continue
				if str(src.get(pn)) != str(copy.get(pn)):
					_lines.append("  prop %s: built %s copy %s" % [pn, str(src.get(pn)), str(copy.get(pn))])
		for i in 60:
			await get_tree().process_frame
		for src: ShaderMaterial in before:
			var now: Dictionary = r.call("uniforms", src)
			for name in now:
				if str(now[name]) != str(before[src][name]):
					_lines.append(
						"per-frame: %s %s %s -> %s" % [src, name, str(before[src][name]), str(now[name])]
					)
		var dir := String(r.call("dir_of", step))
		var path := dir.path_join("%s_dump.txt" % String(step.get("name", "dump")))
		r.call("write", path, _lines)
		print("RJ| remat dump -> %s (%d lines)" % [path, _lines.size()])
		queue_free()

	func _props(m: ShaderMaterial, tag: String) -> String:
		return (
			"  %s rid %d shader rid %d prio %d next %s local %s meta %s"
			% [
				tag, m.get_rid().get_id(), m.shader.get_rid().get_id(), m.render_priority,
				str(m.next_pass), str(m.resource_local_to_scene), str(m.get_meta_list())
			]
		)


class ParityRig:
	extends Node
	var gm: GameMap
	var step: Dictionary
	var r: GDScript
	var _orig := {}

	func _ready() -> void:
		add_to_group(GROUP)
		_main()

	func _set_mode(mode: String) -> void:
		var classes: Array = step.get("classes", ["all"])
		var nodes: Array[Dictionary] = []
		nodes.assign(r.call("scatter_nodes", gm))
		for n in nodes:
			var mesh: Mesh = (n.mmi as MultiMeshInstance3D).multimesh.mesh
			if not _orig.has(mesh):
				var mats: Array[Material] = []
				for s in mesh.get_surface_count():
					mats.append(mesh.surface_get_material(s))
				_orig[mesh] = mats
			var hit: bool = classes.has("all") or classes.has(n.cls) or classes.has(n.size_class)
			var origs: Array[Material] = _orig[mesh]
			for s in origs.size():
				var want: Material = origs[s]
				var src := want as ShaderMaterial
				if mode != "" and hit and src != null and WindFoliage.is_wind_shader(src.shader):
					want = r.call("make", src, mode)
				if mesh.surface_get_material(s) != want:
					mesh.surface_set_material(s, want)

	func _grab() -> Image:
		await get_tree().process_frame
		for i in int(step.get("settle", 20)):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := gm.world_viewport.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		return img

	func _main() -> void:
		var dir := String(r.call("dir_of", step))
		var tag := String(step.get("name", "parity"))
		var lines: Array[String] = []
		var ref := await _grab()
		var modes: Array = step.get("modes", ["copy"])
		var shots := {"built_again": ""}
		for mode: String in modes:
			shots[mode] = mode
		shots["built_end"] = ""
		for label: String in shots:
			_set_mode(String(shots[label]))
			var img := await _grab()
			lines.append("%-12s %s" % [label, _diff(ref, img)])
			if bool(step.get("save", false)):
				img.save_png(dir.path_join("%s_%s.png" % [tag, label]))
		_set_mode("")
		if bool(step.get("save", false)):
			ref.save_png(dir.path_join("%s_built.png" % tag))
		r.call("write", dir.path_join("%s_parity.txt" % tag), lines)
		for l in lines:
			print("RJ| remat parity %s: %s" % [tag, l])
		queue_free()

	func _diff(a: Image, b: Image) -> String:
		var da := a.get_data()
		var db := b.get_data()
		if da.size() != db.size():
			return "size differs"
		var px := 0
		var mx := 0
		var total := 0
		var i := 0
		while i < da.size():
			var dr := absi(da[i] - db[i])
			var d := maxi(maxi(dr, absi(da[i + 1] - db[i + 1])), absi(da[i + 2] - db[i + 2]))
			if d > 0:
				px += 1
				total += d
				mx = maxi(mx, d)
			i += 4
		var n := da.size() / 4
		return "differing px %d of %d, max %d, mean %.4f" % [px, n, mx, float(total) / maxf(n, 1.0)]
