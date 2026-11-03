extends RefCounted

## Render-job probe for the glide between the orbit view and the eye (docs/plans/2026-11-02-camera,
## card SR3 eyeglide): drives the production path (CameraView.enter_street / leave_street) frame by
## frame at a fixed rate (run the job with `--fixed-fps 30` before `--script`) and captures every
## frame, a per-frame report and contact sheets. Steps (`op: call`, script this file):
##   {action: "stand", at: [x, z]}     step into the eye at once (a start pose for an exit clip)
##   {action: "leave"}                 back to the orbit view at once
##   {action: "clip", name, dir, direction: enter|exit, fps (30), width (640), pre, post (seconds
##    held before / after, default 0.6 / 0.8), keep (true: keep the frame PNGs), sheet_first (the
##    first N frames of the glide as one sheet, default 10), sheet_even (N frames spread over the
##    glide, default 6), sheet_width (tile width, 480)}
##                                     one clip: frames <name>_NNNN.png in `dir` (kept when
##                                     `keep`), <name>_report.txt (per frame: phase, progress,
##                                     distance, fov, near, far, sun shadow distance, fog end,
##                                     position, change from the previous frame, wall milliseconds
##                                     since the previous frame) and the two sheets. The job must
##                                     `wait` pre + 1.3 + post + 1.5 seconds after.

const GLIDE_FRAMES_MARGIN := 3


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	match String(step.get("action", "")):
		"stand":
			cc.view().enter_street(false)
			var at: Array = step.get("at", [])
			if at.size() == 2:
				cc.eye.frame_ground(Vector2(float(at[0]), float(at[1])), 0.0)
			cc.finish_zoom()
			return "stand foot %s" % str(cc.eye.foot())
		"leave":
			cc.set_view_mode(cc.orbit_view())
			return "leave"
		"clip":
			var rig := GlideRig.new()
			rig.gm = gm
			rig.cc = cc
			rig.configure(step)
			base.get_tree().root.add_child(rig)
			return "clip %s: %d frames" % [rig.clip_name, rig.total_frames()]
	return "unknown action"


