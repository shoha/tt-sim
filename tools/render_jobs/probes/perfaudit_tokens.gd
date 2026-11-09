extends RefCounted

## Render-job probe (`call` op) for the performance audit's tokens stream (topic perfaudit,
## 2026-11-09; job jobs/perfaudit_tokens.json). One `sweep` call queues the whole measurement plan
## on a runner node; `wait_done` steps hold the job (each up to the driver's 60 s call hold) until
## it has finished, so a long sweep needs several of them. Actions:
## - `sweep` (`kinds` ["pack", "avatar"], `counts` [10, 50, 100, 250, 500], `full_at` the counts
##   that get every variant (the others get ship and hidden), `rounds` 4, `frames` 45, `settle` 8):
##   one-shot build timings first, a token-free baseline, then per kind it adds tokens up to each
##   count on a grid over the map (pack = the shipped Beasts pack's skinned, animated animals, the
##   real pack path; avatar = AvatarPresets figures) and logs the spawn batch, the frames after it,
##   memory deltas, a census of the token nodes, CPU micro timings and the frame-time table over
##   the variants; then removes them all, timed.
## - `wait_done`: blocks (blocker) while the sweep runs; returns its status.
##
## Variants, each applied to the shipped state (the previous variant is undone first):
##   ship          as shipped
##   hidden        every token body hidden: what the tokens cost to draw, fade and ghost
##   no_ghost      TokenGhost off
##   no_shadow     token meshes cast no shadow
##   no_fade       the occlusion fade off (foliage and map materials skip the token loop)
##   no_proc       per-token frame work off: AnimationTree inactive (pack), AvatarTokenView process
##   frozen        token rigid bodies frozen (static): the physics engine's share
##   orig_shading  pack tokens in their original materials instead of TokenToon
##   ceiling       tokens hidden, one MultiMesh per distinct token mesh at the same transforms (the
##                 cheapest draw of the same meshes, bind pose, first material, shadows as shipped)
## Table columns: frame, fmean, fp90 (the window's median, mean and p90 of the wall ms between
## frames; the mean carries the 60 Hz physics steps a median skips), gpu (world viewport GPU ms),
## rcpu (world viewport render CPU ms), each the median over rounds 2..R of the window values with
## the range of those rounds, draws and prims of the variant's last window, and frame and gpu as
## ratios to ship in the same block. Rounds rotate the variant order and reverse it every other
## round. Engine.max_fps is 0 during the sweep, so a headless run's frame is its CPU frame (gpu and
## rcpu read 0 there). Performance.TIME_PROCESS and TIME_PHYSICS_PROCESS are not used: they hold the
## worst step of the last second, not the frame's. Every timing here is a debug build.

const RUNNER := "PerfauditTokensRunner"
const DONE_META := "perfaudit_tokens_done"


static func run(base: Node, step: Dictionary) -> String:
	var root := base.get_tree().root
	match String(step.get("action", "")):
		"sweep":
			var old := root.get_node_or_null(RUNNER)
			if old != null:
				return "a sweep is already running"
			if root.has_meta(DONE_META):
				root.remove_meta(DONE_META)
			var runner := Runner.new()
			runner.name = RUNNER
			runner.setup(base, step)
			root.add_child(runner)
			return "sweep queued: %d tasks" % runner.tasks.size()
		"wait_done":
			var r := root.get_node_or_null(RUNNER)
			if r != null:
				return "still running: %s" % r.get("status")
			return String(root.get_meta(DONE_META, "no sweep ran"))
	return "unknown action %s" % step.get("action", "")


static func blocker(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) != "wait_done":
		return ""
	var r := base.get_tree().root.get_node_or_null(RUNNER)
	return "" if r == null else "sweep running (%s)" % r.get("status")


