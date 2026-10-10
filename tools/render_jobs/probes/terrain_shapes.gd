extends RefCounted

## Render-job probe (`call` op) for the ground shader's automatic dressing (phase 3, P3-4):
## writes terrain shapes straight into the document heights and paints surfaces straight
## into its surface weights (exact, repeatable shapes for judging the dressing; the Sculpt
## tool's own tiers are HeightBrush.tier_goal, see jobs/sculpt_look.json, and there is no
## Paint tool yet), then refreshes the terrain, collision, plants and ground the way an edit
## does.
## step.action picks what it does (positions are map XZ metres):
##   plateau {at, size, tiers, tier_m, inset, corner, lip, lip_width}  stacked flat tiers
##                         with sharp faces (a one-sample step): tier k is the rectangle
##                         `size` centred on `at`, shrunk by inset * (k - 1) each side,
##                         corners rounded by `corner`, at height k * tier_m (default 1.524,
##                         the 5 ft tier); its top edge rounds down by `lip` metres over
##                         `lip_width` (default 0: a square edge), the user's "slightly
##                         rounded top lip" (the Sculpt tool's tiers have their own).
##   hill {at, height, radius}   a round cosine hill added to the heights.
##   hollow {at, radius, depth}  a round pit with a sharp wall, `depth` below the ground.
##   path {surface, points, width, soft}  paints `surface` along the polyline, full weight
##                         within width / 2 and falling to 0 over `soft` metres.
##   area {surface, rect, corner, soft}   paints `surface` over rect [x0, z0, x1, z1].
##   stats {area}          logs the automatic dressing over `area` ([x0, z0, x1, z1]): the
##                         shares of samples by rule weight, from TerrainRules (the CPU
##                         twin of the shader).


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var editor := ctrl.editor
	var doc := ctrl.document
	match String(step.get("action", "")):
		"plateau":
			return _heights(editor, doc, step, _plateau)
		"hill":
			return _heights(editor, doc, step, _hill)
		"hollow":
			return _heights(editor, doc, step, _hollow)
		"path", "area":
			return _paint(editor, doc, step)
		"stats":
			return _stats(ctrl, doc, step.get("area", [-30, -30, 30, 30]))
	return "unknown action %s" % step.get("action", "")


## Applies `shape` (Callable(p: Vector2, h: float, step) -> float) to every sample, then
## refreshes everything an undo of a height edit would.
static func _heights(
	editor: AuthoringEditor, doc: MapDocument, step: Dictionary, shape: Callable
) -> String:
	editor.finish_height_work()
	var before := doc.heights.duplicate()
	var changed := Rect2i()
	var started := Time.get_ticks_usec()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			var p := doc.sample_to_world(Vector2(x, z))
			var h: float = shape.call(p, doc.heights[i], step)
			if not is_equal_approx(h, doc.heights[i]):
				doc.heights[i] = h
				changed = MaskBrush.merge_rect(changed, Rect2i(x, z, 1, 1))
	if not changed.has_area():
		return "%s: nothing changed" % step.get("action", "")
	editor.heights.begin_snap(before, true)
	editor.heights.queue_heights(changed)
	editor.finish_height_work()
	editor.terrain.settle_heights()
	editor.finish_height_work()
	editor.heights.regenerate(changed)
	return (
		"%s: %d x %d samples changed, %.1f ms"
		% [
			step.get("action", ""),
			changed.size.x,
			changed.size.y,
			(Time.get_ticks_usec() - started) / 1000.0
		]
	)


