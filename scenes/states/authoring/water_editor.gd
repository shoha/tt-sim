class_name WaterEditor
extends RefCounted

## AuthoringEditor's water edits (phase 4, P4-3; the Water tool, P4-4, calls them through
## `AuthoringEditor.water`): carving a river, painting a pond, erasing water. It owns the
## pond and erase strokes in progress and shares the editor's ground machinery with sculpt
## strokes (the height queue, the per-frame snap of plants and props, rock keeping, the
## scatter regeneration, history), reaching into the editor for it: it is part of the editor,
## split out only to keep one class a readable size. Frames: world in, document inside, as
## the editor. Summary and the rules: docs/ARCHITECTURE.md "Carving water".
##
## Each operation is one history entry: the heights diff (HeightStroke.lower_to, a one-shot
## carve recorded like a dab), the water model before and after (WaterEdit.model_of), the wet
## dressing before and after, the props cells it changed, the rocks it kept and the crossings
## that followed it (CrossingEditor.follow, P4b-2); undo and redo put either side back
## exactly (_apply()).
##
## The heavy, pure half of an edit (P4-4) runs in compute() on a snapshot of the document:
## the carve's goal heights (WaterCarve), the wet dressing of the result (WaterDressing) and
## which body owns each sample (for the rock rule). With `use_worker` (the Water tool) it runs
## on a WorkerThreadPool task and the document is untouched until the result lands; without
## (tests, probes) it runs at once on this thread. Either way the same function computes it
## and _land() applies it the same way, so the result is identical. Landing is split over
## three frames so none holds the main thread long: the document and the ground (heights, the
## terrain's chunks, collision and plant snapping; the water surface's own rebuild is started
## on its worker), then the terrain's settle (its rule fields), then the rest (the dressing
## texture, rocks, the scatter regeneration and the history entry). While an edit is
## computing or landing (is_working()), AuthoringEditor.has_height_work() is true, so a save
## or an autosave waits, and finish_work() (from AuthoringEditor.finish_height_work(), which
## every other edit and undo call first) lands it at once.

## Why the last carve_river() or paint_pond_begin() made nothing (last_refusal), for the tool.
const REFUSED_NO_CARVE := &"no_carve"
const REFUSED_SHORT := &"short"
const REFUSED_FULL := &"full"
const REFUSED_IN_WATER := &"in_water"

## Why the last carve_river() or paint_pond_begin() made nothing (REFUSED_*), or &"".
var last_refusal: StringName = &""
## True: compute() runs on a worker (the Water tool). False: on this thread (tests, probes).
var use_worker: bool = false
## Microseconds of the last water edit's parts (main thread, and the worker's "compute"),
## for measurement.
var timings: Dictionary = {}
## A pond stroke in progress: {"id", "depth", "before": WaterEdit.model_of(), "rect": Rect2i
## of samples painted}, or {}.
var _pond: Dictionary = {}
## A water erase in progress: {"before", "touched": river id -> true (whole reaches), "shrunk":
## pond id -> true, "area": Rect2 map XZ swept}, or {}.
var _erase: Dictionary = {}
## The edit computing or waiting to land: {"task" (-1: computed on this thread), "spec",
## "result", "before": the water model before, "dressing_before"}, or {}.
var _job: Dictionary = {}
## The second half of a landed edit (Callable), run by step() on a later frame, or none.
var _follow: Callable = Callable()
var _follow_frame: int = -1
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> WaterEditor:
	var water := WaterEditor.new()
	water._owner = weakref(editor)
	return water


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## True when water can be carved (a river or a pond): the map's ground is an AuthoredTerrain.
## Erasing water needs no carving and works on any map with water.
func can_carve() -> bool:
	return _editor().can_sculpt()


## True while a pond or erase stroke is in progress.
func is_stroking() -> bool:
	return not _pond.is_empty() or not _erase.is_empty()


## True while an edit is computing on a worker or still landing (see the header).
func is_working() -> bool:
	return not _job.is_empty() or _follow.is_valid()


