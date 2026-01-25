extends Control

## Controller for the MapMenu UI
## Handles button presses and level editor integration

var _level_editor_instance: Control = null
var _active_level_data: LevelData = null
var _spawned_tokens: Dictionary = {} # placement_id -> iBoardToken
var _loaded_map_instance: Node3D = null

const LevelEditorScene = preload("res://scenes/level_editor/level_editor.tscn")
const LevelLoaderScene = preload("res://scenes/level_loader/level_loader.tscn")

@onready var save_positions_button: Button = %SavePositionsButton

func _ready() -> void:
	# Listen for new tokens being created so we can add them to the active level
	EventBus.token_created.connect(_on_token_created)


func _on_level_editor_button_pressed() -> void:
	_open_level_editor()


func _open_level_editor() -> void:
	if _level_editor_instance and is_instance_valid(_level_editor_instance):
		# Refresh the token list in case tokens were added during play
		_level_editor_instance._refresh_token_list()
		_level_editor_instance.show()
		return

	_level_editor_instance = LevelEditorScene.instantiate()
	_level_editor_instance.editor_closed.connect(_on_editor_closed)
	_level_editor_instance.play_level_requested.connect(_on_play_level_requested)
	add_child(_level_editor_instance)


func _on_editor_closed() -> void:
	if _level_editor_instance:
		_level_editor_instance.queue_free()
		_level_editor_instance = null


func _on_play_level_requested(level_data: LevelData) -> void:
	# Close the editor
	if _level_editor_instance:
		_level_editor_instance.hide()

	# Clear any previously loaded level first
	clear_level()

	# Store reference to active level
	_active_level_data = level_data

	# Find the game map
	var game_map = _find_game_map()
	if not game_map:
		push_error("MapMenuController: Could not find GameMap")
		return

	# Load the map model from level data
	if not _load_level_map(level_data, game_map):
		push_error("MapMenuController: Failed to load map")
		return

	var drag_and_drop = game_map.drag_and_drop_node
	if not drag_and_drop:
		push_error("MapMenuController: Could not find DragAndDrop3D node")
		return

	# Spawn all tokens from the level
	for placement in level_data.token_placements:
		var token = _spawn_token_from_placement(placement)
		if token:
			drag_and_drop.add_child(token)

			# Track token by placement ID
			token.set_meta("placement_id", placement.placement_id)
			token.set_meta("pokemon_number", placement.pokemon_number)
			token.set_meta("is_shiny", placement.is_shiny)
			_spawned_tokens[placement.placement_id] = token

			# Connect context menu
			var token_controller = token.get_controller_component()
			if token_controller and token_controller.has_signal("context_menu_requested"):
				if game_map.has_method("_on_token_context_menu_requested"):
					token_controller.context_menu_requested.connect(game_map._on_token_context_menu_requested)

	# Show save button
	_update_save_button_visibility()


## Load the map model from level data
func _load_level_map(level_data: LevelData, game_map: GameMap) -> bool:
	# Remove previous level map if exists
	if is_instance_valid(_loaded_map_instance):
		_loaded_map_instance.queue_free()
		_loaded_map_instance = null

	# Also clear any existing map children that might be in the scene
	# Look for children that are 3D models (not UI, cameras, environments, etc.)
	_clear_existing_maps(game_map)

	# Check for valid map path
	if level_data.map_glb_path == "":
		push_error("MapMenuController: No map path in level data")
		return false

	if not ResourceLoader.exists(level_data.map_glb_path):
		push_error("MapMenuController: Map file not found: " + level_data.map_glb_path)
		return false

	# Load and instantiate the map
	var map_scene = load(level_data.map_glb_path)
	if not map_scene:
		push_error("MapMenuController: Failed to load map scene")
		return false

	_loaded_map_instance = map_scene.instantiate() as Node3D
	if not _loaded_map_instance:
		push_error("MapMenuController: Map is not a Node3D")
		return false

	_loaded_map_instance.name = "LevelMap"
	_loaded_map_instance.scale = level_data.map_scale
	_loaded_map_instance.position = level_data.map_offset

	# Add to the GameMap node
	game_map.add_child(_loaded_map_instance)

	return true


