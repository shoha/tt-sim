extends RefCounted

## Render-job probe for the street-level shadow sweep (card shadowsweep SR-P1). Question: do the sun
## shadows of trees pop in and out as a PERSPECTIVE eye camera goes from level down to the home
## pitch, and does a larger caster cull margin on the scatter chunks or a longer shadow distance fix
## it? It extends camera_shadow.gd's method (two stills per pose, sun shadows on and off, the
## shadow-only picture S = max(0, luma_off - luma_on), the largest 30 px block change between
## neighbouring poses) from the ortho home camera to an eye camera.
##
## Steps (all `op: call`, script this file):
##   {action: "sweep", name, dir, at: [x, z], eye: 1.6, fov: 60, yaws: [45, 135, 225, 315, "sun"],
##    fine: [0..25 step 1], coarse: [25..90], configs: [{name, margin?, maxdist?}], settle: 4,
##    cfg_settle: 40}
##       A config also takes `blend` (false: directional_shadow_blend_splits off, the state before
##       the 2026-11-02 fix), to show that the sweep does see a pop when there is one.
##       For every config, yaw and pitch (positive looks down) the camera stands `eye` m above the
##       ground at `at`. `margin` sets extra_cull_margin on every MultiMeshInstance3D (the scatter
##       chunks; default their own 1 m), `maxdist` the sun's directional_shadow_max_distance
##       (default: left to MapViewFit, which fits it to the eye under a perspective camera
##       since the eyeperf card; the report line shows the distance in effect as maxd).
##       Writes <dir>/report.txt (one line per pose), the
##       <dir>/summary.txt table and, per config and yaw, <dir>/sheet_s_<cfg>_<yaw>.png (the S
##       pictures of the fine pitches, x4) and sheet_on_<cfg>_<yaw>.png (the lit frames).
##   {action: "walk", name, dir, at, eye, fov, yaw, pitch, speed: 3, seconds: 6, fps: 30, configs}
##       The eye walks forward from `at`; per config (1) a stepped S analysis of every frame
##       position (pops show as block-change spikes), then (2) the real clip: every frame saved
##       as <dir>/<name>_<cfg>_%04d.png, run with `--fixed-fps 30`; then sheet_walk_<cfg>.png tiles
##       eight consecutive frames around the worst spike (lit frames above, S below).
##   {action: "perf", at, eye, fov, yaw, pitches, configs, frames: 90, rounds: 4}
##       In-run A/B of the configs (windows of `frames` frames, the first 20 discarded): world
##       viewport GPU and CPU render time, indicative only.
##   {action: "await"}   holds the job (up to the driver's 60 s per step) while a rig is running.

const BLOCK := 30
const W := 480
const H := 270
const GROUP := "shadow_eye_rig"
const TILE_W := 160
const TILE_H := 90


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return ""
	return "the shadow eye rig is still running"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "await":
		return "idle"
	var rig := ShadowRig.new()
	rig.gm = base.get("_game_map")
	rig.step = step
	rig.mode = action
	rig.process_priority = 1000
	base.get_tree().root.add_child(rig)
	return "%s %s started" % [action, String(step.get("name", ""))]


