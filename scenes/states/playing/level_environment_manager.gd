class_name LevelEnvironmentManager

## Manages the WorldEnvironment node, environment presets, lighting, and lo-fi
## shader overrides for a playing level.
##
## Extracted from LevelPlayController to give it a single responsibility
## (environment & lighting) while LevelPlayController focuses on level
## loading, tokens, and network sync.

## Distance (world units) beyond which the sun stops casting shadows. Left at Godot's
## own default deliberately: tightening it was MEASURED and does nothing on a map of
## this scale.
##
## Swept 100.0 / 50.0 / 30.0 on the dense forest map at 1920x1080 with vsync off and a
## deterministic camera pose, normalising each run against a "foliage hidden" reference
## sample to cancel the GPU clock drift that makes cross-run absolute times unusable
## (see docs/superpowers/specs for the measurement method). Normalised foliage cost came
## out at 2.47 / 2.44 / 2.46 -- identical within noise -- and shadow-pass primitives were
## byte-identical at 15,586,440 for all three values. Every shadow caster on that map is
## already inside 30 units, so a shorter cascade distance excludes nothing.
##
## Kept as an explicit named constant rather than reverted to an implicit engine default
## so the next person does not re-investigate this. It would only become a lever for a
## map substantially larger than the camera's visible extent, and note the extent scales
## with camera.size (max zoom 20), so any future value must cover the zoomed-out view,
## not just the map bounds.
const SUN_SHADOW_MAX_DISTANCE: float = 100.0

## Field of view Godot uses to draw the sky behind the map. The map camera is
## orthographic, and Godot draws any sky behind an orthographic camera as if the
## camera were a wide-angle perspective one, so a panorama shows up as a stretched
## fisheye horizon beyond the map edge (the old gradients had the same geometry but
## no features to reveal it). Every pixel of an orthographic camera shares one view
## direction, so the honest background is the sky sampled in that direction: a
## near-zero field of view gives exactly that, a flat tone from the sky's ground
## band. Lighting and reflections come from the baked radiance map and are
## unaffected. Checked live on 2026-09-16: 2 degrees reads as a soft flat backdrop.
const SKY_ORTHO_FOV_DEG: float = 2.0

## Fraction of the map's own extent added on each side of the reflection probe box, so
## reflections do not cut off exactly at the last mesh.
const PROBE_MARGIN_FACTOR: float = 0.1
## Floor on the probe box's height. A perfectly flat map has zero Y extent and a probe
## with a zero-height box captures nothing at all.
##
## On the deciduous map this floor is what actually sets the height: the terrain's own
## relief is under ~3.3 units across 50x50, so the box comes out 60 x 4 x 60 -- the
## terrain sits inside it, the canopy does not. That is the conservative choice, kept
## deliberately. The alternatives were measured on 2026-09-21 (deciduous, 1920x1080,
## vsync off, sun off, camera at the default pose); don't re-derive them:
##
## - No probe at all: 206/206/204 fps.
## - This shallow box:  196/196/200 fps.
## - Canopy-height box (60 x 30 x 60): 195 fps.
##
## So the ~4% is the per-pixel probe lookup, NOT the volume -- box height is very nearly
## free. The reason to stay shallow is visual, not performance: a canopy-height box pulls
## the foliage into the probe's influence and darkens it substantially, because the probe
## captures the dim forest interior rather than the bright sky. That reads as a plausible
## forest but it is a style change, not a polish, so it wants a human decision rather than
## a magic number here. Raising this constant is all it takes if that look is wanted.
##
## If the probe ever reads too flat, the step up is VoxelGI, not SDFGI: SDFGI centres its
## cascades on the camera, and _update_camera_offset() drives the camera away in
## proportion to camera.size, which is exactly what made it cascade-band across the ground
## (see docs and the sdfgi_enabled default in Constants). VoxelGI is world-anchored like
## this probe and supports dynamic lights, which matters because the sun is user-draggable
## at runtime -- LightmapGI cannot follow that, and cannot bake user-supplied GLBs loaded
## from user:// anyway. VoxelGI's cost here is unmeasured.
const PROBE_MIN_HEIGHT: float = 4.0

var _world_environment: WorldEnvironment = null
var _sun_light: DirectionalLight3D = null
var _map_environment_config: Dictionary = {}
var _map_sky_resource: Sky = null
var _original_light_energies: Dictionary = {}  # instance_id -> base energy
var _wind_materials: Dictionary = {}  # category (String) -> Array[ShaderMaterial]
var _game_map: Node = null  # GameMap reference (for viewport & lo-fi access)
var _current_sky_key: String = ""  # sky_preset of the last resolved environment
var _sun_azimuth_deg: float = 0.0  # azimuth of the last applied SunSettings
var _reflection_probe: ReflectionProbe = null


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
				if material not in _wind_materials[category]:
					_wind_materials[category].append(material)
	for child in node.get_children():
		_collect_wind_materials(child)


