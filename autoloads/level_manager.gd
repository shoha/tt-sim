extends Node

## Manages level save/load operations and level instantiation.
## Autoload singleton for global access.
##
## Supports two storage formats:
## - Legacy: .tres files in user://levels/
## - New: Folder-based with level.json + map.glb in user://levels/{level_name}/

const LEVEL_FILE_EXTENSION = ".tres"
const LEVEL_JSON_NAME = "level.json"
const LEVEL_MAP_NAME = "map.glb"

## Signals
signal level_loaded(level_data: LevelData)
signal level_saved(path: String)
signal level_list_updated(levels: Array[String])

## Current loaded level
var current_level: LevelData = null
var current_level_path: String = ""


func _ready() -> void:
	_ensure_levels_directory()


## Ensure the levels directory exists
func _ensure_levels_directory() -> void:
	if not DirAccess.dir_exists_absolute(Paths.LEVELS_DIR):
		DirAccess.make_dir_recursive_absolute(Paths.LEVELS_DIR)


## Save a level to disk (legacy .tres format)
## For new levels, prefer save_level_folder() which bundles the map
func save_level(level_data: LevelData, file_name: String = "") -> String:
	_ensure_levels_directory()

	if file_name == "":
		file_name = _sanitize_filename(level_data.level_name)

	if not file_name.ends_with(LEVEL_FILE_EXTENSION):
		file_name += LEVEL_FILE_EXTENSION

	var full_path = Paths.LEVELS_DIR + file_name

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

	var folder_path = Paths.get_level_folder(folder_name)

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
	var json_path = Paths.get_level_json_path(folder_name)
	if not _save_level_json(level_data, json_path):
		push_error("LevelManager: Failed to save level.json")
		return ""

	current_level = level_data
	current_level_path = folder_path
	level_saved.emit(folder_path)

	print("LevelManager: Saved level folder: " + folder_path)
	return folder_path


## Get a unique folder name by appending a number if needed
func _get_unique_folder_name(base_name: String) -> String:
	var folder_name = base_name
	var counter = 1

	while DirAccess.dir_exists_absolute(Paths.get_level_folder(folder_name)):
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
	var dest_path = Paths.get_level_map_path(folder_name)

	# Ensure destination folder exists
	var folder_path = Paths.get_level_folder(folder_name)
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

	print("LevelManager: Copied map to " + dest_path)
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
	var json_path = Paths.get_level_json_path(folder_name)

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
	current_level_path = Paths.get_level_folder(folder_name)

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
	var json_path = Paths.get_level_json_path(folder_name)

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
	current_level_path = Paths.get_level_folder(folder_name)

	if notify:
		level_loaded.emit(level)

	return level


## Get list of all saved levels (both formats)
func get_saved_levels() -> Array[Dictionary]:
	_ensure_levels_directory()

	var levels: Array[Dictionary] = []
	var dir = DirAccess.open(Paths.LEVELS_DIR)

	if not dir:
		push_error("LevelManager: Cannot open levels directory")
		return levels

	dir.list_dir_begin()
	var entry_name = dir.get_next()

	while entry_name != "":
		if dir.current_is_dir():
			# Check if it's a folder-based level (has level.json)
			var json_path = Paths.get_level_json_path(entry_name)
			if FileAccess.file_exists(json_path):
				var level_info = _get_folder_level_info(entry_name)
				if level_info:
					levels.append(level_info)
		elif entry_name.ends_with(LEVEL_FILE_EXTENSION):
			# Legacy .tres format
			var full_path = Paths.LEVELS_DIR + entry_name
			var level = (
				ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
			)
			if level:
				levels.append(
					{
						"path": full_path,
						"folder": "",
						"is_folder_based": false,
						"name": level.level_name,
						"description": level.level_description,
						"author": level.author,
						"modified_at": level.modified_at,
						"token_count": level.token_placements.size()
					}
				)
			else:
				push_warning("LevelManager: Skipping incompatible level file: " + entry_name)
		entry_name = dir.get_next()

	dir.list_dir_end()

	# Sort by modified time (newest first)
	levels.sort_custom(func(a, b): return a.modified_at > b.modified_at)

	return levels


