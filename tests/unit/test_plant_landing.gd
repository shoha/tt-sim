extends GutTest

## The plant landing's main-thread savings (card painter-plant-landing, from terraform-s2-cpu round
## 8): a job shares its biome's rules and run() copies them on its worker, with the same rows as a
## copy per job (ScatterRegen.own_rules); the painted trees' tables (PainterTreeTables) give a new
## tree its own line at once and, once the worker pass lands, equal a whole synchronous build; and
## closing the map while a pass waits for a pool thread never blocks the main thread.

const BIOME := "temperate_forest_summer_s1"
const WINDOW := Rect2(-12.0, -12.0, 24.0, 24.0)
const OAK := "temperate_forest_summer_s1/Tree_Oak_v0"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const HOLD_MS := 6000
const BOUND_MS := 3000

var _map: Node3D = null


func before_each() -> void:
	PainterSheet.clear_cache()
	var container := Node3D.new()
	add_child_autofree(container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	container.add_child(_map)


func test_shared_rules_give_the_rows_of_a_copy_per_job() -> void:
	var doc := ProvingGround.build(BIOME)
	var regen := ScatterRegen.for_document(doc)
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	var registered: Array = regen._biomes[BIOME]["species"]
	var untouched: Array = registered.duplicate(true)
	regen.request_region(WINDOW)
	var frozen := ScatterRegen.snapshot(doc)
	var jobs := 0
	var rows := 0
	while regen.has_pending() and jobs < 4:
		var job := regen.take_job(16)
		if job.is_empty():
			break
		jobs += 1
		var work: Dictionary = job["work"]
		var copied := {}
		for biome_id: String in work:
			var entry: Dictionary = work[biome_id]
			assert_true(is_same(entry["species_master"], registered), "the job shares the rules")
			var own := entry.duplicate()
			own["species"] = (entry["species_master"] as Array).duplicate(true)
			own.erase("species_master")
			copied[biome_id] = own
		var shared := ScatterRegen.run(frozen, work)
		var per_job := ScatterRegen.run(frozen, copied)
		assert_eq(shared["rows_by_cell"], per_job["rows_by_cell"], "the same rows")
		assert_eq(shared["anchors"], per_job["anchors"], "the same mass anchors")
		rows += (shared["rows_by_cell"] as Dictionary).size()
	assert_gt(jobs, 0)
	assert_gt(rows, 0, "the jobs grew rows")
	assert_eq(registered, untouched, "no run wrote the shared rules")


func test_worker_tables_equal_a_whole_build_once_landed() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(_grid(Vector2(1, 1), 3))}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := surfaces.trees() as PainterTrees
	trees.complete()
	var host := trees.tables_host()
	assert_false(host.is_busy())
	_assert_whole(trees, "after complete()")

	# A second stand in the next cell (ScatterChunker: 10 m), within NEAR_M of the first.
	scatter.set_cells(
		{
			Vector2i(0, 0): {OAK: _rows(_grid(Vector2(1, 1), 3))},
			Vector2i(1, 1): {OAK: _rows(_grid(Vector2(11, 11), 3))},
		}
	)
	trees._wait_all()
	var before: Dictionary = trees.trees.duplicate()
	trees._install_some(INF)
	var fresh := 0
	for key: Vector3i in trees.trees:
		if before.has(key):
			continue
		fresh += 1
		var row: int = trees.trees[key]["row"]
		var line := PainterTreeTones.role_rows(trees.trees[key]["species"], 0)
		for r in line.size():
			assert_eq(host._rows[row * PainterTrees.MAP_W + r], float(line[r]), "its role rows at once")
		for r in range(9, PainterTrees.MAP_W):
			assert_eq(host._rows[row * PainterTrees.MAP_W + r], -1.0, "no neighbours yet")
	assert_gt(fresh, 0, "new trees installed")
	assert_true(host.is_busy(), "a whole pass follows")
	var frames := 0
	while trees.is_growing() and frames < 600:
		await get_tree().process_frame
		frames += 1
	assert_false(trees.is_growing(), "settled within %d frames" % frames)
	_assert_whole(trees, "after the worker pass")
	surfaces.release()


## A pool with every thread taken (the PainterZoneMaps rule, test_painter_zone_worker): a tables
## pass that cannot start is let go when the map closes, and reaped once it has run. Each blocker
## lets go by itself after HOLD_MS, so a regression fails on the elapsed time instead of hanging
## the run.
func test_closing_the_map_while_a_tables_pass_waits_never_blocks() -> void:
	var scatter := _scatter()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(_grid(Vector2(1, 1), 2))}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := surfaces.trees() as PainterTrees
	trees.complete()
	scatter.set_cells({Vector2i(0, 0): {OAK: _rows(_grid(Vector2(1, 1), 3))}})
	trees._wait_all()
	# Let any pass the landing started run before the pool is taken.
	trees.tables_host().finish()
	var release := [false]
	var deadline := Time.get_ticks_msec() + HOLD_MS
	var blockers := PackedInt64Array()
	for i in OS.get_processor_count() + 1:
		blockers.append(
			WorkerThreadPool.add_task(_hold.bind(release, deadline), true, "test pool blocker")
		)
	trees._install_some(INF)
	var in_flight := trees.tables_host().has_task()
	var started := Time.get_ticks_msec()
	surfaces.release()
	var release_ms := Time.get_ticks_msec() - started
	var held := Time.get_ticks_msec() < deadline
	# Free the pool before any assert, so a failure cannot leave the run blocked.
	release[0] = true
	for task in blockers:
		WorkerThreadPool.wait_for_task_completion(task)
	assert_true(held, "the blockers held the pool for the close")
	assert_true(in_flight, "the install started a worker pass")
	assert_lt(release_ms, BOUND_MS, "closing the map lets go without waiting")
	assert_gt(PainterTreeTables.abandoned_count(), 0, "the abandoned pass waits to be reaped")
	var frames := 0
	while PainterTreeTables.abandoned_count() > 0 and frames < 240:
		await get_tree().process_frame
		frames += 1
	assert_eq(PainterTreeTables.abandoned_count(), 0, "reaped within %d frames" % frames)


func _assert_whole(trees: PainterTrees, when: String) -> void:
	var host := trees.tables_host()
	var built := PainterTreeRows.tables(
		trees.trees, host.lines, PainterTrees.MAP_W, PainterTrees.NEAR_M
	)
	assert_eq(host._rows, built.rows, "the row map equals a whole build " + when)
	assert_eq(host._occ, built.occ, "the occluders equal a whole build " + when)


func _scatter() -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	return scatter


## `n` x `n` points 3 m apart from `origin` (near enough to be each other's neighbours).
static func _grid(origin: Vector2, n: int) -> Array:
	var out: Array = []
	for z in n:
		for x in n:
			out.append(origin + Vector2(x, z) * 3.0)
	return out


static func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p: Vector2 in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


static func _hold(release: Array, deadline: int) -> void:
	while not release[0] and Time.get_ticks_msec() < deadline:
		OS.delay_msec(2)