## Carves a river along `points` (world XZ as Vector2(x, z), upstream first: the water flows
## toward the last point) with a half-width per point (`half_widths`, world metres; one
## value for all points works too), of depth class `depth_class` and flow `speed`: the line
## is split into flat reaches (WaterEdit.plan_river; an end in existing water joins it), their
## channel is carved (WaterCarve), the water, its dressing and flow are refreshed and the
## plants regrow around it; one history entry. Returns the id of the first (upstream) reach,
## or -1 when nothing was made (the map cannot be carved, the line is too short or lies in
## water, or the document is full). With use_worker the carve lands on a later frame.
func carve_river(
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth_class: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED
) -> int:
	var e := _editor()
	_prepare()
	last_refusal = &""
	if not can_carve():
		last_refusal = REFUSED_NO_CARVE
		return -1
	if points.size() < 2:
		last_refusal = REFUSED_SHORT
		return -1
	var doc := e.document
	var line := PackedVector2Array()
	for p in points:
		line.append(e.to_map_xz(Vector3(p.x, 0.0, p.y)))
	var widths := PackedFloat32Array()
	for w in half_widths:
		widths.append(w / e.map_scale())
	if widths.size() == 1:
		var only := widths[0]
		widths.resize(line.size())
		widths.fill(only)
	var bodies := WaterEdit.plan_river(doc, line, widths, depth_class, speed)
	if bodies.is_empty():
		var joined: PackedVector2Array = WaterEdit.join_line(doc, line, widths)[0]
		last_refusal = REFUSED_IN_WATER if joined.size() < 2 else REFUSED_FULL
		return -1
	_start({"kind": "river", "label": "Carve river", "bodies": bodies}, WaterEdit.model_of(doc))
	return bodies[0].id


## Starts painting a pond of depth class `depth_class`, pressed at world point `at`: a press
## inside a pond extends it (and gives it this depth), elsewhere a new pond begins. Dabs
## (paint_pond_dab, or the editor's stroke_dab) mark its area on the sample grid;
## paint_pond_end (or end_stroke) sets its level from the lowest ground on its rim, carves the
## basin and fills it. False when the map cannot be carved or holds MAX_WATER_BODIES bodies.
func paint_pond_begin(depth_class: WaterBody.Depth, at: Vector3) -> bool:
	var e := _editor()
	_prepare()
	last_refusal = &""
	if not can_carve():
		last_refusal = REFUSED_NO_CARVE
		return false
	var doc := e.document
	var id := WaterEdit.pond_id_at(doc, e.to_map_xz(at))
	var full := doc.water_bodies.size() >= MapDocument.MAX_WATER_BODIES
	if id <= 0 or (full and doc.water_body(id) == null):
		last_refusal = REFUSED_FULL
		return false
	var before := WaterEdit.model_of(doc)
	if doc.pond_mask.size() != doc.sample_count():
		var mask := PackedByteArray()
		mask.resize(doc.sample_count())
		doc.pond_mask = mask
	_pond = {"id": id, "depth": depth_class, "before": before, "rect": Rect2i()}
	# Extending a pond: its basin is carved again as one shape at no lower a level than
	# before (compute()), so the stroke needs the area and level it had.
	var existing := doc.water_body(id)
	if existing != null:
		_pond["old_area"] = doc.pond_mask.duplicate()
		_pond["old_level"] = existing.level_m
	return true


## Marks the capsule from `from` to `to` (world) of world radius `radius` as the pond's area
## (samples of no other pond).
func paint_pond_dab(from: Vector3, to: Vector3, radius: float) -> void:
	if _pond.is_empty():
		return
	var e := _editor()
	var rect := WaterEdit.stamp(
		e.document,
		e.document.pond_mask,
		e.to_map_xz(from),
		e.to_map_xz(to),
		radius / e.map_scale(),
		int(_pond.id),
		PackedByteArray([0])
	)
	_pond.rect = MaskBrush.merge_rect(_pond.rect, rect)


## The pond stroke in progress: its id, or -1.
func pond_in_progress() -> int:
	return int(_pond.get("id", -1))


