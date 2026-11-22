extends GutTest

## A river landing off its frame (card painter-land-frame; docs/PERFORMANCE.md "River release"):
## the zone maps' update of a large rect runs on a worker (PainterZoneMaps.update_async) and the
## shading field's too (PainterGroundField), each landing the bytes the synchronous update gives,
## with a finish mid-task giving them too and a drop mid-task never waiting; the terrain's settle
## rebuilds the chunks still queued for an in-place update; and a water edit landed frame by frame
## (its carve's chunks and snap within the frame budgets) leaves what one landed at once leaves.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const BIOMES := ["temperate_forest_summer_s1", "savanna_summer_s1"]
const SURFACES := ["dirt_road_packed", "cliff_rock", "ash"]
## The bound a call that must not wait for a busy pool stays under (a wait takes the whole hold).
const HOLD_MS := 4000
const BOUND_MS := 2000

var _maps: Array[Node3D] = []
var _surfaces: Array[PainterSurfaces] = []


func after_each() -> void:
	for s in _surfaces:
		s.release()
	_surfaces.clear()
	_maps.clear()


## A painted document of `cells` cells a side (biomes, densities, surfaces, rolling heights).
func _doc(cells: int, seed: int) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(cells, cells), "grass_meadow", "test", 7)
	var n := doc.samples_x() * doc.samples_z()
	doc.biome_ids = PackedStringArray(BIOMES)
	doc.surface_ids = PackedStringArray(SURFACES)
	doc.biome_slots.resize(n)
	doc.biome_density.resize(n)
	doc.surface_weights.resize(n * MapDocument.SURFACE_BYTES)
	_scramble(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()), seed)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			heights[doc.sample_index(x, z)] = sin(p.x * 0.35) * 1.2 + cos(p.y * 0.27) * 0.7
	doc.heights = heights
	return doc


