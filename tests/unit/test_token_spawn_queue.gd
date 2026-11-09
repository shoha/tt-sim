extends GutTest

## TokenSpawnQueue spreads token work over frames (perfaudit F-tokens-4): jobs run in the order
## they came, at most the frame budget a frame but at least one, a freed object's job is skipped,
## and the load-time pop-in cascade fits in POP_IN_SPAN_S whatever the count. A removed token
## leaves the board when its tween ends and is freed by the shared queue.

var _queue: TokenSpawnQueue


func before_each() -> void:
	_queue = TokenSpawnQueue.new()


func after_each() -> void:
	_queue.clear()


## Busy-waits `ms` milliseconds: a job that costs what a token costs.
func _busy(ms: float) -> void:
	var end := Time.get_ticks_usec() + int(ms * 1000.0)
	while Time.get_ticks_usec() < end:
		pass


func _record(log: Array, value: int, ms: float) -> void:
	_busy(ms)
	log.append([value, Engine.get_process_frames()])


func test_jobs_run_in_order_over_frames_within_the_budget() -> void:
	var log: Array = []
	for i in 12:
		_queue.enqueue(_record.bind(log, i, 1.5))
	assert_eq(_queue.pending(), 12)
	await wait_process_frames(12)
	assert_eq(log.size(), 12, "every job ran")
	var order: Array = log.map(func(entry: Array) -> int: return entry[0])
	assert_eq(order, range(12), "in the order they were queued")
	var per_frame := {}
	for entry in log:
		per_frame[entry[1]] = int(per_frame.get(entry[1], 0)) + 1
	assert_gt(per_frame.size(), 2, "spread over several frames")
	for frame in per_frame:
		# 1.5 ms jobs under a 4 ms budget: the third starts at 3 ms and ends past it
		assert_lte(per_frame[frame], 3, "at most the budget's worth in frame %d" % frame)
	assert_eq(_queue.pending(), 0)


func test_a_job_dearer_than_the_budget_still_runs_one_a_frame() -> void:
	var log: Array = []
	for i in 3:
		_queue.enqueue(_record.bind(log, i, TokenSpawnQueue.FRAME_BUDGET_MS + 1.0))
	await wait_process_frames(5)
	assert_eq(log.size(), 3)
	assert_ne(log[0][1], log[1][1], "one a frame")
	assert_ne(log[1][1], log[2][1], "one a frame")


func test_a_freed_objects_job_is_skipped_and_drained_fires() -> void:
	var node := Node.new()
	var log: Array = []
	_queue.enqueue(Callable(node, &"free"))
	_queue.enqueue(_record.bind(log, 1, 0.0))
	node.free()
	watch_signals(_queue)
	await wait_process_frames(2)
	assert_eq(log.size(), 1, "the live job ran")
	assert_signal_emitted(_queue, "drained")


func test_the_pop_in_cascade_fits_its_span_whatever_the_count() -> void:
	assert_eq(TokenSpawnQueue.pop_in_delay(0, 1), 0.0)
	assert_almost_eq(TokenSpawnQueue.pop_in_delay(9, 10), 9 * TokenSpawnQueue.POP_IN_STEP_S, 1e-6)
	for total in [31, 100, 500, 2000]:
		var last := TokenSpawnQueue.pop_in_delay(total - 1, total)
		assert_almost_eq(last, TokenSpawnQueue.POP_IN_SPAN_S, 1e-4, "%d tokens" % total)
		assert_lt(
			TokenSpawnQueue.pop_in_delay(total / 2, total), last, "still a cascade at %d" % total
		)


func test_a_removed_token_leaves_the_board_then_is_freed_by_the_queue() -> void:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	add_child(token)
	assert_true(token.is_in_group(BoardToken.GROUP_NAME))
	token.play_removal_animation()
	await wait_seconds(BoardToken.REMOVAL_ANIM_DURATION + 0.1)
	if is_instance_valid(token):
		assert_false(token.visible, "hidden once the tween ends")
		assert_false(token.is_in_group(BoardToken.GROUP_NAME), "out of the token group")
	await wait_process_frames(3)
	assert_false(is_instance_valid(token), "freed by the shared queue")
