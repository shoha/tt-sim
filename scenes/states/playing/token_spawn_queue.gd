class_name TokenSpawnQueue
extends RefCounted

## One queue for token work that would otherwise land in a single frame (perfaudit F-tokens-4):
## the spawns of a level load and the frees after removal animations. A pack token costs about
## 4.4 ms to build and add and a removed one about 0.2 ms to free, so 500 at once made a
## one-second frame or a 100 ms one. Jobs run in the order they were queued, each frame until
## FRAME_BUDGET_MS of it is spent (COVERED_BUDGET_MS while a level load's sheet covers the table,
## LoadPacing), then wait for the next; at least one job runs a frame, so a job dearer than the
## budget still progresses. A host's single spawn does not come through
## here: its caller gets the token back at once.
##
## One shared queue per process (shared()), driven by SceneTree.process_frame while it holds
## jobs. A job is a Callable; one whose object has been freed is skipped.
##
## The load-time pop-in cascade is timed here too: pop_in_delay staggers tokens POP_IN_STEP_S
## apart but fits the whole cascade in POP_IN_SPAN_S whatever the count (user board item
## perf-popin-cap, the recommended 1.5 s).

## Emitted when the last queued job has run.
signal drained

const FRAME_BUDGET_MS := 4.0
## The budget while the loading sheet covers the table: a 20 to 25 ms frame is invisible there, and
## with hundreds of tokens alive each frame costs about 20 ms besides the spawn, so more tokens a
## frame shortens the load (coordinator, 2026-11-08; 12 ms took a 500-token load from 14.9 to
## 8.8 s).
const COVERED_BUDGET_MS := 20.0
const POP_IN_STEP_S := 0.05
const POP_IN_SPAN_S := 1.5

static var _shared: TokenSpawnQueue = null

var _jobs: Array[Callable] = []
var _head := 0
var _tree: SceneTree = null


## The process's queue, made on first use.
static func shared() -> TokenSpawnQueue:
	if _shared == null:
		_shared = TokenSpawnQueue.new()
	return _shared


## Seconds after the cascade's start that token `index` of `total` pops in: POP_IN_STEP_S apart,
## closer when that would take longer than POP_IN_SPAN_S.
static func pop_in_delay(index: int, total: int) -> float:
	if total <= 1:
		return 0.0
	return index * minf(POP_IN_STEP_S, POP_IN_SPAN_S / float(total - 1))


## Queues `job` behind the ones already waiting; it runs in this frame's budget or a later one.
func enqueue(job: Callable) -> void:
	_jobs.append(job)
	if _tree == null:
		_tree = Engine.get_main_loop() as SceneTree
		if _tree != null:
			_tree.process_frame.connect(_run_frame)


## Jobs still waiting.
func pending() -> int:
	return _jobs.size() - _head


## Drops every waiting job without running it.
func clear() -> void:
	_jobs.clear()
	_head = 0
	_stop()


func _run_frame() -> void:
	var start := Time.get_ticks_usec()
	var budget_usec := LoadPacing.budget_usec(
		int(FRAME_BUDGET_MS * 1000.0), int(COVERED_BUDGET_MS * 1000.0)
	)
	var ran := false
	while _head < _jobs.size():
		if ran and Time.get_ticks_usec() - start >= budget_usec:
			return
		var job := _jobs[_head]
		_jobs[_head] = Callable()
		_head += 1
		if job.is_valid():
			job.call()
			ran = true
	_jobs.clear()
	_head = 0
	_stop()
	drained.emit()


func _stop() -> void:
	if _tree != null and _tree.process_frame.is_connected(_run_frame):
		_tree.process_frame.disconnect(_run_frame)
	_tree = null
