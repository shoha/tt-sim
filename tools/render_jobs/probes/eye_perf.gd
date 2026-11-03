extends RefCounted

## Render-job probe for the eye view's frame cost and its near shadow sharpness (card eyeperf,
## SR8 + SR9). It drives the real EyeView through the camera controller, so the painted sky and
## edge fog, the near-eye canopy fade, MSAA 4x and the shadow fit are all live. One `call` step per
## action; every action writes into `dir`.
##   {action: "perf", name, dir, at: [x, z], yaws: [..], pitches: [..], rounds: 4, frames: 90,
##    settle: 30, variants: [{name, sky?, fade?, aa?, shadow?}]}
##       In-run A/B under the pinned procedure (vsync off, window and world viewport as the run
##       gives them, medians, order rotated each round): the home ortho pose first, then every
##       eye pose x variant (the eye stays on between them), then the home pose again for the
##       drift check. A variant may switch the painted sky (EyeSky.enabled), the near-eye fade
##       (CanopyFade.eye_fade_enabled), MSAA 4x at the eye (GameMap.eye_view_antialiasing, off =
##       the shipped setting) and the shadow distance (`shadow`: EyeShadow.forced_distance, 100 =
##       what the eye got before the shadow fit; absent = the fit).
##       Pitch is positive looking DOWN in the game's own convention (CameraController.set_pitch_now); a negative pitch looks up.
##       Writes <dir>/<name>_report.txt and <name>_table.txt.
##   {action: "trees", name, dir, at: [x, z], dist: 5.0, pitch: 14.0, caps: [100, 120, 160, 200]}
##       The eye stands `dist` m from the tallest tree nearest `at`, on the side away from the sun,
##       and looks toward the sun, so the tree's shadow falls toward the eye. For every cap a full
##       frame <dir>/<name>_cap<N>.png (the raw 3D viewport, native size) and the shadow picture
##       S = lit - shadowed: the 99th percentile of its gradient in the lower half of the frame
##       (the ground within a few metres: a softer shadow edge lowers it) is logged.
##   {action: "await"}   holds the job while a rig runs.

const GROUP := "eye_perf_rig"


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the eye perf rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var rig := PerfRig.new()
	rig.gm = base.get("_game_map")
	rig.lpc = base.get("_level_play_controller")
	rig.step = step
	rig.mode = action
	base.get_tree().root.add_child(rig)
	return "%s %s started" % [action, String(step.get("name", ""))]


