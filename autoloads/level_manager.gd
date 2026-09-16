extends Node

## Manages level save/load operations and level instantiation.
## Autoload singleton for global access.
##
## Supports two storage formats:
## - Legacy: .tres files in user://levels/
## - New: Folder-based with level.json + map.glb in user://levels/{level_name}/

## Signals
signal level_loaded(level_data: LevelData)
signal level_saved(path: String)
signal level_list_updated(levels: Array[String])

const LEVEL_FILE_EXTENSION = ".tres"
const LEVEL_JSON_NAME = "level.json"
const LEVEL_MAP_NAME = "map.glb"
const LEVEL_THUMBNAIL_NAME = "thumbnail.png"
const THUMBNAIL_SIZE := Vector2i(320, 180)

## Root of the saved-level folders. Tests point this at a temp directory so no
## real save is touched (the same pattern as UiPreferences.settings_path).
static var levels_dir: String = Paths.LEVELS_DIR

## Current loaded level
var current_level: LevelData = null
var current_level_path: String = ""


func _ready() -> void:
	_ensure_levels_directory()


## Ensure the levels directory exists
func _ensure_levels_directory() -> void:
	if not DirAccess.dir_exists_absolute(levels_dir):
		DirAccess.make_dir_recursive_absolute(levels_dir)


func folder_path(folder_name: String) -> String:
	return levels_dir + folder_name + "/"


func json_path(folder_name: String) -> String:
	return folder_path(folder_name) + LEVEL_JSON_NAME


func map_path(folder_name: String) -> String:
	return folder_path(folder_name) + LEVEL_MAP_NAME


func thumbnail_path(folder_name: String) -> String:
	return folder_path(folder_name) + LEVEL_THUMBNAIL_NAME


## Save a level to disk (legacy .tres format)
## For new levels, prefer save_level_folder() which bundles the map
func save_level(level_data: LevelData, file_name: String = "") -> String:
	_ensure_levels_directory()

	if file_name == "":
		file_name = Paths.sanitize_level_name(level_data.level_name)

	if not file_name.ends_with(LEVEL_FILE_EXTENSION):
		file_name += LEVEL_FILE_EXTENSION

	var full_path = levels_dir + file_name

	level_data._update_modified_time()

	var error = ResourceSaver.save(level_data, full_path)
	if error != OK:
		push_error("LevelManager: Failed to save level: " + str(error))
		return ""

	current_level = level_data
	current_level_path = full_path
	level_saved.emit(full_path)

	return full_path


## Save a level to a folder with bundled map (new format)
## Creates: user://levels/{folder_name}/level.json + map.glb
## @param level_data: The level to save
## @param folder_name: Optional folder name (defaults to sanitized level name)
## @param source_map_path: Optional path to map file to copy (if map needs to be bundled)
## @return: The folder path, or empty string on failure
func save_level_folder(
	level_data: LevelData, folder_name: String = "", source_map_path: String = ""
) -> String:
	_ensure_levels_directory()

	# Determine folder name
	if folder_name == "":
		if level_data.level_folder != "":
			folder_name = level_data.level_folder
		else:
			folder_name = Paths.sanitize_level_name(level_data.level_name)

	# Ensure unique folder name if this is a new level
	if level_data.level_folder == "":
		folder_name = _get_unique_folder_name(folder_name)

	var folder_path = folder_path(folder_name)

	# Create folder if it doesn't exist
	if not DirAccess.dir_exists_absolute(folder_path):
		var error = DirAccess.make_dir_recursive_absolute(folder_path)
		if error != OK:
			push_error("LevelManager: Failed to create level folder: " + folder_path)
			return ""

	# Copy map file if provided
	if source_map_path != "":
		if not copy_map_to_level(source_map_path, folder_name):
			push_error("LevelManager: Failed to copy map file")
			return ""
		level_data.map_path = LEVEL_MAP_NAME

	# Update level_folder
	level_data.level_folder = folder_name
	level_data._update_modified_time()

	# Save level.json
	var json_path = json_path(folder_name)
	if not _save_level_json(level_data, json_path):
		push_error("LevelManager: Failed to save level.json")
		return ""

	current_level = level_data
	current_level_path = folder_path
	level_saved.emit(folder_path)

	return folder_path


