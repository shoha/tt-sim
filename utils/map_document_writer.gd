class_name MapDocumentWriter
extends RefCounted

## Writes map documents on a WorkerThreadPool task, one at a time, so a save costs the main
## thread only its MapDocumentSnapshot.capture() (topic perfaudit, card authsave: the whole
## serialize, deflate and write was 35 / 152 / 388 ms of one frame at 100 / 200 / 320 ft). The
## owner starts a Job, calls poll() once a frame (or wait() where it must block: a discard,
## leaving, quitting) and reads the finished job's error on the main thread.
##
## A job writes its document atomically (MapDocumentIO.write_snapshot: a temp file in the same
## folder renamed over the target) and then its side files, each atomically the same way, so a
## crash or a kill mid-write leaves every target as it was. Side files are written only after
## the document succeeded: the autosave's level never names a document that is not on disk.
##
## Threading: the worker touches only its Job (the snapshot, the paths, the bytes) and the
## files; nothing of the scene tree, the RenderingServer or an autoload. The main thread reads a
## job's results only after poll() or wait() saw the task complete and waited on it (which also
## releases the pool's task), and MapFileHash is invalidated there. Freeing the writer blocks on
## a write in flight, so the last write is never cut short by a teardown or a quit.

## A started job finished (emitted by poll() or wait(), on the main thread).
signal finished(job: Job)

var _task: int = -1
var _job: Job = null


## One write: what to write, set by the caller before start(), and what came of it, set by the
## worker and read only once `done`.
class Job:
	extends RefCounted
	var snapshot: MapDocumentSnapshot = null
	var path: String = ""
	## Path -> PackedByteArray, written in order after the document, each atomically.
	var side_files: Dictionary = {}
	## The caller's own fields (AuthoringSaving keeps the kind, revision and session here).
	var tag: Dictionary = {}
	var error: Error = OK
	## Why it failed, for the warning and the error toast; "" on success.
	var message: String = ""
	## The worker's own time: encode, deflate and every file write.
	var worker_usec: int = 0
	var done: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _job != null:
		WorkerThreadPool.wait_for_task_completion(_task)


## True while a job's task runs or waits to be polled.
func is_busy() -> bool:
	return _job != null


## The running job, or null.
func current() -> Job:
	return _job


## Starts `job` on a low-priority pool task. Returns false (and starts nothing) while busy.
func start(job: Job) -> bool:
	if _job != null:
		return false
	_job = job
	_task = WorkerThreadPool.add_task(
		MapDocumentWriter.run.bind(job), false, "MapDocumentWriter " + job.path.get_file()
	)
	return true


## The job that just finished, once, else null (nothing running, or still running).
func poll() -> Job:
	if _job == null or not WorkerThreadPool.is_task_completed(_task):
		return null
	return _finish()


## Blocks until the running job finished and returns it; null when idle.
func wait() -> Job:
	return _finish() if _job != null else null


func _finish() -> Job:
	WorkerThreadPool.wait_for_task_completion(_task)
	var job := _job
	_job = null
	_task = -1
	job.done = true
	if job.error == OK:
		MapFileHash.invalidate(job.path)
	finished.emit(job)
	return job


## Runs `job` on the calling thread: the task's body, and the synchronous writes'
## (AuthoringAutosave.write). Touches only the job and its files.
static func run(job: Job) -> void:
	var started := Time.get_ticks_usec()
	job.error = MapDocumentIO.write_snapshot(job.snapshot, job.path)
	if job.error == ERR_INVALID_DATA:
		job.message = "not writing %s: %s" % [job.path, job.snapshot.error]
	elif job.error != OK:
		job.message = "could not write %s (%s)" % [job.path, error_string(job.error)]
	else:
		for side_path: String in job.side_files:
			var err := write_atomic(side_path, job.side_files[side_path])
			if err != OK:
				job.error = err
				job.message = "could not write %s (%s)" % [side_path, error_string(err)]
				break
	job.worker_usec = Time.get_ticks_usec() - started


## Writes `bytes` to `path` through `<path>.tmp` in the same folder and a rename over the
## target, so a failure at any step leaves the previous file as it was. Any thread.
static func write_atomic(path: String, bytes: PackedByteArray) -> Error:
	var temp := path + MapDocumentIO.TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	var err := file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(temp, path)
	if err != OK and FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	return err
