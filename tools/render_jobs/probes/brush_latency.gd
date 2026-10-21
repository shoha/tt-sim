extends RefCounted

## Brush latency probe (card brush-latency, 2026-10-19; notes in
## D:/dev/tabletop/tt-sim/docs/plans/2026-10-19-brushland/latency.md). Times a brush's scatter
## regeneration from the press, per 10 m cell: when its generation was bumped (requests), when
## jobs were taken, cancelled and finished, and when rows were applied (provisionally, while
## the cell is still dirty, or for good). It also counts the rows each apply added and removed,
## the churn (rows one apply of this watch added and a later one removed), and samples the
## frame and process time from the press until the scatter settles.
##
## Actions (`action`):
##   live   `mode` "on" or "off": AuthoredScatter.live_applies on the authoring scatter (the
##          A/B switch; reported missing on a build without it).
##   watch  `name`, `dir`: watches the next press until the brush is released and the scatter
##          has settled (at most 12 s), then logs a summary and writes `<dir>/<name>.txt`.
##   film   `name`, `dir`, `seconds` (2.5), `crop` ([800, 450], centred), `scale` (0.8): keeps
##          the window's centre crop of every drawn frame (or one per `gap` ms) from the press
##          for `seconds` of real time, then writes it resampled to 30 fps as `<name>_<NNN>.png`.
##   busy   how many watches and films are still running.
##   native `mode` "on" or "off": the native scatter generator, or every job forced to GDScript
##          (ScatterNative.force_gdscript; card native-scatter); resets its job counts.
##   counts ScatterNative's jobs by outcome since the last "native".
##   mode   `mode` "gdscript" (every job forced to GDScript, lead jobs without ground cover),
##          "lead" (native, lead jobs without ground cover: card native-scatter's behaviour) or
##          "cover" (native, whole lead jobs: card native-cover); after new_map, since
##          attach_document sets whole_leads. Optional `interval` and `hold` (ms) set the live
##          throttle (ScatterRegen.live_interval_msec, live_hold_msec), and `landing` the
##          landing policy (ScatterApply; card native-cover round 2): "r2" (default), "b<usec>"
##          or "bnone" for another budget or none, "r1" and "r1u" round 1's landing and rebuild
##          with and without its one-lead cap, "lead" native-scatter as it was.
##   motion `mode` "today..." (the grow-in before the arrival motion, ScatterArrival.classic) or
##          anything else (the arrival motion; card motion).
##
## A watch also times the ground cover (species of the ground class): its first row, and when
## 90 % of the ground rows this watch added and that are there once it settles had appeared
## ("cover 90 %"), with the ground rows' own churn.

static var _running: Array[Node] = []