## Save a level to disk in whatever format it already uses, routing to
## save_level_folder() for folder-based levels and save_level() for legacy
## ones. Folder levels must never be downgraded to a legacy .tres -- that would
## silently drop the bundled map.glb. Callers that already know the format
## (e.g. always creating a new folder level) should call the specific method
## instead.
func save_level_in_place(level_data: LevelData) -> String:
	if level_data.level_folder != "":
		return save_level_folder(level_data)
	return save_level(level_data)


## Get a unique folder name by appending a number if needed
func _get_unique_folder_name(base_name: String) -> String:
	var folder_name = base_name
	var counter = 1

	while DirAccess.dir_exists_absolute(folder_path(folder_name)):
		folder_name = base_name + "_" + str(counter)
		counter += 1

	return folder_name


## Save level data to a JSON file
func _save_level_json(level_data: LevelData, json_path: String) -> bool:
	var data = level_data.to_dict()
	var json_string = JSON.stringify(data, "\t")

	var file = FileAccess.open(json_path, FileAccess.WRITE)
	if not file:
		push_error("LevelManager: Cannot write to " + json_path)
		return false

	file.store_string(json_string)
	file.close()
	return true


## Copy a map file to a level folder
## @param source_path: Path to the source map file (res:// or user://)
## @param folder_name: The level folder name
## @return: True on success
func copy_map_to_level(source_path: String, folder_name: String) -> bool:
	var dest_path = map_path(folder_name)

	# Ensure destination folder exists
	var folder_path = folder_path(folder_name)
	if not DirAccess.dir_exists_absolute(folder_path):
		DirAccess.make_dir_recursive_absolute(folder_path)

	# Read source file
	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if not source_file:
		push_error("LevelManager: Cannot read source map: " + source_path)
		return false

	var data = source_file.get_buffer(source_file.get_length())
	source_file.close()

	# Write to destination
	var dest_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest_file:
		push_error("LevelManager: Cannot write destination map: " + dest_path)
		return false

	dest_file.store_buffer(data)
	dest_file.close()

	return true


## Load a level from disk (auto-detects format)
## Set notify to false when loading for editing (prevents auto-play)
## @param path: Either a .tres file path or a level folder path
func load_level(path: String, notify: bool = true) -> LevelData:
	# Strip trailing slash if present (affects get_file() behavior)
	var clean_path = path.rstrip("/")

	# Check if it's a folder-based level
	if DirAccess.dir_exists_absolute(clean_path):
		return load_level_folder(clean_path.get_file(), notify)

	# Check for level.json in the path
	if clean_path.ends_with("/" + LEVEL_JSON_NAME):
		var folder_name = clean_path.get_base_dir().get_file()
		return load_level_folder(folder_name, notify)

	# Legacy .tres format
	if not ResourceLoader.exists(path):
		push_error("LevelManager: Level file does not exist: " + path)
		return null

	# Use CACHE_MODE_REPLACE to ensure we get the latest saved data, not a cached version
	var level = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as LevelData
	if not level:
		push_error("LevelManager: Failed to load level: " + path)
		return null

	current_level = level
	current_level_path = path

	if notify:
		level_loaded.emit(level)

	return level


## Load a level from a folder (new format)
## @param folder_name: The folder name within user://levels/
func load_level_folder(folder_name: String, notify: bool = true) -> LevelData:
	var json_path = json_path(folder_name)

	if not FileAccess.file_exists(json_path):
		push_error("LevelManager: Level JSON not found: " + json_path)
		return null

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_error("LevelManager: Cannot read level JSON: " + json_path)
		return null

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("LevelManager: Failed to parse level JSON: " + json.get_error_message())
		return null

	var level = LevelData.from_dict(json.data)

	# Ensure level_folder is set correctly
	level.level_folder = folder_name

	current_level = level
	current_level_path = folder_path(folder_name)

	if notify:
		level_loaded.emit(level)

	return level


# ============================================================================
# Async Loading (non-blocking)
# ============================================================================


## Load a level asynchronously (does not block the main thread)
## @param path: Either a .tres file path or a level folder path
## @param notify: Whether to emit level_loaded signal
## @return: LevelData or null on failure
func load_level_async(path: String, notify: bool = true) -> LevelData:
	var clean_path = path.rstrip("/")

	# Check if it's a folder-based level
	if DirAccess.dir_exists_absolute(clean_path):
		return await load_level_folder_async(clean_path.get_file(), notify)

	# Check for level.json in the path
	if clean_path.ends_with("/" + LEVEL_JSON_NAME):
		var folder_name = clean_path.get_base_dir().get_file()
		return await load_level_folder_async(folder_name, notify)

	# Legacy .tres format - use threaded resource loading
	if not ResourceLoader.exists(path):
		push_error("LevelManager: Level file does not exist: " + path)
		return null

	var load_status = ResourceLoader.load_threaded_request(
		path, "", false, ResourceLoader.CACHE_MODE_REPLACE
	)
	if load_status != OK:
		push_error("LevelManager: Failed to start threaded load: " + path)
		return null

	# Wait for loading to complete without blocking
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame

	var level = ResourceLoader.load_threaded_get(path) as LevelData
	if not level:
		push_error("LevelManager: Failed to load level: " + path)
		return null

	current_level = level
	current_level_path = path

	if notify:
		level_loaded.emit(level)

	return level


