extends Node

## Render-job driver, added to the tree by run.gd. Runs a job (Array of step Dictionaries)
## over real frames and sets root meta "render_job_done" to a summary when finished. Logs
## every step to out_dir/log.txt (appended). The ops are documented in README.md.

var steps: Array = []
var out_dir: String = ""
var root_node: Node = null
var frames: PackedFloat64Array = []
var _i: int = -1
var _state: Dictionary = {}
var _log: PackedStringArray = []
var _last_usec: int = 0
var _recording: bool = false
var _rec_name: String = ""
var _rec_extra: Array = []
var _captures: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	_last_usec = Time.get_ticks_usec()
	get_tree().root.set_meta("render_job_done", "")
	_next()


func log_line(s: String) -> void:
	_log.append(s)
	print("RJ| " + s)
	var path := out_dir.path_join("log.txt")
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_line(s)
	f.close()


func gm() -> GameMap:
	return root_node.get("_game_map") as GameMap


func ctrl() -> AuthoringController:
	return root_node.get("_authoring_controller") as AuthoringController


func _next() -> void:
	_i += 1
	_state = {"t": 0.0, "phase": 0}
	if _i >= steps.size():
		get_tree().root.set_meta(
			"render_job_done", "\n".join(_log) if not _log.is_empty() else "ok"
		)
		queue_free()
		return
	var step: Dictionary = steps[_i]
	log_line("step %d %s" % [_i, JSON.stringify(step)])


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	if _recording:
		frames.append(frame_ms)
		var mon := [
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),
		]
		_rec_extra.append(
			(
				"%.1f ms | pipe canvas %d mesh %d surface %d draw %d spec %d | proc %.1f"
				% [
					frame_ms,
					mon[0],
					mon[1],
					mon[2],
					mon[3],
					mon[4],
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				]
			)
		)
	if _i < 0 or _i >= steps.size():
		return
	var step: Dictionary = steps[_i]
	_state.t += delta
	var done := true
	match String(step.op):
		"title":
			root_node.call("change_state", 0)
		"new_map":
			root_node.call(
				"_begin_authoring",
				{
					"level": null,
					"new_map":
					{
						"size_ft": int(step.get("size", 200)),
						"biome_id": String(step.get("biome", "")),
						"seed": int(step.get("seed", 1234))
					},
					"return_to": &"title"
				}
			)
		"play":
			var level := LevelManager.load_level_folder(String(step.folder), false)
			root_node.call("_on_play_level_requested", level)
		"dress":
			# Opens an existing level in authoring (a GLB-only level opens as a dressing
			# layer). Nothing is written unless something saves.
			var dressed := LevelManager.load_level_folder(String(step.folder), false)
			root_node.call("_begin_authoring", {"level": dressed, "return_to": &"title"})
		"index":
			_write_index(step)
		"expand_biomes":
			# Inserts step.template once per palette biome (or per id in step.biomes),
			# "{biome}" and "{name}" filled in, so the job follows whatever palette is
			# installed.
			var added: Array = []
			var chosen: Array = step.get("biomes", [])
			for biome: Dictionary in PaletteLibrary.biomes():
				if not chosen.is_empty() and not chosen.has(biome.get("id", "")):
					continue
				var text := JSON.stringify(step.template)
				text = text.replace("{biome}", String(biome.get("id", "")))
				text = text.replace("{name}", String(biome.get("name", "")))
				added.append_array(JSON.parse_string(text))
			for k in added.size():
				steps.insert(_i + 1 + k, added[k])
			log_line("expanded into %d steps" % added.size())
		"expand_ab":
			# An in-run shader A/B: per entry of step.configs, swap the ground shader to that
			# version (probes/ground_perf.gd; "std" draws the chunks with perf.gd's
			# StandardMaterial3D instead) and sample step.s seconds (probes/perf.gd).
			var added: Array = []
			var perf := "res://tools/render_jobs/probes/perf.gd"
			var configs: Array = step.get("configs", [])
			for k in configs.size():
				var version := String(configs[k])
				var label := "%s %s #%d" % [step.get("label", ""), version, k]
				var std := version == "std"
				added.append({"op": "call", "script": perf, "action": "ground_std", "on": std})
				if not std:
					added.append(
						{
							"op": "call",
							"script": "res://tools/render_jobs/probes/ground_perf.gd",
							"action": "shader",
							"version": version
						}
					)
				added.append({"op": "wait", "s": 0.5})
				added.append({"op": "call", "script": perf, "action": "start", "name": label})
				added.append({"op": "wait", "s": float(step.get("s", 3.0))})
				added.append({"op": "call", "script": perf, "action": "stop"})
			for k in added.size():
				steps.insert(_i + 1 + k, added[k])
			log_line("expanded into %d steps" % added.size())
		"wait_ready":
			done = _wait_ready(step)
		"wait":
			done = _state.t >= float(step.get("s", 1.0))
		"no_autosave":
			var c := ctrl()
			if c:
				var timer: Timer = c.get("_autosave_timer")
				timer.stop()
				timer.paused = true
				for conn in timer.timeout.get_connections():
					timer.timeout.disconnect(conn.callable)
		"hide_ui":
			var c := ctrl()
			if c and c.panel:
				c.panel.visible = not bool(step.get("hide", true))
		"home":
			gm().get_camera_controller().call("_reset_camera_to_home")
		"zoom":
			var cc := gm().get_camera_controller()
			if step.has("size"):
				cc.set("_target_zoom", float(step.size))
			else:
				for _n in 60:
					cc.zoom_out_step()
		"look_at":
			# Pan so the screen centre looks at world XZ `at`.
			var cc := gm().get_camera_controller()
			var off: Vector2 = cc.call("_get_view_center_ground_offset")
			var holder := gm().cameraholder_node
			var at: Array = step.at
			holder.global_position = Vector3(
				float(at[0]) - off.x, holder.global_position.y, float(at[1]) - off.y
			)
		"stroke":
			done = _stroke(step)
		"release":
			# Ends a stroke left pressed by `release: false`, keeping the brush active.
			var brush := ctrl().brush
			brush.set("_pressed", false)
			brush.call("finish_gesture")
		"hover":
			# The Sculpt tool with `tile` over map point `at`, not pressed, `ctrl` held: the
			# cursor and its readout as an author sees them before pressing.
			var c := ctrl()
			var tiles := {
				"raise": HeightBrush.RAISE,
				"smooth": HeightBrush.SMOOTH,
				"flatten": HeightBrush.FLATTEN,
				"tier": HeightBrush.TIER,
			}
			c.call("_on_sculpt_selected", int(tiles.get(String(step.get("tile", "tier")), 0)))
			if step.has("radius"):
				c.brush.set_radius(float(step.radius))
			c.brush.set("_ctrl", bool(step.get("ctrl", false)))
			var at: Array = step.at
			_set_pointer(c.brush, Vector3(float(at[0]), 0.0, float(at[1])))
		"place":
			var c := ctrl()
			var rule := c.editor.species_rule(String(step.biome), String(step.species))
			if rule.is_empty():
				log_line("no species %s in %s; not placed" % [step.species, step.biome])
			else:
				var at: Array = step.at
				# Bedded on the terrain as the Place brush beds a press (P3-7: at Y = 0 a
				# prop placed in a sunken hollow hung its trunk in the air).
				var p: Vector3 = c.brush.call("_bedded", Vector3(float(at[0]), 0.0, float(at[1])))
				c.editor.place_prop(rule, p, Vector3.UP)
				c.editor.commit_prop_edit()
		"capture":
			done = _capture(step)
		"vsync_off":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			RenderingServer.viewport_set_measure_render_time(
				gm().world_viewport.get_viewport_rid(), true
			)
		"gpu":
			done = _gpu(step)
		"record":
			_recording = bool(step.get("on", true))
			if _recording:
				frames = PackedFloat64Array()
				_rec_extra = []
				_rec_name = String(step.get("name", "rec"))
			else:
				_dump_record()
		"eval":
			var e := Expression.new()
			e.parse(String(step.expr))
			var r: Variant = e.execute([], root_node, false)
			log_line("eval %s -> %s" % [step.expr, str(r)])
		"call":
			var script := load(String(step.script)) as GDScript
			if script == null or not script.can_instantiate():
				log_line("call %s FAILED to load; stopping the job" % step.script)
				_i = steps.size()
			else:
				log_line("call %s -> %s" % [step.script, str(script.call("run", root_node, step))])
		_:
			log_line("unknown op %s" % step.op)
	if done:
		_next()


