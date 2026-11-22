extends GutTest

## A held sculpt stroke on the painted look (card painter-held-stroke; docs/systems/painter.md
## "Water", "Zone maps"): the water field's flushes run on a worker over a snapshot and land a few
## frames later, the zone maps follow every few frames, and what lands equals the synchronous
## result: the landed field mid-stroke equals a whole build of the document as it is, the stroke's
## end while a job runs lands the same, and closing the map mid-task drops the task unwaited. A
## water landing (card painter-river-landing): its ground flush also redoes the new bodies, so the
## swap's refreshed signal redoes nothing, and a large flush runs on the same worker path.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const FIELD_ARRAYS := [
	"ground",
	"w",
	"ew",
	"depth",
	"energy",
	"steep",
	"shore",
	"lateral",
	"spill",
	"calm",
	"owner",
	"foot",
	"flow_u",
]
const BED := -1.0
const LEVEL := -0.2
## Beside the river along z = 0 (its bank reaches z = 1.5 plus the bank margin).
const BESIDE := Vector3(-2, 0, 2.5)

var _map: Node3D = null
var _doc: MapDocument = null
var _editor: AuthoringEditor = null
var _surfaces: PainterSurfaces = null
var _field: PainterWaterField = null


func after_each() -> void:
	if _editor != null and _editor.heights.is_sculpting():
		_editor.end_stroke()
	if _field != null:
		_field.detach()
	if _surfaces != null:
		_surfaces.release()
	_field = null
	_surfaces = null
	_editor = null
	# Dropped tasks are reaped once they complete.
	for i in 300:
		if PainterWaterField.abandoned_count() == 0:
			break
		await get_tree().process_frame


## An editor over a flat 24 m map with a river along z = 0 in a carved bed, painted, with the water
## field drawing it.
func _editor_on() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(24, 24), "grass_meadow", "v", 9)
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 9.0 and absf(p.y) <= 1.5:
				heights[_doc.sample_index(x, z)] = BED
	_doc.heights = heights
	var line := PackedVector2Array([Vector2(-9, 0), Vector2(9, 0)])
	_doc.water_bodies.append(
		WaterBody.river(1, line, PackedFloat32Array([1.5, 1.5]), WaterBody.Depth.WAIST, LEVEL)
	)
	WaterDressing.refresh(_doc)
	var terrain := AuthoredTerrain.create(_doc)
	_map.add_child(terrain)
	var scatter := AuthoredScatter.create()
	scatter.name = MapSourceLoader.SCATTER_NODE
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	AuthoredWater.refresh_map(_map, _doc)
	_water().finish_refresh()
	_editor = AuthoringEditor.create(_doc, _map, AuthoringHistory.new())
	_editor.scatter.attach_document(_doc)
	_surfaces = PainterSurfaces.new()
	assert_true(_surfaces.paint(_map, STATE), "painted")
	_field = PainterWaterField.new()
	var material := ShaderMaterial.new()
	material.shader = load(PainterWater.SHADER) as Shader
	assert_true(_field.attach(_map, material))
	await _settle()


func _water() -> AuthoredWater:
	return _map.get_node_or_null(NodePath(AuthoredWater.NODE_NAME)) as AuthoredWater


func _settle() -> void:
	if _editor != null:
		_editor.finish_height_work()
	if _water() != null:
		_water().finish_refresh()
	for i in 3:
		await get_tree().process_frame
	# A flush over ASYNC_SAMPLES runs on a worker even when not held (card painter-river-landing):
	# land it and the zone maps' worker build now (bounded: a landing may start one more).
	for k in 4:
		var landed := _field != null and _field.finish_update()
		var zoned := _surfaces != null and _surfaces.finish_zones()
		if not (landed or zoned):
			break


## One held frame of the stroke: a dab beside the water and its flush.
func _dab(at: Vector3) -> void:
	_editor.stroke_dab(at, at + Vector3(0.2, 0, 0), 1.5, 0.2)
	_editor.flush()


