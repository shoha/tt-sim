extends RefCounted

## Render-job probe (`call` op) for the persistent fire's pinned performance pass (card F4b-2;
## docs/PERFORMANCE.md "Fire (F4): pinned performance pass", job fire_perf_play). The views and
## the sky come from fire.gd's shot action; this one switches the fire's parts for the in-run
## A/B and times its CPU work. Actions:
##   config {config}   which parts of the fire draw: "on" (all), "off" (the field hidden: the
##                     flames, the ground's fire term, the smoke and the lights), or one part off,
##                     "no_flames", "no_glow" (fire_present 0 on the ground: its char and bed),
##                     "no_smoke" or "no_lights"; a "#n" suffix is ignored, so an expand can
##                     repeat a config in one A/B
##   view {view}       zout (or a key ending in it, "day_zout"): the camera's widest zoom (its
##                     own limit) over the map's middle; any other key is left to fire.gd's shot
##   cpu {frames}      the field's per-frame script work (FireField._process, the lights'
##                     flicker) called `frames` times in a row: microseconds a frame
##   refresh {at, radius, runs}  a brush dab's refresh at document point `at` (a square of
##                     `radius` metres about it): FireField.refresh over its samples `runs`
##                     times, the median of the whole and of its re-plan and heat parts
##   warm              starts the fire's ground surfaces loading as the Fire tool's arming does
##   first_burn {at, radius}  paints the palette's burnt forest biome over a disc with nothing
##                     armed, as a peer applies a fire's op: the stroke's milliseconds, the
##                     ground layers before and after, GroundLayerArrays.last_sync_ms, and the
##                     fire book's state with its load and upload milliseconds (FireLook)
##   bake_gpu {mode, at, radius, read}  the ground bake's redraw on the GPU (card fire-prod-c7a):
##                     without `read`, turns on render-time measuring for the bake's SubViewport
##                     and asks it to redraw the region a 4 m dab at `at` re-bakes (mode "dab",
##                     FireField.bake_region of blocks_to_replan) or the whole map ("whole"),
##                     holding it at UPDATE_ALWAYS over that box (a one-off draw's timestamps never
##                     come back); with `read` true, that viewport's last measured GPU and CPU
##                     milliseconds a redraw, and the viewport back to UPDATE_DISABLED (wait about
##                     a second between the two)
##   book {do}         the fire book's state and last load's timings; do "release" lets both
##                     books go (FireLook.release_book), do "load" asks for them again and waits
##                     for the load and the binding (a warm load: same process, file cached)
##   remove {folder}   deletes one _firefeat_ test level

const FireProbe := preload("res://tools/render_jobs/probes/fire.gd")

## The camera's own widest zoom, read at the first zout (fire.gd's z30 widens the limits).
static var _widest := 0.0


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "remove":
		return _remove(String(step.get("folder", "")))
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var field: FireField = ctrl.editor.fire_field
	match action:
		"config":
			return _config(ctrl, field, String(step.get("config", "on")))
		"view":
			return _view(base.get("_game_map"), String(step.get("view", "zout")))
		"cpu":
			return _cpu(field, int(step.get("frames", 2000)))
		"refresh":
			return _refresh(field, ctrl.document, step)
		"warm":
			FireTool.warm(ctrl.editor)
			return "warming the fire's surfaces"
		"first_burn":
			return _first_burn(ctrl.editor, step)
		"bake_gpu":
			return _bake_gpu(field, ctrl.document, step)
		"book":
			return _book(String(step.get("do", "")))
	return "unknown action %s" % action