static func _vec(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


## Signed distance from `p` to a rectangle centred on `centre` with half size `half` and
## corner radius `corner` (negative inside).
static func _rect_distance(p: Vector2, centre: Vector2, half: Vector2, corner: float) -> float:
	var q := (p - centre).abs() - half + Vector2(corner, corner)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner


static func _plateau(p: Vector2, h: float, step: Dictionary) -> float:
	var at := _vec(step.get("at"), Vector2.ZERO)
	var size := _vec(step.get("size"), Vector2(10, 8))
	var tier_m := float(step.get("tier_m", 1.524))
	var inset := float(step.get("inset", 2.0))
	var corner := float(step.get("corner", 1.0))
	var lip := float(step.get("lip", 0.0))
	var lip_width := float(step.get("lip_width", 0.8))
	var out := h
	for k in range(1, int(step.get("tiers", 2)) + 1):
		var half := size * 0.5 - Vector2.ONE * inset * (k - 1)
		if half.x <= 0.0 or half.y <= 0.0:
			break
		var d := _rect_distance(p, at, half, minf(corner, minf(half.x, half.y)))
		if d <= 0.0:
			var t := clampf(-d / maxf(lip_width, 1e-3), 0.0, 1.0)
			out = maxf(out, k * tier_m - lip * (1.0 - t * t * (3.0 - 2.0 * t)))
	return out


static func _hill(p: Vector2, h: float, step: Dictionary) -> float:
	var at := _vec(step.get("at"), Vector2.ZERO)
	var radius := float(step.get("radius", 9.0))
	var d := p.distance_to(at)
	if d >= radius:
		return h
	return h + float(step.get("height", 6.0)) * 0.5 * (1.0 + cos(PI * d / radius))


static func _hollow(p: Vector2, h: float, step: Dictionary) -> float:
	var at := _vec(step.get("at"), Vector2.ZERO)
	if p.distance_to(at) > float(step.get("radius", 3.5)):
		return h
	return h - float(step.get("depth", 1.524))


static func _paint(editor: AuthoringEditor, doc: MapDocument, step: Dictionary) -> String:
	var surface := String(step.get("surface", "cobblestone"))
	var slot := doc.ensure_surface(surface)
	if slot < 0:
		return "paint: no slot for %s" % surface
	var soft := float(step.get("soft", 0.6))
	var distance: Callable
	if String(step.action) == "path":
		var points: Array = step.get("points", [[0, 0], [1, 0]])
		var half_width := float(step.get("width", 2.0)) * 0.5
		distance = func(p: Vector2) -> float:
			var best := INF
			for k in range(1, points.size()):
				var a := _vec(points[k - 1], Vector2.ZERO)
				var b := _vec(points[k], Vector2.ZERO)
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
			return best - half_width
	else:
		var r: Array = step.get("rect", [-3, -3, 3, 3])
		var low := Vector2(float(r[0]), float(r[1]))
		var high := Vector2(float(r[2]), float(r[3]))
		var corner := float(step.get("corner", 0.8))
		distance = func(p: Vector2) -> float:
			return _rect_distance(p, (low + high) * 0.5, (high - low) * 0.5, corner)
	var changed := Rect2i()
	var count := doc.sample_count()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var d: float = distance.call(doc.sample_to_world(Vector2(x, z)))
			if d >= soft:
				continue
			var t := clampf(1.0 - d / maxf(soft, 1e-3), 0.0, 1.0) if d > 0.0 else 1.0
			var value := roundi(255.0 * t * t * (3.0 - 2.0 * t))
			var i := doc.sample_index(x, z)
			if value > doc.surface_weights[MapDocument.surface_offset(i, slot, count)]:
				doc.set_surface_weight(i, slot, value)
				changed = MaskBrush.merge_rect(changed, Rect2i(x, z, 1, 1))
	if changed.has_area():
		editor.call("_refresh", changed)
	return "paint %s slot %d: %d x %d samples" % [surface, slot, changed.size.x, changed.size.y]


static func _stats(ctrl: AuthoringController, doc: MapDocument, area: Array) -> String:
	var terrain := ctrl.editor.terrain
	var fields := terrain.get_rule_fields()
	var heights := doc.heights
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var seed_value := doc.map_seed & 0x7FFFFFFF
	var low := Vector2i(doc.world_to_sample(Vector2(float(area[0]), float(area[1]))).floor())
	var high := Vector2i(doc.world_to_sample(Vector2(float(area[2]), float(area[3]))).ceil())
	low = low.clamp(Vector2i.ZERO, Vector2i(columns - 1, rows - 1))
	high = high.clamp(Vector2i.ZERO, Vector2i(columns - 1, rows - 1))
	var n := 0
	var cliff_full := 0
	var cliff_some := 0
	var scree_some := 0
	var steep := 0
	var steep_rock := 0
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var s := Vector2(x, z)
			var normal := ScatterGenerator.triangle_normal(heights, columns, rows, s, step)
			var f := TerrainRules.field_at(fields.curvature, fields.steep, columns, rows, s)
			var p := doc.sample_to_world(s)
			var w := TerrainRules.weights(normal.y, f, p, heights[z * columns + x], seed_value)
			n += 1
			cliff_full += 1 if w.x > 0.95 else 0
			cliff_some += 1 if w.x > 0.05 else 0
			scree_some += 1 if w.y > 0.05 else 0
			if normal.y < cos(deg_to_rad(65.0)):
				steep += 1
				steep_rock += 1 if w.x > 0.95 else 0
	return (
		(
			"stats %s: %d samples | cliff > 0.95: %d, > 0.05: %d | scree > 0.05: %d"
			+ " | steeper than 65 deg: %d, of those fully rock: %d"
		)
		% [str(area), n, cliff_full, cliff_some, scree_some, steep, steep_rock]
	)
