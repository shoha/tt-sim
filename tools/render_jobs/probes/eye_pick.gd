extends RefCounted

## Render-job probe for the play tools at the eye (card eyepick, docs/plans/2026-11-02-camera). It
## uses the real eye view (CameraController.set_view_mode, EyeView) and the real input path
## (Input.parse_input_event). One `call` step per action; a step is held while a rig still runs.
## Every action writes report_<action>.txt and PNGs into `dir`; `at` is the eye's ground xz and
## `yaw` the view yaw (CameraRig: 45 is home, 180 looks toward +z).
##   drag {dir, at, yaw}   a token pressed in the open and dragged: the target must be the ground
##                         under the cursor (the ray through the cursor passes through it, its
##                         height is the ground field's); a window capture mid-drag shows the
##                         ruler; the cursor then goes above the horizon (a ray flatter than 6
##                         degrees): the target must not move. Then a token behind a wall (the
##                         eyeprobe ghost case): pressed through the wall, the target must be on
##                         the ground, not on the facade or roof.
##   tools {dir, at, yaw}  measure (a line ahead, a line from behind the eye) and the sun gizmo at
##                         the eye, window captures.
##   await                 holds the job while a rig runs.

const GROUP := "eye_pick_rig"


static func blocker(base: Node, _step: Dictionary) -> String:
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the eye pick rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var rig := PickRig.new()
	rig.gm = base.get("_game_map")
	rig.lpc = base.get("_level_play_controller")
	rig.step = step
	rig.mode = action
	base.get_tree().root.add_child(rig)
	return "%s started" % action


