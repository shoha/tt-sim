extends Resource
class_name TokenPlacement

## Represents a placed token in a level
## Stores the Pokemon identity, position, and custom stats

## Pokemon identification
@export var pokemon_number: String = ""
@export var is_shiny: bool = false

## Transform data
@export var position: Vector3 = Vector3.ZERO
@export var rotation_y: float = 0.0
@export var scale: Vector3 = Vector3.ONE

## Token properties (overrides defaults if set)
@export_group("Token Properties")
@export var token_name: String = ""
@export var is_player_controlled: bool = false
@export var max_health: int = 100
@export var current_health: int = 100

## Visibility
@export_group("Visibility")
@export var is_visible_to_players: bool = true

## Unique identifier for this placement
@export var placement_id: String = ""


func _init() -> void:
	placement_id = _generate_id()


static func _generate_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)


## Create a TokenPlacement from an existing BoardToken
static func from_board_token(token: BoardToken, pokemon_num: String, shiny: bool) -> TokenPlacement:
	var placement = TokenPlacement.new()
	placement.pokemon_number = pokemon_num
	placement.is_shiny = shiny

	# Read position from rigid_body since that's what gets moved during gameplay
	var rigid_body = token.get_rigid_body()
	if rigid_body:
		placement.position = rigid_body.global_position
		placement.rotation_y = rigid_body.rotation.y
		placement.scale = rigid_body.scale
	else:
		placement.position = token.global_position
		placement.rotation_y = token.rotation.y
		placement.scale = token.scale

	placement.token_name = token.token_name
	placement.is_player_controlled = token.is_player_controlled
	placement.max_health = token.max_health
	placement.current_health = token.current_health
	placement.is_visible_to_players = token.is_visible_to_players
	return placement


## Apply this placement's properties to a BoardToken
## Note: Positions the rigid_body since that's what the drag system moves
func apply_to_token(token: BoardToken) -> void:
	# The rigid_body is what gets moved during gameplay, so position it
	var rigid_body = token.get_rigid_body()
	if rigid_body:
		rigid_body.position = position
		rigid_body.rotation.y = rotation_y
		rigid_body.scale = scale
	else:
		token.position = position
		token.rotation.y = rotation_y
		token.scale = scale

	if token_name != "":
		token.token_name = token_name
	token.is_player_controlled = is_player_controlled
	token.max_health = max_health
	token.current_health = current_health
	# Use the setter to ensure visibility visuals are updated
	token.set_visible_to_players(is_visible_to_players)


## Get display name for this placement
func get_display_name() -> String:
	if token_name != "":
		return token_name
	if pokemon_number != "" and PokemonAutoload.available_pokemon.has(pokemon_number):
		var poke_data = PokemonAutoload.available_pokemon[pokemon_number]
		return poke_data.name.capitalize()
	return "Unknown Token"