## Ends the pond stroke: level, basin carve, water, dressing, plants; one history entry.
## False when the stroke painted nothing.
func paint_pond_end() -> bool:
	var pond := _pond
	_pond = {}
	if pond.is_empty():
		return false
	var doc := _editor().document
	var painted: Rect2i = pond.rect
	if not painted.has_area():
		WaterEdit.apply_model(doc, pond.before)
		return false
	var spec := {
		"kind": "pond",
		"label": "Paint pond",
		"id": int(pond.id),
		"depth": pond.depth,
		"rect": painted,
	}
	if pond.has("old_area"):
		spec["old_area"] = pond.old_area
		spec["old_level"] = pond.old_level
	_start(spec, pond.before)
	return true


## Starts erasing water: dabs (erase_water_dab, or stroke_dab) remove pond area under the
## brush and mark the river reaches it touches; erase_water_end (or end_stroke) drops those
## reaches whole, drops emptied ponds and settles shrunk ones to their new rim. The ground
## stays as carved. False when the map has no water.
func erase_water_begin() -> bool:
	var doc := _editor().document
	_prepare()
	if doc.water_bodies.is_empty():
		return false
	_erase = {"before": WaterEdit.model_of(doc), "touched": {}, "shrunk": {}, "area": Rect2()}
	return true


## Erases the water under the capsule from `from` to `to` (world) of world radius `radius`.
func erase_water_dab(from: Vector3, to: Vector3, radius: float) -> void:
	if _erase.is_empty():
		return
	var e := _editor()
	var a := e.to_map_xz(from)
	var b := e.to_map_xz(to)
	var r := radius / e.map_scale()
	var any_pond := PackedByteArray()
	for id in range(1, WaterBody.MAX_ID + 1):
		any_pond.append(id)
	WaterEdit.stamp(e.document, e.document.pond_mask, a, b, r, 0, any_pond, _erase.shrunk)
	WaterEdit.touch_rivers(e.document, _erase.touched, a, b, r)
	var swept := Rect2(a, Vector2.ZERO).expand(b).grow(r)
	var area: Rect2 = _erase.area
	_erase.area = swept if not area.has_area() else area.merge(swept)


## The river reaches the erase in progress will remove (their bodies), for the tool's preview.
func erase_touched() -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	if _erase.is_empty():
		return out
	for body in _editor().document.water_bodies:
		if (_erase.touched as Dictionary).has(body.id):
			out.append(body)
	return out


## Ends the water erase; one history entry. False when nothing was erased.
func erase_water_end() -> bool:
	var erase := _erase
	_erase = {}
	if erase.is_empty():
		return false
	var doc := _editor().document
	var touched: Dictionary = erase.touched
	var shrunk: Dictionary = erase.shrunk
	if touched.is_empty() and shrunk.is_empty():
		return false
	var removed: Array[WaterBody] = []
	for body in doc.water_bodies:
		if touched.has(body.id):
			removed.append(body)
	var area: Rect2 = erase.area
	var rivers := WaterEdit.rivers_bounds(removed, WaterGeometry.RIVER_BANK_M)
	if rivers.has_area():
		area = area.merge(rivers) if area.has_area() else rivers
	_start(
		{
			"kind": "erase",
			"label": "Erase water",
			"touched": touched,
			"shrunk": shrunk,
			"area": area,
		},
		erase.before
	)
	return true


## Forwards the editor's generic stroke calls to the pond or erase stroke in progress.
func dab(from: Vector3, to: Vector3, radius: float) -> void:
	if not _pond.is_empty():
		paint_pond_dab(from, to, radius)
	elif not _erase.is_empty():
		erase_water_dab(from, to, radius)


func end_stroke() -> bool:
	return paint_pond_end() if not _pond.is_empty() else erase_water_end()


## Abandons a pond or water erase stroke, putting the water model back.
func cancel_stroke() -> void:
	var stroke := _pond if not _pond.is_empty() else _erase
	_pond = {}
	_erase = {}
	if not stroke.is_empty():
		WaterEdit.apply_model(_editor().document, stroke.before)


