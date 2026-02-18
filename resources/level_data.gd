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

## Scale & Measurement
@export_group("Scale")
## Size of one grid cell in world units (meters), as measured in the loaded scene.
## Default 1.524 = 5 feet, the standard D&D/Pathfinder grid square.
## For maps authored at "1 unit = 1 square" convention, set to 1.0.
@export var grid_cell_size: float = 1.524
## Unit label for distance display (e.g., "ft", "m", "in", "sq")
@export var display_unit: String = "ft"
## How many display units each grid cell represents (e.g., 5.0 for "5 ft per square")
@export var display_unit_per_cell: float = 5.0

## Grid overlay & snapping
@export_group("Grid")
## Whether the grid overlay is visible by default when this level loads.
## Players can locally override with the G key.
@export var grid_visible: bool = false
## When true, dragged tokens snap to grid cell centers. GM-controlled.
@export var grid_snap_enabled: bool = true
## Auto-show the grid overlay while the measure tool is active.
@export var grid_show_on_measure: bool = true
## Auto-show the grid overlay while dragging a token.
@export var grid_show_on_drag: bool = true
## Grid line color (including alpha for opacity).
@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.0)
## XZ offset for aligning the grid to imported map geometry.
@export var grid_origin: Vector2 = Vector2.ZERO
## Grid type — currently only "square" is supported.
## Reserved for future hex support: "hex_flat", "hex_pointy".
@export var grid_type: String = "square"

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
	new_level.grid_cell_size = grid_cell_size
	new_level.display_unit = display_unit
	new_level.display_unit_per_cell = display_unit_per_cell
	new_level.grid_visible = grid_visible
	new_level.grid_snap_enabled = grid_snap_enabled
	new_level.grid_show_on_measure = grid_show_on_measure
	new_level.grid_show_on_drag = grid_show_on_drag
	new_level.grid_color = grid_color
	new_level.grid_origin = grid_origin
	new_level.grid_type = grid_type

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
		"grid_cell_size": grid_cell_size,
		"display_unit": display_unit,
		"display_unit_per_cell": display_unit_per_cell,
		"grid_visible": grid_visible,
		"grid_snap_enabled": grid_snap_enabled,
		"grid_show_on_measure": grid_show_on_measure,
		"grid_show_on_drag": grid_show_on_drag,
		"grid_color": SerializationUtils.color_to_dict(grid_color),
		"grid_origin": {"x": grid_origin.x, "y": grid_origin.y},
		"grid_type": grid_type,
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
	var lofi_raw = data.get("lofi_overrides", {})
	level.lofi_overrides = lofi_raw.duplicate() if lofi_raw is Dictionary else {}

	level.grid_cell_size = data.get("grid_cell_size", 1.524)
	level.display_unit = data.get("display_unit", "ft")
	level.display_unit_per_cell = data.get("display_unit_per_cell", 5.0)
	level.grid_visible = data.get("grid_visible", false)
	level.grid_snap_enabled = data.get("grid_snap_enabled", true)
	level.grid_show_on_measure = data.get("grid_show_on_measure", true)
	level.grid_show_on_drag = data.get("grid_show_on_drag", true)
	var gc = data.get("grid_color", {})
	if gc is Dictionary and not gc.is_empty():
		level.grid_color = SerializationUtils.dict_to_color(gc, Color(1.0, 1.0, 1.0, 0.0))
	var go = data.get("grid_origin", {})
	if go is Dictionary and not go.is_empty():
		level.grid_origin = Vector2(go.get("x", 0.0), go.get("y", 0.0))
	level.grid_type = data.get("grid_type", "square")

	level.token_placements.clear()
	var placements_data = data.get("token_placements", [])
	for placement_data in placements_data:
		if placement_data is Dictionary:
			level.token_placements.append(TokenPlacement.from_dict(placement_data))

	return level
