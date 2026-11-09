class_name AuthoringSaving
extends Node

## Save and autosave for an authoring session, written so the frame that saves pays only a
## snapshot (topic perfaudit, card authsave). AuthoringController owns one as a child and is
## its host; the host is duck-typed so tests drive this node with a stand-in: it provides
## `session`, `document`, `level`, is_session_open(), sync_document() (the scene's rows,
## tokens and name into the document and level), can_autosave() (nothing regenerating, no
## height work), prepare_save_async() (the manual save's waits and fixes before it syncs) and
## capture_thumbnail().
##
## Both paths sync the scene into the document, freeze it (MapDocumentSnapshot.capture:
## copy-on-write copies, under a millisecond at 320 ft) with the session's revision, and hand it
## to a MapDocumentWriter task that encodes, deflates and writes the file atomically on a
## worker; this node polls the task every frame and finishes on the main thread. A stroke that
## lands while the worker runs belongs to the next save: the session records the revision the
## snapshot held (AuthoringSession.mark_saved(at)), so it stays dirty and is autosaved again.
##
## One write at a time. An autosave tick while a write or a manual save runs is remembered and
## runs once when they end, if the session still needs one. A Save pressed while a save runs
## makes that save go round once more when it ends (one follow-up however many presses), and
## every caller gets the last round's result. A Save during an autosave waits for its write.
##
## Waiting: the manual save, and with it save-and-leave, awaits its write (a toast says so when
## it takes over SAVING_TOAST_MS). discard_autosave() and teardown() block on a write in flight
## first, so a late autosave never lands after its discard; quitting frees the writer, which
## blocks too (MapDocumentWriter), so the last write is never cut short.
##
## Errors from the worker (a full disk, a locked file) come back in the job: a manual save shows
## the existing "could not be saved" error and pushes the reason as a warning; a failed autosave
## shows one warning toast until an autosave succeeds again.

## A manual save finished (every round of it); `ok` is the last round's result.
signal save_finished(ok: bool)

const AUTOSAVE := 0
const SAVE := 1
const AUTOSAVE_INTERVAL := 30.0
## A manual save still writing after this long says so.
const SAVING_TOAST_MS := 400

## The autosave tick (stopped by render jobs that must not autosave).
var timer: Timer = null
## The last finished write, for measurement: {"kind", "capture_usec" (the sync, the snapshot
## and the task's start, all on the main thread), "worker_usec", "error"}.
var last_write: Dictionary = {}

var _host: Node = null
var _writer := MapDocumentWriter.new()
var _saving := false
var _save_again := false
var _autosave_due := false
var _autosave_failed := false


func _init(host: Node = null) -> void:
	_host = host
	name = "AuthoringSaving"


func _ready() -> void:
	timer = Timer.new()
	timer.name = "AutosaveTimer"
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.timeout.connect(autosave_tick)
	add_child(timer)


func _process(_delta: float) -> void:
	var job := _writer.poll()
	if job != null:
		_finished(job)


## True while a manual save runs (its waits or its write).
func is_saving() -> bool:
	return _saving


## True while a write is on the worker.
func is_writing() -> bool:
	return _writer.is_busy()


## Starts the autosave tick.
func start_autosave() -> void:
	timer.start()


## Stops the tick and blocks on a write in flight (leaving, and the state's teardown).
func teardown() -> void:
	if timer:
		timer.stop()
	_autosave_due = false
	_wait_writer()


## Deletes the autosave slot, after a write in flight has landed (else it would land after).
func discard_autosave() -> void:
	_wait_writer()
	AuthoringAutosave.discard()


## The autosave tick: writes the slot when the session has edits it does not hold yet.
func autosave_tick() -> void:
	if not _host.is_session_open() or not _host.session.needs_autosave():
		return
	if _saving or _writer.is_busy():
		_autosave_due = true
		return
	if not _host.can_autosave():
		return  # Next tick: half-regenerated rows are not worth recovering.
	var started := Time.get_ticks_usec()
	_host.sync_document()
	if AuthoringAutosave.ensure_directory() != OK:
		_autosave_error("cannot make %s" % AuthoringAutosave.directory)
		return
	var job := AuthoringAutosave.job(_host.document, _host.level)
	job.tag = _tag(AUTOSAVE, started)
	_writer.start(job)


## Saves the map into its level folder (a new folder named after the map the first time):
## map.ttmap atomically on a worker, then level.json with map_document set and a thumbnail of
## the view at the snapshot. Returns true on success (see the header for coalescing).
func save_async() -> bool:
	if not _host.is_session_open():
		return false
	if _saving:
		_save_again = true
		return await save_finished
	_saving = true
	var ok := false
	while true:
		_save_again = false
		ok = await _save_round()
		if not ok or not _save_again or not is_inside_tree():
			break
	_saving = false
	save_finished.emit(ok)
	_run_due_autosave()
	return ok