class PickRig:
	extends Node

	var gm: GameMap = null
	var lpc: LevelPlayController = null
	var step: Dictionary = {}
	var mode := ""
	var _dir := ""
	var _lines: Array[String] = []
	var _cursor := Vector2.ZERO
	var _height: Callable = Callable()

	func _ready() -> void:
		add_to_group(GROUP)
		_dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/eye_pick")))
		DirAccess.make_dir_recursive_absolute(_dir)
		_height = ViewGround.height_function(gm)
		_main()

	func _main() -> void:
		match mode:
			"drag":
				await _drag()
			"tools":
				await _tools()
			_:
				_log("unknown action %s" % mode)
		var f := FileAccess.open(_dir.path_join("report_%s.txt" % mode), FileAccess.WRITE)
		if f != null:
			for l in _lines:
				f.store_line(l)
		print("RJ| eye_pick %s done, %d lines, %s" % [mode, _lines.size(), _dir])
		queue_free()

	func _log(text: String) -> void:
		_lines.append(text)
		print("RJ| " + text)

	func _v(v: Vector3) -> String:
		return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _at() -> Vector2:
		return Vector2(float(step.at[0]), float(step.at[1]))

	func _ground(xz: Vector2) -> Vector3:
		return Vector3(xz.x, float(_height.call(xz)) if _height.is_valid() else 0.0, xz.y)

	func _enter(yaw: float, pitch: float) -> void:
		var cc := gm.get_camera_controller()
		cc.set_view_mode(cc.eye)
		cc.eye.frame_ground(_at(), 0.0)
		cc.set_yaw_now(yaw)
		cc.set_pitch_now(pitch)
		cc.finish_zoom()
		await _frames(40)

	func _leave() -> void:
		gm.get_camera_controller().leave_eye()
		await _frames(10)

	func _cam() -> Camera3D:
		return gm.camera_node

	func _window(name: String) -> void:
		await _frames(4)
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(_dir.path_join(name + ".png"))

	func _space() -> PhysicsDirectSpaceState3D:
		return gm.world_viewport.find_world_3d().direct_space_state

	func _move(pos: Vector2, mask: int) -> void:
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.relative = pos - _cursor
		motion.button_mask = mask
		_cursor = pos
		Input.parse_input_event(motion)
		Input.flush_buffered_events()

	func _button(pos: Vector2, index: MouseButton, pressed: bool) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = index
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(ev)
		Input.flush_buffered_events()

	## Press on `at` (a screen point) and move 12 px: an active drag if the press landed on the token.
	func _press(at: Vector2, token: BoardToken) -> void:
		gm.camera_node.get_viewport().gui_release_focus()
		_move(at, 0)
		await _frames(2)
		_button(at, MOUSE_BUTTON_LEFT, true)
		await get_tree().physics_frame
		await _frames(2)
		for i in range(1, 13):
			_move(at + Vector2(1.0 * i, 0.0), MOUSE_BUTTON_MASK_LEFT)
			await _frames(1)
		_log("  pressed: dragging %s subject is the token %s" % [
			str(gm.drag_and_drop_node.is_dragging()),
			str(gm.drag_and_drop_node.get_subject() == token.get_dragging_object())
		])

	func _spawn(xz: Vector2) -> BoardToken:
		var token := lpc.spawn_avatar(AvatarPresets.recipe(0), "eyepick", _ground(xz))
		await _frames(150)
		return token

	func _chest(token: BoardToken) -> Vector3:
		var shape: Node3D = token.get_dragging_object().collision_shape
		return shape.global_position + Vector3(0, 0.7, 0)

	## How far the point `p` is from the camera ray through screen point `px`.
	func _ray_miss(px: Vector2, p: Vector3) -> float:
		var o := _cam().project_ray_origin(px)
		var d := _cam().project_ray_normal(px)
		return (p - o).cross(d).length()

	func _target_report(label: String, px: Vector2) -> void:
		var dnd := gm.drag_and_drop_node
		if not dnd.has_target():
			_log("%s: no target" % label)
			return
		var tg: Vector3 = dnd.get_target_ground_position()
		var field := _ground(Vector2(tg.x, tg.z)).y
		_log("%s: target %s ground field y %.3f (error %.3f) cursor ray misses it by %.3f m" % [
			label, _v(tg), field, tg.y - field, _ray_miss(px, tg)
		])

	func _drag() -> void:
		var dnd := gm.drag_and_drop_node
		dnd.set("edge_pan_enabled", false)
		dnd.set("grid_snap_enabled", false)
		var yaw := float(step.get("yaw", 180))
		await _enter(yaw, 8.0)
		var eye_pos := _cam().global_position
		var forward := CameraRig.screen_up(yaw)
		_log("drag: eye %s yaw %.0f height field %s" % [_v(eye_pos), yaw, str(_height.is_valid())])
		# --- A: a token in the open ---
		var open_xz := _at() + Vector2(forward.x, forward.z) * 8.0
		var token := await _spawn(open_xz)
		var chest := _chest(token)
		var at := _cam().unproject_position(chest)
		_log("A open: token %s chest screen %s" % [_v(token.rigid_body.global_position), str(at)])
		await _press(at, token)
		var to := at + Vector2(40.0, 140.0)
		for i in range(1, 11):
			_move(at.lerp(to, float(i) / 10.0), MOUSE_BUTTON_MASK_LEFT)
			await _frames(1)
		await _frames(30)
		_target_report("A open, cursor low", to)
		await _window("drag_open_window")
		var kept: Vector3 = dnd.get_target_ground_position()
		var near_xz := _at() + Vector2(forward.x, forward.z) * 4.0
		var low := _cam().unproject_position(_ground(near_xz))
		_move(low, MOUSE_BUTTON_MASK_LEFT)
		await _frames(10)
		_target_report("A open, cursor near", low)
		# The cursor above the horizon: a ray flatter than 6 degrees names no ground.
		var before: Vector3 = dnd.get_target_ground_position()
		var top := Vector2(float(gm.world_viewport.size.x) * 0.5, 4.0)
		_move(top, MOUSE_BUTTON_MASK_LEFT)
		await _frames(10)
		var after: Vector3 = dnd.get_target_ground_position()
		var ray_y := _cam().project_ray_normal(top).y
		_log("A flat ray: cursor at the top (ray y %.3f, %.1f deg up): target moved %.4f m" % [
			ray_y, rad_to_deg(asin(ray_y)), before.distance_to(after)
		])
		# A ground point 30 m away is 3 degrees below the horizon: also refused.
		var far_px := _cam().unproject_position(_ground(_at() + Vector2(forward.x, forward.z) * 30.0))
		_move(far_px, MOUSE_BUTTON_MASK_LEFT)
		await _frames(10)
		var far_dir := _cam().project_ray_normal(far_px)
		_log("A flat ray: cursor on the ground 30 m away (%.1f deg down): target moved %.4f m" % [
			-rad_to_deg(asin(far_dir.y)), before.distance_to(dnd.get_target_ground_position())
		])
		_button(far_px, MOUSE_BUTTON_LEFT, false)
		await _frames(60)
		_log("A open: dropped at %s (kept target %s)" % [_v(token.rigid_body.global_position), _v(kept)])
		# --- B: a token behind a wall ---
		var spot := _house_behind(eye_pos)
		_log("B wall: house search %s" % str(spot))
		if spot.has("xz"):
			var d: Vector3 = spot.dir
			var wall_yaw := rad_to_deg(atan2(-d.x, -d.z))
			var gp := _ground(spot.xz)
			var behind := await _spawn(spot.xz)
			chest = _chest(behind)
			var flat := Vector2(chest.x - eye_pos.x, chest.z - eye_pos.z).length()
			var pitch := rad_to_deg(atan2(eye_pos.y - chest.y, flat))
			var cc := gm.get_camera_controller()
			cc.set_yaw_now(wall_yaw)
			cc.set_pitch_now(clampf(pitch, EyeRig.PITCH_MIN, EyeRig.PITCH_MAX))
			await _frames(30)
			at = _cam().unproject_position(chest)
			var start := behind.rigid_body.global_position
			_log("B wall: token %s chest screen %s wall front %s (%.1f m) ground behind %s" % [
				_v(start), str(at), _v(spot.front), eye_pos.distance_to(spot.front), _v(gp)
			])
			await _press(at, behind)
			to = at + Vector2(30.0, 40.0)
			for i in range(1, 11):
				_move(at.lerp(to, float(i) / 10.0), MOUSE_BUTTON_MASK_LEFT)
				await _frames(1)
			await _frames(40)
			_target_report("B wall", to)
			if dnd.has_target():
				var tg: Vector3 = dnd.get_target_ground_position()
				_log("B wall: target is %.2f m from the facade point, %.2f m from the token's start" % [
					tg.distance_to(spot.front), tg.distance_to(start)
				])
			await _window("drag_wall_window")
			_button(to, MOUSE_BUTTON_LEFT, false)
			await _frames(60)
			_log("B wall: token ended %s (%.2f m from start, y over ground %.2f)" % [
				_v(behind.rigid_body.global_position), start.distance_to(behind.rigid_body.global_position),
				behind.rigid_body.global_position.y - _ground(Vector2(
					behind.rigid_body.global_position.x, behind.rigid_body.global_position.z)).y
			])
		await _leave()

	## A wall ahead of the eye with open ground 3 m behind the house: {dir, front, xz, ...}.
	func _house_behind(eye_pos: Vector3) -> Dictionary:
		var pick := {}
		for yaw in range(0, 360, 15):
			var d := Vector3(sin(deg_to_rad(yaw)), 0.0, -cos(deg_to_rad(yaw)))
			var front := _ray(eye_pos, eye_pos + d * 30.0)
			if front.is_empty() or absf(front.normal.y) > 0.3:
				continue
			var fd := eye_pos.distance_to(front.position)
			if fd < 3.0 or fd > 20.0:
				continue
			var back := _ray(eye_pos + d * (fd + 20.0), front.position)
			if back.is_empty():
				continue
			var thick: float = front.position.distance_to(back.position)
			if thick < 2.0 or thick > 19.0:
				continue
			pick = {
				"dir": d,
				"front": front.position,
				"xz": Vector2(back.position.x + d.x * 3.0, back.position.z + d.z * 3.0),
				"thick": thick,
				"collider": str(front.collider.get_path()),
			}
			break
		return pick

	func _ray(from: Vector3, to: Vector3) -> Dictionary:
		return _space().intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

	func _tools() -> void:
		var yaw := float(step.get("yaw", 180))
		await _enter(yaw, 10.0)
		var eye_pos := _cam().global_position
		var forward := CameraRig.screen_up(yaw)
		var ahead := Vector3(forward.x, 0.0, forward.z)
		var foot := Vector2(eye_pos.x, eye_pos.z)
		var mt := gm.get_measure_tool()
		mt.activate()
		var dir2 := Vector2(ahead.x, ahead.z)
		var path := PackedVector3Array([_ground(foot + dir2 * 4.0), _ground(foot + dir2 * 12.0)])
		mt.set("_waypoints", path)
		mt.set("_state", MeasureTool.State.PLACING_WAYPOINT)
		mt.call("_mark_dirty")
		await _window("tools_measure_ahead")
		_log("measure ahead: points %s -> %s, screen points %s" % [
			_v(path[0]), _v(path[1]), str(mt.get("_screen_points"))
		])
		var from_behind := PackedVector3Array([_ground(foot - dir2 * 3.0), _ground(foot + dir2 * 10.0)])
		mt.set("_waypoints", from_behind)
		mt.call("_mark_dirty")
		await _window("tools_measure_behind")
		_log("measure from behind the eye: seen %s segments %s" % [
			str(mt.get("_point_seen")), str(mt.get("_screen_segments"))
		])
		mt.deactivate()
		gm.setup_sun_gizmo()
		var sun := gm.get_sun_gizmo()
		sun.set_direction(120.0, 35.0)
		sun.activate()
		await _window("tools_sun")
		var centre: Vector3 = sun.call("_viewport_centre_ground_point")
		var c_px := _cam().unproject_position(centre)
		var probe := c_px + Vector2(60.0, 30.0)
		var hit: Vector3 = sun.call("_ground_point_at", probe, centre.y)
		_log("sun: ring centre %s (screen %s), %.2f m ahead of the eye; pointer %s -> ground %s" % [
			_v(centre), str(c_px), Vector2(centre.x - eye_pos.x, centre.z - eye_pos.z).length(),
			str(probe), _v(hit)
		])
		sun.deactivate()
		await _leave()
