extends RefCounted

## Render-job probe for the performance audit's foliage stream (perfaudit, 2026-11-09): what the
## scatter costs, by class, pass and pixel. One `call` step per action:
##   {action: "census", name, dir}  per asset and per class of the open map's scatter nodes:
##       chunks, instances, triangles, surfaces, textures; at the current camera, the chunks the
##       frustum keeps and those crossing its edge, the instances in kept chunks and those really
##       in view, and the screen size of each in-view instance (its mesh AABB projected, in
##       world-viewport pixels).
##       Writes <dir>/<name>_census.txt.
##   {action: "perf", name, dir, rounds, warm, frames, settle, ref: {..}, variants: [{name, ..}]}
##       The in-run A/B of the shadowtier probe (vsync off, max_fps 0, the same camera, every round
##       ref, the variants rotated and reversed on odd rounds, ref again; the first `warm` rounds
##       dropped), with the world viewport's GPU and CPU time, the wall time and every captured
##       RenderingDevice timestamp interval by name (launch with --gpu-profile for the passes).
##       Variant keys: `hide` [classes] hides those nodes, `nofol` hides every scatter node,
##       `noshadow` [classes or "all"] stops them casting, `frac` {class: f} draws that fraction of
##       each chunk (the density budget's prefix), `scale3d` multiplies the 3D render scale (the
##       pixel count: fragment work scales with it, vertex work does not), `nowind` drops
##       wind_sway_vertex_offset (sway, gust, flutter) from every wind foliage shader. A class is a
##       library category when the catalog has one, else the asset's size class (large, medium,
##       small, ground), plus "flower" for flower assets. Writes <dir>/<name>_table.txt.
##   {action: "overdraw", name, dir, configs: [{name, ..variant keys}]}  the world viewport in the
##       overdraw debug draw (every surface additive, unshaded), tone mapping linear and the
##       post effects off: mean layers per pixel and the share of pixels at 1, 2, 4, 8 and 16 or
##       more layers, per config (variant keys as in perf). Writes <dir>/<name>_overdraw.txt.
##   {action: "load", name, dir, reps}  the MultiMesh build of every (cell, asset) of the open map's
##       scatter on the real renderer, four ways interleaved: the shipped path (rows to Transform3D,
##       set_instance_transform per instance, custom data), the same without custom data, a
##       GDScript-built 12-float buffer assigned at once, and that buffer prebuilt (the floor a
##       native row-to-buffer conversion would leave); then AuthoredScatter.build_all itself.
##   {action: "await"}  holds the job while a rig runs.
##   {action: "shots", name, dir, configs, crop | cols, eye}  a sheet per config (see _shots).
##   {action: "stack", dir, files, out}  strips joined into one sheet.
## Card foliagelight added the variant key `swap` {class: shader path}: that class's wind
## materials drawn on another shader (copies of the built materials, `_aa` twin under MSAA).
## Card matcopy added `remat` {class: mode} (foliage_perf_remat.gd's `make`: same-shader copies,
## duplicates, the lean ground cover back on the plain shader).
## Card foliagelod added `thin` (bool, see _thin_count: ground cover thinned as shipped, or in
## full) and `mips` (bool, foliage_perf_mips.gd: the textures with their chain, or without).
## A class key falls back to the size class: "ground" also names the flowers (size class ground)
## and every painted ground-cover material, so name "flower": "" to leave the flowers out. perf
## logs what each variant redraws.

const GROUP := "foliage_perf_rig"
const INCLUDE_PATH := "res://shaders/wind_foliage_include.gdshaderinc"
const MAIN_INCLUDE := '#include "res://shaders/wind_foliage_main.gdshaderinc"'
const SWAY_HEAD := (
	"vec3 wind_sway_vertex_offset(vec3 vertex, vec4 color, mat4 model_matrix, float time) {"
)
const NO_WIND := "FOLIAGE_PERF_NO_WIND"
const PX_BINS: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0]
## The `load` action, in its own file (the line cap).
const LOAD := preload("res://tools/render_jobs/probes/foliage_perf_load.gd")
## The `remat` variant key's materials (card matcopy).
const REMAT := preload("res://tools/render_jobs/probes/foliage_perf_remat.gd")
## The `mips` variant key's textures (card foliagelod).
const MIPS := preload("res://tools/render_jobs/probes/foliage_perf_mips.gd")


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the foliage perf rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	if action == "census":
		return _census(base, step)
	if action == "load":
		return LOAD.run(base, step, _dir(step))
	if action == "stack":
		return _stack(step)
	var rig := Rig.new()
	rig.gm = base.get("_game_map")
	rig.probe = load(String(step.get("script", "res://tools/render_jobs/probes/foliage_perf.gd")))
	rig.step = step
	rig.mode = action
	base.get_tree().root.add_child(rig)
	return "%s %s started" % [action, String(step.get("name", ""))]


static func _dir(step: Dictionary) -> String:
	var dir := ProjectSettings.globalize_path(
		String(step.get("dir", "user://render_jobs/perfaudit_foliage"))
	)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## {action: "stack", dir, files: [png names in dir], out}: the files one above the other, with a
