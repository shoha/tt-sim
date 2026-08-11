class_name LevelEnvironmentManager

## Manages the WorldEnvironment node, environment presets, lighting, and lo-fi
## shader overrides for a playing level.
##
## Extracted from LevelPlayController to give it a single responsibility
## (environment & lighting) while LevelPlayController focuses on level
## loading, tokens, and network sync.

var _world_environment: WorldEnvironment = null
var _sun_light: DirectionalLight3D = null
var _map_environment_config: Dictionary = {}
var _map_sky_resource: Sky = null
var _original_light_energies: Dictionary = {}  # instance_id -> base energy
var _wind_materials: Dictionary = {}  # category (String) -> Array[ShaderMaterial]
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
	var lighting_config := GlbUtils.extract_lighting_config(root)

	var env_nodes: Array[Node] = []
	GlbUtils._find_world_environments(root, env_nodes)
	if env_nodes.is_empty():
		_map_sky_resource = null
		_map_environment_config = lighting_config.duplicate()
		return _map_environment_config

	var world_env := env_nodes[0] as WorldEnvironment
	var config := lighting_config.duplicate()
	if world_env and world_env.environment:
		var extracted := EnvironmentPresets.extract_from_environment(world_env.environment)
		for key in extracted:
			config[key] = extracted[key]
		if world_env.environment.sky:
			_map_sky_resource = world_env.environment.sky.duplicate()
			print("LevelEnvironmentManager: Extracted sky from map node '%s'" % world_env.name)
		else:
			_map_sky_resource = null
		print("LevelEnvironmentManager: Extracted environment from map node '%s'" % world_env.name)

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
# Foliage Sway
# ============================================================================


## Cache every wind-sway ShaderMaterial in a loaded map's tree, keyed by the
## WindFoliage category it was built for (tagged via set_meta("wind_category", ...)
## in WindFoliage._build_shader_material). Called once after map load, mirroring
## store_original_light_energies -- lets apply_foliage_overrides() re-tune live
## materials without re-walking or reloading the scene tree on every slider drag.
func store_wind_materials(node: Node) -> void:
	_wind_materials.clear()
	_collect_wind_materials(node)


func _collect_wind_materials(node: Node) -> void:
	if node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
		var mesh: Mesh = node.multimesh.mesh
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if material is ShaderMaterial and material.has_meta("wind_category"):
				var category: String = material.get_meta("wind_category")
				if not _wind_materials.has(category):
					_wind_materials[category] = []
				_wind_materials[category].append(material)
	for child in node.get_children():
		_collect_wind_materials(child)