static func run(root: Node, step: Dictionary) -> String:
	var c: AuthoringController = root.get("_authoring_controller")
	var dir := String(step.get("dir", "user://render_jobs/brush_latency"))
	match String(step.get("action", "")):
		"live":
			if not "live_applies" in c.scatter:
				return "no live_applies on this build"
			c.scatter.set("live_applies", String(step.get("mode", "on")) == "on")
			return "live_applies %s" % str(c.scatter.get("live_applies"))
		"watch":
			DirAccess.make_dir_recursive_absolute(dir)
			var watcher := Watcher.new()
			watcher.label = String(step.get("name", "watch"))
			watcher.dir = dir
			watcher.scatter = c.scatter
			watcher.brush = c.brush
			_start(root, watcher)
			return "watching " + watcher.label
		"film":
			DirAccess.make_dir_recursive_absolute(dir)
			var filmer := Filmer.new()
			filmer.prefix = String(step.get("name", "film"))
			filmer.dir = dir
			filmer.seconds = float(step.get("seconds", 2.5))
			var crop: Array = step.get("crop", [800, 450])
			filmer.crop = Vector2i(int(crop[0]), int(crop[1]))
			filmer.scale = float(step.get("scale", 0.8))
			filmer.gap_msec = int(step.get("gap", 0))
			filmer.brush = c.brush
			_start(root, filmer)
			return "filming " + filmer.prefix
		"native":
			ScatterNative.force_gdscript = String(step.get("mode", "on")) != "on"
			ScatterNative.reset_counts()
			return "native %s (library %s)" % [str(ScatterNative.active()), ScatterNative.version()]
		"counts":
			return "jobs %s" % str(ScatterNative.fallbacks())
		"mode":
			var mode := String(step.get("mode", "cover"))
			ScatterNative.force_gdscript = mode == "gdscript"
			ScatterNative.reset_counts()
			var regen := c.scatter.get_regen()
			regen.whole_leads = mode == "cover" and ScatterNative.active()
			regen.live_interval_msec = int(step.get("interval", ScatterRegen.LIVE_INTERVAL_MSEC))
			regen.live_hold_msec = int(step.get("hold", ScatterRegen.LIVE_HOLD_MSEC))
			# Landing policy (card native-cover round 2): "r1" round 1's one lead a frame, "r1u"
			# round 1 uncapped (both with round 1's rebuild), "r2" round 2 at its budget,
			# "b<usec>" another budget, "bnone" none, "lead" native-scatter's leads under r2.
			# "lead": native-scatter as it was (restricted leads, round 1's landing, no cap).
			var landing := String(step.get("landing", "r2"))
			if landing == "lead":
				regen.whole_leads = false
			var applier: ScatterApply = c.scatter.landing
			applier.legacy = landing.begins_with("r1") or landing == "lead"
			applier.max_leads = 1 if landing == "r1" else -1
			applier.budget_usec = ScatterApply.BUDGET_USEC
			if applier.legacy or landing == "bnone":
				applier.budget_usec = -1
			elif landing.begins_with("b"):
				applier.budget_usec = int(landing.substr(1))
			applier.reset_counts()
			c.scatter.lean_rebuild = not applier.legacy
			return (
				"mode %s: native %s, whole leads %s, interval %d, hold %d, landing %s budget %d"
				% [
					mode,
					str(ScatterNative.active()),
					str(regen.whole_leads),
					regen.live_interval_msec,
					regen.live_hold_msec,
					landing,
					applier.budget_usec
				]
			)
		"motion":
			# Card motion: "today" the grow-in before STAGED + LIFE (ScatterArrival.classic), for
			# the in-run A/B and the side-by-side films; anything else the arrival motion.
			ScatterArrival.classic = String(step.get("mode", "arrival")).begins_with("today")
			return "motion classic %s" % str(ScatterArrival.classic)
		"busy":
			var busy := 0
			for node in _running:
				if is_instance_valid(node):
					busy += 1
			return "busy %d" % busy
	return "unknown action %s" % step.get("action", "")


static func _start(root: Node, node: Node) -> void:
	var alive: Array[Node] = []
	for other in _running:
		if is_instance_valid(other):
			alive.append(other)
	alive.append(node)
	_running = alive
	root.add_child(node)


