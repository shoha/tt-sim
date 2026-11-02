extends RefCounted

## Render-job probe for the camera rig (docs/plans/2026-11-02-camera, cards camerarig-1 and -2).
## Steps (all `op: call`, script this file):
##   {action: "yaw", deg}      put the view at azimuth `deg` at once (CameraController.set_yaw_now)
##   {action: "pitch", deg}    put the view at elevation `deg` at once (set_pitch_now)
##   {action: "turn", dir}     start the real eased snap, +1 (E) or -1 (Q)
##   {action: "tokens", ...}   spawn tokens with token_toon_row.gd's spawn_row (from, to, items, zig);
##                             `scale: {item: factor}` then enlarges the named tokens
##   {action: "scale", scale}  enlarge named tokens (after the spawn pop-in, a wait of 0.5 s)
##   {action: "zoom", which}   camera size to "closest" (min_zoom) or "home" (the load zoom)
##   {action: "keys", brush}   report the hint bar's chips and the compass tooltip (live mapping)
##   {action: "clip", name, dir, seconds, fps, width, events: [...]}
##                             a fixed-rate clip: ClipRig runs the scheduled `events` and saves every
##                             drawn frame as <dir>/<name>_%04d.png (width px wide, default 960),
##                             logging per frame the yaw, pitch, the published camera axis against the
##                             true one and a sampled difference from the frame before. The job must
##                             `wait` seconds + 0.5 afterwards. An event is {at: frame, do: ...}:
##                             "turn" (dir), "toggle" (the O key), "home", or "drag" (to: frame, dx, dy:
##                             an Alt + left drag through CameraController.handle_orbit_input, total
##                             pixels spread evenly over the frames).
## Run the job with `--fixed-fps 30` (before `--script`): the engine then steps every frame by
## exactly 1/30 s however long the read-back takes, and shader TIME follows. The wind clock is
## pinned and advanced by 1/fps a frame, as camera-1 found it must be.

const TOKEN_ROW := "res://tools/render_jobs/probes/token_toon_row.gd"


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	match String(step.get("action", "")):
		"yaw":
			cc.set_yaw_now(float(step.deg))
			return "yaw %.1f" % cc.current_yaw()
		"pitch":
			cc.set_pitch_now(float(step.deg))
			return "pitch %.1f" % cc.current_pitch()
		"turn":
			cc.turn_view(int(step.get("dir", 1)))
			return "turn %d from %.1f" % [int(step.get("dir", 1)), cc.current_yaw()]
		"tokens":
			var row: GDScript = load(TOKEN_ROW)
			var out := String(row.call("run", base, step.merged({"action": "spawn_row"}, true)))
			return out + _scale(gm, step.get("scale", {}))
		"scale":
			# Enlarges named tokens after the spawn pop-in has ended (it would reset the scale).
			return "scaled" + _scale(gm, step.get("scale", {}))
		"atlas":
			# Saves the pin portrait atlas (cropped to the used rows, 2x) to `path` and lists each
			# token's pin facts: key, cell, footprint radius and half height, colour.
			return _atlas(gm, String(step.get("path", "user://render_jobs/atlas.png")))
		"zoom":
			# `which` closest (the controller's min_zoom) or home (its load zoom): the camera size.
			var closest := String(step.get("which", "home")) == "closest"
			var size: float = cc.min_zoom if closest else float(cc.get("_home_zoom"))
			cc.set("_target_zoom", size)
			return "zoom %s size %.2f (limits %.2f..%.2f)" % [step.get("which", "home"), size, cc.min_zoom, cc.max_zoom]
		"keys":
			var out := PackedStringArray()
			var compass: CameraCompass = cc.compass
			compass.sync_keys(bool(step.get("brush", false)))
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
			rig.events = step.get("events", [])
			rig.width = int(step.get("width", 960))
			base.get_tree().root.add_child(rig)
			return "clip %s %d frames" % [rig.clip_name, rig.frames]
	return "unknown action"