func _find_game_map() -> GameMap:
	# Navigate up to find the GameMap
	var parent = get_parent()
	while parent:
		if parent is GameMap:
			return parent
		# Check siblings
		for sibling in parent.get_children():
			if sibling is GameMap:
				return sibling
		parent = parent.get_parent()

	# Try finding by tree
	var root = get_tree().root
	return _find_game_map_recursive(root)


func _find_game_map_recursive(node: Node) -> GameMap:
	if node is GameMap:
		return node
	for child in node.get_children():
		var result = _find_game_map_recursive(child)
		if result:
			return result
	return null


func _spawn_token_from_placement(placement: TokenPlacement) -> iBoardToken:
	var scene_path = PokemonAutoload.path_to_scene(placement.pokemon_number, placement.is_shiny)

	if not ResourceLoader.exists(scene_path):
		push_error("MapMenuController: Pokemon scene not found: " + scene_path)
		return null

	var pokemon_scene = load(scene_path)
	var model = pokemon_scene.instantiate()
	var token = BoardTokenFactory.create_from_scene(model)

	if not token:
		push_error("MapMenuController: Failed to create token")
		return null

	# Set the node name and display name to the pokemon name
	var pokemon_name = PokemonAutoload.get_pokemon_name(placement.pokemon_number)
	token.name = pokemon_name
	token.token_name = pokemon_name

	placement.apply_to_token(token)
	return token


func _update_save_button_visibility() -> void:
	if save_positions_button:
		save_positions_button.visible = _active_level_data != null and _spawned_tokens.size() > 0


func _on_save_positions_button_pressed() -> void:
	save_token_positions()


## Update level data with current token positions and save
func save_token_positions() -> void:
	if not _active_level_data:
		push_error("MapMenuController: No active level to save")
		return

	var updated_count = 0

	# Update map position and scale from the loaded map instance
	if is_instance_valid(_loaded_map_instance):
		_active_level_data.map_scale = _loaded_map_instance.scale
		_active_level_data.map_offset = _loaded_map_instance.position

	# Update each placement with current token position
	for placement in _active_level_data.token_placements:
		if _spawned_tokens.has(placement.placement_id):
			var token = _spawned_tokens[placement.placement_id] as iBoardToken
			if is_instance_valid(token):
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
				updated_count += 1

	# Save the level
	var path = LevelManager.save_level(_active_level_data)
	if path == "":
		push_error("MapMenuController: Failed to save level")


## Clear spawned tokens and reset state
func clear_level_tokens() -> void:
	for placement_id in _spawned_tokens:
		var token = _spawned_tokens[placement_id]
		if is_instance_valid(token):
			token.queue_free()

	_spawned_tokens.clear()
	_active_level_data = null
	_update_save_button_visibility()


## Clear the loaded level map
func clear_level_map() -> void:
	if is_instance_valid(_loaded_map_instance):
		_loaded_map_instance.queue_free()
		_loaded_map_instance = null


## Clear any existing map models from the game map
## This handles cases where a default map was already in the scene
func _clear_existing_maps(game_map: GameMap) -> void:
	# List of node names/types to preserve (not maps)
	var preserved_names = ["WorldEnvironment", "MapMenu", "DragAndDrop3D", "LevelMap"]
	
	for child in game_map.get_children():
		# Skip UI nodes, environments, and the drag-and-drop container
		if child.name in preserved_names:
			continue
		# Skip Control nodes (UI)
		if child is Control:
			continue
		# Skip CanvasLayer
		if child is CanvasLayer:
			continue
		# If it's a Node3D that's not one of our known nodes, it's likely a map model
		if child is Node3D:
			child.queue_free()


## Clear everything from the current level
func clear_level() -> void:
	clear_level_tokens()
	clear_level_map()


## Handle new tokens created via the "Add Pokemon" button
## If we have an active level, add them to the level data for tracking
func _on_token_created(token: iBoardToken, pokemon_number: String, is_shiny: bool) -> void:
	# Only track if we have an active level being played/edited
	if not _active_level_data:
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
	_active_level_data.add_token_placement(placement)

	# Track the token
	token.set_meta("placement_id", placement.placement_id)
	token.set_meta("pokemon_number", pokemon_number)
	token.set_meta("is_shiny", is_shiny)
	_spawned_tokens[placement.placement_id] = token

	# Update save button visibility
	_update_save_button_visibility()
