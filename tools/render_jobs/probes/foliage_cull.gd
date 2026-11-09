extends RefCounted

## Render-job probe for card cullprobe (perfaudit F-foliage-2, 2026-11-09): what culling scatter
## instances finer than the engine's per-node frustum cull would save. Every scatter node is one
## (asset, 10 m cell) MultiMesh, drawn whole in a pass when its AABB meets that pass's view, so at
## home most drawn instances are off screen. This probe runs foliage_perf.gd's in-run A/B (its
## rig is extended here, every variant key of it still works) with two more keys, both at the
## camera the step starts with:
##   `split` {class: s}  the class's nodes hidden and their visible instances redrawn from s x s
##       sub-cell nodes (10 / s m), so the engine's own node cull removes more: the CPU-side
##       finer-chunking option, with its node count.
##   `cull` {class: mode}  each node's instances reordered so the ones a cull keeps come first and
##       `visible_instance_count` set to their count: what a GPU-driven cull that compacts the
##       survivors into an indirect MultiMesh would draw, at no cull cost. Nothing the vertex stage
##       reads depends on an instance's index (MODEL_MATRIX, INSTANCE_CUSTOM, per-node uniforms),
##       so the reorder alone draws the same pixels. Modes: `view` keeps the instances whose AABB
##       (grown for the wind) meets the camera frustum, one buffer for both passes, so off-screen
##       casters lose their shadows; `shadow` also keeps the casters whose shadow (the AABB swept
##       along the sun down to the ground) meets it, one buffer; `pass` draws `view` with no
##       shadow and adds a shadows-only twin per casting node that draws `shadow`: a cull per pass.
## Actions:
##   perf  foliage_perf's (rounds, warm, frames, settle, ref, variants), plus `eye` {at, yaw,
##       pitch} to measure in the street view, and a census per variant before the run: nodes,
##       nodes meeting the camera frustum and the instances they draw, per class.
##   diff  {configs, crop}  the world viewport per config against the first config (wind frozen by
##       the job): pixels changed by more than 8 and 32 levels, the largest change and where;
##       <dir>/<name>_diff.png, a row per config (the frame scaled to 640x360, then the change
##       mask at the max of each 3x3 block, levels times 8).

const FOLIAGE_PERF := preload("res://tools/render_jobs/probes/foliage_perf.gd")
## An instance's AABB grows by this share of its height (sway_amplitude reaches 0.06 of it,
## scatter_glb_utils.gd) and by at least SWAY_MIN_M, so swaying tips stay inside.
const SWAY_SHARE := 0.1
const SWAY_MIN_M := 0.05
## A caster's shadow is followed this many of its own heights down along the sun (the ground
## may fall away below it).
const SHADOW_DROP := 2.0
## The scatter's cell edge (ScatterChunker; names end _c<x>_<z>).
const CELL_M := 10.0


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(FOLIAGE_PERF.GROUP).is_empty():
		return ""
	return "the foliage cull rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var rig := CullRig.new()
	rig.gm = base.get("_game_map")
	rig.probe = FOLIAGE_PERF
	rig.step = step
	rig.mode = action
	base.get_tree().root.add_child(rig)
	return "cull %s %s started" % [action, String(step.get("name", ""))]