## Watches one press of the brush and its regeneration (see the header).
class Watcher:
	extends Node

	var label := ""
	var dir := ""
	var scatter: AuthoredScatter = null
	var brush: BrushTool = null
	var _start := 0
	var _press := -1
	var _release := -1
	var _first_apply := -1
	var _first_final := -1
	var _first_growth := -1
	var _gen := {}
	## cell -> [count of frames with a request, first msec, last msec]
	var _requests := {}
	## cell -> Array of [kind, msec]: T taken, C cancel posted, D done, d done cancelled (each
	## with the job's worker ms), a provisional apply, A final apply.
	var _events := {}
	## task id -> {"cells", "cancelled"}
	var _jobs := {}
	## cell -> {asset id -> {row key -> msec added in this watch, 0 for rows already there}}
	var _rows := {}
	var _counts := {
		"applies": 0,
		"provisional": 0,
		"added": 0,
		"removed": 0,
		"churn": 0,
		"ground_churn": 0,
		"ground_rescaled": 0,
	}
	## row key -> its X and Z bits (see _keys_of).
	var _xz := {}
	## Asset ids of the ground class, in every registered biome.
	var _ground := {}
	var _first_ground := -1
	## Frame and process time while pressed, and after the release until settled.
	var _frame_ms := PackedFloat32Array()
	var _proc_ms := PackedFloat32Array()
	var _tail_ms := PackedFloat32Array()
	var _tail_proc_ms := PackedFloat32Array()
	var _apply_ms := PackedFloat32Array()
	var _last_usec := 0

	func _ready() -> void:
		# After every other node, so a frame's requests, takes and applies are all seen.
		process_priority = 1000
		_start = Time.get_ticks_msec()
		_last_usec = Time.get_ticks_usec()
		for cell in scatter.get("_cells") as Dictionary:
			_rows[cell] = _keys_of(cell)
		_gen = (scatter.get_regen().get("_generation") as Dictionary).duplicate()
		_refresh_ground()
		scatter.cells_applied.connect(_on_applied)

	## The ground assets of every biome registered so far (a biome registers on its first paint).
	func _refresh_ground() -> void:
		var biomes: Dictionary = scatter.get_regen().get("_biomes")
		for info: Dictionary in biomes.values():
			for rule: Dictionary in info.species:
				if rule.get("size_class", "") == ScatterRegen.GROUND_CLASS:
					for asset_id in rule.get("assets", []):
						_ground[String(asset_id)] = true

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_msec()
		var usec := Time.get_ticks_usec()
		if _press >= 0:
			var tail := _release >= 0
			(_tail_ms if tail else _frame_ms).append((usec - _last_usec) / 1000.0)
			var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			(_tail_proc_ms if tail else _proc_ms).append(proc)
		_last_usec = usec
		if _press < 0 and brush.pressed:
			_press = now
		if _press >= 0 and _release < 0 and not brush.pressed:
			_release = now
		var gens: Dictionary = scatter.get_regen().get("_generation")
		for cell in gens:
			if gens[cell] != _gen.get(cell, 0):
				_gen[cell] = gens[cell]
				var r: Array = _requests.get(cell, [0, now, now])
				r[0] += 1
				r[2] = now
				_requests[cell] = r
		var alive := {}
		for entry: Dictionary in scatter.get("_jobs"):
			var id: int = entry.id
			alive[id] = true
			if not _jobs.has(id):
				_jobs[id] = {"cells": entry.job.cells, "cancelled": false, "result": entry.result}
				_event(entry.job.cells, "T", now)
			if entry.get("cancelled", false) and not _jobs[id].cancelled:
				_jobs[id].cancelled = true
				_event(entry.job.cells, "C", now)
		for id in _jobs.keys():
			if not alive.has(id):
				# Done; the job's own worker time in brackets (the rest of take..done is queueing).
				var job_usec := float((_jobs[id].result as Dictionary).get("usec", 0))
				var worker_ms := roundi(job_usec / 1000.0)
				var kind := ("d" if _jobs[id].cancelled else "D") + "[%d]" % worker_ms
				_event(_jobs[id].cells, kind, now)
				_jobs.erase(id)
		if _first_growth < 0 and _press >= 0 and scatter.is_growing():
			_first_growth = now
		var settled := _release >= 0 and not scatter.is_regenerating() and not scatter.is_growing()
		if settled or now - _start > 12000:
			_finish(now, not settled)

	func _event(cells: Array, kind: String, now: int) -> void:
		for cell in cells:
			if not _events.has(cell):
				_events[cell] = []
			(_events[cell] as Array).append([kind, now])

	func _keys_of(cell: Vector2i) -> Dictionary:
		var out := {}
		var rows_by_asset: Dictionary = scatter.cell_rows(cell)
		var stride := MapDocument.ROW_STRIDE
		for asset_id in rows_by_asset:
			var rows: PackedFloat32Array = rows_by_asset[asset_id]
			var bits := rows.to_byte_array().to_int32_array()
			var row_keys := AuthoredScatter.row_keys(bits)
			var keys := {}
			for r in row_keys.size():
				keys[row_keys[r]] = 0
				# The row's X and Z bits: a removed row whose spot a new row holds was re-scaled.
				_xz[row_keys[r]] = (bits[r * stride] << 32) | (bits[r * stride + 2] & 0xFFFFFFFF)
			out[asset_id] = keys
		return out

	func _on_applied(cells: Array[Vector2i]) -> void:
		var now := Time.get_ticks_msec()
		_refresh_ground()
		var dirty: Dictionary = scatter.get_regen().get("_dirty")
		_apply_ms.append(scatter.last_apply_usec / 1000.0)
		if _press >= 0 and _first_apply < 0:
			_first_apply = now
		for cell in cells:
			var provisional := dirty.has(cell)
			_counts.applies += 1
			if provisional:
				_counts.provisional += 1
			elif _press >= 0 and _first_final < 0:
				_first_final = now
			_event([cell], "a" if provisional else "A", now)
			var old: Dictionary = _rows.get(cell, {})
			var fresh := _keys_of(cell)
			for asset_id in fresh:
				var before: Dictionary = old.get(asset_id, {})
				var keys: Dictionary = fresh[asset_id]
				for key in keys:
					if before.has(key):
						keys[key] = before[key]
					else:
						keys[key] = now
						_counts.added += 1
						if _press >= 0 and _first_ground < 0 and _ground.has(asset_id):
							_first_ground = now
			for asset_id in old:
				var after: Dictionary = fresh.get(asset_id, {})
				var after_xz := {}
				if _ground.has(asset_id):
					for key in after:
						after_xz[_xz.get(key, 0)] = true
				var keys: Dictionary = old[asset_id]
				for key in keys:
					if not after.has(key):
						_counts.removed += 1
						if int(keys[key]) > 0:
							_counts.churn += 1
							if _ground.has(asset_id):
								_counts.ground_churn += 1
								if after_xz.has(_xz.get(key, -1)):
									_counts.ground_rescaled += 1
			_rows[cell] = fresh

	func _rel(t: int, base: int) -> String:
		return "never" if t < 0 else "+%d" % (t - base)

	## "median / p95 / worst (n)" of `values`.
	static func _stats(values: PackedFloat32Array) -> String:
		if values.is_empty():
			return "none"
		var sorted := values.duplicate()
		sorted.sort()
		var n := sorted.size()
		var p95 := sorted[mini(floori(n * 0.95), n - 1)]
		return "%.2f / %.2f / %.2f (%d)" % [sorted[floori(n * 0.5)], p95, sorted[n - 1], n]

	func _finish(now: int, timed_out: bool) -> void:
		set_process(false)
		scatter.cells_applied.disconnect(_on_applied)
		var p := _press if _press >= 0 else _start
		var lines := PackedStringArray()
		lines.append(
			(
				"%s: release %s ms, first apply %s, first final apply %s, first growth %s, settled %s%s"
				% [
					label,
					_rel(_release, p),
					_rel(_first_apply, p),
					_rel(_first_final, p),
					_rel(_first_growth, p),
					_rel(now, p),
					" (TIMED OUT)" if timed_out else ""
				]
			)
		)
		lines.append(
			(
				"  applies %d (provisional %d); rows added %d, removed %d, churn %d; landing %s"
				% [
					_counts.applies,
					_counts.provisional,
					_counts.added,
					_counts.removed,
					_counts.churn,
					str(scatter.landing.counts)
				]
			)
		)
		scatter.landing.reset_counts()
		# Ground cover: when 90 % of the ground rows added in this watch and still there had appeared.
		var times := PackedInt32Array()
		for cell in _rows:
			for asset_id in _rows[cell]:
				if not _ground.has(asset_id):
					continue
				for key in _rows[cell][asset_id]:
					var t := int(_rows[cell][asset_id][key])
					if t > 0:
						times.append(t)
		times.sort()
		var cover90 := -1
		if times.size() > 0:
			cover90 = times[mini(floori(times.size() * 0.9), times.size() - 1)]
		lines.append(
			(
				(
					"  ground: first row %s, cover 50%% %s, 90%% %s (%d rows added and kept),"
					+ " ground churn %d (re-scaled in place %d)"
				)
				% [
					_rel(_first_ground, p),
					_rel(times[floori(times.size() * 0.5)] if times.size() > 0 else -1, p),
					_rel(cover90, p),
					times.size(),
					_counts.ground_churn,
					_counts.ground_rescaled
				]
			)
		)
		lines.append(
			(
				"  pressed: frame ms %s, process ms %s; tail: frame ms %s, process ms %s; set_cells ms %s"
				% [
					_stats(_frame_ms),
					_stats(_proc_ms),
					_stats(_tail_ms),
					_stats(_tail_proc_ms),
					_stats(_apply_ms)
				]
			)
		)
		var cells := _events.keys()
		cells.sort()
		for cell in cells:
			var r: Array = _requests.get(cell, [0, p, p])
			var parts := PackedStringArray()
			for e in _events[cell]:
				parts.append("%s%d" % [e[0], int(e[1]) - p])
			lines.append(
				(
					"  cell %s: %d request frames %s..%s | %s"
					% [cell, r[0], _rel(r[1], p), _rel(r[2], p), " ".join(parts)]
				)
			)
		var f := FileAccess.open(dir.path_join(label + ".txt"), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
			f.close()
		print("RJ| latency " + lines[0])
		print("RJ| latency " + lines[1].strip_edges())
		print("RJ| latency " + lines[2].strip_edges())
		print("RJ| latency " + lines[3].strip_edges())
		queue_free()


## Films the window's centre crop from the press (see the header).
class Filmer:
	extends Node

	var prefix := "film"
	var dir := ""
	var seconds := 2.5
	var crop := Vector2i(800, 450)
	var scale := 0.8
	## Read a frame back at most this often (0: every frame). Each read stalls its frame on the
	## GPU, so filming every frame ran at about 20 ms a frame against 6-9 ms in play; at 30 ms
	## the frames between reads run at play speed (native-cover round 2).
	var gap_msec := 0
	var brush: BrushTool = null
	var _start := 0
	var _press := -1
	var _last_grab := -1_000_000
	var _images: Array[Image] = []
	var _times := PackedInt32Array()

	func _ready() -> void:
		_start = Time.get_ticks_msec()
		RenderingServer.frame_post_draw.connect(_grab)

	func _grab() -> void:
		if not is_inside_tree():
			return
		var now := Time.get_ticks_msec()
		if _press < 0:
			if brush.pressed:
				_press = now
			elif now - _start > 4000:
				_finish()
				return
			else:
				return
		if now - _press > seconds * 1000.0:
			_finish()
			return
		if now - _last_grab < gap_msec:
			return
		_last_grab = now
		var image := get_viewport().get_texture().get_image()
		var size := image.get_size()
		var w := mini(crop.x, size.x)
		var h := mini(crop.y, size.y)
		var corner := Vector2i(floori((size.x - w) * 0.5), floori((size.y - h) * 0.5))
		var region := image.get_region(Rect2i(corner, Vector2i(w, h)))
		if scale != 1.0:
			region.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_BILINEAR)
		_images.append(region)
		_times.append(now - _press)

	func _finish() -> void:
		RenderingServer.frame_post_draw.disconnect(_grab)
		var fps := 30
		var k := 0
		var written := 0
		if not _images.is_empty():
			for slot in int(seconds * fps):
				var t := slot * 1000.0 / fps
				while k + 1 < _times.size() and _times[k + 1] <= t:
					k += 1
				_images[k].save_png(dir.path_join("%s_%03d.png" % [prefix, slot]))
				written += 1
		print(
			(
				"RJ| latency film %s: %d frames drawn in %.2f s, %d written at %d fps"
				% [prefix, _images.size(), seconds, written, fps]
			)
		)
		_images.clear()
		queue_free()
