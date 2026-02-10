class_name LevelEnvironmentManager

## Manages the WorldEnvironment node, environment presets, lighting, and lo-fi
## shader overrides for a playing level.
##
## Extracted from LevelPlayController to give it a single responsibility
## (environment & lighting) while LevelPlayController focuses on level
## loading, tokens, and network sync.

var _world_environment: WorldEnvironment = null
var _map_environment_config: Dictionary = {}
var _map_sky_resource: Sky = null
var _original_light_energies: Dictionary = {}  # instance_id -> base energy
var _game_map: Node = null  # GameMap reference (for viewport & lo-fi access)


func setup(game_map: Node) -> void:
	_game_map = game_map


# ============================================================================
# Map Environment Extraction
# ============================================================================


## Extract environment settings from any embedded WorldEnvironment nodes in a
## loaded map scene, then strip the nodes so they don't conflict with the
## programmatic LevelEnvironment.  Returns the extracted config dictionary
## (empty if the map had no WorldEnvironment).
func extract_and_strip_map_environment(root: Node3D) -> Dictionary:
	var env_nodes: Array[Node] = []
	GlbUtils._find_world_environments(root, env_nodes)
	if env_nodes.is_empty():
		_map_sky_resource = null
		_map_environment_config = {}
		return {}

	var world_env := env_nodes[0] as WorldEnvironment
	var config := {}
	if world_env and world_env.environment:
		config = EnvironmentPresets.extract_from_environment(world_env.environment)
		if world_env.environment.sky:
			_map_sky_resource = world_env.environment.sky.duplicate()
			print("LevelEnvironmentManager: Extracted sky from map node '%s'" % world_env.name)
		else:
			_map_sky_resource = null
		print(
			"LevelEnvironmentManager: Extracted environment from map node '%s'" % world_env.name
		)

	GlbUtils.strip_world_environments(root)
	_map_environment_config = config
	return config


# ============================================================================
# Light Intensity
# ============================================================================


## Store the original light energies from a node tree so we can scale them
## later.  Called once after the map loads so intensity editing doesn't compound.
func store_original_light_energies(node: Node) -> void:
	_original_light_energies.clear()
	_collect_light_energies(node)


func _collect_light_energies(node: Node) -> void:
	if node is Light3D:
		_original_light_energies[node.get_instance_id()] = node.light_energy
	for child in node.get_children():
		_collect_light_energies(child)


## Apply a light intensity scale to all lights in the loaded map.
func apply_light_intensity_scale(intensity_scale: float, level_data: LevelData = null) -> void:
	for instance_id in _original_light_energies:
		var light = instance_from_id(instance_id)
		if is_instance_valid(light) and light is Light3D:
			light.light_energy = _original_light_energies[instance_id] * intensity_scale
	if level_data:
		level_data.light_intensity_scale = intensity_scale


# ============================================================================
# Environment Application
# ============================================================================


## Apply environment settings from level data.
## Map defaults are passed through as a layer — when preset is ""
## (no explicit choice), the map's embedded environment is used as the base.
func apply_level_environment(level_data: LevelData, world_viewport: Node) -> void:
	# Create WorldEnvironment if it doesn't exist
	if not is_instance_valid(_world_environment):
		_world_environment = WorldEnvironment.new()
		_world_environment.name = "LevelEnvironment"
		world_viewport.add_child(_world_environment)

	EnvironmentPresets.apply_to_world_environment(
		_world_environment,
		level_data.environment_preset,
		level_data.environment_overrides,
		_map_sky_resource,
		_map_environment_config,
	)

	# Apply lo-fi shader overrides if any are set
	if level_data.lofi_overrides.size() > 0 and is_instance_valid(_game_map):
		_game_map.apply_lofi_overrides(level_data.lofi_overrides)

	if level_data.environment_preset != "":
		print(
			"LevelEnvironmentManager: Applied environment preset '%s'"
			% level_data.environment_preset
		)
	elif not _map_environment_config.is_empty():
		print("LevelEnvironmentManager: Applied map default environment")
	else:
		print("LevelEnvironmentManager: Applied default environment")


## Apply environment settings to the live WorldEnvironment.
func apply_environment_settings(preset: String, overrides: Dictionary) -> void:
	if is_instance_valid(_world_environment):
		EnvironmentPresets.apply_to_world_environment(
			_world_environment, preset, overrides, _map_sky_resource, _map_environment_config
		)
	else:
		push_warning("LevelEnvironmentManager: WorldEnvironment is null")


# ============================================================================
# Accessors
# ============================================================================


func get_world_environment() -> WorldEnvironment:
	return _world_environment


func get_map_environment_config() -> Dictionary:
	return _map_environment_config


func get_map_sky_resource() -> Sky:
	return _map_sky_resource


# ============================================================================
# Cleanup
# ============================================================================


## Clear environment state (called when level is unloaded).
func clear() -> void:
	_original_light_energies.clear()
	if is_instance_valid(_world_environment):
		_world_environment.queue_free()
		_world_environment = null
	_map_environment_config = {}
	_map_sky_resource = null