## Rewrites the biomes and surfaces of every sample of `area` at random.
func _scramble(doc: MapDocument, area: Rect2i, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sx := doc.samples_x()
	var n := sx * doc.samples_z()
	var slots := doc.biome_slots
	var density := doc.biome_density
	var weights := doc.surface_weights
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var i := z * sx + x
			slots[i] = rng.randi_range(0, BIOMES.size())
			density[i] = rng.randi_range(0, 255)
			for e in 4:
				weights[i * 4 + e] = rng.randi_range(0, SURFACES.size())
				weights[n * 4 + i * 4 + e] = rng.randi_range(0, 255) * (rng.randi() % 2)
	doc.biome_slots = slots
	doc.biome_density = density
	doc.surface_weights = weights


func _kept(maps: PainterZoneMaps) -> Array:
	return [
		maps.zone.get_data(),
		maps.char_map.get_data() if maps.char_map != null else null,
		maps.biome.get_data() if maps.biome != null else null,
	]


## Raises every height of `rect` by `by` metres.
static func _raise(doc: MapDocument, rect: Rect2i, by: float) -> void:
	var heights := doc.heights
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			heights[doc.sample_index(x, z)] += by
	doc.heights = heights


## Waits (at most 300 frames) until `count` (an abandoned_count) reads 0: the tasks queued behind
## the blockers run once those are done.
func _reaped(count: Callable) -> void:
	for _frame in 300:
		if int(count.call()) == 0:
			return
		await wait_process_frames(1)


## Holds every pool thread for HOLD_MS (the busy-pool tests), returning the group task.
func _hold_pool() -> int:
	var threads := OS.get_processor_count() * 2
	var hold := func(_i: int) -> void: OS.delay_msec(HOLD_MS)
	return WorkerThreadPool.add_group_task(hold, threads, threads, true, "hold")


# ---------------------------------------------------------------- zone maps


func test_a_worker_zone_update_lands_the_bytes_of_update() -> void:
	var doc := _doc(20, 1)
	var sync := PainterZoneMaps.new()
	var worker := PainterZoneMaps.new()
	sync.build(doc)
	worker.build(doc)
	var rect := Rect2i(10, 7, 70, 64)
	_scramble(doc, rect, 2)
	assert_true(worker.wants_worker(doc, rect), "a rect this large goes to the worker")
	assert_false(worker.wants_worker(doc, Rect2i(10, 7, 20, 20)), "a small one stays")
	sync.update(doc, rect)
	worker.update_async(doc, rect)
	assert_true(worker.building())
	# An edit after the start never reaches the snapshot; it follows the landing.
	var later := Rect2i(40, 40, 30, 30)
	_scramble(doc, later, 3)
	var frames := 0
	while not worker.poll() and frames < 300:
		await wait_process_frames(1)
		frames += 1
	assert_false(worker.building(), "landed in %d frames" % frames)
	assert_false(worker.last_whole, "a region, not a build")
	assert_eq(_kept(worker), _kept(sync), "the bytes update() wrote")
	sync.update(doc, later)
	worker.update(doc, later)
	assert_eq(_kept(worker), _kept(sync))
	var whole := PainterZoneMaps.new()
	whole.build(doc)
	assert_eq(_kept(worker), _kept(whole), "and a whole build of the document")


func test_a_finish_mid_update_gives_the_same_bytes_and_a_drop_never_waits() -> void:
	var doc := _doc(20, 4)
	var sync := PainterZoneMaps.new()
	var worker := PainterZoneMaps.new()
	sync.build(doc)
	worker.build(doc)
	var rect := Rect2i(0, 20, 120, 50)
	_scramble(doc, rect, 5)
	sync.update(doc, rect)
	var blockers := _hold_pool()
	worker.update_async(doc, rect)
	var t0 := Time.get_ticks_msec()
	assert_true(worker.finish(), "landed on this thread")
	assert_lt(Time.get_ticks_msec() - t0, BOUND_MS, "never waited for the busy pool")
	assert_eq(_kept(worker), _kept(sync))
	worker.update_async(doc, rect)
	t0 = Time.get_ticks_msec()
	worker = null  # Freed mid-task: the predelete abandons it.
	assert_lt(Time.get_ticks_msec() - t0, BOUND_MS, "the drop never waited")
	WorkerThreadPool.wait_for_group_task_completion(blockers)
	await _reaped(PainterZoneMaps.abandoned_count)
	assert_eq(PainterZoneMaps.abandoned_count(), 0, "reaped once it completed")


# ---------------------------------------------------------------- the shading field


## A terrain of `doc` under a map freed with the test.
func _terrain(doc: MapDocument) -> AuthoredTerrain:
	var map := Node3D.new()
	add_child_autofree(map)
	var terrain := AuthoredTerrain.create(doc)
	map.add_child(terrain)
	return terrain


func test_a_worker_shade_update_lands_the_bytes_of_a_bake() -> void:
	var doc := _doc(16, 6)
	var terrain := _terrain(doc)
	var keeper := PainterGroundField.new()
	keeper.sync(terrain, [])
	var rect := Rect2i(8, 8, 80, 70)
	_raise(doc, rect, 0.8)
	terrain.queue_heights(rect)
	keeper.sync(terrain, [])
	assert_true(keeper.updating(), "a rect this large runs on a worker")
	var before := keeper.field().bytes()
	# A second edit while it runs waits for the landing.
	var later := Rect2i(30, 30, 10, 10)
	_raise(doc, later, -0.5)
	terrain.queue_heights(later)
	keeper.sync(terrain, [])
	assert_eq(keeper.field().bytes(), before, "the field stays as it was until the landing")
	var frames := 0
	while keeper.updating() and frames < 300:
		await wait_process_frames(1)
		frames += 1
	assert_false(keeper.updating(), "landed in %d frames" % frames)
	var baked := GroundShadeField.new()
	baked.bake(doc)
	assert_eq(keeper.field().bytes(), baked.bytes(), "both edits, as a bake of the heights")
	keeper.release()


func test_a_shade_finish_or_release_mid_task_never_waits() -> void:
	var doc := _doc(16, 7)
	var terrain := _terrain(doc)
	var keeper := PainterGroundField.new()
	keeper.sync(terrain, [])
	var blockers := _hold_pool()
	var rect := Rect2i(4, 4, 90, 60)
	_raise(doc, rect, 1.1)
	terrain.queue_heights(rect)
	keeper.sync(terrain, [])
	assert_true(keeper.updating())
	var t0 := Time.get_ticks_msec()
	assert_true(keeper.finish(), "landed on this thread")
	assert_lt(Time.get_ticks_msec() - t0, BOUND_MS, "never waited for the busy pool")
	var baked := GroundShadeField.new()
	baked.bake(doc)
	assert_eq(keeper.field().bytes(), baked.bytes())
	_raise(doc, rect, -0.4)
	terrain.queue_heights(rect)
	keeper.sync(terrain, [])
	assert_true(keeper.updating())
	t0 = Time.get_ticks_msec()
	keeper.release()
	keeper = null
	assert_lt(Time.get_ticks_msec() - t0, BOUND_MS, "the release never waited")
	WorkerThreadPool.wait_for_group_task_completion(blockers)
	await _reaped(PainterGroundField.abandoned_count)
	assert_eq(PainterGroundField.abandoned_count(), 0, "reaped once it completed")


# ---------------------------------------------------------------- the terrain's settle


func test_the_settle_rebuilds_chunks_still_queued_as_a_fresh_build() -> void:
	var doc := _doc(20, 8)
	var terrain := _terrain(doc)
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(-10, -10), Vector2(10, 10), 6.0, 1.0)
	terrain.queue_heights(stroke.take_pending())
	terrain.process_heights(0)  # One chunk in place; the rest still queued.
	assert_true(terrain.has_height_work())
	terrain.settle_heights()
	assert_true(terrain.has_unsettled_chunks(), "the queued chunks wait for their rebuild")
	assert_true(terrain.process_heights(-1))
	assert_false(terrain.has_unsettled_chunks(), "every chunk settled")
	var fresh := _terrain(doc)
	var differ := 0
	var cells := 0
	for chunk: Node in terrain.get_children():
		var mine := chunk as MeshInstance3D
		if mine == null or not mine.name.begins_with(AuthoredTerrain.CHUNK_NAME_PREFIX):
			continue
		var twin := fresh.get_node(NodePath(mine.name)) as MeshInstance3D
		cells += 1
		var a := mine.mesh.surface_get_arrays(0)
		var b := twin.mesh.surface_get_arrays(0)
		if a[Mesh.ARRAY_VERTEX] != b[Mesh.ARRAY_VERTEX] or a[Mesh.ARRAY_NORMAL] != b[Mesh.ARRAY_NORMAL]:
			differ += 1
		if mine.mesh.get_aabb() != twin.mesh.get_aabb():
			differ += 1
	assert_gt(cells, 4)
	assert_eq(differ, 0, "every chunk as a fresh build of the document")


