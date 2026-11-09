extends RefCounted

## Authoring performance audit probe (topic perfaudit, stream authoring, 2026-11-09; plan in
## docs/plans/2026-11-09-perfaudit/PLAN.md, findings in its findings/authoring.md). One harness
## for every in-game editing tool: it records each frame of a stroke or an action with the main
## thread's parts, says what was rebuilt, and times the map-proportional pieces (whole-map
## uploads, collision, autosave, save and open) on the open map, so a stroke on a 320 ft map can
## be compared with the same stroke on a 100 ft map in one run.
##
## Actions (`action`):
##   rec {mode "begin", name} / {mode "end"}  records every frame between begin and end: the
##       CPU frame time, process time, the world viewport's GPU time, and per frame the main
##       thread's parts (read from the editor's and the terrain's last_*_usec, zeroed after each
##       read, so a frame shows only its own work), the chunks updated, the scatter cells landed,
##       the ground and collision updates. Splits the frames into pressed (the brush down) and
##       tail (after the release, until nothing regenerates, grows or waits on height work), and
##       times press -> first edit applied and release -> settled. `end` logs one row and keeps
##       it for `table`.
##   micro {reps (5), tag}  times the map-proportional pieces on the open map, `reps` rounds
##       interleaved: the four index maps' whole upload, a 4 m broad-tint update (whole refilter
##       and upload), the flush's ground update of a 4 m rect, the collision rebuild, the height
##       texture, the collision heights, a 4 m rule-field pass, the autosave's scene sync, the
##       document's serialize, write and read (with the file size). Writes under
##       user://_perfaudit_tmp/ and removes the file.
##   mem {tag}  the document's arrays by size, the history's bytes, the look bake's and the
##       steep bake's viewports, and the engine's texture and static memory.
##   undo {count (3)}  times `count` undos, then as many redos (each call's main-thread ms).
##   rebake  forces the ground look's rebake (GroundLookBake.sync(true)): the CPU side is
##       logged; the frames after it belong to an enclosing rec.
##   table {dir}  writes every row recorded so far to `<dir>/perfaudit_rows.txt` (default the
##       job's folder, user://render_jobs/perfaudit_authoring).

const TMP_DIR := "user://_perfaudit_tmp/"

static var _rows: Array[String] = []
static var _recorder: Node = null