class PerfRig:
	extends Node

	var gm: GameMap = null
	var lpc: Node = null
	var step: Dictionary = {}
	var mode := "perf"
	var _cc: CameraController = null
	var _dir := ""
	var _lines: Array[String] = []

	func _ready() -> void:
		add_to_group(GROUP)
		_dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/eye_perf")))
		DirAccess.make_dir_recursive_absolute(_dir)
		_cc = gm.get_camera_controller()
		_main()

	func _main() -> void:
		match mode:
			"perf":
				await _perf()
			"trees":
				await _trees()
			_:
				_log("unknown action %s" % mode)
		_defaults()
		if _cc.view_mode() == _cc.eye:
			_cc.set_view_mode(_cc.orbit_view())
		var tag := String(step.get("name", mode))
		var f := FileAccess.open(_dir.path_join("%s_report.txt" % tag), FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| eye_perf %s done, %d lines, %s" % [tag, _lines.size(), _dir])
		queue_free()

	func _log(text: String) -> void:
		_lines.append(text)
		print("RJ| " + text)

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _median(a: Array) -> float:
		var b := a.duplicate()
		b.sort()
		return float(b[b.size() / 2]) if not b.is_empty() else 0.0

	## Every toggle back to the shipped state.
	func _defaults() -> void:
		EyeSky.enabled = true
		CanopyFade.eye_fade_enabled = true
		EyeShadow.forced_distance = 0.0
		gm.eye_view_antialiasing = _cc.view_mode() == _cc.eye

	func _apply(v: Dictionary) -> void:
		EyeSky.enabled = bool(v.get("sky", true))
		if not EyeSky.enabled:
			_cc.eye.sky.leave()
		CanopyFade.eye_fade_enabled = bool(v.get("fade", true))
		EyeShadow.forced_distance = float(v.get("shadow", 0.0))
		gm.eye_view_antialiasing = bool(v.get("aa", true))

	# ---- perf ----

	func _perf() -> void:
		var at := Vector2(float(step.at[0]), float(step.at[1]))
		var rid := gm.world_viewport.get_viewport_rid()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(rid, true)
		var vp := gm.world_viewport
		_log(
			(
				"perf: world viewport %s, window %s, vsync mode %d, msaa_3d %d"
				% [
					str(vp.size), str(DisplayServer.window_get_size()),
					DisplayServer.window_get_vsync_mode(), vp.msaa_3d
				]
			)
		)
		var variants: Array = step.get("variants", [{"name": "ship"}])
		var configs: Array[Dictionary] = []
		for pitch in step.get("pitches", [0.0]):
			for yaw in step.get("yaws", [45.0]):
				for v: Dictionary in variants:
					var key := "eye_p%d_y%d" % [int(pitch), int(yaw)]
					if variants.size() > 1:
						key += "_" + String(v.name)
					configs.append({"key": key, "pitch": float(pitch), "yaw": float(yaw), "v": v})
		var data := {}
		var keys: Array[String] = ["home", "home_end"]
		for c in configs:
			keys.append(String(c.key))
		for key in keys:
			data[key] = {"wall": [], "gpu": [], "cpu": [], "prims": 0, "calls": 0}
		var rounds := int(step.get("rounds", 4))
		var drift: Array[String] = []
		for r in rounds:
			await _measure_home("home", data)
			_cc.set_view_mode(_cc.eye)
			_cc.eye.frame_ground(at, 0.0)
			var order := configs.duplicate()
			for i in r % maxi(configs.size(), 1):
				order.push_back(order.pop_front())
			if r % 2 == 1:
				order.reverse()
			for c: Dictionary in order:
				_apply(c.v)
				_cc.set_yaw_now(float(c.yaw))
				_cc.set_pitch_now(float(c.pitch))
				_cc.finish_zoom()
				await _measure(String(c.key), data)
			_defaults()
			_cc.set_view_mode(_cc.orbit_view())
			await _measure_home("home_end", data)
			var h := _median(data.home.gpu.slice(-int(step.get("frames", 90)) + 20))
			var he := _median(data.home_end.gpu.slice(-int(step.get("frames", 90)) + 20))
			drift.append("%.3f" % (he / maxf(h, 0.001)))
		var table: Array[String] = []
		var home_gpu := _median(data.home.gpu)
		var home_wall := _median(data.home.wall)
		for key in keys:
			var d: Dictionary = data[key]
			var line := (
				(
					"%-26s wall %.3f gpu %.3f cpu-render %.3f prims %d calls %d"
					+ " | vs home wall %.2f gpu %.2f (%d frames)"
				)
				% [
					key, _median(d.wall), _median(d.gpu), _median(d.cpu), d.prims, d.calls,
					_median(d.wall) / maxf(home_wall, 0.001), _median(d.gpu) / maxf(home_gpu, 0.001),
					d.wall.size()
				]
			)
			table.append(line)
			_log("perf: " + line)
		_log(
			(
				"perf: drift home_end/home gpu ratio overall %.3f wall ratio %.3f; per round gpu %s"
				% [
					_median(data.home_end.gpu) / maxf(home_gpu, 0.001),
					_median(data.home_end.wall) / maxf(home_wall, 0.001), " ".join(drift)
				]
			)
		)
		var table_name := "%s_table.txt" % step.get("name", "perf")
		var f := FileAccess.open(_dir.path_join(table_name), FileAccess.WRITE)
		if f != null:
			for l in table:
				f.store_line(l)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	func _measure_home(key: String, data: Dictionary) -> void:
		await _measure(key, data)

	## Settle, then `frames` frames of wall time and the world viewport's GPU and CPU render time.
	func _measure(key: String, data: Dictionary) -> void:
		var rid := gm.world_viewport.get_viewport_rid()
		var frames := int(step.get("frames", 90))
		var settle := int(step.get("settle", 30))
		await _frames(settle)
		var last := Time.get_ticks_usec()
		var d: Dictionary = data[key]
		for n in frames:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			d.wall.append(float(now - last) / 1000.0)
			d.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			d.cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			last = now
		d.prims = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
		)
		d.calls = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
		)

	# ---- trees ----

	## The tallest scatter mesh (height >= 5 m) instance nearest `at`: its world position, or INF.
	func _find_tree(at: Vector2) -> Vector3:
		var best := Vector3.INF
		var best_d := INF
		for node in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := node as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null or mm.mesh == null:
				continue
			var aabb := mm.mesh.get_aabb()
			for i in mm.instance_count:
				var xf := mmi.global_transform * mm.get_instance_transform(i)
				if aabb.size.y * xf.basis.get_scale().y < 5.0:
					continue
				var d := Vector2(xf.origin.x, xf.origin.z).distance_to(at)
				if d < best_d:
					best_d = d
					best = xf.origin
		return best

	func _sun() -> DirectionalLight3D:
		for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (node as DirectionalLight3D).shadow_enabled:
				return node
		return null

	func _grab() -> Image:
		await RenderingServer.frame_post_draw
		return gm.world_viewport.get_texture().get_image()

	func _luma(img: Image) -> PackedByteArray:
		var l := img.duplicate() as Image
		l.convert(Image.FORMAT_L8)
		return l.get_data()

	func _trees() -> void:
		var sun := _sun()
		if sun == null:
			_log("trees: no shadow-casting sun")
			return
		var at := Vector2(float(step.at[0]), float(step.at[1]))
		var tree := _find_tree(at)
		if tree == Vector3.INF:
			_log("trees: no tree taller than 5 m")
			return
		var to_sun := Vector2(sun.global_basis.z.x, sun.global_basis.z.z).normalized()
		var dist := float(step.get("dist", 5.0))
		var foot := Vector2(tree.x, tree.z) - to_sun * dist
		_cc.set_view_mode(_cc.eye)
		_cc.eye.frame_ground(foot, 0.0)
		_cc.set_yaw_now(rad_to_deg(atan2(-to_sun.x, -to_sun.y)))
		_cc.set_pitch_now(float(step.get("pitch", 14.0)))
		_cc.finish_zoom()
		_log(
			(
				"trees: tree at %s, sun toward %s, eye foot %s (%.1f m from the trunk), yaw %.1f pitch %.1f"
				% [
					str(tree), str(to_sun), str(foot), dist, _cc.current_yaw(), _cc.current_pitch()
				]
			)
		)
		for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			var light := node as DirectionalLight3D
			_log(
				"trees: light %s shadow %s maxdist %.0f"
				% [light.get_path(), str(light.shadow_enabled), light.directional_shadow_max_distance]
			)
		_log("trees: camera projection %d (0 = perspective)" % gm.camera_node.projection)
		if lpc != null:
			var fit: MapViewFit = lpc.get("_view_fit")
			var bounds: AABB = fit.shadow_bounds if fit != null else AABB()
			_log(
				"trees: shadow_bounds %s, eye fit now %.0f"
				% [str(bounds), EyeShadow.distance(gm.camera_node.global_position, bounds, 1.0)]
			)
		for cap in step.get("caps", [100, 200]):
			EyeShadow.forced_distance = float(cap)
			sun.shadow_enabled = true
			await _frames(int(step.get("settle", 40)))
			var lit := await _grab()
			lit.save_png(_dir.path_join("%s_cap%d.png" % [step.get("name", "trees"), int(cap)]))
			var maxd := sun.directional_shadow_max_distance
			sun.shadow_enabled = false
			await _frames(6)
			var off := await _grab()
			sun.shadow_enabled = true
			_log(
				"trees: cap %d -> sun max distance %.0f; %s"
				% [int(cap), maxd, _sharpness(_luma(off), _luma(lit), lit.get_width(), lit.get_height())]
			)

	## S = max(0, lit-off minus shadowed): the 99th percentile of S's gradient and the shadowed
	## share of the lower half of the frame.
	func _sharpness(off: PackedByteArray, on: PackedByteArray, w: int, h: int) -> String:
		var s := PackedByteArray()
		s.resize(w * h)
		for k in w * h:
			s[k] = maxi(0, int(off[k]) - int(on[k]))
		var grads: Array = []
		var lit := 0
		var y0 := h / 2
		for y in range(y0, h - 1, 2):
			for x in range(0, w - 1, 2):
				var v := int(s[y * w + x])
				var g := absi(v - int(s[y * w + x + 1])) + absi(v - int(s[(y + 1) * w + x]))
				if g > 0:
					grads.append(g)
				if v > 10:
					lit += 1
		grads.sort()
		var p99 := float(grads[int(grads.size() * 0.99)]) if not grads.is_empty() else 0.0
		var p999 := float(grads[int(grads.size() * 0.999)]) if not grads.is_empty() else 0.0
		return (
			"lower-half shadow share %.1f%%, S gradient p99 %.1f p99.9 %.1f (nonzero samples %d)"
			% [
				100.0 * float(lit) / float((h - y0) * w / 4), p99, p999, grads.size()
			]
		)
