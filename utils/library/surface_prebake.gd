class_name SurfacePrebake
extends RefCounted

## The worker lane that bakes library surface maps ahead of their first use (perf card sysbake),
## so a map load's ground finds them in SurfaceStore's memory instead of decoding, compressing
## and caching them on the main thread: about 200 ms per BC7 albedo, which made 2.4 to 2.9 s
## frames on a cold cache (perfaudit sysopen).
##
## A load names the surfaces it is about to draw (SurfaceStore.prebake); each map not in memory
## becomes a job, and ONE task on WorkerThreadPool works the jobs in order: the cache file when it
## holds the map, else the PNG decoded, baked and written to the cache, by the same function the
## main thread uses (SurfaceStore.load_map), so the maps and the cache files are the same bytes.
## A result stays here until the main thread asks for its map (take()), which moves it into the
## store: SurfaceStore's tables are never read or written off the main thread.
##
## One compression at a time, process wide. Two at once do not give the same bytes (a BC7 albedo
## compressed beside a BC1 or BC5 map differed in 6 of 48 bakes; serial bakes, on the main thread
## or one worker, never did: probe sysbake), so the lane is a single task, and COMPRESS_LOCK,
## which load_map holds around a bake, keeps a main-thread bake from overlapping the lane's.
##
## A map asked for before the lane reached it leaves the queue (the main thread bakes it, as it
## always did); one the lane is baking is waited for by polling. Never wait on the lane with
## WorkerThreadPool.wait_for_task_completion before it is done: a main thread blocked that way on
## bake tasks hung for minutes (probe sysbake).

enum State { QUEUED, RUNNING, DONE }

var _mutex := Mutex.new()
## Absolute PNG -> {state, job, result}: `job` as add() took it, `result` load_map's plus "hash".
var _entries: Dictionary = {}
## The QUEUED files in the order the lane takes them.
var _queue: Array[String] = []
## Whether the lane task is running (it ends when the queue is empty; add() starts a new one).
var _running: bool = false
## Lane task ids not yet released (released once completed, so the pool frees them).
var _tasks: Array[int] = []
## Runtime surface name -> the hash of its files, computed by the lane for the jobs that came
## without one (SurfaceStore had not hashed the surface yet).
var _hashes: Dictionary = {}
## Counts forget() calls, so a job baking across one does not keep its hash.
var _generation: int = 0


## Queues `job` ({file, kind, library, name, runtime, files, hash}: hash "" when the surface is
## not hashed yet) unless the lane already knows its file. Main thread.
func add(job: Dictionary) -> void:
	var file := String(job["file"])
	_mutex.lock()
	if not _entries.has(file):
		_entries[file] = {"state": State.QUEUED, "job": job, "result": {}}
		_queue.append(file)
		if not _running:
			_running = true
			_tasks.append(WorkerThreadPool.add_task(_work, false, "Surface prebake"))
	_mutex.unlock()


## True while a job is queued or baking (a finished one waits for take()). Main thread.
func is_busy() -> bool:
	_release()
	_mutex.lock()
	var busy := _running
	_mutex.unlock()
	return busy


## Whether the lane holds `file` (queued, baking or baked and not taken).
func has(file: String) -> bool:
	_mutex.lock()
	var known := _entries.has(file)
	_mutex.unlock()
	return known


## The lane's result for `file` (SurfaceStore.load_map's dictionary plus "hash"), handed over
## and forgotten; {} when the lane does not hold it. A queued job is dropped and {} returned (the
## caller bakes the map itself); a job the lane is baking is waited for. Main thread.
func take(file: String) -> Dictionary:
	_mutex.lock()
	var entry: Dictionary = _entries.get(file, {})
	if entry.is_empty() or entry["state"] == State.QUEUED:
		_entries.erase(file)
		_queue.erase(file)
		_mutex.unlock()
		return {}
	while entry["state"] != State.DONE:
		_mutex.unlock()
		OS.delay_usec(250)
		_mutex.lock()
	_entries.erase(file)
	_mutex.unlock()
	return entry["result"]


## Drops every queued job and every result not taken (SurfaceStore forgetting its libraries or
## its memory); a map the lane is baking still lands in the cache and is dropped. Main thread.
func forget() -> void:
	_mutex.lock()
	_entries.clear()
	_queue.clear()
	_hashes.clear()
	_generation += 1
	_mutex.unlock()


## The lane: takes the queue's first job until none is left.
func _work() -> void:
	while true:
		_mutex.lock()
		if _queue.is_empty():
			_running = false
			_mutex.unlock()
			return
		var file: String = _queue.pop_front()
		var entry: Dictionary = _entries[file]
		entry["state"] = State.RUNNING
		var job: Dictionary = entry["job"]
		var runtime := String(job["runtime"])
		var hash_text := String(job["hash"])
		if hash_text == "":
			hash_text = String(_hashes.get(runtime, ""))
		var generation := _generation
		_mutex.unlock()
		if hash_text == "":
			hash_text = SurfaceStore.files_hash(String(job["name"]), job["files"])
		var result := SurfaceStore.load_map(
			file, String(job["kind"]), String(job["library"]), String(job["name"]), hash_text
		)
		result["hash"] = hash_text
		_mutex.lock()
		if generation == _generation:
			_hashes[runtime] = hash_text
		entry["result"] = result
		entry["state"] = State.DONE
		_mutex.unlock()


## Releases the lane tasks that have finished (a finished task's wait returns at once).
func _release() -> void:
	var left: Array[int] = []
	for id in _tasks:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			left.append(id)
	_tasks = left