static func run(root: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	var c: AuthoringController = root.get("_authoring_controller")
	if action != "table" and (c == null or not is_instance_valid(c) or c.editor == null):
		return "no authoring map open"
	match action:
		"rec":
			if String(step.get("mode", "begin")) == "begin":
				if is_instance_valid(_recorder):
					_recorder.queue_free()
				var rec := Recorder.new()
				rec.label = String(step.get("name", "rec"))
				rec.setup(c, root.get("_game_map"))
				_recorder = rec
				root.add_child(rec)
				return "recording " + rec.label
			if not is_instance_valid(_recorder):
				return "no recording"
			var row: String = _recorder.call("finish")
			_recorder.queue_free()
			_recorder = null
			_rows.append(row)
			return row
		"micro":
			return _micro(c, int(step.get("reps", 5)), String(step.get("tag", "")))
		"mem":
			return _mem(c, String(step.get("tag", "")))
		"undo":
			return _undo(c, int(step.get("count", 3)))
		"rebake":
			var look := c.editor.terrain.ground_look() if c.editor.terrain else null
			if look == null:
				return "no ground look on this map"
			var t := Time.get_ticks_usec()
			look.sync(true)
			return (
				"rebake: call %.2f ms, bake cpu %.2f ms, bakes %d"
				% [(Time.get_ticks_usec() - t) / 1000.0, look.last_bake_usec / 1000.0, look.bakes]
			)
		"table":
			var dir := String(step.get("dir", "user://render_jobs/perfaudit_authoring"))
			DirAccess.make_dir_recursive_absolute(dir)
			var path := dir.path_join("perfaudit_rows.txt")
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return "table: cannot write %s" % path
			f.store_string("\n".join(_rows) + "\n")
			f.close()
			return "table: %d rows in %s" % [_rows.size(), ProjectSettings.globalize_path(path)]
	return "unknown action %s" % step.get("action", "")


static func _median(values: PackedFloat64Array) -> float:
	return PerfauditStats.median(values)


## Times `fn` once, in ms.
static func _time(fn: Callable) -> float:
	var t := Time.get_ticks_usec()
	fn.call()
	return (Time.get_ticks_usec() - t) / 1000.0


static func _micro(c: AuthoringController, reps: int, tag: String) -> String:
	var doc := c.editor.document
	var terrain := c.editor.terrain
	if terrain == null:
		return "micro: no authored terrain"
	var binding := terrain.layer_binding()
	var size := Vector2i(doc.samples_x(), doc.samples_z())
	var step := doc.sample_step()
	# A 4 m brush's rect at the map centre.
	var half := ceili(4.0 / step.x)
	var centre := size / 2
	var rect := Rect2i(centre - Vector2i(half, half), Vector2i(half, half) * 2)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR + "map.ttmap"
	var heights := TerrainMeshBuilder.collision_heights(doc)
	var pieces := {
		"upload_index (4 maps, whole)": binding.upload_index,
		"broad_update 4 m (whole refilter + upload)": binding._update_broad.bind(rect),
		"update_ground_region 4 m (flush)": terrain.update_ground_region.bind(rect),
		"update_collision (whole HeightMapShape3D)": terrain.update_collision,
		"height_texture (whole)": terrain._refresh_height_texture,
		"collision_heights (whole copy)": TerrainMeshBuilder.collision_heights.bind(doc),
		"rule_fields 4 m": func() -> void:
			TerrainRules.sample_fields(heights, size.x, size.y, step, rect.grow(8)),
		"autosave sync (_sync_document)": c._sync_document,
		"serialize": MapDocumentIO.serialize.bind(doc),
		"write (serialize + zip + rename)": MapDocumentIO.write.bind(doc, path),
		"read (unzip + parse)": MapDocumentIO.read.bind(path),
	}
	var times := {}
	for name in pieces:
		times[name] = PackedFloat64Array()
	# Appended through the subscript: a cast (`as`) would append to a copy of the packed array.
	for r in reps:
		for name in pieces:
			times[name].append(_time(pieces[name]))
	var file_bytes := 0
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		file_bytes = f.get_length()
		f.close()
		DirAccess.remove_absolute(path)
	var lines := PackedStringArray()
	lines.append(
		(
			"micro %s: %d x %d samples (%.1f m), ttmap %.2f MB, reps %d, median [min..max] ms"
			% [tag, size.x, size.y, doc.extent_m().x, file_bytes / 1048576.0, reps]
		)
	)
	for name in pieces:
		var t: PackedFloat64Array = times[name]
		var s := t.duplicate()
		s.sort()
		lines.append("  %s: %.2f [%.2f..%.2f]" % [name, _median(t), s[0], s[s.size() - 1]])
	for line in lines:
		_rows.append(line)
	# Returned whole, so the job's log.txt keeps it (the console output is filtered).
	return " || ".join(lines)


## Bytes held by a value: packed arrays by their element size, dictionaries summed.
static func _bytes_of(value: Variant) -> int:
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY:
			return (value as PackedByteArray).size()
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY:
			return value.size() * 4
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return value.size() * 8
		TYPE_DICTIONARY:
			var total := 0
			for key in value:
				total += _bytes_of(value[key])
			return total
	return 0


static func _mem(c: AuthoringController, tag: String) -> String:
	var doc := c.editor.document
	var parts := PackedStringArray()
	var total := 0
	for prop in doc.get_property_list():
		var bytes := _bytes_of(doc.get(prop.name))
		if bytes >= 1024:
			parts.append("%s %.0f kB" % [prop.name, bytes / 1024.0])
			total += bytes
	var look_text := "no look"
	var look := c.editor.terrain.ground_look() if c.editor.terrain else null
	if look != null:
		var slots := PackedStringArray()
		var look_bytes := 0
		for vp: SubViewport in look.get("_viewports"):
			slots.append("%dx%d" % [vp.size.x, vp.size.y])
			look_bytes += vp.size.x * vp.size.y * 4
		var steep: SubViewport = look.get("_steep")
		var steep_text := "none"
		if steep != null:
			steep_text = "%dx%d" % [steep.size.x, steep.size.y]
			look_bytes += steep.size.x * steep.size.y * 4
		look_text = (
			"look slots %s, steep %s, %.1f MB (RGBA8, one buffer each)"
			% [",".join(slots), steep_text, look_bytes / 1048576.0]
		)
	var line := (
		(
			"mem %s: document arrays %.1f MB (%s); history %.2f MB in %d entries; %s;"
			+ " texture mem %.0f MB, video %.0f MB, static %.0f MB"
		)
		% [
			tag,
			total / 1048576.0,
			", ".join(parts),
			c.editor.history.held_bytes() / 1048576.0,
			c.editor.history.undo_count(),
			look_text,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		]
	)
	_rows.append(line)
	return line


static func _undo(c: AuthoringController, count: int) -> String:
	var history := c.editor.history
	var undos := PackedStringArray()
	var redos := PackedStringArray()
	# Lambdas capture locals by value, so the label comes back through an array.
	var out := [""]
	for i in count:
		if not history.can_undo():
			break
		var ms := _time(func() -> void: out[0] = history.undo())
		undos.append("%s %.1f" % [out[0], ms])
	for i in undos.size():
		if not history.can_redo():
			break
		var ms := _time(func() -> void: out[0] = history.redo())
		redos.append("%s %.1f" % [out[0], ms])
	var line := "undo ms: %s | redo ms: %s" % [", ".join(undos), ", ".join(redos)]
	_rows.append(line)
	return line


## Records frames and parts between rec begin and rec end (see the header).
class Recorder:
	extends Node

	## A frame over this is a hitch (ms).
	const HITCH_MS := [16.7, 33.3, 50.0]
	## A part under this did no work that frame (microseconds).
	const IDLE_USEC := 50
	## Main-thread parts read each frame: [label, where, property]. `where` names the object.
	const PARTS := [
		["dab", "editor", "last_dab_usec"],
		["flush", "editor", "last_flush_usec"],
		["ground", "terrain", "last_biome_update_usec"],
		["broad", "terrain", "last_broad_update_usec"],
		["heights", "terrain", "last_heights_usec"],
		["fields", "terrain", "last_fields_usec"],
		["h_terrain", "heights", "last_terrain_usec"],
		["h_snap", "heights", "last_snap_usec"],
		["collision", "heights", "last_collision_usec"],
		["land", "scatter", "last_apply_usec"],
		["water_build", "water", "last_build_usec"],
		["water_swap", "water", "last_swap_usec"],
		["cross_build", "crossings", "last_build_usec"],
		["settle_ref", "settlements", "last_refresh_usec"],
	]

	var label := ""
	var _objects := {}
	var _brush: BrushTool = null
	var _editor: AuthoringEditor = null
	var _scatter: AuthoredScatter = null
	var _terrain: AuthoredTerrain = null
	var _rid := RID()
	var _last := 0
	var _start := 0
	var _press := -1
	var _press_frame := -1
	var _first_edit := -1
	var _first_edit_frame := -1
	var _first_land := -1
	var _release := -1
	var _settled := -1
	var _quiet := 0
	var _frame := 0
	var _frames := {"pressed": PackedFloat64Array(), "tail": PackedFloat64Array()}
	var _gpu := PackedFloat64Array()
	var _compiled := 0
	var _proc := PackedFloat64Array()
	var _render_cpu := PackedFloat64Array()
	var _worst_ms := 0.0
	var _worst_parts := ""
	var _parts := {}
	var _counts := {"chunks": 0, "cells": 0, "ground_updates": 0, "collisions": 0}

	func setup(c: AuthoringController, game_map: Node) -> void:
		_editor = c.editor
		_brush = c.brush
		_scatter = c.scatter
		_terrain = c.editor.terrain
		_objects = {
			"editor": _editor,
			"terrain": _terrain,
			"heights": _editor.heights,
			"scatter": _scatter,
			"water": null,
			"crossings": null,
			"settlements": null,
		}
		if _terrain != null and _terrain.get_parent() != null:
			for child in _terrain.get_parent().get_children():
				if child is AuthoredWater:
					_objects.water = child
				elif child is AuthoredCrossings:
					_objects.crossings = child
				elif child is AuthoredSettlements:
					_objects.settlements = child
		for part: Array in PARTS:
			_parts[part[0]] = PackedFloat64Array()
		if game_map != null and game_map.get("world_viewport") != null:
			_rid = (game_map.get("world_viewport") as Viewport).get_viewport_rid()
		_zero_parts()

	## Pipeline compilations so far (every kind): a first use compiles on the main thread.
	static func compilations() -> int:
		var total := 0
		for info in [
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION,
		]:
			total += RenderingServer.get_rendering_info(info)
		return total

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		# After every other node, so a frame's dabs, flushes and landings are all in it.
		process_priority = 1000
		_compiled = compilations()
		_start = Time.get_ticks_usec()
		_last = _start
		if _scatter != null:
			_scatter.cells_applied.connect(_on_applied)

	func _exit_tree() -> void:
		if _scatter != null and _scatter.cells_applied.is_connected(_on_applied):
			_scatter.cells_applied.disconnect(_on_applied)

	func _on_applied(cells: Array[Vector2i]) -> void:
		_counts.cells += cells.size()
		if _press >= 0 and _first_land < 0:
			_first_land = Time.get_ticks_usec()

	func _zero_parts() -> void:
		for part: Array in PARTS:
			var obj: Object = _objects.get(part[1])
			if obj != null and is_instance_valid(obj):
				obj.set(part[2], 0)

	func _busy() -> bool:
		return (
			(_scatter != null and (_scatter.is_regenerating() or _scatter.is_growing()))
			or _editor.has_height_work()
			or _editor.water.is_working()
		)

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - _last) / 1000.0
		_last = now
		_frame += 1
		var pressed := _brush != null and _brush.pressed
		if _press < 0 and pressed:
			_press = now
			_press_frame = _frame
		if _press >= 0 and _release < 0 and not pressed:
			_release = now
		var any_edit := false
		var here := PackedStringArray()
		for part: Array in PARTS:
			var obj: Object = _objects.get(part[1])
			if obj == null or not is_instance_valid(obj):
				continue
			var usec := int(obj.get(part[2]))
			# Some parts are written on every call, idle ones with a few microseconds.
			if usec > IDLE_USEC:
				_parts[part[0]].append(usec / 1000.0)
				here.append("%s %.1f" % [part[0], usec / 1000.0])
				if part[0] in ["flush", "heights", "h_terrain", "water_build", "cross_build"]:
					any_edit = true
		if _terrain != null:
			_counts.chunks += _terrain.last_heights_chunks if _terrain.last_heights_usec > 0 else 0
			_counts.ground_updates += 1 if _terrain.last_biome_update_usec > 0 else 0
		_counts.collisions += 1 if int(_editor.heights.last_collision_usec) > 200 else 0
		if _press >= 0 and _first_edit < 0 and any_edit:
			_first_edit = now
			_first_edit_frame = _frame
		_zero_parts()
		# The engine's own split of the frame before this one: process (every _process), the
		# render's CPU setup and the world viewport's CPU render time.
		var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var setup := RenderingServer.get_frame_setup_time_cpu()
		var render_cpu := (
			RenderingServer.viewport_get_measured_render_time_cpu(_rid) if _rid.is_valid() else 0.0
		)
		if _frame > 2:
			_proc.append(proc)
			_render_cpu.append(setup + render_cpu)
		if _frame > 2 and ms > _worst_ms:
			_worst_ms = ms
			_worst_parts = (
				"%.1f ms (process %.1f, render cpu %.1f): %s"
				% [ms, proc, setup + render_cpu, ", ".join(here) if not here.is_empty() else "no part"]
			)
		if _frame > 2:
			_frames["tail" if _release >= 0 or _press < 0 else "pressed"].append(ms)
			if _rid.is_valid():
				_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid))
		if _release >= 0 and _settled < 0:
			_quiet = 0 if _busy() else _quiet + 1
			if _quiet >= 3:
				_settled = now

	## The row for this recording (see the header).
	func finish() -> String:
		var all := PackedFloat64Array(_frames.pressed)
		all.append_array(_frames.tail)
		var hitches := PackedStringArray()
		for limit: float in HITCH_MS:
			var n := 0
			for v in all:
				if v > limit:
					n += 1
			hitches.append(str(n))
		var parts := PackedStringArray()
		for part: Array in PARTS:
			var v: PackedFloat64Array = _parts[part[0]]
			if v.is_empty():
				continue
			var total := 0.0
			for x in v:
				total += x
			parts.append("%s %s (n %d, sum %.0f)" % [part[0], PerfauditStats.short(v), v.size(), total])
		var rel := func(t: int, base: int) -> String:
			return "-" if t < 0 or base < 0 else "%.0f" % ((t - base) / 1000.0)
		return (
			(
				"%s | pressed %s (n %d) | tail %s (n %d) | all p99/max %s | >16.7/33/50: %s | gpu med %.2f"
				+ " | process %s, render cpu %s"
				+ " | press->edit %s ms (%s frames) | press->first land %s | release->settled %s"
				+ " | chunks %d, cells %d, ground updates %d, collisions %d, pipelines compiled %d"
				+ " | worst %s | %s"
			)
			% [
				label,
				PerfauditStats.full(_frames.pressed),
				_frames.pressed.size(),
				PerfauditStats.full(_frames.tail),
				_frames.tail.size(),
				PerfauditStats.tail(all),
				"/".join(hitches),
				PerfauditStats.median(_gpu),
				PerfauditStats.full(_proc),
				PerfauditStats.full(_render_cpu),
				rel.call(_first_edit, _press),
				str(_first_edit_frame - _press_frame) if _first_edit_frame >= 0 else "-",
				rel.call(_first_land, _press),
				rel.call(_settled, _release),
				_counts.chunks,
				_counts.cells,
				_counts.ground_updates,
				_counts.collisions,
				compilations() - _compiled,
				_worst_parts,
				"; ".join(parts),
			]
		)


## Formatting helpers the Recorder (an inner class, which cannot call the outer statics
## without a preload) uses.
class PerfauditStats:
	static func median(values: PackedFloat64Array) -> float:
		if values.is_empty():
			return 0.0
		var s := values.duplicate()
		s.sort()
		return s[floori(s.size() * 0.5)]

	static func full(values: PackedFloat64Array) -> String:
		if values.is_empty():
			return "-"
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		return (
			"%.2f / %.2f / %.2f / %.2f"
			% [
				s[floori(n * 0.5)],
				s[mini(floori(n * 0.95), n - 1)],
				s[mini(floori(n * 0.99), n - 1)],
				s[n - 1]
			]
		)

	static func tail(values: PackedFloat64Array) -> String:
		if values.is_empty():
			return "-"
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		return "%.1f/%.1f" % [s[mini(floori(n * 0.99), n - 1)], s[n - 1]]

	static func short(values: PackedFloat64Array) -> String:
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		return "med %.2f max %.2f" % [s[floori(n * 0.5)], s[n - 1]]
