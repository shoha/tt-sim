extends Resource
class_name TokenPlacement

## Represents a placed token in a level
## Stores the asset identity, position, and custom stats

## Asset identification (pack-based system)
@export var pack_id: String = ""
@export var asset_id: String = ""
@export var variant_id: String = "default"

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

## Status effects
@export_group("Status")
@export var status_effects: Array[String] = []
@export var is_alive: bool = true

## Unique identifier for this placement (also used as network_id)
@export var placement_id: String = ""


func _init() -> void:
	placement_id = _generate_id()


static func _generate_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)


## Create a TokenPlacement from an existing BoardToken
static func from_board_token(token: BoardToken, pack: String, asset: String, variant: String = "default") -> TokenPlacement:
	var placement = TokenPlacement.new()
	placement.pack_id = pack
	placement.asset_id = asset
	placement.variant_id = variant

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
	placement.status_effects = token.status_effects.duplicate()
	placement.is_alive = token.is_alive
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
	token.is_alive = is_alive
	# Restore status effects
	token.status_effects = status_effects.duplicate()
	# Use the setter to ensure visibility visuals are updated
	token.set_visible_to_players(is_visible_to_players)


## Get display name for this placement
func get_display_name() -> String:
	if token_name != "":
		return token_name
	
	if pack_id != "" and asset_id != "":
		return AssetPackManager.get_asset_display_name(pack_id, asset_id)
	
	return "Unknown Token"


## Convert to dictionary for network transmission
func to_dict() -> Dictionary:
	return {
		"placement_id": placement_id,
		"pack_id": pack_id,
		"asset_id": asset_id,
		"variant_id": variant_id,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"rotation_y": rotation_y,
		"scale": {"x": scale.x, "y": scale.y, "z": scale.z},
		"token_name": token_name,
		"is_player_controlled": is_player_controlled,
		"max_health": max_health,
		"current_health": current_health,
		"is_visible_to_players": is_visible_to_players,
		"status_effects": status_effects.duplicate(),
		"is_alive": is_alive,
	}


## Create from dictionary (for network reception)
static func from_dict(data: Dictionary) -> TokenPlacement:
	var placement = TokenPlacement.new()
	placement.placement_id = data.get("placement_id", _generate_id())
	placement.pack_id = data.get("pack_id", "")
	placement.asset_id = data.get("asset_id", "")
	placement.variant_id = data.get("variant_id", "default")
	
	var pos = data.get("position", {})
	placement.position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
	placement.rotation_y = data.get("rotation_y", 0.0)
	
	var scl = data.get("scale", {"x": 1, "y": 1, "z": 1})
	placement.scale = Vector3(scl.get("x", 1), scl.get("y", 1), scl.get("z", 1))
	
	placement.token_name = data.get("token_name", "")
	placement.is_player_controlled = data.get("is_player_controlled", false)
	placement.max_health = data.get("max_health", 100)
	placement.current_health = data.get("current_health", 100)
	placement.is_visible_to_players = data.get("is_visible_to_players", true)
	
	# Handle typed array conversion for status_effects
	var effects_data = data.get("status_effects", [])
	placement.status_effects.clear()
	for effect in effects_data:
		placement.status_effects.append(str(effect))
	
	placement.is_alive = data.get("is_alive", true)
	
	return placement