## Re-tune every cached wind-sway material's speed/amplitude in place, with no
## map reload. overrides uses the same flat key shape as
## LevelData.foliage.to_dict() ("<category>_sway_speed" / "<category>_sway_amplitude").
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
# Reflection probe
# ============================================================================


## Union of every MeshInstance3D's world-space AABB under `root`, or a zero-size AABB
## when the subtree holds no geometry.
##
## Scattered foliage (MultiMeshInstance3D) is deliberately NOT included. Headless stores
## no MultiMesh instance data at all -- verified 2026-09-21: `buffer` is empty and
## `get_instance_transform()` reads back identity, so both the node's `get_aabb()` and
## any transform-derived box are unavailable in CI, and bounds built from them would
## differ silently between headless and a real renderer. Excluding the canopy costs
## nothing that exists today: geometry outside the probe box simply keeps the sky
## reflection it already gets, and the terrain -- the surface this is meant to improve --
## is always inside. This also matches CameraController's own map-bounds walk.
static func compute_map_bounds(root: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh_inst: MeshInstance3D in _mesh_instances(root):
		var world_aabb := mesh_inst.global_transform * mesh_inst.mesh.get_aabb()
		bounds = world_aabb if not found else bounds.merge(world_aabb)
		found = true
	return bounds


static func _mesh_instances(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for child in node.get_children():
		_mesh_instances(child, out)
	return out


## The world-space box a reflection probe should cover for a map with these bounds:
## the map's own bounds plus a proportional margin, floored to PROBE_MIN_HEIGHT so a
## flat map still encloses a volume. Kept separate from the node so it can be reasoned
## about (and tested) without a scene.
static func compute_probe_box(map_bounds: AABB) -> AABB:
	var margin := map_bounds.size * PROBE_MARGIN_FACTOR
	var box := AABB(map_bounds.position - margin, map_bounds.size + margin * 2.0)
	if box.size.y < PROBE_MIN_HEIGHT:
		box.position.y -= (PROBE_MIN_HEIGHT - box.size.y) * 0.5
		box.size.y = PROBE_MIN_HEIGHT
	return box


## Create (or re-size) the level's ReflectionProbe over the currently loaded map.
##
## Every environment preset asks for REFLECTION_SOURCE_SKY, so without a probe anything
## that cannot see open sky gets no environmental reflection at all. A probe is anchored
## in world space, unlike SDFGI's camera-centred cascades, so it is unaffected by the
## orthographic camera moving away as camera.size grows.
##
## Does nothing when the map has no geometry to bound. Idempotent: re-applying (say on a
## preset change) re-sizes the existing probe rather than stacking a second one.
func apply_reflection_probe(world_viewport: Node) -> void:
	if not is_instance_valid(_game_map) or not ("map_container" in _game_map):
		return
	var map_container: Node = _game_map.map_container
	if map_container == null:
		return
	var bounds := compute_map_bounds(map_container)
	if bounds.size == Vector3.ZERO:
		return
	if not is_instance_valid(_reflection_probe):
		_reflection_probe = ReflectionProbe.new()
		_reflection_probe.name = "LevelReflectionProbe"
		world_viewport.add_child(_reflection_probe)
	configure_reflection_probe(_reflection_probe, bounds)


## Size and place a ReflectionProbe over a map with these bounds.
##
## UPDATE_ONCE, not UPDATE_ALWAYS: the map is static once loaded, so the cubemap is
## captured a single time at level load rather than re-rendered per frame -- that is
## what keeps this affordable. interior stays false so the sky still reaches the
## capture; it is the main ambient source in most outdoor presets.
static func configure_reflection_probe(probe: ReflectionProbe, map_bounds: AABB) -> void:
	var box := compute_probe_box(map_bounds)
	probe.size = box.size
	probe.position = box.get_center()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.interior = false


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
	_remember_sky_key(level_data.environment_preset, level_data.environment_overrides)
	_push_water_ambient_reflection_uniform()

	var rendering_toggles_config := ConfigFile.new()
	var err := rendering_toggles_config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning(
			"LevelEnvironmentManager: failed to load settings for rendering toggles: %d" % err
		)
	apply_rendering_toggles(
		rendering_toggles_config.get_value(
			"graphics", "ssao_enabled", Constants.RENDERING_TOGGLES_DEFAULTS["ssao_enabled"]
		),
		rendering_toggles_config.get_value(
			"graphics", "ssr_enabled", Constants.RENDERING_TOGGLES_DEFAULTS["ssr_enabled"]
		),
		rendering_toggles_config.get_value(
			"graphics", "sdfgi_enabled", Constants.RENDERING_TOGGLES_DEFAULTS["sdfgi_enabled"]
		),
	)

	# Map geometry is already parented under MapContainer by this point (see
	# LevelPlayLoader._finalize_map_loading), so its bounds are measurable here.
	apply_reflection_probe(world_viewport)

	# Create the default sun light if it doesn't exist, then configure it per
	# level_data.visual_settings.sun (mode, direction, color, energy, shadows).
	if not is_instance_valid(_sun_light):
		_sun_light = DirectionalLight3D.new()
		_sun_light.name = "LevelSunLight"
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
		#
		# shadow_enabled, light_angular_distance, and shadow_opacity are NOT set
		# here -- they are per-level artistic settings written by
		# DefaultSun.apply() on every _configure_sun_light() call. The biases
		# below are engine tuning for this project's object scale and stay fixed.
		_sun_light.shadow_bias = 0.02
		_sun_light.shadow_normal_bias = 0.1
		_sun_light.directional_shadow_max_distance = SUN_SHADOW_MAX_DISTANCE
		world_viewport.add_child(_sun_light)
	_configure_sun_light(level_data.visual_settings.sun)
	_sun_azimuth_deg = level_data.visual_settings.sun.azimuth_degrees
	_sync_sky_view()

	# Apply lo-fi shader parameters. Unlike WorldEnvironment/sun light (freshly
	# recomputed every load) and weather (a fresh WeatherRenderer every load),
	# the lo-fi ShaderMaterial is a single persistent resource reused for this
	# GameMap's whole lifetime, so every parameter must be written on every load
	# or a previous level's value survives.
	#
	# LofiSettings.to_dict() is already complete over the seven level-editable
	# parameters, so the merge is not there to fill gaps in it. It is there for
	# the three parameters LofiSettings deliberately does not model --
	# color_tint, grain_speed and grain_scale -- which are not level-editable
	# and would otherwise keep whatever the previous level left on the material.
	if is_instance_valid(_game_map):
		var lofi_config := Constants.LOFI_DEFAULTS.duplicate()
		lofi_config.merge(level_data.lofi.to_dict(), true)
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
		_remember_sky_key(preset, overrides)
		_sync_sky_view()
	else:
		push_warning("LevelEnvironmentManager: WorldEnvironment is null")


## Apply sun settings to the live sun light (real-time editing). The light must
## already exist -- created by apply_level_environment() at load time.
func apply_sun_settings(settings: SunSettings) -> void:
	if not is_instance_valid(_sun_light):
		push_warning("LevelEnvironmentManager: sun light is null")
		return
	_configure_sun_light(settings)
	_sun_azimuth_deg = settings.azimuth_degrees
	_sync_sky_view()


## Resolve mode ("auto" | "on" | "off") against whether the map brought its own
## lights, then show/hide and (if visible) re-apply the full sun configuration.
func _configure_sun_light(settings: SunSettings) -> void:
	var map_has_lights := not _original_light_energies.is_empty()
	var enabled: bool = settings.mode == "on" or (settings.mode == "auto" and not map_has_lights)
	_sun_light.visible = enabled
	if enabled:
		DefaultSun.apply(_sun_light, settings)


## The sky key the resolved config selected, so rotation can be recomputed when
## only the sun changes.
func _remember_sky_key(preset: String, overrides: Dictionary) -> void:
	var config := EnvironmentPresets.get_environment_config(
		preset, overrides, _map_environment_config
	)
	_current_sky_key = String(config.get("sky_preset", ""))


## An HDRI sky turns so its brightest column faces the sun's azimuth (every sun
## mode, so toggling the sun never snaps the sky); gradients stay at zero. The
## sky is also drawn at SKY_ORTHO_FOV_DEG here because apply_to_world_environment
## may have just created the Environment resource.
func _sync_sky_view() -> void:
	if not is_instance_valid(_world_environment) or not _world_environment.environment:
		return
	var environment := _world_environment.environment
	environment.sky_rotation = EnvironmentPresets.sky_rotation_for(
		_sun_azimuth_deg, _current_sky_key
	)
	environment.sky_custom_fov = SKY_ORTHO_FOV_DEG


# ============================================================================
# Accessors
# ============================================================================


func get_world_environment() -> WorldEnvironment:
	return _world_environment


## Return the level's sun light (may be null before a level is loaded).
func get_sun_light() -> DirectionalLight3D:
	return _sun_light


## Write the three global rendering-quality toggles (SSAO, SSR, SDFGI) onto the
## live WorldEnvironment. Takes explicit values rather than reading
## settings.cfg itself, so both call sites can supply the right source: the
## level-load path (apply_level_environment()) reads the saved config once,
## while a live Settings-menu change passes the checkboxes' current in-memory
## state directly -- reading from disk here would show a stale (not-yet-saved)
## value on a live toggle.
func apply_rendering_toggles(ssao_enabled: bool, ssr_enabled: bool, sdfgi_enabled: bool) -> void:
	if not is_instance_valid(_world_environment) or not _world_environment.environment:
		return
	var env := _world_environment.environment
	env.ssao_enabled = ssao_enabled
	env.ssr_enabled = ssr_enabled
	env.sdfgi_enabled = sdfgi_enabled


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
	if is_instance_valid(_reflection_probe):
		_reflection_probe.queue_free()
		_reflection_probe = null
	_map_environment_config = {}
	_map_sky_resource = null
	_current_sky_key = ""
	_sun_azimuth_deg = 0.0