## Get info about a folder-based level
func _get_folder_level_info(folder_name: String) -> Dictionary:
	var json_path = Paths.get_level_json_path(folder_name)

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}

	var data = json.data
	var token_count = 0
	if data.has("token_placements") and data.token_placements is Array:
		token_count = data.token_placements.size()

	return {
		"path": Paths.get_level_folder(folder_name),
		"folder": folder_name,
		"is_folder_based": true,
		"name": data.get("level_name", folder_name),
		"description": data.get("level_description", ""),
		"author": data.get("author", ""),
		"modified_at": data.get("modified_at", 0),
		"token_count": token_count
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

	print("LevelManager: Deleted level folder: " + folder_path)
	return true


## Create a new empty level
func create_new_level(level_name: String = "New Level") -> LevelData:
	var level = LevelData.new()
	level.level_name = level_name
	current_level = level
	current_level_path = ""
	return level


## Instantiate a loaded level into the scene
## Returns the map node with all tokens added
func instantiate_level(level_data: LevelData, parent: Node3D) -> Node3D:
	if level_data.map_path == "":
		push_error("LevelManager: No map path specified")
		return null

	# Load the map using the unified pipeline (handles res:// and user:// paths)
	var map_instance = GlbUtils.load_map(level_data.map_path, true)
	if not map_instance:
		push_error("LevelManager: Failed to load map: " + level_data.map_path)
		return null

	map_instance.scale = level_data.map_scale
	map_instance.position = level_data.map_offset
	parent.add_child(map_instance)

	# Create all token placements
	var tokens_container = Node3D.new()
	tokens_container.name = "Tokens"
	parent.add_child(tokens_container)

	for placement in level_data.token_placements:
		var token = _create_token_from_placement(placement)
		if token:
			tokens_container.add_child(token)

	return map_instance


## Create a BoardToken from a TokenPlacement
func _create_token_from_placement(placement: TokenPlacement) -> BoardToken:
	return BoardTokenFactory.create_from_placement(placement)


## Sanitize a filename
func _sanitize_filename(file_name_input: String) -> String:
	var sanitized = file_name_input.strip_edges().to_lower()
	sanitized = sanitized.replace(" ", "_")

	# Remove invalid characters
	var valid_chars = "abcdefghijklmnopqrstuvwxyz0123456789_-"
	var result = ""
	for c in sanitized:
		if c in valid_chars:
			result += c

	if result == "":
		result = "level_" + str(Time.get_unix_time_from_system())

	return result


## Export level to a portable JSON format
func export_level_json(level_data: LevelData, file_path: String) -> bool:
	var data = {
		"level_name": level_data.level_name,
		"level_description": level_data.level_description,
		"author": level_data.author,
		"created_at": level_data.created_at,
		"modified_at": level_data.modified_at,
		"map_path": level_data.map_path,
		"map_scale":
		{"x": level_data.map_scale.x, "y": level_data.map_scale.y, "z": level_data.map_scale.z},
		"map_offset":
		{"x": level_data.map_offset.x, "y": level_data.map_offset.y, "z": level_data.map_offset.z},
		"light_intensity_scale": level_data.light_intensity_scale,
		"environment_preset": level_data.environment_preset,
		"environment_overrides":
		EnvironmentPresets.overrides_to_json(level_data.environment_overrides),
		"token_placements": []
	}

	for placement in level_data.token_placements:
		data.token_placements.append(
			{
				"placement_id": placement.placement_id,
				"pack_id": placement.pack_id,
				"asset_id": placement.asset_id,
				"variant_id": placement.variant_id,
				"position":
				{"x": placement.position.x, "y": placement.position.y, "z": placement.position.z},
				"rotation_y": placement.rotation_y,
				"scale": {"x": placement.scale.x, "y": placement.scale.y, "z": placement.scale.z},
				"token_name": placement.token_name,
				"is_player_controlled": placement.is_player_controlled,
				"max_health": placement.max_health,
				"current_health": placement.current_health,
				"is_visible_to_players": placement.is_visible_to_players
			}
		)

	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("LevelManager: Cannot write to " + file_path)
		return false

	file.store_string(json_string)
	file.close()
	return true


## Import level from JSON format
func import_level_json(file_path: String) -> LevelData:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("LevelManager: Cannot read " + file_path)
		return null

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("LevelManager: Failed to parse JSON: " + json.get_error_message())
		return null

	var data = json.data
	var level = LevelData.new()

	level.level_name = data.get("level_name", "Imported Level")
	level.level_description = data.get("level_description", "")
	level.author = data.get("author", "")
	level.created_at = data.get("created_at", int(Time.get_unix_time_from_system()))
	level.modified_at = data.get("modified_at", level.created_at)
	level.map_path = data.get("map_path", "")

	if data.has("map_scale"):
		level.map_scale = Vector3(data.map_scale.x, data.map_scale.y, data.map_scale.z)
	if data.has("map_offset"):
		level.map_offset = Vector3(data.map_offset.x, data.map_offset.y, data.map_offset.z)

	level.light_intensity_scale = data.get("light_intensity_scale", 1.0)
	level.environment_preset = data.get("environment_preset", "")
	level.environment_overrides = EnvironmentPresets.overrides_from_json(
		data.get("environment_overrides", {})
	)

	for placement_data in data.get("token_placements", []):
		var placement = TokenPlacement.new()
		placement.placement_id = placement_data.get("placement_id", TokenPlacement._generate_id())
		placement.pack_id = placement_data.get("pack_id", "")
		placement.asset_id = placement_data.get("asset_id", "")
		placement.variant_id = placement_data.get("variant_id", "default")
		placement.position = Vector3(
			placement_data.position.x, placement_data.position.y, placement_data.position.z
		)
		placement.rotation_y = placement_data.get("rotation_y", 0.0)
		if placement_data.has("scale"):
			placement.scale = Vector3(
				placement_data.scale.x, placement_data.scale.y, placement_data.scale.z
			)
		placement.token_name = placement_data.get("token_name", "")
		placement.is_player_controlled = placement_data.get("is_player_controlled", false)
		placement.max_health = placement_data.get("max_health", 100)
		placement.current_health = placement_data.get("current_health", 100)
		placement.is_visible_to_players = placement_data.get("is_visible_to_players", true)
		level.token_placements.append(placement)

	return level