func _save_round() -> bool:
	while _writer.is_busy():
		await get_tree().process_frame
	await _host.prepare_save_async()
	if not is_inside_tree():
		return false
	var started := Time.get_ticks_usec()
	var level: LevelData = _host.level
	_host.sync_document()
	var begun := begin_level(level)
	if begun["folder"] == "":
		UIManager.show_error("The map could not be saved.")
		return false
	var job := MapDocumentWriter.Job.new()
	job.snapshot = MapDocumentSnapshot.capture(_host.document)
	job.path = LevelManager.map_document_path(begun["folder"])
	job.tag = _tag(SAVE, started)
	var thumbnail: Image = _host.capture_thumbnail()
	_writer.start(job)
	var toast_at := Time.get_ticks_msec() + SAVING_TOAST_MS
	while not job.done and is_inside_tree():
		await get_tree().process_frame
		if toast_at > 0 and Time.get_ticks_msec() > toast_at:
			toast_at = 0
			UIManager.show_toast("Saving “%s”…" % level.level_name, UIManager.TOAST_INFO, 2.0)
	if not job.done:
		_wait_writer()
	if job.error != OK:
		push_warning("AuthoringSaving: " + job.message)
	var ok := finish_level(level, begun["folder"], begun["is_new"], job.error == OK, thumbnail)
	if not ok:
		UIManager.show_error("The map could not be saved.")
		return false
	var session: AuthoringSession = job.tag["session"]
	session.mark_saved(job.tag["revision"])
	AuthoringAutosave.discard()
	UIManager.show_success("Saved “%s”" % level.level_name)
	return true


func _tag(kind: int, started_usec: int) -> Dictionary:
	return {
		"kind": kind,
		"revision": _host.session.revision,
		"session": _host.session,
		"capture_usec": Time.get_ticks_usec() - started_usec,
	}


func _finished(job: MapDocumentWriter.Job) -> void:
	last_write = {
		"kind": job.tag.get("kind", -1),
		"capture_usec": job.tag.get("capture_usec", 0),
		"worker_usec": job.worker_usec,
		"error": job.error,
	}
	if job.tag.get("kind", -1) != AUTOSAVE:
		return  # The save round that started it finishes it.
	if job.error != OK:
		_autosave_error(job.message)
	else:
		_autosave_failed = false
		var session: AuthoringSession = job.tag["session"]
		# A reopen starts a new session; the old one's autosave marks nothing.
		if session == _host.session:
			session.mark_autosaved(job.tag["revision"])
	_run_due_autosave()


func _autosave_error(message: String) -> void:
	push_warning("AuthoringSaving: autosave: " + message)
	if not _autosave_failed:
		_autosave_failed = true
		UIManager.show_toast(
			"The autosave could not be written; save to keep your work.", UIManager.TOAST_WARNING, 6.0
		)


func _run_due_autosave() -> void:
	if _autosave_due and not _saving and not _writer.is_busy():
		_autosave_due = false
		autosave_tick()


func _wait_writer() -> void:
	var job := _writer.wait()
	if job != null:
		_finished(job)


# --- level folders --------------------------------------------------------------------


## Writes `doc` and `saved` into the level's folder on the calling thread, making the folder
## first for a level that has none (AuthoringController.write_level). The document goes first,
## so level.json never names a document that is not on disk; a failure leaves a new level
## folder-less again. Best-effort thumbnail. Returns true when both files were written.
static func write_level(saved: LevelData, doc: MapDocument, thumbnail: Image) -> bool:
	var begun := begin_level(saved)
	if begun["folder"] == "":
		return false
	var written := MapDocumentIO.write(doc, LevelManager.map_document_path(begun["folder"])) == OK
	return finish_level(saved, begun["folder"], begun["is_new"], written, thumbnail)


## The folder a save of `saved` writes into: {"folder" ("" when a new one could not be made),
## "is_new"}. A level without one gets a new folder named after it, made now.
static func begin_level(saved: LevelData) -> Dictionary:
	var folder := saved.level_folder
	var is_new := folder == ""
	if is_new:
		folder = LevelManager.new_folder_name(saved.level_name)
		if DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder)) != OK:
			folder = ""
	return {"folder": folder, "is_new": is_new}


## Finishes a save of `saved` into `folder` after its document was written (`document_ok`):
## points the level at its document and writes level.json, then the thumbnail. On a failure a
## new folder is removed again. Returns true when both files were written.
static func finish_level(
	saved: LevelData, folder: String, is_new: bool, document_ok: bool, thumbnail: Image
) -> bool:
	if not document_ok:
		if is_new:
			DirAccess.remove_absolute(LevelManager.folder_path(folder).trim_suffix("/"))
		return false
	var previous_document := saved.map_document
	saved.level_folder = folder
	saved.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	if LevelManager.save_level_folder(saved, folder) == "":
		saved.map_document = previous_document
		if is_new:
			saved.level_folder = ""
			DirAccess.remove_absolute(LevelManager.map_document_path(folder))
			DirAccess.remove_absolute(LevelManager.folder_path(folder).trim_suffix("/"))
		return false
	if thumbnail != null:
		LevelManager.save_thumbnail(saved, thumbnail)
	return true
