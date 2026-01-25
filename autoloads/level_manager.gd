extends Node

## Manages level save/load operations and level instantiation.
## Autoload singleton for global access.

const LEVEL_FILE_EXTENSION = ".tres"

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


## Save a level to disk
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


## Load a level from disk
func load_level(file_path: String) -> LevelData:
	if not ResourceLoader.exists(file_path):
		push_error("LevelManager: Level file does not exist: " + file_path)
		return null
	
	# Use CACHE_MODE_REPLACE to ensure we get the latest saved data, not a cached version
	var level = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REPLACE) as LevelData
	if not level:
		push_error("LevelManager: Failed to load level: " + file_path)
		return null
	
	current_level = level
	current_level_path = file_path
	level_loaded.emit(level)
	
	return level


## Get list of all saved levels
func get_saved_levels() -> Array[Dictionary]:
	_ensure_levels_directory()
	
	var levels: Array[Dictionary] = []
	var dir = DirAccess.open(Paths.LEVELS_DIR)
	
	if not dir:
		push_error("LevelManager: Cannot open levels directory")
		return levels
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(LEVEL_FILE_EXTENSION):
			var full_path = Paths.LEVELS_DIR + file_name
			# Use load with error handling for potentially corrupted/outdated files
			var level = ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
			if level:
				levels.append({
					"path": full_path,
					"name": level.level_name,
					"description": level.level_description,
					"author": level.author,
					"modified_at": level.modified_at,
					"token_count": level.token_placements.size()
				})
			else:
				push_warning("LevelManager: Skipping incompatible level file: " + file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Sort by modified time (newest first)
	levels.sort_custom(func(a, b): return a.modified_at > b.modified_at)
	
	return levels


## Delete a level file
func delete_level(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	
	var error = DirAccess.remove_absolute(file_path)
	if error != OK:
		push_error("LevelManager: Failed to delete level: " + str(error))
		return false
	
	if current_level_path == file_path:
		current_level = null
		current_level_path = ""
	
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
	if level_data.map_glb_path == "":
		push_error("LevelManager: No map path specified")
		return null
	
	# Load and instantiate the map
	var map_scene: PackedScene
	if ResourceLoader.exists(level_data.map_glb_path):
		map_scene = load(level_data.map_glb_path)
	else:
		push_error("LevelManager: Map file not found: " + level_data.map_glb_path)
		return null
	
	var map_instance = map_scene.instantiate() as Node3D
	if not map_instance:
		push_error("LevelManager: Failed to instantiate map")
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
		"map_glb_path": level_data.map_glb_path,
		"map_scale": {"x": level_data.map_scale.x, "y": level_data.map_scale.y, "z": level_data.map_scale.z},
		"map_offset": {"x": level_data.map_offset.x, "y": level_data.map_offset.y, "z": level_data.map_offset.z},
		"token_placements": []
	}
	
	for placement in level_data.token_placements:
		data.token_placements.append({
			"placement_id": placement.placement_id,
			"pokemon_number": placement.pokemon_number,
			"is_shiny": placement.is_shiny,
			"position": {"x": placement.position.x, "y": placement.position.y, "z": placement.position.z},
			"rotation_y": placement.rotation_y,
			"scale": {"x": placement.scale.x, "y": placement.scale.y, "z": placement.scale.z},
			"token_name": placement.token_name,
			"is_player_controlled": placement.is_player_controlled,
			"max_health": placement.max_health,
			"current_health": placement.current_health,
			"is_visible_to_players": placement.is_visible_to_players
		})
	
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
	level.map_glb_path = data.get("map_glb_path", "")
	
	if data.has("map_scale"):
		level.map_scale = Vector3(data.map_scale.x, data.map_scale.y, data.map_scale.z)
	if data.has("map_offset"):
		level.map_offset = Vector3(data.map_offset.x, data.map_offset.y, data.map_offset.z)
	
	for placement_data in data.get("token_placements", []):
		var placement = TokenPlacement.new()
		placement.placement_id = placement_data.get("placement_id", TokenPlacement._generate_id())
		placement.pokemon_number = placement_data.get("pokemon_number", "")
		placement.is_shiny = placement_data.get("is_shiny", false)
		placement.position = Vector3(
			placement_data.position.x,
			placement_data.position.y,
			placement_data.position.z
		)
		placement.rotation_y = placement_data.get("rotation_y", 0.0)
		if placement_data.has("scale"):
			placement.scale = Vector3(
				placement_data.scale.x,
				placement_data.scale.y,
				placement_data.scale.z
			)
		placement.token_name = placement_data.get("token_name", "")
		placement.is_player_controlled = placement_data.get("is_player_controlled", false)
		placement.max_health = placement_data.get("max_health", 100)
		placement.current_health = placement_data.get("current_health", 100)
		placement.is_visible_to_players = placement_data.get("is_visible_to_players", true)
		level.token_placements.append(placement)
	
	return level
