extends Node

## Centralized path constants for the project.
## Use this autoload for all resource paths to maintain consistency.

# User data directories
const LEVELS_DIR: String = "user://levels/"

# Data files
const POKEMON_DATA_PATH: String = "res://data/pokemon.json"

# Asset directories
const ASSETS_DIR: String = "res://assets/"
const MODELS_DIR: String = "res://assets/models/"
const ICONS_DIR: String = "res://assets/icons/"
const POKEMON_MODELS_DIR: String = "res://assets/models/user/pokemon/"
const POKEMON_ICONS_DIR: String = "res://assets/icons/user/pokemon/"
const MAPS_DIR: String = "res://assets/models/maps/"

# Scene directories
const SCENES_DIR: String = "res://scenes/"
const BOARD_TOKEN_DIR: String = "res://scenes/board_token/"


## Build a Pokemon model path from number and shiny flag
func pokemon_model_path(number: String, poke_name: String, is_shiny: bool) -> String:
	var path = POKEMON_MODELS_DIR + number + "_" + poke_name
	if is_shiny:
		path += "_shiny"
	path += ".glb"
	return path


## Build a Pokemon icon path from number and shiny flag
func pokemon_icon_path(number: String, poke_name: String, is_shiny: bool) -> String:
	var path = POKEMON_ICONS_DIR + number + "_" + poke_name
	if is_shiny:
		path += "_shiny"
	path += ".png"
	return path