static func _bake_gpu(field: FireField, doc: MapDocument, step: Dictionary) -> String:
	var bake := field.get_node_or_null(FireNoiseBake.NODE_NAME) as FireNoiseBake
	var viewport := bake.get_node_or_null("Sim") as SubViewport if bake != null else null
	if viewport == null:
		return "no ground bake"
	var rid := viewport.get_viewport_rid()
	if bool(step.get("read", false)):
		var text := "bake redraw measured: gpu %.3f ms, cpu %.3f ms (viewport %s)" % [
			RenderingServer.viewport_get_measured_render_time_gpu(rid),
			RenderingServer.viewport_get_measured_render_time_cpu(rid),
			str(viewport.size)
		]
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return text
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var half := doc.extent_m() * 0.5
	var region := Rect2(-half, doc.extent_m())
	var mode := String(step.get("mode", "whole"))
	if mode == "dab":
		var at_list: Array = step.get("at", [0.0, 0.0])
		var at := Vector2(float(at_list[0]), float(at_list[1]))
		var radius := float(step.get("radius", 4.0))
		var spacing := doc.sample_step()
		var lo := Vector2i(((at - Vector2.ONE * radius + half) / spacing).floor())
		var hi := Vector2i(((at + Vector2.ONE * radius + half) / spacing).ceil())
		var rect := Rect2i(lo, hi - lo).intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
		region = FireField.bake_region(doc, FireField.blocks_to_replan(doc, rect))
	bake.rebake(region)
	# A viewport drawn once never gets its timestamps back (they resolve frames later), so it
	# redraws the same box every frame until the read: the same pixels, a steady per-frame cost.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var box := FireNoiseBake.texels_of(region, bake.sim_rect(), viewport.size / Vector2i(2, 1))
	return "bake redraw %s over %s m: %s texels a tile of %s" % [
		mode, str(region), str(box.size), str(viewport.size / Vector2i(2, 1))
	]


static func _book(what: String) -> String:
	var started := Time.get_ticks_usec()
	if what == "release":
		FireLook.release_book()
		return "books released in %.2f ms; %s" % [
			(Time.get_ticks_usec() - started) / 1000.0, _book_text()
		]
	if what == "load":
		FireLook.request_book()
		FireLook.finish_book()
		return "books loaded and bound in %.2f ms (blocking); %s; smoke book %s" % [
			(Time.get_ticks_usec() - started) / 1000.0,
			_book_text(),
			String(FireLook.Book.keys()[FireFieldSmoke.book_state()]).to_lower()
		]
	return _book_text()


static func _config(ctrl: AuthoringController, field: FireField, config: String) -> String:
	if field == null or field.lights() == null:
		return "no fire"
	var name := config.split("#")[0]
	var off := name == "off"
	var flames := not off and name != "no_flames"
	var glow := not off and name != "no_glow"
	for chunk in field.get_children():
		if not (chunk is FireLights or chunk is FireFieldSmoke or chunk is FireNoiseBake):
			(chunk as Node3D).visible = flames
	ctrl.editor.terrain.get_material().set_shader_parameter("fire_present", 1 if glow else 0)
	field.smoke().visible = not off and name != "no_smoke"
	field.lights().visible = not off and name != "no_lights"
	return "config %s: flames %s, glow %s, smoke %s, lights %s (%d lit)" % [
		name, flames, glow, field.smoke().visible, field.lights().visible, _lit(field.lights())
	]


static func _lit(lights: FireLights) -> int:
	var n := 0
	for light in lights.lights():
		n += 1 if light.visible else 0
	return n


static func _view(gm: GameMap, view: String) -> String:
	# A shot key ("day_zout") names the same view; any other key leaves the camera to fire.gd.
	if not view.ends_with("zout"):
		return "view %s left to the shot" % view
	var cc := gm.get_camera_controller()
	if _widest <= 0.0:
		_widest = float(cc.get("max_zoom"))
	var zoom := _widest
	cc.set("_target_zoom", zoom)
	FireProbe._look(gm, Vector2.ZERO)
	return "view zout: zoom %.2f" % zoom


static func _cpu(field: FireField, frames: int) -> String:
	var lights := field.lights()
	var started := Time.get_ticks_usec()
	for k in frames:
		field._process(1.0 / 60.0)
	var field_us := float(Time.get_ticks_usec() - started) / frames
	started = Time.get_ticks_usec()
	for k in frames:
		lights._process(1.0 / 60.0)
	var lights_us := float(Time.get_ticks_usec() - started) / frames
	return "cpu per frame: field %.2f us, lights %.2f us (%d lit), total %.3f ms" % [
		field_us, lights_us, _lit(lights), (field_us + lights_us) / 1000.0
	]


