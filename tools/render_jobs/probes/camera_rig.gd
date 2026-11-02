extends RefCounted

## Render-job probe for the camera rig's yaw (docs/plans/2026-11-02-camera, card camerarig-1).
## Steps (all `op: call`, script this file):
##   {action: "yaw", deg}      put the view at azimuth `deg` at once (CameraController.set_yaw_now)
##   {action: "turn", dir}     start the real eased snap, +1 (E) or -1 (Q)
##   {action: "keys", brush}   report the hint bar's chips and the compass tooltip (live mapping)
##   {action: "clip", name, dir, seconds, fps, lead, turn, width}
##                             a fixed-rate clip: ClipRig presses the turn key `turn` (+1/-1) after
##                             `lead` seconds and saves every drawn frame as <dir>/<name>_%04d.png
##                             (width px wide, default 960), logging per frame the yaw, the
##                             published camera axis against the true one and a sampled difference
##                             from the frame before. The job must `wait` seconds + 0.5 afterwards.
## Run the job with `--fixed-fps 30` (before `--script`): the engine then steps every frame by
## exactly 1/30 s however long the read-back takes, and shader TIME follows. The wind clock is
## pinned and advanced by 1/fps a frame, as camera-1 found it must be.


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	match String(step.get("action", "")):
		"yaw":
			cc.set_yaw_now(float(step.deg))
			return "yaw %.1f" % cc.current_yaw()
		"turn":
			cc.turn_view(int(step.get("dir", 1)))
			return "turn %d from %.1f" % [int(step.get("dir", 1)), cc.current_yaw()]
		"keys":
			var out := PackedStringArray()
			var compass: CameraCompass = cc.get("_compass")
			cc.get("_compass").sync_keys(bool(step.get("brush", false)))
			out.append("tooltip: " + compass._get_tooltip(Vector2(compass.size.x * 0.5, 10.0)))
			out.append("button tip: " + compass._get_tooltip(Vector2(compass.size.x * 0.5 + 54.0, 30.0)))
			return "\n".join(out)
		"clip":
			var rig := ClipRig.new()
			rig.gm = gm
			rig.cc = cc
			rig.clip_name = String(step.get("name", "clip"))
			rig.dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/camera_rig")))
			rig.fps = int(step.get("fps", 30))
			rig.frames = int(float(step.get("seconds", 3.0)) * rig.fps)
			rig.lead = int(float(step.get("lead", 0.5)) * rig.fps)
			rig.turn = int(step.get("turn", 1))
			rig.width = int(step.get("width", 960))
			base.get_tree().root.add_child(rig)
			return "clip %s %d frames" % [rig.clip_name, rig.frames]
	return "unknown action"


## Drives one snap at the clip's frame rate and saves every drawn frame.
class ClipRig:
	extends Node

	var gm: GameMap = null
	var cc: CameraController = null
	var clip_name := "clip"
	var dir := ""
	var fps := 30
	var frames := 90
	var lead := 15
	var turn := 1
	var width := 960
	var _log: Array[String] = []
	var _frame := 0
	var _wind0 := 0.0
	var _hashes := {}
	var _diffs: Array[int] = []
	var _prev := PackedByteArray()
	var _dmin := 1e9
	var _dmax := 0.0
	var _wall0 := 0

	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute(dir)
		_wind0 = Wind.clock()
		Wind.set_clock_override(_wind0)
		_wall0 = Time.get_ticks_msec()
		RenderingServer.frame_post_draw.connect(_grab)

	func _process(delta: float) -> void:
		if _frame > 0:
			_dmin = minf(_dmin, delta)
			_dmax = maxf(_dmax, delta)
		if _frame == lead:
			cc.turn_view(turn)
		Wind.set_clock_override(_wind0 + float(_frame) / float(fps))

	func _grab() -> void:
		if _frame >= frames:
			return
		var cam := gm.camera_node
		var back := cam.global_basis.z.normalized()
		var published := Vector3(CanopyFade._last_view.x, CanopyFade._last_view.y, CanopyFade._last_view.z)
		var image := get_viewport().get_texture().get_image()
		var data := image.get_data()
		_hashes[hash(data)] = true
		var diff := 0
		if _prev.size() == data.size():
			for k in range(0, data.size(), 997):
				diff += absi(int(data[k]) - int(_prev[k]))
		_diffs.append(diff)
		_prev = data
		_log.append(
			"%d yaw %.2f dot_published %.6f turning %s diff %d"
			% [_frame, cc.current_yaw(), published.dot(back), str(cc.is_turning()), diff]
		)
		image.resize(width, width * 9 / 16, Image.INTERPOLATE_LANCZOS)
		image.save_png(dir.path_join("%s_%04d.png" % [clip_name, _frame]))
		_frame += 1
		if _frame >= frames:
			_finish()

	func _finish() -> void:
		RenderingServer.frame_post_draw.disconnect(_grab)
		Wind.clear_clock_override()
		var worst := 1.0
		for line in _log:
			worst = minf(worst, float(line.split(" ")[4]))
		var line := (
			"clip %s: %d frames, %d unique hashes, delta %.5f..%.5f, min dot_published %.6f, %.1f s"
			% [clip_name, frames, _hashes.size(), _dmin, _dmax, worst, (Time.get_ticks_msec() - _wall0) / 1000.0]
		)
		print("RJ| " + line)
		var f := FileAccess.open(dir.path_join("report.txt"), FileAccess.WRITE)
		if f != null:
			f.store_line(line)
			for l in _log:
				f.store_line(l)
		queue_free()
