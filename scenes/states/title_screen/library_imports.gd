class_name LibraryImports
extends Node

## The library's ways in for a Blender map, each through the import check (ImportCheckPanel)
## before anything is written: Import... (the system's file picker, on .glb), a file dropped
## anywhere on the library (a new level) or on a map's card (Replace for that map), and Reload
## from Blender (Replace with the source ImportSources remembers). A confirmed check runs
## MapImport (import_glb or replace_map, which render the card's thumbnail offscreen) and
## reports the level it wrote, so the title selects it. A file of another kind opens the panel
## on its one-sentence refusal; of several files dropped at once, the first .glb is checked.
## One panel at a time: a drop while one is open is ignored.

## A new level was written into `folder`.
signal imported(folder: String)
## Level `folder` has a new map under it; `result` is MapImport.replace_map's.
signal replaced(folder: String, result: Dictionary)

const PICKER_FILTER := "*.glb ; Map export (glTF Binary)"
const REPLACED := "Map replaced"
const REPLACED_DROPPED := "Map replaced; %d props and plants off the new map were dropped"

## The open check panel, or null.
var panel: ImportCheckPanel = null
## Where panels go: the tree's root unless a test sets its own.
var host: Node = null
## Whether imports render the card's thumbnail (false in tests).
var render_thumbnails: bool = true


## Opens the system's file picker on .glb files; a chosen file goes to the check.
func pick() -> void:
	var dialog := FileDialog.new()
	dialog.name = "ImportPicker"
	dialog.title = "Import a map"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([PICKER_FILTER])
	dialog.file_selected.connect(
		func(path: String) -> void:
			dialog.queue_free()
			check_import(path)
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## The check of the file at `path`, for a new level.
func check_import(path: String) -> ImportCheckPanel:
	return _open(GlbCheck.check(path), "")


## The check of the file at `path`, for Replace on level folder `folder`.
func check_replace(folder: String, path: String) -> ImportCheckPanel:
	return _open(GlbCheck.check(path), folder)


## Reload from Blender for the map `info` describes: Replace with its remembered source.
func reload(info: Dictionary) -> ImportCheckPanel:
	var folder := String(info.get("folder", ""))
	var source := ImportSources.source_of(folder)
	if folder == "" or source == "":
		return null
	return check_replace(folder, source)


## Files dropped on the library: on the card of level folder `folder` a .glb is Replace for
## that map; anywhere else ("") it is a new level.
func drop(files: PackedStringArray, folder: String) -> ImportCheckPanel:
	if files.is_empty():
		return null
	var path := files[0]
	for file in files:
		if file.get_extension().to_lower() == "glb":
			path = file
			break
	if folder != "" and GlbCheck.extension_refusal(path) == "":
		return check_replace(folder, path)
	return check_import(path)


func _open(check: Dictionary, folder: String) -> ImportCheckPanel:
	if is_instance_valid(panel):
		return null
	panel = ImportCheckPanel.new()
	if folder == "":
		panel.open_import(check)
	else:
		panel.open_replace(check, folder)
	panel.import_confirmed.connect(_on_import_confirmed)
	panel.replace_confirmed.connect(_on_replace_confirmed)
	(host if host != null else get_tree().root).add_child(panel)
	return panel


func _tree() -> SceneTree:
	return get_tree() if render_thumbnails and is_inside_tree() else null


func _on_import_confirmed(path: String, level_name: String) -> void:
	var result: Dictionary = await MapImport.import_glb(path, level_name, _tree())
	if not result.ok:
		UIManager.show_error(String(result.error))
		return
	imported.emit(String(result.folder))


func _on_replace_confirmed(folder: String, path: String, mode: String) -> void:
	var result: Dictionary = await MapImport.replace_map(folder, path, mode, _tree())
	if not result.ok:
		UIManager.show_error(String(result.error))
		return
	var dropped := int(result.props_dropped) + int(result.scatter_dropped)
	UIManager.show_success(REPLACED_DROPPED % dropped if dropped > 0 else REPLACED)
	replaced.emit(folder, result)