## Re-tune every cached wind-sway material's speed/amplitude in place, with no
## map reload. overrides uses the same flat key shape as
## LevelData.foliage_overrides ("<category>_sway_speed" / "<category>_sway_amplitude").
func apply_foliage_overrides(overrides: Dictionary) -> void:
	for category in _wind_materials:
		var preset := WindFoliage.get_effective_preset(category, overrides)
		if preset.is_empty():
			continue
		for material in _wind_materials[category]:
			if is_instance_valid(material):
				material.set_shader_parameter("sway_speed", preset["sway_speed"])
				material.set_shader_parameter("sway_amplitude", preset["sway_amplitude"])


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

	(
		EnvironmentPresets
		. apply_to_world_environment(
			_world_environment,
			level_data.environment_preset,
			level_data.environment_overrides,
			_map_sky_resource,
			_map_environment_config,
		)
	)
	_push_water_ambient_reflection_uniform()

	# Create the default sun light if it doesn't exist, then configure it per
	# level_data.sun_overrides (auto/on/off + time of day).
	if not is_instance_valid(_sun_light):
		_sun_light = DirectionalLight3D.new()
		_sun_light.name = "LevelSunLight"
		_sun_light.shadow_enabled = true
		_sun_light.shadow_blur = 2.0
		# Leave directional_shadow_mode at its engine default (cascaded
		# PARALLEL_4_SPLITS). Explicitly forcing SHADOW_ORTHOGONAL (the
		# simplest, single-frustum mode) produced no visible shadows at all
		# in this project's camera setup -- confirmed by visual A/B test:
		# switching away from SHADOW_ORTHOGONAL is what made shadows appear,
		# most likely because the single-frustum fit degenerates against this
		# project's orthogonal Camera3D (see the "Near-plane culling fix" note
		# in game_map.gd for its unusual near=0.001/far=1000 range).
		#
		# Godot's engine defaults for the biases (shadow_bias=0.1,
		# shadow_normal_bias=2.0) are tuned for room/building-scale geometry.
		# Tokens are small (well under 1 unit tall), so the default
		# normal_bias pushes the shadow-map lookup far enough off the surface
		# that small props can lose their shadow entirely ("peter-panning").
		# These smaller values keep shadows attached to small objects while
		# still avoiding shadow acne on the terrain.
		_sun_light.shadow_bias = 0.02
		_sun_light.shadow_normal_bias = 0.1
		world_viewport.add_child(_sun_light)
	_configure_sun_light(level_data.sun_overrides)

	# Apply lo-fi shader overrides. Unlike WorldEnvironment/sun light (freshly
	# recomputed every load regardless of override emptiness) and weather
	# (a fresh WeatherRenderer every load), the lo-fi ShaderMaterial is a
	# single persistent resource reused for this GameMap's whole lifetime --
	# so a level with no overrides must still get a full reset to defaults,
	# not a skipped call that leaves a previous level's live values in place.
	if is_instance_valid(_game_map):
		var lofi_config := Constants.LOFI_DEFAULTS.duplicate()
		lofi_config.merge(level_data.lofi_overrides, true)
		_game_map.apply_lofi_overrides(lofi_config)

	if level_data.environment_preset != "":
		print(
			(
				"LevelEnvironmentManager: Applied environment preset '%s'"
				% level_data.environment_preset
			)
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
		_push_water_ambient_reflection_uniform()
	else:
		push_warning("LevelEnvironmentManager: WorldEnvironment is null")


## Apply sun overrides to the live sun light (real-time editing). The light
## must already exist -- created by apply_level_environment() at load time.
func apply_sun_overrides(overrides: Dictionary) -> void:
	if not is_instance_valid(_sun_light):
		push_warning("LevelEnvironmentManager: sun light is null")
		return
	_configure_sun_light(overrides)


## Resolve mode ("auto" | "on" | "off") against whether the map brought its own
## lights, then show/hide and (if visible) re-angle the sun light.
func _configure_sun_light(overrides: Dictionary) -> void:
	var mode: String = overrides.get("mode", "auto")
	var map_has_lights := not _original_light_energies.is_empty()
	var enabled: bool = mode == "on" or (mode == "auto" and not map_has_lights)
	_sun_light.visible = enabled
	if enabled:
		var time_of_day: float = overrides.get("time_of_day", DefaultSun.DEFAULT_TIME_OF_DAY)
		DefaultSun.configure_directional_light(_sun_light, time_of_day)


# ============================================================================
# Accessors
# ============================================================================


func get_world_environment() -> WorldEnvironment:
	return _world_environment


## Force real-time screen-space reflections on for the "realistic" Water Style
## preset when Water Quality is at its highest tier -- the one Water Quality
## knob that isn't a shader uniform (Environment.ssr_enabled lives on the live
## WorldEnvironment, not on the water material). Never turns SSR off on behalf
## of a lower tier/style -- if the resolved environment preset/overrides
## already enabled it for their own reasons, that choice is left alone.
func apply_water_quality_ssr_override(water_style: String, ssr_quality_enabled: bool) -> void:
	if not is_instance_valid(_world_environment) or not _world_environment.environment:
		return
	if water_style == "realistic" and ssr_quality_enabled:
		_world_environment.environment.ssr_enabled = true


## Push the level's actual ambient/sky color to the water shader's
## water_ambient_reflection_color global uniform, so the "realistic" Water
## Style's fresnel sky-blend (see sky_blend_strength in water.gdshader) tracks
## the current level's atmosphere instead of a hardcoded default.
func _push_water_ambient_reflection_uniform() -> void:
	if not is_instance_valid(_world_environment) or not _world_environment.environment:
		return
	var env := _world_environment.environment
	var ambient := env.ambient_light_color * env.ambient_light_energy
	RenderingServer.global_shader_parameter_set(
		"water_ambient_reflection_color", Vector3(ambient.r, ambient.g, ambient.b)
	)


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
	_wind_materials.clear()
	if is_instance_valid(_world_environment):
		_world_environment.queue_free()
		_world_environment = null
	if is_instance_valid(_sun_light):
		_sun_light.queue_free()
		_sun_light = null
	_map_environment_config = {}
	_map_sky_resource = null
