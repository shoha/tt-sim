extends Node

## Manages Pokemon data loading and asset path resolution.

var available_pokemon: Dictionary = {}


func _ready() -> void:
	_load_pokemon_data()


func _load_pokemon_data() -> void:
	var file = FileAccess.open(Paths.POKEMON_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open pokemon data file: " + Paths.POKEMON_DATA_PATH)
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse pokemon data JSON: " + json.get_error_message())
		return

	available_pokemon = json.data


func path_to_scene(number: String, is_shiny: bool) -> String:
	var poke_name = available_pokemon[number].name
	return Paths.pokemon_model_path(number, poke_name, is_shiny)


func path_to_icon(number: String, is_shiny: bool) -> String:
	var poke_name = available_pokemon[number].name
	return Paths.pokemon_icon_path(number, poke_name, is_shiny)


## Get the display name for a pokemon by number
func get_pokemon_name(number: String) -> String:
	if number != "" and available_pokemon.has(number):
		return available_pokemon[number].name.capitalize()
	return "Unknown"