func _wait_ready(step: Dictionary) -> bool:
	var settle := float(step.get("settle", 2.0))
	var g := gm()
	if g == null or not is_instance_valid(g):
		return false
	if g.call("_is_level_loading"):
		_state.t = 0.0
		return false
	var c := ctrl()
	if c != null:
		if not c.get("_is_open"):
			_state.t = 0.0
			return false
		if is_instance_valid(c.scatter) and (c.scatter.is_regenerating() or c.scatter.is_growing()):
			_state.t = 0.0
			return false
	return _state.t >= settle


func _stroke(step: Dictionary) -> bool:
	var c := ctrl()
	var brush := c.brush
	var points: Array = step.points
	if _state.phase == 0:
		var mode := String(step.get("mode", "paint"))
		brush.set_radius(float(step.get("radius", 4.0)))
		brush.set_flow(float(step.get("flow", 1.0)))
		_state.ctrl = mode == "clear"
		_state.shift = false
		if mode == "paint":
			c.call("_use_biome", String(step.biome))
			c.call("_select_tool", AuthoringPanel.TOOL_BIOME)
		elif mode == "sculpt":
			# The Sculpt tool through its tile, with the press's modifiers (P3-5).
			var tiles := {
				"raise": HeightBrush.RAISE,
				"smooth": HeightBrush.SMOOTH,
				"flatten": HeightBrush.FLATTEN,
				"tier": HeightBrush.TIER,
			}
			c.call("_on_sculpt_selected", int(tiles.get(String(step.get("tile", "raise")), 0)))
			_state.ctrl = bool(step.get("ctrl", false))
			_state.shift = bool(step.get("shift", false))
		elif mode == "surface":
			# The Paint tool through its tile (P3-6); Ctrl at the press erases paint.
			c.call("_on_paint_selected", String(step.get("surface", "")))
			_state.ctrl = bool(step.get("ctrl", false))
		else:
			c.call("_select_tool", AuthoringPanel.TOOL_THIN)
		_state.phase = 1
		_state.dist = 0.0
		# The modifiers held for the whole stroke (a `hover` step may have left Ctrl on).
		brush.set("_ctrl", _state.ctrl)
		brush.set("_shift", _state.shift)
		_set_pointer(brush, _point_at(points, 0.0))
		return false
	if _state.phase == 1:
		brush.set("_pressed", true)
		brush.set("_press_pending", true)
		brush.set("_press_ctrl", _state.ctrl)
		brush.set("_press_shift", _state.shift)
		_state.phase = 2
		return false
	var speed := float(step.get("speed", 6.0))
	var total := _length(points)
	_state.dist += speed * get_process_delta_time()
	var hold := float(step.get("hold", 0.0))
	if _state.dist >= total:
		_set_pointer(brush, _point_at(points, total))
		_state.held = float(_state.get("held", 0.0)) + get_process_delta_time()
		if _state.held < hold:
			return false
		if not bool(step.get("release", true)):
			# Still pressed at the end point (a capture mid-stroke); a `release` step ends it.
			return true
		if bool(step.get("keep_active", false)):
			brush.set("_pressed", false)
			brush.call("finish_gesture")
		else:
			brush.finish_gesture()
		return true
	_set_pointer(brush, _point_at(points, _state.dist))
	return false


