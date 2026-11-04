extends RefCounted

## Render-job probe for card verify1 (item 5): the eye rim's GPU cost, an in-run A/B in the style of
## eye_perf.gd ("perf"): vsync off, medians, pose order rotated and reversed per round, the orbit home
## pose measured before and after each round as the drift check.
##   {action: "perf", name, dir, poses: [{name, at: [x, z], yaw, pitch}], rounds: 4, frames: 90,
##    settle: 30}
##       For every pose: EyeRim visible versus hidden. Writes <dir>/<name>_report.txt.
##   {action: "await"}   holds the job while the rig runs.

const GROUP := "verify1_rim_perf_rig"


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the rim perf rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) == "await":
		return "idle"
	var rig := Rig.new()
	rig.gm = base.get("_game_map")
	rig.step = step
	base.get_tree().root.add_child(rig)
	return "rim perf %s started" % String(step.get("name", ""))


class Rig:
	extends Node

	var gm: GameMap = null
	var step: Dictionary = {}
	var _cc: CameraController = null
	var _lines: Array[String] = []

	func _ready() -> void:
		add_to_group(GROUP)
		_cc = gm.get_camera_controller()
		_main()

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

	func _rim() -> Node3D:
		return get_tree().root.find_child("EyeRim", true, false) as Node3D

	func _main() -> void:
		var rid := gm.world_viewport.get_viewport_rid()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(rid, true)
		_log(
			(
				"rimperf: world viewport %s, window %s, vsync mode %d, msaa_3d %d"
				% [
					str(gm.world_viewport.size), str(DisplayServer.window_get_size()),
					DisplayServer.window_get_vsync_mode(), gm.world_viewport.msaa_3d
				]
			)
		)
		var poses: Array = step.get("poses", [])
		var data := {"home": _blank(), "home_end": _blank()}
		var keys: Array[String] = []
		for p: Dictionary in poses:
			for v in ["on", "off"]:
				var key := "%s_%s" % [p.name, v]
				keys.append(key)
				data[key] = _blank()
		var rounds := int(step.get("rounds", 4))
		var drift: Array[String] = []
		for r in rounds:
			await _measure("home", data)
			_cc.set_view_mode(_cc.eye)
			gm.eye_view_antialiasing = true
			var rim := _rim()
			if r == 0:
				_log("rimperf: rim node %s, children %d" % [str(rim), rim.get_child_count() if rim != null else -1])
			var order := keys.duplicate()
			for i in r % maxi(order.size(), 1):
				order.push_back(order.pop_front())
			if r % 2 == 1:
				order.reverse()
			for key: String in order:
				var pose := _pose_of(poses, key)
				_cc.eye.frame_ground(Vector2(float(pose.at[0]), float(pose.at[1])), 0.0)
				_cc.set_yaw_now(float(pose.yaw))
				_cc.set_pitch_now(float(pose.get("pitch", 0.0)))
				_cc.finish_zoom()
				if rim != null:
					rim.visible = key.ends_with("_on")
				await _measure(key, data)
			if rim != null:
				rim.visible = true
			_cc.set_view_mode(_cc.orbit_view())
			await _measure("home_end", data)
			var h := _median(data.home.gpu.slice(-(int(step.get("frames", 90)) - 20)))
			var he := _median(data.home_end.gpu.slice(-(int(step.get("frames", 90)) - 20)))
			drift.append("%.3f" % (he / maxf(h, 0.001)))
		var all_keys: Array[String] = ["home", "home_end"]
		all_keys.append_array(keys)
		for key in all_keys:
			var d: Dictionary = data[key]
			_log(
				(
					"rimperf: %-22s gpu %.3f ms  cpu-render %.3f  wall %.3f  prims %d calls %d (%d frames)"
					% [
						key, _median(d.gpu), _median(d.cpu), _median(d.wall), d.prims, d.calls,
						d.gpu.size()
					]
				)
			)
		for p: Dictionary in poses:
			var on := _median(data["%s_on" % p.name].gpu)
			var off := _median(data["%s_off" % p.name].gpu)
			_log(
				"rimperf: %s rim cost gpu %.3f ms (on %.3f, off %.3f, ratio %.3f)"
				% [p.name, on - off, on, off, on / maxf(off, 0.001)]
			)
		_log(
			"rimperf: drift home_end/home gpu per round %s; overall %.3f"
			% [" ".join(drift), _median(data.home_end.gpu) / maxf(_median(data.home.gpu), 0.001)]
		)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		var dir := ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/verify1_perf")))
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("%s_report.txt" % step.get("name", "rimperf")), FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| rimperf %s done" % step.get("name", ""))
		queue_free()

	func _blank() -> Dictionary:
		return {"wall": [], "gpu": [], "cpu": [], "prims": 0, "calls": 0}

	func _pose_of(poses: Array, key: String) -> Dictionary:
		for p: Dictionary in poses:
			if key.begins_with(String(p.name) + "_o"):
				return p
		return poses[0]

	func _measure(key: String, data: Dictionary) -> void:
		var rid := gm.world_viewport.get_viewport_rid()
		await _frames(int(step.get("settle", 30)))
		var last := Time.get_ticks_usec()
		var d: Dictionary = data[key]
		for n in int(step.get("frames", 90)):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			d.wall.append(float(now - last) / 1000.0)
			d.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			d.cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			last = now
		d.prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		d.calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
