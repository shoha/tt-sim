extends RefCounted

## Render-job probe for the eye view (docs/plans/2026-11-02-camera, card eyeview). Steps (`op: call`,
## script this file):
##   {action: "enter", at: [x, z], yaw, pitch, fov, via_key}
##                             step into the eye view (CameraController.set_view_mode, or the F9 key
##                             handler with `via_key`), optionally standing at world XZ `at`, at once,
##                             with yaw / pitch / lens (fov) set and the lens eased onto its target
##   {action: "leave"}         back to the orbit view
##   {action: "pose", yaw, pitch, fov}   the same pose arguments, without a mode change
##   {action: "state"}         one line: mode, foot, eye position, yaw, pitch, fov, camera near/far
##   {action: "walk", name, dir, seconds, fps, every, width, events: [...]}
##                             a fixed-rate scripted walk: the events below run on their frames, and the
##                             foot, eye height, speed and grab error are written per frame to
##                             <dir>/<name>_report.txt (a frame is saved every `every` frames, `width`
##                             px wide, default 0: none). The job must `wait` seconds + 0.5 afterwards.
##                             Events {at: frame, do: ...}: "walk" (v: [right, forward], run),
##                             "turn" (dir), "yaw" (deg), "grab" (px: [x, y] screen fractions),
##                             "drag" (to: frame, dx, dy: cursor pixels over the frames), "release",
##                             "glide" (xz: [x, z])
## Run walk jobs with `--fixed-fps 30` (before `--script`) so every step is exactly 1/30 s.


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	match String(step.get("action", "")):
		"enter":
			if bool(step.get("via_key", false)):
				var key := InputEventKey.new()
				key.keycode = KEY_F9
				key.pressed = true
				cc._unhandled_key_input(key)
			else:
				cc.set_view_mode(cc.eye)
			if cc.view_mode() != cc.eye:
				return "enter failed: %s active" % cc.view_mode().mode_name()
			var at: Array = step.get("at", [])
			if at.size() == 2:
				cc.eye.frame_ground(Vector2(float(at[0]), float(at[1])), 0.0)
			return _pose(cc, step) + " | " + _state(gm, cc)
		"leave":
			cc.set_view_mode(cc.orbit_view())
			return _state(gm, cc)
		"pose":
			return _pose(cc, step) + " | " + _state(gm, cc)
		"state":
			return _state(gm, cc)
		"walk":
			var rig := WalkRig.new()
			rig.gm = gm
			rig.cc = cc
			rig.eye = cc.eye
			rig.rig_name = String(step.get("name", "walk"))
			rig.dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/eye_view")))
			rig.fps = int(step.get("fps", 30))
			rig.frames = int(float(step.get("seconds", 3.0)) * rig.fps)
			rig.every = int(step.get("every", 0))
			rig.width = int(step.get("width", 0))
			rig.events = step.get("events", [])
			base.get_tree().root.add_child(rig)
			return "walk %s %d frames" % [rig.rig_name, rig.frames]
	return "unknown action"


static func _pose(cc: CameraController, step: Dictionary) -> String:
	if step.has("yaw"):
		cc.set_yaw_now(float(step.yaw))
	if step.has("pitch"):
		cc.set_pitch_now(float(step.pitch))
	if step.has("fov"):
		cc.view_mode().zoom_by(float(step.fov) - cc.view_mode().fov_deg())
	cc.finish_zoom()
	return "pose"


static func _state(gm: GameMap, cc: CameraController) -> String:
	var cam := gm.camera_node
	var eye := cc.eye
	return (
		"%s foot %s eye %s yaw %.1f pitch %.1f lens %.1f fov %.1f proj %d near %.3f far %.0f"
		% [
			cc.view_mode().mode_name(),
			str(eye.foot().snapped(Vector2.ONE * 0.01)),
			str(cam.global_position.snapped(Vector3.ONE * 0.01)),
			cc.current_yaw(),
			cc.current_pitch(),
			cc.view_mode().fov_deg(),
			cam.fov,
			cam.projection,
			cam.near,
			cam.far
		]
	)