static func _refresh(field: FireField, doc: MapDocument, step: Dictionary) -> String:
	var at_list: Array = step.get("at", [0.0, 0.0])
	var at := Vector2(float(at_list[0]), float(at_list[1]))
	var radius := float(step.get("radius", 4.0))
	var runs := int(step.get("runs", 9))
	var spacing := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var lo := Vector2i(((at - Vector2.ONE * radius + half) / spacing).floor())
	var hi := Vector2i(((at + Vector2.ONE * radius + half) / spacing).ceil())
	var rect := Rect2i(lo, hi - lo).intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	# The blocks refresh() re-plans for that rect.
	var touched := FireField.blocks_to_replan(doc, rect)
	var whole := PackedFloat64Array()
	var plan := PackedFloat64Array()
	var heat := PackedFloat64Array()
	var launch := PackedFloat64Array()
	var worker := PackedFloat64Array()
	var land := PackedFloat64Array()
	var threaded := field.use_worker
	field.finish_work()
	for k in runs:
		# At once on this thread (FireField.use_worker off): the whole refresh and its parts.
		field.use_worker = false
		var started := Time.get_ticks_usec()
		field.refresh(rect)
		whole.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		for block in touched:
			FireClusters.cells_of(FireField.plan_block(doc, block))
		plan.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		var heat_copy := field._heat.duplicate()
		var pools_copy := field._pools.duplicate()
		FireField.resplat(doc, field._plans, touched, heat_copy, pools_copy, field._heat_size)
		heat.append((Time.get_ticks_usec() - started) / 1000.0)
		# On a worker: the main thread's launch (the snapshot) and landing, and the worker's time.
		field.use_worker = true
		started = Time.get_ticks_usec()
		field.refresh(rect)
		launch.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		while not WorkerThreadPool.is_task_completed(field._job.task):
			OS.delay_usec(50)
		worker.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		field.finish_work()
		land.append((Time.get_ticks_usec() - started) / 1000.0)
	field.use_worker = threaded
	return (
		(
			"refresh at %s r %.1f m (%d blocks re-planned, %d shown of the map): at once %.2f ms"
			+ " (re-plan %.2f, heat re-splat %.2f, the rest %.2f); on the worker: main thread"
			+ " %.2f ms (launch %.2f, landing %.2f), the worker %.2f"
		)
		% [
			str(at), radius, touched.size(), field.flame_count(), _median(whole),
			_median(plan), _median(heat), _median(whole) - _median(plan) - _median(heat),
			_median(launch) + _median(land), _median(launch), _median(land), _median(worker)
		]
	)


static func _first_burn(editor: AuthoringEditor, step: Dictionary) -> String:
	var burnt := FireSweep.burnt_biome(editor.palette_root)
	if burnt == "":
		return "no burnt biome in the palette"
	var binding := editor.terrain.layer_binding()
	var before := binding.layers().size()
	# The last sync before the burn is the load's (build()).
	var load_sync := binding.arrays.last_sync_ms
	var at_list: Array = step.get("at", [0.0, 0.0])
	var local := Vector3(float(at_list[0]), 0.0, float(at_list[1]))
	var world := editor.to_world(local)
	var radius := float(step.get("radius", 4.0)) * editor.map_scale()
	var started := Time.get_ticks_usec()
	if not editor.begin_stroke(MaskBrush.PAINT, burnt):
		return "the burnt forest stroke did not start"
	editor.stroke_dab(world, world, radius, 0.5)
	editor.flush()
	var stroked := (Time.get_ticks_usec() - started) / 1000.0
	editor.end_stroke()
	var total := (Time.get_ticks_usec() - started) / 1000.0
	return (
		(
			"first burn: dab and flush %.1f ms, with the stroke's end %.1f ms; layers %d -> %d,"
			+ " arrays sync %.1f ms (at load %.1f ms; %s); %s"
		)
		% [
			stroked, total, before, binding.layers().size(), binding.arrays.last_sync_ms,
			load_sync, ", ".join(binding.layers()), _book_text()
		]
	)


## The fire book's state and its last load's timings (FireLook.book_timings).
static func _book_text() -> String:
	var timings := FireLook.book_timings()
	var state: String = FireLook.Book.keys()[FireLook.book_state()]
	return "fire book %s: load %.1f ms (threaded), upload %.1f ms (main thread)" % [
		state.to_lower(), float(timings.load_ms), float(timings.upload_ms)
	]


static func _remove(folder: String) -> String:
	if not folder.begins_with(FireProbe.PREFIX):
		return "refused: %s is not a %s level" % [folder, FireProbe.PREFIX]
	var path := LevelManager.folder_path(folder)
	if not DirAccess.dir_exists_absolute(path):
		return "no level %s" % folder
	if not LevelManager.delete_level_folder(path):
		FireProbe._remove_tree(path)
	return "removed %s" % folder


static func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
