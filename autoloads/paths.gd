class_name Paths

## Centralized path constants for the project.
## Accessible everywhere via the class_name (no autoload needed).

# User data directories
const LEVELS_DIR: String = "user://levels/"

# Special pack ID for map streaming (used by AssetStreamer)
const LEVEL_MAPS_PACK_ID: String = "_level_maps"

# User asset packs directory (pack-based system)
const USER_ASSETS_DIR: String = "res://user_assets/"

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


## Get the base path for an asset pack
static func pack_path(pack_id: String) -> String:
	return USER_ASSETS_DIR + pack_id + "/"


## Get the models directory for an asset pack
static func pack_models_path(pack_id: String) -> String:
	return pack_path(pack_id) + "models/"


## Get the icons directory for an asset pack
static func pack_icons_path(pack_id: String) -> String:
	return pack_path(pack_id) + "icons/"


## Get the folder path for a level (where level.json and map.glb are stored)
static func get_level_folder(level_name: String) -> String:
	return LEVELS_DIR + level_name + "/"


## Get the map GLB path within a level folder
static func get_level_map_path(level_name: String) -> String:
	return get_level_folder(level_name) + "map.glb"


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
