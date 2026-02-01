extends Node

## DEPRECATED: Use AssetPackManager instead for the new pack-based asset system.
## This autoload is kept for backward compatibility with existing code.
##
## Manages Pokemon data loading and asset path resolution.
## Now acts as a thin wrapper around AssetPackManager for the "pokemon" pack.

var available_pokemon: Dictionary = {}


func _ready() -> void:
	_load_pokemon_data()


func _load_pokemon_data() -> void:
	# Still load the legacy data file for backward compatibility
	var file = FileAccess.open(Paths.POKEMON_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("PokemonAutoload: Legacy pokemon.json not found - using AssetPackManager instead")
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse pokemon data JSON: " + json.get_error_message())
		return

	available_pokemon = json.data


## DEPRECATED: Use AssetPackManager.get_model_path("pokemon", number, variant) instead
func path_to_scene(number: String, is_shiny: bool) -> String:
	var variant = "shiny" if is_shiny else "default"
	return AssetPackManager.get_model_path("pokemon", number, variant)


## DEPRECATED: Use AssetPackManager.get_icon_path("pokemon", number, variant) instead
func path_to_icon(number: String, is_shiny: bool) -> String:
	var variant = "shiny" if is_shiny else "default"
	return AssetPackManager.get_icon_path("pokemon", number, variant)


## DEPRECATED: Use AssetPackManager.get_asset_display_name("pokemon", number) instead
## Get the display name for a pokemon by number
func get_pokemon_name(number: String) -> String:
	# Try new system first
	var display_name = AssetPackManager.get_asset_display_name("pokemon", number)
	if display_name != "Unknown":
		return display_name
	
	# Fallback to legacy data
	if number != "" and available_pokemon.has(number):
		return available_pokemon[number].name.capitalize()
	return "Unknown"
