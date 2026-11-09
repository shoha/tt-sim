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
			GroundClipmap.attach(terrain)
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
		"cost":
			var crig := CostRig.new()
			crig.cm = GroundClipmap.of(terrain)
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


## Holds the clipmap's strips and windows drawing for 90 frames and logs their GPU ms (mean of
## the last 60): the cost of one column strip, one row strip and all the windows' blits.
class CostRig:
	extends Node

	var cm: GroundClipmap = null
	var tag := "cost"
	var _frames := 0
	var _sum := {"column": 0.0, "row": 0.0, "windows": 0.0}

	func _ready() -> void:
		if cm != null:
			cm.hold_drawing(true)

	func _process(_delta: float) -> void:
		_frames += 1
		if cm == null or _frames < 90:
			if cm == null:
				queue_free()
			return
		if _frames <= 150:
			var c := cm.drawing_cost_ms()
			for k: String in _sum:
				_sum[k] += float(c[k])
			if _frames < 150:
				return
		cm.hold_drawing(false)
		var n := 60.0
		(load(PROBE) as Script).call(
			"note",
			(
				"cost %s: column strip %.3f ms, row strip %.3f ms, all windows %.3f ms (%d levels)"
				% [tag, _sum.column / n, _sum.row / n, _sum.windows / n, cm.held_levels().size()]
			)
		)
		queue_free()


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
	var _gpu: Array[float] = []
	var _wall: Array[float] = []
	var _rid: RID

	func _ready() -> void:
		_rid = gm.world_viewport.get_viewport_rid()
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
		_gpu.clear()
		_wall.clear()
		if ab and cm != null:
			cm.read = _phase == 1

	func _process(delta: float) -> void:
		var dir := Vector3(float(step.get("dx", 0.0)), 0.0, float(step.get("dz", 0.0)))
		if _phase == 1:
			dir = -dir  # the way back: the same ground, the other read
		var holder := gm.cameraholder_node
		holder.global_position += dir * delta
		_t += delta
		var cm := GroundClipmap.of(terrain)
		var bake := cm.frame_bake_ms if cm != null and cm.read else 0.0
		_bake_total += bake
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid) + bake)
		_wall.append(delta * 1000.0)
		if _t < float(step.get("seconds", 4.0)):
			return
		var tag := String(step.get("tag", "pan"))
		if ab:
			tag += " read=" + ("on" if _phase == 1 else "off")
		_report(tag)
		if ab and _phase == 0:
			_phase = 1
			_begin()
			return
		RenderingServer.viewport_set_measure_render_time(_rid, false)
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
		text += "wall median %.2f max %.2f ms; strips %d, bake gpu %.2f ms total" % [
			w[n / 2], w[n - 1], (cm.jobs_done - _jobs0) if cm != null else 0, _bake_total
		]
		(load(PROBE) as Script).call("note", text)