## The wet dressing and the water surface from the document as it is now (a sculpt stroke on
## a map with water; its undo and redo), then `then` (optional): the stroke's rock keeping and
## regeneration, which read the new dressing. With use_worker (P4-5) the dressing is computed
## on a worker from a snapshot, like an edit's, and lands on a later frame (step(), or at once
## from finish_work()); it cost the main thread 110-175 ms on a 150 ft map with water. A map
## without water has nothing to refresh: `then` runs at once.
func refresh(then: Callable = Callable()) -> void:
	finish_work()
	var doc := _editor().document
	if doc.water_bodies.is_empty():
		if then.is_valid():
			then.call()
		return
	timings = {}
	var snapshot := snapshot_of(doc)
	var result := {}
	var spec := {"kind": "dressing", "then": then}
	var job := {"task": -1, "spec": spec, "result": result, "before": {}, "dressing_before": {}}
	if use_worker:
		job.task = WorkerThreadPool.add_task(
			func() -> void: compute(snapshot, spec, result), false, "Wet dressing"
		)
		_job = job
		return
	compute(snapshot, spec, result)
	_job = job
	finish_work()


## Landing a dressing refresh (refresh()): the field, the ground's texture, the surface, then
## the caller's follow-up.
func _land_dressing(spec: Dictionary, result: Dictionary) -> void:
	var e := _editor()
	var t0 := Time.get_ticks_usec()
	e.document.water_dressing = result.dressing
	if is_instance_valid(e.terrain):
		e.terrain.refresh_water_dressing()
	if is_instance_valid(e.map_root):
		AuthoredWater.refresh_map(e.map_root, e.document)
	timings["dressing_upload"] = Time.get_ticks_usec() - t0
	var then: Callable = spec.then
	if then.is_valid():
		then.call()


## Once per frame (AuthoringEditor.step_height_work): lands a finished worker edit, or runs
## the second half of one landed on an earlier frame.
func step() -> void:
	if _follow.is_valid():
		if Engine.get_process_frames() != _follow_frame:
			var follow := _follow
			_follow = Callable()
			follow.call()
		return
	if _job.is_empty():
		return
	if int(_job.task) < 0 or WorkerThreadPool.is_task_completed(int(_job.task)):
		_land()


## Lands the edit in progress at once, every part (waiting for its worker).
func finish_work() -> void:
	if not _job.is_empty():
		_land()
	while _follow.is_valid():
		var follow := _follow
		_follow = Callable()
		follow.call()


## Waits for a computing edit and drops it, landed or not (the map is closing).
func release() -> void:
	if not _job.is_empty() and int(_job.task) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(_job.task))
	_job = {}
	_follow = Callable()


## Ends whatever is in progress before a water edit, so it starts from settled ground.
func _prepare() -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()


# ============================================================================
# Computing an edit
# ============================================================================


## A copy of what compute() reads of `doc` (the grid, heights, seed, water bodies and pond
## mask), safe to hand to a worker while `doc` is edited.
static func snapshot_of(doc: MapDocument) -> MapDocument:
	var copy := WaterMeshBuilder.snapshot(doc)
	copy.map_seed = doc.map_seed
	return copy


