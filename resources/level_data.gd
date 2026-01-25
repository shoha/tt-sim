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
@export var map_glb_path: String = ""
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
	new_level.map_glb_path = map_glb_path
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

	if map_glb_path == "":
		errors.append("Map GLB file is required")
	elif not ResourceLoader.exists(map_glb_path) and not FileAccess.file_exists(map_glb_path):
		errors.append("Map file does not exist: " + map_glb_path)

	for i in range(token_placements.size()):
		var placement = token_placements[i]
		if placement.pokemon_number == "":
			errors.append("Token %d has no Pokemon assigned" % (i + 1))

	return errors