## 4 px dark gutter, saved as <dir>/<out> (card foliagelight's contact sheet).
static func _stack(step: Dictionary) -> String:
	var dir := _dir(step)
	var imgs: Array[Image] = []
	var w := 0
	var h := 0
	for name in step.get("files", []):
		var img := Image.load_from_file(dir.path_join(String(name)))
		if img == null:
			return "stack: %s missing" % name
		img.convert(Image.FORMAT_RGBA8)
		imgs.append(img)
		w = maxi(w, img.get_width())
		h += img.get_height() + 4
	var sheet := Image.create(w, maxi(h - 4, 1), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.08, 0.08))
	var y := 0
	for img in imgs:
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		y += img.get_height() + 4
	var out := dir.path_join(String(step.get("out", "stack.png")))
	sheet.save_png(out)
	return "stack: %d strips -> %s" % [imgs.size(), out]


static func _write(path: String, lines: Array[String]) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	for l in lines:
		f.store_line(l)


## Every scatter chunk node of the map: {mmi, asset, cls, size_class, tris, cast, count}.
static func scatter_nodes(gm: GameMap) -> Array[Dictionary]:
	var by_stem := {}
	var assets: Dictionary = PaletteLibrary.get_palette()["assets"]
	for asset_id in assets:
		by_stem[String(asset_id).validate_node_name()] = asset_id
	var out: Array[Dictionary] = []
	for node in gm.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var at := String(mmi.name).find("_MultiMesh")
		if at < 0 or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var stem := String(mmi.name).substr(0, at)
		var asset_id := String(by_stem.get(stem, stem))
		var entry: Dictionary = assets.get(asset_id, {})
		var size_class := String(entry.get("size_class", "?"))
		var cls := String(entry.get("category", size_class))
		if entry.get("flower", false) == true:
			cls = "flower"
		out.append(
			{
				"mmi": mmi,
				"asset": asset_id,
				"cls": cls,
				"size_class": size_class,
				"tris": FoliageBudget.primitives_per_instance(mmi.multimesh.mesh),
				"cast": mmi.cast_shadow,
				"count": mmi.multimesh.visible_instance_count,
			}
		)
	return out


static func _drawn_count(mm: MultiMesh) -> int:
	return mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count


## Screen rect (world-viewport pixels) of `aabb` under `xf` seen by `cam`.
static func _screen_rect(cam: Camera3D, xf: Transform3D, aabb: AABB) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := cam.unproject_position(xf * aabb.get_endpoint(i))
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


