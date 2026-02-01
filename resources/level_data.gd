extends Resource
class_name LevelData

## Stores all data for a game level
## Includes the map model and all token placements

## Level metadata
@export var level_name: String = "Untitled Level"
@export var level_description: String = ""
@export var author: String = ""
@export var created_at: int = 0
@export var modified_at: int = 0

## Map configuration
@export_group("Map")
@export var map_path: String = ""
@export var map_scale: Vector3 = Vector3.ONE
@export var map_offset: Vector3 = Vector3.ZERO

## Token placements
@export_group("Tokens")
@export var token_placements: Array[TokenPlacement] = []


func _init() -> void:
	created_at = int(Time.get_unix_time_from_system())
	modified_at = created_at


## Add a new token placement
func add_token_placement(placement: TokenPlacement) -> void:
	token_placements.append(placement)
	_update_modified_time()


## Remove a token placement by ID
func remove_token_placement(placement_id: String) -> bool:
	for i in range(token_placements.size()):
		if token_placements[i].placement_id == placement_id:
			token_placements.remove_at(i)
			_update_modified_time()
			return true
	return false


## Get a token placement by ID
func get_token_placement(placement_id: String) -> TokenPlacement:
	for placement in token_placements:
		if placement.placement_id == placement_id:
			return placement
	return null


## Update a token placement
func update_token_placement(placement: TokenPlacement) -> void:
	for i in range(token_placements.size()):
		if token_placements[i].placement_id == placement.placement_id:
			token_placements[i] = placement
			_update_modified_time()
			return


## Clear all token placements
func clear_tokens() -> void:
	token_placements.clear()
	_update_modified_time()


func _update_modified_time() -> void:
	modified_at = int(Time.get_unix_time_from_system())


## Create a duplicate of this level data
func duplicate_level() -> LevelData:
	var new_level = LevelData.new()
	new_level.level_name = level_name + " (Copy)"
	new_level.level_description = level_description
	new_level.author = author
	new_level.map_path = map_path
	new_level.map_scale = map_scale
	new_level.map_offset = map_offset

	for placement in token_placements:
		var new_placement = placement.duplicate()
		new_placement.placement_id = TokenPlacement._generate_id()
		new_level.token_placements.append(new_placement)

	return new_level


## Validate the level data
func validate() -> Array[String]:
	var errors: Array[String] = []

	if level_name.strip_edges() == "":
		errors.append("Level name is required")

	if map_path == "":
		errors.append("Map file is required")
	elif not ResourceLoader.exists(map_path) and not FileAccess.file_exists(map_path):
		errors.append("Map file does not exist: " + map_path)

	for i in range(token_placements.size()):
		var placement = token_placements[i]
		if placement.pack_id == "" or placement.asset_id == "":
			errors.append("Token %d has no asset assigned" % (i + 1))

	return errors


## Convert to dictionary for network transmission
func to_dict() -> Dictionary:
	var placements_array: Array[Dictionary] = []
	for placement in token_placements:
		placements_array.append(placement.to_dict())
	
	return {
		"level_name": level_name,
		"level_description": level_description,
		"author": author,
		"created_at": created_at,
		"modified_at": modified_at,
		"map_path": map_path,
		"map_scale": {"x": map_scale.x, "y": map_scale.y, "z": map_scale.z},
		"map_offset": {"x": map_offset.x, "y": map_offset.y, "z": map_offset.z},
		"token_placements": placements_array,
	}


## Create from dictionary (for network reception)
static func from_dict(data: Dictionary) -> LevelData:
	var level = LevelData.new()
	level.level_name = data.get("level_name", "Untitled Level")
	level.level_description = data.get("level_description", "")
	level.author = data.get("author", "")
	level.created_at = data.get("created_at", 0)
	level.modified_at = data.get("modified_at", 0)
	level.map_path = data.get("map_path", "")
	
	var scale_data = data.get("map_scale", {"x": 1, "y": 1, "z": 1})
	level.map_scale = Vector3(scale_data.get("x", 1), scale_data.get("y", 1), scale_data.get("z", 1))
	
	var offset_data = data.get("map_offset", {"x": 0, "y": 0, "z": 0})
	level.map_offset = Vector3(offset_data.get("x", 0), offset_data.get("y", 0), offset_data.get("z", 0))
	
	level.token_placements.clear()
	var placements_data = data.get("token_placements", [])
	for placement_data in placements_data:
		level.token_placements.append(TokenPlacement.from_dict(placement_data))
	
	return level