class Runner:
	extends Node

	const BEASTS := ["cow", "horse", "sheep", "wolf", "fox", "pig", "deer", "llama"]
	const BEAST_PATH := "res://builtin_packs/beasts/models/%s.glb"
	const PLACEHOLDER_PATH := "res://scenes/board_token/board_token.tscn"
	const GRID := 23
	const SPACING := 1.25
	const SCALE_VARIANTS := ["ship", "hidden"]
	const FULL_VARIANTS := [
		"ship",
		"hidden",
		"no_ghost",
		"no_shadow",
		"no_fade",
		"no_proc",
		"frozen",
		"orig_shading",
		"ceiling",
	]
	const SERIES := ["frame", "fmean", "fp90", "gpu", "rcpu"]
	const MB := 1048576.0
	const DONE_KEY := "perfaudit_tokens_done"

	var tasks: Array[Dictionary] = []
	var status := "starting"
	var _base: Node
	var _gm: GameMap
	var _lpc: LevelPlayController
	var _task: Dictionary = {}
	var _last_us := 0
	var _frames := PackedFloat64Array()
	var _windows: Array[Dictionary] = []
	var _win := 0
	var _skip := 0
	var _cur := {}
	var _table := {}
	var _counts := {}
	var _applied := "ship"
	var _shadow_saved := {}
	var _ceiling: Array[MultiMeshInstance3D] = []
	var _mem_last := {}
	var _mem_tokens := 0
	var _next_index := 0
	var _models := {}
	var _max_fps := 0
	var _sleep_us := 0

	func setup(base: Node, step: Dictionary) -> void:
		_base = base
		_gm = base.get("_game_map")
		_lpc = base.get("_level_play_controller")
		var rounds := int(step.get("rounds", 4))
		var frames := int(step.get("frames", 45))
		var settle := int(step.get("settle", 8))
		var full_at: Array[int] = []
		for n in step.get("full_at", [100, 500]):
			full_at.append(int(n))
		var sample := {"rounds": rounds, "frames": frames, "settle": settle}
		tasks.append({"do": "mem", "label": "baseline"})
		tasks.append({"do": "builds"})
		tasks.append({"do": "micro", "label": "none 0"})
		tasks.append(_merged(sample, {"do": "sample", "label": "none 0", "variants": ["ship"]}))
		for kind in step.get("kinds", ["pack", "avatar"]):
			for n in step.get("counts", [10, 50, 100, 250, 500]):
				var label := "%s %d" % [kind, int(n)]
				var variants: Array = FULL_VARIANTS if full_at.has(int(n)) else SCALE_VARIANTS
				if kind != "pack":
					variants = variants.filter(func(v: String) -> bool: return v != "orig_shading")
				tasks.append({"do": "spawn", "kind": kind, "n": int(n)})
				tasks.append({"do": "watch", "frames": 40, "label": "after spawn " + label})
				tasks.append({"do": "mem", "label": label})
				tasks.append({"do": "census", "label": label})
				tasks.append({"do": "micro", "label": label})
				tasks.append(_merged(sample, {"do": "sample", "label": label, "variants": variants}))
			tasks.append({"do": "clear", "kind": kind})
			tasks.append({"do": "watch", "frames": 40, "label": "after clear " + kind})
			tasks.append({"do": "mem", "label": "cleared " + kind})

	func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
		var out := a.duplicate()
		out.merge(b, true)
		return out

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -99
		_last_us = Time.get_ticks_usec()
		RenderingServer.viewport_set_measure_render_time(_gm.world_viewport.get_viewport_rid(), true)
		# Uncapped, so a headless run's wall frame is its CPU frame: a run with no window to draw
		# is otherwise paced at low_processor_usage_mode_sleep_usec (6.9 ms) per frame.
		_max_fps = Engine.max_fps
		_sleep_us = OS.low_processor_usage_mode_sleep_usec
		Engine.max_fps = 0
		OS.low_processor_usage_mode_sleep_usec = 0
		_log("sweep: max_fps %d, frame sleep %d us -> 0 for the sweep" % [_max_fps, _sleep_us])

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - _last_us) / 1000.0
		_last_us = now
		if _task.is_empty():
			if tasks.is_empty():
				_finish()
				return
			_task = tasks.pop_front()
			status = "%s %s" % [_task.get("do"), _task.get("label", _task.get("kind", ""))]
			if not _begin(_task):
				_task = {}
			return
		if _tick(ms):
			_task = {}

	func _finish() -> void:
		_apply("ship")
		Engine.max_fps = _max_fps
		OS.low_processor_usage_mode_sleep_usec = _sleep_us
		get_tree().root.set_meta(DONE_KEY, "sweep done")
		_log("sweep done")
		queue_free()

	func _log(s: String) -> void:
		for node in get_tree().root.get_children():
			if node.has_method("log_line"):
				node.call("log_line", s)
				return
		print("RJ| " + s)

	## Runs a task's synchronous part; true when it goes on over frames (_tick).
	func _begin(task: Dictionary) -> bool:
		match String(task.do):
			"mem":
				_mem(String(task.label))
			"builds":
				_builds()
			"micro":
				_micro(String(task.label))
			"census":
				_census(String(task.label))
			"spawn":
				_spawn(String(task.kind), int(task.n))
			"clear":
				_clear()
			"watch":
				_frames = PackedFloat64Array()
				return true
			"sample":
				_start_sample(task)
				return true
		return false

	## One frame of a frame task; true when it is done.
	func _tick(ms: float) -> bool:
		if String(_task.do) == "watch":
			_frames.append(ms)
			if _frames.size() < int(_task.frames):
				return false
			var s := Stats.of(_frames)
			_log(
				(
					"watch %s: %d frames sum %.1f ms, median %.2f, worst %.2f"
					% [_task.label, s.n, s.sum, s.median, s.worst]
				)
			)
			return true
		return _tick_sample(ms)

	# --- tokens ---

	func _tokens() -> Array[BoardToken]:
		var out: Array[BoardToken] = []
		for node in _gm.drag_and_drop_node.get_children():
			if node is BoardToken and not node.is_queued_for_deletion():
				out.append(node as BoardToken)
		return out

	func _cell(i: int) -> Vector3:
		var cell := (i * 97) % (GRID * GRID)
		var half := (GRID - 1) * SPACING * 0.5
		var x := -half + (cell % GRID) * SPACING
		var z := -half + (cell / GRID) * SPACING
		var space := _gm.world_viewport.find_world_3d().direct_space_state
		var hit := DragPlaceController.raycast_terrain_down(space, Vector3(x, 0, z))
		return Vector3(x, hit.y if hit != Vector3.INF else 0.0, z)

	func _beast_model(asset_id: String) -> Node3D:
		var path: String = BEAST_PATH % asset_id
		var model := AssetManager.get_model_instance_from_path_sync(path, false)
		if model != null:
			return model
		if not _models.has(asset_id):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			doc.append_from_buffer(FileAccess.get_file_as_bytes(path), "", state)
			_models[asset_id] = doc.generate_scene(state)
		return (_models[asset_id] as Node3D).duplicate()

	func _make(kind: String, i: int) -> BoardToken:
		if kind == "pack":
			var asset_id: String = BEASTS[i % BEASTS.size()]
			var token := BoardTokenFactory.create_from_scene(_beast_model(asset_id))
			token.set_meta("perfaudit_asset", asset_id)
			return token
		var preset := i % AvatarPresets.PRESETS.size()
		return AvatarTokenFactory.create(
			AvatarPresets.recipe(preset), String(AvatarPresets.PRESETS[preset].name)
		)

	func _spawn(kind: String, n: int) -> void:
		var spawner: Object = _lpc.get("_token_spawner")
		var made := PackedFloat64Array()
		var placed := PackedFloat64Array()
		var have := _tokens().size()
		var t0 := Time.get_ticks_usec()
		while have < n:
			var at := _cell(_next_index)
			var t1 := Time.get_ticks_usec()
			var token := _make(kind, _next_index)
			var t2 := Time.get_ticks_usec()
			var asset_id := String(token.get_meta("perfaudit_asset", ""))
			var pack_id := "beasts" if kind == "pack" else ""
			spawner.call("_place_new_token", token, pack_id, asset_id, "default", at, false)
			var t3 := Time.get_ticks_usec()
			made.append((t2 - t1) / 1000.0)
			placed.append((t3 - t2) / 1000.0)
			_next_index += 1
			have += 1
		var m := Stats.of(made)
		var p := Stats.of(placed)
		_log(
			(
				"spawn %s to %d: %d new in %.1f ms; create median %.2f worst %.2f ms, place median"
				+ " %.2f worst %.2f ms (sum create %.1f, place %.1f)"
			)
			% [
				kind,
				n,
				made.size(),
				(Time.get_ticks_usec() - t0) / 1000.0,
				m.median,
				m.worst,
				p.median,
				p.worst,
				m.sum,
				p.sum
			]
		)

	func _clear() -> void:
		_apply("ship")
		var spawner: Object = _lpc.get("_token_spawner")
		var tokens := _tokens()
		var t0 := Time.get_ticks_usec()
		for token in tokens:
			spawner.call("remove_token", token)
		_log(
			(
				"clear %d tokens: remove_token %.1f ms total (%.3f each)"
				% [
					tokens.size(),
					(Time.get_ticks_usec() - t0) / 1000.0,
					(Time.get_ticks_usec() - t0) / 1000.0 / maxi(tokens.size(), 1)
				]
			)
		)
		_next_index = 0

	# --- one-shot measurements ---

	func _mem(label: String) -> void:
		var cur := {
			"static": OS.get_static_memory_usage() / MB,
			"video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB,
			"tex": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / MB,
			"buf": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / MB,
			"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
			"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		}
		var n := _tokens().size()
		var parts := PackedStringArray()
		for key in cur:
			var d: float = float(cur[key]) - float(_mem_last.get(key, cur[key]))
			var per := d / (n - _mem_tokens) if n != _mem_tokens else 0.0
			parts.append("%s %.1f (%+.1f, %+.3f/token)" % [key, cur[key], d, per])
		_log("mem %s (%d tokens): %s" % [label, n, ", ".join(parts)])
		_mem_last = cur
		_mem_tokens = n

	func _census(label: String) -> void:
		var tokens := _tokens()
		var c := Census.new()
		for token in tokens:
			c.add(token)
			for node in token.find_children("*", "", true, false):
				c.add(node)
		var whole := Census.new()
		for node in get_tree().root.find_children("*", "", true, false):
			whole.add(node)
		_log("census %s: %s" % [label, c.text(tokens.size())])
		_log("census whole tree %s: %s" % [label, whole.text(1)])

	func _micro(label: String) -> void:
		var cam := _gm.camera_node
		var vp := _gm.world_viewport
		var space := vp.find_world_3d().direct_space_state
		var size := Vector2(vp.size)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var out := PackedStringArray()
		for mask in [2, 0xFFFFFFFF]:
			var hits := 0
			var t0 := Time.get_ticks_usec()
			for i in 2000:
				var px := Vector2(rng.randf() * size.x, rng.randf() * size.y)
				var origin := cam.project_ray_origin(px)
				var q := PhysicsRayQueryParameters3D.create(
					origin, origin + cam.project_ray_normal(px) * 1000.0, mask
				)
				hits += 0 if space.intersect_ray(q).is_empty() else 1
			out.append(
				(
					"ray mask %s %.2f us (%d/2000 hit)"
					% ["tokens" if mask == 2 else "all", (Time.get_ticks_usec() - t0) / 2000.0, hits]
				)
			)
		var t1 := Time.get_ticks_usec()
		for i in 300:
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(size.x * 0.5 + float(i % 2), size.y * 0.1)
			ev.relative = Vector2(1, 0)
			vp.push_input(ev)
		out.append("motion %.2f us/event" % ((Time.get_ticks_usec() - t1) / 300.0))
		var t2 := Time.get_ticks_usec()
		for i in 100:
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_XBUTTON1
				ev.pressed = pressed
				ev.position = Vector2(size.x * 0.5, size.y * 0.1)
				vp.push_input(ev)
		out.append("button %.2f us/event" % ((Time.get_ticks_usec() - t2) / 200.0))
		out.append(_input_without_controllers(vp, size))
		out.append_array(_micro_tokens(cam))
		_log("micro %s: %s" % [label, ", ".join(out)])

	## The same motion and button events with every BoardTokenController's _unhandled_input off:
	## the per-token share of the input dispatch.
	func _input_without_controllers(vp: Viewport, size: Vector2) -> String:
		var controllers: Array[Node] = []
		for token in _tokens():
			var c := token.get_node_or_null("BoardTokenController")
			if c != null and c.is_processing_unhandled_input():
				c.set_process_unhandled_input(false)
				controllers.append(c)
		var t1 := Time.get_ticks_usec()
		for i in 300:
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(size.x * 0.5 + float(i % 2), size.y * 0.1)
			ev.relative = Vector2(1, 0)
			vp.push_input(ev)
		var t2 := Time.get_ticks_usec()
		for i in 100:
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_XBUTTON1
				ev.pressed = pressed
				ev.position = Vector2(size.x * 0.5, size.y * 0.1)
				vp.push_input(ev)
		var t3 := Time.get_ticks_usec()
		for c in controllers:
			c.set_process_unhandled_input(true)
		return (
			"without %d controllers: motion %.2f us/event, button %.2f us/event"
			% [controllers.size(), (t2 - t1) / 300.0, (t3 - t2) / 200.0]
		)

	func _micro_tokens(cam: Camera3D) -> PackedStringArray:
		var out := PackedStringArray()
		var ofm: Node = _gm.occlusion_fade
		var entries: Array[Vector4] = []
		var t0 := Time.get_ticks_usec()
		for i in 200:
			entries = ofm.call("_collect_token_entries")
		var t1 := Time.get_ticks_usec()
		var image: Image = null
		var view := cam.get_camera_transform().affine_inverse()
		var proj := cam.get_camera_projection()
		var tiles := OcclusionTiles.TILES
		for i in 200:
			var bins := OcclusionTiles.bin(entries, view, proj, tiles, Vector2(0.001, 0.002))
			image = OcclusionTiles.build_image(entries, bins, tiles)
		var t2 := Time.get_ticks_usec()
		var texture := ImageTexture.create_from_image(image)
		for i in 100:
			texture.update(image)
		var t3 := Time.get_ticks_usec()
		out.append(
			(
				"occl collect %.1f us (%d entries), tiles and image %.1f us, upload %.1f us"
				% [
					(t1 - t0) / 200.0,
					entries.size(),
					(t2 - t1) / 200.0,
					(t3 - t2) / 100.0,
				]
			)
		)
		TokenGhost.apply_budget(get_tree(), cam)
		var t4 := Time.get_ticks_usec()
		for i in 20:
			TokenGhost.apply_budget(get_tree(), cam)
		out.append("ghost budget %.1f us" % ((Time.get_ticks_usec() - t4) / 20.0))
		var views: Array[AvatarTokenView] = []
		for token in _tokens():
			var view := AvatarTokenFactory.view_of(token)
			if view != null:
				views.append(view)
		if not views.is_empty():
			var t5 := Time.get_ticks_usec()
			for view in views:
				view.refresh_shade()
			var t6 := Time.get_ticks_usec()
			for k in 10:
				for view in views:
					view._process(0.016)
			var t7 := Time.get_ticks_usec()
			out.append(
				(
					"avatar shade %.1f us/token, view _process %.2f us/token"
					% [(t6 - t5) / float(views.size()), (t7 - t6) / 10.0 / views.size()]
				)
			)
		return out

	func _builds() -> void:
		var out := PackedStringArray()
		var load_ms := PackedFloat64Array()
		var held: Array[Resource] = []
		var mem0 := OS.get_static_memory_usage()
		for i in 3:
			var t := Time.get_ticks_usec()
			held.append(ResourceLoader.load(PLACEHOLDER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE))
			load_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		out.append(
			(
				"placeholder tscn load median %.1f ms, %.1f MB static per copy"
				% [Stats.of(load_ms).median, (OS.get_static_memory_usage() - mem0) / MB / 3.0]
			)
		)
		held.clear()
		var inst := PackedFloat64Array()
		for i in 20:
			var t := Time.get_ticks_usec()
			var node := BoardTokenFactory.BoardTokenScene.instantiate()
			inst.append((Time.get_ticks_usec() - t) / 1000.0)
			node.free()
		out.append("placeholder instantiate median %.3f ms" % Stats.of(inst).median)
		var t_kit := Time.get_ticks_usec()
		var kit := AvatarKit.load_kit()
		out.append(
			(
				"avatar kit load %.1f ms (%s)"
				% [(Time.get_ticks_usec() - t_kit) / 1000.0, "ok" if kit != null else "null"]
			)
		)
		var bare := PackedFloat64Array()
		for i in 8:
			var model := _beast_model(BEASTS[i])
			var t := Time.get_ticks_usec()
			_gm.drag_and_drop_node.get_parent().add_child(model)
			bare.append((Time.get_ticks_usec() - t) / 1000.0)
			model.get_parent().remove_child(model)
			model.free()
		out.append("bare beast model enter tree median %.2f ms" % Stats.of(bare).median)
		var t_tree := Time.get_ticks_usec()
		var tree_node := BoardTokenAnimationTreeFactory.create()
		out.append("animation tree create %.3f ms" % ((Time.get_ticks_usec() - t_tree) / 1000.0))
		tree_node.free()
		for kind in ["avatar", "pack"]:
			var times := PackedFloat64Array()
			var enter := PackedFloat64Array()
			var dress := PackedFloat64Array()
			for i in 10:
				var t := Time.get_ticks_usec()
				var token := _make(kind, i)
				times.append((Time.get_ticks_usec() - t) / 1000.0)
				var t1 := Time.get_ticks_usec()
				_gm.drag_and_drop_node.add_child(token)
				var t2 := Time.get_ticks_usec()
				TokenGhost.dress(token)
				var t3 := Time.get_ticks_usec()
				enter.append((t2 - t1) / 1000.0)
				dress.append((t3 - t2) / 1000.0)
				_gm.drag_and_drop_node.remove_child(token)
				token.free()
			var s := Stats.of(times)
			out.append(
				(
					"%s create median %.2f ms worst %.2f, enter tree median %.2f, dress %.2f"
					% [kind, s.median, s.worst, Stats.of(enter).median, Stats.of(dress).median]
				)
			)
		_log("builds: " + ", ".join(out))

	# --- frame sampling over variants ---

	func _start_sample(task: Dictionary) -> void:
		_windows.clear()
		_table.clear()
		_counts.clear()
		var variants: Array = task.variants
		for r in int(task.rounds):
			var order := variants.duplicate()
			for k in r % order.size():
				order.push_back(order.pop_front())
			if r % 2 == 1:
				order.reverse()
			for v in order:
				_windows.append({"variant": v, "round": r})
		_win = -1
		_next_window()

	func _next_window() -> void:
		_win += 1
		if _win >= _windows.size():
			return
		_apply(String(_windows[_win].variant))
		_skip = int(_task.settle)
		_cur = {}
		for s in SERIES:
			_cur[s] = []

	func _tick_sample(ms: float) -> bool:
		if _win >= _windows.size():
			_report_sample()
			_apply("ship")
			return true
		if _skip > 0:
			_skip -= 1
			return false
		var rid := _gm.world_viewport.get_viewport_rid()
		_cur.frame.append(ms)
		_cur.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		_cur.rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		if _cur.frame.size() < int(_task.frames):
			return false
		var w: Dictionary = _windows[_win]
		var v := String(w.variant)
		if not _table.has(v):
			_table[v] = {}
			for s in SERIES:
				_table[v][s] = []
		if int(w.round) > 0:
			var fs := Stats.of(_cur.frame)
			_table[v].frame.append(fs.median)
			_table[v].fmean.append(fs.mean)
			_table[v].fp90.append(fs.p90)
			_table[v].gpu.append(Stats.of(_cur.gpu).median)
			_table[v].rcpu.append(Stats.of(_cur.rcpu).median)
		var info := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
		_counts[v] = Vector2i(
			RenderingServer.viewport_get_render_info(
				rid, info, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
			),
			RenderingServer.viewport_get_render_info(
				rid, info, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
			)
		)
		_next_window()
		return false

	func _report_sample() -> void:
		var head := (
			"sample %s (%d tokens, %d rounds kept x %d frames)"
			% [_task.label, _tokens().size(), int(_task.rounds) - 1, int(_task.frames)]
		)
		_log(head)
		var ship: Dictionary = _table.get("ship", {})
		for v in _task.variants:
			if not _table.has(v):
				continue
			var parts := PackedStringArray()
			for s in SERIES:
				var st := Stats.of(_table[v][s])
				parts.append("%s %.3f [%.3f-%.3f]" % [s, st.median, st.best, st.worst])
			var ratios := ""
			if not ship.is_empty():
				var f0: float = Stats.of(ship.frame).median
				var g0: float = Stats.of(ship.gpu).median
				ratios = (
					" | frame/ship %.3f gpu/ship %.3f"
					% [
						Stats.of(_table[v].frame).median / maxf(f0, 0.0001),
						Stats.of(_table[v].gpu).median / maxf(g0, 0.0001)
					]
				)
			var c: Vector2i = _counts.get(v, Vector2i.ZERO)
			_log(
				(
					"  %s %s: %s | draws %d prims %d%s"
					% [_task.label, v, " ".join(parts), c.x, c.y, ratios]
				)
			)

	func _apply(variant: String) -> void:
		var tree := get_tree()
		var tokens := _tokens()
		match _applied:
			"hidden":
				for t in tokens:
					t.rigid_body.visible = true
			"no_ghost":
				TokenGhost.set_enabled(true, tree)
			"no_shadow":
				for id in _shadow_saved:
					var gi := instance_from_id(id) as GeometryInstance3D
					if gi != null:
						gi.cast_shadow = _shadow_saved[id]
				_shadow_saved.clear()
			"no_fade":
				_gm.set_occlusion_fade_enabled(true)
			"no_proc":
				_set_token_processing(tokens, true)
			"frozen":
				for t in tokens:
					t.rigid_body.freeze = false
			"orig_shading":
				TokenToon.painted = true
				TokenToon.refresh_all(tree)
			"ceiling":
				for mmi in _ceiling:
					mmi.queue_free()
				_ceiling.clear()
				for t in tokens:
					t.rigid_body.visible = true
		_applied = variant
		match variant:
			"hidden":
				for t in tokens:
					t.rigid_body.visible = false
			"no_ghost":
				TokenGhost.set_enabled(false, tree)
			"no_shadow":
				for t in tokens:
					for gi in t.rigid_body.find_children("*", "GeometryInstance3D", true, false):
						_shadow_saved[gi.get_instance_id()] = gi.cast_shadow
						gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"no_fade":
				_gm.set_occlusion_fade_enabled(false)
			"no_proc":
				_set_token_processing(tokens, false)
			"frozen":
				for t in tokens:
					t.rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
					t.rigid_body.freeze = true
			"orig_shading":
				TokenToon.painted = false
				TokenToon.refresh_all(tree)
			"ceiling":
				_build_ceiling(tokens)

	func _set_token_processing(tokens: Array[BoardToken], on: bool) -> void:
		for t in tokens:
			for mixer in t.rigid_body.find_children("*", "AnimationMixer", true, false):
				(mixer as AnimationMixer).active = on
			var view := AvatarTokenFactory.view_of(t)
			if view != null:
				view.set_process(on)

	## One MultiMesh per distinct token mesh, an instance at each token mesh's transform.
	func _build_ceiling(tokens: Array[BoardToken]) -> void:
		var groups := {}
		for t in tokens:
			for mi in TokenGhost.meshes_of(t.rigid_body):
				if mi.mesh == null:
					continue
				if not groups.has(mi.mesh):
					groups[mi.mesh] = {"xf": [], "mi": mi}
				groups[mi.mesh].xf.append(mi.global_transform)
		for mesh in groups:
			var g: Dictionary = groups[mesh]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = g.xf.size()
			for k in g.xf.size():
				mm.set_instance_transform(k, g.xf[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var src := g.mi as MeshInstance3D
			mmi.material_override = src.get_active_material(0)
			mmi.cast_shadow = src.cast_shadow
			_gm.drag_and_drop_node.get_parent().add_child(mmi)
			_ceiling.append(mmi)
		for t in tokens:
			t.rigid_body.visible = false


## Counts nodes by class and by what they process.
class Census:
	var nodes := 0
	var by_class := {}
	var flags := {}
	var meshes := 0
	var surfaces := 0
	var overlays := 0
	var unique_meshes := {}
	var unique_materials := {}
	var shadow_casters := 0

	func add(node: Node) -> void:
		nodes += 1
		by_class[node.get_class()] = int(by_class.get(node.get_class(), 0)) + 1
		var checks := {
			"process": node.is_processing(),
			"physics": node.is_physics_processing(),
			"internal": node.is_processing_internal(),
			"phys_internal": node.is_physics_processing_internal(),
			"input": node.is_processing_input(),
			"unhandled": node.is_processing_unhandled_input(),
			"script": node.get_script() != null,
		}
		for key in checks:
			if checks[key]:
				flags[key] = int(flags.get(key, 0)) + 1
		var gi := node as GeometryInstance3D
		if gi != null and gi.visible and gi.cast_shadow != gi.SHADOW_CASTING_SETTING_OFF:
			shadow_casters += 1
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			meshes += 1
			unique_meshes[mi.mesh] = true
			surfaces += mi.mesh.get_surface_count()
			for s in mi.mesh.get_surface_count():
				unique_materials[mi.get_active_material(s)] = true
			if mi.material_overlay != null:
				overlays += 1

	func text(tokens: int) -> String:
		var per := float(maxi(tokens, 1))
		var classes := by_class.keys()
		classes.sort_custom(func(a: String, b: String) -> bool: return by_class[a] > by_class[b])
		var top := PackedStringArray()
		for k in classes.slice(0, 12):
			top.append("%s %.1f" % [k, by_class[k] / per])
		var fl := PackedStringArray()
		for k in flags:
			fl.append("%s %d (%.2f)" % [k, flags[k], flags[k] / per])
		return (
			"%d units, nodes %d (%.1f each); flags %s; meshes %d (%d unique), surfaces %d, "
			% [tokens, nodes, nodes / per, ", ".join(fl), meshes, unique_meshes.size(), surfaces]
			+ (
				"materials %d unique, overlays %d, shadow casters %d; classes per unit: %s"
				% [unique_materials.size(), overlays, shadow_casters, ", ".join(top)]
			)
		)


class Stats:
	static func of(values: Variant) -> Dictionary:
		var s := PackedFloat64Array(values)
		s.sort()
		var n := s.size()
		if n == 0:
			return {
				"n": 0, "median": 0.0, "best": 0.0, "worst": 0.0, "sum": 0.0, "mean": 0.0, "p90": 0.0
			}
		var total := 0.0
		for v in s:
			total += v
		return {
			"n": n,
			"median": s[n / 2],
			"best": s[0],
			"worst": s[n - 1],
			"sum": total,
			"mean": total / n,
			"p90": s[clampi(ceili(0.9 * n) - 1, 0, n - 1)],
		}
