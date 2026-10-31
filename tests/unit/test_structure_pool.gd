extends GutTest

## The group build waited on from inside a low-priority pool task (what AuthoredLoadPrep does) must
## not need a low-priority thread. The pool gives low-priority tasks only a share of its threads
## (clamp(0.3 * threads, 1, threads - 1): one on a 4-core CI runner), and the waiting task holds
## one: a low-priority group then sat queued behind the task that waited for it, and every test
## that loaded structures through the prep hung for 900 s in CI (2026-10-31; seven low-priority
## threads on the 24-thread dev machine hid it). Here the caller waits at a gate while blockers
## take every other low-priority thread, so it fails on any core count.
## Summary: docs/systems/structure_performance.md.

const WAIT_MS := 15000

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	for k in 3:
		var plan := PackedVector2Array(
			[Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)]
		)
		for p in plan.size():
			plan[p] += Vector2(-8.0 + 7.0 * k, -6.0)
		_doc.structures.append(Structure.make(k + 1, "core:cottage", plan, 5))


func test_a_group_build_inside_a_busy_low_priority_pool_finishes() -> void:
	var go := Semaphore.new()
	var release := [false]
	var built: Array = []
	var caller := WorkerThreadPool.add_task(
		_build_at_gate.bind(go, built), false, "test group build caller"
	)
	var blockers := PackedInt64Array()
	for i in OS.get_processor_count():
		blockers.append(
			WorkerThreadPool.add_task(_hold_until.bind(release), false, "test low priority blocker")
		)
	OS.delay_msec(100)
	go.post()
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while not WorkerThreadPool.is_task_completed(caller) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
	var finished := WorkerThreadPool.is_task_completed(caller)
	# Free the pool before any assert, so a failure cannot leave the run hung.
	release[0] = true
	for task in blockers:
		WorkerThreadPool.wait_for_task_completion(task)
	WorkerThreadPool.wait_for_task_completion(caller)
	assert_true(finished, "the group build finished while every low-priority thread was busy")
	assert_eq(built.size(), 1)
	if built.size() == 1:
		assert_eq((built[0].structures as Array).size(), 3, "one parts per record")


func _build_at_gate(go: Semaphore, out: Array) -> void:
	go.wait()
	out.append(StructureGeometry.build(_doc, true))


func _hold_until(release: Array) -> void:
	while not release[0]:
		OS.delay_msec(2)