static func _atlas(gm: GameMap, path: String) -> String:
	var markers := gm.world_viewport.get_node_or_null("TokenMarkers") as TokenMarkers
	if markers == null or markers._portraits == null:
		return "no portraits yet"
	var portraits: TokenPortraits = markers._portraits
	var image: Image = portraits._image.duplicate()
	var rows := ceili(float(portraits._next_cell) / TokenPortraits.GRID)
	image = image.get_region(Rect2i(0, 0, TokenPortraits.ATLAS_PX, maxi(rows, 1) * TokenPortraits.CELL_PX))
	image.save_png(ProjectSettings.globalize_path(path))
	var out := PackedStringArray(["cells %d, failed %d" % [portraits._next_cell, portraits._failed.size()]])
	for id in markers._look:
		var look: Dictionary = markers._look[id]
		var token := instance_from_id(id) as BoardToken
		if token == null:
			continue
		var cam := gm.camera_node
		var body := token.rigid_body
		var shapes := TokenMarkers.shape_box(body)
		var mesh_box := AABB()
		var first := true
		for mi in TokenGhost.meshes_of(body):
			var b := mi.global_transform * mi.get_aabb()
			mesh_box = b if first else mesh_box.merge(b)
			first = false
		var centre: Vector3 = body.global_position + (look.offset as Vector3)
		out.append(
			"%s cell %d r %.2f hh %.2f colour %s | body px %s centre px %s | shape c %s s %s | mesh c %s s %s"
			% [
				token.token_name,
				portraits.cell_of(String(look.key)),
				look.radius,
				look.half_height,
				(look.colour as Color).to_html(false),
				str(cam.unproject_position(body.global_position).round()),
				str(cam.unproject_position(centre).round()),
				str(shapes.get_center().snapped(Vector3.ONE * 0.01)),
				str(shapes.size.snapped(Vector3.ONE * 0.01)),
				str(mesh_box.get_center().snapped(Vector3.ONE * 0.01)),
				str(mesh_box.size.snapped(Vector3.ONE * 0.01))
			]
		)
	return "\n".join(out)


static func _scale(gm: GameMap, scales: Dictionary) -> String:
	var done := 0
	for node in gm.get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if token != null and scales.has(token.token_name):
			var at := token.rigid_body.global_position
			var factor := float(scales[token.token_name])
			token.set_transform_immediate(at, Vector3.ZERO, Vector3.ONE * factor)
			token.transform_changed.emit()
			done += 1
	return " (%d scaled)" % done


## Drives the scheduled events at the clip's frame rate and saves every drawn frame.
class ClipRig:
	extends Node

	var gm: GameMap = null
	var cc: CameraController = null
	var clip_name := "clip"
	var dir := ""
	var fps := 30
	var frames := 90
	var events: Array = []
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
	var _drags: Array[Dictionary] = []

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
		for e: Dictionary in events:
			if int(e.at) == _frame:
				_start(e)
		for d in _drags:
			_drag_frame(d)
		Wind.set_clock_override(_wind0 + float(_frame) / float(fps))

	func _start(e: Dictionary) -> void:
		match String(e.get("do", "")):
			"turn":
				cc.turn_view(int(e.get("dir", 1)))
			"toggle":
				cc.view().toggle_top_down()
			"home":
				cc.call("_reset_camera_to_home")
			"drag":
				_drags.append(e)

	## One frame of an Alt + left drag: the press on its first frame, an even share of the motion on
	## each frame after, the release on its last.
	func _drag_frame(d: Dictionary) -> void:
		var from := int(d.at)
		var to := int(d.to)
		if _frame < from or _frame > to:
			return
		if _frame == from:
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.alt_pressed = true
			cc.handle_orbit_input(press, false)
		elif _frame < to:
			var move := InputEventMouseMotion.new()
			move.relative = Vector2(float(d.dx), float(d.dy)) / float(to - from)
			cc.handle_orbit_input(move, false)
		else:
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			cc.handle_orbit_input(release, false)

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
			"%d yaw %.2f dot_published %.6f turning %s diff %d pitch %.2f"
			% [_frame, cc.current_yaw(), published.dot(back), str(cc.is_turning()), diff, cc.current_pitch()]
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
