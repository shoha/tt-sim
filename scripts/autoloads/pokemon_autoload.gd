extends Node

const POKEMON_DATA_PATH = "res://data/pokemon.json"

var available_pokemon: Dictionary = {}

enum AssetType {
	SCENE,
	ICON
}

func _ready() -> void:
	_load_pokemon_data()

func _load_pokemon_data() -> void:
	var file = FileAccess.open(POKEMON_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open pokemon data file: " + POKEMON_DATA_PATH)
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse pokemon data JSON: " + json.get_error_message())
		return

	available_pokemon = json.data

func _asset_path_for(number: String, is_shiny: bool, type: AssetType) -> String:
	var poke_name = available_pokemon[number].name
	var ext: String
	var subdir: String

	if type == AssetType.SCENE:
		ext = ".glb"
		subdir = "models"
	elif type == AssetType.ICON:
		ext = ".png"
		subdir = "icons"

	var path = "res://assets/" + subdir + "/pokemon/" + number + "_" + poke_name

	if is_shiny:
		path += "_shiny"

	path += ext

	return path

func path_to_scene(number: String, is_shiny: bool) -> String:
	return _asset_path_for(number, is_shiny, AssetType.SCENE)

func path_to_icon(number: String, is_shiny: bool) -> String:
	return _asset_path_for(number, is_shiny, AssetType.ICON)


## Get the display name for a pokemon by number
func get_pokemon_name(number: String) -> String:
	if number != "" and available_pokemon.has(number):
		return available_pokemon[number].name.capitalize()
	return "Unknown"