class ShadowRig:
	extends Node

	var gm: GameMap = null
	var step: Dictionary = {}
	var mode := "sweep"
	var _sun: DirectionalLight3D = null
	var _cam: Camera3D = null
	var _mms: Array[MultiMeshInstance3D] = []
	var _orig_margin := {}
	var _home_dist := 100.0
	var _orig_blend := false
	var _maxdist := 100.0
	var _dir := ""
	var _lines: Array[String] = []
	var _summary: Array[String] = []
	var _pos := Vector3.ZERO
	var _basis := Basis.IDENTITY

	func _ready() -> void:
		add_to_group(GROUP)
		_dir = ProjectSettings.globalize_path(String(step.get("dir", "user://render_jobs/sw")))
		DirAccess.make_dir_recursive_absolute(_dir)
		for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (node as DirectionalLight3D).shadow_enabled:
				_sun = node
				break
		if _sun == null:
			remove_from_group(GROUP)
			print("RJ| shadow_eye: no shadow-casting sun in the scene; nothing run")
			queue_free()
			return
		_home_dist = _sun.directional_shadow_max_distance
		_orig_blend = _sun.directional_shadow_blend_splits
		_maxdist = -1.0
		for node in get_tree().root.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := node as MultiMeshInstance3D
			_mms.append(mm)
			_orig_margin[mm] = mm.extra_cull_margin
		gm.get_camera_controller().set_process(false)
		_cam = gm.camera_node
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.fov = float(step.get("fov", 60.0))
		_cam.near = 0.05
		_cam.far = 2000.0
		_main()

	func _process(_delta: float) -> void:
		# A negative _maxdist leaves the distance to MapViewFit (the eye fit under perspective).
		if _sun != null and _maxdist >= 0.0:
			_sun.directional_shadow_max_distance = _maxdist
		if _cam != null:
			_cam.global_transform = Transform3D(_basis, _pos)

	func _main() -> void:
		var cfgs: Array = step.get("configs", [{"name": "a"}])
		match mode:
			"sweep":
				await _sweep(cfgs)
			"walk":
				await _walk(cfgs)
			"perf":
				await _perf(cfgs)
		_apply_cfg({})
		_sun.shadow_enabled = true
		_flush("report.txt", "summary.txt")
		var tag := "%s %s" % [mode, step.get("name", "")]
		print("RJ| shadow_eye %s done, %d lines, %s" % [tag, _lines.size(), _dir])
		queue_free()

	func _flush(report: String, summary: String) -> void:
		for pair in [[report, _lines], [summary, _summary]]:
			var f := FileAccess.open(_dir.path_join(pair[0]), FileAccess.WRITE)
			if f == null:
				continue
			for l in pair[1]:
				f.store_line(l)

	# ---- scene helpers ----

	func _apply_cfg(cfg: Dictionary) -> void:
		for mm in _mms:
			if is_instance_valid(mm):
				mm.extra_cull_margin = float(cfg.get("margin", _orig_margin[mm]))
		_maxdist = float(cfg.get("maxdist", -1.0))
		_sun.directional_shadow_blend_splits = bool(cfg.get("blend", _orig_blend))

	func _ground(xz: Vector2) -> Vector3:
		var space := gm.world_viewport.find_world_3d().direct_space_state
		var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0.0, xz.y))
		return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)

	func _eye_at(xz: Vector2) -> Vector3:
		return _ground(xz) + Vector3.UP * float(step.get("eye", 1.6))

	func _sun_yaw() -> float:
		var d := -_sun.global_basis.z
		return rad_to_deg(atan2(-d.x, d.z))

	func _yaw_of(v: Variant) -> float:
		return _sun_yaw() if typeof(v) == TYPE_STRING else float(v)

	func _pose(pos: Vector3, yaw: float, pitch: float) -> void:
		var y := deg_to_rad(yaw)
		var p := deg_to_rad(pitch)
		var look := Vector3(sin(y) * cos(p), -sin(p), -cos(y) * cos(p))
		var up := Vector3.UP if pitch < 89.5 else Vector3(sin(y), 0.0, -cos(y))
		_pos = pos
		_basis = Basis.looking_at(look, up)
		_cam.global_transform = Transform3D(_basis, _pos)

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _grab() -> Image:
		await RenderingServer.frame_post_draw
		return gm.world_viewport.get_texture().get_image()

	## Sun shadows on then off at the current pose; returns [on_image, S, meanS, litfrac].
	func _still_pair(settle: int) -> Array:
		_sun.shadow_enabled = true
		await _frames(settle)
		var on := await _grab()
		_sun.shadow_enabled = false
		await _frames(settle)
		var off := await _grab()
		_sun.shadow_enabled = true
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
		return [on, s, float(total) / float(W * H), float(lit) / float(W * H)]

	func _luma(image: Image) -> PackedByteArray:
		var small := image.duplicate() as Image
		small.convert(Image.FORMAT_L8)
		small.resize(W, H, Image.INTERPOLATE_BILINEAR)
		return small.get_data()

	## [largest 30 px block change of the mean S, block (bx, by)] between two S pictures.
	func _worst_block(a: PackedByteArray, b: PackedByteArray) -> Array:
		var worst := 0.0
		var at := Vector2i.ZERO
		for by in range(0, H - BLOCK + 1, BLOCK):
			for bx in range(0, W - BLOCK + 1, BLOCK):
				var sa := 0
				var sb := 0
				for y in BLOCK:
					var row := (by + y) * W + bx
					for x in BLOCK:
						sa += a[row + x]
						sb += b[row + x]
				var dm := absf(float(sa - sb)) / float(BLOCK * BLOCK)
				if dm > worst:
					worst = dm
					at = Vector2i(bx / BLOCK, by / BLOCK)
		return [worst, at]

	func _tile_s(s: PackedByteArray, w: int, h: int) -> Image:
		var scaled := s.duplicate()
		for k in W * H:
			scaled[k] = mini(255, int(s[k]) * 4)
		var img := Image.create_from_data(W, H, false, Image.FORMAT_L8, scaled)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		return img

	func _tile_on(on: Image, w: int, h: int) -> Image:
		var img := on.duplicate() as Image
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		return img

	func _sheet(tiles: Array, cols: int, w: int, h: int, fmt: Image.Format) -> Image:
		var rows := ceili(float(tiles.size()) / float(cols))
		var sheet := Image.create(cols * w, rows * h, false, fmt)
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		return sheet

	# ---- sweep ----

	func _sweep(cfgs: Array) -> void:
		var at := Vector2(float(step.at[0]), float(step.at[1]))
		var pos := _eye_at(at)
		var fine: Array = step.get("fine", [])
		var coarse: Array = step.get("coarse", [])
		var dist0 := _sun.directional_shadow_max_distance
		_lines.append(
			"sweep %s at %s eye pos %s fov %.0f scatter nodes %d sun maxdist %.0f"
			% [step.get("name", ""), str(at), str(pos), _cam.fov, _mms.size(), dist0]
		)
		for cfg: Dictionary in cfgs:
			_apply_cfg(cfg)
			await _frames(int(step.get("cfg_settle", 40)))
			for yv in step.get("yaws", [45]):
				var yaw := _yaw_of(yv)
				await _one_yaw(String(cfg.name), str(yv), yaw, pos, fine, coarse)

	func _one_yaw(
		cfg: String, ytag: String, yaw: float, pos: Vector3, fine: Array, coarse: Array
	) -> void:
		var settle := int(step.get("settle", 4))
		var prev := PackedByteArray()
		var prev_mean := 0.0
		var rows: Array = []
		var s_tiles: Array = []
		var on_tiles: Array = []
		var beyond := func(p: Variant) -> bool: return float(p) > float(fine.back())
		var seq: Array = fine + coarse.filter(beyond)
		for pitch_v in seq:
			var pitch := float(pitch_v)
			_pose(pos, yaw, pitch)
			var pair: Array = await _still_pair(settle)
			var s: PackedByteArray = pair[1]
			var worst: Array = [0.0, Vector2i.ZERO]
			if prev.size() == s.size():
				worst = _worst_block(s, prev)
			var step_deg := pitch - float(rows.back().pitch) if not rows.is_empty() else 0.0
			rows.append(
				{
					"pitch": pitch, "mean": pair[2], "lit": pair[3], "worst": worst[0],
					"at": worst[1], "step": step_deg, "dmean": pair[2] - prev_mean
				}
			)
			_lines.append(
				(
					"%s yaw %s(%.1f) pitch %.1f step %.0f meanS %.3f lit %.4f dMean %.3f "
					+ "worstBlock %.2f at %s maxd %.0f"
				)
				% [
					cfg, ytag, yaw, pitch, step_deg, pair[2], pair[3],
					pair[2] - prev_mean, worst[0], str(worst[1]),
					_sun.directional_shadow_max_distance
				]
			)
			prev = s
			prev_mean = pair[2]
			if pitch <= float(fine.back()):
				s_tiles.append(_tile_s(s, TILE_W, TILE_H))
				on_tiles.append(_tile_on(pair[0], TILE_W, TILE_H))
		_sheet(s_tiles, 6, TILE_W, TILE_H, Image.FORMAT_L8).save_png(
			_dir.path_join("sheet_s_%s_%s.png" % [cfg, ytag])
		)
		_sheet(on_tiles, 6, TILE_W, TILE_H, Image.FORMAT_RGB8).save_png(
			_dir.path_join("sheet_on_%s_%s.png" % [cfg, ytag])
		)
		_summarise(cfg, ytag, rows, float(fine.back()))

	## One summary line: the share at some pitches, the worst 1 degree step in the fine range and
	## the worst step in the coarse range (its size in degrees named).
	func _summarise(cfg: String, ytag: String, rows: Array, fine_max: float) -> void:
		var worst_f := 0.0
		var at_f := 0.0
		var worst_c := 0.0
		var at_c := 0.0
		var share := ""
		for r: Dictionary in rows:
			if float(r.pitch) in [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 45.0, 90.0]:
				share += " %d:%.1f%%" % [int(r.pitch), float(r.lit) * 100.0]
			if float(r.step) == 0.0:
				continue
			if float(r.pitch) <= fine_max and float(r.worst) > worst_f:
				worst_f = float(r.worst)
				at_f = float(r.pitch)
			elif float(r.pitch) > fine_max and float(r.worst) > worst_c:
				worst_c = float(r.worst)
				at_c = float(r.pitch)
		_summary.append(
			(
				"%s yaw %s | share(lit>10) by pitch%s | worst 1deg block change %.2f at pitch %.0f "
				+ "| worst coarse-step change %.2f at pitch %.0f"
			)
			% [cfg, ytag, share, worst_f, at_f, worst_c, at_c]
		)

	# ---- walk ----

	func _walk(cfgs: Array) -> void:
		var fps := int(step.get("fps", 30))
		var frames := int(float(step.get("seconds", 6.0)) * float(fps))
		var speed := float(step.get("speed", 3.0))
		var yaw := _yaw_of(step.get("yaw", 0.0))
		var pitch := float(step.get("pitch", 3.0))
		var at := Vector2(float(step.at[0]), float(step.at[1]))
		var fwd := Vector2(sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))
		for cfg: Dictionary in cfgs:
			_apply_cfg(cfg)
			await _frames(int(step.get("cfg_settle", 40)))
			var cname := String(cfg.name)
			# Pass 1: stepped S analysis per frame position.
			var prev := PackedByteArray()
			var s_all: Array = []
			var worst_k := 1
			var worst_v := -1.0
			for k in frames:
				_pose(_eye_at(at + fwd * speed * float(k) / float(fps)), yaw, pitch)
				var pair: Array = await _still_pair(2)
				var s: PackedByteArray = pair[1]
				s_all.append(s)
				var w := 0.0
				if k > 0:
					var wb := _worst_block(s, prev)
					w = wb[0]
					if w > worst_v:
						worst_v = w
						worst_k = k
				_lines.append(
					"walk %s frame %d meanS %.3f lit %.4f worstBlock %.2f" % [cname, k, pair[2], pair[3], w]
				)
				prev = s
			_summary.append(
				"walk %s: worst frame-to-frame S block change %.2f at frame %d"
				% [cname, worst_v, worst_k]
			)
			# Pass 2: the real clip, every drawn frame.
			var small: Array = []
			var clip_dir := _dir.path_join("clip_%s" % cname)
			DirAccess.make_dir_recursive_absolute(clip_dir)
			for k in frames:
				_pose(_eye_at(at + fwd * speed * float(k) / float(fps)), yaw, pitch)
				await get_tree().process_frame
				var img := await _grab()
				var half := _tile_on(img, 960, 540)
				half.save_png(clip_dir.path_join("%s_%04d.png" % [cname, k]))
				small.append(_tile_on(half, 480, 270))
			var first := clampi(worst_k - 4, 0, frames - 8)
			var tiles: Array = []
			for k in range(first, first + 8):
				tiles.append(small[k])
			for k in range(first, first + 8):
				tiles.append(_tile_s(s_all[k], 480, 270))
			_sheet_walk(cname, tiles, first)

	func _sheet_walk(cname: String, tiles: Array, first: int) -> void:
		var on_sheet := _sheet(tiles.slice(0, 8), 4, 480, 270, Image.FORMAT_RGB8)
		var s_sheet := _sheet(tiles.slice(8, 16), 4, 480, 270, Image.FORMAT_L8)
		s_sheet.convert(Image.FORMAT_RGB8)
		var all := Image.create(1920, 1080, false, Image.FORMAT_RGB8)
		all.blit_rect(on_sheet, Rect2i(0, 0, 1920, 540), Vector2i(0, 0))
		all.blit_rect(s_sheet, Rect2i(0, 0, 1920, 540), Vector2i(0, 540))
		all.save_png(_dir.path_join("sheet_walk_%s.png" % cname))
		_summary.append("walk %s sheet frames %d..%d (lit above, S x4 below)" % [cname, first, first + 7])

	# ---- perf ----

	func _median(a: Array) -> float:
		var b := a.duplicate()
		b.sort()
		return float(b[b.size() / 2]) if not b.is_empty() else 0.0

	func _perf(cfgs: Array) -> void:
		var at := Vector2(float(step.at[0]), float(step.at[1]))
		var pos := _eye_at(at)
		var yaw := _yaw_of(step.get("yaw", 45.0))
		var frames := int(step.get("frames", 90))
		var rid := gm.world_viewport.get_viewport_rid()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(rid, true)
		for pitch_v in step.get("pitches", [0.0]):
			_pose(pos, yaw, float(pitch_v))
			var gpu := {}
			var cpu := {}
			for cfg: Dictionary in cfgs:
				gpu[cfg.name] = []
				cpu[cfg.name] = []
			for round_i in int(step.get("rounds", 4)):
				for cfg: Dictionary in cfgs:
					_apply_cfg(cfg)
					for n in frames:
						await get_tree().process_frame
						if n >= 20:
							var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
							var c := RenderingServer.viewport_get_measured_render_time_cpu(rid)
							gpu[cfg.name].append(g)
							cpu[cfg.name].append(c)
			for cfg: Dictionary in cfgs:
				var line := (
					"perf pitch %.0f %s gpu %.3f ms cpu-render %.3f ms (medians of %d frames)"
					% [
						float(pitch_v), cfg.name, _median(gpu[cfg.name]),
						_median(cpu[cfg.name]), gpu[cfg.name].size()
					]
				)
				_summary.append(line)
				print("RJ| " + line)
