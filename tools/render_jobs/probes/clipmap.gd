extends RefCounted

## Render-job probe for the ground clipmap (card clipmap1, 2026-11-09; GroundClipmap).
##
##   {action: "on"}          GroundClipmap on (AuthoredTerrain.set_clipmap), shaders and windows.
##   {action: "off"}         off: the plain shaders, the windows freed.
##   {action: "read", on}    only the ground's shader (the windows keep baking): the A/B toggle.
##   {action: "await"}       holds the job until every held level is fully baked (or `max_s`).
##   {action: "view", view}  home, close (zoom 4), steep (zoom 8 on the steepest step), z20, far.
##   {action: "density"}     logs the screen's px per metre across the view.
##   {action: "stats", tag}  logs the levels held, their baked tiles, strips baked, memory.
##   {action: "pan", tag, dx, dz, seconds, frames?}  moves the camera pivot at (dx, dz) m/s for
##                           `seconds` and logs the world viewport's GPU ms per frame (mean, p95,
##                           max) and the wall frame time; holds the job while it runs.
##   {action: "pan_ab", tag, dx, dz, seconds}  the same twice, clipmap read off then on.
##   {action: "prepare", surface?}  binds a surface's ground layer ahead (before an edit).
##   {action: "edit", tag, size_m?, surface?, x?, z?, dir?}  one dab at the screen centre and the
##                           clipmap's reaction (see EditRig); `dir` saves the A-D crops.
##   {action: "cost", tag}   holds the strips and windows drawing and logs their GPU ms: the
##                           cost of one column strip, one row strip and all windows' blits.

const GROUP := "clipmap_probe_rig"
const PROBE := "res://tools/render_jobs/probes/clipmap.gd"

static var _waited := 0.0


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "await":
		return ""
	if not base.get_tree().get_nodes_in_group(GROUP).is_empty():
		return "the clipmap pan rig is still running"
	var gm: GameMap = base.get("_game_map")
	var cm := _clipmap(gm)
	if cm == null or cm.is_settled():
		_waited = 0.0
		return ""
	_waited += base.get_process_delta_time()
	if _waited > float(step.get("max_s", 60.0)):
		note("await: gave up after %.0f s, levels %s" % [_waited, str(cm.held_levels())])
		_waited = 0.0
		return ""
	return "the clipmap is still baking"


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	var gm: GameMap = base.get("_game_map")
	if gm == null:
		return "%s: no map open" % action
	var terrain := _terrain(gm)
	match action:
		"await":
			return "idle"
		"on":
			GroundClipmap.attach(terrain, true)
			return note("clipmap on")
		"off":
			GroundClipmap.detach(terrain)
			return note("clipmap off")
		"read":
			var cm := GroundClipmap.of(terrain)
			if cm != null:
				cm.read = bool(step.get("on", true))
			return "read %s" % str(step.get("on", true))
		"view":
			return _view(gm, step, base)
		"density":
			return _density(gm)
		"stats":
			return _stats(terrain, String(step.get("tag", "")))
		"edit":
			var erig := EditRig.new()
			erig.gm = gm
			erig.terrain = terrain
			erig.step = step
			erig.add_to_group(GROUP)
			base.get_tree().root.add_child(erig)
			return "edit started"
		"cliff":
			return _cliff(terrain, step)
		"prepare":
			terrain.prepare_surfaces(PackedStringArray([String(step.get("surface", "cobblestone"))]))
			return "prepare started"
		"cost":
			var crig := CostRig.new()
			crig.cm = GroundClipmap.of(terrain)
			crig.terrain = terrain
			crig.tag = String(step.get("tag", "cost"))
			crig.add_to_group(GROUP)
			base.get_tree().root.add_child(crig)
			return "cost started"
		"pan", "pan_ab":
			var rig := PanRig.new()
			rig.gm = gm
			rig.terrain = terrain
			rig.step = step
			rig.ab = action == "pan_ab"
			rig.add_to_group(GROUP)
			base.get_tree().root.add_child(rig)
			return "%s started" % action
	return "unknown action %s" % action


