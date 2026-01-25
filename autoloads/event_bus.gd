extends Node

signal pokemon_added(pokemon: PackedScene)
signal token_selected(token: Node3D)

# Token creation signal with full metadata for level editor tracking
signal token_created(token: BoardToken, pokemon_number: String, is_shiny: bool)

# Level editor signals
signal level_editor_requested
signal level_load_requested(level_data: LevelData)
signal level_play_requested(level_data: LevelData)
