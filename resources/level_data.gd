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

## Level storage location (folder name within user://levels/)
## Empty string means the level hasn't been saved yet
@export var level_folder: String = ""

## Map configuration
@export_group("Map")
## For user:// levels: relative path within level folder (e.g., "map.glb")
## For legacy res:// levels: full path (e.g., "res://assets/models/maps/map.glb")
@export var map_path: String = ""
@export var map_scale: Vector3 = Vector3.ONE
@export var map_offset: Vector3 = Vector3.ZERO

## Lighting configuration
@export_group("Lighting")
## Multiplier for all light intensities in the map's GLB file.
## Use 1.0 for GLBs exported with "Unitless" lighting mode in Blender.
## Use lower values (0.001 - 0.01) for GLBs exported with "Standard" lighting mode.
@export var light_intensity_scale: float = 1.0

## Environment configuration
@export_group("Environment")
## Environment preset name (e.g., "dungeon_dark", "outdoor_day", "tavern")
## Empty string means "use map defaults if available, otherwise PROPERTY_DEFAULTS".
## See EnvironmentPresets for available presets.
@export var environment_preset: String = ""
## Optional overrides for specific environment properties
## Keys should match EnvironmentPresets property names (e.g., "ambient_light_energy", "fog_density")
## Colors should be Color objects or hex strings like "#ff0000"
@export var environment_overrides: Dictionary = {}

## Visual Effects (lo-fi shader)
@export_group("Effects")
## Optional overrides for lo-fi post-processing shader parameters
## Keys: "pixelation", "saturation", "color_levels", "dither_strength",
##       "vignette_strength", "vignette_radius", "grain_intensity"
## Empty dictionary uses defaults from the scene/shader
@export var lofi_overrides: Dictionary = {}

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


## Get the absolute path to the map file
## Handles both user:// (folder-based) and res:// (legacy) paths
func get_absolute_map_path() -> String:
	if map_path == "":
		return ""

	# If map_path is already absolute (res:// or user://), return as-is
	if map_path.begins_with("res://") or map_path.begins_with("user://"):
		return map_path

	# Otherwise, it's a relative path within the level folder
	if level_folder != "":
		return Paths.get_level_folder(level_folder) + map_path

	# No level folder set - can't resolve relative path
	return ""


## Check if this level uses the new folder-based storage
func is_folder_based() -> bool:
	return level_folder != "" and not map_path.begins_with("res://")


## Create a duplicate of this level data
## Note: level_folder is NOT copied - duplicates need their own folder
func duplicate_level() -> LevelData:
	var new_level = LevelData.new()
	new_level.level_name = level_name + " (Copy)"
	new_level.level_description = level_description
	new_level.author = author
	new_level.level_folder = ""  # Duplicates need to be saved to a new folder
	new_level.map_path = map_path
	new_level.map_scale = map_scale
	new_level.map_offset = map_offset
	new_level.light_intensity_scale = light_intensity_scale
	new_level.environment_preset = environment_preset
	new_level.environment_overrides = environment_overrides.duplicate()
	new_level.lofi_overrides = lofi_overrides.duplicate()

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
	else:
		var absolute_path = get_absolute_map_path()
		if absolute_path == "":
			errors.append("Cannot resolve map path - level_folder may not be set")
		elif not _map_file_exists(absolute_path):
			errors.append("Map file does not exist: " + absolute_path)

	for i in range(token_placements.size()):
		var placement = token_placements[i]
		if placement.pack_id == "" or placement.asset_id == "":
			errors.append("Token %d has no asset assigned" % (i + 1))

	return errors


## Check if a map file exists (handles both res:// and user:// paths)
func _map_file_exists(path: String) -> bool:
	if path.begins_with("res://"):
		return ResourceLoader.exists(path)
	else:
		return FileAccess.file_exists(path)


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
		"level_folder": level_folder,
		"map_path": map_path,
		"map_scale": SerializationUtils.vec3_to_dict(map_scale),
		"map_offset": SerializationUtils.vec3_to_dict(map_offset),
		"light_intensity_scale": light_intensity_scale,
		"environment_preset": environment_preset,
		"environment_overrides": EnvironmentPresets.overrides_to_json(environment_overrides),
		"lofi_overrides": lofi_overrides.duplicate(),
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
	level.level_folder = data.get("level_folder", "")
	level.map_path = data.get("map_path", "")

	level.map_scale = SerializationUtils.dict_to_vec3(data.get("map_scale", {}), Vector3.ONE)
	level.map_offset = SerializationUtils.dict_to_vec3(data.get("map_offset", {}))

	level.light_intensity_scale = data.get("light_intensity_scale", 1.0)
	level.environment_preset = data.get("environment_preset", "")
	level.environment_overrides = EnvironmentPresets.overrides_from_json(
		data.get("environment_overrides", {})
	)
	level.lofi_overrides = data.get("lofi_overrides", {}).duplicate()

	level.token_placements.clear()
	var placements_data = data.get("token_placements", [])
	for placement_data in placements_data:
		level.token_placements.append(TokenPlacement.from_dict(placement_data))

	return level
