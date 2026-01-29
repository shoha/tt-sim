extends Node
class_name LevelPlayController

## Manages level playback: loading maps, spawning tokens, tracking state.
## Extracted from MapMenuController to follow single-responsibility principle.

signal level_loaded(level_data: LevelData)
signal level_cleared()
signal token_spawned(token: BoardToken, placement: TokenPlacement)
signal token_added(token: BoardToken)

var active_level_data: LevelData = null
var spawned_tokens: Dictionary = {} # placement_id -> BoardToken
var loaded_map_instance: Node3D = null
var _game_map: GameMap = null


## Initialize with a reference to the game map
func setup(game_map: GameMap) -> void:
	_game_map = game_map


## Load and play a level
func play_level(level_data: LevelData) -> bool:
	if not _game_map:
		push_error("LevelPlayController: No GameMap set. Call setup() first.")
		return false

	# Clear any previously loaded level first
	clear_level()

	# Store reference to active level
	active_level_data = level_data

	# Load the map model from level data
	if not _load_level_map(level_data):
		push_error("LevelPlayController: Failed to load map")
		return false

	var drag_and_drop = _game_map.drag_and_drop_node
	if not drag_and_drop:
		push_error("LevelPlayController: Could not find DragAndDrop3D node")
		return false

	# Spawn all tokens from the level
	for placement in level_data.token_placements:
		var token = BoardTokenFactory.create_from_placement(placement)
		if token:
			drag_and_drop.add_child(token)
			_track_token(token, placement)
			_connect_token_context_menu(token)
			token_spawned.emit(token, placement)

	level_loaded.emit(level_data)
	return true


## Load the map model from level data
func _load_level_map(level_data: LevelData) -> bool:
	# Remove previous level map if exists
	if is_instance_valid(loaded_map_instance):
		loaded_map_instance.queue_free()
		loaded_map_instance = null

	# Clear any existing map children from the game map
	_clear_existing_maps()

	# Check for valid map path
	if level_data.map_path == "":
		push_error("LevelPlayController: No map path in level data")
		return false

	if not ResourceLoader.exists(level_data.map_path):
		push_error("LevelPlayController: Map file not found: " + level_data.map_path)
		return false

	# Load and instantiate the map
	var map_scene = load(level_data.map_path)
	if not map_scene:
		push_error("LevelPlayController: Failed to load map scene")
		return false

	loaded_map_instance = map_scene.instantiate() as Node3D
	if not loaded_map_instance:
		push_error("LevelPlayController: Map is not a Node3D")
		return false

	loaded_map_instance.name = "LevelMap"
	loaded_map_instance.scale = level_data.map_scale
	loaded_map_instance.position = level_data.map_offset

	# Add to the GameMap node
	_game_map.add_child(loaded_map_instance)

	return true


## Track a spawned token
func _track_token(token: BoardToken, placement: TokenPlacement) -> void:
	spawned_tokens[placement.placement_id] = token


## Connect token's context menu signal to game map
func _connect_token_context_menu(token: BoardToken) -> void:
	var token_controller = token.get_controller_component()
	if token_controller and token_controller.has_signal("context_menu_requested"):
		if _game_map.has_method("_on_token_context_menu_requested"):
			token_controller.context_menu_requested.connect(_game_map._on_token_context_menu_requested)


## Clear any existing map models from the game map
func _clear_existing_maps() -> void:
	if not _game_map:
		return

	# List of node names/types to preserve (not maps)
	var preserved_names = ["MapMenu", "DragAndDrop3D", "LevelMap", "CameraHolder", "PixelateCanvas", "SharpenCanvas"]

	for child in _game_map.get_children():
		# Skip UI nodes, environments, and the drag-and-drop container
		if child.name in preserved_names:
			continue
		if child is Control or child is CanvasLayer:
			continue
		# If it's a Node3D that's not one of our known nodes, it's likely a map model
		if child is Node3D:
			child.queue_free()


## Spawn a Pokemon token and add it to the current level
## Returns the created token, or null if spawning failed
func spawn_pokemon(pokemon_number: String, is_shiny: bool) -> BoardToken:
	if not _game_map or not active_level_data:
		push_warning("LevelPlayController: Cannot spawn Pokemon - no GameMap or active level")
		return null

	var token = BoardTokenFactory.create_from_pokemon(pokemon_number, is_shiny)
	if not token:
		push_error("LevelPlayController: Failed to create board token")
		return null

	_game_map.drag_and_drop_node.add_child(token)
	_connect_token_context_menu(token)
	add_token_to_level(token, pokemon_number, is_shiny)
	token_added.emit(token)
	return token


## Add a new token to the active level
func add_token_to_level(token: BoardToken, pokemon_number: String, is_shiny: bool) -> void:
	if not active_level_data:
		return

	# Create a new placement for this token
	var placement = TokenPlacement.new()
	placement.pokemon_number = pokemon_number
	placement.is_shiny = is_shiny
	placement.position = Vector3.ZERO # Will be updated when saved

	# Set default name from pokemon
	if PokemonAutoload.available_pokemon.has(pokemon_number):
		placement.token_name = PokemonAutoload.available_pokemon[pokemon_number].name.capitalize()

	# Add to level data
	active_level_data.add_token_placement(placement)

	# Track the token
	token.set_meta("placement_id", placement.placement_id)
	token.set_meta("pokemon_number", pokemon_number)
	token.set_meta("is_shiny", is_shiny)
	spawned_tokens[placement.placement_id] = token


## Save current token positions to level data
func save_token_positions() -> String:
	if not active_level_data:
		push_error("LevelPlayController: No active level to save")
		return ""

	# Update map position and scale from the loaded map instance
	if is_instance_valid(loaded_map_instance):
		active_level_data.map_scale = loaded_map_instance.scale
		active_level_data.map_offset = loaded_map_instance.position

	# Update each placement with current token position
	for placement in active_level_data.token_placements:
		if spawned_tokens.has(placement.placement_id):
			var token = spawned_tokens[placement.placement_id] as BoardToken
			if is_instance_valid(token):
				_sync_placement_from_token(placement, token)

	# Save the level
	return LevelManager.save_level(active_level_data)


## Sync placement data from a token's current state
func _sync_placement_from_token(placement: TokenPlacement, token: BoardToken) -> void:
	# The rigid_body is what actually gets moved/scaled during dragging
	var rigid_body = token.get_rigid_body()
	if rigid_body:
		placement.position = rigid_body.global_position
		placement.rotation_y = rigid_body.rotation.y
		placement.scale = rigid_body.scale
	else:
		placement.position = token.global_position
		placement.rotation_y = token.rotation.y
		placement.scale = token.scale

	# Also sync current stats
	placement.token_name = token.token_name
	placement.max_health = token.max_health
	placement.current_health = token.current_health
	placement.is_visible_to_players = token.is_visible_to_players
	placement.is_player_controlled = token.is_player_controlled


## Clear spawned tokens
func clear_level_tokens() -> void:
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id]
		if is_instance_valid(token):
			token.queue_free()

	spawned_tokens.clear()
	active_level_data = null


## Clear the loaded level map
func clear_level_map() -> void:
	if is_instance_valid(loaded_map_instance):
		loaded_map_instance.queue_free()
		loaded_map_instance = null


## Clear everything from the current level
func clear_level() -> void:
	clear_level_tokens()
	clear_level_map()
	level_cleared.emit()


## Check if a level is currently loaded
func has_active_level() -> bool:
	return active_level_data != null


## Get token count
func get_token_count() -> int:
	return spawned_tokens.size()
