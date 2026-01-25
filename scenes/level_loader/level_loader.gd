extends Node3D
class_name LevelLoader

## Loads and instantiates a level from LevelData
## Can be used as the main scene or instantiated dynamically

@export var level_data: LevelData

# Node references
var map_instance: Node3D = null
var tokens_container: Node3D = null
var game_map: GameMap = null

# References set after loading
var loaded_tokens: Array[BoardToken] = []


signal level_loaded(level_data: LevelData)
signal token_spawned(token: BoardToken, placement: TokenPlacement)


func _ready() -> void:
	if level_data:
		load_level(level_data)


## Load a level from LevelData resource
func load_level(data: LevelData) -> bool:
	level_data = data

	# Clear any existing level
	_clear_current_level()

	if data.map_glb_path == "":
		push_error("LevelLoader: No map path in level data")
		return false

	# Load the map
	if not _load_map():
		return false

	# Create tokens container
	tokens_container = Node3D.new()
	tokens_container.name = "LevelTokens"
	add_child(tokens_container)

	# Spawn all tokens
	for placement in level_data.token_placements:
		var token = _spawn_token(placement)
		if token:
			loaded_tokens.append(token)
			token_spawned.emit(token, placement)

	level_loaded.emit(level_data)

	return true


## Load the map GLB/scene
func _load_map() -> bool:
	if not ResourceLoader.exists(level_data.map_glb_path):
		push_error("LevelLoader: Map file not found: " + level_data.map_glb_path)
		return false

	var map_scene = load(level_data.map_glb_path)
	if not map_scene:
		push_error("LevelLoader: Failed to load map scene")
		return false

	map_instance = map_scene.instantiate() as Node3D
	if not map_instance:
		push_error("LevelLoader: Map is not a Node3D")
		return false

	map_instance.name = "Map"
	map_instance.scale = level_data.map_scale
	map_instance.position = level_data.map_offset
	add_child(map_instance)

	return true


## Spawn a single token from placement data
func _spawn_token(placement: TokenPlacement) -> BoardToken:
	var token = BoardTokenFactory.create_from_placement(placement)

	if not token:
		push_error("LevelLoader: Failed to create token for Pokemon " + placement.pokemon_number)
		return null

	tokens_container.add_child(token)

	return token


## Clear the current level
func _clear_current_level() -> void:
	for token in loaded_tokens:
		if is_instance_valid(token):
			token.queue_free()
	loaded_tokens.clear()

	if is_instance_valid(map_instance):
		map_instance.queue_free()
		map_instance = null

	if is_instance_valid(tokens_container):
		tokens_container.queue_free()
		tokens_container = null


## Get a token by its placement ID
func get_token_by_placement_id(placement_id: String) -> BoardToken:
	for token in loaded_tokens:
		if token.get_meta("placement_id", "") == placement_id:
			return token
	return null


## Reload the current level
func reload_level() -> bool:
	if level_data:
		return load_level(level_data)
	return false


## Load a level by file path
func load_level_from_file(file_path: String) -> bool:
	var data = LevelManager.load_level(file_path)
	if data:
		return load_level(data)
	return false
