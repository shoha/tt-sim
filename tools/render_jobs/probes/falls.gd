extends RefCounted

## Render-job probe (`call` op) for waterfalls (phase 4c, P4c-2): the falls the open document
## derives (WaterFalls.falls) and the ground the carve shaped under each, read numerically
## beside the captures. Positions are map XZ metres. step.action:
##   falls                 every fall: its reaches, lip, direction, drop, half-width, the face
##                         foot and plunge pool the carve shaped (WaterCarve.fall_shape), the
##                         steepest slope found, and the carved ground along the lower course
##                         from the lip every quarter metre; names "found:fall<k>_lip",
##                         "found:fall<k>_foot" (the face's foot) and "found:fall<k>_plunge"
##                         (the middle of the plunge pool) for `look` and any point field.
##   look {at}             pans so the screen centre looks at `at` ([x, z] or found:).
## P4c-4 (the falls shader):
##   falls_visible {visible} shows or hides every AuthoredWater-falls mesh alone (the water
##                         stays), for an in-run GPU A/B of the falls.
##   quality {low}         sets the Water Quality globals (water_quality_skip_fine_detail and
##                         water_quality_skip_refraction) to `low`, as Settings > Graphics Low
##                         does; the shader drops its second octave and the mist.
##   clock {scale}         Engine.time_scale: 0 freezes the shader clock (TIME) for a capture
##                         whose PNG save would otherwise advance it; 1 resumes. The driver's
##                         `wait` runs on scaled time, so set 1 before any wait.
##   palette {name}        applies a WaterPresets palette (lagoon, lake, river, swamp, ocean,
##                         glacial) to the water and the falls, as the Water pane's tile does.
## P4c-6 (the judgment set):
##   tokens {points, assets} water.gd's `tokens` with this probe's found: names resolved
##                         ("found:fall1_plunge" puts a token in the first fall's plunge pool).
##   ramp {at, rise, face_slope, back_slope, half_length}
##                         raises a block of ground (never lowers): flat `rise` metres high
##                         around `at`, dropping east at `face_slope` (0.8: 39 degrees, under
##                         the cliff rule's 44) and rising from the west at `back_slope`, its
##                         sides across z easing out over 3 m past `half_length`. The natural
##                         slope a v0.1.29 document keeps its draped riffle sheet on.
##   old_river {points, half_width, depth}
##                         a river as v0.1.29 made it: planned with the frozen v0.1.29
##                         plan_river (test_water_falls.gd's copy: no orient, no lips, no
##                         subdivision, a cliff as one two-point step) and carved with every
##                         step a riffle (WaterCarve.river_goals with zero flags), refreshed
##                         like an undo; the current build then derives falls from it on load.

const WATER := preload("res://tools/render_jobs/probes/water.gd")

static var _found: Dictionary = {}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"falls":
			return _falls(base)
		"look":
			return WATER.run(base, {"action": "look", "at": _resolve(step.get("at"))})
		"tokens":
			var points: Array = []
			for p in step.get("points", []):
				points.append(_resolve(p))
			return WATER.run(
				base, {"action": "tokens", "points": points, "assets": step.get("assets", [])}
			)
		"ramp":
			return _ramp(base, step)
		"old_river":
			return _old_river(base, step)
		"falls_visible":
			# A bool, or a label from an `expand` template ("off ..." hides), as crossing.gd.
			var shown: Variant = step.get("visible", true)
			return _falls_visible(
				base, shown if shown is bool else not String(shown).begins_with("off")
			)
		"quality":
			# A bool, or an `expand` label ("low ..." is Low).
			var low: Variant = step.get("low", false)
			return _quality(low if low is bool else String(low).begins_with("low"))
		"clock":
			Engine.time_scale = float(step.get("scale", 1.0))
			return "time scale %.3f" % Engine.time_scale
		"palette":
			return _palette(String(step.get("name", "lagoon")))
	return "unknown action %s" % step.get("action", "")