## The pure half of an edit (see the header) on `snapshot` (snapshot_of(), consumed: it ends
## as the document after the edit): `spec` says which ({"kind": "river", "bodies"}, {"kind":
## "pond", "id", "depth"} or {"kind": "erase", "touched", "shrunk"}). Fills `out` with
## "goals" (WaterCarve goals, river and pond), "level" (pond), "bodies" (erase), "dressing"
## (WaterDressing field after the edit), "owners" (WaterMeshBuilder.sample_owners after it)
## and "usec". Touches no Node; safe on any thread.
static func compute(snapshot: MapDocument, spec: Dictionary, out: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	match String(spec.kind):
		"river":
			var bodies: Array[WaterBody] = spec.bodies
			# The reaches' fall flags (WaterFalls.fall_flags, P4c-2) come from the bodies inside
			# river_goals, so the worker and the synchronous carve read the same ones.
			var goals := WaterCarve.river_goals(snapshot, bodies, snapshot.heights)
			out["goals"] = goals
			lower(snapshot, goals)
			snapshot.water_bodies = WaterEdit.with_bodies(snapshot, bodies)
		"pond":
			var id: int = spec.id
			var level := WaterGeometry.pond_rim_level(snapshot, id)
			if spec.has("old_area"):
				level = extended_pond_level(snapshot, id, spec.old_area, float(spec.old_level))
			var body := WaterBody.pond(id, spec.depth, level)
			snapshot.water_bodies = _with_pond(snapshot, body)
			var goals := WaterCarve.pond_goals(snapshot, body, snapshot.heights)
			out["level"] = level
			out["goals"] = goals
			lower(snapshot, goals)
		"erase":
			var bodies := WaterEdit.erased_bodies(snapshot, spec.touched, spec.shrunk)
			out["bodies"] = bodies
			snapshot.water_bodies = bodies
	out["dressing"] = WaterDressing.refresh(snapshot)
	if String(spec.kind) != "dressing":
		out["owners"] = WaterMeshBuilder.sample_owners(snapshot)
	out["usec"] = Time.get_ticks_usec() - started


## `doc`'s heights lowered to `goals` (WaterCarve goals) exactly as HeightStroke.lower_to
## lowers them.
static func lower(doc: MapDocument, goals: Dictionary) -> void:
	var rect: Rect2i = goals.get("rect", Rect2i())
	var values: PackedFloat32Array = goals.get("goals", PackedFloat32Array())
	if not rect.has_area() or values.size() != rect.size.x * rect.size.y:
		return
	var heights := doc.heights
	var width := doc.samples_x()
	var limit := MapDocument.MAX_ABS_HEIGHT_M
	for j in rect.size.y:
		var z := rect.position.y + j
		if z < 0 or z >= doc.samples_z():
			continue
		for i in rect.size.x:
			var x := rect.position.x + i
			if x < 0 or x >= width:
				continue
			var goal := values[j * rect.size.x + i]
			var at := z * width + x
			if is_inf(goal) or goal >= heights[at]:
				continue
			heights[at] = minf(heights[at], maxf(goal, -limit))
	doc.heights = heights


## The level of pond `id` of `doc` after a stroke extended it from `old_area` (the pond mask
## before the stroke) at `old_level` (P4-5): the lowest rim ground less the freeboard, as a
## new pond's, except that ground its own basin carved (within WaterCarve.BANK_REACH_M of the
## old area) counts as at least the old level plus the freeboard, and never above the old
## level. Read from that carved ground, every extension sank the pond by the freeboard, and
## the old basin, carved again only as far as its eased top allowed, stood as a ledge under
## the new water.
static func extended_pond_level(
	doc: MapDocument, id: int, old_area: PackedByteArray, old_level: float
) -> float:
	var count := doc.sample_count()
	var feature := PackedByteArray()
	feature.resize(count)
	for i in mini(old_area.size(), count):
		if old_area[i] == id:
			feature[i] = 1
	var field := DistanceField.transform(
		feature, doc.samples_x(), doc.samples_z(), doc.sample_step()
	)
	var distance_sq: PackedFloat32Array = field.distance_sq
	var near := PackedByteArray()
	near.resize(count)
	var reach_sq := WaterCarve.BANK_REACH_M * WaterCarve.BANK_REACH_M
	for i in count:
		if distance_sq[i] <= reach_sq:
			near[i] = 1
	var level := WaterGeometry.pond_rim_level(doc, id, near, old_level + WaterGeometry.FREEBOARD_M)
	return minf(level, old_level)


## `doc`'s bodies with pond `body` in place of any body with its id.
static func _with_pond(doc: MapDocument, body: WaterBody) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	for other in doc.water_bodies:
		if other.id != body.id:
			bodies.append(other)
	bodies.append(body)
	return bodies


## Starts an edit (compute() on a snapshot; see the header). `before` is the water model the
## edit's undo returns to.
func _start(spec: Dictionary, before: Dictionary) -> void:
	var doc := _editor().document
	timings = {}
	var snapshot := snapshot_of(doc)
	var result := {}
	var job := {
		"task": -1,
		"spec": spec,
		"result": result,
		"before": before,
		"dressing_before": doc.water_dressing,
	}
	if use_worker:
		job.task = WorkerThreadPool.add_task(
			func() -> void: compute(snapshot, spec, result), false, "Water edit"
		)
		_job = job
		return
	compute(snapshot, spec, result)
	_job = job
	finish_work()


# ============================================================================
# Landing an edit
# ============================================================================


## Landing the edit in _job, first frame (waiting for its worker): the document takes the
## edit's water and heights, the terrain, collision and plants follow the ground, and the
## water surface's rebuild starts; _settle() and _finish() follow on the next frames.
func _land() -> void:
	var job := _job
	_job = {}
	if int(job.task) >= 0:
		WorkerThreadPool.wait_for_task_completion(int(job.task))
	var e := _editor()
	var doc := e.document
	var spec: Dictionary = job.spec
	var result: Dictionary = job.result
	timings["compute"] = int(result.get("usec", 0))
	if String(spec.kind) == "dressing":
		_land_dressing(spec, result)
		return
	var t0 := Time.get_ticks_usec()
	var stroke: HeightStroke = null
	var region := Rect2i()
	match String(spec.kind):
		"river":
			doc.water_bodies = WaterEdit.with_bodies(doc, spec.bodies)
			stroke = HeightStroke.begin(doc, HeightBrush.LOWER)
			var goals: Dictionary = result.goals
			stroke.lower_to(goals.rect, goals.goals)
			var bounds := WaterEdit.rivers_bounds(spec.bodies, WaterCarve.BANK_REACH_M)
			region = _sample_rect_of(bounds)
		"pond":
			var body := WaterBody.pond(int(spec.id), spec.depth, float(result.level))
			doc.water_bodies = _with_pond(doc, body)
			stroke = HeightStroke.begin(doc, HeightBrush.LOWER)
			var goals: Dictionary = result.goals
			stroke.lower_to(goals.rect, goals.goals)
			var carved: Rect2i = goals.rect
			region = carved.merge(spec.rect) if carved.has_area() else spec.rect
		"erase":
			doc.water_bodies = result.bodies
			region = _sample_rect_of(spec.area)
	timings["lower"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var diff := {}
	if stroke != null:
		e._snap_before = stroke.start_heights
		e._snap_windows.clear()
		e._snap_start.clear()
		e._prop_start.clear()
		e._aligned = DressingGround.aligned_assets(doc.biome_ids, e.palette_root)
		e._rocks = RockKeep.rock_assets(doc.biome_ids, e.palette_root)
		e._queue_heights(stroke.take_pending())
		e._work(true)
		diff = stroke.finish()
		region = region.merge(stroke.changed) if stroke.changed.has_area() else region
	timings["ground"] = Time.get_ticks_usec() - t0
	# The shore band reaches past the water's area.
	var step := doc.sample_step()
	var shore := WaterDressing.SHORE_FAR_M + WaterDressing.SHORE_NOISE_M + 0.5
	region = region.grow(ceili(shore / minf(step.x, step.y))).intersection(
		Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	)
	doc.water_dressing = result.dressing
	if is_instance_valid(e.map_root):
		AuthoredWater.refresh_map(e.map_root, doc)
	_then(_settle.bind(String(spec.label), stroke, diff, job, region))


## Runs `follow` on the next frame (step()), or at once from finish_work().
func _then(follow: Callable) -> void:
	_follow = follow
	_follow_frame = Engine.get_process_frames()


## Landing, second frame: the terrain settles (its rule fields over the carve).
func _settle(
	label: String, stroke: HeightStroke, diff: Dictionary, job: Dictionary, region: Rect2i
) -> void:
	var e := _editor()
	var t0 := Time.get_ticks_usec()
	if stroke != null and is_instance_valid(e.terrain):
		e.terrain.settle_heights()
	timings["settle"] = Time.get_ticks_usec() - t0
	_then(_finish.bind(label, stroke, diff, job, region))


## Landing, third frame: the dressing texture (the first water on a map re-plans the ground's
## layers too), rocks, the scatter regeneration, and the history entry.
func _finish(
	label: String, stroke: HeightStroke, diff: Dictionary, job: Dictionary, region: Rect2i
) -> void:
	var e := _editor()
	var doc := e.document
	var t0 := Time.get_ticks_usec()
	if is_instance_valid(e.terrain):
		e.terrain.refresh_water_dressing()
	timings["dressing_upload"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var before: Dictionary = job.before
	var after := WaterEdit.model_of(doc)
	var dressing_before: PackedByteArray = job.dressing_before
	var record := {
		"props_before": {},
		"props_after": {},
		"kept": {},
		"water_before": before,
		"water_after": after,
		"dressing_before": _pack(dressing_before),
		"dressing_after": _pack(doc.water_dressing),
		"region": region,
		# Crossings follow their water and banks, in this edit's entry (P4b-2).
		"crossings": e.crossings.follow(MaskBrush.sample_rect_to_world(doc, region)),
	}
	for cell in e._prop_start:
		record.props_before[cell] = (e._prop_start[cell] as Dictionary).duplicate(true)
	var keep := _wet_rock_rule(job.result.owners)
	_drop_wet_rocks(region, keep, record)
	var props_bytes := 0
	for cell in record.props_before:
		record.props_after[cell] = e.props.cell_rows(cell).duplicate(true)
		props_bytes += PropRows.rows_bytes(record.props_before[cell]) * 2
	timings["rocks"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var started := false
	if stroke != null and not diff.is_empty():
		var area: Rect2 = e._regenerated_area(region)
		started = e.rock_keeper.start(
			stroke.start_heights, region, area, record, e._rocks, dressing_before, keep
		)
	if not started:
		e._regenerate(region)
	timings["regenerate"] = Time.get_ticks_usec() - t0
	var bytes := int(diff.get("bytes", 0)) + props_bytes
	bytes += WaterEdit.model_bytes(before) + WaterEdit.model_bytes(after)
	bytes += (record.dressing_before.data as PackedByteArray).size()
	bytes += (record.dressing_after.data as PackedByteArray).size()
	(
		e
		. history
		. record(
			{
				"label": label,
				"undo": _apply.bind(diff, false, record),
				"redo": _apply.bind(diff, true, record),
				"bytes": bytes,
			}
		)
	)
	e.edited.emit()


## A dressing field ZSTD-packed for history: {"data", "size"}.
static func _pack(field: PackedByteArray) -> Dictionary:
	if field.is_empty():
		return {"data": PackedByteArray(), "size": 0}
	return {"data": field.compress(WaterEdit.COMPRESSION), "size": field.size()}


static func _unpack(packed: Dictionary) -> PackedByteArray:
	var size: int = packed.get("size", 0)
	if size <= 0:
		return PackedByteArray()
	return (packed.data as PackedByteArray).decompress(size, WaterEdit.COMPRESSION)


## Undo (`redo` false) or redo of a water edit (_finish()'s record): the heights, the water
## model and its dressing, props as recorded, kept rocks swapped, then the surface and plants.
func _apply(diff: Dictionary, redo: bool, record: Dictionary) -> void:
	var e := _editor()
	var doc := e.document
	e.finish_height_work()
	WaterEdit.apply_model(doc, record.water_after if redo else record.water_before)
	var prop_rows: Dictionary = record.props_after if redo else record.props_before
	if not diff.is_empty():
		var before := doc.heights.duplicate()
		var rect := HeightStroke.apply_diff(doc, diff, redo)
		e._snap_before = before
		e._snap_start.clear()
		e._prop_start.clear()
		e._aligned = DressingGround.aligned_assets(doc.biome_ids, e.palette_root)
		e._rocks = RockKeep.rock_assets(doc.biome_ids, e.palette_root)
		e._queue_heights(rect)
		# Props take their recorded rows, not a snap.
		e._snap_props = false
		e._work(true)
		e._snap_props = true
		e._snap_start.clear()
	e.crossings.restore(record.get("crossings", {}), redo)
	for cell in prop_rows:
		e._set_prop_cell(cell, prop_rows[cell], false)
	e.rock_keeper.swap(record.kept, redo)
	if is_instance_valid(e.terrain):
		e.terrain.settle_heights()
	doc.water_dressing = _unpack(record.dressing_after if redo else record.dressing_before)
	if is_instance_valid(e.terrain):
		e.terrain.refresh_water_dressing()
	if is_instance_valid(e.map_root):
		AuthoredWater.refresh_map(e.map_root, doc)
	e._regenerate(record.region)


## WaterCarve.keeps_rock() for the document's water as it is now, as Callable(asset id,
## row) -> bool: the level and channel width at the row's sample (its owning body, `owners`:
## WaterMeshBuilder.sample_owners of the document after the edit).
func _wet_rock_rule(owners: PackedInt32Array) -> Callable:
	var doc := _editor().document
	var root := _editor().palette_root
	return func(asset_id: String, row: PackedFloat32Array) -> bool:
		var p := Vector2(row[0], row[2])
		var s := doc.world_to_sample(p).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		var at := doc.sample_index(x, z)
		var owner := owners[at] if at < owners.size() else -1
		if owner < 0 or owner >= doc.water_bodies.size():
			return true
		var body := doc.water_bodies[owner]
		var channel := 0.0
		if body.is_river():
			var course := WaterGeometry.river_course(body)
			var near := WaterGeometry.nearest_on_polyline(course[0], p)
			if near.y >= 0:
				channel = 2.0 * WaterGeometry.width_at(course[1], int(near.y), near.z)
		var size: Variant = PaletteLibrary.asset(asset_id, root).get("dimensions_m")
		var tall: float = (size as Vector3).y if size is Vector3 else 0.5
		var radius := RockKeep.footprint_radius(asset_id, root)
		return WaterCarve.keeps_rock(row, tall, radius, body.level_m, channel)


## Removes the rock props of the cells over `region` (samples) that `keep` refuses (they
## shrink away), recording each changed cell's rows before in `record.props_before` (unless
## a snap already did).
func _drop_wet_rocks(region: Rect2i, keep: Callable, record: Dictionary) -> void:
	var e := _editor()
	if not is_instance_valid(e.props) or not region.has_area():
		return
	var rock_rules := {}
	var world := MaskBrush.sample_rect_to_world(e.document, region)
	for cell in ScatterGenerator.cells_in_bounds(world):
		var rows: Dictionary = e.props.cell_rows(cell).duplicate(true)
		var changed := false
		for asset_id: String in rows.keys():
			if not rock_rules.has(asset_id):
				rock_rules[asset_id] = RockKeep.is_rock(e.rule_for_asset(asset_id))
			if not rock_rules[asset_id]:
				continue
			var flat: PackedFloat32Array = rows[asset_id]
			var kept := PackedFloat32Array()
			@warning_ignore("integer_division")
			for r in flat.size() / MapDocument.ROW_STRIDE:
				var row := PropRows.row_at(flat, r)
				if keep.call(asset_id, row):
					kept.append_array(row)
			if kept.size() != flat.size():
				changed = true
				if kept.is_empty():
					rows.erase(asset_id)
				else:
					rows[asset_id] = kept
		if not changed:
			continue
		if not record.props_before.has(cell):
			record.props_before[cell] = e.props.cell_rows(cell).duplicate(true)
		e.props.set_cells({cell: rows}, true)


## The sample rectangle covering map rectangle `area` (clipped to the grid).
func _sample_rect_of(area: Rect2) -> Rect2i:
	var doc := _editor().document
	if not area.has_area():
		return Rect2i()
	var first := Vector2i(doc.world_to_sample(area.position).floor())
	var last := Vector2i(doc.world_to_sample(area.end).ceil())
	var rect := Rect2i(first, last - first + Vector2i.ONE)
	return rect.intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
