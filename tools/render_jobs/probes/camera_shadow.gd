extends RefCounted

## Render-job probe for the shadow-pop diagnosis (docs/plans/handoffs/camerarig-3.md).
## One action, `sweep`: for each pitch in `pitches` the camera is put there at once, the frame is
## grabbed with the sun's shadows ON and again with them OFF; the shadow-only picture is
## S = max(0, luma_off - luma_on). Consecutive S pictures are compared (mean darkness, mean
## absolute change, the largest 30 px block change and where), so a shadow that appears or
## vanishes between two close pitches shows as a spike. Everything lands in <dir>:
##   report.txt   one line per pitch, then the spike list
##   s_<pitch>.png   S x4 at 480 px wide;  on_<pitch>.png   the lit frame at 480 px wide
## Step keys: name, dir, pitches (Array of float), settle (frames, default 4), tweak (Dictionary):
##   maxdist (float)     hold directional_shadow_max_distance (after MapViewFit.follow ran)
##   hold_home_dist      hold the value seen at the first pitch
##   mode ("ortho"|"p2"|"p4")  directional_shadow_mode
##   blend (bool)        directional_shadow_blend_splits
##   nofade              fade start 1.0
##   splits ([a, b, c])  directional_shadow_split_1..3
##   no_push             set the foliage shadow push to 0 for the run (global shader parameter)
##   no_wind             nothing (wind is frozen by the job)
##   hide_scatter        hide every MultiMeshInstance3D (control: shadows of the rest only)
##   cull_off            every GeometryInstance3D gets ignore_occlusion_culling and a huge extra_cull_margin
##   unlit_probe         nothing; reserved

const BLOCK := 30
const W := 480
const H := 270


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	if String(step.get("action", "")) == "blend":
		for node in base.get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			(node as DirectionalLight3D).directional_shadow_blend_splits = bool(step.get("on", true))
		return "blend splits %s" % str(step.get("on", true))
	if String(step.get("action", "")) == "perf":
		var perf := PerfRig.new()
		perf.gm = gm
		perf.cc = gm.get_camera_controller()
		perf.pitch = float(step.get("pitch", 21.6))
		perf.frames = int(step.get("frames", 90))
		perf.rounds = int(step.get("rounds", 4))
		perf.process_priority = 1000
		for node in base.get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (node as DirectionalLight3D).shadow_enabled:
				perf.sun = node
				break
		base.get_tree().root.add_child(perf)
		return "perf pitch %.1f" % perf.pitch
	var rig := SweepRig.new()
	rig.gm = gm
	rig.cc = gm.get_camera_controller()
	rig.sweep_name = String(step.get("name", "sweep"))
	rig.dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/camera_shadow")))
	rig.pitches = step.get("pitches", [21.6, 90.0])
	rig.settle = int(step.get("settle", 4))
	rig.tweak = step.get("tweak", {})
	rig.zooms = step.get("zooms", [])
	rig.pans = step.get("pans", [])
	rig.process_priority = 1000
	base.get_tree().root.add_child(rig)
	return "sweep %s %d pitches" % [rig.sweep_name, rig.pitches.size()]