## Waits (bounded) for the field's worker update to start; true when it did.
func _until_updating() -> bool:
	for i in 60:
		if _field.updating():
			return true
		await get_tree().process_frame
	return false


## The kept water field against a whole build of the document as it is now.
func _field_differs() -> PackedStringArray:
	var whole := WaterField.build(_doc)
	var kept := _field.field
	var differ := PackedStringArray()
	for name: String in FIELD_ARRAYS:
		if kept.get(name) != whole.get(name):
			differ.append(name)
	if kept.events != whole.events:
		differ.append("events")
	return differ


func test_a_clone_shares_nothing_writable() -> void:
	await _editor_on()
	var f := _field.field
	var c := PainterWaterField.clone_field(f)
	for name: String in FIELD_ARRAYS:
		assert_eq(c.get(name), f.get(name), "%s copied" % name)
	var w0 := f.w[0]
	c.w[0] = 123.0
	c.marks.film[0] = 9.0
	assert_eq(f.w[0], w0, "a write to the clone never reaches the field")
	assert_ne(f.marks.film[0], 9.0, "nor to its marks")


func test_a_held_raise_lands_the_synchronous_field_from_a_worker() -> void:
	await _editor_on()
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	assert_true(_editor.terrain.stroke_held, "the terrain knows the stroke is held")
	_dab(BESIDE)
	assert_true(await _until_updating(), "the held flush runs on a worker")
	for i in 600:
		if not _field.updating():
			break
		await get_tree().process_frame
	assert_false(_field.updating(), "the update landed")
	assert_eq(_field_differs(), PackedStringArray(), "landed mid-stroke: equal to a whole build")
	assert_not_null(_field.node, "the mesh is drawn")
	assert_true(_editor.end_stroke())
	assert_false(_editor.terrain.stroke_held, "released")
	await _settle()
	assert_eq(_field_differs(), PackedStringArray(), "after the stroke")


func test_finish_update_lands_the_same_field() -> void:
	await _editor_on()
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	_dab(BESIDE)
	assert_true(await _until_updating(), "a worker update in flight")
	assert_true(_field.finish_update(), "landed now")
	assert_false(_field.updating())
	assert_eq(_field_differs(), PackedStringArray(), "equal to a whole build")


func test_the_stroke_ending_mid_task_lands_the_synchronous_result() -> void:
	await _editor_on()
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	_dab(BESIDE)
	assert_true(await _until_updating(), "a worker update in flight")
	# More ground while it runs, then the release before it lands.
	_dab(BESIDE + Vector3(1.0, 0, 0))
	assert_true(_editor.end_stroke())
	# The stroke's last flush waits for the job to land, then runs on this thread.
	for i in 300:
		if not _field.updating():
			break
		await get_tree().process_frame
	await _settle()
	assert_false(_field.updating(), "nothing in flight after the stroke")
	assert_eq(_field_differs(), PackedStringArray(), "after the stroke: equal to a whole build")
	var zones := _surfaces.zones()
	assert_eq(zones.zone.get_data(), PainterZoneMaps.zone_image(_doc).get_data(), "zone maps whole")


func test_closing_the_map_mid_task_never_waits() -> void:
	await _editor_on()
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	_dab(BESIDE)
	assert_true(await _until_updating(), "a worker update in flight")
	_field.detach()
	assert_false(_field.updating(), "dropped")
	assert_null(_field.field, "detached")
	# A frame on: whatever the task does now lands nowhere.
	await get_tree().process_frame
	assert_null(_field.field, "still detached")
	_editor.end_stroke()


func test_freeing_the_field_mid_task_drops_it() -> void:
	await _editor_on()
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	_dab(BESIDE)
	assert_true(await _until_updating(), "a worker update in flight")
	var ref: WeakRef = weakref(_field)
	_field = null  # The last reference: the predelete drops the task.
	assert_null(ref.get_ref(), "freed")
	for i in 300:
		if PainterWaterField.abandoned_count() == 0:
			break
		await get_tree().process_frame
	assert_eq(PainterWaterField.abandoned_count(), 0, "reaped once it completed")
	_editor.end_stroke()


