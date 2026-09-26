class_name Paths

## Centralized path constants for the project.
## Accessible everywhere via the class_name (no autoload needed).

# User data directories
const LEVELS_DIR: String = "user://levels/"
const SETTINGS_PATH: String = "user://settings.cfg"
const PERF_LOG_DIR: String = "user://perf_logs/"

# Special pack ID for map streaming (used by AssetStreamer)
const LEVEL_MAPS_PACK_ID: String = "_level_maps"
# The map files of a level folder, and the streaming variant id that names each one. A
# level has a Blender-made map.glb, an authored map.ttmap, or both.
const LEVEL_MAP_NAME: String = "map.glb"
const LEVEL_MAP_DOCUMENT_NAME: String = "map.ttmap"
const LEVEL_MAP_VARIANT: String = "map"
const LEVEL_MAP_DOCUMENT_VARIANT: String = "ttmap"

# Data files
const POKEMON_DATA_PATH: String = "res://data/pokemon.json"

# Asset directories
const ASSETS_DIR: String = "res://assets/"
const MODELS_DIR: String = "res://assets/models/"
const ICONS_DIR: String = "res://assets/icons/"
const MAPS_DIR: String = "res://assets/models/maps/"

# Scene directories
const SCENES_DIR: String = "res://scenes/"
const BOARD_TOKEN_DIR: String = "res://scenes/board_token/"


## Get the folder path for a level (where level.json and map.glb are stored)
static func get_level_folder(level_name: String) -> String:
	return LEVELS_DIR + level_name + "/"


## Get the map GLB path within a level folder
static func get_level_map_path(level_name: String) -> String:
	return get_level_folder(level_name) + LEVEL_MAP_NAME


## Get the authored map document (map.ttmap) path within a level folder
static func get_level_map_document_path(level_name: String) -> String:
	return get_level_folder(level_name) + LEVEL_MAP_DOCUMENT_NAME


## The file a streaming variant id names in a level folder: the whitelist the host serves
## level map requests through. "" for any variant other than the two map files, so a
## client-chosen variant can never name another file.
static func get_level_map_file_for_variant(level_name: String, variant_id: String) -> String:
	match variant_id:
		LEVEL_MAP_VARIANT:
			return get_level_map_path(level_name)
		LEVEL_MAP_DOCUMENT_VARIANT:
			return get_level_map_document_path(level_name)
	return ""


## Get the level.json path within a level folder
static func get_level_json_path(level_name: String) -> String:
	return get_level_folder(level_name) + "level.json"


## Sanitize a level name for use as a folder name
static func sanitize_level_name(level_name: String) -> String:
	var sanitized = level_name.strip_edges().to_lower()
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