## Drives the scheduled events at the walk's frame rate and logs the foot every drawn frame.
class WalkRig:
	extends Node

	var gm: GameMap = null
	var cc: CameraController = null
	var eye: EyeView = null
	var rig_name := "walk"
	var dir := ""
	var fps := 30
	var frames := 90
	var every := 0
	var width := 0
	var events: Array = []
	var _log: Array[String] = []
	var _frame := 0
	var _wind0 := 0.0
	var _press := Vector2.ZERO
	var _cursor := Vector2.ZERO
	var _grabbed: Variant = null
	var _prev_foot := Vector2.ZERO
	var _drags: Array[Dictionary] = []
	var _fired := {}
	var _min := Vector2(INF, INF)
	var _max := Vector2(-INF, -INF)

	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute(dir)
		_wind0 = Wind.clock()
		Wind.set_clock_override(_wind0)
		_prev_foot = eye.foot()
		RenderingServer.frame_post_draw.connect(_after)

	func _process(_delta: float) -> void:
		# Frame 0 can be drawn before the first process, so an event is due from its frame on.
		for i in events.size():
			if not _fired.has(i) and int(events[i].at) <= _frame:
				_fired[i] = true
				_start(events[i])
		for d in _drags:
			_drag_frame(d)
		Wind.set_clock_override(_wind0 + float(_frame) / float(fps))

	func _start(e: Dictionary) -> void:
		match String(e.get("do", "")):
			"walk":
				var v: Array = e.get("v", [0, 0])
				eye.set_walk(Vector2(float(v[0]), float(v[1])), bool(e.get("run", false)))
			"turn":
				cc.turn_view(int(e.get("dir", 1)))
			"yaw":
				cc.set_yaw_now(float(e.deg))
			"glide":
				var xz: Array = e.xz
				eye.glide_to(Vector2(float(xz[0]), float(xz[1])))
			"grab":
				var px: Array = e.px
				var size := Vector2(gm.world_viewport.size)
				_press = Vector2(float(px[0]), float(px[1])) * size
				_cursor = _press
				eye.pan_begin(_press, false)
				_grabbed = eye._grab
			"release":
				eye.pan_end(false)
				_grabbed = null
			"drag":
				_drags.append(e)

	func _drag_frame(d: Dictionary) -> void:
		var from := int(d.at)
		var to := int(d.to)
		if _frame < from or _frame > to or to <= from:
			return
		var motion := InputEventMouseMotion.new()
		_cursor = _press + Vector2(float(d.dx), float(d.dy)) * float(_frame - from) / float(to - from)
		motion.position = _cursor
		eye.pan_motion(motion)

	func _after() -> void:
		if _frame >= frames:
			return
		var foot := eye.foot()
		_min = _min.min(foot)
		_max = _max.max(foot)
		var err := -1.0
		if _grabbed != null:
			var under: Variant = eye._pointer_ground(_cursor)
			if under != null:
				err = Vector2((under as Vector3).x - (_grabbed as Vector3).x, (under as Vector3).z - (_grabbed as Vector3).z).length()
		var speed := foot.distance_to(_prev_foot) * float(fps)
		_prev_foot = foot
		var eye_pos := eye.eye_position()
		_log.append(
			"%d t %.3f foot %.3f %.3f eye_y %.3f speed %.3f yaw %.1f pitch %.1f grab_err %.5f"
			% [_frame, float(_frame) / float(fps), foot.x, foot.y, eye_pos.y, speed, cc.current_yaw(), cc.current_pitch(), err]
		)
		if every > 0 and width > 0 and _frame % every == 0:
			var image := get_viewport().get_texture().get_image()
			image.resize(width, width * 9 / 16, Image.INTERPOLATE_LANCZOS)
			image.save_png(dir.path_join("%s_%04d.png" % [rig_name, _frame]))
		_frame += 1
		if _frame >= frames:
			_finish()

	func _finish() -> void:
		RenderingServer.frame_post_draw.disconnect(_after)
		Wind.clear_clock_override()
		var summary := (
			"walk %s: %d frames, foot range x %.3f..%.3f z %.3f..%.3f, final %s"
			% [rig_name, frames, _min.x, _max.x, _min.y, _max.y, str(eye.foot().snapped(Vector2.ONE * 0.001))]
		)
		print("RJ| " + summary)
		var f := FileAccess.open(dir.path_join("%s_report.txt" % rig_name), FileAccess.WRITE)
		if f != null:
			f.store_line(summary)
			for l in _log:
				f.store_line(l)
		queue_free()
