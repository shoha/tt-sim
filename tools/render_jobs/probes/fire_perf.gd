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
##   view {view}       zout: the camera's widest zoom (its own limit) over the map's middle
##   cpu {frames}      the field's per-frame script work (FireField._process, the lights'
##                     flicker) called `frames` times in a row: microseconds a frame
##   refresh {at, radius, runs}  a brush dab's refresh at document point `at` (a square of
##                     `radius` metres about it): FireField.refresh over its samples `runs`
##                     times, the median of the whole and of its re-plan and heat parts
##   warm              starts the fire's ground surfaces loading as the Fire tool's arming does
##   first_burn {at, radius}  paints the palette's burnt forest biome over a disc with nothing
##                     armed, as a peer applies a fire's op: the stroke's milliseconds, the
##                     ground layers before and after, GroundLayerArrays.last_sync_ms
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
	return "unknown action %s" % action


static func _config(ctrl: AuthoringController, field: FireField, config: String) -> String:
	if field == null or field.lights() == null:
		return "no fire"
	var name := config.split("#")[0]
	var off := name == "off"
	var flames := not off and name != "no_flames"
	var glow := not off and name != "no_glow"
	for chunk in field.get_children():
		if not (chunk is FireLights or chunk is FireFieldSmoke):
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
	if view != "zout":
		return "unknown view %s" % view
	var cc := gm.get_camera_controller()
	if _widest <= 0.0:
		_widest = float(cc.get("max_zoom"))
	var zoom := _widest
	cc.set("_target_zoom", zoom)
	FireProbe._look(gm, Vector2.ZERO)
	return "view zout: zoom %.2f (LOD past %.0f)" % [zoom, FireField.LOD_ZOOM]


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
	# The blocks refresh() re-plans for that rect (its own reach through the placement warp).
	var reach := FireField.PLACE_WARP.y + FireField.JITTER * FireField.FLAME_SPACING_M
	var grow := ceili(reach / minf(spacing.x, spacing.y)) + 1
	var touched := FireField.blocks_of(doc, rect.grow(grow))
	var whole := PackedFloat64Array()
	var plan := PackedFloat64Array()
	var heat := PackedFloat64Array()
	for k in runs:
		var started := Time.get_ticks_usec()
		field.refresh(rect)
		whole.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		for block in touched:
			FireClusters.cells_of(FireField.plan_block(doc, block))
		plan.append((Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		field._update_heat(touched)
		heat.append((Time.get_ticks_usec() - started) / 1000.0)
	return (
		(
			"refresh at %s r %.1f m (%d blocks re-planned, %d shown of the map): whole %.2f ms,"
			+ " re-plan %.2f, heat re-splat and upload %.2f, the rest (budget, drawing, glow,"
			+ " lights) %.2f"
		)
		% [
			str(at), radius, touched.size(), field.flame_count(), _median(whole),
			_median(plan), _median(heat), _median(whole) - _median(plan) - _median(heat)
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
			+ " arrays sync %.1f ms (at load %.1f ms; %s)"
		)
		% [
			stroked, total, before, binding.layers().size(), binding.arrays.last_sync_ms,
			load_sync, ", ".join(binding.layers())
		]
	)


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