static func _census(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cam := gm.camera_node
	var vp := gm.world_viewport
	var view := Rect2(Vector2.ZERO, Vector2(vp.size))
	var view_area := view.get_area()
	var nodes := scatter_nodes(gm)
	var stride := maxi(1, int(step.get("stride", 1)))
	var per_asset := {}
	var per_cls := {}
	var textures := {}
	for n in nodes:
		var mmi: MultiMeshInstance3D = n.mmi
		var mm := mmi.multimesh
		var mesh := mm.mesh
		var maabb := mesh.get_aabb()
		var a: Dictionary = per_asset.get(n.asset, {})
		if a.is_empty():
			a = _blank(n)
			a["surfaces"] = mesh.get_surface_count()
			var verts := 0
			for s in mesh.get_surface_count():
				verts += mesh.surface_get_array_len(s)
				var mat := mesh.surface_get_material(s)
				if mat is ShaderMaterial:
					var sm := mat as ShaderMaterial
					a["shader"] = sm.shader.resource_path.get_file() if sm.shader else "?"
					for key in ["albedo_texture", "orm_texture", "normal_texture"]:
						var tex: Variant = sm.get_shader_parameter(key)
						if tex is Texture2D:
							var t := tex as Texture2D
							a["tex"].append("%s %dx%d" % [key.get_slice("_", 0), t.get_width(), t.get_height()])
							if not textures.has(t.get_rid()):
								var img := t.get_image()
								textures[t.get_rid()] = [
									t.get_width(), t.get_height(),
									img.get_format() if img else -1,
									img.has_mipmaps() if img else false
								]
			a["verts"] = verts
			a["aabb"] = maabb.size
			per_asset[n.asset] = a
		var c: Dictionary = per_cls.get(n.cls, {})
		if c.is_empty():
			c = _blank(n)
			per_cls[n.cls] = c
		var count := _drawn_count(mm)
		var cull_aabb := mm.get_aabb().grow(mmi.extra_cull_margin)
		var chunk_rect := _screen_rect(cam, mmi.global_transform, cull_aabb)
		var drawn := chunk_rect.intersects(view)
		var inside := view.encloses(chunk_rect)
		var tris: int = n.tris
		for rec: Dictionary in [a, c]:
			rec.chunks += 1
			rec.instances += count
			rec.prims += count * tris
			if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				rec.casting_chunks += 1
			if drawn:
				rec.drawn_chunks += 1
				rec.drawn_instances += count
				rec.drawn_prims += count * tris
				if not inside:
					rec.crossing += 1
		if not drawn:
			continue
		var i := 0
		while i < count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			var r := _screen_rect(cam, xf, maabb)
			if r.intersects(view):
				var px := maxf(r.size.x, r.size.y)
				var area := r.intersection(view).get_area()
				var bin := PX_BINS.size()
				for b in PX_BINS.size():
					if px < PX_BINS[b]:
						bin = b
						break
				for rec: Dictionary in [a, c]:
					rec.in_view += stride
					rec.bins[bin] += stride
					rec.area += area * stride
					rec.view_prims += tris * stride
					if px < 2.0:
						rec.small_prims += tris * stride
					rec.px.append(px)
			i += stride
	var lines: Array[String] = []
	lines.append(
		(
			"census %s: world viewport %s scale3d %.2f, camera size %.2f, %d scatter nodes, stride %d"
			% [
				step.get("name", ""), str(vp.size), vp.scaling_3d_scale, cam.size, nodes.size(),
				stride
			]
		)
	)
	lines.append("bins (max screen side px): <1 <2 <4 <8 <16 <32 <64 >=64")
	var ids := per_asset.keys()
	ids.sort_custom(func(x, y): return per_asset[x].instances > per_asset[y].instances)
	var tot := _blank({"tris": 0})
	for asset_id in ids:
		lines.append(_line("asset " + String(asset_id), per_asset[asset_id], view_area, true))
	var classes := per_cls.keys()
	classes.sort()
	for cls in classes:
		var c: Dictionary = per_cls[cls]
		lines.append(_line("class " + String(cls), c, view_area, false))
		for key in [
			"chunks", "instances", "drawn_chunks", "drawn_instances", "crossing", "in_view",
			"area", "casting_chunks", "prims", "drawn_prims", "view_prims", "small_prims"
		]:
			tot[key] = float(tot.get(key, 0)) + float(c.get(key, 0))
	lines.append(
		(
			(
				"total: chunks %d drawn %d crossing %d casting %d | instances %d drawn %d in view %d"
				+ " | prims %d drawn %d in view %d in instances under 2 px %d | bbox coverage %.2f"
			)
			% [
				tot.chunks, tot.drawn_chunks, tot.crossing, tot.casting_chunks, tot.instances,
				tot.drawn_instances, tot.in_view, tot.prims, tot.drawn_prims, tot.view_prims,
				tot.small_prims, tot.area / view_area
			]
		)
	)
	for rid in textures:
		lines.append("texture %s" % str(textures[rid]))
	var rs: Array[String] = []
	for m in ClassDB.class_get_method_list("RenderingServer", true):
		if String(m.name).begins_with("multimesh_"):
			rs.append(String(m.name))
	lines.append("RenderingServer multimesh methods: %s" % ", ".join(rs))
	_write(_dir(step).path_join("%s_census.txt" % String(step.get("name", "census"))), lines)
	for l in lines:
		if l.begins_with("class") or l.begins_with("total") or l.begins_with("census"):
			print("RJ| " + l)
	return "census %s: %d lines" % [step.get("name", ""), lines.size()]


static func _blank(n: Dictionary) -> Dictionary:
	var bins: Array[int] = []
	bins.resize(PX_BINS.size() + 1)
	bins.fill(0)
	return {
		"cls": n.get("cls", ""), "size_class": n.get("size_class", ""), "tris": n.get("tris", 0),
		"chunks": 0, "instances": 0, "drawn_chunks": 0, "drawn_instances": 0, "crossing": 0,
		"in_view": 0, "area": 0.0, "bins": bins, "px": [], "casting_chunks": 0, "tex": [],
		"shader": "", "surfaces": 0, "verts": 0, "aabb": Vector3.ZERO, "prims": 0,
		"drawn_prims": 0, "view_prims": 0, "small_prims": 0
	}


static func _line(label: String, r: Dictionary, view_area: float, asset: bool) -> String:
	var px: Array = r.px
	px.sort()
	var med: float = px[px.size() / 2] if not px.is_empty() else 0.0
	var shares: Array[String] = []
	for b in r.bins:
		shares.append("%.0f" % (100.0 * float(b) / maxf(1.0, float(r.in_view))))
	var text := (
		(
			"%-58s %-12s tris %5d | chunks %4d drawn %4d crossing %4d | inst %6d drawn %6d view %6d"
			+ " (view/drawn %.2f) | prims %d drawn %d view %d under2px %d | median px %.1f"
			+ " bins%% %s | bbox cover %.3f"
		)
		% [
			label, r.cls, r.tris if asset else 0, r.chunks, r.drawn_chunks, r.crossing,
			r.instances, r.drawn_instances, r.in_view,
			float(r.in_view) / maxf(1.0, float(r.drawn_instances)), r.prims, r.drawn_prims,
			r.view_prims, r.small_prims, med, "/".join(shares), r.area / view_area
		]
	)
	if asset:
		text += (
			" | surf %d verts %d aabb %s %s %s"
			% [
				r.surfaces, r.verts, str(r.aabb.snapped(Vector3.ONE * 0.01)), r.shader,
				",".join(r.tex)
			]
		)
	return text


class Rig:
	extends Node

	var gm: GameMap = null
	## This script, for its static helpers (an inner class cannot call them unqualified).
	var probe: Script = null
	var step: Dictionary = {}
	var mode := "perf"
	var _dir := ""
	var _lines: Array[String] = []
	var _nodes: Array[Dictionary] = []
	var _orig_scale := 1.0
	var _shaders: Array[Shader] = []
	var _shader_code := {}
	var _include: ShaderInclude = null
	var _include_code := ""
	var _wind_on := true
	var _orig_lod_px := 1.0
	## Source mesh -> the same mesh with a generated LOD chain (_prepare_lods).
	var _lod_mesh := {}
	## Merge size k -> the merged chunk nodes (_prepare_merge); asset id -> trivial material.
	var _merged := {}
	var _trivial_mat := {}
	## `swap` (card foliagelight): source mesh -> its surface materials as built; and
	## "<material id>|<shader path>" -> that material's copy on the other shader.
	var _orig_surfaces := {}
	var _swap_mat := {}

	func _ready() -> void:
		add_to_group(GROUP)
		_dir = ProjectSettings.globalize_path(
			String(step.get("dir", "user://render_jobs/perfaudit_foliage"))
		)
		DirAccess.make_dir_recursive_absolute(_dir)
		_nodes.assign(probe.call("scatter_nodes", gm))
		_orig_scale = gm.world_viewport.scaling_3d_scale
		_orig_lod_px = gm.world_viewport.mesh_lod_threshold
		for n in _nodes:
			n["mesh"] = (n.mmi as MultiMeshInstance3D).multimesh.mesh
		_main()

	func _main() -> void:
		if mode == "perf":
			await _perf()
		elif mode == "overdraw":
			await _overdraw()
		elif mode == "shots":
			await _shots()
		else:
			_log("unknown action %s" % mode)
		_restore()
		var tag := String(step.get("name", mode))
		var f := FileAccess.open(_dir.path_join("%s_%s_report.txt" % [tag, mode]), FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| foliage_perf %s %s done, %d lines" % [mode, tag, _lines.size()])
		queue_free()

	func _log(text: String) -> void:
		_lines.append(text)
		print("RJ| " + text)

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _median(a: Array) -> float:
		if a.is_empty():
			return 0.0
		var b := a.duplicate()
		b.sort()
		return float(b[b.size() / 2])

	func _min(a: Array) -> float:
		return float(a.min()) if not a.is_empty() else 0.0

	func _max(a: Array) -> float:
		return float(a.max()) if not a.is_empty() else 0.0

	# ---- variants ----

	func _uses_wind(variants: Array) -> bool:
		for v: Dictionary in variants:
			if bool(v.get("nowind", false)):
				return true
		return false

	## Prepares the no-wind switch: the include's sway function returns zero under NO_WIND, and
	## each wind variant shader defines it or not (setting its code re-preprocesses the include).
	func _prepare_wind() -> void:
		_include = load(INCLUDE_PATH) as ShaderInclude
		_include_code = _include.code
		if not _include_code.contains(SWAY_HEAD):
			_log("nowind: sway head not found; variant inert")
			return
		_include.code = _include_code.replace(
			SWAY_HEAD, SWAY_HEAD + "\n#ifdef %s\n\treturn vec3(0.0);\n#endif" % NO_WIND
		)
		for n in _nodes:
			var mesh: Mesh = (n.mmi as MultiMeshInstance3D).multimesh.mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
					var sh := (mat as ShaderMaterial).shader
					if sh.code.contains(MAIN_INCLUDE) and not _shader_code.has(sh):
						_shader_code[sh] = sh.code
						_shaders.append(sh)
		var names := _shaders.map(func(s): return s.resource_path.get_file())
		_log("nowind: %d wind shaders: %s" % [_shaders.size(), str(names)])

	func _set_wind(on: bool) -> void:
		if on == _wind_on or _shaders.is_empty():
			return
		_wind_on = on
		for sh in _shaders:
			var code: String = _shader_code[sh]
			sh.code = code if on else code.replace(MAIN_INCLUDE, "#define %s\n%s" % [NO_WIND, MAIN_INCLUDE])

	func _apply(v: Dictionary) -> void:
		var hide: Array = v.get("hide", [])
		var noshadow: Array = v.get("noshadow", [])
		var frac: Dictionary = v.get("frac", {})
		var nofol := bool(v.get("nofol", false))
		for n in _nodes:
			var mmi: MultiMeshInstance3D = n.mmi
			if not is_instance_valid(mmi):
				continue
			mmi.visible = not (nofol or hide.has(n.cls) or hide.has(n.size_class))
			var ns: bool = noshadow.has("all") or noshadow.has(n.cls) or noshadow.has(n.size_class)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ns else n.cast
			var f := float(frac.get(n.cls, frac.get(n.size_class, frac.get("all", -1.0))))
			var mm := mmi.multimesh
			if f >= 0.0:
				var full: int = mm.instance_count if int(n.count) < 0 else int(n.count)
				mm.visible_instance_count = int(ceil(full * f))
			else:
				mm.visible_instance_count = int(n.count)
			if v.has("thin") and FoliageDensityController.is_ground(mmi):
				mm.visible_instance_count = _thin_count(mm, bool(v.thin))
			if int(v.get("merge", 0)) > 0:
				mmi.visible = false
			var trivial: Array = v.get("trivial", [])
			var hit_t: bool = trivial.has("all") or trivial.has(n.cls) or trivial.has(n.size_class)
			mmi.material_override = _trivial_mat.get(n.asset) if hit_t else null
			var lod: Array = v.get("lod", [])
			var orig: Mesh = n.mesh
			var want: Mesh = orig
			if lod.has("all") or lod.has(n.cls) or lod.has(n.size_class):
				want = _lod_mesh.get(orig, orig)
			if mm.mesh != want:
				mm.mesh = want
			_apply_swap(n, v.get("swap", {}), v.get("remat", {}))
			if v.has("mips"):
				MIPS.set_mips(orig, bool(v.mips))
		var merge := int(v.get("merge", 0))
		for k in _merged:
			for m: MultiMeshInstance3D in _merged[k]:
				m.visible = k == merge
		gm.world_viewport.scaling_3d_scale = _orig_scale * float(v.get("scale3d", 1.0))
		gm.world_viewport.mesh_lod_threshold = float(v.get("lod_px", _orig_lod_px))
		_set_wind(not bool(v.get("nowind", false)))

	## `thin` (card foliagelod): ground cover at the camera's zoom-keyed thinning (true) or in full.
	func _thin_count(mm: MultiMesh, on: bool) -> int:
		var home := float(gm.get_camera_controller().get("_home_zoom"))
		var keep := FoliageDensityController.keep_fraction(gm.camera_node.size, home)
		return FoliageDensityController.thinned_count(mm.instance_count, keep if on else 1.0)

	## `swap` {class: shader path} (card foliagelight): every wind material of that class's
	## meshes drawn on the shader at the path instead (a copy, every uniform carried over); an
	## empty dictionary puts the built materials back. The mesh is shared by every chunk of its
	## asset, so this is one switch per asset. `remat` {class: mode} (card matcopy) draws the
	## class's wind materials as foliage_perf_remat.gd's `make` returns them instead.
	func _apply_swap(n: Dictionary, swap: Dictionary, remat: Dictionary = {}) -> void:
		var mesh: Mesh = n.mesh
		if not _orig_surfaces.has(mesh):
			if swap.is_empty() and remat.is_empty():
				return
			var mats: Array[Material] = []
			for s in mesh.get_surface_count():
				mats.append(mesh.surface_get_material(s))
			_orig_surfaces[mesh] = mats
		var path := String(swap.get(n.cls, swap.get(n.size_class, swap.get("all", ""))))
		var mode := REMAT.picks(n, remat)
		var origs: Array[Material] = _orig_surfaces[mesh]
		for s in origs.size():
			var want: Material = origs[s]
			var src := want as ShaderMaterial
			if mode != "" and src != null and WindFoliage.is_wind_shader(src.shader):
				var rkey := "%d|%s" % [src.get_instance_id(), mode]
				if not _swap_mat.has(rkey):
					_swap_mat[rkey] = REMAT.make(src, mode)
				want = _swap_mat[rkey]
			elif path != "" and src != null and WindFoliage.is_wind_shader(src.shader):
				# A source on an antialiased wind shader (the eye view's MSAA) takes the variant's
				# `_aa` twin when there is one.
				var use := path
				var twin := path.replace(".gdshader", "_aa.gdshader")
				if not src.shader.resource_path.contains("no_aa") and ResourceLoader.exists(twin):
					use = twin
				var key := "%d|%s" % [src.get_instance_id(), use]
				if not _swap_mat.has(key):
					var copy := ShaderMaterial.new()
					copy.shader = load(use) as Shader
					for u: Dictionary in copy.shader.get_shader_uniform_list():
						var value: Variant = src.get_shader_parameter(u.name)
						if value != null:
							copy.set_shader_parameter(u.name, value)
					_swap_mat[key] = copy
				want = _swap_mat[key]
			if mesh.surface_get_material(s) != want:
				mesh.surface_set_material(s, want)

	func _restore() -> void:
		_apply({})
		_set_wind(true)
		if _include != null:
			_include.code = _include_code
		for k in _merged:
			for m: MultiMeshInstance3D in _merged[k]:
				m.queue_free()
		_merged.clear()

	## Merged chunk nodes for every `merge` size k any variant names: one node per (asset, k x k
	## block of 10 m cells) holding the instances of the cells it covers, hidden until a variant
	## shows them (fewer draws, the same instances, coarser culling). Also the trivial-shader
	## override materials (`trivial`): the debug variant, unshaded, the albedo cutout only.
	func _prepare_merge(variants: Array) -> void:
		var sizes := {}
		var want_trivial := false
		for v: Dictionary in variants:
			if int(v.get("merge", 0)) > 0:
				sizes[int(v.merge)] = true
			if not (v.get("trivial", []) as Array).is_empty():
				want_trivial = true
		if want_trivial:
			var sh := load("res://shaders/wind_foliage_debug_trivial.gdshader") as Shader
			for n in _nodes:
				if _trivial_mat.has(n.asset):
					continue
				var src := (n.mesh as Mesh).surface_get_material(0)
				var mat := ShaderMaterial.new()
				mat.shader = sh
				if src is ShaderMaterial:
					for key in ["albedo_texture", "alpha_scissor_threshold"]:
						mat.set_shader_parameter(key, (src as ShaderMaterial).get_shader_parameter(key))
				_trivial_mat[n.asset] = mat
		for k in sizes:
			var groups := {}
			for n in _nodes:
				var mmi: MultiMeshInstance3D = n.mmi
				var at := String(mmi.name).rfind("_c")
				var parts := String(mmi.name).substr(at + 2).split("_")
				if at < 0 or parts.size() < 2:
					continue
				var gx := floori(int(parts[0]) / float(k))
				var gz := floori(int(parts[1]) / float(k))
				var key := "%s|%d|%d" % [n.asset, gx, gz]
				if not groups.has(key):
					groups[key] = []
				groups[key].append(n)
			var made: Array[MultiMeshInstance3D] = []
			for key in groups:
				var list: Array = groups[key]
				var first: Dictionary = list[0]
				var xfs: Array[Transform3D] = []
				for n: Dictionary in list:
					var mmi: MultiMeshInstance3D = n.mmi
					var mm := mmi.multimesh
					var count := mm.instance_count if int(n.count) < 0 else int(n.count)
					for i in count:
						xfs.append(mmi.transform * mm.get_instance_transform(i))
				var node := MultiMeshInstance3D.new()
				node.multimesh = ScatterGlbUtils.build_multimesh(first.mesh, xfs)
				node.cast_shadow = first.cast
				node.layers = (first.mmi as MultiMeshInstance3D).layers
				node.extra_cull_margin = 1.0
				node.visible = false
				(first.mmi as Node).get_parent().add_child(node)
				made.append(node)
			_merged[k] = made
			_log("merge %d: %d nodes from %d" % [k, made.size(), _nodes.size()])

	## LOD chains (ImporterMesh.generate_lods, the importer's own simplifier) for the meshes of
	## the classes any variant's `lod` names; the orthographic camera picks a LOD per node from its
	## size (Projection.get_lod_multiplier), so this is the zoom-keyed mesh LOD.
	func _prepare_lods(variants: Array) -> void:
		var classes := []
		for v: Dictionary in variants:
			classes.append_array(v.get("lod", []))
		if classes.is_empty():
			return
		var t0 := Time.get_ticks_msec()
		for n in _nodes:
			var orig: Mesh = n.mesh
			if _lod_mesh.has(orig):
				continue
			if not (classes.has("all") or classes.has(n.cls) or classes.has(n.size_class)):
				continue
			var im := ImporterMesh.new()
			for s in orig.get_surface_count():
				im.add_surface(
					orig.surface_get_primitive_type(s), orig.surface_get_arrays(s), [], {},
					orig.surface_get_material(s)
				)
			im.generate_lods(25.0, 60.0, [])
			var sizes: Array[String] = []
			for s in im.get_surface_count():
				var chain: Array[String] = ["%d" % (orig.surface_get_array_index_len(s) / 3)]
				for k in im.get_surface_lod_count(s):
					chain.append("%d" % (im.get_surface_lod_indices(s, k).size() / 3))
				sizes.append(">".join(chain))
			_lod_mesh[orig] = im.get_mesh()
			_log("lod %s (%s): triangles per surface %s" % [n.asset, n.cls, ", ".join(sizes)])
		_log("lod: %d meshes in %d ms" % [_lod_mesh.size(), Time.get_ticks_msec() - t0])

	# ---- perf ----

	func _perf() -> void:
		var vp := gm.world_viewport
		var rid := vp.get_viewport_rid()
		var variants: Array = step.get("variants", [])
		if _uses_wind(variants):
			_prepare_wind()
		_prepare_lods(variants)
		_prepare_merge(variants)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var max_fps := Engine.max_fps
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(rid, true)
		_log(
			(
				(
					"perf %s: world viewport %s scale3d %.2f, window %s, vsync %d, msaa_3d %d,"
					+ " adapter %s, camera size %.2f, %d scatter nodes"
				)
				% [
					step.get("name", ""), str(vp.size), vp.scaling_3d_scale,
					str(DisplayServer.window_get_size()), DisplayServer.window_get_vsync_mode(),
					vp.msaa_3d, RenderingServer.get_video_adapter_name(), gm.camera_node.size,
					_nodes.size()
				]
			)
		)
		var ref: Dictionary = step.get("ref", {"name": "ref"})
		var keys: Array[String] = ["ref_start"]
		for v: Dictionary in variants:
			keys.append(String(v.name))
			var moved := REMAT.census(_nodes, v)
			if moved != "":
				_log("perf: " + moved)
		keys.append("ref_end")
		var data := {}
		for key in keys:
			data[key] = {"gpu": [], "cpu": [], "wall": [], "pass": {}, "info": ""}
		var rounds := int(step.get("rounds", 6))
		var warm := int(step.get("warm", 1))
		var drift: Array[String] = []
		var scale_samples: Array = []
		for r in rounds:
			await _measure(ref, "ref_start", r >= warm, data, rid, scale_samples)
			var order := variants.duplicate()
			for i in r % maxi(order.size(), 1):
				order.push_back(order.pop_front())
			if r % 2 == 1:
				order.reverse()
			for v: Dictionary in order:
				await _measure(v, String(v.name), r >= warm, data, rid, scale_samples)
			await _measure(ref, "ref_end", r >= warm, data, rid, scale_samples)
			if r >= warm:
				var end_gpu := float(data.ref_end.gpu[-1])
				drift.append("%.3f" % (end_gpu / maxf(float(data.ref_start.gpu[-1]), 0.001)))
		_apply({})
		Engine.max_fps = max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		var raw_to_ms := _median(scale_samples)
		var table: Array[String] = []
		var ref_gpu := _median(data.ref_start.gpu + data.ref_end.gpu)
		for key in keys:
			var d: Dictionary = data[key]
			var g := _median(d.gpu)
			var line := (
				"%-16s gpu %.3f [%.3f-%.3f] vs ref %+.3f | cpu %.3f wall %.3f (%d rounds) | %s"
				% [
					key, g, _min(d.gpu), _max(d.gpu), g - ref_gpu, _median(d.cpu), _median(d.wall),
					d.gpu.size(), d.info
				]
			)
			table.append(line)
			_log("perf: " + line)
			var passes: Array[String] = []
			var names: Array = d.pass.keys()
			names.sort_custom(func(x, y): return _median(d.pass[x]) > _median(d.pass[y]))
			for nm in names:
				var ms: float = _median(d.pass[nm]) * raw_to_ms
				if ms >= 0.02:
					passes.append("%s %.3f" % [nm, ms])
			if not passes.is_empty():
				var pline := "    passes " + key + ": " + "; ".join(passes)
				table.append(pline)
				_log("perf: " + pline)
		_log("perf: drift ref_end/ref_start gpu per round %s" % " ".join(drift))
		table.append("drift ref_end/ref_start per round %s" % " ".join(drift))
		var f := FileAccess.open(
			_dir.path_join("%s_table.txt" % String(step.get("name", "perf"))), FileAccess.WRITE
		)
		if f != null:
			for l in table:
				f.store_line(l)

	func _measure(
		v: Dictionary, key: String, keep: bool, data: Dictionary, rid: RID, scale_samples: Array
	) -> void:
		_apply(v)
		await _frames(int(step.get("settle", 30)))
		var rd := RenderingServer.get_rendering_device()
		var begin_name := "vp_begin_%d" % rid.get_id()
		var end_name := "vp_end_%d" % rid.get_id()
		var gpu: Array = []
		var cpu: Array = []
		var wall: Array = []
		var passes := {}
		var last := Time.get_ticks_usec()
		for n in int(step.get("frames", 90)):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			wall.append(float(now - last) / 1000.0)
			last = now
			var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
			gpu.append(g)
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			if rd == null:
				continue
			var count := rd.get_captured_timestamps_count()
			var sums := {}
			var t_begin := -1
			var t_end := -1
			for i in count:
				var nm := rd.get_captured_timestamp_name(i)
				var t := rd.get_captured_timestamp_gpu_time(i)
				if nm == begin_name:
					t_begin = t
				elif nm == end_name:
					t_end = t
				if i + 1 < count:
					sums[nm] = float(sums.get(nm, 0.0)) + float(rd.get_captured_timestamp_gpu_time(i + 1) - t)
			for nm in sums:
				if not passes.has(nm):
					passes[nm] = []
				passes[nm].append(sums[nm])
			if t_begin >= 0 and t_end > t_begin and g > 0.0:
				scale_samples.append(g / float(t_end - t_begin))
		var d: Dictionary = data[key]
		d.info = _info(rid)
		if not keep:
			return
		d.gpu.append(_median(gpu))
		d.cpu.append(_median(cpu))
		d.wall.append(_median(wall))
		for nm in passes:
			if not d.pass.has(nm):
				d.pass[nm] = []
			d.pass[nm].append(_median(passes[nm]))

	func _info(rid: RID) -> String:
		var parts: Array[String] = []
		for t in [
			[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, "visible"],
			[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, "shadow"]
		]:
			var vals: Array = []
			for info in [
				RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
			]:
				vals.append(RenderingServer.viewport_get_render_info(rid, t[0], info))
			parts.append("%s obj %d prims %d calls %d" % [t[1], vals[0], vals[1], vals[2]])
		return ", ".join(parts)

	# ---- shots ----

	## {action: "shots", name, dir, configs: [{name, ..variant keys}], crop: [x, y]}: one sheet,
	## a row per config: the world viewport scaled to 640x360, then a 640x360 crop at 1:1 from
	## `crop` (default the centre). Saved as <dir>/<name>_shots.png.
	func _shots() -> void:
		var configs: Array = step.get("configs", [{"name": "ref"}])
		var variants := configs.duplicate()
		_prepare_lods(variants)
		if step.has("cols"):
			await _shots_cols(configs)
			return
		var w := 640
		var h := 360
		var sheet := Image.create(w * 2, h * configs.size(), false, Image.FORMAT_RGBA8)
		var crop: Array = step.get("crop", [640, 360])
		for row in configs.size():
			_apply(configs[row])
			await _frames(20)
			await RenderingServer.frame_post_draw
			var img := gm.world_viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			var small := img.duplicate() as Image
			small.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(0, row * h))
			sheet.blit_rect(img, Rect2i(int(crop[0]), int(crop[1]), w, h), Vector2i(w, row * h))
		var path := _dir.path_join("%s_shots.png" % String(step.get("name", "shots")))
		sheet.save_png(path)
		_log("shots: rows %s -> %s" % [str(configs.map(func(c): return c.name)), path])

	## The column layout (card foliagelight), `cols`: [w, h, x, y]: one strip, a column per config,
	## each the w x h crop at 1:1 from (x, y) of the world viewport, with a 4 px dark gutter.
	## Saved as <dir>/<name>_cols.png; `stack` joins strips into one sheet.
	func _shots_cols(configs: Array) -> void:
		var c: Array = step.cols
		var w := int(c[0])
		var h := int(c[1])
		var gutter := 4
		var strip := Image.create(
			w * configs.size() + gutter * (configs.size() - 1), h, false, Image.FORMAT_RGBA8
		)
		strip.fill(Color(0.08, 0.08, 0.08))
		if step.has("eye"):
			# `eye`: {at: [x, z], yaw, pitch}: the street view at that ground point, entered with the
			# built materials on so the eye's antialiasing swap sees them.
			_apply({})
			var e: Dictionary = step.eye
			var cc := gm.get_camera_controller()
			cc.set_view_mode(cc.eye)
			cc.eye.frame_ground(Vector2(float(e.at[0]), float(e.at[1])), 0.0)
			cc.finish_zoom()
			await _frames(40)
			cc.set_yaw_now(float(e.get("yaw", 0.0)))
			cc.set_pitch_now(float(e.get("pitch", 0.0)))
			await _frames(30)
		for col in configs.size():
			_apply(configs[col])
			await _frames(int(step.get("settle", 20)))
			await RenderingServer.frame_post_draw
			var img := gm.world_viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(img, Rect2i(int(c[2]), int(c[3]), w, h), Vector2i(col * (w + gutter), 0))
		var path := _dir.path_join("%s_cols.png" % String(step.get("name", "shots")))
		strip.save_png(path)
		_log("shots: cols %s -> %s" % [str(configs.map(func(x): return x.name)), path])

	# ---- overdraw ----

	func _environment() -> Environment:
		var world := gm.world_viewport.find_world_3d()
		if world != null and world.environment != null:
			return world.environment
		for node in gm.find_children("*", "WorldEnvironment", true, false):
			return (node as WorldEnvironment).environment
		return null

	func _overdraw() -> void:
		var vp := gm.world_viewport
		var env := _environment()
		var saved := {}
		var props := [
			"tonemap_mode", "tonemap_exposure", "glow_enabled", "ssao_enabled", "ssil_enabled",
			"fog_enabled", "volumetric_fog_enabled", "adjustment_enabled", "sdfgi_enabled",
			"ssr_enabled"
		]
		if env != null:
			for p in props:
				saved[p] = env.get(p)
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = 1.0
			for p in props.slice(2):
				env.set(p, false)
		# HDR 2D keeps the additive sum past 1.0 (25 layers at 0.04 a layer clip otherwise).
		var hdr := vp.use_hdr_2d
		vp.use_hdr_2d = true
		vp.debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
		await _frames(30)
		var lut := PackedFloat32Array()
		lut.resize(256)
		for i in 256:
			var c := float(i) / 255.0
			lut[i] = c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
		var per_layer := float(step.get("per_layer", 0.04))
		var table: Array[String] = []
		for cfg: Dictionary in step.get("configs", [{"name": "all"}]):
			_apply(cfg)
			await _frames(20)
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var fmt := img.get_format()
			# Layers per pixel, from the red channel (0.04 linear a layer), histogram capped at 64.
			var hist := PackedInt32Array()
			hist.resize(65)
			var n := 0
			var sum := 0.0
			if fmt in [Image.FORMAT_RGBAH, Image.FORMAT_RGBH, Image.FORMAT_RGBAF, Image.FORMAT_RGBF]:
				img.convert(Image.FORMAT_RF)
				var f := img.get_data().to_float32_array()
				for k in f.size():
					var layers := f[k] / per_layer
					hist[mini(roundi(layers), 64)] += 1
					sum += layers
				n = f.size()
			else:
				img.convert(Image.FORMAT_RGBA8)
				var data := img.get_data()
				var i := 0
				while i < data.size():
					var layers := lut[data[i]] / per_layer
					hist[mini(roundi(layers), 64)] += 1
					sum += layers
					n += 1
					i += 4
			var at := {1: 0, 2: 0, 4: 0, 8: 0, 16: 0, 32: 0}
			var parts: Array[String] = []
			for k in 65:
				for t in at:
					if k >= t:
						at[t] += hist[k]
				if hist[k] > 0:
					parts.append("%d:%d" % [k, hist[k]])
			var shares: Array[String] = []
			for t in at:
				shares.append(">=%d %.3f" % [t, float(at[t]) / maxf(1.0, n)])
			var line := (
				"%-14s mean layers %.3f | %s | format %d | layer hist %s"
				% [cfg.name, sum / maxf(1.0, n), " ".join(shares), fmt, " ".join(parts)]
			)
			table.append(line)
			_log("overdraw: " + line)
		vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		vp.use_hdr_2d = hdr
		if env != null:
			for p in saved:
				env.set(p, saved[p])
		probe.call(
			"_write", _dir.path_join("%s_overdraw.txt" % String(step.get("name", "overdraw"))), table
		)