func _set_pointer(brush: BrushTool, world: Vector3) -> void:
	# On sculptable ground the point is lifted onto the ground, so the pointer aims at the
	# map point on raised or sunken ground too (a still pointer then stays still).
	var c := ctrl()
	if c != null and c.editor != null and c.editor.can_sculpt():
		world.y = c.editor.ground_height_at(world)
	var screen := gm().camera_node.unproject_position(world)
	brush.set("_pointer", screen)
	brush.set("_has_pointer", true)


func _length(points: Array) -> float:
	var total := 0.0
	for k in range(1, points.size()):
		total += Vector2(points[k][0], points[k][1]).distance_to(
			Vector2(points[k - 1][0], points[k - 1][1])
		)
	return total


func _point_at(points: Array, d: float) -> Vector3:
	var left := d
	for k in range(1, points.size()):
		var a := Vector2(points[k - 1][0], points[k - 1][1])
		var b := Vector2(points[k][0], points[k][1])
		var seg := a.distance_to(b)
		if left <= seg or k == points.size() - 1:
			var p := a.lerp(b, clampf(left / maxf(seg, 0.0001), 0.0, 1.0))
			return Vector3(p.x, 0.0, p.y)
		left -= seg
	return Vector3(points[0][0], 0.0, points[0][1])