## Load a level from a folder asynchronously (new format)
## Uses WorkerThreadPool for file I/O to avoid blocking
## @param folder_name: The folder name within user://levels/
func load_level_folder_async(folder_name: String, notify: bool = true) -> LevelData:
	var json_path = json_path(folder_name)

	if not FileAccess.file_exists(json_path):
		push_error("LevelManager: Level JSON not found: " + json_path)
		return null

	# Read file on background thread
	var thread_result: Dictionary = {"json_string": "", "error": ""}

	var task_id = WorkerThreadPool.add_task(
		func():
			var file = FileAccess.open(json_path, FileAccess.READ)
			if not file:
				thread_result.error = "Cannot read level JSON: " + json_path
				return
			thread_result.json_string = file.get_as_text()
			file.close()
	)

	# Wait for thread without blocking main thread
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame

	WorkerThreadPool.wait_for_task_completion(task_id)

	if thread_result.error != "":
		push_error("LevelManager: " + thread_result.error)
		return null

	# Parse JSON on main thread (fast operation)
	var json = JSON.new()
	var error = json.parse(thread_result.json_string)
	if error != OK:
		push_error("LevelManager: Failed to parse level JSON: " + json.get_error_message())
		return null

	var level = LevelData.from_dict(json.data)

	# Ensure level_folder is set correctly
	level.level_folder = folder_name

	current_level = level
	current_level_path = folder_path(folder_name)

	if notify:
		level_loaded.emit(level)

	return level


## Get list of all saved levels (both formats)
func get_saved_levels() -> Array[Dictionary]:
	_ensure_levels_directory()

	var levels: Array[Dictionary] = []
	var dir = DirAccess.open(levels_dir)

	if not dir:
		push_error("LevelManager: Cannot open levels directory")
		return levels

	dir.list_dir_begin()
	var entry_name = dir.get_next()

	while entry_name != "":
		if dir.current_is_dir():
			# Check if it's a folder-based level (has level.json)
			var json_path = json_path(entry_name)
			if FileAccess.file_exists(json_path):
				var level_info = _get_folder_level_info(entry_name)
				if level_info:
					levels.append(level_info)
		elif entry_name.ends_with(LEVEL_FILE_EXTENSION):
			# Legacy .tres format
			var full_path = levels_dir + entry_name
			var level = (
				ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
			)
			if level and level.map_path.is_empty():
				push_warning(
					"LevelManager: Skipping unloadable level (no map assigned): " + entry_name
				)
			elif level:
				(
					levels
					. append(
						{
							"path": full_path,
							"folder": "",
							"is_folder_based": false,
							"name": level.level_name,
							"description": level.level_description,
							"author": level.author,
							"modified_at": level.modified_at,
							"token_count": level.token_placements.size(),
							"environment_preset": level.environment_preset,
							"thumbnail": "",
						}
					)
				)
			else:
				push_warning("LevelManager: Skipping incompatible level file: " + entry_name)
		entry_name = dir.get_next()

	dir.list_dir_end()

	# Sort by modified time (newest first)
	levels.sort_custom(func(a, b): return a.modified_at > b.modified_at)

	return levels


## Get info about a folder-based level.
## Returns an empty Dictionary (falsy, skipped by callers) if the folder cannot be
## read/parsed, or if it has no map assigned yet -- e.g. the "_autosave" scratch
## slot, which is written without validation (see level_editor_history.gd
## _perform_autosave()) so it can capture in-progress edits before a map is chosen.
## Such an entry can never be played, so it is excluded from every level list.
func _get_folder_level_info(folder_name: String) -> Dictionary:
	var json_path = json_path(folder_name)

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}

	var data = json.data
	var map_path: String = data.get("map_path", "")
	if map_path.is_empty():
		return {}

	var token_count = 0
	if data.has("token_placements") and data.token_placements is Array:
		token_count = data.token_placements.size()

	var thumbnail := thumbnail_path(folder_name)
	return {
		"path": folder_path(folder_name),
		"folder": folder_name,
		"is_folder_based": true,
		"name": data.get("level_name", folder_name),
		"description": data.get("level_description", ""),
		"author": data.get("author", ""),
		"modified_at": data.get("modified_at", 0),
		"token_count": token_count,
		"environment_preset": String(data.get("environment_preset", "")),
		"thumbnail": thumbnail if FileAccess.file_exists(thumbnail) else "",
	}