class CullRig:
	extends "res://tools/render_jobs/probes/foliage_perf.gd".Rig

	## MultiMeshInstance3D -> {orig, view, shadow: [buffer, kept], state, twin}.
	var _cull := {}
	## Split size s -> {MultiMeshInstance3D: Array[MultiMeshInstance3D]}.
	var _split := {}
	var _made: Array[Node] = []

	## True when `box` meets the convex volume bounded by `planes` (outward normals, as
	## Camera3D.get_frustum gives them): the engine's own conservative box test.
	static func box_in_planes(box: AABB, planes: Array[Plane]) -> bool:
		var c := box.get_center()
		var e := box.size * 0.5
		for p in planes:
			var r := e.x * absf(p.normal.x) + e.y * absf(p.normal.y) + e.z * absf(p.normal.z)
			if p.distance_to(c) > r:
				return false
		return true

	## `buf` (stride floats per instance) with the instances of `keep` first, then the rest of
	## the first `count`, then those past it (the density cut stays a prefix of what is left).
	static func reordered(
		buf: PackedFloat32Array, stride: int, keep: PackedInt32Array, count: int, full: int
	) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var kept := {}
		for i in keep:
			out.append_array(buf.slice(i * stride, (i + 1) * stride))
			kept[i] = true
		for i in count:
			if not kept.has(i):
				out.append_array(buf.slice(i * stride, (i + 1) * stride))
		if full > count:
			out.append_array(buf.slice(count * stride, full * stride))
		return out

	## The key's value for node `n`: by class, then size class, then "all".
	static func pick(n: Dictionary, keyed: Dictionary, none: Variant) -> Variant:
		return keyed.get(n.cls, keyed.get(n.size_class, keyed.get("all", none)))

	func _main() -> void:
		if step.has("eye"):
			await _enter_eye(step.eye)
		var variants: Array = step.get("variants", []) + step.get("configs", [])
		_prepare_split(variants)
		_prepare_cull(variants)
		_census(variants)
		if mode != "diff":
			await super()
			return
		await _diff()
		_restore()
		var report := _dir.path_join("%s_diff_report.txt" % step.get("name", ""))
		var f := FileAccess.open(report, FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| foliage_cull diff %s done" % step.get("name", ""))
		queue_free()

	func _enter_eye(e: Dictionary) -> void:
		var cc := gm.get_camera_controller()
		cc.set_view_mode(cc.eye)
		cc.eye.frame_ground(Vector2(float(e.at[0]), float(e.at[1])), 0.0)
		cc.finish_zoom()
		await _frames(40)
		cc.set_yaw_now(float(e.get("yaw", 0.0)))
		cc.set_pitch_now(float(e.get("pitch", 0.0)))
		await _frames(30)

	func _camera() -> Camera3D:
		return gm.world_viewport.get_camera_3d()

	func _planes() -> Array[Plane]:
		var planes: Array[Plane] = []
		planes.assign(_camera().get_frustum())
		return planes

	## The horizontal run of a shadow per metre of drop, from the first shadowed sun.
	func _sweep() -> Vector3:
		for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			var sun := node as DirectionalLight3D
			if sun.is_visible_in_tree() and sun.shadow_enabled:
				var d := -sun.global_transform.basis.z
				_log("cull: sun %s direction %s" % [sun.name, str(d.snapped(Vector3.ONE * 0.01))])
				return d / maxf(-d.y, 0.05)
		_log("cull: no shadowed sun found")
		return Vector3.ZERO

	func _node_box(mmi: MultiMeshInstance3D) -> AABB:
		return (mmi.global_transform * mmi.multimesh.get_aabb()).grow(mmi.extra_cull_margin)

	# ---- prepare ----

	func _prepare_cull(variants: Array) -> void:
		var want := {}
		for v: Dictionary in variants:
			for cls in v.get("cull", {}):
				want[cls] = true
		if want.is_empty():
			return
		var t0 := Time.get_ticks_msec()
		var planes := _planes()
		var sweep := _sweep()
		var cam := _camera()
		_log(
			(
				"cull: camera %s size %.2f fov %.1f at %s; frustum self-check %s"
				% [
					"ortho" if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else "persp", cam.size,
					cam.fov, str(cam.global_position.snapped(Vector3.ONE * 0.1)),
					str(
						box_in_planes(
							AABB(cam.global_position - cam.global_transform.basis.z * 10.0, Vector3.ONE * 0.01),
							planes
						)
					)
				]
			)
		)
		for n in _nodes:
			if not (want.has("all") or want.has(n.cls) or want.has(n.size_class)):
				continue
			var mmi: MultiMeshInstance3D = n.mmi
			var mm := mmi.multimesh
			var full := mm.instance_count
			var count: int = full if int(n.count) < 0 else mini(int(n.count), full)
			var buf := mm.buffer
			var stride := buf.size() / maxi(full, 1)
			var maabb := (n.mesh as Mesh).get_aabb()
			var casts: bool = n.cast != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var view_keep := PackedInt32Array()
			var shadow_keep := PackedInt32Array()
			var xf := mmi.global_transform
			for i in count:
				var box := (xf * mm.get_instance_transform(i)) * maabb
				box = box.grow(maxf(SWAY_MIN_M, box.size.y * SWAY_SHARE))
				if box_in_planes(box, planes):
					view_keep.append(i)
					shadow_keep.append(i)
				elif casts:
					var off := sweep * box.size.y * SHADOW_DROP
					if box_in_planes(box.merge(AABB(box.position + off, box.size)), planes):
						shadow_keep.append(i)
			# The engine keeps culling against the whole chunk (custom_aabb), as it would with
			# an indirect MultiMesh whose count only the GPU knows; else a node left with no
			# visible instance gets an empty AABB at the origin and draws wherever that is seen.
			var rec := {
				"orig": buf, "state": "orig", "twin": null, "count": count, "aabb": mm.get_aabb()
			}
			rec["view"] = [reordered(buf, stride, view_keep, count, full), view_keep.size()]
			if casts:
				rec["shadow"] = [reordered(buf, stride, shadow_keep, count, full), shadow_keep.size()]
				rec["twin"] = _twin(mmi, rec.shadow)
			else:
				rec["shadow"] = rec.view
			_cull[mmi] = rec
		_log("cull: %d nodes reordered in %d ms" % [_cull.size(), Time.get_ticks_msec() - t0])

	## A shadows-only copy of `mmi` drawing `shadow` ([buffer, kept]), hidden until `pass`.
	func _twin(mmi: MultiMeshInstance3D, shadow: Array) -> MultiMeshInstance3D:
		var src := mmi.multimesh
		var mm := MultiMesh.new()
		mm.transform_format = src.transform_format
		mm.use_colors = src.use_colors
		mm.use_custom_data = src.use_custom_data
		mm.mesh = src.mesh
		mm.instance_count = src.instance_count
		mm.buffer = shadow[0]
		mm.visible_instance_count = int(shadow[1])
		mm.custom_aabb = src.get_aabb()
		var twin := MultiMeshInstance3D.new()
		twin.multimesh = mm
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		twin.layers = mmi.layers
		twin.extra_cull_margin = mmi.extra_cull_margin
		twin.transform = mmi.transform
		twin.visible = false
		mmi.get_parent().add_child(twin)
		_made.append(twin)
		return twin

	func _prepare_split(variants: Array) -> void:
		var want := {}
		for v: Dictionary in variants:
			var split: Dictionary = v.get("split", {})
			for cls in split:
				var s := int(split[cls])
				if not want.has(s):
					want[s] = {}
				want[s][cls] = true
		for s: int in want:
			var t0 := Time.get_ticks_msec()
			var classes: Dictionary = want[s]
			var by_node := {}
			var made := 0
			var sub := CELL_M / float(s)
			for n in _nodes:
				if not (classes.has("all") or classes.has(n.cls) or classes.has(n.size_class)):
					continue
				var mmi: MultiMeshInstance3D = n.mmi
				var mm := mmi.multimesh
				var full := mm.instance_count
				var count: int = full if int(n.count) < 0 else mini(int(n.count), full)
				var buf := mm.buffer
				var stride := buf.size() / maxi(full, 1)
				var groups := {}
				for i in count:
					var p := mmi.global_transform * mm.get_instance_transform(i).origin
					var key := Vector2i(floori(p.x / sub), floori(p.z / sub))
					if not groups.has(key):
						groups[key] = []
					(groups[key] as Array).append(i)
				var parts: Array[MultiMeshInstance3D] = []
				for key in groups:
					# Packed arrays are values in GDScript: built here, not appended in the dictionary.
					var part_buf := PackedFloat32Array()
					for i: int in groups[key]:
						part_buf.append_array(buf.slice(i * stride, (i + 1) * stride))
					var pm := MultiMesh.new()
					pm.transform_format = mm.transform_format
					pm.use_colors = mm.use_colors
					pm.use_custom_data = mm.use_custom_data
					pm.mesh = mm.mesh
					pm.instance_count = part_buf.size() / stride
					pm.buffer = part_buf
					var part := MultiMeshInstance3D.new()
					part.multimesh = pm
					part.cast_shadow = mmi.cast_shadow
					part.layers = mmi.layers
					part.extra_cull_margin = mmi.extra_cull_margin
					part.transform = mmi.transform
					part.visible = false
					mmi.get_parent().add_child(part)
					_made.append(part)
					parts.append(part)
				by_node[mmi] = parts
				made += parts.size()
			_split[s] = by_node
			_log(
				(
					"split %d (%.2f m cells): %d nodes from %d in %d ms"
					% [s, sub, made, by_node.size(), Time.get_ticks_msec() - t0]
				)
			)

	## Per variant, at the current camera: nodes in the scene, nodes meeting the frustum and the
	## instances those draw, per class (the camera pass; the shadow pass is in perf's info).
	func _census(variants: Array) -> void:
		var planes := _planes()
		var all := [{"name": "ref"}] + variants
		for v: Dictionary in all:
			var cull: Dictionary = v.get("cull", {})
			var split: Dictionary = v.get("split", {})
			var hide: Array = v.get("hide", [])
			var per := {}
			var nodes := 0
			for n in _nodes:
				var mmi: MultiMeshInstance3D = n.mmi
				if bool(v.get("nofol", false)) or hide.has(n.cls) or hide.has(n.size_class):
					continue
				var rec: Dictionary = per.get(n.cls, {"nodes": 0, "seen": 0, "inst": 0})
				per[n.cls] = rec
				var s := int(pick(n, split, 0))
				var count: int = (
					mmi.multimesh.instance_count if int(n.count) < 0 else int(n.count)
				)
				if s > 0 and _split.has(s) and (_split[s] as Dictionary).has(mmi):
					for part: MultiMeshInstance3D in _split[s][mmi]:
						rec.nodes += 1
						if box_in_planes(_node_box(part), planes):
							rec.seen += 1
							rec.inst += part.multimesh.instance_count
					continue
				rec.nodes += 1
				var mode_c := String(pick(n, cull, ""))
				var c: Dictionary = _cull.get(mmi, {})
				if mode_c == "pass" and c.get("twin") != null:
					rec.nodes += 1
				if not box_in_planes(_node_box(mmi), planes):
					continue
				rec.seen += 1
				if mode_c != "" and not c.is_empty():
					rec.inst += int(c["shadow" if mode_c == "shadow" else "view"][1])
				else:
					rec.inst += count
			var parts: Array[String] = []
			var tot := {"nodes": 0, "seen": 0, "inst": 0}
			var classes := per.keys()
			classes.sort()
			for cls in classes:
				var r: Dictionary = per[cls]
				parts.append("%s %d/%d/%d" % [cls, r.nodes, r.seen, r.inst])
				for k in tot:
					tot[k] += int(r[k])
			nodes = tot.nodes
			_log(
				(
					"census %-14s nodes %5d seen %4d drawn instances %6d | per class nodes/seen/inst %s"
					% [v.get("name", "?"), nodes, tot.seen, tot.inst, ", ".join(parts)]
				)
			)

	# ---- variants ----

	func _apply(v: Dictionary) -> void:
		super(v)
		if _cull.is_empty() and _split.is_empty():
			return
		var cull: Dictionary = v.get("cull", {})
		var split: Dictionary = v.get("split", {})
		for n in _nodes:
			var mmi: MultiMeshInstance3D = n.mmi
			if not is_instance_valid(mmi):
				continue
			var shown := mmi.visible
			var c: Dictionary = _cull.get(mmi, {})
			if not c.is_empty():
				var mode_c := String(pick(n, cull, ""))
				var state := "orig"
				if mode_c == "view" or mode_c == "pass":
					state = "view"
				elif mode_c == "shadow":
					state = "shadow"
				var mm := mmi.multimesh
				if c.state != state:
					mm.buffer = c.orig if state == "orig" else c[state][0]
					mm.custom_aabb = AABB() if state == "orig" else c.aabb
					c.state = state
				if state != "orig":
					mm.visible_instance_count = int(c[state][1])
				var twin: MultiMeshInstance3D = c.twin
				if twin != null:
					twin.visible = shown and mode_c == "pass"
					if mode_c == "pass":
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var s := int(pick(n, split, 0))
			for size: int in _split:
				var parts: Array = (_split[size] as Dictionary).get(mmi, [])
				for part: MultiMeshInstance3D in parts:
					part.visible = shown and size == s
				if size == s and not parts.is_empty():
					mmi.visible = false

	func _restore() -> void:
		_apply({})
		super()
		for node in _made:
			if is_instance_valid(node):
				node.queue_free()
		_made.clear()
		_cull.clear()
		_split.clear()

	# ---- diff ----

	func _diff() -> void:
		var configs: Array = step.get("configs", [{"name": "ref"}])
		var w := 640
		var h := 360
		var sheet := Image.create(w * 2, h * configs.size(), false, Image.FORMAT_RGBA8)
		var ref: Image = null
		# Water animates on the shader clock, which the wind freeze does not stop: hidden, so
		# two frames of one config match.
		var hidden: Array[GeometryInstance3D] = []
		for node in gm.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			if gi.visible and _is_water(gi):
				gi.visible = false
				hidden.append(gi)
		_log("diff: %d water meshes hidden" % hidden.size())
		for row in configs.size():
			var cfg: Dictionary = configs[row]
			_apply(cfg)
			await _frames(int(step.get("settle", 30)))
			await RenderingServer.frame_post_draw
			var img := gm.world_viewport.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			var small := img.duplicate() as Image
			small.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(0, row * h))
			if ref == null:
				ref = img
				_log("diff %s: reference %s" % [cfg.get("name", "?"), str(img.get_size())])
				continue
			var r := _compare(ref, img, w, h)
			sheet.blit_rect(r.mask, Rect2i(0, 0, w, h), Vector2i(w, row * h))
			_log(
				(
					"diff %-14s changed >8: %d (%.3f%%) >32: %d | max %d | box of >32 %s | edge band share %.2f"
					% [
						cfg.get("name", "?"), r.n8, 100.0 * r.n8 / float(ref.get_width() * ref.get_height()),
						r.n32, r.max, str(r.box), r.edge
					]
				)
			)
		for gi in hidden:
			if is_instance_valid(gi):
				gi.visible = true
		var path := _dir.path_join("%s_diff.png" % String(step.get("name", "diff")))
		sheet.save_png(path)
		_log("diff: sheet -> %s" % path)

	## Whether `gi` draws with a water or falls shader (override or any surface material).
	func _is_water(gi: GeometryInstance3D) -> bool:
		var mats: Array[Material] = [gi.material_override]
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var mesh := (gi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				mats.append((gi as MeshInstance3D).get_active_material(s))
		for m in mats:
			var sm := m as ShaderMaterial
			if sm != null and sm.shader != null:
				var p := sm.shader.resource_path.get_file()
				if p.contains("water") or p.contains("falls"):
					return true
		return false

	## Changed pixels between two same-size RGBA8 frames, and a w x h mask of the largest change
	## in each block (levels times 8, white on black). `edge` is the share of >32 changes within
	## the outer eighth of the frame.
	func _compare(a: Image, b: Image, w: int, h: int) -> Dictionary:
		var da := a.get_data()
		var db := b.get_data()
		var iw := a.get_width()
		var ih := a.get_height()
		var bx := maxi(1, iw / w)
		var by := maxi(1, ih / h)
		var mask := PackedByteArray()
		mask.resize(w * h)
		var n8 := 0
		var n32 := 0
		var edge := 0
		var mx := 0
		var lo := Vector2i(iw, ih)
		var hi := Vector2i(-1, -1)
		var mx_x := iw / 8
		var mx_y := ih / 8
		for y in ih:
			var row := y * iw * 4
			var my := mini(y / by, h - 1) * w
			for x in iw:
				var i := row + x * 4
				var d := maxi(
					maxi(absi(da[i] - db[i]), absi(da[i + 1] - db[i + 1])), absi(da[i + 2] - db[i + 2])
				)
				if d <= 8:
					continue
				n8 += 1
				mx = maxi(mx, d)
				var m := my + mini(x / bx, w - 1)
				mask[m] = maxi(mask[m], mini(255, d * 8))
				if d > 32:
					n32 += 1
					lo = lo.min(Vector2i(x, y))
					hi = hi.max(Vector2i(x, y))
					if x < mx_x or x >= iw - mx_x or y < mx_y or y >= ih - mx_y:
						edge += 1
		var mimg := Image.create_from_data(w, h, false, Image.FORMAT_L8, mask)
		mimg.convert(Image.FORMAT_RGBA8)
		return {
			"n8": n8, "n32": n32, "max": mx, "mask": mimg,
			"box": Rect2i(lo, hi - lo) if hi.x >= 0 else Rect2i(),
			"edge": float(edge) / maxf(1.0, float(n32))
		}