## Samples the SubViewport's GPU render time every frame for step.s seconds (after a
## 0.3 s settle) and logs the median under step.name.
func _gpu(step: Dictionary) -> bool:
	if _state.t < 0.3:
		_state.samples = PackedFloat64Array()
		return false
	var rid := gm().world_viewport.get_viewport_rid()
	var samples: PackedFloat64Array = _state.samples
	samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_state.samples = samples
	if _state.t < 0.3 + float(step.get("s", 2.0)):
		return false
	var sorted := samples.duplicate()
	sorted.sort()
	log_line(
		(
			"gpu %s: median %.3f ms, p10 %.3f, p90 %.3f, n %d"
			% [
				String(step.get("name", "")),
				sorted[sorted.size() / 2],
				sorted[sorted.size() / 10],
				sorted[sorted.size() * 9 / 10],
				sorted.size()
			]
		)
	)
	return true


func _capture(step: Dictionary) -> bool:
	if _state.phase == 0:
		_state.phase = 1
		RenderingServer.frame_post_draw.connect(_grab.bind(String(step.name)), CONNECT_ONE_SHOT)
	return _state.phase == 2


func _grab(name: String) -> void:
	var sub := gm().world_viewport.get_texture().get_image()
	sub.save_png(out_dir.path_join(name + "_sub.png"))
	var win := get_viewport().get_texture().get_image()
	win.save_png(out_dir.path_join(name + ".png"))
	var step: Dictionary = steps[_i]
	_captures.append(
		{"name": name, "desc": String(step.get("desc", "")), "zoom": gm().camera_node.size}
	)
	log_line(
		(
			"captured %s sub %s win %s zoom %.2f"
			% [name, sub.get_size(), win.get_size(), gm().camera_node.size]
		)
	)
	_state.phase = 2


## Writes out_dir/INDEX.md: step.title, step.intro, then one row per capture so far (the
## lo-fi composited window image, the raw SubViewport image, the camera size, the caption).
func _write_index(step: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("# " + String(step.get("title", "Render set")))
	lines.append("")
	lines.append(String(step.get("intro", "")))
	lines.append("")
	lines.append("| Image (lo-fi window) | Raw 3D view | Camera size | What |")
	lines.append("|---|---|---|---|")
	for entry in _captures:
		lines.append(
			(
				"| %s.png | %s_sub.png | %.1f | %s |"
				% [entry.name, entry.name, float(entry.zoom), String(entry.desc)]
			)
		)
	lines.append("")
	lines.append("Written %s." % Time.get_datetime_string_from_system())
	var f := FileAccess.open(out_dir.path_join("INDEX.md"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	log_line("index written with %d captures" % _captures.size())


func _dump_record() -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var worst := sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0
	var median := sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	log_line(
		(
			"record %s: %d frames, median %.1f ms, worst %.1f ms"
			% [_rec_name, frames.size(), median, worst]
		)
	)
	var f := FileAccess.open(out_dir.path_join(_rec_name + "_frames.txt"), FileAccess.WRITE)
	for line in _rec_extra:
		f.store_line(line)
	f.close()