## Delete a level (handles both file and folder formats)
func delete_level(path: String) -> bool:
	# Check if it's a folder
	if DirAccess.dir_exists_absolute(path):
		return delete_level_folder(path)

	# Legacy file format
	if not FileAccess.file_exists(path):
		return false

	var error = DirAccess.remove_absolute(path)
	if error != OK:
		push_error("LevelManager: Failed to delete level: " + str(error))
		return false

	if current_level_path == path:
		current_level = null
		current_level_path = ""

	return true


## Delete a folder-based level and all its contents
func delete_level_folder(folder_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(folder_path):
		return false

	var dir = DirAccess.open(folder_path)
	if not dir:
		push_error("LevelManager: Cannot open folder for deletion: " + folder_path)
		return false

	# Delete all files in the folder
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var file_path = folder_path + file_name
			var file_error = DirAccess.remove_absolute(file_path)
			if file_error != OK:
				push_error("LevelManager: Failed to delete file: " + file_path)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Delete the folder itself
	var folder_error = DirAccess.remove_absolute(folder_path)
	if folder_error != OK:
		push_error("LevelManager: Failed to delete folder: " + folder_path)
		return false

	if current_level_path == folder_path:
		current_level = null
		current_level_path = ""

	return true


## Write a 320x180 thumbnail beside level.json. Only folder-based levels have a
## home for it; legacy .tres levels return false with a warning.
func save_thumbnail(level_data: LevelData, image: Image) -> bool:
	if level_data.level_folder.is_empty():
		push_warning("LevelManager: cannot save a thumbnail for a level without a folder")
		return false
	var fitted := LevelThumbnail.fit(image)
	var path := thumbnail_path(level_data.level_folder)
	var err := fitted.save_png(path)
	if err != OK:
		push_error("LevelManager: failed to save thumbnail %s: %d" % [path, err])
		return false
	return true


## Change a level's display name in place; the folder name never changes so
## paths stay stable. Legacy .tres levels are renamed the same way through
## save_level_in_place.
func rename_level(level_info: Dictionary, new_name: String) -> bool:
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		return false
	var level := load_level(level_info.get("path", ""), false)
	if level == null:
		return false
	level.level_name = trimmed
	return save_level_in_place(level) != ""


## Copy a folder level into a new folder ("<name> (Copy)"), including its map
## and thumbnail. Returns the new folder path, or "" on failure.
func duplicate_level(level_info: Dictionary) -> String:
	var source_folder: String = level_info.get("folder", "")
	if source_folder.is_empty():
		push_warning("LevelManager: only folder levels can be duplicated")
		return ""
	var level := load_level_folder(source_folder, false)
	if level == null:
		return ""
	var copy := level.duplicate_level()
	var new_path := save_level_folder(copy, "", map_path(source_folder))
	if new_path.is_empty():
		return ""
	var source_thumb := thumbnail_path(source_folder)
	if FileAccess.file_exists(source_thumb):
		DirAccess.copy_absolute(source_thumb, thumbnail_path(copy.level_folder))
	return new_path


## Create a new empty level
func create_new_level(level_name: String = "New Level") -> LevelData:
	var level = LevelData.new()
	level.level_name = level_name
	current_level = level
	current_level_path = ""
	return level


## Export level to a portable JSON format
func export_level_json(level_data: LevelData, file_path: String) -> bool:
	var data = level_data.to_dict()
	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("LevelManager: Failed to open export file: " + file_path)
		return false
	file.store_string(json_string)
	file.close()
	return true


## Import level from JSON format
func import_level_json(file_path: String) -> LevelData:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("LevelManager: Failed to open import file: " + file_path)
		return null
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	var parse_err = json.parse(json_string)
	if parse_err != OK:
		push_error("LevelManager: Failed to parse JSON: " + json.get_error_message())
		return null
	return LevelData.from_dict(json.data)