## Drives one clip and writes its frames, report and sheets.
class GlideRig:
	extends Node

	var gm: GameMap = null
	var cc: CameraController = null
	var clip_name := "clip"
	var dir := ""
	var is_exit := false
	var fps := 30
	var width := 640
	var pre := 18
	var post := 24
	var keep := false
	var sheet_first := 10
	var sheet_even := 6
	var sheet_width := 480

	var _frame := 0
	var _glide_n := 0
	var _started_at := -1
	var _finished := false
	var _log: Array[String] = []
	var _prev := PackedByteArray()
	var _small: Array[Image] = []
	var _mae_list: Array[float] = []
	var _mae_peak := 0.0
	var _last_usec := 0
	var _light: DirectionalLight3D = null
	var _env: Environment = null

	func configure(step: Dictionary) -> void:
		clip_name = String(step.get("name", "clip"))
		dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/eye_glide")))
		is_exit = String(step.get("direction", "enter")) == "exit"
		fps = int(step.get("fps", 30))
		width = int(step.get("width", 640))
		pre = int(float(step.get("pre", 0.6)) * fps)
		post = int(float(step.get("post", 0.8)) * fps)
		keep = bool(step.get("keep", false))
		sheet_first = int(step.get("sheet_first", 10))
		sheet_even = int(step.get("sheet_even", 6))
		sheet_width = int(step.get("sheet_width", 480))
		_glide_n = int(ceil(EyeGlideRig.SECONDS * fps)) + GLIDE_FRAMES_MARGIN

	func total_frames() -> int:
		return pre + _glide_n + post

	func _ready() -> void:
		# Before the controller's own process, so the glide's first step is in the switch frame.
		process_priority = -100
		DirAccess.make_dir_recursive_absolute(dir)
		_light = gm.world_viewport.find_child("LevelSunLight", true, false) as DirectionalLight3D
		_env = cc.eye.level_environment()
		RenderingServer.frame_post_draw.connect(_after)

	func _process(_delta: float) -> void:
		if _frame == pre and _started_at < 0:
			_started_at = _frame
			if is_exit:
				cc.view().leave_street()
			else:
				cc.view().enter_street()

	func _after() -> void:
		if _finished:
			return
		var now := Time.get_ticks_usec()
		var wall_ms := float(now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
		_last_usec = now
		var full := get_viewport().get_texture().get_image()
		var mae := _mae(full)
		var cam := gm.camera_node
		var glide := cc.eye.glide
		var shadow := _light.directional_shadow_max_distance if is_instance_valid(_light) else -1.0
		_env = cc.eye.level_environment()
		var fog_end := _env.fog_depth_end if _env != null else -1.0
		var phase := "-"
		if _started_at >= 0:
			phase = "glide" if glide.is_active() else "after"
		_log.append(
			(
				"%d %s mode %s q %.3f d %.1f fov %.2f near %.2f far %.0f shadow %.0f fog_end %.0f "
				+ "pos %s mae %.2f wall_ms %.1f"
			)
			% [
				_frame,
				phase,
				cc.view_mode().mode_name(),
				glide.progress() if _started_at >= 0 else 0.0,
				glide.distance() if _started_at >= 0 else 0.0,
				cam.fov,
				cam.near,
				cam.far,
				shadow,
				fog_end,
				str(cam.global_position.snapped(Vector3.ONE * 0.1)),
				mae,
				wall_ms
			]
		)
		if _frame > 0:
			_mae_peak = maxf(_mae_peak, mae)
		var out := full.duplicate() as Image
		out.resize(width, width * 9 / 16, Image.INTERPOLATE_LANCZOS)
		if keep:
			out.save_png(dir.path_join("%s_%04d.png" % [clip_name, _frame]))
		var tile := full.duplicate() as Image
		tile.resize(sheet_width, sheet_width * 9 / 16, Image.INTERPOLATE_LANCZOS)
		_small.append(tile)
		_mae_list.append(mae)
		_frame += 1
		if _frame >= total_frames():
			_finish()

	## Mean absolute difference per byte against the previous captured frame (160 x 90 copy).
	func _mae(image: Image) -> float:
		var small := image.duplicate() as Image
		small.resize(160, 90, Image.INTERPOLATE_BILINEAR)
		small.convert(Image.FORMAT_RGB8)
		var data := small.get_data()
		var sum := 0
		if _prev.size() == data.size():
			for i in data.size():
				sum += absi(int(data[i]) - int(_prev[i]))
		_prev = data
		return float(sum) / float(data.size())

	## One sheet of the frames `indices` (absolute frame numbers), `cols` tiles per row.
	func _sheet(indices: Array, cols: int, file: String) -> void:
		if indices.is_empty():
			return
		var rows := ceili(float(indices.size()) / float(cols))
		var tw := sheet_width
		var th := sheet_width * 9 / 16
		var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.BLACK)
		for k in indices.size():
			var idx: int = indices[k]
			if idx < 0 or idx >= _small.size():
				continue
			var tile := _small[idx]
			if tile.get_format() != Image.FORMAT_RGBA8:
				tile = tile.duplicate() as Image
				tile.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(tile, Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
		sheet.save_png(dir.path_join(file))

	func _finish() -> void:
		_finished = true
		RenderingServer.frame_post_draw.disconnect(_after)
		var first: Array = []
		for k in sheet_first:
			first.append(pre + k)
		_sheet(first, 5, "%s_first_sheet.png" % clip_name)
		var even: Array = []
		for k in sheet_even:
			var span := float(_glide_n - GLIDE_FRAMES_MARGIN)
			even.append(pre + int(round(float(k) * span / float(maxi(sheet_even - 1, 1)))))
		_sheet(even, 3, "%s_even_sheet.png" % clip_name)
		var firsts := PackedStringArray()
		for k in 12:
			if pre + k < _mae_list.size():
				firsts.append("%.2f" % _mae_list[pre + k])
		var head := "clip %s %s: %d frames (pre %d, glide %d, post %d)" % [
			clip_name, "exit" if is_exit else "enter", total_frames(), pre, _glide_n, post
		]
		var summary := "%s, peak frame change %.2f, first 12 glide frames change: %s" % [
			head, _mae_peak, ", ".join(firsts)
		]
		print("RJ| " + summary)
		var f := FileAccess.open(dir.path_join("%s_report.txt" % clip_name), FileAccess.WRITE)
		if f != null:
			f.store_line(summary)
			for l in _log:
				f.store_line(l)
		queue_free()