static func _falls_visible(base: Node, on: bool) -> String:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.map_container == null:
		return "no map"
	var root := gm.map_container.get_node_or_null(^"LevelMap") as Node3D
	if root == null:
		return "no map"
	var count := 0
	for node in root.find_children(WaterFallMesh.MESH_NAME, "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = on
		count += 1
	return "%d falls meshes visible %s" % [count, str(on)]


static func _quality(low: bool) -> String:
	RenderingServer.global_shader_parameter_set("water_quality_skip_fine_detail", low)
	RenderingServer.global_shader_parameter_set("water_quality_skip_refraction", low)
	return "water quality low %s" % str(low)


static func _palette(name: String) -> String:
	if not WaterPresets.PALETTES.has(name):
		return "no palette %s" % name
	WaterGlbUtils.apply_water_settings(WaterPresets.PALETTES[name])
	var material := AuthoredWater.fall_material()
	return (
		"palette %s: falls foam %s water %s"
		% [
			name,
			str(material.get_shader_parameter("foam_color")),
			str(material.get_shader_parameter("water_color")),
		]
	)


static func _resolve(value: Variant) -> Variant:
	if value is String and String(value).begins_with("found:"):
		var p: Vector2 = _found.get(String(value).trim_prefix("found:"), Vector2.ZERO)
		return [p.x, p.y]
	return value


## A point field ([x, z] or a found: name) as map XZ.
static func _xz(value: Variant) -> Vector2:
	var resolved: Variant = _resolve(value)
	if resolved is Array and (resolved as Array).size() >= 2:
		return Vector2(float(resolved[0]), float(resolved[1]))
	return Vector2.ZERO


## The falls of the open document and the carved ground under each (see the header).
static func _falls(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	ctrl.editor.finish_height_work()
	var doc := ctrl.document
	var out := PackedStringArray()
	var k := 0
	for fall in WaterFalls.falls(doc):
		k += 1
		var lip: Vector2 = fall.lip
		var direction: Vector2 = fall.dir
		var drop := float(fall.top) - float(fall.bottom)
		var lower: WaterBody = doc.water_bodies[fall.lower_index]
		var plunge := WaterFalls.plunge_depth(drop)
		var foot := WaterCarve.fall_foot(drop, lower.depth_m())
		var basin := WaterFalls.plunge_length(drop)
		_found["fall%d_lip" % k] = lip
		_found["fall%d_foot" % k] = lip + direction * foot
		_found["fall%d_plunge" % k] = lip + direction * (foot + 0.5 * basin)
		var profile := PackedStringArray()
		var steepest := 0.0
		var previous := WaterGeometry.ground_at(doc, lip)
		var s := 0.0
		while s <= foot + basin + 1e-6:
			var g := WaterGeometry.ground_at(doc, lip + direction * s)
			profile.append("%.2f:%.2f" % [s, g])
			steepest = maxf(steepest, (previous - g) / 0.25)
			previous = g
			s += 0.25
		(
			out
			. append(
				(
					(
						"fall %d: %d -> %d lip %s dir %s drop %.2f hw %.2f foot %.2f m plunge %.2f m"
						+ " deep %.2f m | steepest %.1f deg | ground %s"
					)
					% [
						k,
						int(fall.upper_index),
						int(fall.lower_index),
						str(lip.snapped(Vector2.ONE * 0.01)),
						str(direction.snapped(Vector2.ONE * 0.01)),
						drop,
						float(fall.half_width),
						foot,
						basin,
						plunge,
						rad_to_deg(atan(steepest)),
						" ".join(profile),
					]
				)
			)
		)
	if out.is_empty():
		return "no falls (%d bodies)" % doc.water_bodies.size()
	return " || ".join(out)


# --- the v0.1.29 fixture (P4c-6) ---------------------------------------------------------


## Raises the open document's ground to a block (see the header), as a one-shot height edit
## refreshed like an undo (terrain, collision, plants); never lowers ground.
static func _ramp(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var doc := ctrl.document
	var at := _xz(step.get("at"))
	var rise := float(step.get("rise", 2.0))
	var face := float(step.get("face_slope", 0.8))
	var back := float(step.get("back_slope", 0.2))
	var half_length := float(step.get("half_length", 3.5))
	var back_run := rise / back
	ctrl.editor.finish_height_work()
	var before := doc.heights.duplicate()
	var heights := doc.heights.duplicate()
	var raised := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z)) - at
			var east := clampf(1.0 - p.x * face / rise, 0.0, 1.0)
			var west := clampf((p.x + back_run) / back_run, 0.0, 1.0)
			var across := 1.0 - smoothstep(half_length, half_length + 3.0, absf(p.y))
			var h := rise * minf(east, west) * across
			var i := doc.sample_index(x, z)
			if h > heights[i]:
				heights[i] = h
				raised += 1
	doc.heights = heights
	_refresh_heights(ctrl.editor, before)
	return (
		"ramp at %s: %d samples raised, top %.2f m, face slope %.2f" % [str(at), raised, rise, face]
	)


## A one-shot height edit of the open document landed the way water.gd's `tilt` lands one:
## the terrain's chunks, collision, plant snapping, its settle and the regeneration.
static func _refresh_heights(editor: AuthoringEditor, before: PackedFloat32Array) -> void:
	var doc := editor.document
	var changed := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	editor.set("_snap_before", before)
	editor.set("_aligned", DressingGround.aligned_assets(doc.biome_ids, editor.palette_root))
	(editor.get("_snap_start") as Dictionary).clear()
	(editor.get("_prop_start") as Dictionary).clear()
	editor.call("_queue_heights", changed)
	editor.finish_height_work()
	editor.terrain.settle_heights()
	editor.finish_height_work()
	editor.call("_regenerate", changed)


## A river as v0.1.29 made it (see the header): the frozen plan, the riffle-only carve, the
## bodies added, the wet dressing and the water surface refreshed. Logs the reaches and which
## steps the current rule reads as falls.
static func _old_river(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var editor := ctrl.editor
	var doc := ctrl.document
	editor.finish_height_work()
	var points := PackedVector2Array()
	for p in step.get("points", []):
		points.append(_xz(p))
	var half := float(step.get("half_width", 1.0))
	var widths := PackedFloat32Array()
	widths.resize(points.size())
	widths.fill(half)
	var depth_index := WaterBody.DEPTH_NAMES.find(String(step.get("depth", "waist")))
	var depth := (depth_index if depth_index >= 0 else WaterBody.Depth.WAIST) as WaterBody.Depth
	var bodies := _plan_river_v0_1_29(doc, points, widths, depth)
	if bodies.is_empty():
		return "old plan made nothing"
	var before := doc.heights.duplicate()
	var zeros := PackedByteArray()
	zeros.resize(bodies.size() - 1)
	var goals := WaterCarve.river_goals(doc, bodies, before, zeros)
	WaterEditor.lower(doc, goals)
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	_refresh_heights(editor, before)
	doc.water_dressing = WaterDressing.refresh(doc)
	if is_instance_valid(editor.terrain):
		editor.terrain.refresh_water_dressing()
	var water := AuthoredWater.refresh_map(editor.map_root, doc)
	water.finish_refresh()
	var lines := PackedStringArray()
	for b in bodies.size():
		var body := bodies[b]
		var step_text := ""
		if b > 0:
			var drop := bodies[b - 1].level_m - body.level_m
			var fall := WaterFalls.is_fall(doc, bodies[b - 1], body)
			step_text = " step %.2f %s" % [drop, "FALL" if fall else "riffle"]
		lines.append(
			(
				"%d: %d pts level %.2f hw %.2f%s"
				% [body.id, body.points.size(), body.level_m, body.half_widths[0], step_text]
			)
		)
	return "old river %s: %s" % [WaterBody.DEPTH_NAMES[depth], "; ".join(lines)]


## WaterEdit.plan_river exactly as v0.1.29 shipped it (test_water_falls.gd's frozen copy:
## join, resample, clamp, ground with the water-level override, reach_ranges, bodies).
static func _plan_river_v0_1_29(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED
) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	if doc.heights.size() != doc.sample_count():
		return bodies
	var joined := WaterEdit.join_line(doc, points, half_widths)
	var line: Array = WaterEdit.resample(joined[0], joined[1])
	var course: PackedVector2Array = line[0]
	var widths: PackedFloat32Array = line[1]
	if course.size() < 2:
		return bodies
	var narrowest := maxf(WaterBody.MIN_HALF_WIDTH_M, WaterCarve.min_half_width(depth))
	for i in widths.size():
		widths[i] = clampf(widths[i], narrowest, WaterBody.MAX_HALF_WIDTH_M)
	var ground := WaterGeometry.ground_along(doc, course)
	for i in course.size():
		var level := WaterGeometry.level_at(doc, course[i])
		if level != WaterGeometry.DRY and ground[i] < level:
			ground[i] = level + WaterGeometry.FREEBOARD_M
	var ranges := WaterGeometry.reach_ranges(ground)
	var rivers := 0
	for body in doc.water_bodies:
		rivers += 1 if body.is_river() else 0
	if (
		doc.water_bodies.size() + ranges.size() > MapDocument.MAX_WATER_BODIES
		or rivers + ranges.size() > MapDocument.MAX_RIVERS
	):
		return bodies
	var next := doc.next_water_id()
	var used := {}
	for body in doc.water_bodies:
		used[body.id] = true
	for reach in ranges:
		while next > 0 and next <= WaterBody.MAX_ID and used.has(next):
			next += 1
		if next <= 0 or next > WaterBody.MAX_ID:
			bodies.clear()
			return bodies
		used[next] = true
		bodies.append(
			WaterBody.river(
				next,
				course.slice(reach.x, reach.y + 1),
				widths.slice(reach.x, reach.y + 1),
				depth,
				WaterGeometry.reach_level(ground, reach),
				clampf(speed, 0.0, WaterBody.MAX_SPEED)
			)
		)
	return bodies
