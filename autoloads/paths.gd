extends Node

## Centralized path constants for the project.
## Use this autoload for all resource paths to maintain consistency.

# User data directories
const LEVELS_DIR: String = "user://levels/"

# User asset packs directory (new pack-based system)
const USER_ASSETS_DIR: String = "res://user_assets/"

# Data files
const POKEMON_DATA_PATH: String = "res://data/pokemon.json"

# Asset directories
const ASSETS_DIR: String = "res://assets/"
const MODELS_DIR: String = "res://assets/models/"
const ICONS_DIR: String = "res://assets/icons/"
const MAPS_DIR: String = "res://assets/models/maps/"

# Legacy Pokemon directories (DEPRECATED - assets now in user_assets/pokemon/)
const POKEMON_MODELS_DIR: String = "res://user_assets/pokemon/models/"
const POKEMON_ICONS_DIR: String = "res://user_assets/pokemon/icons/"

# Scene directories
const SCENES_DIR: String = "res://scenes/"
const BOARD_TOKEN_DIR: String = "res://scenes/board_token/"


## Get the base path for an asset pack
func pack_path(pack_id: String) -> String:
	return USER_ASSETS_DIR + pack_id + "/"


## Get the models directory for an asset pack
func pack_models_path(pack_id: String) -> String:
	return pack_path(pack_id) + "models/"


## Get the icons directory for an asset pack
func pack_icons_path(pack_id: String) -> String:
	return pack_path(pack_id) + "icons/"


## Build a Pokemon model path from number and shiny flag
## DEPRECATED: Use AssetPackManager.get_model_path("pokemon", number, variant) instead
func pokemon_model_path(number: String, poke_name: String, is_shiny: bool) -> String:
	var path = POKEMON_MODELS_DIR + number + "_" + poke_name
	if is_shiny:
		path += "_shiny"
	path += ".glb"
	return path


## Build a Pokemon icon path from number and shiny flag
## DEPRECATED: Use AssetPackManager.get_icon_path("pokemon", number, variant) instead
func pokemon_icon_path(number: String, poke_name: String, is_shiny: bool) -> String:
	var path = POKEMON_ICONS_DIR + number + "_" + poke_name
	if is_shiny:
		path += "_shiny"
	path += ".png"
	return path