class SweepRig:
	extends Node

	var gm: GameMap = null
	var cc: CameraController = null
	var sweep_name := "sweep"
	var dir := ""
	var pitches: Array = []
	var settle := 4
	var tweak: Dictionary = {}
	var zooms: Array = []
	var pans: Array = []
	var _holder0 := Vector3.INF
	var _orig_mode := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var _orig_blend := false
	var _orig_fade := 0.8
	var _orig_pancake := 20.0
	var _orig_splits: Array = [0.1, 0.2, 0.5]
	var _sun: DirectionalLight3D = null
	var _i := 0
	var _phase := 0  # 0 settle with shadows, 1 grab on, 2 settle off, 3 grab off
	var _wait := 0
	var _on: Image = null
	var _prev_s := PackedByteArray()
	var _prev_mean := 0.0
	var _lines: Array[String] = []
	var _spikes: Array[String] = []
	var _home_dist := -1.0
	var _started := false
	var _done := false

	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute(dir)
		for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			var light := node as DirectionalLight3D
			if light != null and light.shadow_enabled:
				_sun = light
				_orig_mode = light.directional_shadow_mode
				_orig_blend = light.directional_shadow_blend_splits
				_orig_fade = light.directional_shadow_fade_start
				_orig_pancake = light.directional_shadow_pancake_size
				_orig_splits = [
					light.directional_shadow_split_1,
					light.directional_shadow_split_2,
					light.directional_shadow_split_3
				]
				break
		RenderingServer.frame_post_draw.connect(_grab)

	func _apply_tweak() -> void:
		if _sun == null:
			return
		if _home_dist < 0.0:
			_home_dist = _sun.directional_shadow_max_distance
		if tweak.has("maxdist"):
			_sun.directional_shadow_max_distance = float(tweak.maxdist)
		if bool(tweak.get("hold_home_dist", false)):
			_sun.directional_shadow_max_distance = _home_dist
		match String(tweak.get("mode", "")):
			"ortho":
				_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			"p2":
				_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			"p4":
				_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		if tweak.has("pancake"):
			_sun.directional_shadow_pancake_size = float(tweak.pancake)
		if tweak.has("blend"):
			_sun.directional_shadow_blend_splits = bool(tweak.blend)
		if bool(tweak.get("nofade", false)):
			_sun.directional_shadow_fade_start = 1.0
		if tweak.has("splits"):
			var s: Array = tweak.splits
			_sun.directional_shadow_split_1 = float(s[0])
			_sun.directional_shadow_split_2 = float(s[1])
			_sun.directional_shadow_split_3 = float(s[2])

	func _once() -> void:
		if bool(tweak.get("no_push", false)):
			for node in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
				var mesh := (node as MultiMeshInstance3D).multimesh.mesh
				if mesh == null:
					continue
				for i in mesh.get_surface_count():
					var mat := mesh.surface_get_material(i) as ShaderMaterial
					if mat != null:
						mat.set_shader_parameter("shadow_caster_push", 0.0)
		if bool(tweak.get("hide_scatter", false)):
			for node in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
				(node as MultiMeshInstance3D).visible = false
		if tweak.has("margin"):
			var kind := "MultiMeshInstance3D" if bool(tweak.get("mm_only", false)) else "GeometryInstance3D"
			for node in get_tree().root.find_children("*", kind, true, false):
				(node as GeometryInstance3D).extra_cull_margin = float(tweak.margin)
		if bool(tweak.get("occl_off", false)):
			for node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				(node as GeometryInstance3D).ignore_occlusion_culling = true
		if bool(tweak.get("cull_off", false)):
			for node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				var g := node as GeometryInstance3D
				g.extra_cull_margin = 16384.0
				g.ignore_occlusion_culling = true

	func _process(_delta: float) -> void:
		if _done or _sun == null:
			return
		if not _started:
			_started = true
			_once()
		_apply_tweak()
		if _phase == 0 and _wait == 0:
			cc.set_pitch_now(float(pitches[_i]))
			if zooms.size() > _i:
				cc.set("_target_zoom", float(zooms[_i]))
			if pans.size() > _i:
				var p: Array = pans[_i]
				var holder := gm.cameraholder_node
				if _holder0 == Vector3.INF:
					_holder0 = holder.global_position
				holder.global_position = _holder0 + Vector3(float(p[0]), 0.0, float(p[1]))
			_sun.shadow_enabled = true
			_wait = settle
		elif _phase == 2 and _wait == 0:
			_sun.shadow_enabled = false
			_wait = settle
		if _wait > 0:
			_wait -= 1
			if _wait == 0:
				_phase += 1

	func _luma(image: Image) -> PackedByteArray:
		var small := image.duplicate() as Image
		small.convert(Image.FORMAT_L8)
		small.resize(W, H, Image.INTERPOLATE_BILINEAR)
		return small.get_data()

	func _grab() -> void:
		if _done or _sun == null:
			return
		if _phase == 1:
			_on = get_viewport().get_texture().get_image()
			_phase = 2
		elif _phase == 3:
			var off := get_viewport().get_texture().get_image()
			_finish_pitch(_on, off)
			_sun.shadow_enabled = true
			_phase = 0
			_i += 1
			if _i >= pitches.size():
				_finish()

	func _finish_pitch(on: Image, off: Image) -> void:
		var pitch := float(pitches[_i])
		var lon := _luma(on)
		var loff := _luma(off)
		var s := PackedByteArray()
		s.resize(W * H)
		var total := 0
		var lit := 0
		for k in W * H:
			var d := maxi(0, int(loff[k]) - int(lon[k]))
			s[k] = d
			total += d
			if d > 10:
				lit += 1
		var mean := float(total) / float(W * H)
		var change := 0.0
		var worst := 0.0
		var worst_at := Vector2i.ZERO
		if _prev_s.size() == s.size():
			var sum := 0
			for k in W * H:
				sum += absi(int(s[k]) - int(_prev_s[k]))
			change = float(sum) / float(W * H)
			for by in range(0, H - BLOCK + 1, BLOCK):
				for bx in range(0, W - BLOCK + 1, BLOCK):
					var a := 0
					var b := 0
					for y in BLOCK:
						var row := (by + y) * W + bx
						for x in BLOCK:
							a += s[row + x]
							b += _prev_s[row + x]
					var dm := absf(float(a - b)) / float(BLOCK * BLOCK)
					if dm > worst:
						worst = dm
						worst_at = Vector2i(bx / BLOCK, by / BLOCK)
		var cam := gm.camera_node
		_lines.append(
			(
				"pitch %.2f meanS %.3f litfrac %.4f dMean %.3f changeAbs %.3f worstBlock %.2f at %s maxdist %.0f mode %d cam_y %.1f near %.1f far %.0f size %.2f"
				% [
					pitch,
					mean,
					float(lit) / float(W * H),
					mean - _prev_mean,
					change,
					worst,
					str(worst_at),
					_sun.directional_shadow_max_distance,
					_sun.directional_shadow_mode,
					cam.global_position.y,
					cam.near,
					cam.far,
					cam.size,
				]
			)
		)
		_prev_s = s
		_prev_mean = mean
		var tag := "%05.1f" % pitch
		var scaled := s.duplicate()
		for k in W * H:
			scaled[k] = mini(255, int(s[k]) * 4)
		Image.create_from_data(W, H, false, Image.FORMAT_L8, scaled).save_png(
			dir.path_join("s_%s.png" % tag)
		)
		var small_on := on.duplicate() as Image
		small_on.resize(W, H, Image.INTERPOLATE_BILINEAR)
		small_on.save_png(dir.path_join("on_%s.png" % tag))

	func _restore() -> void:
		_sun.directional_shadow_mode = _orig_mode
		_sun.directional_shadow_blend_splits = _orig_blend
		_sun.directional_shadow_fade_start = _orig_fade
		_sun.directional_shadow_split_1 = _orig_splits[0]
		_sun.directional_shadow_split_2 = _orig_splits[1]
		_sun.directional_shadow_split_3 = _orig_splits[2]
		_sun.directional_shadow_pancake_size = _orig_pancake
		_sun.shadow_enabled = true

	func _finish() -> void:
		_done = true
		_restore()
		RenderingServer.frame_post_draw.disconnect(_grab)
		var f := FileAccess.open(dir.path_join("report.txt"), FileAccess.WRITE)
		if f != null:
			f.store_line("sweep %s tweak %s" % [sweep_name, str(tweak)])
			for l in _lines:
				f.store_line(l)
		print("RJ| sweep %s done, %d pitches, report %s" % [sweep_name, _lines.size(), dir.path_join("report.txt")])
		queue_free()


