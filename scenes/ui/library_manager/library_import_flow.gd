class_name LibraryImportFlow
extends Node

## The ways a collection comes in, one flow behind all of them: the file picker (a .ttlib or .zip),
## the folder picker, and a file or folder dropped on the title screen or the manager. Each goes
## through the same steps (design 5.5): LibraryImporter.inspect judges the archive without
## extracting, LibraryImporter.stage extracts it into the quarantine on a worker thread while the
## install card shows a bar, LibraryInstall.examine describes what was staged, and only the
## player's Install (or Replace) on the card moves it into place. Then the registry is read
## again, the served libraries are laid over the palette again (FoliageLibrary.refresh_libraries,
## which also tells open pickers such as the New map dialog) and a toast says it is done.
##
## One import at a time: a drop while the card is open is ignored with a toast. Whatever the
## player does (Cancel, Escape, closing the card, quitting the manager) the quarantine is
## emptied of what this flow staged.

## A collection was moved into place (after the registry was refreshed).
signal installed(library_id: String, replaced: bool)
## The card is gone, whatever came of it.
signal finished
## The card opened or closed (the manager dims its Import buttons).
signal busy_changed(busy: bool)

const BUSY_TEXT := "Finish the import that is open first."

## When false, refresh_all() only rescans the folders and leaves the palette alone (tests).
static var serve_palette: bool = true

## The open card, or null.
var panel: LibraryInstallCard = null
## Where the card goes: the tree's root unless a test sets its own.
var host: Node = null

var _plan: Dictionary = {}
var _progress: LibraryImporter.Progress = null
var _task: int = -1
var _result: Dictionary = {}
var _staged: String = ""
var _name: String = ""


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	_finish_task()
	_discard()


## True while a card is open.
func is_busy() -> bool:
	return is_instance_valid(panel)


## The system's file picker on .ttlib and .zip files; a chosen file goes to the check.
func pick_file() -> void:
	var filter := "*.ttlib, *.zip ; %s archive" % LibraryNames.title()
	var title := "Import %s" % LibraryNames.article()
	_picker(title, FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray([filter]))


## The system's folder picker; a chosen folder goes to the check.
func pick_folder() -> void:
	var title := "Import %s folder" % LibraryNames.article()
	_picker(title, FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray())


func _picker(title: String, mode: FileDialog.FileMode, filters: PackedStringArray) -> void:
	var dialog := FileDialog.new()
	dialog.name = "LibraryPicker"
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = filters
	var chosen := func(path: String) -> void:
		dialog.queue_free()
		begin(path)
	dialog.file_selected.connect(chosen)
	dialog.dir_selected.connect(chosen)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## Files dropped on the window: the first that looks like a collection (LibraryImporter.
## is_candidate) goes to the check. False when none does, so the caller can route the drop
## elsewhere (a Blender map).
func drop(files: PackedStringArray) -> bool:
	for path in files:
		if LibraryImporter.is_candidate(path):
			begin(path)
			return true
	return false


## Whether any of `files` looks like a collection.
static func any_candidate(files: PackedStringArray) -> bool:
	for path in files:
		if LibraryImporter.is_candidate(path):
			return true
	return false


## Starts the import of `path` (a zip or a folder): the check, then the card.
func begin(path: String) -> void:
	if is_busy():
		UIManager.show_info(BUSY_TEXT)
		return
	LibraryImporter.sweep_incoming()
	_name = path.get_file()
	_plan = LibraryImporter.inspect(path)
	panel = LibraryInstallCard.new()
	panel.cancelled.connect(_on_cancelled)
	panel.install_confirmed.connect(_on_install_confirmed)
	panel.closed.connect(_on_closed)
	(host if host != null else get_tree().root).add_child(panel)
	busy_changed.emit(true)
	if not bool(_plan["ok"]):
		panel.show_refused(_name, _plan["errors"])
		return
	_progress = LibraryImporter.Progress.new()
	_progress.total = int(_plan["total_bytes"])
	panel.show_reading(_name, _progress.total)
	_result = {}
	var plan := _plan
	var progress := _progress
	var result := _result
	_task = WorkerThreadPool.add_task(
		func() -> void:
			var staged := LibraryImporter.stage(plan, progress)
			result.merge(staged, true),
		false,
		"Reading a content library"
	)
	set_process(true)


func _process(_delta: float) -> void:
	if _task < 0:
		set_process(false)
		return
	if is_instance_valid(panel) and _progress != null:
		panel.set_progress(_progress.done, _progress.total)
	if not WorkerThreadPool.is_task_completed(_task):
		return
	_finish_task()
	set_process(false)
	_staging_done()


func _finish_task() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The worker is done: describe what it staged, or say why it could not.
func _staging_done() -> void:
	if not is_instance_valid(panel):
		LibraryImporter.discard(String(_result.get("folder", "")))
		return
	if not bool(_result.get("ok", false)):
		panel.show_refused(_name, [String(_result.get("error", "The file could not be read."))])
		return
	_staged = String(_result["folder"])
	var card := LibraryInstall.examine(_staged)
	if not bool(card["can_install"]):
		_discard()
	panel.show_card(card)


func _on_install_confirmed(card: Dictionary, replace: bool) -> void:
	var done := LibraryInstall.install(card, replace)
	_staged = ""
	if not bool(done["ok"]):
		UIManager.show_error(String(done["error"]))
		LibraryImporter.discard(String(card["folder"]))
		return
	refresh_all()
	var shown := String(card["name"]) if String(card["name"]) != "" else String(card["id"])
	var verb := "updated" if bool(done["replaced"]) else "added"
	UIManager.show_success("%s %s" % [shown, verb])
	installed.emit(String(card["id"]), bool(done["replaced"]))


func _on_cancelled() -> void:
	if _progress != null:
		_progress.cancelled = true
	_finish_task()
	_discard()


func _on_closed() -> void:
	_finish_task()
	_discard()
	_progress = null
	panel = null
	busy_changed.emit(false)
	finished.emit()


func _discard() -> void:
	if _staged != "":
		LibraryImporter.discard(_staged)
		_staged = ""
	var leftover := String(_result.get("folder", ""))
	if leftover != "":
		LibraryImporter.discard(leftover)


## Reads the folders again and serves what changed: the registry is rescanned, the libraries are
## laid over the palette again and the open map and pickers hear of it (EventBus.
## foliage_library_changed). With `serve_palette` false it only rescans (tests).
static func refresh_all() -> void:
	LibraryRegistry.refresh()
	if serve_palette:
		FoliageLibrary.refresh_libraries()