static func _terrain(gm: GameMap) -> AuthoredTerrain:
	return gm.world_viewport.find_child("AuthoredTerrain", true, false) as AuthoredTerrain


static func _clipmap(gm: GameMap) -> GroundClipmap:
	if gm == null:
		return null
	var t := _terrain(gm)
	return GroundClipmap.of(t) if t != null else null


static func _view(gm: GameMap, step: Dictionary, base: Node) -> String:
	var view := String(step.get("view", "home"))
	var cc := gm.get_camera_controller()
	cc.call("_reset_camera_to_home")
	var sizes := {"close": 4.0, "steep": 8.0, "z20": 20.0, "far": 99.0}
	if sizes.has(view):
		cc.set("_target_zoom", sizes[view])
	if view == "steep":
		var lf: Script = load("res://tools/render_jobs/probes/landform.gd")
		var landform := String(step.get("landform", "valley"))
		return lf.call("run", base, {"action": "look", "at": "steepest", "landform": landform})
	return "view %s" % view


## Raises a square plateau (`size_m` across, `h` metres, at `x`, `z`) with one-sample walls: a test
## cliff for the steep fallback, built the way a sculpt stroke does (queue, process, settle).
static func _cliff(terrain: AuthoredTerrain, step: Dictionary) -> String:
	var doc := terrain.document
	var h := float(step.get("h", 4.0))
	var half := float(step.get("size_m", 12.0)) * 0.5
	var at := Vector2(float(step.get("x", 0.0)), float(step.get("z", 0.0)))
	var low := Vector2i(doc.world_to_sample(at - Vector2(half, half)).round())
	var high := Vector2i(doc.world_to_sample(at + Vector2(half, half)).round())
	var rect := Rect2i(low, high - low).intersection(
		Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			doc.heights[doc.sample_index(x, z)] += h
	terrain.queue_heights(rect)
	terrain.process_heights()
	terrain.settle_heights()
	terrain.process_heights()
	terrain.update_collision_region(rect)
	return note("cliff: %s samples raised %.1f m" % [str(rect.size), h])


static func _density(gm: GameMap) -> String:
	var cam := gm.camera_node
	var vp := gm.world_viewport
	var centre := Vector2(vp.size) * 0.5
	var from := cam.project_ray_origin(centre)
	var dir := cam.project_ray_normal(centre)
	var p := from + dir * (-from.y / dir.y)
	var fwd := Vector3(dir.x, 0.0, dir.z).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var c := cam.unproject_position(p)
	var across := cam.unproject_position(p + right * 0.5).distance_to(c) * 2.0
	var along := cam.unproject_position(p + fwd * 0.5).distance_to(c) * 2.0
	return note(
		"density at %s: %.1f px/m across, %.1f along; viewport %s" % [str(p), across, along, str(vp.size)]
	)


static func _stats(terrain: AuthoredTerrain, tag: String) -> String:
	var cm := GroundClipmap.of(terrain)
	if cm == null:
		return note("stats %s: clipmap off" % tag)
	var parts: Array[String] = []
	for l in cm.held_levels():
		var v := cm.valid_tiles(l)
		parts.append("L%d %s" % [l, str(v)])
	var tex_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	return note(
		(
			"stats %s: levels %s; strips %d, rebakes %d; %.0f MB windows; texture mem %.0f MB"
			% [
				tag,
				", ".join(parts),
				cm.jobs_done,
				cm.rebakes,
				GroundClipmap.memory_bytes(cm.held_levels().size()) / 1048576.0,
				tex_mb / 1048576.0,
			]
		)
	)


## Prints `text` and appends it to the probe's log file.
static func note(text: String) -> String:
	var path := "user://render_jobs/clipmap1/probe_log.txt"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var f := FileAccess.open(path, mode)
	if f != null:
		f.seek_end()
		f.store_line(text)
	print("RJ| " + text)
	return text


## Paints a surface into a square of the ground under the screen centre (the way a brush dab
## does: the document, then update_ground_region) and follows the clipmap's reaction frame by
## frame: the corrected pixels with the hole open (A), with the hole forced shut so the stale
## windows show (B), the per-pixel truth (C), and the rebaked windows (D). Logs the mean and max
## level difference over a crop around the edit (A, B, D against C) and the time from the edit to
## the closed hole. The surface must be bound already (prepare_surfaces), else the dab also pays
## the layer bind.
class EditRig:
	extends Node

	var gm: GameMap = null
	var terrain: AuthoredTerrain = null
	var step: Dictionary = {}
	var cm: GroundClipmap = null
	var _f := 0
	var _crop := Rect2i()
	var _imgs: Dictionary = {}
	var _patches0 := 0
	var _call_usec := 0
	var _closed_f := -1
	var _rect := Rect2i()

	func _ready() -> void:
		cm = GroundClipmap.of(terrain)
		var doc := terrain.document
		var vp := gm.world_viewport
		var cam := gm.camera_node
		var centre := Vector2(vp.size) * 0.5
		var from := cam.project_ray_origin(centre)
		var dir := cam.project_ray_normal(centre)
		var p := from + dir * (-from.y / dir.y)
		var at := Vector2(float(step.get("x", p.x)), float(step.get("z", p.z)))
		var size_m := float(step.get("size_m", 4.0))
		var sample_step := doc.sample_step()
		var n := int(ceil(size_m / minf(sample_step.x, sample_step.y)))
		var c := Vector2i(doc.world_to_sample(at).round())
		_rect = Rect2i(c - Vector2i(n / 2, n / 2), Vector2i(n, n)).intersection(
			Rect2i(0, 0, doc.samples_x(), doc.samples_z())
		)
		var screen := cam.unproject_position(Vector3(at.x, 0.0, at.y))
		var half := Vector2i(220, 140)
		_crop = Rect2i(Vector2i(screen) - half, half * 2).intersection(Rect2i(Vector2i.ZERO, vp.size))
		_patches0 = cm.patches_done if cm != null else 0
		var slot := doc.ensure_surface(String(step.get("surface", "cobblestone")))
		for z in range(_rect.position.y, _rect.end.y):
			for x in range(_rect.position.x, _rect.end.x):
				doc.set_surface_weight(doc.sample_index(x, z), slot, 255)
		var t0 := Time.get_ticks_usec()
		terrain.update_ground_region(_rect)
		_call_usec = Time.get_ticks_usec() - t0

	func _process(_delta: float) -> void:
		_f += 1
		if cm == null:
			queue_free()
			return
		match _f:
			2:
				_grab("A")
			3:
				cm.hole_off = true
			5:
				_grab("B")
			6:
				cm.hole_off = false
				cm.read = false
			8:
				_grab("C")
			9:
				cm.read = true
		if _f > 9 and _closed_f < 0 and cm.patches_done > _patches0:
			_closed_f = _f
		if _closed_f >= 0 and _f == _closed_f + 3:
			_grab("D")
			_report()
			queue_free()
		elif _f > 600:
			_report()
			queue_free()

	func _grab(tag: String) -> void:
		var img := gm.world_viewport.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		_imgs[tag] = img.get_region(_crop)

	func _diff(tag: String) -> String:
		if not _imgs.has(tag) or not _imgs.has("C"):
			return "%s n/a" % tag
		var a: Image = _imgs[tag]
		var c: Image = _imgs["C"]
		var sum := 0.0
		var peak := 0
		var over4 := 0
		for y in a.get_height():
			for x in a.get_width():
				var pa := a.get_pixel(x, y)
				var pc := c.get_pixel(x, y)
				var d := maxi(
					maxi(int(absf(pa.r - pc.r) * 255.0), int(absf(pa.g - pc.g) * 255.0)),
					int(absf(pa.b - pc.b) * 255.0)
				)
				sum += d
				peak = maxi(peak, d)
				over4 += 1 if d > 4 else 0
		var n := float(a.get_width() * a.get_height())
		return "%s mean %.3f max %d over4 %.2f%%" % [tag, sum / n, peak, 100.0 * over4 / n]

	func _report() -> void:
		var text := (
			"edit %s: %d samples (%s), update_ground_region %.2f ms; closed after %d ms (%d frames); "
			% [
				String(step.get("tag", "edit")),
				_rect.get_area(),
				str(_rect.size),
				_call_usec / 1000.0,
				cm.last_patch_msec,
				_closed_f,
			]
		)
		text += "vs per-pixel over a %s crop: %s | %s | %s" % [
			str(_crop.size), _diff("A"), _diff("B"), _diff("D")
		]
		(load(PROBE) as Script).call("note", text)
		var dir := String(step.get("dir", ""))
		if dir != "":
			for tag: String in _imgs:
				(_imgs[tag] as Image).save_png("%s/edit_%s_%s.png" % [dir, String(step.get("tag", "e")), tag])


## Holds the clipmap's strips and windows drawing and logs the GPU ms of a strip (both passes) per
## held level and kind: each is placed over the level's centre column or row (the full block), 20
## frames to settle and the mean of the next 30. The share of the strip's rectangle over the map
## explains the spread (the empty part has nothing to shade).
class CostRig:
	extends Node

	const PER := 50

	var cm: GroundClipmap = null
	var terrain: AuthoredTerrain = null
	var tag := "cost"
	var _frames := 0
	var _plan: Array = []  # [level, kind]
	var _sum := 0.0
	var _lines: Array[String] = []

	func _ready() -> void:
		if cm == null:
			return
		for l in cm.held_levels():
			for kind in 2:
				_plan.append([l, kind])
		cm.hold_drawing(true)

	func _process(_delta: float) -> void:
		if cm == null:
			queue_free()
			return
		var i := _frames / PER
		var k := _frames % PER
		_frames += 1
		if i >= _plan.size():
			cm.hold_drawing(false)
			var windows := cm.drawing_cost_ms().windows as float
			_lines.append("windows (all held levels) %.3f ms" % windows)
			(load(PROBE) as Script).call(
				"note", "cost %s: %s" % [tag, "; ".join(PackedStringArray(_lines))]
			)
			queue_free()
			return
		var l: int = _plan[i][0]
		var kind: int = _plan[i][1]
		if k == 0:
			cm.place_strip(l, kind)
			_sum = 0.0
		elif k >= 20:
			var c := cm.drawing_cost_ms()
			_sum += float(c["column" if kind == 0 else "row"])
		if k == PER - 1:
			var rect := cm.strip_world_rect(l, kind)
			var ext := terrain.document.extent_m()
			var map := Rect2(-ext * 0.5, ext)
			var share := rect.intersection(map).get_area() / maxf(rect.get_area(), 1e-6)
			_lines.append(
				(
					"L%d %s %.3f ms (%.0f%% over the map)"
					% [l, "col" if kind == 0 else "row", _sum / float(PER - 20), share * 100.0]
				)
			)


## Moves the camera pivot and records the frame cost.
class PanRig:
	extends Node

	var gm: GameMap = null
	var terrain: AuthoredTerrain = null
	var step: Dictionary = {}
	var ab: bool = false
	var _phase := 0
	var _t := 0.0
	var _bake_total := 0.0
	var _jobs0 := 0
	var _jobs_seen := 0
	var _vsync := DisplayServer.VSYNC_ENABLED
	var _settling := false
	var _settle_s := 0.0
	var _trace: Array[float] = []  # the world viewport's GPU ms alone, per frame
	var _marks: Array[int] = []  # frames in which a strip was committed
	var _gpu: Array[float] = []
	var _wall: Array[float] = []
	var _rid: RID

	func _ready() -> void:
		_rid = gm.world_viewport.get_viewport_rid()
		# vsync on lets the GPU idle between frames and drop its clocks (steps of 2 ms in the world
		# time with nothing changing, seen in the first traces): the wall time of an unthrottled
		# frame is the cost.
		_vsync = DisplayServer.window_get_vsync_mode()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(_rid, true)
		var cm := GroundClipmap.of(terrain)
		if cm != null:
			cm.measure = true
		_begin()

	func _begin() -> void:
		_t = 0.0
		_bake_total = 0.0
		var cm := GroundClipmap.of(terrain)
		_jobs0 = cm.jobs_done if cm != null else 0
		_jobs_seen = _jobs0
		_trace.clear()
		_marks.clear()
		_gpu.clear()
		_wall.clear()
		if ab and cm != null:
			cm.read = _phase == 1

	func _process(delta: float) -> void:
		var dir := Vector3(float(step.get("dx", 0.0)), 0.0, float(step.get("dz", 0.0)))
		var holder := gm.cameraholder_node
		var cm := GroundClipmap.of(terrain)
		if _settling:
			# Back at the start for the second read, the clipmap catching up before it is timed.
			_settle_s += delta
			if (cm != null and cm.is_settled()) or _settle_s > 6.0:
				_settling = false
				_begin()
			return
		holder.global_position += dir * delta
		_t += delta
		var bake := cm.frame_bake_ms if cm != null and cm.read else 0.0
		_bake_total += bake
		var now_gpu := RenderingServer.viewport_get_measured_render_time_gpu(_rid)
		if cm != null and cm.jobs_done != _jobs_seen:
			_jobs_seen = cm.jobs_done
			_marks.append(_gpu.size())
		_trace.append(now_gpu)
		_gpu.append(now_gpu + bake)
		_wall.append(delta * 1000.0)
		if _t < float(step.get("seconds", 4.0)):
			return
		var tag := String(step.get("tag", "pan"))
		if ab:
			tag += " read=" + ("on" if _phase == 1 else "off")
		_report(tag)
		if ab and _phase == 0:
			_phase = 1
			# The same path again with the other read: put the camera back, let the clipmap settle.
			holder.global_position -= dir * _t
			_settling = true
			_settle_s = 0.0
			if cm != null:
				cm.read = true
			return
		RenderingServer.viewport_set_measure_render_time(_rid, false)
		DisplayServer.window_set_vsync_mode(_vsync)
		queue_free()

	func _report(tag: String) -> void:
		var g := _gpu.duplicate()
		var w := _wall.duplicate()
		g.sort()
		w.sort()
		var n := g.size()
		if n == 0:
			return
		var mean := 0.0
		for v: float in g:
			mean += v
		mean /= n
		var cm := GroundClipmap.of(terrain)
		var text := "pan %s: %d frames, gpu mean %.2f p95 %.2f max %.2f ms; " % [
			tag, n, mean, g[int(n * 0.95)], g[n - 1]
		]
		var wall_mean := 0.0
		for v: float in w:
			wall_mean += v
		wall_mean /= n
		text += "wall (vsync off) mean %.2f median %.2f p95 %.2f p99 %.2f max %.2f ms; " % [
			wall_mean, w[n / 2], w[int(n * 0.95)], w[int(n * 0.99)], w[n - 1]
		]
		text += "strips %d, bake gpu %.2f ms total" % [
			(cm.jobs_done - _jobs0) if cm != null else 0, _bake_total
		]
		(load(PROBE) as Script).call("note", text)
		if bool(step.get("trace", false)):
			var line := PackedStringArray()
			for v: float in _trace:
				line.append("%.2f" % v)
			(load(PROBE) as Script).call(
				"note",
				(
					"trace %s gpu ms per frame: %s | frames with a strip committed: %s"
					% [tag, " ".join(line), " ".join(PackedStringArray(_marks.map(str)))]
				)
			)