## In-run A/B of directional_shadow_blend_splits: windows of `frames` frames, off then on, `rounds`
## times, at one pitch; the world viewport's GPU render time (vsync off, measuring on) and the
## frame's wall time, the first 20 frames of each window discarded. Prints medians.
class PerfRig:
	extends Node

	var gm: GameMap = null
	var cc: CameraController = null
	var sun: DirectionalLight3D = null
	var pitch := 21.6
	var frames := 90
	var rounds := 4
	var _window := 0
	var _n := 0
	var _gpu := {false: [], true: []}
	var _cpu := {false: [], true: []}

	func _ready() -> void:
		cc.set_pitch_now(pitch)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(gm.world_viewport.get_viewport_rid(), true)

	func _median(a: Array) -> float:
		var b := a.duplicate()
		b.sort()
		return float(b[b.size() / 2]) if not b.is_empty() else 0.0

	func _process(delta: float) -> void:
		var on := _window % 2 == 1
		sun.directional_shadow_blend_splits = on
		if _n >= 20:
			var rid := gm.world_viewport.get_viewport_rid()
			_gpu[on].append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			_cpu[on].append(delta * 1000.0)
		_n += 1
		if _n >= frames:
			_n = 0
			_window += 1
			if _window >= rounds * 2:
				sun.directional_shadow_blend_splits = false
				print(
					"RJ| gpu blend A/B pitch %.1f blend off gpu %.3f ms cpu-frame %.3f ms | blend on gpu %.3f ms cpu-frame %.3f ms (medians, %d frames each)"
					% [
						pitch,
						_median(_gpu[false]),
						_median(_cpu[false]),
						_median(_gpu[true]),
						_median(_cpu[true]),
						_gpu[true].size()
					]
				)
				queue_free()