func test_held_zone_rebuilds_wait_and_the_release_lands_them_exactly() -> void:
	await _editor_on()
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	var rects: Array[Rect2i] = []
	var zones := _surfaces.zones()
	for i in PainterSurfaces.ZONE_HELD_EVERY * 3:
		_dab(BESIDE + Vector3(0.1 * i, 0, 0))
		await get_tree().process_frame
		if not rects.has(zones.last_rect):
			rects.append(zones.last_rect)
	assert_lte(rects.size(), 4, "a zone update every few held frames, not every frame: %s" % [rects])
	assert_true(_editor.end_stroke())
	await _settle()
	assert_eq(zones.zone.get_data(), PainterZoneMaps.zone_image(_doc).get_data(), "zone maps whole")
	assert_eq(_field_differs(), PackedStringArray(), "water field whole")


# ---------------------------------------------------------------- a water landing


## A second river across the first, carved, as WaterEditor._land puts it in the document: the bodies
## and the heights in one frame, then a ground edit of `ground` (sample rect) only.
func _land_crossing(ground: Rect2i) -> void:
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 1.0 and absf(p.y) <= 9.0:
				heights[_doc.sample_index(x, z)] = BED
	_doc.heights = heights
	var bodies: Array[WaterBody] = _doc.water_bodies.duplicate()
	var line := PackedVector2Array([Vector2(0, -9), Vector2(0, 9)])
	bodies.append(
		WaterBody.river(2, line, PackedFloat32Array([1.0, 1.0]), WaterBody.Depth.WAIST, LEVEL)
	)
	_doc.water_bodies = bodies
	_editor.terrain.ground_edited.emit(ground)


func test_a_water_landing_updates_the_field_once_with_its_bodies() -> void:
	await _editor_on()
	# Only the crossing's middle is reported as ground: the new body's whole rect must be redone
	# by the flush anyway, so that the swap's refreshed signal has nothing left to do.
	var middle := Vector2i(_doc.samples_x() >> 1, _doc.samples_z() >> 1)
	_land_crossing(Rect2i(middle, Vector2i.ONE).grow(4))
	await _settle()
	assert_eq(_field_differs(), PackedStringArray(), "the flush: equal to a whole build")
	_field.timings["field"] = -1.0
	AuthoredWater.refresh_map(_map, _doc)
	_water().finish_refresh()
	await get_tree().process_frame
	assert_false(_field.updating(), "nothing started")
	assert_eq(float(_field.timings["field"]), -1.0, "the swap's refreshed redid nothing")
	assert_eq(_field_differs(), PackedStringArray(), "after the swap")


func test_a_large_release_flush_runs_on_a_worker_and_lands_the_synchronous_field() -> void:
	await _editor_on()
	var grid := Rect2i(0, 0, _doc.samples_x(), _doc.samples_z())
	assert_gte(grid.get_area(), PainterWaterField.ASYNC_SAMPLES, "the test map is large enough")
	assert_false(_editor.terrain.stroke_held, "not held")
	_land_crossing(grid)
	assert_true(await _until_updating(), "the flush runs on a worker")
	for i in 600:
		if not _field.updating():
			break
		await get_tree().process_frame
	assert_false(_field.updating(), "the update landed")
	assert_eq(_field_differs(), PackedStringArray(), "landed: equal to a whole build")
	assert_not_null(_field.node, "the mesh is drawn")


func test_closing_the_map_mid_release_flush_never_waits() -> void:
	await _editor_on()
	_land_crossing(Rect2i(0, 0, _doc.samples_x(), _doc.samples_z()))
	assert_true(await _until_updating(), "a worker update in flight")
	_field.detach()
	assert_false(_field.updating(), "dropped")
	assert_null(_field.field, "detached")
	await get_tree().process_frame
	assert_null(_field.field, "still detached")