# ---------------------------------------------------------------- a water edit's landing


## A painted editor over a flat 24-cell map: [editor, map].
func _editor() -> AuthoringEditor:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	_maps.append(map)
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass_meadow", "v", 9)
	var terrain := AuthoredTerrain.create(doc)
	map.add_child(terrain)
	var scatter := AuthoredScatter.create()
	scatter.name = MapSourceLoader.SCATTER_NODE
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	map.add_child(scatter)
	var editor := AuthoringEditor.create(doc, map, AuthoringHistory.new())
	editor.scatter.attach_document(doc)
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(map, STATE), "painted")
	_surfaces.append(surfaces)
	editor.finish_height_work()
	return editor


func _carve(editor: AuthoringEditor) -> void:
	var carved := editor.water.carve_river(
		PackedVector2Array([Vector2(-26, -6), Vector2(0, -2), Vector2(26, -6)]),
		PackedFloat32Array([1.2]),
		WaterBody.Depth.WAIST
	)
	assert_gt(carved, 0, "carved")


func _scatter_rows(editor: AuthoringEditor) -> Array:
	var cells: Dictionary = editor.scatter.get("_cells")
	var keys := cells.keys()
	keys.sort()
	var out := []
	for cell: Vector2i in keys:
		out.append([cell, cells[cell]])
	return out


func test_a_river_landed_frame_by_frame_leaves_what_one_landed_at_once_leaves() -> void:
	var at_once := _editor()
	var framed := _editor()
	_carve(at_once)
	at_once.finish_height_work()
	_carve(framed)
	var frames := 0
	while framed.has_height_work() and frames < 600:
		await wait_process_frames(1)
		framed.step_height_work()
		frames += 1
	assert_false(framed.has_height_work(), "landed in %d frames" % frames)
	assert_gte(frames, 3, "land, settle and finish on frames of their own")
	for s in _surfaces:
		s.finish_zones()
	assert_eq(framed.document.heights, at_once.document.heights, "heights")
	assert_eq(framed.document.water_dressing, at_once.document.water_dressing, "dressing")
	assert_eq(framed.history.undo_count(), at_once.history.undo_count(), "one history entry")
	assert_eq(framed.history.next_undo_label(), at_once.history.next_undo_label())
	await wait_process_frames(2)
	framed.finish_height_work()
	at_once.finish_height_work()
	assert_eq(_scatter_rows(framed), _scatter_rows(at_once), "scatter rows")
	var shade := []
	for s in _surfaces:
		shade.append(s.ground_field().field().bytes())
	assert_eq(shade[1], shade[0], "shading field")
	assert_eq(_kept(_surfaces[1].zones()), _kept(_surfaces[0].zones()), "zone maps")
	var baked := GroundShadeField.new()
	baked.bake(framed.document)
	assert_eq(shade[1], baked.bytes(), "the shading field as a bake")
