extends Resource
class_name TokenState

## Pure state data for a token, designed for network synchronization.
## This resource contains all data needed to represent and sync a token's state.
## Separated from BoardToken to enable clean network state management.
##
## Usage:
##   - GameState maintains a dictionary of TokenState objects
##   - Changes to TokenState emit signals that visuals can observe
##   - Netfox can sync TokenState properties directly
##
## Network Considerations:
##   - All properties are designed to be serializable
##   - The network_id is the unique identifier across host/clients
##   - Changes should go through GameState for proper signal emission

## Unique identifier for network synchronization
## Matches BoardToken.network_id and TokenPlacement.placement_id
@export var network_id: String = ""

## Asset identification (for recreating the token visual)
@export_group("Asset")
@export var pack_id: String = ""
@export var asset_id: String = ""
@export var variant_id: String = "default"

## Transform data
@export_group("Transform")
@export var position: Vector3 = Vector3.ZERO
@export var rotation: Vector3 = Vector3.ZERO
@export var scale: Vector3 = Vector3.ONE

## Entity identification
@export_group("Identity")
@export var token_name: String = "Token"
@export var is_player_controlled: bool = false
@export var character_id: String = ""

## Health and combat state
@export_group("Health")
@export var max_health: int = 100
@export var current_health: int = 100
@export var is_alive: bool = true

## Visibility
@export_group("Visibility")
@export var is_visible_to_players: bool = true
@export var is_hidden_from_gm: bool = false

## Status effects
@export_group("Status")
@export var status_effects: Array[String] = []


## Create a TokenState from a BoardToken
static func from_board_token(token: BoardToken) -> TokenState:
	var state = TokenState.new()
	state.network_id = token.network_id

	# Get asset info from metadata
	state.pack_id = token.get_meta("pack_id", "")
	state.asset_id = token.get_meta("asset_id", "")
	state.variant_id = token.get_meta("variant_id", "default")

	# Transform from rigid body (what actually moves)
	var rigid_body = token.get_rigid_body()
	if rigid_body:
		state.position = rigid_body.global_position
		state.rotation = rigid_body.rotation
		state.scale = rigid_body.scale
	else:
		state.position = token.global_position
		state.rotation = token.rotation
		state.scale = token.scale

	# Identity
	state.token_name = token.token_name
	state.is_player_controlled = token.is_player_controlled
	state.character_id = token.character_id

	# Health
	state.max_health = token.max_health
	state.current_health = token.current_health
	state.is_alive = token.is_alive

	# Visibility
	state.is_visible_to_players = token.is_visible_to_players
	state.is_hidden_from_gm = token.is_hidden_from_gm

	# Status
	state.status_effects = token.status_effects.duplicate()

	return state


## Create a TokenState from a TokenPlacement
static func from_placement(placement: TokenPlacement) -> TokenState:
	var state = TokenState.new()
	state.network_id = placement.placement_id

	# Asset info
	state.pack_id = placement.pack_id
	state.asset_id = placement.asset_id
	state.variant_id = placement.variant_id

	# Transform
	state.position = placement.position
	state.rotation = Vector3(0, placement.rotation_y, 0)
	state.scale = placement.scale

	# Identity
	state.token_name = placement.token_name
	state.is_player_controlled = placement.is_player_controlled

	# Health
	state.max_health = placement.max_health
	state.current_health = placement.current_health
	state.is_alive = placement.is_alive

	# Visibility
	state.is_visible_to_players = placement.is_visible_to_players

	# Status
	state.status_effects = placement.status_effects.duplicate()

	return state


## Apply this state to a BoardToken
func apply_to_token(token: BoardToken) -> void:
	# Transform
	var rigid_body = token.get_rigid_body()
	if rigid_body:
		rigid_body.global_position = position
		rigid_body.rotation = rotation
		rigid_body.scale = scale
	else:
		token.global_position = position
		token.rotation = rotation
		token.scale = scale

	# Identity
	token.token_name = token_name
	token.is_player_controlled = is_player_controlled
	token.character_id = character_id

	# Health
	token.max_health = max_health
	token.current_health = current_health
	token.is_alive = is_alive

	# Visibility (use setter to update visuals)
	token.set_visible_to_players(is_visible_to_players)
	token.is_hidden_from_gm = is_hidden_from_gm

	# Status effects
	token.status_effects = status_effects.duplicate()


## Convert to a dictionary for network transmission
func to_dict() -> Dictionary:
	return {
		"network_id": network_id,
		"pack_id": pack_id,
		"asset_id": asset_id,
		"variant_id": variant_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"rotation": {"x": rotation.x, "y": rotation.y, "z": rotation.z},
		"scale": {"x": scale.x, "y": scale.y, "z": scale.z},
		"token_name": token_name,
		"is_player_controlled": is_player_controlled,
		"character_id": character_id,
		"max_health": max_health,
		"current_health": current_health,
		"is_alive": is_alive,
		"is_visible_to_players": is_visible_to_players,
		"is_hidden_from_gm": is_hidden_from_gm,
		"status_effects": status_effects.duplicate(),
	}


## Create a TokenState from a dictionary (for network reception)
static func from_dict(data: Dictionary) -> TokenState:
	var state = TokenState.new()
	state.network_id = data.get("network_id", "")
	state.pack_id = data.get("pack_id", "")
	state.asset_id = data.get("asset_id", "")
	state.variant_id = data.get("variant_id", "default")

	var pos = data.get("position", {})
	state.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))

	var rot = data.get("rotation", {})
	state.rotation = Vector3(rot.get("x", 0), rot.get("y", 0), rot.get("z", 0))

	var scl = data.get("scale", {"x": 1, "y": 1, "z": 1})
	state.scale = Vector3(scl.get("x", 1), scl.get("y", 1), scl.get("z", 1))

	state.token_name = data.get("token_name", "Token")
	state.is_player_controlled = data.get("is_player_controlled", false)
	state.character_id = data.get("character_id", "")
	state.max_health = data.get("max_health", 100)
	state.current_health = data.get("current_health", 100)
	state.is_alive = data.get("is_alive", true)
	state.is_visible_to_players = data.get("is_visible_to_players", true)
	state.is_hidden_from_gm = data.get("is_hidden_from_gm", false)
	state.status_effects = data.get("status_effects", [])

	return state


## Create a duplicate of this state
func duplicate_state() -> TokenState:
	return from_dict(to_dict())


## Check if this token should be synchronized to a specific client
## Used for visibility filtering in network sync
## @param _client_id: Reserved for future per-player visibility (currently unused)
## @param is_gm: Whether the client is the GM/host
func should_sync_to_client(_client_id: String, is_gm: bool = false) -> bool:
	# GM always sees everything except explicitly hidden tokens
	if is_gm:
		return not is_hidden_from_gm

	# Regular players only see visible tokens
	return is_visible_to_players
